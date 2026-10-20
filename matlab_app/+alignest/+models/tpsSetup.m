function model = tpsSetup(trainFeatures, testFeatures, log10Grid)
%TPSSETUP 平滑化つき薄板スプライン（TPS）の前計算。
%   f(z) = Σ w_i φ(‖z − z_i‖) + c₀ + cᵀz、φ(r) = r² log r（3次元以上の説明変数にも同じ φ を使う）。
%   λ は一般化交差検証（GCV）で選ぶ。多項式部分 P = [1, z] の直交補空間 Q₂ で
%   Q₂ᵀΦQ₂ = U D Uᵀ と固有分解すると（Wahba の方法）、λ を変えても固有分解は1回で済む。
%   log10Grid は nλ の候補（固有値の平均に対する倍率の常用対数）。
phi = tpsKernel(sqrt(alignest.basis.pairwiseSquaredDiff(trainFeatures, trainFeatures)));
phiTest = tpsKernel(sqrt(alignest.basis.pairwiseSquaredDiff(testFeatures, trainFeatures)));
model = alignest.models.radialSetup(trainFeatures, testFeatures, phi, phiTest, log10Grid);
end

function values = tpsKernel(distance)
values = zeros(size(distance));
positive = distance > 0;
values(positive) = distance(positive) .^ 2 .* log(distance(positive));
end
