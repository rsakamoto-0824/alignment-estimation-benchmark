function maps = rotationMaps(variability, metric, thresholds, intervals)
%ROTATIONMAPS ばらつき（3σ）のしきい値で Shot・Mark の計測の優先度を分け、ローテーションする計測マップを作る。
%   maps = alignest.rotationMaps(variability, metric, thresholds, intervals)
%   variability：alignest.markVariability の結果。metric：優先度を分ける指標（variability.metrics の1つ。例 "sigma3Vector"）。
%   thresholds：3σ のしきい値（いくつでも。大きい順に並べ直す）。しきい値が k 個なら優先度は k + 1 段：
%   優先度 1 = しきい値 1 以上、優先度 2 = しきい値 2 以上しきい値 1 未満、…、優先度 k + 1 = しきい値 k 未満。3σ が
%   求められない点（値のある Wafer が2枚未満）は優先度 1（毎回計測）にする。
%   intervals：優先度ごとの計測の間隔（n Lot に1回。正の整数。優先度の数と同じ数）。
%   計測マップの数 M = 間隔の最小公倍数。間隔 n の優先度の Shot・Mark は、表の順（Shot の順、Shot の中は位置の順）に
%   n 組へ順に振り分け、組 g（0 始まり）を (m − 1) を n で割った余りが g の計測マップ m に入れる（n 枚に1回、どの点も
%   M 枚の中で同じ回数だけ計測し、各マップに Wafer 全体の点が散らばる）。
%   maps.table：variability.table に rank（優先度）・interval（間隔）を足した表。maps.membership：行 × M の論理値（その
%   計測マップで計測する）。maps.nMaps・mapNames（"計測マップ1" …）・rankNames（優先度の説明）・counts（マップごとの計測数）・
%   rates（全点に対する割合）・averageRate（平均の計測率）・metric・metricLabel・thresholds・intervals・level
arguments
    variability struct
    metric (1, 1) string
    thresholds double
    intervals double
end
MAX_MAPS = 24;   % 計測マップの数の上限（間隔の最小公倍数が大きすぎると、マップが多くなり運用できないため）
if ~any(variability.metrics == metric)
    error('alignest:rotationMaps', '優先度を分ける指標が正しくありません: %s', metric);
end
thresholds = sort(reshape(double(thresholds), 1, []), 'descend');
intervals = reshape(double(intervals), 1, []);
if any(~isfinite(thresholds))
    error('alignest:rotationMaps', 'しきい値は数で入れてください。');
end
if numel(intervals) ~= numel(thresholds) + 1
    error('alignest:rotationMaps', ['計測の間隔は優先度の数（しきい値の数 + 1 = %d）だけ入れてください' ...
        '（例：しきい値 1 つなら「1 3」）。'], numel(thresholds) + 1);
end
if any(~isfinite(intervals) | intervals < 1 | intervals ~= round(intervals))
    error('alignest:rotationMaps', '計測の間隔は 1 以上の整数（n Lot に1回の n）で入れてください。');
end
nMaps = 1;
for n = intervals
    nMaps = lcm(nMaps, n);
end
if nMaps > MAX_MAPS
    error('alignest:rotationMaps', ['計測マップが %d 枚になります（間隔の最小公倍数）。%d 枚以下になるように間隔を' ...
        '選んでください（例：1・2・4・8 や 1・3・6）。'], nMaps, MAX_MAPS);
end
rows = variability.table;
value = rows.(metric);
rank = 1 + sum(value < thresholds, 2);
rank(~isfinite(value)) = 1;   % ばらつきが分からない点は毎回計測する
nRows = height(rows);
membership = false(nRows, nMaps);
for r = 1:numel(intervals)
    members = find(rank == r);
    n = intervals(r);
    groupOf = mod(0:numel(members) - 1, n);
    for m = 1:nMaps
        membership(members(groupOf == mod(m - 1, n)), m) = true;
    end
end
rows.rank = rank;
rows.interval = intervals(rank).';
metricLabel = variability.metricLabels(variability.metrics == metric);
rankNames = strings(1, numel(intervals));
for r = 1:numel(intervals)
    if numel(thresholds) == 0
        range = "すべて";
    elseif r == 1
        range = sprintf("%.4g 以上", thresholds(1));
    elseif r == numel(intervals)
        range = sprintf("%.4g 未満", thresholds(end));
    else
        range = sprintf("%.4g 以上 %.4g 未満", thresholds(r), thresholds(r - 1));
    end
    frequency = "毎回";
    if intervals(r) > 1
        frequency = sprintf("%d Lot に1回", intervals(r));
    end
    rankNames(r) = sprintf("優先度 %d（%s・%s）", r, range, frequency);
end
counts = sum(membership, 1);
maps = struct("table", rows, "membership", membership, "nMaps", nMaps, ...
    "mapNames", "計測マップ" + string(1:nMaps), "rankNames", rankNames, "counts", counts, ...
    "rates", counts / max(nRows, 1), "averageRate", mean(counts) / max(nRows, 1), "metric", metric, ...
    "metricLabel", metricLabel, "thresholds", thresholds, "intervals", intervals, "level", variability.level);
end
