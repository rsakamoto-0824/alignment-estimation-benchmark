function transfer = transferHighOrder(result, sources, targets, waferRadiusMm, options)
%TRANSFERHIGHORDER ほかの Wafer で求めた Shot 高次補正の補正値（k パラメータ）を、別の Wafer に当てて評価する。
%   transfer = alignest.transferHighOrder(result, sources, targets)
%   transfer = alignest.transferHighOrder(result, sources, targets, waferRadiusMm, method="coefficients")
%   result：alignest.shotHighOrder の結果（補正元・補正先の Wafer を両方含む）。sources：補正元の Wafer の名前（1つ以上）、
%   targets：補正先の Wafer の名前（1つ以上）。waferRadiusMm：Wafer RT の座標を割る Wafer 半径 [mm]（省略時 150）。
%   補正元が2枚以上のときの補正値の求め方（options.method）：
%   - "coefficients"（既定。補正値を平均する）：補正元の Wafer ごとに求めた補正値（係数）を項ごとに平均して当てる（Shot ごとの
%     k は shotNo ごと、Scan 方向ごと・行の偶奇ごとは k の組ごと。その項を持つ補正元の Wafer だけで平均する）
%   - "values"（実測値を平均する）：補正元の Wafer の計測値を、同じ Shot（shotNo）・Shot 内の位置（0.001 mm で丸める）の点
%     ごとに平均し（値のある Wafer だけで。X・Y 別）、その平均の値で result と同じ設定の補正値を求め直して当てる
%     （alignest.shotHighOrder。result.options）。最小二乗・正則化なしで、どの補正元も同じ点に値があれば、2つの求め方は同じ補正値
%   補正元が1枚なら、どちらもその Wafer の補正値。補正先の点ごとの補正量 =
%   - k の組の補正の式：Shot 内の座標 (x, y) で Σ k × x^a × y^b（Shot ごとのくくりは shotNo、ほかは k の組の名前で対応させる。
%     Shot 共通を先に引いたときの Shot ごとの k は Shot 共通の k を足した値なので、そのまま当てる）
%   - Wafer 成分：Shot 中心の座標 (Xc, Yc) で Σ 係数 × Xc^a × Yc^b（Wafer RT で補正する Shot には使わない）
%   - Wafer RT：Shot 中心の座標を Wafer 半径で割った RT モデル（alignest.basis.rtDesign）の値（RT で補正する Shot だけ）
%   補正元に k の組（Shot）が無い点は補正しない（NaN）。残差 = 補正先の計測値 − 補正量。
%   transfer.summary：補正先の Wafer・軸ごとと、すべての補正先をまとめた行（wafer = "すべての補正先"）。n（値のある点）・
%   nCorrected（補正元の k を当てられた点）・before（補正前の |平均|+3σ）・own（補正先で求めた高次補正の残差の |平均|+3σ。
%   同じ点で）・transferred（補正元の k を当てた残差の |平均|+3σ）・difference（transferred − own）・transferredP95・
%   transferredMedian（|残差| の 95% 点・中央値）[nm]
%   transfer.points：補正先の点（result.points の列に transferCorrectionX・Y、transferResidualX・Y を足す）
%   transfer.coefficients：当てた補正値（平均した係数。result.coefficients と同じ列で、wafer は補正元の説明）
%   transfer.description：補正元の説明、transfer.messages：知らせ（補正元に無い Shot・k の組など）、transfer.method：求め方
arguments
    result struct
    sources (1, :) string
    targets (1, :) string
    waferRadiusMm (1, 1) double {mustBePositive} = 150
    options.method (1, 1) string {mustBeMember(options.method, ["coefficients", "values"])} = "coefficients"
end
ALL_LABEL = "すべての補正先";
AXIS_NAMES = ["X", "Y"];
FORMULA_AXES = ["dx", "dy"];
sources = unique(sources, 'stable');
targets = unique(targets, 'stable');
waferNames = unique(result.points.wafer, 'stable');
if isempty(sources) || isempty(targets)
    error('alignest:highOrderTransfer', '補正元と補正先の Wafer を1つ以上ずつ選んでください。');
end
missing = [sources(~ismember(sources, waferNames)), targets(~ismember(targets, waferNames))];
if ~isempty(missing)
    error('alignest:highOrderTransfer', '補正の結果に無い Wafer です：%s。「補正を計算する」で計算した Wafer を選んでください。', ...
        strjoin(missing, "・"));
end
method = options.method;
options = result.options;
messages = strings(0, 1);
if numel(sources) == 1
    coefficients = averageCoefficients(result.coefficients(result.coefficients.wafer == sources, :), sources);
    description = "補正元：" + sources + " の補正値";
elseif method == "values"
    [coefficients, fitMessages] = averagedValueCoefficients(result, sources, waferRadiusMm);
    description = sprintf("補正元：%s の実測値の平均から求めた補正値（%d 枚）", strjoin(sources, "・"), numel(sources));
    messages = [messages; fitMessages];
else
    coefficients = averageCoefficients(result.coefficients(ismember(result.coefficients.wafer, sources), :), sources);
    description = sprintf("補正元：%s の補正値の平均（%d 枚）", strjoin(sources, "・"), numel(sources));
end
if any(ismember(targets, sources))
    messages(end + 1, 1) = "補正元と同じ Wafer も補正先に選んでいます（その Wafer は自分の補正値を当てた結果です）。";
end
parts = cell(numel(targets), 1);
uncorrectedKeys = strings(1, 0);
for t = 1:numel(targets)
    points = result.points(result.points.wafer == targets(t), :);
    centers = [points.x - points.localX, points.y - points.localY];
    rtUsed = false(height(points), 1);
    if ismember("waferRtUsed", string(points.Properties.VariableNames))
        rtUsed = logical(points.waferRtUsed);
    end
    [correction, residual] = deal(nan(height(points), 2));
    for a = 1:2
        axisRows = coefficients(coefficients.axis == FORMULA_AXES(a), :);
        [shotPart, known, keys] = groupPart(axisRows(axisRows.component == "Shot 高次補正", :), points, options.unit);
        uncorrectedKeys = [uncorrectedKeys, keys]; %#ok<AGROW>
        waferRows = axisRows(axisRows.component == "Wafer 成分", :);
        waferPart = zeros(height(points), 1);
        for r = 1:height(waferRows)
            waferPart = waferPart + waferRows.value(r) .* centers(:, 1) .^ waferRows.xPower(r) .* ...
                centers(:, 2) .^ waferRows.yPower(r);
        end
        waferPart(rtUsed) = 0;   % RT で補正する Shot は Wafer 成分の代わりに RT
        values = shotPart + waferPart + rtPart(coefficients, centers, rtUsed, options, waferRadiusMm, a);
        values(~known) = NaN;
        correction(:, a) = values;
        residual(:, a) = points.("value" + AXIS_NAMES(a)) - values;
    end
    points.transferCorrectionX = correction(:, 1);
    points.transferCorrectionY = correction(:, 2);
    points.transferResidualX = residual(:, 1);
    points.transferResidualY = residual(:, 2);
    parts{t} = points;
end
transferPoints = vertcat(parts{:});
uncorrectedKeys = unique(uncorrectedKeys, 'stable');
if ~isempty(uncorrectedKeys)
    messages(end + 1, 1) = "補正元に k の組が無いので補正しなかった点があります：" + strjoin(uncorrectedKeys, "・") + "。";
end
summaryParts = cell(numel(targets) + 1, 2);
for a = 1:2
    for t = 1:numel(targets)
        summaryParts{t, a} = summaryRow(targets(t), AXIS_NAMES(a), transferPoints(transferPoints.wafer == targets(t), :));
    end
    summaryParts{end, a} = summaryRow(ALL_LABEL, AXIS_NAMES(a), transferPoints);
end
summary = [vertcat(summaryParts{:, 1}); vertcat(summaryParts{:, 2})];
transfer = struct("summary", summary, "points", transferPoints, "coefficients", coefficients, "description", ...
    description, "messages", messages, "sources", sources, "targets", targets, "method", method);
end

function [coefficients, messages] = averagedValueCoefficients(result, sources, waferRadiusMm)
% 補正元の計測値を、同じ Shot・Shot 内の位置の点ごとに平均し（値のある Wafer だけ。X・Y 別）、result と同じ設定で補正値を求める
POSITION_DIGITS = 3;   % 同じ Shot 内の位置とみなす桁（0.001 mm）
parts = result.points(ismember(result.points.wafer, sources), :);
[~, first, index] = unique([parts.shotNo, round(parts.localX, POSITION_DIGITS), round(parts.localY, POSITION_DIGITS)], ...
    'rows', 'stable');
base = parts(first, :);
label = sprintf("%d 枚の実測値の平均", numel(sources));
points = table(base.source, base.name, base.shotNo, base.x - base.localX, base.y - base.localY, base.localX, ...
    base.localY, base.x, base.y, finiteMean(index, parts.valueX), finiteMean(index, parts.valueY), base.direction, ...
    base.rowParity, 'VariableNames', ["source", "name", "shotNo", "Xc", "Yc", "localX", "localY", "x", "y", "valueX", ...
    "valueY", "direction", "rowParity"]);
settings = struct("highOrder", result.options, "data", struct("waferRadiusMm", waferRadiusMm));
fit = alignest.shotHighOrder(struct("label", string(label), "points", points), settings, stages=false);
coefficients = fit.coefficients;
messages = sprintf(['補正元 %d 枚の計測値を、同じ Shot・Shot 内の位置の点ごとに平均して（値のある Wafer だけ）、補正値を' ...
    '求め直しました（%d 点）。'], numel(sources), height(points));
end

function means = finiteMean(index, values)
% 点ごとの、値のある Wafer だけの平均（どの Wafer にも値が無ければ NaN）
usable = isfinite(values);
sums = accumarray(index(usable), values(usable), [max(index), 1]);
counts = accumarray(index(usable), 1, [max(index), 1]);
means = sums ./ counts;
means(counts == 0) = NaN;
end

function averaged = averageCoefficients(rows, sources)
% 補正元の係数を項ごとに平均する（同じ成分・軸・k の組・shotNo・項・範囲の行。その行を持つ補正元だけで平均）
averaged = rows([], :);
if isempty(rows)
    return
end
shotText = string(rows.shotNo);
shotText(~isfinite(rows.shotNo)) = "";
keys = rows.component + "|" + rows.axis + "|" + rows.group + "|" + shotText + "|" + rows.term + "|" + rows.zone;
[~, first, groupIndex] = unique(keys, 'stable');
averaged = rows(first, :);
averaged.value = accumarray(groupIndex, rows.value, [], @mean);
if numel(sources) == 1
    averaged.wafer(:) = sources;
else
    averaged.wafer(:) = sprintf("%d 枚の平均", numel(sources));
end
end

function [values, known, missingKeys] = groupPart(rows, points, unit)
% k の組の補正の式の値（点ごと）。Shot ごとのくくりは shotNo、ほかは k の組の名前で補正元の係数と対応させる。
% known：補正元に k の組がある点。missingKeys：補正元に無い k の組の名前（知らせ用）
nPoints = height(points);
values = zeros(nPoints, 1);
known = false(nPoints, 1);
missingKeys = strings(1, 0);
if unit == "shot"
    pointKeys = "Shot " + string(points.shotNo);
    rowKeys = "Shot " + string(rows.shotNo);
else
    pointKeys = string(points.group);
    rowKeys = string(rows.group);
end
usable = isfinite(points.shotNo) & pointKeys ~= "" & ~ismissing(pointKeys);
for key = unique(pointKeys(usable)).'
    members = usable & pointKeys == key;
    mine = rows(rowKeys == key, :);
    if isempty(mine)
        missingKeys(end + 1) = key; %#ok<AGROW>
        continue
    end
    values(members) = points.localX(members) .^ (mine.xPower.') .* points.localY(members) .^ (mine.yPower.') * mine.value;
    known(members) = true;
end
end

function values = rtPart(coefficients, centers, rtUsed, options, waferRadiusMm, axisIndex)
% Wafer RT の補正量（RT で補正する Shot だけ。RT を使わなければ 0）
values = zeros(size(centers, 1), 1);
rtRows = coefficients(coefficients.component == "Wafer RT", :);
if isempty(rtRows) || ~any(rtUsed) || options.waferRtRange == "none"
    return
end
[basisU, basisV, names] = alignest.basis.rtDesign(centers(rtUsed, :) / waferRadiusMm, options.waferRtOrder);
[found, position] = ismember(names, rtRows.term);
coefficientValues = zeros(numel(names), 1);
coefficientValues(found) = rtRows.value(position(found));
if axisIndex == 1
    values(rtUsed) = basisU * coefficientValues;
else
    values(rtUsed) = basisV * coefficientValues;
end
end

function row = summaryRow(label, axisName, points)
% 1つの補正先（またはすべて）・軸の評価。補正元の k を当てた点と、補正先で求めた高次補正の残差がある点で比べる
values = points.("value" + axisName);
own = points.("residual" + axisName);
transferred = points.("transferResidual" + axisName);
compared = isfinite(transferred) & isfinite(own);
magnitude = abs(transferred(compared));
middle = NaN;
if ~isempty(magnitude)
    middle = median(magnitude);
end
ownValue = meanPlus3Sigma(own(compared));
transferredValue = meanPlus3Sigma(transferred(compared));
row = table(string(label), string(axisName), nnz(isfinite(values)), nnz(compared), meanPlus3Sigma(values(compared)), ...
    ownValue, transferredValue, transferredValue - ownValue, alignest.stats.percentile(magnitude, 95), middle, ...
    'VariableNames', ["wafer", "axis", "n", "nCorrected", "before", "own", "transferred", "difference", ...
    "transferredP95", "transferredMedian"]);
end

function value = meanPlus3Sigma(values)
% Overlay の代表値 |平均| + 3σ（σ は不偏標準偏差）。点が2点未満なら NaN（alignest.shotHighOrder と同じ）
values = values(isfinite(values));
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end
