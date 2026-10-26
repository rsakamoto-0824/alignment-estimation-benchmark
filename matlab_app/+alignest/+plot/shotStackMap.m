function summary = shotStackMap(ax, local, values, options)
%SHOTSTACKMAP Shot スタックマップ：全 Shot の Mark を Shot 内の座標（markXmm・markYmm）で1つの Shot に重ねて描く。
%   summary = alignest.plot.shotStackMap(ax, local, values, options)
%   local は点ごとの Shot 内の座標 [mm]（点数 × 2）、values は点ごとの値 [nm]（点数 × 2：X・Y）。
%   options.mode = "vector"：Shot ごとの矢印を薄い色で重ね、Mark の位置ごとの平均を濃い矢印で描く。
%   options.mode = "X"・"Y"：点ごとの値を色で描き（同じ位置の点は少しずつ横にずらす）、位置ごとの平均を
%   黒い枠の四角で描く。Shot の外形（options.shotSizeMm）を破線で描く。
%   options.scaleMmPerNm：矢印の倍率 [mm/nm]（0 なら値の大きさの95%点が Shot の短い辺の ARROW_RATIO 倍になる）。
%   options.colorLimit：色の範囲 ±[nm]（0 を中心に青・白・赤）、options.colorRange：[最小, 最大] を渡すと parula で描く
%   （1変数の計測値・推定値）。summary は位置ごとの点数・平均・標準偏差の表（localX・localY・n・meanX・meanY・stdX・stdY）。
arguments
    ax
    local double
    values double
    options.mode (1, 1) string {mustBeMember(options.mode, ["vector", "X", "Y"])} = "vector"
    options.shotSizeMm (1, 2) double = [NaN, NaN]
    options.scaleMmPerNm (1, 1) double {mustBeNonnegative} = 0
    options.colorLimit (1, 1) double = 0
    options.colorRange (1, 2) double = [NaN, NaN]
    options.colorTitle (1, 1) string = ""
    options.titleText (1, 1) string = ""
    options.markerSize (1, 1) double {mustBePositive} = 30
    options.showLegend (1, 1) logical = true
end
ARROW_RATIO = 0.18;            % 自動の倍率：大きさの95%点の矢印が Shot の短い辺のこの割合
ROUND_DIGITS = 3;              % 同じ Mark の位置とみなす Shot 内の座標の桁（mm の小数点以下）
JITTER_RATIO = 0.04;           % 色で描くとき、同じ位置の点を横にずらす幅（Shot の幅に対する割合）
SHOT_EDGE_COLOR = [0.45, 0.45, 0.45];
EACH_COLOR = [0.42, 0.62, 0.85];
MEAN_COLOR = [0.05, 0.20, 0.45];
MARGIN_RATIO = 0.12;
local = double(local);
values = double(values);
column = 1 + (options.mode == "Y");
use = all(isfinite(local), 2) & ternary(options.mode == "vector", all(isfinite(values), 2), isfinite(values(:, column)));
local = local(use, :);
values = values(use, :);
summary = positionSummary(local, values, ROUND_DIGITS);
cla(ax, 'reset');
legend(ax, 'off');
hold(ax, 'on');
sizeMm = options.shotSizeMm;
if any(~isfinite(sizeMm)) || any(sizeMm <= 0)
    sizeMm = 2 * max(abs([local; 1, 1]), [], 1);   % Shot の大きさが分からないときは点の広がり
end
half = sizeMm / 2;
plot(ax, [-1, 1, 1, -1, -1] * half(1), [-1, -1, 1, 1, -1] * half(2), '--', 'Color', SHOT_EDGE_COLOR, ...
    'LineWidth', 1, 'HandleVisibility', 'off');
items = gobjects(0);
if isempty(local)
    title(ax, options.titleText + "（点がありません）", 'Interpreter', 'none');
    hold(ax, 'off');
    return
end
if options.mode == "vector"
    scale = options.scaleMmPerNm;
    if scale <= 0
        scale = autoScale(values, min(sizeMm) * ARROW_RATIO);
    end
    items(end + 1) = quiver(ax, local(:, 1), local(:, 2), values(:, 1) * scale, values(:, 2) * scale, 0, ...
        'Color', EACH_COLOR, 'LineWidth', 0.6, 'MaxHeadSize', 0.4, ...
        'DisplayName', sprintf('Shot ごと（%d 本）', size(local, 1)));
    items(end + 1) = quiver(ax, summary.localX, summary.localY, summary.meanX * scale, summary.meanY * scale, 0, ...
        'Color', MEAN_COLOR, 'LineWidth', 2, 'MaxHeadSize', 0.5, ...
        'DisplayName', sprintf('Mark の位置ごとの平均（%d 位置）', height(summary)));
    plot(ax, summary.localX, summary.localY, 'o', 'MarkerSize', 4, 'MarkerFaceColor', MEAN_COLOR, ...
        'MarkerEdgeColor', MEAN_COLOR, 'HandleVisibility', 'off');
    xlabel(ax, sprintf('Shot 内の X [mm]（矢印 1 nm = %.3g mm）', scale));
else
    % 同じ位置の点は、位置ごとの順番で少しずつ横にずらす（重なって見えなくならないように）
    [~, ~, position] = unique(round(local, ROUND_DIGITS), 'rows');
    order = zeros(size(position));
    for p = 1:max(position)
        members = find(position == p);
        order(members) = (1:numel(members)) - (numel(members) + 1) / 2;
        order(members) = order(members) / max(numel(members), 1);
    end
    jittered = local(:, 1) + order * sizeMm(1) * JITTER_RATIO * 2;
    items(end + 1) = scatter(ax, jittered, local(:, 2), options.markerSize, values(:, column), 'filled', ...
        'MarkerEdgeColor', 'none', 'DisplayName', sprintf('Shot ごと（%d 点）', size(local, 1)));
    meanColumn = ternary(column == 1, summary.meanX, summary.meanY);
    items(end + 1) = scatter(ax, summary.localX, summary.localY - sizeMm(2) * JITTER_RATIO * 2, ...
        options.markerSize * 2.5, meanColumn, 's', 'filled', 'MarkerEdgeColor', [0, 0, 0], 'LineWidth', 1, ...
        'DisplayName', '位置ごとの平均（■、少し下に描く）');
    if all(isfinite(options.colorRange)) && options.colorRange(2) > options.colorRange(1)
        colormap(ax, parula(256));
        clim(ax, options.colorRange);
    else
        limit = options.colorLimit;
        if limit <= 0
            limit = max(abs(values(:, column)), [], 'all');
        end
        colormap(ax, alignest.plot.divergingColormap());
        clim(ax, [-1, 1] * max(limit, eps));
    end
    bar = colorbar(ax);
    axisNames = ["X", "Y"];
    bar.Title.String = ternary(options.colorTitle == "", axisNames(column) + " [nm]", options.colorTitle);
    bar.Title.Interpreter = 'none';
    xlabel(ax, 'Shot 内の X [mm]');
end
hold(ax, 'off');
ylabel(ax, 'Shot 内の Y [mm]');
axis(ax, 'equal');
margin = MARGIN_RATIO * max(sizeMm);
xlim(ax, [-half(1) - margin, half(1) + margin]);
ylim(ax, [-half(2) - margin, half(2) + margin]);
grid(ax, 'on');
box(ax, 'on');
title(ax, options.titleText, 'Interpreter', 'none');
if options.showLegend
    legend(ax, items, 'Location', 'southoutside', 'Box', 'off', 'FontSize', 9);
end
end

function summary = positionSummary(local, values, digits)
% Mark の位置（丸めた Shot 内の座標）ごとの点数・平均・標準偏差
if isempty(local)
    summary = table(zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
        'VariableNames', ["localX", "localY", "n", "meanX", "meanY", "stdX", "stdY"]);
    return
end
[positions, ~, index] = unique(round(local, digits), 'rows');
n = accumarray(index, 1);
meanX = accumarray(index, values(:, 1), [], @(v) mean(v, 'omitnan'));
meanY = accumarray(index, values(:, 2), [], @(v) mean(v, 'omitnan'));
stdX = accumarray(index, values(:, 1), [], @(v) std(v, 'omitnan'));
stdY = accumarray(index, values(:, 2), [], @(v) std(v, 'omitnan'));
summary = table(positions(:, 1), positions(:, 2), n, meanX, meanY, stdX, stdY, 'VariableNames', ...
    ["localX", "localY", "n", "meanX", "meanY", "stdX", "stdY"]);
end

function scale = autoScale(values, targetMm)
% 大きさの95%点の矢印が targetMm になる倍率
magnitude = sort(hypot(values(:, 1), values(:, 2)));
magnitude = magnitude(isfinite(magnitude));
if isempty(magnitude) || magnitude(end) <= 0
    scale = 1;
    return
end
reference = magnitude(max(1, ceil(0.95 * numel(magnitude))));
scale = targetMm / max(reference, eps);
end

function value = ternary(condition, whenTrue, whenFalse)
if condition
    value = whenTrue;
else
    value = whenFalse;
end
end
