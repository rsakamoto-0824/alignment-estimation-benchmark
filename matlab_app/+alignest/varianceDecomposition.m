function result = varianceDecomposition(points, options)
%VARIANCEDECOMPOSITION 値のばらつき（分散）を、Lot 間・Wafer 間・Shot 間・その他の分散成分に分ける（入れ子の分散分析）。
%   result = alignest.varianceDecomposition(points)
%   result = alignest.varianceDecomposition(points, valueColumns=["valueX", "valueY"], axisNames=["X", "Y"], ...
%       categories=棒の並び, useLot=true)
%   points：点ごとの表。category（棒を分ける名前。例：Operation・補正の段階）・lot（Lot の名前）・wafer（Wafer（計測）の名前）・
%   shot（Shot の番号）と、値の列（valueColumns。値の無い点は NaN）。
%   分け方：値 = 全体の平均 + Lot の効果 + Wafer の効果 + Shot の効果 + その他（Shot 内）と、上の段から Lot → Wafer → Shot
%   と入れ子にしたばらつきの和とみなし（分散の加法性：値の分散 = 段の分散成分の和）、段ごとの分散成分を入れ子の分散分析の
%   モーメント法で求める：段ごとの平方和（組の平均と、上の段の組の平均の差の2乗 × 点の数の和）を自由度で割った平均平方の
%   期待値が、その段と下の段の分散成分の和（係数つき。点の数がそろわないデータの係数）になることから、下の段から順に解く。
%   上の段の組の平均には下の段のばらつきも少し入るので、それを差し引いた分散成分になる（平方和を点の数で割っただけの値より
%   上の段が小さく、その他が大きくなる）。負になった段は 0 にする。その他 = Shot 内のばらつき（Mark ごとの違いと計測のばらつき。
%   Shot に1点しかないときは Shot 間と分けられないので 0）。
%   全体の分散 = 段の分散成分の和。段の 3σ = 3 × √（段の分散）（3σ は足しても全体の 3σ にならない）。
%   3σ の配分 = 全体の 3σ（3 × √全体の分散）× 段の分散の割合（足すと全体の 3σ になる。積み上げの棒に使う）。
%   useLot（省略時：Lot が2つ以上あれば true）が false なら Lot 間は分けない（その分は Wafer 間に入る）。
%   result.table：category・axis・component（段の名前）・variance（分散 [値の単位²]）・sigma3（段の 3σ [値の単位]）・
%   sigma3Share（3σ の配分 [値の単位]）・percent（全体の分散に対する割合 [%]）・n（点の数）。result.totals：category・axis・
%   variance・sigma3・n（全体）。result.components（分けた段の名前。上の段から）・categories・axes・useLot・kind（"nested"）
arguments
    points table
    options.valueColumns (1, :) string = ["valueX", "valueY"]
    options.axisNames (1, :) string = ["X", "Y"]
    options.categories (1, :) string = strings(1, 0)
    options.useLot = []
end
LEVEL_NAMES = ["Lot 間", "Wafer 間", "Shot 間"];
OTHER_NAME = "その他";
if numel(options.valueColumns) ~= numel(options.axisNames)
    error('alignest:varianceDecomposition', '値の列と軸の名前の数が違います。');
end
category = string(points.category);
lot = string(points.lot);
lot(ismissing(lot)) = "";
useLot = options.useLot;
if isempty(useLot)
    useLot = numel(unique(lot)) >= 2;
end
categories = options.categories;
if isempty(categories)
    categories = reshape(unique(category, 'stable'), 1, []);
end
% 入れ子の組のキー（上の段のキーを前に付けて、下の段は上の段の中で分ける）
keys = {lot, lot + "|" + string(points.wafer)};
keys{3} = keys{2} + "|" + string(points.shot);
used = [useLot, true, true];
components = [LEVEL_NAMES(used), OTHER_NAME];
nComponents = numel(components);
nRows = numel(categories) * numel(options.axisNames);
[rowCategory, rowAxis] = deal(strings(nRows, 1));
[variances, counts] = deal(nan(nRows, nComponents), zeros(nRows, 1));
r = 0;
for c = 1:numel(categories)
    for a = 1:numel(options.axisNames)
        r = r + 1;
        rowCategory(r) = categories(c);
        rowAxis(r) = options.axisNames(a);
        values = double(points.(options.valueColumns(a)));
        rows = category == categories(c) & isfinite(values);
        counts(r) = nnz(rows);
        if counts(r) == 0
            continue
        end
        variances(r, :) = levelVariances(values(rows), cellfun(@(key) key(rows), keys(used), 'UniformOutput', false));
    end
end
result = varianceTables(rowCategory, rowAxis, components, variances, counts);
result.categories = categories;
result.axes = options.axisNames;
result.useLot = logical(useLot);
result.kind = "nested";
end

function variances = levelVariances(values, keys)
% 入れ子の段（keys：上の段から、点ごとの組のキー）の分散成分と、いちばん下の段の中の分散（その他）。入れ子の分散分析の
% モーメント法（点の数がそろわないデータでも使える係数）：段 k の平均平方の期待値 = その他の分散 + Σ（段 j ≥ k の係数 ×
% 段 j の分散成分）を、下の段から順に解く。係数 = [Σ（段 k の組 y）Σ（y の中の段 j の組 x）n_x² / n_y − 同じ和を段 k − 1 の
% 組で] / 段 k の自由度。自由度が 0 の段（組が1つしかない）と、負になった段は 0 にする
n = numel(values);
nLevels = numel(keys);
group = cell(1, nLevels);
counts = cell(1, nLevels);
means = cell(1, nLevels);
for k = 1:nLevels
    [~, ~, group{k}] = unique(keys{k});
    counts{k} = accumarray(group{k}, 1);
    means{k} = accumarray(group{k}, values) ./ counts{k};
end
% ancestor{j}{k}：段 j の組の、段 k（0 = 全体）の組の番号（j ≥ k）
ancestor = cell(1, nLevels);
for j = 1:nLevels
    ancestor{j} = cell(1, j + 1);
    ancestor{j}{1} = ones(numel(counts{j}), 1);   % 段 0（全体）
    for k = 1:j
        ancestor{j}{k + 1} = accumarray(group{j}, group{k}, [numel(counts{j}), 1], @(v) v(1));
    end
end
levelCounts = [{n}, counts];   % 段 0 は全体（1つの組、点の数 n）
levelMeans = [{mean(values)}, means];
squares = zeros(1, nLevels + 1);
freedom = zeros(1, nLevels + 1);
for k = 1:nLevels
    parentMean = levelMeans{k}(ancestor{k}{k});   % 上の段の組の平均（組ごと）
    squares(k) = sum(counts{k} .* (means{k} - parentMean) .^ 2);
    freedom(k) = numel(counts{k}) - numel(levelCounts{k});
end
squares(end) = sum((values - means{nLevels}(group{nLevels})) .^ 2);
freedom(end) = n - numel(counts{nLevels});
meanSquares = squares ./ max(freedom, 1);
variances = zeros(1, nLevels + 1);
if freedom(end) > 0
    variances(end) = meanSquares(end);
end
for k = nLevels:-1:1
    if freedom(k) <= 0
        continue
    end
    rest = meanSquares(k) - variances(end);
    for j = k:nLevels
        coefficient = (squareSum(counts{j}, ancestor{j}{k + 1}, levelCounts{k + 1}) - ...
            squareSum(counts{j}, ancestor{j}{k}, levelCounts{k})) / freedom(k);
        if j == k
            diagonal = coefficient;
        else
            rest = rest - coefficient * variances(j);
        end
    end
    variances(k) = max(rest / diagonal, 0);
end
end

function value = squareSum(childCounts, ancestorGroup, ancestorCounts)
% Σ（上の段の組 y）Σ（y の中の下の段の組 x）n_x² / n_y
value = sum(accumarray(ancestorGroup, childCounts .^ 2, [numel(ancestorCounts), 1]) ./ ancestorCounts(:));
end

function result = varianceTables(rowCategory, rowAxis, components, variances, counts)
% 結果の表。rowCategory・rowAxis：行（棒 × 軸）の名前、components：段の名前、variances：行 × 段の分散、counts：行ごとの点の数。
% 全体の分散 = 段の分散の和（分散の加法性）。3σ = 3√分散、3σ の配分 = 全体の 3σ × 段の分散の割合（足すと全体の 3σ）
SIGMA_MULTIPLE = 3;   % 3σ
nRows = numel(rowCategory);
nComponents = numel(components);
total = sum(variances, 2);
percent = 100 * variances ./ total;
percent(~(total > 0), :) = NaN;
share = SIGMA_MULTIPLE * sqrt(total) .* percent / 100;
long = reshape(variances.', [], 1);
result.components = components;
result.table = table(repelem(rowCategory, nComponents, 1), repelem(rowAxis, nComponents, 1), ...
    repmat(components(:), nRows, 1), long, SIGMA_MULTIPLE * sqrt(long), reshape(share.', [], 1), ...
    reshape(percent.', [], 1), repelem(counts, nComponents, 1), 'VariableNames', ["category", "axis", "component", ...
    "variance", "sigma3", "sigma3Share", "percent", "n"]);
result.totals = table(rowCategory, rowAxis, total, SIGMA_MULTIPLE * sqrt(total), counts, ...
    'VariableNames', ["category", "axis", "variance", "sigma3", "n"]);
end
