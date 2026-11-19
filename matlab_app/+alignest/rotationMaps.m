function maps = rotationMaps(variability, metric, thresholds, intervals, options)
%ROTATIONMAPS ばらつき（3σ）のしきい値で Shot・Mark の計測の優先度を分け、ローテーションする計測マップを作る。
%   maps = alignest.rotationMaps(variability, metric, thresholds, intervals)
%   maps = alignest.rotationMaps(..., thresholdKind="percent", outerRadiusMm=135, assignment="random", seed=0)
%   variability：alignest.markVariability の結果。metric：優先度を分ける指標（variability.metrics の1つ。例 "sigma3Vector"）。
%   thresholds：しきい値（いくつでも。大きい順に並べ直す）。thresholdKind："value"（既定。3σ の値）・"percent"（指標の分布の
%   累積 n% の値をしきい値にする。n は 0 より大きく 100 より小さい。値は Excel の PERCENTILE.INC と同じ
%   alignest.stats.percentile。例：75 なら 3σ の大きい上位 25% がしきい値以上）。しきい値が k 個なら優先度は k + 1 段：
%   優先度 1 = しきい値 1 以上、優先度 2 = しきい値 2 以上しきい値 1 未満、…、優先度 k + 1 = しきい値 k 未満。3σ が
%   求められない点（値のある Wafer が2枚未満）は優先度 1（毎回計測）にする。
%   outerRadiusMm：Wafer 中心からの半径がこの値 [mm] 以上の点（Shot ごとのときは Shot 中心）は、3σ によらず優先度 1 にする
%   （NaN = 使わない）。
%   intervals：優先度ごとの計測の間隔（n Lot に1回。正の整数。優先度の数と同じ数）。
%   計測マップの数 M = 間隔の最小公倍数。間隔 n の優先度の Shot・Mark を n 組に振り分け、組 g（0 始まり）を (m − 1) を n で
%   割った余りが g の計測マップ m に入れる（n 枚に1回、どの点も M 枚の中で同じ回数だけ計測する）。振り分け方
%   assignment："order"（既定。表の順（Shot の順、Shot の中は位置の順）に 1, 2, …, n 組と順に振る。各マップに Wafer 全体の
%   点が散らばる）・"random"（乱数で並べ替えてから順に振る。組の点の数は同じ（差は 1 以内）。seed：乱数の種。同じ種なら
%   同じ振り分け）。間隔 1 の優先度（毎回計測）は振り分けない。
%   maps.table：variability.table に rank（優先度）・interval（間隔）・outer（半径で優先度 1 にした点）を足した表。
%   maps.membership：行 × M の論理値（その計測マップで計測する）。maps.nMaps・mapNames（"計測マップ1" …）・rankNames（優先度の
%   説明）・counts（マップごとの計測数）・rates（全点に対する割合）・averageRate（平均の計測率）・metric・metricLabel・
%   thresholds（しきい値の 3σ の値。大きい順）・thresholdKind・thresholdPercents（累積 % のときの n。値のときは空）・
%   outerRadiusMm・assignment・seed・intervals・level
arguments
    variability struct
    metric (1, 1) string
    thresholds double
    intervals double
    options.thresholdKind (1, 1) string {mustBeMember(options.thresholdKind, ["value", "percent"])} = "value"
    options.outerRadiusMm (1, 1) double = NaN
    options.assignment (1, 1) string {mustBeMember(options.assignment, ["order", "random"])} = "order"
    options.seed (1, 1) double = 0
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
percents = zeros(1, 0);
rows = variability.table;
value = rows.(metric);
if options.thresholdKind == "percent"
    if any(thresholds <= 0 | thresholds >= 100)
        error('alignest:rotationMaps', '累積 %s のしきい値は 0 より大きく 100 より小さい数で入れてください（例：75）。', '%');
    end
    percents = thresholds;
    thresholds = arrayfun(@(p) alignest.stats.percentile(value(isfinite(value)), p), percents);
    if any(~isfinite(thresholds))
        error('alignest:rotationMaps', '3σ の値が無いので、累積 %s のしきい値を決められません。', '%');
    end
end
outerRadius = options.outerRadiusMm;
if ~isnan(outerRadius) && ~(isfinite(outerRadius) && outerRadius >= 0)
    error('alignest:rotationMaps', '優先度 1 にする外周の半径は 0 以上の数 [mm] で入れてください。');
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
rank = 1 + sum(value < thresholds, 2);
rank(~isfinite(value)) = 1;   % ばらつきが分からない点は毎回計測する
outer = false(height(rows), 1);
if ~isnan(outerRadius)
    outer = hypot(rows.x, rows.y) >= outerRadius;
    rank(outer) = 1;   % 外周の点は 3σ によらず毎回計測する（優先度 1）
end
nRows = height(rows);
membership = false(nRows, nMaps);
stream = RandStream('mt19937ar', 'Seed', options.seed);
for r = 1:numel(intervals)
    members = find(rank == r);
    n = intervals(r);
    if options.assignment == "random" && n > 1
        members = members(randperm(stream, numel(members)));   % 振り分ける順を乱数で決める
    end
    groupOf = mod(0:numel(members) - 1, n);
    for m = 1:nMaps
        membership(members(groupOf == mod(m - 1, n)), m) = true;
    end
end
rows.rank = rank;
rows.interval = intervals(rank).';
rows.outer = outer;
metricLabel = variability.metricLabels(variability.metrics == metric);
rankNames = strings(1, numel(intervals));
for r = 1:numel(intervals)
    if numel(thresholds) == 0
        range = "すべて";
    elseif r == 1
        range = sprintf("%.4g 以上", thresholds(1)) + percentText(percents, 1);
    elseif r == numel(intervals)
        range = sprintf("%.4g 未満", thresholds(end)) + percentText(percents, numel(percents));
    else
        range = sprintf("%.4g 以上 %.4g 未満", thresholds(r), thresholds(r - 1));
    end
    if r == 1 && ~isnan(outerRadius)
        range = range + sprintf("、半径 %g mm 以上", outerRadius);
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
    "metricLabel", metricLabel, "thresholds", thresholds, "thresholdKind", options.thresholdKind, ...
    "thresholdPercents", percents, "outerRadiusMm", outerRadius, "assignment", options.assignment, "seed", options.seed, ...
    "intervals", intervals, "level", variability.level);
end

function text = percentText(percents, index)
% 累積 % のしきい値なら「（累積 n%）」を添える
text = "";
if ~isempty(percents)
    text = sprintf("（累積 %g%%）", percents(index));
end
end
