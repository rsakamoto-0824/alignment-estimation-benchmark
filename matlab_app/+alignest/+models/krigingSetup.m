function model = krigingSetup(trainFeatures, testFeatures, krigingType, variogramName, nLags)
%KRIGINGSETUP 通常 Kriging（ordinary）と Universal Kriging（universal）の前計算。
%   - 通常      ：ドリフトは定数（未知の平均）。経験バリオグラムは計測値そのもので求める。
%   - Universal ：ドリフトは説明変数の1次式 [1, z]。経験バリオグラムはドリフトを最小二乗で除いた残差で求める。
%   経験バリオグラムは PyKrige と同じく、最小〜最大距離を nLags 等分した区間の平均（最後の端は +0.001）。
if nargin < 5
    nLags = 6;
end
krigingType = string(krigingType);
variogramName = string(variogramName);
if ~any(krigingType == ["ordinary", "universal"])
    error('alignest:krigingType', 'Kriging の種類は ordinary・universal のいずれかです: %s', krigingType);
end
n = size(trainFeatures, 1);
model.krigingType = krigingType;
model.variogramName = variogramName;
model.n = n;
model.distance = sqrt(alignest.basis.pairwiseSquaredDiff(trainFeatures, trainFeatures));
model.distanceTest = sqrt(alignest.basis.pairwiseSquaredDiff(testFeatures, trainFeatures));
if krigingType == "ordinary"
    model.drift = ones(n, 1);
    model.driftTest = ones(size(testFeatures, 1), 1);
else
    model.drift = [ones(n, 1), trainFeatures];
    model.driftTest = [ones(size(testFeatures, 1), 1), testFeatures];
end
mask = triu(true(n), 1);
[model.pairI, model.pairJ] = find(mask);
model.pairDistance = model.distance(mask);
minimum = min(model.pairDistance);
maximum = max(model.pairDistance);
edges = minimum + (maximum - minimum) / nLags * (0:nLags);
edges(end) = maximum + 0.001;
model.pairBin = discretize(model.pairDistance, edges);
model.nLags = nLags;
model.driftBasis = [];
if krigingType == "universal"
    [q, ~] = qr(model.drift, 0);
    model.driftBasis = q;
end
end
