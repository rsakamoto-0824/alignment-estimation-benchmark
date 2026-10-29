function summary = correctionMap(ax, correction, unit, options)
%CORRECTIONMAP 重ね合わせ補正（alignest.targetOverlayCorrection）の補正後の残差・補正量・補正前の値を Wafer 上に描く。
%   summary = alignest.plot.correctionMap(ax, correction, unit, options)
%   correction.points の点（実測値＝学習点・学習しなかった Mark の推定値・未知の座標の推定値）の値を、矢印
%   （options.mode = "vector"）または X・Y の色で描く（alignest.plot.waferMap）。色だけで区別しないよう、
%   実測値の点は四角、未知の座標の点は ◇ で重ね、凡例にも出す。Shot の枠は unit の Shot。
%   options.value ："residual"（補正後の残差 = 値 − 補正量）・"correction"（補正量）・"value"（補正前の値）
%   options.source："all"（すべての点）・"target"（未知の座標だけ）・"measured"（実測値＝学習点だけ）・
%                   "estimated"（学習しなかった Mark の推定値だけ）
%   options.titleText：題名の1行目（2行目に値の名前と |平均| + 3σ を足す。options.showStatistics = false なら
%   1行目だけ）、options.waferRadiusMm：Wafer の半径 [mm]、options.legendLocation：凡例の位置（既定は図の下）。
%   options.valueLabel：値の名前を変えるとき（例："1次だけで補正した残差"。既定は options.value の名前）、
%   options.markMeasured：false なら実測値の点に四角を重ねない（すべての点が計測値のとき。「7. Shot高次補正」）。
%   summary は描いた点の数 n と、X・Y の |平均| + 3σ [nm]（meanPlus3SigmaX・Y）、値の名前 valueLabel。
arguments
    ax
    correction struct
    unit struct
    options.value (1, 1) string {mustBeMember(options.value, ["residual", "correction", "value"])} = "residual"
    options.source (1, 1) string {mustBeMember(options.source, ["all", "target", "measured", "estimated"])} = "all"
    options.mode (1, 1) string {mustBeMember(options.mode, ["vector", "X", "Y"])} = "vector"
    options.titleText (1, 1) string = ""
    options.waferRadiusMm (1, 1) double = 150
    options.markerSize (1, 1) double {mustBePositive} = 30
    options.showStatistics (1, 1) logical = true
    options.legendLocation (1, 1) string = "southoutside"
    options.valueLabel (1, 1) string = ""
    options.markMeasured (1, 1) logical = true
end
VALUE_COLUMNS = struct("residual", ["residualX", "residualY"], "correction", ["correctionX", "correctionY"], ...
    "value", ["valueX", "valueY"]);
VALUE_LABELS = struct("residual", "補正後の残差", "correction", "補正量", "value", "補正前の値");
SOURCE_NAMES = struct("target", "推定値（未知の座標）", "measured", "実測値（学習点）", ...
    "estimated", "推定値（学習しなかった Mark）");
TARGET_COLOR = [0.85, 0.33, 0.10];
LEGEND_FONT_SIZE = 9;
MAX_LEGEND_COLUMNS = 2;
points = correction.points;
if options.source ~= "all"
    points = points(points.source == SOURCE_NAMES.(options.source), :);
end
columns = VALUE_COLUMNS.(options.value);
values = [points.(columns(1)), points.(columns(2))];
xy = [points.x, points.y];
valueLabel = VALUE_LABELS.(options.value);
if options.valueLabel ~= ""
    valueLabel = options.valueLabel;
end
summary = struct("n", height(points), "meanPlus3SigmaX", meanPlus3Sigma(values(:, 1)), ...
    "meanPlus3SigmaY", meanPlus3Sigma(values(:, 2)), "valueLabel", valueLabel);
secondLine = sprintf("%s（%d 点）｜|平均|+3σ X %.3f・Y %.3f nm", valueLabel, summary.n, summary.meanPlus3SigmaX, ...
    summary.meanPlus3SigmaY);
titleText = secondLine;
if options.titleText ~= "" && options.showStatistics
    titleText = options.titleText + newline + secondLine;
elseif options.titleText ~= ""
    titleText = options.titleText;   % 画面の狭い図では1行にする（値の名前は凡例、数値は図の外の説明に出す）
end
column = 1 + (options.mode == "Y");
colorLimit = max(abs(values(isfinite(values(:, column)), column)), [], 'all');
if isempty(colorLimit) || colorLimit <= 0
    colorLimit = 1;
end
measured = points.source == SOURCE_NAMES.measured & options.markMeasured;
alignest.plot.waferMap(ax, xy, values, mode=options.mode, scaleMmPerNm=alignest.plot.vectorScale(values), ...
    colorLimit=colorLimit, trainPoints=xy(measured, :), titleText=titleText, waferRadiusMm=options.waferRadiusMm, ...
    markerSize=options.markerSize, showLegend=false, shotCenters=[unit.shots.Xmm(:), unit.shots.Ymm(:)], ...
    shotSizeMm=unit.shotSizeMm);
hold(ax, 'on');
items = reshape(findobj(ax, 'DisplayName', '学習に使った Mark'), 1, []);
set(items, 'DisplayName', '実測値の点（学習点）');
arrows = reshape(findobj(ax, 'DisplayName', '値（矢印）'), 1, []);
set(arrows, 'DisplayName', valueLabel + "（矢印）");
items = [items, arrows];
targets = points.source == SOURCE_NAMES.target;
if any(targets)
    items(end + 1) = plot(ax, points.x(targets), points.y(targets), 'd', 'MarkerSize', 5, 'LineWidth', 1, ...
        'Color', TARGET_COLOR, 'LineStyle', 'none', 'DisplayName', sprintf('未知の座標の点（%d 点）', nnz(targets)));
end
hold(ax, 'off');
if ~isempty(items)
    columns = min(numel(items), MAX_LEGEND_COLUMNS);
    if contains(options.legendLocation, ["east", "west"])
        columns = 1;   % 横に置くときは縦に並べる
    end
    legend(ax, items, 'Location', options.legendLocation, 'NumColumns', columns, 'Box', 'off', 'FontSize', LEGEND_FONT_SIZE);
end
end

function value = meanPlus3Sigma(values)
% Overlay の代表値 |平均| + 3σ（σ は不偏標準偏差）。点が2点未満なら NaN（alignest.targetOverlayCorrection と同じ）
values = values(isfinite(values));
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end
