function interactionPlot(ax, cells, factorA, factorB, titleText, unit)
%INTERACTIONPLOT 交互作用の図：横軸に1つ目の変数の水準、2つ目の変数の水準ごとの平均を線でつなぐ。
%   alignest.plot.interactionPlot(ax, cells, factorA, factorB, titleText, unit)
%   cells は alignest.stats.interactionTests の水準の組の平均（factorA・factorB・levelA・levelB・n・mean）。
%   線がほぼ平行なら交互作用は小さく（効果を足し合わせて表せる）、交わる・開くなら交互作用がある。
%   水準は数字なら数の順、それ以外は名前の順。unit（省略可）は縦軸の単位（既定 "nm"）。
if nargin < 6
    unit = "nm";
end
MAX_LEGEND_ITEMS = 12;   % これより水準が多いときは凡例を出さない（線だけ）
rows = cells(cells.factorA == factorA & cells.factorB == factorB, :);
cla(ax, 'reset');
legend(ax, 'off');
if height(rows) == 0
    title(ax, titleText + "（点がありません）", 'Interpreter', 'none');
    return
end
levelsA = sortLevels(unique(rows.levelA));
levelsB = sortLevels(unique(rows.levelB));
hold(ax, 'on');
colors = lines(numel(levelsB));
for b = 1:numel(levelsB)
    part = rows(rows.levelB == levelsB(b), :);
    [~, position] = ismember(part.levelA, levelsA);
    [position, order] = sort(position);
    plot(ax, position, part.mean(order), '-o', 'Color', colors(b, :), 'LineWidth', 1.5, 'MarkerSize', 6, ...
        'MarkerFaceColor', colors(b, :), 'DisplayName', factorB + " = " + levelsB(b));
end
yline(ax, 0, ':', 'Color', [0.5, 0.5, 0.5], 'HandleVisibility', 'off');
hold(ax, 'off');
xticks(ax, 1:numel(levelsA));
xticklabels(ax, cellstr(levelsA));
xlim(ax, [0.5, numel(levelsA) + 0.5]);
xlabel(ax, factorA + " の水準", 'Interpreter', 'none');
ylabel(ax, "平均 [" + unit + "]（面内の傾向を除いた値）");
title(ax, titleText, 'Interpreter', 'none');
grid(ax, 'on');
box(ax, 'on');
if numel(levelsB) <= MAX_LEGEND_ITEMS
    legend(ax, 'Location', 'bestoutside', 'Box', 'off', 'FontSize', 9, 'Interpreter', 'none');
end
end

function levels = sortLevels(levels)
levels = string(levels(:));
numbers = str2double(levels);
if all(isfinite(numbers))
    [~, order] = sort(numbers);
    levels = levels(order);
else
    levels = sort(levels);
end
end
