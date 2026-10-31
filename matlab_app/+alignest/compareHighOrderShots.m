function shots = compareHighOrderShots(reference, other, options)
%COMPAREHIGHORDERSHOTS 2つの Shot 高次補正の結果の残差を Shot ごとに比べ、基準より残差が小さくなった（改善）・大きくなった
%   （悪化）Shot を決める（「7. Shot高次補正」の「2つの条件を並べる」。例：最小二乗を基準に、ロバスト回帰がよかった Shot）。
%   shots = alignest.compareHighOrderShots(reference, other)
%   shots = alignest.compareHighOrderShots(..., axis="xy", statistic="median", toleranceNm=0.1)
%   reference・other：同じ入力のデータ・Wafer で計算した alignest.shotHighOrder の result.points（点の並びが同じ表）。
%   axis："xy"（残差の大きさ √(X² + Y²)。X・Y の両方を補正した点）・"X"・"Y"（その軸の残差の大きさ）。
%   statistic：Shot の値。"median"（|残差| の中央値。外れ値の点1つに引っ張られないので、ロバスト回帰が外れ値でない点を
%   よく合わせたかが分かる）・"rms"（残差の RMS。外れ値の点の残差も大きく効く）・"max"（|残差| の最大）。
%   toleranceNm：差の大きさがこの値 [nm] 以下の Shot は「同じ」とする。
%   比べる点は、両方の結果で補正した点（残差のある点）だけ。shots は Shot ごとの表（Wafer の順、Shot の番号の順）：
%   wafer・shotNo・zone（内周・外周）・Xc・Yc（Shot 中心 [mm]）・nCompared（比べた点の数）・reference・other（Shot の値 [nm]）・
%   difference（reference − other。正なら改善）・verdict（"改善"・"悪化"・"同じ"）・downweightedReference・downweightedOther
%   （ロバスト回帰で重みを下げた点の数。外れ値とみなした点）。
arguments
    reference table
    other table
    options.axis (1, 1) string {mustBeMember(options.axis, ["xy", "X", "Y"])} = "xy"
    options.statistic (1, 1) string {mustBeMember(options.statistic, ["median", "rms", "max"])} = "median"
    options.toleranceNm (1, 1) double {mustBeNonnegative, mustBeFinite} = 0.1
end
WEIGHT_TOLERANCE = 1e-6;   % 重みがこれより 1 から下がった点を「重みを下げた点」に数える（alignest.shotHighOrder と同じ）
samePoints = height(reference) == height(other) && all(reference.wafer == other.wafer) && ...
    isequaln(reference.shotNo, other.shotNo) && isequaln(reference.x, other.x) && isequaln(reference.y, other.y);
if ~samePoints
    error('alignest:highOrderShots', ['2つの結果の点が違います（同じ入力のデータ・Wafer で計算した結果を選んで' ...
        'ください）。']);
end
[referenceValue, referenceWeight] = residualSize(reference, options.axis);
[otherValue, otherWeight] = residualSize(other, options.axis);
compared = isfinite(referenceValue) & isfinite(otherValue) & isfinite(reference.shotNo);
waferNames = unique(reference.wafer, 'stable');
[~, waferOrder] = ismember(reference.wafer, waferNames);
keys = [waferOrder(compared), reference.shotNo(compared)];
rows = find(compared);
[shotKeys, first, index] = unique(keys, 'rows');   % Wafer の順、Shot の番号の順
nShots = size(shotKeys, 1);
[referenceStat, otherStat] = deal(nan(nShots, 1));
[nCompared, downReference, downOther] = deal(zeros(nShots, 1));
for s = 1:nShots
    members = rows(index == s);
    referenceStat(s) = statisticOf(referenceValue(members), options.statistic);
    otherStat(s) = statisticOf(otherValue(members), options.statistic);
    nCompared(s) = numel(members);
    downReference(s) = nnz(referenceWeight(members) < 1 - WEIGHT_TOLERANCE);
    downOther(s) = nnz(otherWeight(members) < 1 - WEIGHT_TOLERANCE);
end
difference = referenceStat - otherStat;
verdict = repmat("同じ", nShots, 1);
verdict(difference > options.toleranceNm) = "改善";
verdict(difference < -options.toleranceNm) = "悪化";
firstRows = rows(first);
shots = table(reference.wafer(firstRows), shotKeys(:, 2), reference.zone(firstRows), ...
    reference.x(firstRows) - reference.localX(firstRows), reference.y(firstRows) - reference.localY(firstRows), ...
    nCompared, referenceStat, otherStat, difference, verdict, downReference, downOther, 'VariableNames', ["wafer", ...
    "shotNo", "zone", "Xc", "Yc", "nCompared", "reference", "other", "difference", "verdict", ...
    "downweightedReference", "downweightedOther"]);
end

function [value, weight] = residualSize(points, axisName)
% 点ごとの残差の大きさ [nm] と、ロバスト回帰の重み（X・Y の大きさのときは、どちらかの軸で重みを下げた点を下げた点とする）
switch axisName
    case "xy"
        value = hypot(points.residualX, points.residualY);
        weight = min(points.weightX, points.weightY);
    case "X"
        value = abs(points.residualX);
        weight = points.weightX;
    otherwise
        value = abs(points.residualY);
        weight = points.weightY;
end
end

function value = statisticOf(values, statistic)
switch statistic
    case "median"
        value = median(values);
    case "rms"
        value = sqrt(mean(values .^ 2));
    otherwise
        value = max(values);
end
end
