function targetMap(ax, result, unit, options)
%TARGETMAP 未知の座標での推定値を Wafer 上に描く（「6. 未知の座標の推定」）。
%   alignest.plot.targetMap(ax, result, unit, options)
%   result：alignest.predictTargets の結果。unit：その Wafer（Shot の枠を描く）。
%   推定値を矢印（options.mode = "vector"）または X・Y の色で描き（alignest.plot.waferMap）、学習点（四角）、
%   学習点の範囲（凸包、破線）、外挿の点（× 印）を重ねる。色だけで区別しないよう、外挿の点は形（×）と凡例でも示す。
%   options.titleText：題名、options.waferRadiusMm：Wafer の半径 [mm]、options.markerSize：色で描く点の大きさ。
%   options.spec：推定する値（alignest.valueSpec）。1変数なら色で描き、色の範囲は推定値の最小〜最大、目盛りは値の名前。
arguments
    ax
    result struct
    unit struct
    options.mode (1, 1) string {mustBeMember(options.mode, ["vector", "X", "Y"])} = "vector"
    options.titleText (1, 1) string = ""
    options.waferRadiusMm (1, 1) double = 150
    options.markerSize (1, 1) double {mustBePositive} = 30
    options.spec struct = alignest.valueSpec(struct())
end
HULL_COLOR = [0.50, 0.50, 0.50];
EXTRAPOLATED_COLOR = [0.85, 0.33, 0.10];
LEGEND_FONT_SIZE = 9;
MAX_LEGEND_COLUMNS = 2;
MARGIN_MM = 8;   % 図の端の余白（alignest.plot.waferMap と同じ）
estimates = result.table;
points = [estimates.x, estimates.y];
values = [estimates.estimateX, estimates.estimateY];
column = 1 + (options.mode == "Y");
colorLimit = max(abs(values(isfinite(values(:, column)), column)), [], 'all');
if isempty(colorLimit) || colorLimit <= 0
    colorLimit = 1;
end
colorRange = [NaN, NaN];
colorTitle = "";
if options.spec.scalar
    options.mode = "X";   % 1変数は色で描く（矢印は X・Y の2成分が要る）
    finite = values(isfinite(values(:, 1)), 1);
    if ~isempty(finite)
        colorRange = [min(finite), max(finite)];
    end
    colorTitle = options.spec.name + " [" + options.spec.unit + "]";
end
alignest.plot.waferMap(ax, points, values, mode=options.mode, scaleMmPerNm=alignest.plot.vectorScale(values), ...
    colorLimit=colorLimit, colorRange=colorRange, colorTitle=colorTitle, trainPoints=result.trainXY, ...
    titleText=options.titleText, ...
    waferRadiusMm=options.waferRadiusMm, markerSize=options.markerSize, showLegend=false, ...
    shotCenters=[unit.shots.Xmm(:), unit.shots.Ymm(:)], shotSizeMm=unit.shotSizeMm);
hold(ax, 'on');
items = reshape(findobj(ax, 'DisplayName', '学習に使った Mark'), 1, []);
set(items, 'DisplayName', '学習点（計測値）');
arrows = reshape(findobj(ax, 'DisplayName', '値（矢印）'), 1, []);
set(arrows, 'DisplayName', '推定値（矢印）');
items = [items, arrows];
hull = result.hull;
if size(hull, 1) >= 2
    items(end + 1) = plot(ax, hull(:, 1), hull(:, 2), '--', 'Color', HULL_COLOR, 'LineWidth', 1, ...
        'DisplayName', '学習点の範囲（凸包）');
end
outside = estimates.extrapolated;
if any(outside)
    items(end + 1) = plot(ax, estimates.x(outside), estimates.y(outside), 'x', 'MarkerSize', 9, 'LineWidth', 1.6, ...
        'Color', EXTRAPOLATED_COLOR, 'LineStyle', 'none', 'DisplayName', sprintf('外挿の点（%d 点）', nnz(outside)));
end
hold(ax, 'off');
limit = max(options.waferRadiusMm, max(abs(points(:)))) + MARGIN_MM;   % Wafer の外の点も見えるように
xlim(ax, [-limit, limit]);
ylim(ax, [-limit, limit]);
if ~isempty(items)
    legend(ax, items, 'Location', 'southoutside', 'NumColumns', min(numel(items), MAX_LEGEND_COLUMNS), 'Box', 'off', ...
        'FontSize', LEGEND_FONT_SIZE);
end
end
