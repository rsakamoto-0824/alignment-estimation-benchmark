function colors = correlationScale(ax)
%CORRELATIONSCALE 共分散楕円の色（X・Y の相関係数の絶対値 |r|）の色の並びと、図の中の小さな目盛り。
%   colors = alignest.plot.correlationScale()      % 色の並び（|r| = 0 → 1。灰色 → 紫）
%   alignest.plot.correlationScale(ax)             % ax の右上の隅（Wafer の外）に |r| の目盛りを描く
%   図の右の色の目盛りは矢印の長さに使うので、|r| の目盛りは図の中に描く。軸の範囲を決めた後に呼ぶ。
LEVELS = 64;
STOPS = [0, 1];
STOP_COLORS = [0.66, 0.66, 0.66; 0.50, 0.05, 0.55];
colors = interp1(STOPS, STOP_COLORS, linspace(0, 1, LEVELS));
if nargin == 0
    return
end
% 目盛りの位置：軸の範囲に対する割合（右上の隅。Wafer の円の外に収まる）
BAR_X = [0.935, 0.965];
BAR_Y = [0.76, 0.96];
LABEL_FONT_SIZE = 9;
xRange = ax.XLim;
yRange = ax.YLim;
toX = @(ratio) xRange(1) + ratio * diff(xRange);
toY = @(ratio) yRange(1) + ratio * diff(yRange);
levels = linspace(0, 1, LEVELS + 1);
bottoms = toY(BAR_Y(1) + levels(1:end - 1) * diff(BAR_Y));
tops = toY(BAR_Y(1) + levels(2:end) * diff(BAR_Y));
left = toX(BAR_X(1));
right = toX(BAR_X(2));
holdState = ishold(ax);
hold(ax, 'on');
patch(ax, 'XData', repmat([left; right; right; left], 1, LEVELS), 'YData', [bottoms; bottoms; tops; tops], ...
    'FaceVertexCData', colors, 'FaceColor', 'flat', 'EdgeColor', 'none', 'HandleVisibility', 'off', ...
    'Tag', 'correlationScale');
plot(ax, [left, right, right, left, left], toY(BAR_Y([1, 1, 2, 2, 1])), '-', 'Color', [0.4, 0.4, 0.4], ...
    'LineWidth', 0.5, 'HandleVisibility', 'off', 'Tag', 'correlationScale');
text(ax, left, toY(BAR_Y(2)), '|r| 1 ', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
    'FontSize', LABEL_FONT_SIZE, 'Tag', 'correlationScale');
text(ax, left, toY(BAR_Y(1)), '0 ', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
    'FontSize', LABEL_FONT_SIZE, 'Tag', 'correlationScale');
if ~holdState
    hold(ax, 'off');
end
end
