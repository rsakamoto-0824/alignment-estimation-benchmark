function result = varianceDecomposition(points, options)
%VARIANCEDECOMPOSITION 値のばらつきを、Lot 間・Wafer 間・Shot 間・その他に分ける（入れ子の平方和の分解）。
%   result = alignest.varianceDecomposition(points)
%   result = alignest.varianceDecomposition(points, valueColumns=["valueX", "valueY"], axisNames=["X", "Y"], ...
%       categories=棒の並び, useLot=true)
%   points：点ごとの表。category（棒を分ける名前。例：Operation・補正の段階）・lot（Lot の名前）・wafer（Wafer（計測）の名前）・
%   shot（Shot の番号）と、値の列（valueColumns。値の無い点は NaN）。
%   分け方：上の段から Lot → Wafer → Shot と入れ子にして（下の段は上の段の中で分ける）、点の値を
%     値 = 全体の平均 + (Lot の平均 − 全体の平均) + (Wafer の平均 − Lot の平均) + (Shot の平均 − Wafer の平均)
%          + (値 − Shot の平均)
%   と分ける。それぞれの差の2乗を全点で足して点の数で割った値が、その段のばらつき（分散）で、足すと値の分散（点の数で割る）に
%   なる（差どうしは直交するため）。その他 = Shot 内のばらつき（Mark ごとの違いと計測のばらつき）。上の段のばらつきには、
%   下の段のばらつきの平均の分も少し入る（Wafer ごとの平均にも Shot・計測のばらつきが残るため）。
%   段の 3σ = 3 × √（段の分散）。3σ は足しても全体の 3σ にならない（全体の 3σ = 3 × √（段の分散の和））。
%   useLot（省略時：Lot が2つ以上あれば true）が false なら Lot 間は分けない（その分は Wafer 間に入る）。
%   result.table：category・axis・component（段の名前）・variance（分散 [値の単位²]）・sigma3（3σ [値の単位]）・percent（全体の
%   分散に対する割合 [%]）・n（点の数）。result.totals：category・axis・variance・sigma3・n（全体）。
%   result.components（分けた段の名前。上の段から）・categories・axes・useLot
arguments
    points table
    options.valueColumns (1, :) string = ["valueX", "valueY"]
    options.axisNames (1, :) string = ["X", "Y"]
    options.categories (1, :) string = strings(1, 0)
    options.useLot = []
end
LEVEL_NAMES = ["Lot 間", "Wafer 間", "Shot 間"];
OTHER_NAME = "その他";
SIGMA_MULTIPLE = 3;   % 3σ
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
total = sum(variances, 2);
percent = 100 * variances ./ total;
percent(~(total > 0), :) = NaN;
long = reshape(variances.', [], 1);
result.components = components;
result.categories = categories;
result.axes = options.axisNames;
result.useLot = logical(useLot);
result.table = table(repelem(rowCategory, nComponents, 1), repelem(rowAxis, nComponents, 1), ...
    repmat(components(:), nRows, 1), long, SIGMA_MULTIPLE * sqrt(long), reshape(percent.', [], 1), ...
    repelem(counts, nComponents, 1), 'VariableNames', ["category", "axis", "component", "variance", "sigma3", ...
    "percent", "n"]);
result.totals = table(rowCategory, rowAxis, total, SIGMA_MULTIPLE * sqrt(total), counts, ...
    'VariableNames', ["category", "axis", "variance", "sigma3", "n"]);
end

function variances = levelVariances(values, keys)
% 入れ子の段（keys：上の段から、点ごとの組のキー）ごとのばらつきと、いちばん下の段の中のばらつき（その他）
n = numel(values);
previous = repmat(mean(values), n, 1);
variances = zeros(1, numel(keys) + 1);
for k = 1:numel(keys)
    [~, ~, group] = unique(keys{k});
    means = accumarray(group, values) ./ accumarray(group, 1);
    current = means(group);
    variances(k) = sum((current - previous) .^ 2) / n;
    previous = current;
end
variances(end) = sum((values - previous) .^ 2) / n;
end
