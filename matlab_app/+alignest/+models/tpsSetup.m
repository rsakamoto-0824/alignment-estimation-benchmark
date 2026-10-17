function model = tpsSetup(trainFeatures, testFeatures, log10Grid)
%TPSSETUP 平滑化つき薄板スプライン（TPS）の前計算。
%   f(z) = Σ w_i φ(‖z − z_i‖) + c₀ + cᵀz、φ(r) = r² log r（3次元以上の説明変数にも同じ φ を使う）。
%   λ は一般化交差検証（GCV）で選ぶ。多項式部分 P = [1, z] の直交補空間 Q₂ で
%   Q₂ᵀΦQ₂ = U D Uᵀ と固有分解すると（Wahba の方法）、λ を変えても固有分解は1回で済む。
%   log10Grid は nλ の候補（固有値の平均に対する倍率の常用対数）。
n = size(trainFeatures, 1);
model.n = n;
model.phi = tpsKernel(sqrt(alignest.basis.pairwiseSquaredDiff(trainFeatures, trainFeatures)));
model.phiTest = tpsKernel(sqrt(alignest.basis.pairwiseSquaredDiff(testFeatures, trainFeatures)));
model.poly = [ones(n, 1), trainFeatures];
model.polyTest = [ones(size(testFeatures, 1), 1), testFeatures];
k = size(model.poly, 2);
if n <= k
    error('alignest:tpsPoints', 'TPS の学習点（%d 点）が多項式部分の項数（%d）以下です。学習 Shot を増やしてください。', n, k);
end
[qFull, rFull] = qr(model.poly);
model.q1 = qFull(:, 1:k);
model.r1 = rFull(1:k, :);
q2 = qFull(:, k + 1:end);
reduced = q2.' * model.phi * q2;
[vectors, values] = eig((reduced + reduced.') / 2, 'vector');
model.eigval = max(values, 0);  % 条件付き正定値なので理論上 ≥ 0（丸め誤差を切る）
model.basis = q2 * vectors;
scale = mean(model.eigval);
if scale <= 0
    scale = 1;
end
model.nLambdaGrid = scale * 10 .^ log10Grid(:);
end

function values = tpsKernel(distance)
values = zeros(size(distance));
positive = distance > 0;
values(positive) = distance(positive) .^ 2 .* log(distance(positive));
end
