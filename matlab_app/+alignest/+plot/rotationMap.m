function rotationMap(ax, maps, mapIndex, options)
%ROTATIONMAP 1つの計測マップ（alignest.rotationMaps）を Wafer 上に描く：計測する Shot・Mark を優先度の色の点、計測しない
%   Shot・Mark を灰色の白抜きの点で描く（Shot ごとのマップは Shot 中心）。
%   alignest.plot.rotationMap(ax, maps, mapIndex)
%   alignest.plot.rotationMap(..., waferRadiusMm=150, shotCenters=[x, y], shotSizeMm=[幅, 高さ], showLegend=true, ...
%       circleRadiiMm=[120, 140])   % 半径 [mm] の円を重ねる（alignest.plot.radiusCircles。空なら描かない）
arguments
    ax
    maps struct
    mapIndex (1, 1) double
    options.waferRadiusMm (1, 1) double = 150
    options.shotCenters double = zeros(0, 2)
    options.shotSizeMm (1, 2) double = [NaN, NaN]
    options.showLegend (1, 1) logical = true
    options.markerSize (1, 1) double = 22
    options.circleRadiiMm double = zeros(1, 0)
end
RANK_COLORS = [0.85, 0.20, 0.15; 0.93, 0.60, 0.10; 0.20, 0.55, 0.80; 0.35, 0.65, 0.30; 0.55, 0.40, 0.70; 0.45, 0.45, 0.45];
SKIPPED_COLOR = [0.65, 0.65, 0.65];
EDGE_COLOR = [0.45, 0.45, 0.45];
MARGIN_MM = 8;
cla(ax, 'reset');
legend(ax, 'off');
hold(ax, 'on');
angle = linspace(0, 2 * pi, 361);
plot(ax, options.waferRadiusMm * cos(angle), options.waferRadiusMm * sin(angle), '--', 'Color', EDGE_COLOR, ...
    'HandleVisibility', 'off');
alignest.plot.shotFrames(ax, options.shotCenters, options.shotSizeMm);
rows = maps.table;
measured = maps.membership(:, mapIndex);
items = gobjects(0);
skipped = ~measured;
if any(skipped)
    items(end + 1) = scatter(ax, rows.x(skipped), rows.y(skipped), options.markerSize, 'o', ...
        'MarkerEdgeColor', SKIPPED_COLOR, 'DisplayName', "計測しない（" + nnz(skipped) + "）");
end
for r = 1:numel(maps.rankNames)
    mine = measured & rows.rank == r;
    if ~any(mine)
        continue
    end
    color = RANK_COLORS(min(r, size(RANK_COLORS, 1)), :);
    items(end + 1) = scatter(ax, rows.x(mine), rows.y(mine), options.markerSize, color, 'filled', ...
        'DisplayName', "優先度 " + r + "（" + nnz(mine) + "）"); %#ok<AGROW>
end
items = [items, alignest.plot.radiusCircles(ax, options.circleRadiiMm)];
hold(ax, 'off');
axis(ax, 'equal');
limit = options.waferRadiusMm + MARGIN_MM;
xlim(ax, [-limit, limit]);
ylim(ax, [-limit, limit]);
xlabel(ax, 'x [mm]');
ylabel(ax, 'y [mm]');
title(ax, sprintf('%s（計測 %d / %d・%.0f%%）', maps.mapNames(mapIndex), nnz(measured), numel(measured), ...
    100 * nnz(measured) / max(numel(measured), 1)), 'Interpreter', 'none');
box(ax, 'on');
if options.showLegend && ~isempty(items)
    legend(ax, items, 'Location', 'southoutside', 'NumColumns', min(numel(items), 3), 'Box', 'off', 'Interpreter', 'none');
end
end
