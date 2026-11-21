function metrics = rotationMapMetrics(maps, options)
%ROTATIONMAPMETRICS 計測マップ（alignest.rotationMaps）の振り分けの良さの指標（「8. 計測Mapローテ」の振り分けの比較）。
%   metrics = alignest.rotationMapMetrics(maps)
%   metrics = alignest.rotationMapMetrics(maps, waferRadiusMm=150, designOrder=5, designFeatures="XYR")
%   どの指標も小さいほど良い。マップで計測する点（毎回計測する点を含む）の位置で求める（Shot ごとは Shot 中心）。
%   - klBetween：マップ間の KL ダイバージェンス（マップの組ごとの、両向きの平均 (KL(P‖Q) + KL(Q‖P)) / 2 の、すべての組の
%     平均。マップが1枚なら 0）。小さいほど、どのマップも点の散らばり方が似ている。
%   - klWhole：全体との KL ダイバージェンス KL(全点‖マップ) のマップの平均。小さいほど、どのマップも全点（全計測）の
%     散らばり方に近い（計測しない所が偏らない）。マップどうしが似ていても、どれも偏っていれば大きくなる。
%     点の散らばり方 P は、すべての点の位置で求めたガウスの重みの和（カーネル密度。幅 h = √(πR² / マップの平均の点の数)、
%     マップ1枚の点の間隔の目安。どの振り分けでも同じ幅）を、和が 1 になるように割ったもの（0 を避けるため小さな値を足す）。
%   - fillDistanceMm：最大の空白 [mm]（マップごとに、すべての点から最も近い計測する点までの距離の最大。マップの中で
%     最も大きい値）。小さいほど、計測しない大きな穴が無い。
%   - criterionI・criterionD：マップごとの I 基準 tr(M⁻¹)・D 基準 det(M)^(−1/p)（alignest.designCriteria。基準モデルは
%     alignest.rotationCriterionBasis。全点を計測すると I 基準 = 項の数 p、D 基準 = 1。特異なら NaN）。meanI・maxI・
%     meanD・maxD：その平均と最大（最も悪いマップ）。
%   bandwidthMm：カーネル密度の幅 h。
arguments
    maps struct
    options.waferRadiusMm (1, 1) double {mustBePositive} = 150
    options.designOrder (1, 1) double {mustBeInteger, mustBePositive} = 5
    options.designFeatures (1, 1) string = "XYR"
end
FLOOR = 1e-12;   % 散らばり方の 0 を避けるために足す値（KL の log(0) を避ける）
BLOCK_ROWS = 1000;   % 距離をまとめて求める行の数
rows = maps.table;
points = [rows.x, rows.y];
membership = maps.membership;
nMaps = size(membership, 2);
counts = sum(membership, 1);
bandwidth = sqrt(pi * options.waferRadiusMm ^ 2 / max(mean(counts), 1));
whole = spread(points, points, bandwidth, FLOOR, BLOCK_ROWS);
perMap = zeros(size(points, 1), nMaps);
fill = zeros(1, nMaps);
for m = 1:nMaps
    measured = points(membership(:, m), :);
    perMap(:, m) = spread(points, measured, bandwidth, FLOOR, BLOCK_ROWS);
    fill(m) = farthestGap(points, measured, BLOCK_ROWS);
end
klBetween = 0;
if nMaps > 1
    pairs = nchoosek(1:nMaps, 2);
    values = arrayfun(@(k) (kl(perMap(:, pairs(k, 1)), perMap(:, pairs(k, 2))) + ...
        kl(perMap(:, pairs(k, 2)), perMap(:, pairs(k, 1)))) / 2, 1:size(pairs, 1));
    klBetween = mean(values);
end
klWhole = mean(arrayfun(@(m) kl(whole, perMap(:, m)), 1:nMaps));
criterionI = nan(1, nMaps);
criterionD = nan(1, nMaps);
try
    basis = alignest.rotationCriterionBasis(points, options.waferRadiusMm, options.designOrder, options.designFeatures);
    for m = 1:nMaps
        [criterionI(m), criterionD(m)] = alignest.designCriteria({basis(membership(:, m), :)});
    end
catch
    % 点が基準モデルの項の数より少ないときは NaN のまま
end
metrics = struct("klBetween", klBetween, "klWhole", klWhole, "fillDistanceMm", max(fill), ...
    "criterionI", criterionI, "criterionD", criterionD, "meanI", mean(criterionI), "maxI", max(criterionI), ...
    "meanD", mean(criterionD), "maxD", max(criterionD), "bandwidthMm", bandwidth);
end

function density = spread(evaluation, measured, bandwidth, floor_, blockRows)
% 計測する点のガウスの重みの和を evaluation の位置で求め、和が 1 になるように割る（0 を避けて floor_ を足す）
density = zeros(size(evaluation, 1), 1);
for first = 1:blockRows:size(evaluation, 1)
    rowsInBlock = first:min(size(evaluation, 1), first + blockRows - 1);
    squared = (evaluation(rowsInBlock, 1) - measured(:, 1).') .^ 2 + (evaluation(rowsInBlock, 2) - measured(:, 2).') .^ 2;
    density(rowsInBlock) = sum(exp(-squared / (2 * bandwidth ^ 2)), 2);
end
density = density / max(sum(density), realmin) + floor_;
density = density / sum(density);
end

function gap = farthestGap(points, measured, blockRows)
% すべての点から、最も近い計測する点までの距離の最大（計測する点が無ければ Inf）
gap = Inf;
if isempty(measured)
    return
end
gap = 0;
for first = 1:blockRows:size(points, 1)
    rowsInBlock = first:min(size(points, 1), first + blockRows - 1);
    nearest = min(hypot(points(rowsInBlock, 1) - measured(:, 1).', points(rowsInBlock, 2) - measured(:, 2).'), [], 2);
    gap = max(gap, max(nearest));
end
end

function value = kl(p, q)
% KL ダイバージェンス Σ p log(p / q)
value = sum(p .* log(p ./ q));
end
