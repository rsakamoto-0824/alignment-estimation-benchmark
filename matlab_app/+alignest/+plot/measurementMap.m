function measurementMap(ax, unit, plan, waferRadiusMm, titleText, options)
%MEASUREMENTMAP 計測マップ：Wafer 上の Shot を、学習に使う（計測する）かどうかで塗り分けて描く。
%   alignest.plot.measurementMap(ax, unit, plan, waferRadiusMm, titleText)
%   alignest.plot.measurementMap(..., showScan=true, ringRadiiMm=[67.5, 105], showLegend=false)
%   plan は alignest.planTrainingShots の結果（shotIndex：計測する Shot、requiredShotIndex：必ず計測する Shot）。
%   塗りの区分：必ず計測する Shot（太い枠）・選んで計測する Shot・計測しない Shot（評価に使う）・計測値の無い Shot。
%   色だけで区別しないよう、必ず計測する Shot は太い枠、計測する Shot の shotNo は太字にする。
%   Mark 単位の計画（plan.markIndex が空でない）では、Shot はすべて計測するので薄い塗りにし、計測する Mark を
%   塗りつぶした ●、計測しない Mark（評価に使う）を白抜きの ○ で描く。
%   options.showScan    ：Shot の内側に Scan 方向の色の枠と印（▲ 上向き・▼ 下向き）を描く（alignest.plot.scanFrames）
%   options.scanStyle   ：Scan 方向の色と向き（alignest.plot.scanStyle。設定の「表示：Scan 方向」）
%   options.ringRadiiMm ：同心円の制約の区切りの半径 [mm]（破線の円。空なら描かない）
%   options.showLegend  ：凡例を出すか（並べて描くときは1枚だけに出す）
%   options.legendLocation：凡例の位置（既定は図の右）
%   options.allCategories：Shot の無い区分も凡例の見本として描く（並べた図で1つの凡例にまとめるとき）
arguments
    ax
    unit struct
    plan struct
    waferRadiusMm (1, 1) double
    titleText (1, 1) string
    options.showScan (1, 1) logical = false
    options.ringRadiiMm double = zeros(1, 0)
    options.showLegend (1, 1) logical = true
    options.legendLocation (1, 1) string = "eastoutside"
    options.allCategories (1, 1) logical = false
    options.scanStyle struct = alignest.plot.scanStyle()
end
REQUIRED_COLOR = [0.96, 0.62, 0.25];
SELECTED_COLOR = [0.42, 0.65, 0.90];
UNUSED_COLOR = [1, 1, 1];
NO_DATA_COLOR = [0.86, 0.86, 0.86];
EDGE_COLOR = [0.45, 0.45, 0.45];
REQUIRED_EDGE_COLOR = [0.55, 0.20, 0.0];
MARK_SHOT_COLOR = [0.86, 0.92, 0.99];   % Mark 単位の計画で、計測する Shot の薄い塗り
MARK_COLOR = [0.0, 0.30, 0.62];
MARK_SIZE = 4;
SCAN_FRAME_INSET = 0.16;   % Scan 方向の枠を Shot の内側に縮める割合（塗りの枠と重ならないように）
LABEL_FONT_SIZE = 7;
MARGIN_MM = 8;
shots = unit.shots;
nShots = numel(shots.Xmm);
hasData = shots.nValidX + shots.nValidY > 0;
required = ismember((1:nShots).', plan.requiredShotIndex);
measured = ismember((1:nShots).', plan.shotIndex);
markLevel = isfield(plan, "markIndex") && ~isempty(plan.markIndex);
categories = {measured & required, measured & ~required, ~measured & hasData, ~hasData};
names = ["必ず計測する Shot（指定・最外周など）", "選んで計測する Shot", "計測しない Shot（評価に使う）", ...
    "計測値の無い Shot"];
colors = [REQUIRED_COLOR; SELECTED_COLOR; UNUSED_COLOR; NO_DATA_COLOR];
if markLevel
    names(2) = "計測する Shot（Mark を選んで計測）";
    colors(2, :) = MARK_SHOT_COLOR;
end
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
        if options.allCategories
            legendItems(end + 1) = patch(ax, 'XData', NaN, 'YData', NaN, 'FaceColor', colors(k, :), ...
                'EdgeColor', edgeColors(k, :), 'LineWidth', lineWidths(k), 'DisplayName', names(k)); %#ok<AGROW>
        end
        continue
    end
    patchX = shots.Xmm(select).' + [-1; 1; 1; -1] * half(1);
    patchY = shots.Ymm(select).' + [-1; -1; 1; 1] * half(2);
    legendItems(end + 1) = patch(ax, 'XData', patchX, 'YData', patchY, 'FaceColor', colors(k, :), ...
        'EdgeColor', edgeColors(k, :), 'LineWidth', lineWidths(k), ...
        'DisplayName', sprintf("%s（%d）", names(k), nnz(select))); %#ok<AGROW>
end
if markLevel
    % 計測する Mark（●）と、計測しない Mark（○、評価に使う）
    marks = unit.marks;
    candidate = ismember(marks.shotIndex, find(hasData)) & (marks.validX | marks.validY);
    chosen = false(numel(marks.x), 1);
    chosen(plan.markIndex) = true;
    legendItems(end + 1) = plot(ax, marks.x(chosen), marks.y(chosen), 'o', 'MarkerSize', MARK_SIZE, ...
        'MarkerFaceColor', MARK_COLOR, 'MarkerEdgeColor', MARK_COLOR, 'LineStyle', 'none', ...
        'DisplayName', sprintf("計測する Mark（%d）", nnz(chosen)));
    legendItems(end + 1) = plot(ax, marks.x(candidate & ~chosen), marks.y(candidate & ~chosen), 'o', ...
        'MarkerSize', MARK_SIZE, 'MarkerFaceColor', [1, 1, 1], 'MarkerEdgeColor', MARK_COLOR, 'LineStyle', 'none', ...
        'DisplayName', sprintf("計測しない Mark（評価に使う）（%d）", nnz(candidate & ~chosen)));
end
if options.showScan
    directions = nan(nShots, 1);
    if isfield(unit, "hasDirection") && unit.hasDirection
        directions = shots.direction;
    end
    legendItems = [legendItems, alignest.plot.scanFrames(ax, [shots.Xmm, shots.Ymm], unit.shotSizeMm, directions, ...
        SCAN_FRAME_INSET, options.scanStyle)];
end
rings = alignest.plot.zoneRings(ax, options.ringRadiiMm);
legendItems = [legendItems, rings];
weights = repmat("normal", nShots, 1);
weights(measured & ~markLevel) = "bold";
for s = 1:nShots
    if markLevel
        break   % Mark 単位の計画では Mark の印を見やすくするため shotNo を書かない
    end
    % 薄い塗りの上に書くので、ダークモードでも黒い文字のまま（Tag = keepColor）
    text(ax, shots.Xmm(s), shots.Ymm(s), string(shots.shotNo(s)), 'FontSize', LABEL_FONT_SIZE, ...
        'FontWeight', weights(s), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'Clipping', 'on', ...
        'Color', [0, 0, 0], 'Tag', 'keepColor');
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
if options.showLegend
    legend(ax, legendItems, 'Location', options.legendLocation, 'Box', 'off');
end
end
