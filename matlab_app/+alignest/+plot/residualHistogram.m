function residualHistogram(ax, residuals, titleText, unit, names)
%RESIDUALHISTOGRAM 残差のヒストグラム（確率密度）に、同じ平均・標準偏差の正規分布の曲線を重ねて描く。
%   unit（省略可）は横軸の単位（既定 "nm"）。
%   手法を比べるときは residuals を手法ごとの残差の cell 配列、names を手法の名前にする。2つ以上あると、
%   共通の区間で手法ごとの輪郭（階段の線）を重ねる（正規分布の曲線は描かず、凡例に平均・標準偏差を書く）。
if nargin < 4
    unit = "nm";
end
if iscell(residuals) && numel(residuals) >= 2
    drawSeries(ax, residuals, string(names), titleText, unit);
    return
elseif iscell(residuals)
    residuals = residuals{1};
end
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
xlabel(ax, "残差 [" + unit + "]（計測値 − 推定値）");
ylabel(ax, '確率密度');
title(ax, sprintf("%s（%d 点）", titleText, numel(values)), 'Interpreter', 'none');
grid(ax, 'on');
box(ax, 'on');
legend(ax, 'Location', 'northeast', 'Box', 'off', 'FontSize', 10);
end

function drawSeries(ax, residuals, names, titleText, unit)
% 手法ごとの残差の分布を、共通の区間の輪郭で重ねる
LINE_WIDTH = 1.8;
values = cellfun(@(r) r(isfinite(r)), residuals, 'UniformOutput', false);
allValues = vertcat(values{:});
cla(ax, 'reset');
if isempty(allValues)
    title(ax, titleText + "（評価点なし）", 'Interpreter', 'none');
    return
end
[~, edges] = histcounts(allValues);
hold(ax, 'on');
for k = 1:numel(values)
    if isempty(values{k})
        continue
    end
    histogram(ax, values{k}, edges, 'Normalization', 'pdf', 'DisplayStyle', 'stairs', 'LineWidth', LINE_WIDTH, ...
        'DisplayName', sprintf('%s（平均 %.2f、σ %.2f）', names(k), mean(values{k}), std(values{k})));
end
hold(ax, 'off');
xlabel(ax, "残差 [" + unit + "]（計測値 − 推定値）");
ylabel(ax, '確率密度');
title(ax, sprintf("%s（手法 %d 個）", titleText, numel(values)), 'Interpreter', 'none');
grid(ax, 'on');
box(ax, 'on');
legend(ax, 'Location', 'best', 'Box', 'off', 'FontSize', 9, 'Interpreter', 'none');
end
