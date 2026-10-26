function summary = residualBoxplot(ax, levels, residual, titleText, methods)
%RESIDUALBOXPLOT 質的変数の水準ごとの残差の箱ひげ図（ANOVA で比べる水準の違いを見る）。
%   summary = alignest.plot.residualBoxplot(ax, levels, residual, titleText)
%   summary = alignest.plot.residualBoxplot(ax, levels, residual, titleText, methods)   % 手法を比べる
%   levels は点ごとの水準（文字列。"" の点は除く）、residual は残差 [nm]（NaN の点は除く）。
%   箱は四分位範囲、中の線は中央値、ひげは箱から 1.5 × 四分位範囲までの点、外の点は外れ値（MATLAB の boxchart）。
%   ANOVA は平均を比べるので、水準ごとの平均を ◆ で重ねる。水準は数字なら数の順、それ以外は名前の順。
%   methods（点ごとの手法の名前）に2つ以上の手法があると、水準ごとに手法を色分けして並べる（◆ は描かない）。
%   summary は水準ごとの点数・平均・中央値の表（level・n・mean・median。手法を比べるときは method も）。
MEAN_COLOR = [0.80, 0.22, 0.17];
BOX_COLOR = [0.0, 0.36, 0.67];
MAX_LABEL_ROTATION_LEVELS = 6;   % 水準がこれより多いときは横軸の名前を斜めにする
levels = string(levels(:));
residual = double(residual(:));
use = levels ~= "" & isfinite(residual);
if nargin < 5
    methods = strings(size(levels));
end
methods = string(methods(:));
levels = levels(use);
residual = residual(use);
methods = methods(use);
names = unique(levels);
numbers = str2double(names);
if all(isfinite(numbers))
    [~, order] = sort(numbers);
    names = names(order);
end
methodNames = unique(methods, 'stable');
if numel(methodNames) >= 2
    summary = drawByMethod(ax, levels, residual, methods, names, methodNames, titleText, MAX_LABEL_ROTATION_LEVELS);
    return
end
n = arrayfun(@(name) nnz(levels == name), names);
averages = arrayfun(@(name) mean(residual(levels == name)), names);
medians = arrayfun(@(name) median(residual(levels == name)), names);
summary = table(names, n, averages, medians, 'VariableNames', ["level", "n", "mean", "median"]);
cla(ax, 'reset');
legend(ax, 'off');
if isempty(residual)
    title(ax, titleText + "（点がありません）", 'Interpreter', 'none');
    return
end
groups = categorical(levels, names, names + "（" + n + "）");
hold(ax, 'on');
boxchart(ax, groups, residual, 'BoxFaceColor', BOX_COLOR, 'MarkerColor', BOX_COLOR, 'DisplayName', '残差の分布');
plot(ax, categorical(names, names, names + "（" + n + "）"), averages, 'd', 'MarkerSize', 7, ...
    'MarkerFaceColor', MEAN_COLOR, 'MarkerEdgeColor', MEAN_COLOR, 'LineStyle', 'none', 'DisplayName', '平均');
yline(ax, 0, ':', 'Color', [0.5, 0.5, 0.5], 'HandleVisibility', 'off');   % ライト・ダークのどちらでも見える灰色
hold(ax, 'off');
grid(ax, 'on');
box(ax, 'on');
ylabel(ax, '残差 [nm]');
xlabel(ax, '水準（点数）');
if numel(names) > MAX_LABEL_ROTATION_LEVELS
    ax.XTickLabelRotation = 45;
end
title(ax, titleText, 'Interpreter', 'none');
legend(ax, 'Location', 'northeast', 'Box', 'off', 'FontSize', 9);
end

function summary = drawByMethod(ax, levels, residual, methods, names, methodNames, titleText, maxLevels)
% 水準ごとに手法を色分けして並べる（boxchart の GroupByColor）
rows = cell(0, 1);
for m = 1:numel(methodNames)
    for k = 1:numel(names)
        select = levels == names(k) & methods == methodNames(m);
        rows{end + 1, 1} = table(names(k), methodNames(m), nnz(select), mean(residual(select)), ...
            median(residual(select)), 'VariableNames', ["level", "method", "n", "mean", "median"]); %#ok<AGROW>
    end
end
summary = vertcat(rows{:});
summary = summary(summary.n > 0, :);
cla(ax, 'reset');
legend(ax, 'off');
if isempty(residual)
    title(ax, titleText + "（点がありません）", 'Interpreter', 'none');
    return
end
hold(ax, 'on');
boxchart(ax, categorical(levels, names), residual, 'GroupByColor', categorical(methods, methodNames));
yline(ax, 0, ':', 'Color', [0.5, 0.5, 0.5], 'HandleVisibility', 'off');
hold(ax, 'off');
grid(ax, 'on');
box(ax, 'on');
ylabel(ax, '残差 [nm]');
xlabel(ax, '水準');
if numel(names) > maxLevels
    ax.XTickLabelRotation = 45;
end
title(ax, titleText, 'Interpreter', 'none');
legend(ax, 'Location', 'northeast', 'Box', 'off', 'FontSize', 9, 'Interpreter', 'none');
end
