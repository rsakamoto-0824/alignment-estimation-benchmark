function summary = valueHeatmap(ax, points, values, options)
%VALUEHEATMAP Wafer 上の点の値をヒートマップ（点の間を線形に内挿した面の色）で描く。
%   summary = alignest.plot.valueHeatmap(ax, points, values, waferRadiusMm=150, colorTitle="分散 [nm²]")
%   points：点の座標 [x, y]（mm、点数 × 2）、values：点の値（点数 × 1）。値の無い点は使わない。
%   点を結んだ三角形の中だけを線形に内挿して色を付け（外側に広げない。scatteredInterpolant の 'linear'・'none'）、
%   Wafer の外（半径 options.waferRadiusMm より外）は描かない。点の位置は小さな黒い点で重ねる。
%   面を作れない（値のある点が3点未満・一直線）ときは、点の色だけで描く。色の範囲は 0〜最大（options.colorRange で変えられる）。
%   summary.n：使った点の数、summary.interpolated：面を描いたか
arguments
    ax
    points double
    values double
    options.waferRadiusMm (1, 1) double {mustBePositive} = 150
    options.colorTitle (1, 1) string = ""
    options.titleText (1, 1) string = ""
    options.colorRange (1, 2) double = [NaN, NaN]
    options.gridCount (1, 1) double {mustBeInteger, mustBePositive} = 201
end
POINT_COLOR = [0.15, 0.15, 0.15];
EDGE_COLOR = [0.45, 0.45, 0.45];
values = values(:);
use = all(isfinite(points), 2) & isfinite(values);
points = points(use, :);
values = values(use);
summary = struct("n", numel(values), "interpolated", false);
cla(ax, 'reset');
hold(ax, 'on');
radius = options.waferRadiusMm;
angle = linspace(0, 2 * pi, 361);
plot(ax, radius * cos(angle), radius * sin(angle), '-', 'Color', EDGE_COLOR, 'HandleVisibility', 'off');
range = options.colorRange;
if any(~isfinite(range))
    range = [0, max([values; eps])];
end
if range(2) <= range(1)
    range(2) = range(1) + eps;
end
if numel(values) >= 3 && rank(points - mean(points, 1)) >= 2
    axisValues = linspace(-radius, radius, options.gridCount);
    [gridX, gridY] = meshgrid(axisValues, axisValues);
    surface = scatteredInterpolant(points(:, 1), points(:, 2), values, 'linear', 'none');
    field = surface(gridX, gridY);
    field(hypot(gridX, gridY) > radius) = NaN;   % Wafer の外は描かない
    imagesc(ax, axisValues, axisValues, field, 'AlphaData', double(isfinite(field)), 'HandleVisibility', 'off');
    summary.interpolated = true;
    plot(ax, points(:, 1), points(:, 2), '.', 'Color', POINT_COLOR, 'MarkerSize', 4, 'DisplayName', '評価点');
else
    scatter(ax, points(:, 1), points(:, 2), 30, values, 'filled', 'DisplayName', '評価点');
end
hold(ax, 'off');
ax.YDir = 'normal';   % imagesc は y を下向きにするので、Wafer の座標（上が +y）に戻す
colormap(ax, parula);
clim(ax, range);
bar = colorbar(ax);
bar.Label.String = options.colorTitle;
axis(ax, 'equal');
xlim(ax, [-1, 1] * radius * 1.05);
ylim(ax, [-1, 1] * radius * 1.05);
xlabel(ax, 'x [mm]');
ylabel(ax, 'y [mm]');
title(ax, options.titleText, 'Interpreter', 'none');
grid(ax, 'on');
box(ax, 'on');
end
