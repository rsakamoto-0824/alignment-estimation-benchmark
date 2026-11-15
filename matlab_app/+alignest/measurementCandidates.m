function candidates = measurementCandidates(estimates, criterion, level, count, options)
%MEASUREMENTCANDIDATES 計測を足す候補：推定誤差の大きい場所、GPR の推定の分散の大きい場所の上位 n（計測の最適化に使う）。
%   candidates = alignest.measurementCandidates(estimates, "error", "shot", 10)
%   candidates = alignest.measurementCandidates(estimates, "variance", "mark", 20, axis="X", statistic="max")
%   estimates：alignest.collectEstimates の表（評価の行を使う。学習の行は推定誤差が無いので除く）。
%   criterion："error"（推定誤差の大きさ |計測値 − 推定値|）・"variance"（GPR の推定の分散。GPR 以外は値が無い）。
%   level："shot"（shotNo ごとの場所）・"mark"（shotNo と markNo の組ごとの場所）。count：上位の数 n（1 以上）。
%   options.axis："xy"（既定。推定誤差は √(X² + Y²)、分散は X + Y。X・Y のどちらかが無い点は使わない）・"X"・"Y"
%   options.statistic："mean"（既定）・"max"：場所ごとに、その場所の点（Wafer・学習パターンのくり返し・Shot の Mark）の値を
%     平均するか、最大を取るか
%   options.exclude：候補にしない場所（shot は shotNo の数、mark は "shotNo-markNo" の文字。既に必ず計測・計測しないに
%     した場所）
%   candidates：値の大きい順の表（rank・key（shot は "12"、mark は "12-3"）・shotNo・markNo（shot は NaN）・value・nPoints
%   （使った点の数）・nWafers（Wafer の数）・x・y（場所の点の平均の座標 [mm]））。値のある場所が n より少なければその数だけ。
arguments
    estimates table
    criterion (1, 1) string {mustBeMember(criterion, ["error", "variance"])}
    level (1, 1) string {mustBeMember(level, ["shot", "mark"])}
    count (1, 1) double {mustBeInteger, mustBePositive}
    options.axis (1, 1) string {mustBeMember(options.axis, ["xy", "X", "Y"])} = "xy"
    options.statistic (1, 1) string {mustBeMember(options.statistic, ["mean", "max"])} = "mean"
    options.exclude = []
end
candidates = table(zeros(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), 'VariableNames', ["rank", "key", "shotNo", "markNo", "value", "nPoints", "nWafers", "x", "y"]);
columns = string(estimates.Properties.VariableNames);
if criterion == "variance" && ~all(ismember(["varianceX", "varianceY"], columns))
    return   % 推定の分散の無い表（以前の推定値の Excel など）
end
rows = estimates;
if any(columns == "role")
    rows = rows(rows.role == "評価", :);
end
rows = rows(isfinite(rows.shotNo), :);
value = pointValues(rows, criterion, options.axis);
keep = isfinite(value);
if level == "mark"
    keep = keep & isfinite(rows.markNo);
end
rows = rows(keep, :);
value = value(keep);
if isempty(value)
    return
end
if level == "mark"
    keys = compose("%d-%d", rows.shotNo, rows.markNo);
else
    keys = compose("%d", rows.shotNo);
end
[groupIndex, uniqueKeys] = findgroups(keys);
if options.statistic == "max"
    groupValue = splitapply(@max, value, groupIndex);
else
    groupValue = splitapply(@mean, value, groupIndex);
end
nPoints = accumarray(groupIndex, 1);
nWafers = splitapply(@(names) numel(unique(names)), string(rows.Wafer), groupIndex);
meanX = splitapply(@mean, rows.x, groupIndex);
meanY = splitapply(@mean, rows.y, groupIndex);
firstRow = splitapply(@(index) index(1), (1:height(rows)).', groupIndex);
shotNo = rows.shotNo(firstRow);
markNo = nan(numel(uniqueKeys), 1);
if level == "mark"
    markNo = rows.markNo(firstRow);
end
excluded = ismember(uniqueKeys, excludedKeys(options.exclude, level));
[~, order] = sort(groupValue, 'descend');
order = order(~excluded(order));
order = order(1:min(count, numel(order)));
candidates = table((1:numel(order)).', uniqueKeys(order), shotNo(order), markNo(order), groupValue(order), ...
    nPoints(order), nWafers(order), meanX(order), meanY(order), 'VariableNames', candidates.Properties.VariableNames);
end

function value = pointValues(rows, criterion, axisName)
% 点ごとの値：推定誤差は残差の大きさ（X・Y の大きさは √(X² + Y²)）、分散は推定の分散（X・Y の大きさは X + Y）
if criterion == "error"
    x = abs(rows.residualX);
    y = abs(rows.residualY);
    combined = hypot(x, y);
else
    x = rows.varianceX;
    y = rows.varianceY;
    combined = x + y;
end
switch axisName
    case "X"
        value = x;
    case "Y"
        value = y;
    otherwise
        value = combined;   % どちらかが NaN なら NaN（片方の軸だけの値で大きさを比べない）
end
end

function keys = excludedKeys(exclude, level)
% 候補にしない場所を key の文字にそろえる（shot は shotNo の数でも文字でもよい）
if isempty(exclude)
    keys = strings(0, 1);
elseif level == "shot" && isnumeric(exclude)
    keys = compose("%d", exclude(:));
else
    keys = string(exclude(:));
end
end
