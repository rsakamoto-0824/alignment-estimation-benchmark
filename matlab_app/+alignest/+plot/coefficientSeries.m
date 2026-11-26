function lines_ = coefficientSeries(ax, coefficients, axisNames, titleText, options)
%COEFFICIENTSERIES Wafer ごとの成分の回帰係数（alignest.componentCoefficients。「ばらつき分解」の分け方「成分」）を、横軸に
%   Wafer の番号（表の No.）、縦軸に係数で描く（軸ごとの線。0 の横線と、category（Operation）が変わる所に縦の点線）。
%   lines_ = alignest.plot.coefficientSeries(ax, coefficients, axisNames, titleText)
%   lines_ = alignest.plot.coefficientSeries(..., categories=Wafer ごとの category, showLegend=true)
%   coefficients：Wafer × 軸 の係数（NaN の点は描かない）。lines_：軸ごとの線。
arguments
    ax
    coefficients double
    axisNames (1, :) string
    titleText (1, 1) string
    options.categories (1, :) string = strings(1, 0)
    options.showLegend (1, 1) logical = true
end
AXIS_COLORS = [0.00, 0.45, 0.74; 0.85, 0.33, 0.10];   % X・Y
MARKERS = ["o", "s"];
MARKER_SIZE = 5;
GUIDE_COLOR = [0.55, 0.55, 0.55];   % 0 の横線と category の区切り
MAX_TICKS = 15;   % Wafer がこれより多いときは横軸の目盛りを間引く
nWafers = size(coefficients, 1);
positions = 1:nWafers;
held = ishold(ax);
hold(ax, 'on');
lines_ = gobjects(1, numel(axisNames));
for a = 1:numel(axisNames)
    style = mod(a - 1, size(AXIS_COLORS, 1)) + 1;
    lines_(a) = plot(ax, positions, coefficients(:, a), '-', 'Color', AXIS_COLORS(style, :), 'Marker', MARKERS(style), ...
        'MarkerSize', MARKER_SIZE, 'MarkerFaceColor', AXIS_COLORS(style, :), 'DisplayName', axisNames(a));
end
yline(ax, 0, ':', 'Color', GUIDE_COLOR, 'HandleVisibility', 'off');
categories = options.categories;
if numel(categories) == nWafers && nWafers > 1
    for boundary = find(categories(2:end) ~= categories(1:end - 1)) + 0.5
        xline(ax, boundary, '--', 'Color', GUIDE_COLOR, 'HandleVisibility', 'off');
    end
end
if ~held
    hold(ax, 'off');
end
ticks = positions;
if nWafers > MAX_TICKS
    ticks = unique(round(linspace(1, nWafers, MAX_TICKS)));
end
xlim(ax, [0.5, max(nWafers, 1) + 0.5]);
ax.XTick = ticks;
xlabel(ax, 'Wafer（表の No.）');
title(ax, titleText);
grid(ax, 'on');
box(ax, 'on');
if options.showLegend
    legend(ax, lines_, 'Location', 'best');
end
end
