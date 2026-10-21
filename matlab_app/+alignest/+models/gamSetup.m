function model = gamSetup(trainPoints, testPoints, featureSet, factorsTrain, factorsTest, nBasis, options)
%GAMSETUP 一般化加法モデル（GAM、正規分布・恒等リンク）の前計算。
%   y = β₀ + s(x, y) [+ s(r)] + 質的変数の効果 + ε
%   形状関数（平滑項）は項ごとに、スプライン（既定）かガウス過程回帰を選ぶ（options.shapes.xy・r = "spline"・"gp"）。
%   スプライン
%   - s(x, y)   : 3次 B スプラインのテンソル積（各軸 nBasis.axis 個、[−1, 1]）。罰則は各軸の2階差分の和（P-spline）。
%   - s(r)      : 3次 B スプライン（nBasis.radius 個、[0, 1]）、2階差分の罰則。
%   ガウス過程回帰（Matérn 5/2 カーネル、長さスケール options.lengthScales.<項>、Wafer 半径で割った単位）
%   - 節点 κ でのカーネルによる低ランクの近似：s(z) = 線形部分 + Σ_k b_k k(z, κ_k)、罰則 bᵀK(κ, κ)b（λ と組で
%     事前分布 b ~ N(0, σ²/λ·K⁻¹) のガウス過程と同じ）。線形部分（x・y、r）は罰則なし（スプラインの2階差分と同じ）。
%   - 節点：s(x, y) は [−1, 1]² の options.gpGridKnots × 同数の格子のうち Wafer の内側（半径 1 + 格子の間隔 以下）、
%     s(r) は [0, 1] の options.gpKnots 点。
%   - 質的変数  : 効果コード（罰則なし）。factorsTrain / factorsTest に列として渡す。
%   各平滑項は学習点での和が0になるよう制約する（mgcv と同じ QR 分解による吸収）。
%   trainPoints / testPoints は x, y, r のフィールドを持つ構造体（Wafer 半径で割った値）。
%   model.logPseudoDetPenalty は罰則行列の擬似行列式の対数の和（長さスケールの違う模型の REML を比べるときに使う）。
arguments
    trainPoints struct
    testPoints struct
    featureSet (1, 1) string
    factorsTrain double
    factorsTest double
    nBasis struct
    options.shapes struct = struct()
    options.lengthScales struct = struct()
    options.gpKnots (1, 1) double {mustBeInteger, mustBeGreaterThanOrEqual(options.gpKnots, 3)} = 10
    options.gpGridKnots (1, 1) double {mustBeInteger, mustBeGreaterThanOrEqual(options.gpGridKnots, 3)} = 7
end
RIDGE = 1e-9;
DEFAULT_LENGTH_SCALE = 0.3;
if ~any(featureSet == ["XY", "XYR"])
    error('alignest:featureSet', '説明変数の組は XY・XYR のいずれかです: %s', featureSet);
end
shape = @(name) shapeOf(options.shapes, name);
lengthScale = @(name) valueOr(options.lengthScales, name, DEFAULT_LENGTH_SCALE);
smooths = struct("name", {}, "build", {}, "penalty", {});
if shape("xy") == "gp"
    smooths(end + 1) = gpSmooth("xy", @(p) [p.x(:), p.y(:)], gridKnots(options.gpGridKnots), @(p) [p.x(:), p.y(:)], 2, ...
        lengthScale("xy"));
else
    smooths(end + 1) = struct("name", "xy", "build", @(p) tensorBasis(p, nBasis.axis), ...
        "penalty", tensorPenalty(nBasis.axis));
end
if featureSet == "XYR"
    if shape("r") == "gp"
        smooths(end + 1) = gpSmooth("r", @(p) p.r(:), linspace(0, 1, options.gpKnots).', @(p) p.r(:), 1, lengthScale("r"));
    else
        smooths(end + 1) = struct("name", "r", ...
            "build", @(p) alignest.basis.bsplineBasis(p.r, 0, 1, nBasis.radius), ...
            "penalty", alignest.basis.differencePenalty(nBasis.radius));
    end
end
nTrain = numel(trainPoints.x);
blocksTrain = {ones(nTrain, 1), factorsTrain};
blocksTest = {ones(numel(testPoints.x), 1), factorsTest};
offset = 1 + size(factorsTrain, 2);
penalties = struct("columns", {}, "matrix", {});
ranks = zeros(1, numel(smooths));
logPseudoDet = 0;
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
    eigenvalues = eig((reduced + reduced.') / 2);
    eigenvalues = sort(eigenvalues, 'descend');
    logPseudoDet = logPseudoDet + sum(log(eigenvalues(1:ranks(k))));
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
model.logPseudoDetPenalty = logPseudoDet;
model.shapes = strings(size(model.names));
for k = 1:numel(model.names)
    model.shapes(k) = shape(model.names(k));
end
if model.nUnpenalized >= model.n
    error('alignest:gamPoints', 'GAM の学習点（%d 点）が罰則のない係数の数（%d）以下です。学習 Shot を増やしてください。', ...
        model.n, model.nUnpenalized);
end
end

function value = shapeOf(shapes, name)
value = valueOr(shapes, name, "spline");
value = string(value);
if ~any(value == ["spline", "gp"])
    error('alignest:gamShape', 'GAM の形状関数は spline（スプライン）か gp（ガウス過程回帰）です: %s = %s', name, value);
end
end

function value = valueOr(values, name, fallback)
value = fallback;
if isfield(values, name)
    value = values.(name);
end
end

function smooth = gpSmooth(name, coordinates, knots, linear, nLinear, lengthScale)
% ガウス過程の形状関数。K(κ, κ) = UΛUᵀ として基底を [線形部分, K(z, κ)UΛ^(−1/2)] にすると罰則が単位行列になり、
% 数値が安定する（固有値の小さい成分は除く）。
EIGEN_TOLERANCE = 1e-8;
if ~(isscalar(lengthScale) && isfinite(lengthScale) && lengthScale > 0)
    error('alignest:gamLengthScale', 'GAM のガウス過程の長さスケールは正の数にしてください（%s）。', name);
end
gram = maternKernel(knots, knots, lengthScale);
[vectors, values] = eig((gram + gram.') / 2, 'vector');
keep = values > EIGEN_TOLERANCE * max(values);
transform = vectors(:, keep) ./ sqrt(values(keep)).';
nKernel = nnz(keep);
smooth = struct("name", name, ...
    "build", @(p) [linear(p), maternKernel(coordinates(p), knots, lengthScale) * transform], ...
    "penalty", blkdiag(zeros(nLinear), eye(nKernel)));
end

function values = maternKernel(a, b, lengthScale)
% Matérn 5/2（GPR の matern52 と同じ式、σf = 1）
distance = sqrt(alignest.basis.pairwiseSquaredDiff(a, b)) / lengthScale;
values = (1 + sqrt(5) * distance + 5 / 3 * distance .^ 2) .* exp(-sqrt(5) * distance);
end

function knots = gridKnots(nPerAxis)
% [−1, 1]² の格子点のうち、Wafer の内側（半径 1 + 格子の間隔 以下）
grid = linspace(-1, 1, nPerAxis);
spacing = grid(2) - grid(1);
[gridX, gridY] = meshgrid(grid);
inside = hypot(gridX(:), gridY(:)) <= 1 + spacing;
knots = [gridX(inside), gridY(inside)];
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
