function variability = markVariability(wafers, options)
%MARKVARIABILITY Shot・Mark ごとの Wafer 間のばらつき（3σ）を求める（「8. 計測マップのローテーション」の「ばらつき」）。
%   variability = alignest.markVariability(wafers)
%   variability = alignest.markVariability(wafers, level="shot", shotStatistic="max")
%   wafers：Wafer ごとの label・points（alignest.rotationPoints の列を持つ点の表）。同じ Shot・Mark（points.key）の値を
%   Wafer 間で比べる。値は points.valueX・valueY（計測値そのまま、または選んだ入力の推定値）と points.target（目的変数）。
%   Mark ごとの値（Wafer 間の標準偏差 σ は不偏。値のある Wafer が2枚未満なら NaN）：
%   - sigma3X・sigma3Y：X・Y の 3σ
%   - sigma3Vector：ベクトルのばらつき 3√(σX² + σY²)（矢印の先のばらつき）
%   - sigma3Length：Wafer ごとの矢印の長さ |v| = √(X² + Y²) の 3σ（X・Y の両方がある Wafer で）
%   - sigma3Target：目的変数の 3σ
%   options.level："mark"（既定。Mark ごと）・"shot"（Shot ごと：Shot の中の Mark の値の代表値。options.shotStatistic が
%   "max"（既定。最も大きい Mark）か "mean"（平均））。
%   variability.table：行ごとに key・shotNo・markNo・Xc・Yc・localX・localY・x・y（Shot ごとは Shot 中心）・nWafers（X の値の
%   ある Wafer の数）・nMarks（Shot ごとの Mark の数。Mark ごとは 1）・meanX・meanY・meanTarget・sigma3X・sigma3Y・
%   sigma3Vector・sigma3Length・sigma3Target。並びは Shot（Yc の大きい順・Xc の小さい順）、Shot の中は Shot 内の位置の順。
%   variability.level・shotStatistic・nWafers（Wafer の数）・labels（Wafer の名前）・hasTarget（目的変数があるか）・
%   metrics（指標の列の名前）・metricLabels（画面に出す名前）
arguments
    wafers struct
    options.level (1, 1) string {mustBeMember(options.level, ["mark", "shot"])} = "mark"
    options.shotStatistic (1, 1) string {mustBeMember(options.shotStatistic, ["max", "mean"])} = "max"
end
METRICS = ["sigma3X", "sigma3Y", "sigma3Vector", "sigma3Length", "sigma3Target"];
METRIC_LABELS = ["X の 3σ", "Y の 3σ", "ベクトルの 3σ（3√(σX²+σY²)）", "長さ |v| の 3σ", "目的変数の 3σ"];
if isempty(wafers)
    error('alignest:rotationInput', 'ばらつきを求める Wafer がありません。');
end
parts = cell(numel(wafers), 1);
for w = 1:numel(wafers)
    p = wafers(w).points;
    parts{w} = [p(:, ["key", "shotNo", "markNo", "Xc", "Yc", "localX", "localY", "x", "y", "valueX", "valueY", ...
        "target"]), table(repmat(w, height(p), 1), 'VariableNames', "waferIndex")];
end
everything = vertcat(parts{:});
[keys, first, group] = unique(everything.key, 'stable');
nKeys = numel(keys);
values = {everything.valueX, everything.valueY, hypot(everything.valueX, everything.valueY), everything.target};
[sigmas, means] = deal(nan(nKeys, numel(values)));
for k = 1:numel(values)
    [sigmas(:, k), means(:, k)] = groupSigma(values{k}, group, nKeys);
end
counts = accumarray(group, double(isfinite(everything.valueX)), [nKeys, 1]);
geometry = everything(first, ["shotNo", "markNo", "Xc", "Yc", "localX", "localY", "x", "y"]);
marks = [table(keys, 'VariableNames', "key"), geometry, table(counts, ones(nKeys, 1), means(:, 1), means(:, 2), ...
    means(:, 4), 3 * sigmas(:, 1), 3 * sigmas(:, 2), 3 * sqrt(sigmas(:, 1) .^ 2 + sigmas(:, 2) .^ 2), 3 * sigmas(:, 3), ...
    3 * sigmas(:, 4), 'VariableNames', ["nWafers", "nMarks", "meanX", "meanY", "meanTarget", METRICS])];
marks = sortRows(marks);
if options.level == "shot"
    marks = shotRows(marks, options.shotStatistic, METRICS);
end
variability = struct("table", marks, "level", options.level, "shotStatistic", options.shotStatistic, ...
    "nWafers", numel(wafers), "labels", reshape(string({wafers.label}), 1, []), ...
    "hasTarget", any(isfinite(everything.target)), "metrics", METRICS, "metricLabels", METRIC_LABELS);
end

function [sigma, center] = groupSigma(values, group, nGroups)
% 組ごとの不偏標準偏差と平均（値のある点が2つ未満の組の σ は NaN）
usable = isfinite(values);
n = accumarray(group(usable), 1, [nGroups, 1]);
total = accumarray(group(usable), values(usable), [nGroups, 1]);
center = total ./ n;
center(n == 0) = NaN;
squares = accumarray(group(usable), (values(usable) - center(group(usable))) .^ 2, [nGroups, 1]);
sigma = sqrt(squares ./ (n - 1));
sigma(n < 2) = NaN;
end

function rows = sortRows(rows)
% Shot（Shot 中心の Y の大きい順・X の小さい順）、Shot の中は Shot 内の Y の大きい順・X の小さい順
[~, order] = sortrows([-round(rows.Yc, 3), round(rows.Xc, 3), -round(rows.localY, 3), round(rows.localX, 3)]);
rows = rows(order, :);
end

function shots = shotRows(marks, statistic, metrics)
% Shot ごとの行：Shot の中の Mark の指標の代表値（最大・平均。値の無い Mark は除く）と Shot 中心
[shotNos, first, group] = unique(marks.shotNo, 'stable');
nShots = numel(shotNos);
shots = table(string(shotNos), shotNos, nan(nShots, 1), marks.Xc(first), marks.Yc(first), zeros(nShots, 1), ...
    zeros(nShots, 1), marks.Xc(first), marks.Yc(first), accumarray(group, marks.nWafers, [nShots, 1], @max), ...
    accumarray(group, 1, [nShots, 1]), 'VariableNames', ["key", "shotNo", "markNo", "Xc", "Yc", "localX", "localY", ...
    "x", "y", "nWafers", "nMarks"]);
for name = ["meanX", "meanY", "meanTarget"]
    shots.(name) = accumarray(group, marks.(name), [nShots, 1], @meanOmit);
end
reduce = @maxOmit;
if statistic == "mean"
    reduce = @meanOmit;
end
for name = metrics
    shots.(name) = accumarray(group, marks.(name), [nShots, 1], reduce);
end
end

function value = maxOmit(values)
values = values(isfinite(values));
value = NaN;
if ~isempty(values)
    value = max(values);
end
end

function value = meanOmit(values)
values = values(isfinite(values));
value = NaN;
if ~isempty(values)
    value = mean(values);
end
end
