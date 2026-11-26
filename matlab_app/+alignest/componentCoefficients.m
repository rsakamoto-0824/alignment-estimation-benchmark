function result = componentCoefficients(points, options)
%COMPONENTCOEFFICIENTS Wafer ごとの成分の回帰係数（全体 Shift・Wafer 倍率・Wafer 回転・Shot 倍率・Shot 回転。X・Y それぞれ）
%   （「1. データ読込」の「ばらつき分解」の分け方「成分」）。
%   result = alignest.componentCoefficients(points)
%   result = alignest.componentCoefficients(points, valueColumns=["valueX", "valueY"], axisNames=["X", "Y"], ...
%       categories=Operation などの並び)
%   points：点ごとの表。category（Operation など）・wafer（Wafer（計測）を見分ける名前）・waferLabel（画面の Wafer の名前。
%   無ければ wafer）・shot（Wafer の中の Shot の番号）・shotX・shotY（Shot 中心 [mm]）・localX・localY（Shot 内の座標 [mm]）と、
%   値の列（値の無い点は NaN）。
%   Wafer ごと・軸ごとに、次の2段で最小二乗の回帰係数を求める（座標は mm、係数の単位は 値の単位 と 値の単位/mm）：
%   1. Wafer の成分：Shot ごとの n 点の平均値を、Shot 中心の座標に Shot の点の数の重みで当てはめる。
%      X：Shot の平均 = 全体 Shift + Wafer 倍率 × Shot 中心 X + Wafer 回転 × Shot 中心 Y
%      Y：Shot の平均 = 全体 Shift + Wafer 倍率 × Shot 中心 Y + Wafer 回転 × Shot 中心 X
%      全体 Shift は Wafer 中心（座標 0）の値。
%   2. Shot 共通の成分：Wafer の成分を除いた値（点の値 − その Shot の平均）を、Shot 内の座標（Shot ごとに平均を引く）に当てはめる。
%      X：Shot 倍率 × Shot 内 X + Shot 回転 × Shot 内 Y、Y：Shot 倍率 × Shot 内 Y + Shot 回転 × Shot 内 X
%   1変数の値（axisNames が1つ）は X と同じ向き。点・Shot が足りず決まらない係数は NaN。
%   result.table：category・waferIndex（表の順の番号）・wafer（画面の名前）・axis・component・coefficient・n（使った点の数）。
%   result.components（成分の名前）・categories・axes・wafers（Wafer の画面の名前。表の順）・waferCategories（Wafer ごとの
%   category）・kind（"components"）。
arguments
    points table
    options.valueColumns (1, :) string = ["valueX", "valueY"]
    options.axisNames (1, :) string = ["X", "Y"]
    options.categories (1, :) string = strings(1, 0)
end
COMPONENTS = ["全体 Shift", "Wafer 倍率", "Wafer 回転", "Shot 倍率", "Shot 回転"];
if numel(options.valueColumns) ~= numel(options.axisNames)
    error('alignest:varianceDecomposition', '値の列と軸の名前の数が違います。');
end
category = string(points.category);
categories = options.categories;
if isempty(categories)
    categories = reshape(unique(category, 'stable'), 1, []);
end
wafer = string(points.wafer);
label = wafer;
if ismember("waferLabel", string(points.Properties.VariableNames))
    label = string(points.waferLabel);
end
% Wafer の並び：categories の順、その中は表に出てきた順
[keys, first] = unique(wafer, 'stable');
waferCategory = category(first);
[known, categoryOrder] = ismember(waferCategory, categories);
keys = keys(known);
first = first(known);
[~, order] = sortrows([categoryOrder(known), (1:numel(keys)).']);
keys = keys(order);
first = first(order);
nWafers = numel(keys);
nAxes = numel(options.axisNames);
nComponents = numel(COMPONENTS);
coefficients = nan(nWafers, nComponents, nAxes);
counts = zeros(nWafers, nAxes);
for w = 1:nWafers
    mine = wafer == keys(w);
    for a = 1:nAxes
        values = double(points.(options.valueColumns(a)));
        rows = mine & isfinite(values);
        counts(w, a) = nnz(rows);
        if counts(w, a) == 0
            continue
        end
        if a == 2   % Y：倍率は Y の項、回転は X の項
            coordinates = [points.shotY, points.shotX, points.localY, points.localX];
        else        % X（1変数の値も X と同じ向き）：倍率は X の項、回転は Y の項
            coordinates = [points.shotX, points.shotY, points.localX, points.localY];
        end
        coefficients(w, :, a) = waferCoefficients(values(rows), string(points.shot(rows)), double(coordinates(rows, :)));
    end
end
% 長い表（Wafer × 軸 × 成分）
[componentIndex, axisIndex, waferIndex] = ndgrid(1:nComponents, 1:nAxes, 1:nWafers);
values = permute(coefficients, [2, 3, 1]);   % 成分 × 軸 × Wafer
nRows = numel(componentIndex);
waferNames = label(first);
waferCategories = category(first);   % first は点の行の番号
result.table = table(reshape(waferCategories(waferIndex(:)), nRows, 1), waferIndex(:), ...
    reshape(waferNames(waferIndex(:)), nRows, 1), reshape(options.axisNames(axisIndex(:)), nRows, 1), ...
    reshape(COMPONENTS(componentIndex(:)), nRows, 1), values(:), ...
    reshape(counts(sub2ind(size(counts), waferIndex(:), axisIndex(:))), nRows, 1), ...
    'VariableNames', ["category", "waferIndex", "wafer", "axis", "component", "coefficient", "n"]);
result.components = COMPONENTS;
result.categories = categories;
result.axes = options.axisNames;
result.wafers = reshape(waferNames, 1, []);
result.waferCategories = reshape(waferCategories, 1, []);
result.kind = "components";
end

function coefficients = waferCoefficients(values, shotKey, coordinates)
% 1枚の Wafer・1つの軸の係数 [全体 Shift, Wafer 倍率, Wafer 回転, Shot 倍率, Shot 回転]。
% coordinates：点ごとの [Wafer 倍率の座標, Wafer 回転の座標, Shot 倍率の座標, Shot 回転の座標]（Shot 中心・Shot 内）
coefficients = nan(1, 5);
[~, ~, shot] = unique(shotKey);
weights = accumarray(shot, 1);
shotMean = accumarray(shot, values) ./ weights;
shotCenter = [accumarray(shot, coordinates(:, 1)), accumarray(shot, coordinates(:, 2))] ./ weights;
coefficients(1:3) = weightedFit([ones(numel(weights), 1), shotCenter], shotMean, weights);
% Wafer の成分（Shot の平均）を除いた値を、Shot ごとに平均を引いた Shot 内の座標に当てはめる（Shot 共通の成分）
within = values - shotMean(shot);
local = coordinates(:, 3:4);
localMean = [accumarray(shot, local(:, 1)), accumarray(shot, local(:, 2))] ./ weights;
coefficients(4:5) = weightedFit(local - localMean(shot, :), within, ones(numel(values), 1));
end

function beta = weightedFit(design, values, weights)
% 重み付き最小二乗の係数。項が点で決まらない（階数が足りない）ときは NaN
beta = nan(1, size(design, 2));
scaled = sqrt(weights) .* design;
if size(design, 1) < size(design, 2) || rank(scaled) < size(design, 2)
    return
end
beta = reshape(scaled \ (sqrt(weights) .* values), 1, []);
end
