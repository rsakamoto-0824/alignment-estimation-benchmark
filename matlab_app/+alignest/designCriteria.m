function [iValue, dValue] = designCriteria(blocks)
%DESIGNCRITERIA 選んだ Shot の組の I 基準と D 基準（I 最適計画の評価指標）。どちらも小さいほど良い計画。
%   [iValue, dValue] = alignest.designCriteria(blocks)
%   blocks{s} は選んだ Shot s の Mark での基底の行（候補の全 Mark で正規直交化した XY 多項式。
%   alignest.planTrainingShots を参照）。M = Σ BᵀB（情報行列）、p = 基底の項数として
%   - I 基準 = tr(M⁻¹)       ：候補の全 Mark での予測分散の平均に比例する（I 最適はこれを小さくする）
%   - D 基準 = det(M)^(−1/p) ：係数の推定のばらつき（信頼領域の体積）の大きさ（D 最適は det(M) を大きくする）
%   全候補を使うと M が単位行列になり、I 基準 = p、D 基準 = 1。学習点が項数より少なく M が特異なら NaN。
RCOND_LIMIT = 1e-12;  % これより条件の悪い M は特異とみなす
iValue = NaN;
dValue = NaN;
if isempty(blocks)
    return
end
stacked = vertcat(blocks{:});
nParams = size(stacked, 2);
if size(stacked, 1) < nParams
    return
end
information = stacked.' * stacked;
[upperFactor, failed] = chol(information);
if failed || rcond(information) < RCOND_LIMIT
    return
end
inverseFactor = upperFactor \ eye(nParams);
iValue = sum(inverseFactor .^ 2, 'all');
dValue = exp(-2 * sum(log(diag(upperFactor))) / nParams);
end
