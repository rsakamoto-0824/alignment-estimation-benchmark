function interactionPlot(ax, sample, factorA, factorB, titleText, unit)
%INTERACTIONPLOT 交互作用の箱ひげ図：横軸に1つ目の変数の水準、その中に2つ目の変数の水準ごとの箱を色を分けて並べる。
%   alignest.plot.interactionPlot(ax, sample, factorA, factorB, titleText, unit)
%   sample は alignest.factorInteractions の samples の1つの軸（values：点ごとの値、factors：質的変数ごとの name・levels）。
%   箱は四分位（25%・75% 点）、箱の中の線は中央値、ひげは箱の端から 1.5 × 四分位範囲までの点、○ はその外の点。◆ は平均で、
%   2つ目の変数の水準ごとに同じ色の線でつなぐ（線がほぼ平行なら交互作用は小さく、交わる・開くなら交互作用がある）。
%   水準は数字なら数の順、それ以外は名前の順。値の無い点・どちらかの水準が欠けた点は使わない。unit（省略可）は縦軸の単位
%   （既定 "nm"）。
if nargin < 6
    unit = "nm";
end
MAX_LEGEND_ITEMS = 12;   % これより水準が多いときは凡例を出さない
GROUP_WIDTH = 0.8;       % 1つ目の変数の1つの水準に並べる箱の幅の合計（水準の間隔を 1 として）
BOX_FILL = 0.85;         % 箱の幅のうち、箱を描く割合（となりの箱との間をあける）
names = string({sample.factors.name});
levelsA = string(sample.factors(names == factorA).levels);
levelsB = string(sample.factors(names == factorB).levels);
values = double(sample.values(:));
use = isfinite(values) & levelsA ~= "" & ~ismissing(levelsA) & levelsB ~= "" & ~ismissing(levelsB);
cla(ax, 'reset');
legend(ax, 'off');
if ~any(use)
    title(ax, titleText + "（点がありません）", 'Interpreter', 'none');
    return
end
values = values(use);
namesA = sortLevels(unique(levelsA(use)));
namesB = sortLevels(unique(levelsB(use)));
[~, indexA] = ismember(levelsA(use), namesA);
[~, indexB] = ismember(levelsB(use), namesB);
nA = numel(namesA);
nB = numel(namesB);
width = GROUP_WIDTH / nB;
offsets = ((1:nB) - (nB + 1) / 2) * width;
colors = lines(nB);
hold(ax, 'on');
boxes = gobjects(1, nB);
for b = 1:nB
    mine = indexB == b;
    % 箱は1つずつ描く（boxchart の箱の幅は位置の間隔で決まるので、1つの位置だけにして幅をそろえる）
    for a = reshape(unique(indexA(mine)), 1, [])
        part = values(mine & indexA == a);
        boxItem = boxchart(ax, repmat(a + offsets(b), numel(part), 1), part, 'BoxWidth', BOX_FILL * width, ...
            'BoxFaceColor', colors(b, :), 'MarkerColor', colors(b, :), 'WhiskerLineColor', colors(b, :), ...
            'DisplayName', factorB + " = " + namesB(b));
        if ~isgraphics(boxes(b))
            boxes(b) = boxItem;
        else
            boxItem.HandleVisibility = 'off';
        end
    end
    means = accumarray(indexA(mine), values(mine), [nA, 1], @mean, NaN);
    present = find(isfinite(means));
    plot(ax, present + offsets(b), means(present), '-d', 'Color', colors(b, :), 'LineWidth', 1.2, 'MarkerSize', 6, ...
        'MarkerFaceColor', colors(b, :), 'MarkerEdgeColor', [0.15, 0.15, 0.15], 'HandleVisibility', 'off');
end
yline(ax, 0, ':', 'Color', [0.5, 0.5, 0.5], 'HandleVisibility', 'off');
meanItem = plot(ax, NaN, NaN, 'd', 'Color', [0.3, 0.3, 0.3], 'MarkerFaceColor', [0.3, 0.3, 0.3], ...
    'DisplayName', '平均（◆。同じ色の線でつなぐ）');
hold(ax, 'off');
xticks(ax, 1:nA);
xticklabels(ax, cellstr(namesA));
xlim(ax, [0.5, nA + 0.5]);
xlabel(ax, factorA + " の水準", 'Interpreter', 'none');
ylabel(ax, "値 [" + unit + "]（面内の傾向を除いた値）");
title(ax, titleText, 'Interpreter', 'none');
grid(ax, 'on');
box(ax, 'on');
if nB <= MAX_LEGEND_ITEMS
    legend(ax, [boxes(isgraphics(boxes)), meanItem], 'Location', 'bestoutside', 'Box', 'off', 'FontSize', 9, ...
        'Interpreter', 'none');
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
