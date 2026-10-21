function summary = estimateScatter(ax, measured, estimated, categories, titleText)
%ESTIMATESCATTER 実測値（横軸）と推定値（縦軸）の散布図。y = x の線と回帰直線を引き、相関を題名に書く。
%   categories は点ごとの色分けの水準（文字列。"" だけなら1色）。水準が多すぎるときは凡例を出さない。
%   summary は alignest.scatterSummary の結果。
MAX_LEGEND_ITEMS = 20;
POINT_SIZE = 12;
POINT_ALPHA = 0.55;
valid = isfinite(measured) & isfinite(estimated);
measured = measured(valid);
estimated = estimated(valid);
categories = string(categories(valid));
summary = alignest.scatterSummary(measured, estimated);
cla(ax, 'reset');
hold(ax, 'on');
levels = unique(categories, 'stable');
numbers = str2double(levels);
if all(isfinite(numbers))
    [~, order] = sort(numbers);
    levels = levels(order);
end
colors = lines(max(numel(levels), 1));
for k = 1:numel(levels)
    select = categories == levels(k);
    name = levels(k);
    if name == ""
        name = "評価点";
    end
    scatter(ax, measured(select), estimated(select), POINT_SIZE, colors(k, :), 'filled', 'MarkerFaceAlpha', POINT_ALPHA, ...
        'DisplayName', name);
end
if ~isempty(measured)
    span = [min([measured; estimated]), max([measured; estimated])];
    span = span + [-1, 1] * 0.05 * max(diff(span), eps);
    plot(ax, span, span, '--', 'Color', [0.3, 0.3, 0.3], 'DisplayName', 'y = x');
    if isfinite(summary.slope)
        plot(ax, span, summary.intercept + summary.slope * span, '-', 'Color', [0.80, 0.22, 0.17], 'LineWidth', 1.5, ...
            'DisplayName', '回帰直線');
    end
    xlim(ax, span);
    ylim(ax, span);
end
hold(ax, 'off');
axis(ax, 'square');
grid(ax, 'on');
box(ax, 'on');
xlabel(ax, '実測値 [nm]');
ylabel(ax, '推定値 [nm]');
title(ax, sprintf("%s：r = %.3f、r² = %.3f、傾き %.3f、RMSE %.3f nm（%d 点）", titleText, summary.r, summary.r2, ...
    summary.slope, summary.rmse, summary.n), 'Interpreter', 'none');
if numel(levels) <= MAX_LEGEND_ITEMS
    legend(ax, 'Location', 'southeast', 'Box', 'off', 'FontSize', 9, 'Interpreter', 'none');
end
end
