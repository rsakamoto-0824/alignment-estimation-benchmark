function varianceBars(valueAx, percentAx, result, axisName, options)
%VARIANCEBARS ばらつき分解（alignest.varianceDecomposition の結果）の棒：上は段ごとの 3σ [単位]（または分散 [単位²]）の
%   積み上げ、下は分散の割合 [%] の積み上げ。
%   alignest.plot.varianceBars(valueAx, percentAx, result, axisName)
%   alignest.plot.varianceBars(..., quantity="sigma3", unitLabel="nm", showLegend=true, categoryLabels=棒の名前)
%   quantity："sigma3"（段の 3σ をそのまま積み上げ、全体の 3σ を ◆ で重ねる。3σ は足しても全体の 3σ にならないので、
%   棒の高さ（段の 3σ の和）は全体の 3σ より高い）・"variance"（段の分散の積み上げ。足すと全体の分散）。
%   棒は result.categories（横に並べる）、色は段（result.components。Lot 間・Wafer 間・Shot 間・その他。段の色は図を
%   またいで同じ）。割合の図には、5% 以上の段に割合の数字を書く。axisName：描く軸（result.axes の1つ）。
arguments
    valueAx
    percentAx
    result struct
    axisName (1, 1) string
    options.quantity (1, 1) string {mustBeMember(options.quantity, ["sigma3", "variance"])} = "sigma3"
    options.unitLabel (1, 1) string = "nm"
    options.showLegend (1, 1) logical = true
    options.categoryLabels (1, :) string = strings(1, 0)
end
COMPONENT_NAMES = ["Lot 間", "Wafer 間", "Shot 間", "その他"];
COMPONENT_COLORS = [0.49, 0.33, 0.66; 0.00, 0.45, 0.74; 0.40, 0.65, 0.20; 0.62, 0.62, 0.62];
TEXT_COLORS = [1, 1, 1; 1, 1, 1; 1, 1, 1; 0, 0, 0];   % 段の色の上で読める文字の色
TOTAL_NAME = "全体の 3σ";
TOTAL_COLOR = [0.10, 0.10, 0.10];
LABEL_MIN_PERCENT = 5;     % これより小さい段には割合の数字を書かない（重なって読めないため）
LABEL_FONT_SIZE = 10;
VALUE_FONT_SIZE = 8;
MAX_VALUE_LABELS = 12;     % 3σ の棒がこれより多いときは、段・全体の値を書かない（重なって読めないため）
VALUE_MIN_FRACTION = 0.06; % 段の 3σ が図の高さのこの割合より小さいときは、段に値を書かない（重なって読めないため）
TOTAL_MARKER_SIZE = 8;
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
totals = result.totals(result.totals.axis == axisName, :);
nCategories = numel(categories);
nComponents = numel(components);
[variances, sigmas, percents] = deal(zeros(nCategories, nComponents));
totalSigma = zeros(nCategories, 1);
for c = 1:nCategories
    for k = 1:nComponents
        row = mine(mine.category == categories(c) & mine.component == components(k), :);
        if ~isempty(row)
            variances(c, k) = row.variance(1);
            sigmas(c, k) = row.sigma3(1);
            percents(c, k) = row.percent(1);
        end
    end
    total = totals.sigma3(totals.category == categories(c));
    if ~isempty(total)
        totalSigma(c) = total(1);
    end
end
variances(~isfinite(variances)) = 0;
sigmas(~isfinite(sigmas)) = 0;
percents(~isfinite(percents)) = 0;
totalSigma(~isfinite(totalSigma)) = 0;
if options.quantity == "sigma3"
    values = sigmas;
    valueLabel = "3σ [" + options.unitLabel + "]";
    valueTitle = "段ごとの 3σ の積み上げ（" + axisName + "）";
else
    values = variances;
    valueLabel = "分散 [" + options.unitLabel + "²]";
    valueTitle = "ばらつき（分散）の内訳（" + axisName + "）";
end
axesList = [valueAx, percentAx];
data = {values, percents};
yLabels = [valueLabel, "割合 [%]"];
titles = [valueTitle, "ばらつき（分散）の割合（" + axisName + "）"];
for p = 1:2
    ax = axesList(p);
    cla(ax, 'reset');
    legend(ax, 'off');
    ax.Visible = 'on';
    if nCategories == 1
        % 1本だけのときは、空の2本目を足す（行が1つだと段ごとの棒と読まれるため）
        bars = bar(ax, [1, 2], [data{p}; nan(1, size(data{p}, 2))], 'stacked');
    else
        bars = bar(ax, 1:nCategories, data{p}, 'stacked');
    end
    for k = 1:numel(bars)
        set(bars(k), 'FaceColor', colors(k, :), 'EdgeColor', 'none', 'DisplayName', components(k));
        if nCategories <= NARROW_COUNT
            bars(k).BarWidth = NARROW_BAR_WIDTH;
        end
    end
    if p == 1 && options.quantity == "sigma3"
        drawSigmaLabels(ax, values, totalSigma, textColors, struct("markerSize", TOTAL_MARKER_SIZE, ...
            "totalColor", TOTAL_COLOR, "totalName", TOTAL_NAME, "maxLabels", MAX_VALUE_LABELS, ...
            "minFraction", VALUE_MIN_FRACTION, "fontSize", VALUE_FONT_SIZE));
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
if options.quantity == "sigma3"
    top = max([sum(values, 2); totalSigma]);
    if top > 0
        ylim(valueAx, [0, 1.08 * top]);   % 値の文字が枠からはみ出さないように
    end
end
% 割合の数字（段の真ん中）
hold(percentAx, 'on');
for c = 1:nCategories
    bottom = 0;
    for k = 1:nComponents
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
    if options.quantity == "sigma3"
        legend(valueAx, 'Location', 'eastoutside', 'Interpreter', 'none', 'Box', 'off');   % 「全体の 3σ」の印も見せる
    end
end
end

function drawSigmaLabels(ax, sigmaValues, totals, textColors, style)
% 3σ：全体の 3σ を ◆ で重ね、段の 3σ（段の真ん中）と全体の 3σ（◆ の右）の値を書く。style：印・文字の大きさと色
[nCategories, nComponents] = size(sigmaValues);
hold(ax, 'on');
plot(ax, 1:nCategories, totals, 'd', 'MarkerSize', style.markerSize, 'MarkerFaceColor', style.totalColor, ...
    'MarkerEdgeColor', [1, 1, 1], 'LineStyle', 'none', 'DisplayName', style.totalName);
if nCategories <= style.maxLabels
    height = max([sum(sigmaValues, 2); totals; eps]);
    for c = 1:nCategories
        bottom = 0;
        for k = 1:nComponents
            segment = sigmaValues(c, k);
            if segment >= style.minFraction * height
                text(ax, c, bottom + segment / 2, sprintf('%.3g', segment), 'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'middle', 'FontSize', style.fontSize, 'Color', textColors(k, :), 'HitTest', 'off');
            end
            bottom = bottom + segment;
        end
        text(ax, c + 0.12, totals(c), sprintf('全体 %.3g', totals(c)), 'HorizontalAlignment', 'left', ...
            'VerticalAlignment', 'middle', 'FontSize', style.fontSize, 'FontWeight', 'bold', ...
            'BackgroundColor', [1, 1, 1], 'Margin', 1, 'HitTest', 'off');
    end
end
hold(ax, 'off');
end
