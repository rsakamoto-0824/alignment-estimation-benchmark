function model = gamSetup(trainPoints, testPoints, featureSet, factorsTrain, factorsTest, nBasis)
%GAMSETUP 一般化加法モデル（GAM、正規分布・恒等リンク）の前計算。
%   y = β₀ + s(x, y) [+ s(r)] [+ s_周期(θ)] + Scan方向の効果 + Mark番号の効果 + ε
%   - s(x, y)   : 3次 B スプラインのテンソル積（各軸 nBasis.axis 個、[−1, 1]）。罰則は各軸の2階差分の和（P-spline）。
%   - s(r)      : 3次 B スプライン（nBasis.radius 個、[0, 1]）、2階差分の罰則。
%   - s_周期(θ) : 周期3次 B スプライン（nBasis.angle 個、[−π, π)）、周期的な2階差分の罰則。
%   - 質的変数  : 効果コード（罰則なし）。factorsTrain / factorsTest に列として渡す。
%   各平滑項は学習点での和が0になるよう制約する（mgcv と同じ QR 分解による吸収）。
%   trainPoints / testPoints は x, y, r, theta のフィールドを持つ構造体（x, y, r は Wafer 半径で割った値）。
RIDGE = 1e-9;
smooths = struct("name", {}, "build", {}, "penalty", {});
smooths(end + 1) = struct("name", "xy", "build", @(p) tensorBasis(p, nBasis.axis), ...
    "penalty", tensorPenalty(nBasis.axis));
if any(featureSet == ["XYR", "XYRT"])
    smooths(end + 1) = struct("name", "r", ...
        "build", @(p) alignest.basis.bsplineBasis(p.r, 0, 1, nBasis.radius), ...
        "penalty", alignest.basis.differencePenalty(nBasis.radius));
end
if featureSet == "XYRT"
    smooths(end + 1) = struct("name", "theta", ...
        "build", @(p) alignest.basis.cyclicBsplineBasis(p.theta, -pi, 2 * pi, nBasis.angle), ...
        "penalty", alignest.basis.differencePenalty(nBasis.angle, true));
end
if ~any(featureSet == ["XY", "XYR", "XYRT"])
    error('alignest:featureSet', '説明変数の組は XY・XYR・XYRT のいずれかです: %s', featureSet);
end
nTrain = numel(trainPoints.x);
blocksTrain = {ones(nTrain, 1), factorsTrain};
blocksTest = {ones(numel(testPoints.x), 1), factorsTest};
offset = 1 + size(factorsTrain, 2);
penalties = struct("columns", {}, "matrix", {});
ranks = zeros(1, numel(smooths));
for k = 1:numel(smooths)
    basisTrain = smooths(k).build(trainPoints);
    basisTest = smooths(k).build(testPoints);
    constraint = sum(basisTrain, 1).';
    [q, ~] = qr(constraint);
    centering = q(:, 2:end);  % 学習点での和が0になる係数空間の基底
    blocksTrain{end + 1} = basisTrain * centering; %#ok<AGROW>
    blocksTest{end + 1} = basisTest * centering; %#ok<AGROW>
    width = size(centering, 2);
    reduced = centering.' * smooths(k).penalty * centering;
    penalties(k) = struct("columns", offset + (1:width), "matrix", reduced);
    ranks(k) = rank(reduced, 1e-9 * max(abs(reduced(:))));
    offset = offset + width;
end
model.names = string({smooths.name});
model.design = [blocksTrain{:}];
model.designTest = [blocksTest{:}];
model.penalties = penalties;
model.gram = model.design.' * model.design;
model.n = nTrain;
model.nCoef = size(model.design, 2);
model.penaltyRanks = ranks;
model.nUnpenalized = model.nCoef - sum(ranks);
model.ridge = RIDGE;
if model.nUnpenalized >= model.n
    error('alignest:gamPoints', 'GAM の学習点（%d 点）が罰則のない係数の数（%d）以下です。学習 Shot を増やしてください。', ...
        model.n, model.nUnpenalized);
end
end

function basis = tensorBasis(points, nBasis)
basisX = alignest.basis.bsplineBasis(points.x, -1, 1, nBasis);
basisY = alignest.basis.bsplineBasis(points.y, -1, 1, nBasis);
basis = zeros(numel(points.x), nBasis * nBasis);
for i = 1:nBasis
    for j = 1:nBasis
        basis(:, (i - 1) * nBasis + j) = basisX(:, i) .* basisY(:, j);
    end
end
end

function penalty = tensorPenalty(nBasis)
difference = alignest.basis.differencePenalty(nBasis);
identity = eye(nBasis);
penalty = kron(difference, identity) + kron(identity, difference);
end
