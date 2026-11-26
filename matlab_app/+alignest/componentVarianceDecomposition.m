function result = componentVarianceDecomposition(points, options)
%COMPONENTVARIANCEDECOMPOSITION 値のばらつき（分散）を、全体 Shift・Wafer 倍率・Wafer 回転・Wafer その他・Shot 倍率・
%   Shot 回転・Shot その他の成分に分ける（X・Y それぞれ。「1. データ読込」の「ばらつき分解」の分け方「成分」）。
%   result = alignest.componentVarianceDecomposition(points)
%   result = alignest.componentVarianceDecomposition(points, valueColumns=["valueX", "valueY"], axisNames=["X", "Y"], ...
%       categories=棒の並び)
%   points：点ごとの表。category（棒を分ける名前）・wafer（Wafer（計測）の名前）・shot（Wafer の中の Shot の番号）・
%   shotX・shotY（Shot 中心 [mm]）・localX・localY（Shot 内の座標 [mm]）と、値の列（値の無い点は NaN）。
%   Wafer ごとに、軸ごとの点の値を次の順に分ける（点の数で重みを付けた最小二乗の射影なので、成分どうしは直交し、成分の
%   平方和を足すと全体の平均からの平方和になる。分散 = 平方和 / 点の数（棒の全点）で、足すと値の分散）：
%   1. 全体 Shift：Wafer の平均（値 − 全体の平均 のうち Wafer ごとに一定の分。Wafer 間の Shift のばらつき）
%   2. Wafer 倍率・Wafer 回転：Shot ごとの n 点の平均値（Shot 平均 − Wafer の平均）を Shot 中心の座標に当てはめた成分。X は
%      倍率 = Shot 中心 X の項、回転 = Shot 中心 Y の項、Y は倍率 = Y の項、回転 = X の項（座標は Shot の点の数の重みで平均を
%      引き、回転の座標は倍率の座標と直交させる）
%   3. Wafer その他：Shot 平均の残り（Wafer の高次の形と Shot 間のばらつき）
%   4. Shot 倍率・Shot 回転：Wafer の成分（Shot 平均）を除いた値（Shot 内の差）を、Shot 内の座標に当てはめた Shot 共通の成分
%      （Wafer ごと。X は倍率 = Shot 内 X、回転 = Shot 内 Y、Y は逆。Shot 内の座標は Shot ごとに平均を引く）
%   5. Shot その他：残り（Shot 内の高次の形・Shot ごとの違い・計測のばらつき）
%   1変数の値（axisNames が1つ）は X と同じ向きで分ける。
%   result：alignest.varianceResult の形（table・totals・components）に、categories・axes・useLot（false）・kind
%   （"components"）・means（棒・軸ごとの全体の平均 = Shift の平均。表 category・axis・mean）を足したもの
arguments
    points table
    options.valueColumns (1, :) string = ["valueX", "valueY"]
    options.axisNames (1, :) string = ["X", "Y"]
    options.categories (1, :) string = strings(1, 0)
end
COMPONENTS = ["全体 Shift", "Wafer 倍率", "Wafer 回転", "Wafer その他", "Shot 倍率", "Shot 回転", "Shot その他"];
if numel(options.valueColumns) ~= numel(options.axisNames)
    error('alignest:varianceDecomposition', '値の列と軸の名前の数が違います。');
end
category = string(points.category);
categories = options.categories;
if isempty(categories)
    categories = reshape(unique(category, 'stable'), 1, []);
end
wafer = string(points.wafer);
shotKey = wafer + "|" + string(points.shot);
nRows = numel(categories) * numel(options.axisNames);
[rowCategory, rowAxis] = deal(strings(nRows, 1));
[variances, counts, means] = deal(nan(nRows, numel(COMPONENTS)), zeros(nRows, 1), nan(nRows, 1));
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
        if a == 2   % Y：倍率は Y の項、回転は X の項
            coordinates = [points.shotY, points.shotX, points.localY, points.localX];
        else        % X（1変数の値も X と同じ向き）：倍率は X の項、回転は Y の項
            coordinates = [points.shotX, points.shotY, points.localX, points.localY];
        end
        [squares, means(r)] = componentSquares(values(rows), wafer(rows), shotKey(rows), double(coordinates(rows, :)));
        variances(r, :) = squares / counts(r);
    end
end
result = alignest.varianceResult(rowCategory, rowAxis, COMPONENTS, variances, counts);
result.categories = categories;
result.axes = options.axisNames;
result.useLot = false;
result.kind = "components";
result.means = table(rowCategory, rowAxis, means, 'VariableNames', ["category", "axis", "mean"]);
end

function [squares, grand] = componentSquares(values, wafer, shotKey, coordinates)
% 成分ごとの平方和（全体 Shift・Wafer 倍率・Wafer 回転・Wafer その他・Shot 倍率・Shot 回転・Shot その他）と全体の平均。
% coordinates：点ごとの [Wafer 倍率の座標, Wafer 回転の座標, Shot 倍率の座標, Shot 回転の座標]（Shot 中心・Shot 内）
grand = mean(values);
squares = zeros(1, 7);
[~, ~, waferIndex] = unique(wafer);
for w = 1:max(waferIndex)
    mine = waferIndex == w;
    v = values(mine);
    waferMean = mean(v);
    squares(1) = squares(1) + numel(v) * (waferMean - grand) ^ 2;
    % Shot ごとの n 点の平均で、Wafer の成分（倍率・回転・その他）を求める（Shot の点の数の重み）
    [~, ~, shot] = unique(shotKey(mine));
    weights = accumarray(shot, 1);
    shotMean = accumarray(shot, v) ./ weights;
    shotCoordinates = [accumarray(shot, coordinates(mine, 1)), accumarray(shot, coordinates(mine, 2))] ./ weights;
    [fitted, residual] = orthogonalFit(shotMean - waferMean, shotCoordinates, weights);
    squares(2:3) = squares(2:3) + sum(weights .* fitted .^ 2, 1);
    squares(4) = squares(4) + sum(weights .* residual .^ 2);
    % Wafer の成分（Shot 平均）を除いた Shot 内の差で、Shot 共通の成分（倍率・回転）を求める
    within = v - shotMean(shot);
    local = coordinates(mine, 3:4);
    localMean = [accumarray(shot, local(:, 1)), accumarray(shot, local(:, 2))] ./ weights;
    [fitted, residual] = orthogonalFit(within, local - localMean(shot, :), ones(numel(v), 1));   % Shot ごとに平均を引いた座標
    squares(5:6) = squares(5:6) + sum(fitted .^ 2, 1);
    squares(7) = squares(7) + sum(residual .^ 2);
end
end

function [fitted, residual] = orthogonalFit(values, coordinates, weights)
% 重み weights の最小二乗で、values を座標の項（1 列目、続けて 1 列目と直交させた 2 列目）に順に当てはめる。fitted：項ごとの
% 当てはめた値（行 × 2）、residual：残り。座標は重み付きの平均を引く（values の重み付きの平均は 0 なので、定数とも直交する）
fitted = zeros(numel(values), 2);
residual = values;
basis = coordinates - sum(weights .* coordinates, 1) / max(sum(weights), eps);
tolerance = eps * max(1, sum(weights)) * max(1, max(abs(basis(:))) ^ 2);
for k = 1:2
    if k == 2
        scale = sum(weights .* basis(:, 1) .^ 2);
        if scale > tolerance
            basis(:, 2) = basis(:, 2) - sum(weights .* basis(:, 1) .* basis(:, 2)) / scale * basis(:, 1);
        end
    end
    scale = sum(weights .* basis(:, k) .^ 2);
    if scale > tolerance
        fitted(:, k) = sum(weights .* basis(:, k) .* residual) / scale * basis(:, k);
        residual = residual - fitted(:, k);
    end
end
end
