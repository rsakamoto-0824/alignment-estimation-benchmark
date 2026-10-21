function residualHistogram(ax, residuals, titleText)
%RESIDUALHISTOGRAM 残差のヒストグラム（確率密度）に、同じ平均・標準偏差の正規分布の曲線を重ねて描く。
BAR_COLOR = [0.0, 0.36, 0.67];
CURVE_COLOR = [0.80, 0.22, 0.17];
CURVE_POINTS = 200;
values = residuals(isfinite(residuals));
cla(ax, 'reset');
if isempty(values)
    title(ax, titleText + "（評価点なし）", 'Interpreter', 'none');
    return
end
hold(ax, 'on');
histogram(ax, values, 'Normalization', 'pdf', 'FaceColor', BAR_COLOR, 'FaceAlpha', 0.55, 'EdgeColor', 'w', ...
    'DisplayName', '残差');
mu = mean(values);
sigma = std(values);
if sigma > 0
    grid_ = linspace(min(values), max(values), CURVE_POINTS);
    density = exp(-0.5 * ((grid_ - mu) / sigma) .^ 2) / (sigma * sqrt(2 * pi));
    plot(ax, grid_, density, '-', 'Color', CURVE_COLOR, 'LineWidth', 2, ...
        'DisplayName', sprintf('正規分布（平均 %.3f、標準偏差 %.3f）', mu, sigma));
end
hold(ax, 'off');
xlabel(ax, '残差 [nm]（計測値 − 推定値）');
ylabel(ax, '確率密度');
title(ax, sprintf("%s（%d 点）", titleText, numel(values)), 'Interpreter', 'none');
grid(ax, 'on');
box(ax, 'on');
legend(ax, 'Location', 'northeast', 'Box', 'off', 'FontSize', 10);
end
