function result = anovaMainEffects(values, factors)
%ANOVAMAINEFFECTS 質的変数の水準によって値（残差）の平均が違うかを、分散分析（ANOVA）の F 検定で確かめる。
%   result = alignest.stats.anovaMainEffects(values, factors)
%   factors は構造体配列（name：質的変数の名前、levels：各点の水準の文字列。欠けは ""）。
%   変数ごとに2つの検定を出す。
%   - 一元配置：その変数だけで点を分けたときの F 検定。η² は全変動のうち水準の違いで説明できる割合。
%   - ほかの変数で調整：使える質的変数をすべて入れた主効果モデル（交互作用なし）から、その変数を外したときに
%     残差平方和がどれだけ増えるか（Type II）。Scan 方向と Shot 行の奇偶のように重なる変数を見分けるため。
%     ほかの変数と区別できない（同じ分け方になる）変数は自由度が 0 になり、NaN とする。
%   水準が1つしかない変数は検定しない（note に理由を入れる）。値が NaN の点・水準が欠けた点は使わない。
values = values(:);
nFactors = numel(factors);
names = strings(nFactors, 1);
nLevels = zeros(nFactors, 1);
levelSummary = strings(nFactors, 1);
oneWayF = nan(nFactors, 1);
df1 = nan(nFactors, 1);
df2 = nan(nFactors, 1);
oneWayP = nan(nFactors, 1);
etaSquared = nan(nFactors, 1);
adjustedF = nan(nFactors, 1);
adjustedDf = nan(nFactors, 1);
adjustedP = nan(nFactors, 1);
note = strings(nFactors, 1);
usable = false(nFactors, 1);
for k = 1:nFactors
    names(k) = factors(k).name;
    levels = string(factors(k).levels(:));
    select = isfinite(values) & levels ~= "" & ~ismissing(levels);
    [levelNames, ~, code] = unique(levels(select));
    nLevels(k) = numel(levelNames);
    if nLevels(k) < 2
        note(k) = "水準が1つしかないので検定しません。";
        continue
    end
    usable(k) = true;
    y = values(select);
    counts = accumarray(code, 1);
    means = accumarray(code, y) ./ counts;
    levelSummary(k) = summarizeLevels(levelNames, means, counts);
    between = sum(counts .* (means - mean(y)) .^ 2);
    within = sum((y - means(code)) .^ 2);
    df1(k) = nLevels(k) - 1;
    df2(k) = numel(y) - nLevels(k);
    if df2(k) > 0 && between + within > 0
        etaSquared(k) = between / (between + within);
        oneWayF(k) = ratio(between / df1(k), within / df2(k));
        oneWayP(k) = upperTailF(oneWayF(k), df1(k), df2(k));
    end
end

% ほかの変数で調整（使える変数がすべてそろった点で、主効果モデルを当てはめる）
used = find(usable);
if ~isempty(used)
    complete = isfinite(values);
    for k = used.'
        levels = string(factors(k).levels(:));
        complete = complete & levels ~= "" & ~ismissing(levels);
    end
    y = values(complete);
    blocks = cell(nFactors, 1);
    for k = used.'
        [~, ~, code] = unique(string(factors(k).levels(complete)));
        dummies = code == 2:max(code);   % 基準の水準（1番目）以外の 0/1 の列
        blocks{k} = double(dummies);
    end
    intercept = ones(numel(y), 1);
    [rssFull, rankFull] = residualSumOfSquares([intercept, blocks{used}], y);
    dfResidual = numel(y) - rankFull;
    for k = used.'
        others = setdiff(used, k);
        [rssDrop, rankDrop] = residualSumOfSquares([intercept, blocks{others}], y);
        adjustedDf(k) = rankFull - rankDrop;
        if adjustedDf(k) == 0
            note(k) = "ほかの質的変数と同じ分け方になるため、調整した検定はできません。";
            continue
        end
        if dfResidual > 0
            adjustedF(k) = ratio(max(rssDrop - rssFull, 0) / adjustedDf(k), rssFull / dfResidual);
            adjustedP(k) = upperTailF(adjustedF(k), adjustedDf(k), dfResidual);
        end
    end
end
result = table(names, nLevels, levelSummary, oneWayF, df1, df2, oneWayP, etaSquared, adjustedF, adjustedDf, ...
    adjustedP, note, 'VariableNames', ["factor", "nLevels", "levelSummary", "F", "df1", "df2", "p", "etaSquared", ...
    "adjustedF", "adjustedDf", "adjustedP", "note"]);
end

function value = ratio(numerator, denominator)
if denominator > 0
    value = numerator / denominator;
elseif numerator > 0
    value = Inf;
else
    value = NaN;
end
end

function p = upperTailF(f, dfNumerator, dfDenominator)
% F 分布の上側確率（正則化不完全ベータ関数で求める。Toolbox の fcdf を使わない）
if isnan(f)
    p = NaN;
elseif isinf(f)
    p = 0;
else
    p = betainc(dfDenominator / (dfDenominator + dfNumerator * f), dfDenominator / 2, dfNumerator / 2);
end
end

function [rss, rankValue] = residualSumOfSquares(design, y)
% 最小二乗の残差平方和と計画行列の階数（列の重なりは QR 分解の対角で判定する）
[q, r, ~] = qr(design, 0);
diagonal = abs(diag(r));
if isempty(diagonal)
    rankValue = 0;
else
    rankValue = nnz(diagonal > max(size(design)) * eps(max(diagonal)));
end
q = q(:, 1:rankValue);
residual = y - q * (q.' * y);
rss = sum(residual .^ 2);
end

function text = summarizeLevels(levelNames, means, counts)
% 水準を数の順（数でなければ文字の順）に並べ、「水準: 平均（点数）」にする
numbers = str2double(levelNames);
if all(isfinite(numbers))
    [~, order] = sort(numbers);
else
    order = (1:numel(levelNames)).';
end
parts = strings(numel(order), 1);
for k = 1:numel(order)
    index = order(k);
    parts(k) = sprintf("%s: %+.3f（%d 点）", levelNames(index), means(index), counts(index));
end
text = strjoin(parts, "、");
end
