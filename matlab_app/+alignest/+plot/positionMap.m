function summary = positionMap(ax, positions, meanValues, covariance, options)
%POSITIONMAP Mark の位置ごとの値の平均（矢印）と共分散楕円を、Shot 内の座標で描く（「8. Mark配置の最適化」の Shot スタックマップ）。
%   summary = alignest.plot.positionMap(ax, positions, meanValues, covariance, options)
%   positions：Mark の位置 [mm]（位置の数 × 2）、meanValues：平均 [nm]（位置の数 × 2）、covariance：[X の分散, Y の分散, X・Y の
%   共分散]（位置の数 × 3 [nm²]。alignest.plot.covarianceEllipses）。options.measured：計測する Mark（●で描く）、
%   options.shotSizeMm：Shot の大きさ（破線の枠）、options.ellipseSigma：楕円の大きさ（σ の何倍か。0 なら描かない）、
%   options.titleText：題名、options.arrowColor：矢印の色（図の地の色で見やすい色）。矢印の倍率は、矢印と楕円の大きさの 95% 点が Shot の短い辺の ARROW_RATIO 倍になるように決め、
%   長さの目安の矢印を描く。summary：scaleMmPerNm（矢印の倍率）。
arguments
    ax
    positions double
    meanValues double
    covariance double
    options.measured logical = false(0, 1)
    options.shotSizeMm (1, 2) double
    options.ellipseSigma (1, 1) double {mustBeNonnegative} = 1
    options.titleText (1, 1) string = ""
    options.arrowColor (1, 3) double = [0.05, 0.20, 0.45]
end
ARROW_RATIO = 0.18;
MARGIN_RATIO = 0.12;
REFERENCE_RATIO = 0.25;
SHOT_EDGE_COLOR = [0.45, 0.45, 0.45];
MEASURED_COLOR = [0.0, 0.45, 0.74];
REFERENCE_COLOR = [0.85, 0.33, 0.10];
cla(ax, 'reset');
legend(ax, 'off');
colorbar(ax, 'off');
hold(ax, 'on');
sizeMm = options.shotSizeMm;
half = sizeMm / 2;
plot(ax, [-1, 1, 1, -1, -1] * half(1), [-1, -1, 1, 1, -1] * half(2), '--', 'Color', SHOT_EDGE_COLOR, 'LineWidth', 1, ...
    'HandleVisibility', 'off');
usable = all(isfinite(positions), 2) & all(isfinite(meanValues), 2);
spread = sqrt(max(covariance(:, 1:2), [], 2));
spread(~isfinite(spread)) = 0;
reach = hypot(meanValues(:, 1), meanValues(:, 2)) + options.ellipseSigma * spread;
reference = sort(reach(usable));
scale = 1;
if ~isempty(reference) && reference(end) > 0
    scale = min(sizeMm) * ARROW_RATIO / reference(max(1, ceil(0.95 * numel(reference))));
end
items = gobjects(0);
if any(options.measured)
    items(end + 1) = plot(ax, positions(options.measured, 1), positions(options.measured, 2), 'o', 'MarkerSize', 6, ...
        'MarkerFaceColor', MEASURED_COLOR, 'MarkerEdgeColor', MEASURED_COLOR, 'LineStyle', 'none', 'DisplayName', '計測する Mark');
end
if any(usable)
    items(end + 1) = quiver(ax, positions(usable, 1), positions(usable, 2), meanValues(usable, 1) * scale, ...
        meanValues(usable, 2) * scale, 0, 'Color', options.arrowColor, 'LineWidth', 1.6, 'MaxHeadSize', 0.5, ...
        'DisplayName', '制御残差の平均');
    if options.ellipseSigma > 0
        tips = positions(usable, :) + meanValues(usable, :) * scale;
        ellipses = alignest.plot.covarianceEllipses(ax, tips, covariance(usable, :), options.ellipseSigma * scale);
        if ~isempty(ellipses)
            ellipses.DisplayName = sprintf('Shot 間のばらつき（%gσ 楕円）', options.ellipseSigma);
            items(end + 1) = ellipses;
        end
    end
    alignest.plot.referenceArrow(ax, [half(1) - min(sizeMm) * REFERENCE_RATIO, -half(2) - MARGIN_RATIO * max(sizeMm) * 0.35], ...
        scale, min(sizeMm) * REFERENCE_RATIO, REFERENCE_COLOR);
end
hold(ax, 'off');
axis(ax, 'equal');
margin = MARGIN_RATIO * max(sizeMm);
xlim(ax, [-half(1) - margin, half(1) + margin]);
ylim(ax, [-half(2) - margin, half(2) + margin]);
xlabel(ax, sprintf('Shot 内の X [mm]（矢印 1 nm = %.3g mm）', scale));
ylabel(ax, 'Shot 内の Y [mm]');
title(ax, options.titleText, 'Interpreter', 'none');
grid(ax, 'on');
box(ax, 'on');
if ~isempty(items)
    legend(ax, items, 'Location', 'southoutside', 'Box', 'off', 'FontSize', 9, 'Interpreter', 'none');
end
summary = struct("scaleMmPerNm", scale);
end
