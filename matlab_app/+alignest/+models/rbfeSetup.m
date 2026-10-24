function model = rbfeSetup(trainXY, testXY, trainFeatures, testFeatures, nRegions, log10Grid, options)
%RBFESETUP RBFe（仮）の前計算：面内を領域に分け、領域ごとの TPS をつなぎ合わせる形状関数。
%   model = alignest.models.rbfeSetup(trainXY, testXY, trainFeatures, testFeatures, nRegions, log10Grid)
%   1. 学習点の Wafer 上の位置（trainXY [mm]）を nRegions 個のまとまりに分ける（k-means。初期値は決まった選び方
%      なので、同じ学習点なら毎回同じ領域になる）。まとまりの中心が領域の中心。
%   2. 領域の半径 h は、まとまりの点の中心からの距離の最大 × options.overlap（隣の領域と重なる）。領域の学習点が
%      options.minPoints より少なければ、その数になるまで半径を広げる。
%   3. 領域ごとに、半径の中の学習点で平滑化つき TPS（alignest.models.tpsSetup、説明変数は trainFeatures）を前計算する。
%   4. つなぎ合わせる重み（1 の分割）：w_k(x) = φ(‖x − c_k‖ / h_k)、φ(t) = (1 − t)⁴(4t + 1)（t < 1、Wendland の関数）、
%      W_k = w_k / Σ_j w_j。どの領域の半径にも入らない点（外挿）は、中心が最も近い領域の重みを 1 にする。
%      推定値は f(x) = Σ_k W_k(x) f_k(x) で、領域の境目でも滑らかにつながる。
%   学習点が少なくて nRegions 個の領域にそれぞれ options.minPoints 点を取れないときは、領域の数を減らす
%   （model.nRegions が実際に使った数）。nRegions = 1 なら全体で1つの TPS と同じ。
arguments
    trainXY (:, 2) double
    testXY (:, 2) double
    trainFeatures double
    testFeatures double
    nRegions (1, 1) double {mustBeInteger, mustBePositive}
    log10Grid double
    options.overlap (1, 1) double {mustBeGreaterThan(options.overlap, 1)} = 1.5
    options.minPoints (1, 1) double {mustBeInteger, mustBePositive} = 10
end
MAX_KMEANS_ITERATIONS = 100;
nTrain = size(trainXY, 1);
nFeatures = size(trainFeatures, 2);
minPoints = min(max(options.minPoints, 3 * (nFeatures + 1)), nTrain);   % TPS の多項式部分（定数＋1次）より十分多く
nRegions = max(1, min(nRegions, floor(nTrain / minPoints)));
centers = regionCenters(trainXY, nRegions, MAX_KMEANS_ITERATIONS);
nRegions = size(centers, 1);
distanceTrain = sqrt(alignest.basis.pairwiseSquaredDiff(trainXY, centers));   % 学習点 × 領域
distanceTest = sqrt(alignest.basis.pairwiseSquaredDiff(testXY, centers));
[~, nearestTrain] = min(distanceTrain, [], 2);
radius = zeros(nRegions, 1);
for k = 1:nRegions
    members = distanceTrain(nearestTrain == k, k);
    sorted = sort(distanceTrain(:, k));
    radius(k) = max([options.overlap * max([members; 0]), sorted(minPoints) * (1 + 1e-9)]);
end
weightTrain = partitionWeights(distanceTrain, radius);
weightTest = partitionWeights(distanceTest, radius);
regions = struct("train", {}, "test", {}, "tps", {});
for k = 1:nRegions
    train = find(distanceTrain(:, k) < radius(k));
    test = find(weightTest(:, k) > 0);
    regions(k).train = train;
    regions(k).test = test;
    regions(k).tps = alignest.models.tpsSetup(trainFeatures(train, :), testFeatures(test, :), log10Grid);
end
model = struct("nRegions", nRegions, "centers", centers, "radius", radius, "weightTrain", weightTrain, ...
    "weightTest", weightTest, "regions", regions, "nTrain", nTrain, "nTest", size(testXY, 1));
end

function centers = regionCenters(points, k, maxIterations)
% 学習点の位置を k 個のまとまりに分け、その中心を返す（k-means。初期値は全体の中心に最も近い点から始め、
% 選んだ点から最も遠い点を順に足す。空になったまとまりは除く）
[~, first] = min(sum((points - mean(points, 1)).^2, 2));
centers = points(first, :);
nearest = sum((points - centers).^2, 2);
for j = 2:k
    [~, next] = max(nearest);
    centers(j, :) = points(next, :);
    nearest = min(nearest, sum((points - centers(j, :)).^2, 2));
end
for iteration = 1:maxIterations
    [~, label] = min(alignest.basis.pairwiseSquaredDiff(points, centers), [], 2);
    counts = accumarray(label, 1, [size(centers, 1), 1]);
    updated = [accumarray(label, points(:, 1), [size(centers, 1), 1]), ...
        accumarray(label, points(:, 2), [size(centers, 1), 1])] ./ counts;
    updated(counts == 0, :) = [];
    if isequal(size(updated), size(centers)) && max(abs(updated - centers), [], 'all') < 1e-9
        break
    end
    centers = updated;
end
end

function weights = partitionWeights(distance, radius)
% 1 の分割の重み（行の和が 1）。どの領域にも入らない点は、中心が最も近い領域の重みを 1 にする
t = distance ./ radius.';
weights = (1 - t).^4 .* (4 * t + 1);
weights(t >= 1) = 0;
total = sum(weights, 2);
outside = total <= 0;
if any(outside)
    [~, nearest] = min(distance(outside, :), [], 2);
    fallback = zeros(nnz(outside), size(distance, 2));
    fallback(sub2ind(size(fallback), (1:nnz(outside)).', nearest)) = 1;
    weights(outside, :) = fallback;
    total(outside) = 1;
end
weights = weights ./ total;
end
