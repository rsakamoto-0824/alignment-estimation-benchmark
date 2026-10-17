function waferMap(ax, points, values, options)
%WAFERMAP Wafer 上の値をベクトル（矢印）または色で描く。
%   points : 点の座標 [x, y]（mm、点数 × 2）
%   values : 値 [X, Y]（nm、点数 × 2。片方の軸が無効な点は NaN）
%   options.mode         : "vector"（矢印）・"X"・"Y"（色）
%   options.scaleMmPerNm : 矢印の長さ [mm/nm]
%   options.colorLimit   : 色の範囲 ±[nm]
%   options.trainPoints  : 学習に使った Mark の座標（四角で描く）
%   options.titleText    : 図の題名
%   options.showLegend   : 凡例を出すか（既定 true）
%   色だけで意味を伝えないよう、学習 Mark は形（四角）と凡例の文字でも示す。
arguments
    ax
    points double
    values double
    options.mode (1, 1) string = "vector"
    options.scaleMmPerNm (1, 1) double = 1
    options.colorLimit (1, 1) double = 5
    options.trainPoints double = zeros(0, 2)
    options.titleText (1, 1) string = ""
    options.waferRadiusMm (1, 1) double = 150
    options.arrowColor (1, 3) double = [0.0, 0.33, 0.62]
    options.showLegend (1, 1) logical = true
end
WAFER_EDGE_COLOR = [0.45, 0.45, 0.45];
TRAIN_FACE_COLOR = [0.80, 0.80, 0.80];
TRAIN_EDGE_COLOR = [0.25, 0.25, 0.25];
MARGIN_MM = 8;
cla(ax, 'reset');
hold(ax, 'on');
angle = linspace(0, 2 * pi, 361);
plot(ax, options.waferRadiusMm * cos(angle), options.waferRadiusMm * sin(angle), '--', ...
    'Color', WAFER_EDGE_COLOR, 'HandleVisibility', 'off');
legendItems = gobjects(0);
if ~isempty(options.trainPoints)
    legendItems(end + 1) = plot(ax, options.trainPoints(:, 1), options.trainPoints(:, 2), 's', 'MarkerSize', 6, ...
        'MarkerFaceColor', TRAIN_FACE_COLOR, 'MarkerEdgeColor', TRAIN_EDGE_COLOR, 'LineStyle', 'none', ...
        'DisplayName', '学習に使った Mark');
end
if options.mode == "vector"
    usable = all(isfinite(values), 2);
    legendItems(end + 1) = quiver(ax, points(usable, 1), points(usable, 2), ...
        values(usable, 1) * options.scaleMmPerNm, values(usable, 2) * options.scaleMmPerNm, 0, ...
        'Color', options.arrowColor, 'LineWidth', 1, 'MaxHeadSize', 0.4, 'DisplayName', '値（矢印）');
    drawScaleBar(ax, options.scaleMmPerNm, options.waferRadiusMm);
else
    column = 1 + (options.mode == "Y");
    usable = isfinite(values(:, column));
    scatter(ax, points(usable, 1), points(usable, 2), 30, values(usable, column), 'filled', 'HandleVisibility', 'off');
    colormap(ax, alignest.plot.divergingColormap());
    caxis(ax, [-1, 1] * max(options.colorLimit, eps));
    bar = colorbar(ax);
    bar.Title.String = options.mode + " [nm]";
end
hold(ax, 'off');
axis(ax, 'equal');
limit = options.waferRadiusMm + MARGIN_MM;
xlim(ax, [-limit, limit]);
ylim(ax, [-limit, limit]);
xlabel(ax, 'x [mm]');
ylabel(ax, 'y [mm]');
title(ax, options.titleText, 'Interpreter', 'none');
box(ax, 'on');
if options.showLegend && ~isempty(legendItems)
    legend(ax, legendItems, 'Location', 'southoutside', 'Orientation', 'horizontal', 'Box', 'off');
end
end

function drawScaleBar(ax, scaleMmPerNm, waferRadiusMm)
% 左下に矢印の長さの目安（きりのよい nm）を描く
TARGET_LENGTH_MM = 25;
raw = TARGET_LENGTH_MM / scaleMmPerNm;
exponent = floor(log10(raw));
candidates = [1, 2, 5, 10] * 10^exponent;
lengthNm = candidates(find(candidates <= raw, 1, 'last'));
if isempty(lengthNm)
    lengthNm = candidates(1);
end
x0 = -waferRadiusMm;
y0 = -waferRadiusMm + 2;
quiver(ax, x0, y0, lengthNm * scaleMmPerNm, 0, 0, 'Color', [0, 0, 0], 'LineWidth', 1.5, 'MaxHeadSize', 0.6, ...
    'HandleVisibility', 'off');
text(ax, x0, y0 + 8, sprintf('%g nm', lengthNm), 'FontSize', 12, 'VerticalAlignment', 'bottom');
end
