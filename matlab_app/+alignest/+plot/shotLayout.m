function shotLayout(ax, unit, waferRadiusMm)
%SHOTLAYOUT Wafer 上の Shot の並び（枠と shotNo）と、計測した Mark の位置を描く。
%   Scan 方向があれば、Shot を Scan 方向で塗り分け、shotNo の下に「S1」「S2」と書く（色だけに頼らない）。
%   unit は prepareData の評価の単位（shots・marks・shotSizeMm を使う）。
SCAN_COLORS = [0.80, 0.88, 0.97; 0.99, 0.87, 0.74];  % Scan 方向 1・2 の塗り（薄い青・薄い橙）
NO_SCAN_COLOR = [0.93, 0.93, 0.93];
EDGE_COLOR = [0.45, 0.45, 0.45];
MARK_COLOR = [0.10, 0.10, 0.10];
LABEL_FONT_SIZE = 8;
MARGIN_MM = 8;
shots = unit.shots;
marks = unit.marks;
cla(ax, 'reset');
hold(ax, 'on');
angle = linspace(0, 2 * pi, 361);
plot(ax, waferRadiusMm * cos(angle), waferRadiusMm * sin(angle), '--', 'Color', [0.45, 0.45, 0.45], ...
    'HandleVisibility', 'off');
half = unit.shotSizeMm / 2;
legendItems = gobjects(0);
if unit.hasDirection
    names = ["Scan 方向 1（S1）", "Scan 方向 2（S2）"];
    colors = SCAN_COLORS;
else
    names = "Shot";
    colors = NO_SCAN_COLOR;
end
for k = 1:numel(names)
    select = true(size(shots.Xmm));
    if unit.hasDirection
        select = shots.direction == k;
    end
    if ~any(select)
        continue
    end
    patchX = shots.Xmm(select).' + [-1; 1; 1; -1] * half(1);
    patchY = shots.Ymm(select).' + [-1; -1; 1; 1] * half(2);
    legendItems(end + 1) = patch(ax, 'XData', patchX, 'YData', patchY, 'FaceColor', colors(k, :), ...
        'EdgeColor', EDGE_COLOR, 'LineWidth', 0.5, 'DisplayName', names(k)); %#ok<AGROW>
end
legendItems(end + 1) = plot(ax, marks.x, marks.y, '.', 'Color', MARK_COLOR, 'MarkerSize', 6, ...
    'DisplayName', 'Mark（計測した点）');
for s = 1:numel(shots.Xmm)
    label = string(shots.shotNo(s));
    if unit.hasDirection && isfinite(shots.direction(s))
        label = [label; "S" + shots.direction(s)];
    end
    text(ax, shots.Xmm(s), shots.Ymm(s), label, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'FontSize', LABEL_FONT_SIZE, 'Interpreter', 'none');
end
hold(ax, 'off');
axis(ax, 'equal');
limit = waferRadiusMm + MARGIN_MM;
xlim(ax, [-limit, limit]);
ylim(ax, [-limit, limit]);
xlabel(ax, 'x [mm]');
ylabel(ax, 'y [mm]');
title(ax, sprintf("%s：Shot の配置（数字は shotNo）", unit.label), 'Interpreter', 'none');
box(ax, 'on');
legend(ax, legendItems, 'Location', 'southoutside', 'Orientation', 'horizontal', 'Box', 'off');
end
