function maps = rotationMaps(variability, metric, thresholds, nMaps, options)
%ROTATIONMAPS ばらつき（3σ）のしきい値で Shot・Mark の計測の優先度を分け、ローテーションする計測マップを作る。
%   maps = alignest.rotationMaps(variability, metric, thresholds, nMaps)
%   maps = alignest.rotationMaps(..., thresholdKind="percent", outerRadiusMm=135, assignment="random", seed=0, ...
%       priorityShotNos=[12, 40], waferRadiusMm=150, designOrder=5, designFeatures="XYR")
%   variability：alignest.markVariability の結果。metric：優先度を分ける指標（variability.metrics の1つ。例 "sigma3Length"）。
%   thresholds：しきい値（いくつでも。大きい順に並べ直す）。thresholdKind："value"（既定。3σ の値）・"percent"（指標の分布の
%   累積 n% の値をしきい値にする。n は 0 より大きく 100 より小さい。値は Excel の PERCENTILE.INC と同じ
%   alignest.stats.percentile。例：75 なら 3σ の大きい上位 25% がしきい値以上）。しきい値が k 個なら優先度は k + 1 段：
%   優先度 1 = しきい値 1 以上、優先度 2 = しきい値 2 以上しきい値 1 未満、…、優先度 k + 1 = しきい値 k 未満。3σ が
%   求められない点（値のある Wafer が2枚未満）は優先度 1（毎回計測）にする。
%   outerRadiusMm：Wafer 中心からの半径がこの値 [mm] 以上の点（Shot ごとのときは Shot 中心）は、3σ によらず優先度 1 にする
%   （NaN = 使わない）。
%   priorityShotNos：この shotNo の点（Mark ごとのときは、その Shot のすべての Mark）は、3σ によらず優先度 1 にする
%   （任意の Shot を毎回計測にする。空 = 使わない。表に無い shotNo は maps.missingShotNos に返す）。
%   nMaps：計測マップの数 M（1〜24 の整数）。優先度ごとの計測の頻度（n 枚に1回の n。maps.intervals）は M から決める：
%   優先度 1 は毎回（n = 1）、最も低い優先度は M 枚に1回（n = M）。優先度が3段以上なら、間の優先度の n は M の約数から、
%   1 と M の間を等比に分けた値に最も近いものを選ぶ（例：M = 6・3段なら 1・2・6）。しきい値が無いときはすべて優先度 1
%   （毎回）。頻度 n の優先度の Shot・Mark を n 組に振り分け、組 g（0 始まり）を (m − 1) を n で割った余りが g の
%   計測マップ m に入れる（n 枚に1回、どの点も M 枚の中で同じ回数だけ計測する）。振り分け方
%   assignment："order"（既定。表の順（Shot の順、Shot の中は位置の順）に 1, 2, …, n 組と順に振る。各マップに Wafer 全体の
%   点が散らばる）・"random"（乱数で並べ替えてから順に振る。組の点の数は同じ（差は 1 以内）。seed：乱数の種。同じ種なら
%   同じ振り分け）・"poisson"（ポアソンディスクサンプリングのように、組ごとに点どうしが離れて Wafer 全体に散らばるよう
%   振る：乱数で並べた順に組を 1, 2, …, n と順に回り、その組の点から最も離れた（組の点までの最短距離が最も大きい）
%   まだ振っていない点を、その組に入れ、続けて近くの点どうしの組の入れ替えで、同じ組の近い点を減らす（同じ組の近くの
%   点ほど大きくなる値 exp(−d²/2s²) の和を小さくする。s = 点の最短距離の中央値 × √n）。組の点の数の差は 1 以内。
%   同じ種なら同じ振り分け。画面の初期値）・"ioptimal"・"doptimal"（ポアソンディスクの振り分けから始め、同じ頻度の違う組の2点を入れ替えて、すべての計測マップの
%   I 基準 tr(M⁻¹)・D 基準 det(M)^(−1/p) の和を小さくする。alignest.rotationCriterionExchange。M は計測マップで計測する
%   点の情報行列。基準モデルは designOrder 次の多項式（designFeatures："XYR"・"XY"。座標は waferRadiusMm で割る）を
%   全点で正規直交化したもの（alignest.designCriteria と同じ。Shot ごとのときは Shot 中心の点で求める））。
%   頻度 1 の優先度（毎回計測）は振り分けない。
%   maps.table：variability.table に rank（優先度）・interval（n 枚に1回の n）・outer（半径で優先度 1 にした点）・specified（shotNo の
%   指定で優先度 1 にした点）を足した表。
%   maps.membership：行 × M の論理値（その計測マップで計測する）。maps.nMaps・mapNames（"計測マップ1" …）・rankNames（優先度の
%   説明）・counts（マップごとの計測数）・rates（全点に対する割合）・averageRate（平均の計測率）・metric・metricLabel・
%   thresholds（しきい値の 3σ の値。大きい順）・thresholdKind・thresholdPercents（累積 % のときの n。値のときは空）・
%   outerRadiusMm・priorityShotNos（指定した shotNo）・missingShotNos（指定のうち表に無い shotNo）・assignment・seed・
%   intervals（優先度ごとの n 枚に1回の n）・level
arguments
    variability struct
    metric (1, 1) string
    thresholds double
    nMaps double
    options.thresholdKind (1, 1) string {mustBeMember(options.thresholdKind, ["value", "percent"])} = "value"
    options.outerRadiusMm (1, 1) double = NaN
    options.assignment (1, 1) string {mustBeMember(options.assignment, ...
        ["order", "random", "poisson", "ioptimal", "doptimal"])} = "order"
    options.seed (1, 1) double = 0
    options.priorityShotNos double = zeros(1, 0)
    options.waferRadiusMm (1, 1) double {mustBePositive} = 150
    options.designOrder (1, 1) double {mustBeInteger, mustBePositive} = 5
    options.designFeatures (1, 1) string = "XYR"
end
MAX_MAPS = 24;   % 計測マップの数の上限（マップが多すぎると運用できないため）
if ~any(variability.metrics == metric)
    error('alignest:rotationMaps', '優先度を分ける指標が正しくありません: %s', metric);
end
thresholds = sort(reshape(double(thresholds), 1, []), 'descend');
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
priorityShotNos = unique(reshape(double(options.priorityShotNos), 1, []), 'stable');
if any(~isfinite(priorityShotNos) | priorityShotNos ~= round(priorityShotNos))
    error('alignest:rotationMaps', '優先度 1 にする Shot は shotNo（整数）を空白で区切って入れてください（例：12 40）。');
end
if ~isempty(priorityShotNos) && ~any(string(rows.Properties.VariableNames) == "shotNo")
    error('alignest:rotationMaps', 'ばらつきの表に shotNo が無いので、優先度 1 にする Shot を指定できません。');
end
if ~isscalar(nMaps) || ~isfinite(nMaps) || nMaps < 1 || nMaps ~= round(nMaps) || nMaps > MAX_MAPS
    error('alignest:rotationMaps', '計測マップの数は 1〜%d の整数で入れてください。', MAX_MAPS);
end
intervals = rankIntervals(nMaps, numel(thresholds) + 1);
rank = 1 + sum(value < thresholds, 2);
rank(~isfinite(value)) = 1;   % ばらつきが分からない点は毎回計測する
outer = false(height(rows), 1);
if ~isnan(outerRadius)
    outer = hypot(rows.x, rows.y) >= outerRadius;
    rank(outer) = 1;   % 外周の点は 3σ によらず毎回計測する（優先度 1）
end
specified = false(height(rows), 1);
missingShotNos = zeros(1, 0);
if ~isempty(priorityShotNos)
    specified = ismember(rows.shotNo, priorityShotNos);
    rank(specified) = 1;   % 指定した Shot は 3σ によらず毎回計測する（優先度 1）
    missingShotNos = priorityShotNos(~ismember(priorityShotNos, rows.shotNo));
end
nRows = height(rows);
stream = RandStream('mt19937ar', 'Seed', options.seed);
% 点ごとの組（0 始まり。頻度 n の優先度の点を n 組に分ける。毎回計測する点は 0）
groupOf = zeros(nRows, 1);
points = [rows.x, rows.y];
for r = 1:numel(intervals)
    members = find(rank == r);
    n = intervals(r);
    if n == 1 || isempty(members)
        continue
    end
    switch options.assignment
        case {"poisson", "ioptimal", "doptimal"}
            groups = poissonGroups(points(members, :), n, stream);   % I・D 最適は、ここから入れ替えで良くする
        case "random"
            groups = zeros(1, numel(members));
            groups(randperm(stream, numel(members))) = mod(0:numel(members) - 1, n);   % 振り分ける順を乱数で決める
        otherwise
            groups = mod(0:numel(members) - 1, n);
    end
    groupOf(members) = groups;
end
interval = reshape(intervals(rank), [], 1);   % 点ごとの頻度（優先度が1段でも列にする）
if any(options.assignment == ["ioptimal", "doptimal"]) && any(interval > 1)
    basis = alignest.rotationCriterionBasis(points, options.waferRadiusMm, options.designOrder, options.designFeatures);
    groupOf = alignest.rotationCriterionExchange(basis, interval, groupOf, nMaps, ...
        upper(extractBefore(options.assignment, 2)), stream);
end
membership = mod(repmat(0:nMaps - 1, nRows, 1), interval) == groupOf;   % 計測マップ m は組 (m − 1) mod n を計測する
rows.rank = rank;
rows.interval = interval;
rows.outer = outer;
rows.specified = specified;
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
    if r == 1 && any(specified)
        range = range + "、指定した Shot";
    end
    frequency = "毎回";
    if intervals(r) > 1
        frequency = sprintf("%d 枚に1回", intervals(r));
    end
    rankNames(r) = sprintf("優先度 %d（%s・%s）", r, range, frequency);
end
counts = sum(membership, 1);
maps = struct("table", rows, "membership", membership, "nMaps", nMaps, ...
    "mapNames", "計測マップ" + string(1:nMaps), "rankNames", rankNames, "counts", counts, ...
    "rates", counts / max(nRows, 1), "averageRate", mean(counts) / max(nRows, 1), "metric", metric, ...
    "metricLabel", metricLabel, "thresholds", thresholds, "thresholdKind", options.thresholdKind, ...
    "thresholdPercents", percents, "outerRadiusMm", outerRadius, "priorityShotNos", priorityShotNos, ...
    "missingShotNos", missingShotNos, "assignment", options.assignment, "seed", options.seed, ...
    "intervals", intervals, "level", variability.level);
end

function intervals = rankIntervals(nMaps, nRanks)
% 優先度ごとの計測の頻度（n 枚に1回の n）：優先度 1 は毎回、最も低い優先度は nMaps 枚に1回。間の優先度は、nMaps の約数
% （どの点も nMaps 枚の中で同じ回数だけ計測するため）から、1 と nMaps の間を等比に分けた値に最も近いもの（同じ近さなら
% 小さい方。前の優先度より小さくしない）。優先度が1段（しきい値なし）ならすべて毎回
TIE_TOLERANCE = 1e-9;   % 約数 d と nMaps / d は等比の真ん中から同じ近さ。計算の誤差で大きい方を選ばないように
intervals = ones(1, nRanks);
if nRanks < 2
    return
end
divisors = find(mod(nMaps, 1:nMaps) == 0);
intervals(nRanks) = nMaps;
for r = 2:nRanks - 1
    target = nMaps ^ ((r - 1) / (nRanks - 1));
    allowed = divisors(divisors >= intervals(r - 1));
    distance = abs(log(allowed) - log(target));
    intervals(r) = allowed(find(distance <= min(distance) + TIE_TOLERANCE, 1));   % 同じ近さなら小さい方（多く計測する）
end
end

function groupOf = poissonGroups(points, nGroups, stream)
% 点を nGroups 組（0 始まりの組の番号）に分ける。ポアソンディスクサンプリングのように、組ごとに点どうしが離れて Wafer
% 全体に散らばるよう、乱数で並べた順に組を順に回り、その組の点までの最短距離が最も大きい、まだ分けていない点を入れる
% （組にまだ点が無いときは、乱数の順で先の点。同じ距離なら乱数の順で先の点）。各組の点の数の差は 1 以内
nPoints = size(points, 1);
groupOf = zeros(1, nPoints);
if nPoints == 0
    return
end
order = randperm(stream, nPoints);
points0 = points;
points = points(order, :);
nearest = inf(nGroups, nPoints);   % 組 g の点までの最短距離
free = true(1, nPoints);
assigned = zeros(1, nPoints);
for step = 0:nPoints - 1
    group = mod(step, nGroups) + 1;
    candidates = find(free);
    [~, best] = max(nearest(group, candidates));
    pick = candidates(best);
    free(pick) = false;
    assigned(pick) = group - 1;
    distance = hypot(points(:, 1) - points(pick, 1), points(:, 2) - points(pick, 2)).';
    nearest(group, :) = min(nearest(group, :), distance);
end
groupOf(order) = assigned;
groupOf = refineGroups(points0, groupOf, nGroups);
end

function groupOf = refineGroups(points, groupOf, nGroups)
% 近くの点どうし（K 近傍）の組を入れ替えて、同じ組の近い点を減らす（組の点の数は変わらない）。入れ替えると、同じ組の
% 近くの点ほど大きくなる値 exp(−d²/2s²)（d：距離、s：点の最短距離の中央値 × √組の数）の和が小さくなるときだけ入れ替え、
% 入れ替えが無くなるまで（最大 MAX_SWEEPS 回）繰り返す
NEIGHBOR_EXTRA = 4;   % 近傍の数 K = 4 × 組の数 + 4（組の数が多いほど、同じ組の点は遠くにあるため）
MAX_SWEEPS = 30;
BLOCK_ROWS = 500;     % 距離をまとめて求める行の数（点が多いときに大きな表を作らないように）
nPoints = size(points, 1);
nNeighbors = min(nPoints - 1, NEIGHBOR_EXTRA * nGroups + NEIGHBOR_EXTRA);
if nNeighbors < 1
    return
end
neighbors = zeros(nPoints, nNeighbors);
distances = zeros(nPoints, nNeighbors);
for first = 1:BLOCK_ROWS:nPoints
    rowsInBlock = first:min(nPoints, first + BLOCK_ROWS - 1);
    block = hypot(points(rowsInBlock, 1) - points(:, 1).', points(rowsInBlock, 2) - points(:, 2).');
    block(sub2ind(size(block), 1:numel(rowsInBlock), rowsInBlock)) = Inf;   % 自分自身は近傍にしない
    [distances(rowsInBlock, :), neighbors(rowsInBlock, :)] = mink(block, nNeighbors, 2);
end
% 近傍は両向きにする（i が j の近傍なら j も i の近傍）
self = repmat((1:nPoints).', 1, nNeighbors);
pairs = unique([self(:), neighbors(:), distances(:); neighbors(:), self(:), distances(:)], 'rows');
spread = max(median(distances(:, 1)) * sqrt(nGroups), eps);
weights = exp(-pairs(:, 3) .^ 2 / (2 * spread ^ 2));
% 点ごとの近傍と重みを、行 = 点の表にする（足りない所は近傍 0・重み 0）。pairs は 1 列目の順に並んでいる
degree = accumarray(pairs(:, 1), 1, [nPoints, 1]);
starts = cumsum([1; degree(1:end - 1)]);
slot = (1:size(pairs, 1)).' - starts(pairs(:, 1)) + 1;
near = zeros(nPoints, max(degree));
weightOf = zeros(nPoints, max(degree));
near(sub2ind(size(near), pairs(:, 1), slot)) = pairs(:, 2);
weightOf(sub2ind(size(near), pairs(:, 1), slot)) = weights;
groupOf = reshape(groupOf, [], 1);
for sweep = 1:MAX_SWEEPS
    swapped = false;
    for i = 1:nPoints
        nearI = near(i, 1:degree(i));
        weightI = weightOf(i, 1:degree(i));
        for k = 1:degree(i)
            j = nearI(k);
            [gi, gj] = deal(groupOf(i), groupOf(j));
            if gi == gj
                continue
            end
            nearJ = near(j, 1:degree(j));
            weightJ = weightOf(j, 1:degree(j));
            groupsI = groupOf(nearI).';
            groupsJ = groupOf(nearJ).';
            before = sum(weightI(groupsI == gi)) + sum(weightJ(groupsJ == gj));
            after = sum(weightI(groupsI == gj & nearI ~= j)) + sum(weightJ(groupsJ == gi & nearJ ~= i));
            if after < before - 1e-12
                groupOf([i, j]) = [gj; gi];
                swapped = true;
            end
        end
    end
    if ~swapped
        break
    end
end
groupOf = reshape(groupOf, 1, []);
end

function text = percentText(percents, index)
% 累積 % のしきい値なら「（累積 n%）」を添える
text = "";
if ~isempty(percents)
    text = sprintf("（累積 %g%%）", percents(index));
end
end
