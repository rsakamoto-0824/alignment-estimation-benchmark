function [result, cells] = interactionTests(values, factors)
%INTERACTIONTESTS 質的変数の2つずつの組について、主効果と交互作用（二元配置の分散分析、F 検定）を調べる。
%   [result, cells] = alignest.stats.interactionTests(values, factors)
%   factors は構造体配列（name：質的変数の名前、levels：各点の水準の文字列。欠けは ""）。値が NaN の点・
%   どちらかの水準が欠けた点は、その組では使わない。水準が1つしかない変数は組にしない。
%   組 (A, B) ごとに、水準の 0/1 の列で次のモデルを当てはめる（水準の点数がそろっていなくてもよい）。
%   - 主効果：A を外したときの残差平方和の増え方（B は入れたまま。Type II）。B も同じ
%   - 交互作用：主効果だけのモデル（1 + A + B）に、A × B の列を足したときの残差平方和の減り方
%     （F = (RSS主効果 − RSS交互作用あり) / 自由度 ÷ (RSS交互作用あり / 残差の自由度)）
%   partialEta2 = 交互作用の平方和 /（交互作用の平方和 + RSS交互作用あり）（交互作用で説明できる割合）。
%   A と B が同じ分け方になる（例：Scan 方向と Shot 行の奇偶）、または水準の組に点の無いものが多く交互作用の
%   自由度が 0 になる組は、交互作用を調べられない（NaN、note に理由）。
%   result は組ごとの表（factorA・factorB・n・FA・pA・FB・pB・F・df・p・partialEta2・note）。
%   cells は組ごとの水準の組の平均（factorA・factorB・levelA・levelB・n・mean の表）を縦に並べた表（交互作用の図用）。
values = double(values(:));
nFactors = numel(factors);
usable = false(1, nFactors);
for k = 1:nFactors
    levels = string(factors(k).levels(:));
    usable(k) = numel(unique(levels(levels ~= "" & ~ismissing(levels) & isfinite(values)))) >= 2;
end
pairs = zeros(0, 2);
if nnz(usable) >= 2
    pairs = nchoosek(find(usable), 2);   % 変数が1つのときに nchoosek(数, 2) が組の数になるのを避ける
end
nPairs = size(pairs, 1);
[factorA, factorB, note] = deal(strings(nPairs, 1));
[n, FA, pA, FB, pB, F, df, p, partialEta2] = deal(nan(nPairs, 1));
cellParts = cell(nPairs, 1);
for k = 1:nPairs
    first = factors(pairs(k, 1));
    second = factors(pairs(k, 2));
    factorA(k) = first.name;
    factorB(k) = second.name;
    levelsA = string(first.levels(:));
    levelsB = string(second.levels(:));
    use = isfinite(values) & levelsA ~= "" & ~ismissing(levelsA) & levelsB ~= "" & ~ismissing(levelsB);
    y = values(use);
    [namesA, ~, codeA] = unique(levelsA(use));
    [namesB, ~, codeB] = unique(levelsB(use));
    n(k) = numel(y);
    cellParts{k} = cellMeans(first.name, second.name, namesA, namesB, codeA, codeB, y);
    if numel(namesA) < 2 || numel(namesB) < 2
        note(k) = "この組では水準が1つしか無いので調べられません。";
        continue
    end
    one = ones(numel(y), 1);
    dummyA = double(codeA == 2:numel(namesA));   % 基準の水準（1番目）以外の 0/1 の列
    dummyB = double(codeB == 2:numel(namesB));
    product = zeros(numel(y), size(dummyA, 2) * size(dummyB, 2));
    for a = 1:size(dummyA, 2)
        product(:, (a - 1) * size(dummyB, 2) + (1:size(dummyB, 2))) = dummyA(:, a) .* dummyB;
    end
    [rssMain, rankMain] = alignest.stats.residualSumOfSquares([one, dummyA, dummyB], y);
    [rssFull, rankFull] = alignest.stats.residualSumOfSquares([one, dummyA, dummyB, product], y);
    dfResidual = numel(y) - rankFull;
    dfMainResidual = numel(y) - rankMain;
    % 主効果（ほかの変数を入れたまま外す。Type II）
    [rssWithoutA, rankWithoutA] = alignest.stats.residualSumOfSquares([one, dummyB], y);
    [rssWithoutB, rankWithoutB] = alignest.stats.residualSumOfSquares([one, dummyA], y);
    [FA(k), pA(k)] = partialF(rssWithoutA - rssMain, rankMain - rankWithoutA, rssMain, dfMainResidual);
    [FB(k), pB(k)] = partialF(rssWithoutB - rssMain, rankMain - rankWithoutB, rssMain, dfMainResidual);
    df(k) = rankFull - rankMain;
    if df(k) == 0
        note(k) = "水準の組が重なる（同じ分け方になる、または点の無い組が多い）ので、交互作用を調べられません。";
        continue
    end
    [F(k), p(k)] = partialF(rssMain - rssFull, df(k), rssFull, dfResidual);
    interaction = max(rssMain - rssFull, 0);
    if interaction + rssFull > 0
        partialEta2(k) = interaction / (interaction + rssFull);
    end
end
result = table(factorA, factorB, n, FA, pA, FB, pB, F, df, p, partialEta2, note, 'VariableNames', ...
    ["factorA", "factorB", "n", "FA", "pA", "FB", "pB", "F", "df", "p", "partialEta2", "note"]);
if isempty(cellParts)
    cells = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
        'VariableNames', ["factorA", "factorB", "levelA", "levelB", "n", "mean"]);
else
    cells = vertcat(cellParts{:});
end
end

function [f, p] = partialF(increase, dfEffect, rss, dfResidual)
% 列を足した（外した）ときの残差平方和の差の F 検定
f = NaN;
p = NaN;
if dfEffect <= 0 || dfResidual <= 0
    return
end
if rss > 0
    f = max(increase, 0) / dfEffect / (rss / dfResidual);
elseif increase > 0
    f = Inf;
end
p = alignest.stats.upperTailF(f, dfEffect, dfResidual);
end

function cells = cellMeans(nameA, nameB, namesA, namesB, codeA, codeB, y)
% 水準の組ごとの点数と平均（点の無い組は入れない）
[groups, ~, index] = unique([codeA, codeB], 'rows');
counts = accumarray(index, 1);
means = accumarray(index, y) ./ counts;
m = size(groups, 1);
cells = table(repmat(string(nameA), m, 1), repmat(string(nameB), m, 1), namesA(groups(:, 1)), namesB(groups(:, 2)), ...
    counts, means, 'VariableNames', ["factorA", "factorB", "levelA", "levelB", "n", "mean"]);
end
