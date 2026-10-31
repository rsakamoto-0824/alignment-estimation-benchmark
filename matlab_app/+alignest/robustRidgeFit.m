function fit = robustRidgeFit(A, y, isPenalized, options)
%ROBUSTRIDGEFIT 補正の式の係数を、ロバスト回帰（Huber・LAD）と、選んだ項だけの正則化（L2・L1）で求める（1組の点・1つの軸）。
%   fit = alignest.robustRidgeFit(A, y, isPenalized, loss=..., huberTuning=..., lambda=..., penalty="l2")
%   fit = alignest.robustRidgeFit(..., rowGroup=..., columnGroup=...)   % 組ごとに別の係数を持つ項があるとき
%   A：設計行列（点の数 × 項の数。値がすべて 1 の列を定数の列とする）、y：値 [nm]（点の数 × 1）、
%   isPenalized：正則化をかける項（項の数 × 1。Shot 高次補正では選んだ次数の項）。
%   loss："ols"（最小二乗）・"huber"・"lad"、huberTuning：Huber の定数 c、lambda：正則化の強さ λ（0 なら正則化なし）、
%   penalty："l2"（係数の二乗に罰則。係数を小さくする）・"l1"（係数の絶対値に罰則。効かない項の係数を 0 にする）。
%   rowGroup：点の組の番号（点の数 × 1。1, 2, …）、columnGroup：項の組の番号（項の数 × 1。0 はすべての点の項、g は組 g の
%   点だけの項で、ほかの点では 0 の列）。組 g の項は組 g の点だけで平均 0 にそろえ（組 g の点で 1・ほかで 0 の列を組 g の
%   定数の列とする）、大きさはすべての点で二乗平均 1 にそろえる。最小二乗では、組ごとに別に解いたときと同じ L2 の強さになる。
%   目的関数（n：点の数、r_i：残差、s：残差の尺度 = MAD × 1.4826、θ：列をそろえたときの係数）
%     最小二乗：(1/2n) Σ r_i^2              + 罰則
%     Huber   ：(1/n)  Σ s^2 ρ_c(r_i / s)   + 罰則
%     LAD     ：(1/n)  Σ s |r_i|            + 罰則
%     罰則：L2 は (λ/2) Σ_{かける項} θ_j^2、L1 は λ Σ_{かける項} |θ_j|
%   計算の方法は high-order-correction-report の fit_batch と同じ：
%   - 定数の列を除く列を平均 0・標準偏差 1 にそろえてから解く（L2 が項の単位・座標の桁によらず同じ強さで効くように）
%   - L2 は「L2 の項の係数を 0 に近づける行」を設計行列の下に足して、最小二乗として解く
%   - L1 は、罰則をかけない列を最小二乗で消してから、かける列を座標降下法（Lasso。1つずつ軟しきい値で更新）で解き、
%     かけない列の係数はその残りから最小二乗で求める
%   - Huber・LAD は、残差の大きい点ほど重みを下げた重み付き最小二乗を、重みを変えながら解き直す（IRLS）。
%     重みは Huber が min(1, c s/|r_i|)、LAD が s / max(|r_i|, 0.1 s)。尺度 s は最初の SCALE_UPDATE_ITERATIONS 回だけ
%     求め直し、その後は固定する（MAD が隣り合う残差の間で行き来して収束しないのを防ぐ）
%   決まらない項：L2 をかけない列のうち、値が変わらない列（定数の列を除く）と前の列で表せる列（点が少ない・点の配置で
%   決まらない）は、係数を 0 にして解く（fit.determined が false）。正則化をかける列は λ > 0 なら決まるとする（ほかの列と
%   似ていても、L2 なら一つに決まり、L1 なら 0 になる項が出る）。かける列で値が変わらない列（定数の列と同じ）は係数 0 とする
%   （fit.determined は true、fit.constant が true）。
%   点の数が決まった項の数以下のときは、残差がほぼ 0 になり尺度を決められないので、ロバストの重みは使わない（fit.robust）。
%   fit.coefficients：A の列（そろえる前）に対する係数（項の数 × 1）、fit.fitted：A * 係数、fit.weights：最後の重み
%   （最小二乗はすべて 1）、fit.determined：係数が決まった項、fit.constant：値が変わらない列（定数の列を除く）、
%   fit.robust・converged・iterations。
%   fit.looResidual：1点ずつ抜いて求め直したときの、抜いた点の予測の誤差（値 − 予測）。e_i / (1 − h_i)（h_i は重み付きの
%   ハット行列の対角）で求める。最小二乗は求め直したときと同じ値。L2・Huber・LAD は、列のそろえ方・L2 の強さ・重みを
%   すべての点のときのままとした近似（求め直した値との差は、誤差の大きさの1割ほど）。L1 は、係数が 0 でない項だけで罰則なしに
%   当てはめたときのハット行列の対角で近似する。
%   h_i が 1 に近い点（その点だけで決まる項がある）は NaN。
arguments
    A double
    y double
    isPenalized logical
    options.loss (1, 1) string {mustBeMember(options.loss, ["ols", "huber", "lad"])} = "ols"
    options.huberTuning (1, 1) double {mustBePositive} = 1.345
    options.lambda (1, 1) double {mustBeNonnegative} = 0
    options.penalty (1, 1) string {mustBeMember(options.penalty, ["l2", "l1"])} = "l2"
    options.rowGroup double = []
    options.columnGroup double = []
end
MAD_TO_SIGMA = 1.4826;            % MAD を正規分布の標準偏差に直す係数
SCALE_UPDATE_ITERATIONS = 20;     % 尺度 s を求め直す回数（その後は固定して収束させる）
MAX_ITERATIONS = 1000;
TOLERANCE_NM = 1e-5;              % そろえた係数の変化がこれより小さくなったら止める
LAD_MIN_RESIDUAL_RATIO = 0.1;     % LAD の重み s/|r| で、|r| を「この比 × s」より小さくしない（重みが大きくなりすぎないように）
LEVERAGE_LIMIT = 1 - 1e-8;        % ハット行列の対角がこれ以上の点は、1点抜きの予測の誤差を求めない
RELATIVE_TOLERANCE = 1e-9;        % 前の列で表せる割合がこれより大きい列は、決まらない列とする
CONSTANT_TOLERANCE = 1e-9;        % ばらつき（標準偏差）が値の大きさのこの割合以下の列は、値が変わらない列とする（計算の丸めの差を除く）
[n, p] = size(A);
y = y(:);
isPenalized = isPenalized(:) & options.lambda > 0;
rowGroup = options.rowGroup(:);
columnGroup = options.columnGroup(:);
if isempty(rowGroup)
    rowGroup = ones(n, 1);
end
if isempty(columnGroup)
    columnGroup = zeros(p, 1);
end
if numel(y) ~= n || numel(isPenalized) ~= p || numel(rowGroup) ~= n || numel(columnGroup) ~= p
    error('alignest:fitSize', '設計行列・値・L2 をかける項・組の番号の数が合いません。');
end
fit = struct("coefficients", zeros(p, 1), "fitted", zeros(n, 1), "weights", ones(n, 1), "determined", false(p, 1), ...
    "constant", false(p, 1), "robust", false, "converged", true, "iterations", 0, "looResidual", nan(n, 1));
if n == 0
    return
end

% 列をそろえる（定数の列はそのまま。定数の列が無い組は中心を動かさない）。組の項は、その組の点だけで中心を求める
[isIntercept, center, inGroup] = columnCenters(A, rowGroup, columnGroup);
centered = A - center .* inGroup;
spread = sqrt(mean(centered .^ 2, 1));
spread(isIntercept) = 1;
constant = spread <= CONSTANT_TOLERANCE * max(abs(A), [], 1);   % 定数の列のほかに、値が（ほぼ）変わらない列
spread(constant) = 1;
standardized = centered ./ spread;

% 決まる列：L2 をかけない列は、前の列で表せない列だけ（列の順に確かめる）。L2 をかける列は必ず決まる
constant = constant(:) & ~isIntercept(:);
determined = ~constant;
free = find(determined & ~isPenalized);
determined(free) = independentColumns(standardized(:, free), RELATIVE_TOLERANCE);
columns = find(determined & ~constant);
As = standardized(:, columns);
penalized = isPenalized(columns);
penaltyRows = zeros(0, numel(columns));
if options.penalty == "l2"
    penaltyRows = sqrt(n * options.lambda) * diag(double(penalized));
    penaltyRows = penaltyRows(penalized, :);
end
l1Threshold = 0;   % L1 の軟しきい値（目的関数を n 倍したときの λ）
if options.penalty == "l1"
    l1Threshold = n * options.lambda;
end

weights = ones(n, 1);
theta = solveWeighted(As, y, weights, penaltyRows, penalized, l1Threshold, zeros(numel(columns), 1));
fit.robust = options.loss ~= "ols" && n > numel(columns);
if fit.robust
    scale = 0;
    fit.converged = false;
    for iteration = 1:MAX_ITERATIONS
        residual = y - As * theta;
        if iteration <= SCALE_UPDATE_ITERATIONS
            scale = max(MAD_TO_SIGMA * median(abs(residual - median(residual))), eps);
        end
        absResidual = abs(residual);
        if options.loss == "huber"
            weights = min(1, options.huberTuning * scale ./ max(absResidual, eps));
        else
            weights = scale ./ max(absResidual, LAD_MIN_RESIDUAL_RATIO * scale);
        end
        thetaNew = solveWeighted(As, y, weights, penaltyRows, penalized, l1Threshold, theta);
        change = max(abs(thetaNew - theta));
        theta = thetaNew;
        fit.iterations = iteration;
        if iteration > SCALE_UPDATE_ITERATIONS && change < TOLERANCE_NM
            fit.converged = true;
            break
        end
    end
end

% そろえた係数を、そろえる前の列の係数に戻す（定数の列の係数で中心の分を差し引く）
coefficients = zeros(p, 1);
coefficients(columns) = theta ./ spread(columns).';
for group = unique(columnGroup).'
    intercept = find(isIntercept(:) & determined & columnGroup == group, 1);
    if ~isempty(intercept)
        members = columnGroup(columns) == group;
        coefficients(intercept) = coefficients(intercept) - ...
            sum(theta(members) .* (center(columns(members)) ./ spread(columns(members))).');
    end
end
fit.coefficients = coefficients;
fit.fitted = A * coefficients;
fit.weights = weights;
% 1点抜きの予測の誤差：H = W^(1/2) A (A'WA + P'P)^(-1) A' W^(1/2) の対角 h_i から e_i / (1 − h_i)
active = true(numel(columns), 1);
if l1Threshold > 0
    active = ~penalized | theta ~= 0;   % L1 は係数が 0 でない項だけで近似する
end
information = As(:, active).' * (weights .* As(:, active)) + penaltyRows(:, active).' * penaltyRows(:, active);
leverage = weights .* sum((As(:, active) / information) .* As(:, active), 2);
residual = y - fit.fitted;
loo = residual ./ (1 - leverage);
loo(leverage >= LEVERAGE_LIMIT | ~isfinite(loo)) = NaN;
fit.looResidual = loo;
fit.determined = determined | (constant & isPenalized);
fit.constant = constant;
end

function theta = solveWeighted(A, y, weights, penaltyRows, penalized, l1Threshold, start)
% 重み付き最小二乗に罰則を足して解く。L2（penaltyRows）：罰則の行を足して QR 分解（バックスラッシュ）で解く。
% L1（l1Threshold > 0）：(1/2) Σ w_i r_i^2 + l1Threshold Σ_{かける項} |θ_j| を、かけない列を消してから座標降下法で解く
% （start から始める。IRLS では前の係数から始めると早く収束する）
MAX_SWEEPS = 10000;           % 座標降下法で全部の項を更新する回数の上限
SWEEP_TOLERANCE = 1e-10;      % そろえた係数の変化がこれより小さくなったら止める
ZERO_TOLERANCE = 1e-12;       % かけない列で表せる割合がこれより大きい列は、係数 0 とする
rootWeights = sqrt(weights);
if l1Threshold <= 0 || ~any(penalized)
    theta = [rootWeights .* A; penaltyRows] \ [rootWeights .* y; zeros(size(penaltyRows, 1), 1)];
    return
end
weightedA = rootWeights .* A;
weightedY = rootWeights .* y;
free = weightedA(:, ~penalized);
shrunk = weightedA(:, penalized);
projectedA = shrunk;
projectedY = weightedY;
if ~isempty(free)
    [basis, ~] = qr(free, 0);
    projectedA = shrunk - basis * (basis.' * shrunk);
    projectedY = weightedY - basis * (basis.' * weightedY);
end
gram = projectedA.' * projectedA;
target = projectedA.' * projectedY;
usable = diag(gram) > ZERO_TOLERANCE * max(sum(shrunk .^ 2, 1).', eps);
beta = start(penalized);
beta(~usable) = 0;
for sweep = 1:MAX_SWEEPS
    largest = 0;
    for j = find(usable).'
        rho = target(j) - gram(j, :) * beta + gram(j, j) * beta(j);
        updated = sign(rho) * max(abs(rho) - l1Threshold, 0) / gram(j, j);
        largest = max(largest, abs(updated - beta(j)));
        beta(j) = updated;
    end
    if largest < SWEEP_TOLERANCE
        break
    end
end
theta = zeros(size(A, 2), 1);
theta(penalized) = beta;
if ~isempty(free)
    theta(~penalized) = free \ (weightedY - shrunk * beta);
end
end

function [isIntercept, center, inGroup] = columnCenters(A, rowGroup, columnGroup)
% 定数の列（組 g の点で 1・ほかの点で 0。組 0 はすべての点で 1）と、列の中心（定数の列がある組の列だけ、その組の点の平均）。
% inGroup：列ごとに、その列の組の点（組 0 の列はすべての点）
[n, p] = size(A);
isIntercept = false(1, p);
center = zeros(1, p);
inGroup = true(n, p);
for group = unique(columnGroup).'
    members = find(columnGroup == group).';
    if group ~= 0
        inGroup(:, members) = repmat(rowGroup == group, 1, numel(members));
    end
    rows = inGroup(:, members(1));
    isIntercept(members) = all(A(rows, members) == 1, 1) & all(A(~rows, members) == 0, 1);
    if any(isIntercept(members))
        center(members) = mean(A(rows, members), 1);
        center(members(isIntercept(members))) = 0;
    end
end
end

function keep = independentColumns(A, tolerance)
% 前の列で表せない列（列の順に、それまでに残した列の正規直交基底へ射影した残りの大きさで判定。2回射影して安定させる）
nColumns = size(A, 2);
keep = false(nColumns, 1);
basis = zeros(size(A, 1), 0);
for column = 1:nColumns
    vector = A(:, column);
    scale = norm(vector);
    if scale == 0
        continue
    end
    for pass = 1:2
        vector = vector - basis * (basis.' * vector);
    end
    remainder = norm(vector);
    if remainder > sqrt(tolerance) * scale
        keep(column) = true;
        basis(:, end + 1) = vector / remainder; %#ok<AGROW>
    end
end
end
