function markLayout(ax, unit)
%MARKLAYOUT 1つの Shot の中の Mark の位置と番号を描く（Shot 中心からの座標 markXmm・markYmm）。
%   Wafer の全 Shot の Mark を、Shot 内の座標で重ねる。同じ位置の Mark は1つにまとめ、
%   「M番号」「x・y の座標」「その位置で計測した Shot の数」を、Shot の中心寄りに書く（枠の外にはみ出さないように）。
%   同じ番号が違う位置にある（Shot によって Mark の位置が違う）場合も、位置ごとに書く。
COORDINATE_DIGITS = 3;
FRAME_COLOR = [0.45, 0.45, 0.45];
MARK_COLOR = [0.0, 0.36, 0.67];
LABEL_FONT_SIZE = 9;
MARGIN_RATIO = 0.15;
LABEL_OFFSET_RATIO = 0.03;  % Mark の点から文字までの間（Shot の高さに対する比）
marks = unit.marks;
positions = round([marks.markXmm, marks.markYmm], COORDINATE_DIGITS);
[keys, ~, group] = unique([positions, marks.markNo], 'rows');
nShots = accumarray(group, 1);
cla(ax, 'reset');
hold(ax, 'on');
half = unit.shotSizeMm / 2;
plot(ax, [-1, 1, 1, -1, -1] * half(1), [-1, -1, 1, 1, -1] * half(2), '-', 'Color', FRAME_COLOR, 'LineWidth', 1.2, ...
    'DisplayName', 'Shot の枠');
plot(ax, [-half(1), half(1)], [0, 0], ':', 'Color', FRAME_COLOR, 'HandleVisibility', 'off');
plot(ax, [0, 0], [-half(2), half(2)], ':', 'Color', FRAME_COLOR, 'HandleVisibility', 'off');
plot(ax, 0, 0, '+', 'Color', FRAME_COLOR, 'MarkerSize', 10, 'HandleVisibility', 'off');
plot(ax, keys(:, 1), keys(:, 2), 'o', 'MarkerFaceColor', MARK_COLOR, 'MarkerEdgeColor', 'none', 'MarkerSize', 8, ...
    'DisplayName', 'Mark');
for k = 1:size(keys, 1)
    upper = keys(k, 2) >= 0;
    right = keys(k, 1) > 0;
    offset = (1 - 2 * upper) * LABEL_OFFSET_RATIO * unit.shotSizeMm(2);
    text(ax, keys(k, 1), keys(k, 2) + offset, sprintf("M%g\nx %.3f\ny %.3f\n%d Shot", keys(k, 3), keys(k, 1), ...
        keys(k, 2), nShots(k)), 'HorizontalAlignment', ternary(right, 'right', ternary(keys(k, 1) < 0, 'left', 'center')), ...
        'VerticalAlignment', ternary(upper, 'top', 'bottom'), 'FontSize', LABEL_FONT_SIZE, 'Interpreter', 'none');
end
hold(ax, 'off');
axis(ax, 'equal');
span = max([half; abs(keys(:, 1:2))], [], 1) * (1 + 2 * MARGIN_RATIO);
xlim(ax, [-span(1), span(1)]);
ylim(ax, [-span(2), span(2)]);
xlabel(ax, 'markXmm [mm]（Shot 中心から）');
ylabel(ax, 'markYmm [mm]（Shot 中心から）');
title(ax, sprintf("Shot 内の Mark の位置（%d 通り、M は markNo）", size(keys, 1)), 'Interpreter', 'none');
box(ax, 'on');
legend(ax, 'Location', 'southoutside', 'Orientation', 'horizontal', 'Box', 'off');
end

function value = ternary(condition, whenTrue, whenFalse)
if condition
    value = whenTrue;
else
    value = whenFalse;
end
end
