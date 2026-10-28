function summary = residualVsVariable(ax, variable, residual, variableLabel, titleText, unit)
%RESIDUALVSVARIABLE 残差（縦軸）と説明変数（横軸）の散布図。回帰直線と、区間ごとの平均（曲がった傾向を見る）を重ねる。
%   summary = alignest.plot.residualVsVariable(ax, variable, residual, variableLabel, titleText, unit)
%   相関係数 r と p 値（alignest.stats.correlationTest）を題名に書く。残差に説明変数の傾向が残っていなければ、
%   点は 0 のまわりに平らに散らばり、r は 0 に近く、区間ごとの平均も 0 の近くになる。
%   unit（省略可）は残差の単位（既定 "nm"）。summary は alignest.stats.correlationTest の結果。
if nargin < 6
    unit = "nm";
end
POINT_SIZE = 10;
POINT_ALPHA = 0.4;
POINT_COLOR = [0.0, 0.36, 0.67];
LINE_COLOR = [0.80, 0.22, 0.17];
BIN_COLOR = [0.10, 0.10, 0.10];
N_BINS = 12;   % 区間ごとの平均の区間の数（点の数で等分する）
variable = double(variable(:));
residual = double(residual(:));
use = isfinite(variable) & isfinite(residual);
variable = variable(use);
residual = residual(use);
summary = alignest.stats.correlationTest(variable, residual);
cla(ax, 'reset');
legend(ax, 'off');
if isempty(variable)
    title(ax, titleText + "（点がありません）", 'Interpreter', 'none');
    return
end
hold(ax, 'on');
scatter(ax, variable, residual, POINT_SIZE, POINT_COLOR, 'filled', 'MarkerFaceAlpha', POINT_ALPHA, ...
    'DisplayName', sprintf('評価点（%d）', numel(variable)));
yline(ax, 0, ':', 'Color', [0.5, 0.5, 0.5], 'HandleVisibility', 'off');
if isfinite(summary.slope)
    range = [min(variable), max(variable)];
    plot(ax, range, summary.intercept + summary.slope * range, '-', 'Color', LINE_COLOR, 'LineWidth', 1.8, ...
        'DisplayName', '回帰直線');
end
[centers, means] = binnedMeans(variable, residual, N_BINS);
if numel(centers) >= 2
    plot(ax, centers, means, '-s', 'Color', BIN_COLOR, 'MarkerFaceColor', BIN_COLOR, 'MarkerSize', 4, 'LineWidth', 1.2, ...
        'DisplayName', '区間ごとの平均');
end
hold(ax, 'off');
grid(ax, 'on');
box(ax, 'on');
xlabel(ax, variableLabel, 'Interpreter', 'none');
ylabel(ax, "残差 [" + unit + "]");
title(ax, sprintf("%s（r = %.3f、p = %s、%d 点）", titleText, summary.r, pText(summary.p), summary.n), ...
    'Interpreter', 'none');
legend(ax, 'Location', 'best', 'Box', 'off', 'FontSize', 9);
end

function [centers, means] = binnedMeans(x, y, nBins)
% 点の数で等分した区間ごとの、横軸の中央値と縦軸の平均（同じ値が多いときは区間をまとめる）
[x, order] = sort(x);
y = y(order);
edges = unique(round(linspace(0, numel(x), nBins + 1)));
centers = zeros(0, 1);
means = zeros(0, 1);
for k = 1:numel(edges) - 1
    rows = edges(k) + 1:edges(k + 1);
    if isempty(rows)
        continue
    end
    centers(end + 1, 1) = median(x(rows)); %#ok<AGROW>
    means(end + 1, 1) = mean(y(rows)); %#ok<AGROW>
end
end

function text = pText(p)
if isnan(p)
    text = "—";
elseif p < 1e-4
    text = sprintf("%.1e", p);
else
    text = sprintf("%.4f", p);
end
end
