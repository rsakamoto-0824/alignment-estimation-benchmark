function residualHistogram(ax, residuals, titleText, unit, names, options)
%RESIDUALHISTOGRAM 残差のヒストグラム（確率密度）に、同じ平均・標準偏差の正規分布の曲線を重ねて描く。
%   unit（省略可）は横軸の単位（既定 "nm"）。
%   手法を比べるときは residuals を手法ごとの残差の cell 配列、names を手法の名前にする。2つ以上あると、
%   共通の区間で手法ごとの輪郭（階段の線）を重ねる（正規分布の曲線は描かず、凡例に平均・標準偏差を書く）。
%   前の手法と同じ値の手法は破線にし、凡例に「＝ 〇〇と同じ」と書く（線が重なって数が減ったように見えないように）。
%   名前と値の組（省略可）：xLabelText（横軸の名前。既定は「残差 [unit]（計測値 − 推定値）」）、seriesWord（題名の
%   「手法 n 個」の「手法」）、finestBins（true なら、区間の幅を、それぞれの値だけで決めた幅のうち最も細かい幅にする。
%   補正前の値と残差のように、広がりの違う値を重ねるとき、狭い分布の形がつぶれないように）。
arguments
    ax
    residuals
    titleText (1, 1) string
    unit (1, 1) string = "nm"
    names string = strings(1, 0)
    options.xLabelText (1, 1) string = ""
    options.seriesWord (1, 1) string = "手法"
    options.finestBins (1, 1) logical = false
end
if options.xLabelText == ""
    options.xLabelText = "残差 [" + unit + "]（計測値 − 推定値）";
end
if iscell(residuals) && numel(residuals) >= 2
    drawSeries(ax, residuals, names, titleText, options);
    return
elseif iscell(residuals)
    residuals = residuals{1};
end
seriesName = "残差";
if ~isempty(names)
    seriesName = names(1);
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
    'DisplayName', seriesName);
mu = mean(values);
sigma = std(values);
if sigma > 0
    grid_ = linspace(min(values), max(values), CURVE_POINTS);
    density = exp(-0.5 * ((grid_ - mu) / sigma) .^ 2) / (sigma * sqrt(2 * pi));
    plot(ax, grid_, density, '-', 'Color', CURVE_COLOR, 'LineWidth', 2, ...
        'DisplayName', sprintf('正規分布（平均 %.3f、標準偏差 %.3f）', mu, sigma));
end
hold(ax, 'off');
xlabel(ax, options.xLabelText);
ylabel(ax, '確率密度');
title(ax, sprintf("%s（%d 点）", titleText, numel(values)), 'Interpreter', 'none');
grid(ax, 'on');
box(ax, 'on');
legend(ax, 'Location', 'northeast', 'Box', 'off', 'FontSize', 10);
end

function drawSeries(ax, residuals, names, titleText, options)
% 手法ごとの残差の分布を、共通の区間の輪郭で重ねる。色は手法ごとに決め（重ねる数によらず同じ順）、前の手法と
% 同じ値の手法（例：Y 成分だけ質的変数が違う手法の X 成分）は破線にして凡例に「＝ 〇〇と同じ」と書く
% （重なって線が1本に見えても、何本あるか分かるように）
LINE_WIDTH = 1.8;
MAX_BINS = 400;   % 最も細かい幅にするときの区間の数の上限（描く線が細かくなりすぎないように）
values = cellfun(@(r) r(isfinite(r)), residuals, 'UniformOutput', false);
allValues = vertcat(values{:});
cla(ax, 'reset');
legend(ax, 'off');
if isempty(allValues)
    title(ax, titleText + "（評価点なし）", 'Interpreter', 'none');
    return
end
[~, edges] = histcounts(allValues);
if options.finestBins
    widths = cellfun(@binWidth, values(~cellfun(@isempty, values)));
    width = max(min(widths), (max(allValues) - min(allValues)) / MAX_BINS);
    if isfinite(width) && width > 0
        edges = (floor(min(allValues) / width):ceil(max(allValues) / width)) * width;
        if numel(edges) < 2
            edges = [edges, edges(end) + width];
        end
    end
end
colors = lines(numel(values));
hold(ax, 'on');
for k = 1:numel(values)
    if isempty(values{k})
        continue
    end
    label = sprintf('%s（平均 %.2f、σ %.2f）', names(k), mean(values{k}), std(values{k}));
    style = '-';
    same = find(cellfun(@(other) isequal(sort(other), sort(values{k})), values(1:k - 1)), 1);
    if ~isempty(same)
        style = '--';
        label = label + "＝" + names(same) + " と同じ";
    end
    histogram(ax, values{k}, edges, 'Normalization', 'pdf', 'DisplayStyle', 'stairs', 'LineWidth', LINE_WIDTH, ...
        'EdgeColor', colors(k, :), 'LineStyle', style, 'DisplayName', label);
end
hold(ax, 'off');
xlabel(ax, options.xLabelText);
ylabel(ax, '確率密度');
title(ax, sprintf("%s（%s %d 個）", titleText, options.seriesWord, numel(values)), 'Interpreter', 'none');
grid(ax, 'on');
box(ax, 'on');
legend(ax, 'Location', 'northeast', 'Box', 'off', 'FontSize', 9, 'Interpreter', 'none');
end

function width = binWidth(values)
% 1つの値だけで決めた区間の幅（histcounts の既定の決め方。値が1つなら幅は決まらない）
[~, edges] = histcounts(values);
width = Inf;
if numel(values) >= 2 && numel(edges) >= 2
    width = edges(2) - edges(1);
end
end
