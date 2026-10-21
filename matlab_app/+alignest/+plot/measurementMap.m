function measurementMap(ax, unit, plan, waferRadiusMm, titleText)
%MEASUREMENTMAP 計測マップ：Wafer 上の Shot を、学習に使う（計測する）かどうかで塗り分けて描く。
%   plan は alignest.planTrainingShots の結果（shotIndex：計測する Shot、requiredShotIndex：必ず計測する Shot）。
%   塗りの区分：必ず計測する Shot（太い枠）・選んで計測する Shot・計測しない Shot（評価に使う）・計測値の無い Shot。
%   色だけで区別しないよう、必ず計測する Shot は太い枠、計測する Shot の shotNo は太字にする。
REQUIRED_COLOR = [0.96, 0.62, 0.25];
SELECTED_COLOR = [0.42, 0.65, 0.90];
UNUSED_COLOR = [1, 1, 1];
NO_DATA_COLOR = [0.86, 0.86, 0.86];
EDGE_COLOR = [0.45, 0.45, 0.45];
REQUIRED_EDGE_COLOR = [0.55, 0.20, 0.0];
LABEL_FONT_SIZE = 7;
MARGIN_MM = 8;
shots = unit.shots;
nShots = numel(shots.Xmm);
hasData = shots.nValidX + shots.nValidY > 0;
required = ismember((1:nShots).', plan.requiredShotIndex);
measured = ismember((1:nShots).', plan.shotIndex);
categories = {measured & required, measured & ~required, ~measured & hasData, ~hasData};
names = ["必ず計測する Shot（指定・最外周など）", "選んで計測する Shot", "計測しない Shot（評価に使う）", ...
    "計測値の無い Shot"];
colors = [REQUIRED_COLOR; SELECTED_COLOR; UNUSED_COLOR; NO_DATA_COLOR];
edgeColors = [REQUIRED_EDGE_COLOR; EDGE_COLOR; EDGE_COLOR; EDGE_COLOR];
lineWidths = [2, 0.5, 0.5, 0.5];
cla(ax, 'reset');
legend(ax, 'off');
hold(ax, 'on');
angle = linspace(0, 2 * pi, 361);
plot(ax, waferRadiusMm * cos(angle), waferRadiusMm * sin(angle), '--', 'Color', EDGE_COLOR, 'HandleVisibility', 'off');
half = unit.shotSizeMm / 2;
legendItems = gobjects(0);
for k = 1:numel(categories)
    select = categories{k};
    if ~any(select)
        continue
    end
    patchX = shots.Xmm(select).' + [-1; 1; 1; -1] * half(1);
    patchY = shots.Ymm(select).' + [-1; -1; 1; 1] * half(2);
    legendItems(end + 1) = patch(ax, 'XData', patchX, 'YData', patchY, 'FaceColor', colors(k, :), ...
        'EdgeColor', edgeColors(k, :), 'LineWidth', lineWidths(k), ...
        'DisplayName', sprintf("%s（%d）", names(k), nnz(select))); %#ok<AGROW>
end
weights = repmat("normal", nShots, 1);
weights(measured) = "bold";
for s = 1:nShots
    text(ax, shots.Xmm(s), shots.Ymm(s), string(shots.shotNo(s)), 'FontSize', LABEL_FONT_SIZE, ...
        'FontWeight', weights(s), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'Clipping', 'on');
end
hold(ax, 'off');
axis(ax, 'equal');
limit = waferRadiusMm + MARGIN_MM;
xlim(ax, [-limit, limit]);
ylim(ax, [-limit, limit]);
xlabel(ax, 'x [mm]');
ylabel(ax, 'y [mm]');
title(ax, titleText, 'Interpreter', 'none');
box(ax, 'on');
legend(ax, legendItems, 'Location', 'eastoutside', 'Box', 'off');
end
