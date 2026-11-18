function varianceBars(varianceAx, percentAx, result, axisName, options)
%VARIANCEBARS ばらつき分解（alignest.varianceDecomposition の結果）の積み上げ棒：分散 [単位²] と、割合 [%]。
%   alignest.plot.varianceBars(varianceAx, percentAx, result, axisName)
%   alignest.plot.varianceBars(..., unitLabel="nm", showLegend=true, categoryLabels=棒の名前)
%   棒は result.categories（横に並べる）、色は段（result.components。Lot 間・Wafer 間・Scan 方向間・Shot 間・その他。
%   段の色は図をまたいで同じ）。割合の図には、5% 以上の段に割合の数字を書く。axisName：描く軸（result.axes の1つ）。
arguments
    varianceAx
    percentAx
    result struct
    axisName (1, 1) string
    options.unitLabel (1, 1) string = "nm"
    options.showLegend (1, 1) logical = true
    options.categoryLabels (1, :) string = strings(1, 0)
end
COMPONENT_NAMES = ["Lot 間", "Wafer 間", "Scan 方向間", "Shot 間", "その他"];
COMPONENT_COLORS = [0.49, 0.33, 0.66; 0.00, 0.45, 0.74; 0.93, 0.62, 0.13; 0.40, 0.65, 0.20; 0.62, 0.62, 0.62];
TEXT_COLORS = [1, 1, 1; 1, 1, 1; 0, 0, 0; 1, 1, 1; 0, 0, 0];   % 段の色の上で読める文字の色
LABEL_MIN_PERCENT = 5;     % これより小さい段には割合の数字を書かない（重なって読めないため）
LABEL_FONT_SIZE = 10;
NARROW_BAR_WIDTH = 0.45;   % 棒が少ない（2本以下）ときの棒の幅（図の幅いっぱいに太くならないように）
NARROW_COUNT = 2;
MAX_FLAT_LABELS = 4;       % 棒がこれより多いときは横軸の名前を斜めにする
LABEL_ROTATION = 30;
categories = result.categories;
labels = options.categoryLabels;
if isempty(labels)
    labels = categories;
end
components = result.components;
[~, colorIndex] = ismember(components, COMPONENT_NAMES);
colors = COMPONENT_COLORS(max(colorIndex, 1), :);
textColors = TEXT_COLORS(max(colorIndex, 1), :);
mine = result.table(result.table.axis == axisName, :);
nCategories = numel(categories);
[variances, percents] = deal(zeros(nCategories, numel(components)));
for c = 1:nCategories
    for k = 1:numel(components)
        row = mine(mine.category == categories(c) & mine.component == components(k), :);
        if ~isempty(row)
            variances(c, k) = row.variance(1);
            percents(c, k) = row.percent(1);
        end
    end
end
variances(~isfinite(variances)) = 0;
percents(~isfinite(percents)) = 0;
axesList = [varianceAx, percentAx];
data = {variances, percents};
yLabels = ["分散 [" + options.unitLabel + "²]", "割合 [%]"];
titles = ["ばらつき（分散）の内訳（" + axisName + "）", "ばらつきの割合（" + axisName + "）"];
for p = 1:2
    ax = axesList(p);
    cla(ax, 'reset');
    legend(ax, 'off');
    ax.Visible = 'on';
    if nCategories == 1
        % 1本だけのときは、空の2本目を足して積み上げにする（行が1つだと段ごとの棒と読まれるため）
        bars = bar(ax, [1, 2], [data{p}; nan(1, numel(components))], 'stacked');
    else
        bars = bar(ax, 1:nCategories, data{p}, 'stacked');
    end
    for k = 1:numel(bars)
        set(bars(k), 'FaceColor', colors(k, :), 'EdgeColor', 'none', 'DisplayName', components(k));
        if nCategories <= NARROW_COUNT
            bars(k).BarWidth = NARROW_BAR_WIDTH;
        end
    end
    xlim(ax, [0.4, nCategories + 0.6]);
    xticks(ax, 1:nCategories);
    xticklabels(ax, cellstr(labels));
    ax.TickLabelInterpreter = 'none';
    if nCategories > MAX_FLAT_LABELS
        ax.XTickLabelRotation = LABEL_ROTATION;
    else
        ax.XTickLabelRotation = 0;
    end
    ylabel(ax, yLabels(p));
    title(ax, titles(p), 'Interpreter', 'none');
    grid(ax, 'on');
    box(ax, 'on');
end
ylim(percentAx, [0, 100]);
% 割合の数字（段の真ん中）
hold(percentAx, 'on');
for c = 1:nCategories
    bottom = 0;
    for k = 1:numel(components)
        segment = percents(c, k);
        if segment >= LABEL_MIN_PERCENT
            text(percentAx, c, bottom + segment / 2, sprintf('%.0f%%', segment), 'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', 'FontSize', LABEL_FONT_SIZE, 'Color', textColors(k, :), 'HitTest', 'off');
        end
        bottom = bottom + segment;
    end
end
hold(percentAx, 'off');
if options.showLegend
    legend(percentAx, 'Location', 'eastoutside', 'Interpreter', 'none', 'Box', 'off');
end
end
