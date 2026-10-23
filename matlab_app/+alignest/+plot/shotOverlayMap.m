function scale = shotOverlayMap(ax, overlay, options)
%SHOTOVERLAYMAP すべての Shot を重ね合わせたベクトル場（Shot 内の座標）を描く。
%   個々の Shot の矢印（色は長さ |v|。右の目盛り。楕円も描くときは薄い青の単色）、Mark の位置ごとの平均の矢印
%   （黒い太い矢印）、平均の矢印の先を中心にした Shot・Wafer 間の共分散楕円（options.ellipseSigma σ。
%   色は X・Y の相関係数の絶対値。MATLAB の既定の色・右の目盛り）、
%   Shot の枠と Mark 番号を描く。Mark は数か所なので、|r| は図の中の目盛りではなく Mark 番号の横に数字で書く。
%   overlay は alignest.shotOverlay の結果。scale は使った矢印の倍率 [mm/nm]（並べる図を同じ倍率にするため）。
arguments
    ax
    overlay struct
    options.scaleMmPerNm (1, 1) double = 0      % 矢印の倍率 [mm/nm]。0 なら自動
    options.ellipseSigma (1, 1) double {mustBeNonnegative} = 1
    options.showIndividual (1, 1) logical = true
    options.titleText (1, 1) string = ""
    options.magnitudeLimit (1, 1) double {mustBeNonnegative} = 0   % 矢印の色の上限 [nm]（0 なら最大。並べる図をそろえる）
    options.showArrows (1, 1) logical = true   % false なら個々の Shot・平均の矢印を描かず、楕円だけ（中心は平均の矢印の先）
end
MEAN_COLOR = [0.0, 0.0, 0.0];
INDIVIDUAL_COLOR = [0.62, 0.74, 0.88];   % 楕円と重ねるときの個々の Shot の矢印
FRAME_COLOR = [0.45, 0.45, 0.45];
TARGET_ARROW_RATIO = 0.18;  % 自動の倍率：値の大きさの95%点が Shot の短い辺のこの割合になる
MARGIN_RATIO = 0.25;
average = overlay.average;
allPoints = vertcat(overlay.points{:});
allValues = vertcat(overlay.values{:});
half = overlay.shotSizeMm / 2;
scale = options.scaleMmPerNm;
if scale <= 0
    magnitude = sort(hypot(allValues(:, 1), allValues(:, 2)));
    magnitude = magnitude(isfinite(magnitude));
    scale = 1;
    if ~isempty(magnitude) && magnitude(end) > 0
        reference = magnitude(max(1, ceil(0.95 * numel(magnitude))));
        scale = TARGET_ARROW_RATIO * min(overlay.shotSizeMm) / max(reference, eps);
    end
end
cla(ax, 'reset');
colorbar(ax, 'off');
hold(ax, 'on');
plot(ax, [-1, 1, 1, -1, -1] * half(1), [-1, -1, 1, 1, -1] * half(2), '-', 'Color', FRAME_COLOR, 'LineWidth', 1.2, ...
    'HandleVisibility', 'off');
plot(ax, 0, 0, '+', 'Color', FRAME_COLOR, 'MarkerSize', 10, 'HandleVisibility', 'off');
legendItems = gobjects(0);
ellipses = gobjects(0);
usable = all(isfinite(allValues), 2);
if options.showArrows && options.showIndividual && any(usable)
    if options.ellipseSigma > 0
        arrows = quiver(ax, allPoints(usable, 1), allPoints(usable, 2), allValues(usable, 1) * scale, ...
            allValues(usable, 2) * scale, 0, 'Color', INDIVIDUAL_COLOR, 'LineWidth', 0.5, 'MaxHeadSize', 0.05);
    else
        arrows = alignest.plot.magnitudeArrows(ax, allPoints(usable, :), allValues(usable, :), scale, ...
            magnitudeLimit=options.magnitudeLimit, lineWidth=0.5);
    end
    if ~isempty(arrows)
        arrows.DisplayName = sprintf('個々の Shot（%d Shot）', overlay.nShots);
        legendItems(end + 1) = arrows;
    end
end
meanUsable = all(isfinite(average.mean), 2);
if options.showArrows
    legendItems(end + 1) = quiver(ax, average.points(meanUsable, 1), average.points(meanUsable, 2), ...
        average.mean(meanUsable, 1) * scale, average.mean(meanUsable, 2) * scale, 0, 'Color', MEAN_COLOR, ...
        'LineWidth', 2, 'MaxHeadSize', 0.4, 'DisplayName', '平均');
end
if options.ellipseSigma > 0
    tips = average.points(meanUsable, :) + average.mean(meanUsable, :) * scale;
    ellipses = alignest.plot.covarianceEllipses(ax, tips, average.covariance(meanUsable, :), options.ellipseSigma * scale);
    if ~isempty(ellipses)
        ellipses.LineWidth = 1.5;
        ellipses.DisplayName = sprintf('Shot・Wafer 間のばらつき（%gσ 楕円）', options.ellipseSigma);
        legendItems(end + 1) = ellipses;
    end
end
covariance = average.covariance;
correlation = abs(covariance(:, 3)) ./ sqrt(covariance(:, 1) .* covariance(:, 2));
for k = 1:size(average.points, 1)
    label = sprintf('  M%g', overlay.markLabels(k));
    if ~isempty(ellipses) && isfinite(correlation(k))
        label = sprintf('%s（|r| %.2f）', label, correlation(k));
    end
    text(ax, average.points(k, 1), average.points(k, 2), label, 'FontSize', 10, 'Color', FRAME_COLOR, ...
        'VerticalAlignment', 'top');
end
% 矢印の長さの目安（きりのよい nm）
targetMm = 0.25 * overlay.shotSizeMm(1);
raw = targetMm / scale;
candidates = [1, 2, 5, 10] * 10 ^ floor(log10(raw));
lengthNm = candidates(find(candidates <= raw, 1, 'last'));
if isempty(lengthNm)
    lengthNm = candidates(1);
end
x0 = -half(1);
y0 = -half(2) * (1 + MARGIN_RATIO / 2);
quiver(ax, x0, y0, lengthNm * scale, 0, 0, 'Color', ax.XColor, 'LineWidth', 1.5, 'MaxHeadSize', 0.6, ...
    'HandleVisibility', 'off', 'Tag', 'foreground');   % 軸と同じ色（ダークモードでは明るい色）
text(ax, x0 + lengthNm * scale + 0.5, y0, sprintf('%g nm', lengthNm), 'FontSize', 11, 'VerticalAlignment', 'middle');
hold(ax, 'off');
axis(ax, 'equal');
span = max([half; abs(average.points)], [], 1) * (1 + 2 * MARGIN_RATIO);
xlim(ax, [-span(1), span(1)]);
ylim(ax, [-span(2), span(2)]);

xlabel(ax, 'Shot 内の x [mm]（markXmm）');
ylabel(ax, 'Shot 内の y [mm]（markYmm）');
title(ax, options.titleText, 'Interpreter', 'none');
box(ax, 'on');
grid(ax, 'on');
% 右には楕円の色の目盛りを置くので、凡例は下に置く
legend(ax, legendItems, 'Location', 'southoutside', 'Box', 'off');
end
