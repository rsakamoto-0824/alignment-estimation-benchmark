function vif = varianceInflation(A, isIntercept, weights)
%VARIANCEINFLATION 設計行列の列ごとの VIF（分散拡大係数）VIF_j = 1 / (1 − R_j^2)。
%   vif = alignest.varianceInflation(A, isIntercept)
%   vif = alignest.varianceInflation(A, isIntercept, weights)   % 行ごとの重み（同じ点をまとめたときの点の数）
%   R_j^2 は、列 j をほかの列（定数の列を含む）で回帰したときの決定係数。定数の列（isIntercept）は対象外で NaN。
%   ほかの列で完全に表せる列（一次従属）は Inf。VIF は列を定数倍しても変わらないので、桁の違う列（mm 座標のべき乗）は
%   最大値で割ってから計算する（数値計算を安定させるため。high-order-correction-report の compute_vif と同じ考え方）。
arguments
    A double
    isIntercept logical
    weights double = ones(size(A, 1), 1)
end
RANK_TOLERANCE = 1e-10;   % QR 分解の対角がこれ（最大の対角に対する比）より小さい列は、ほかの列で表せるとみなす
nColumns = size(A, 2);
vif = nan(nColumns, 1);
if size(A, 1) == 0
    return
end
weights = weights(:);
scale = max(abs(A), [], 1);
scale(scale == 0) = 1;
A = A ./ scale;
rootWeights = sqrt(weights);
for j = reshape(find(~isIntercept(:)), 1, [])
    others = rootWeights .* A(:, [1:j - 1, j + 1:nColumns]);
    target = A(:, j);
    targetMean = sum(weights .* target) / sum(weights);
    totalSum = sum(weights .* (target - targetMean) .^ 2);
    if totalSum <= eps * max(1, sum(weights .* target .^ 2))
        vif(j) = Inf;   % 値が変わらない列（定数の列と同じ）
        continue
    end
    [Q, R] = qr(others, 0);
    diagonal = abs(diag(R));
    keep = diagonal > RANK_TOLERANCE * max([diagonal; 1]);
    weightedTarget = rootWeights .* target;
    fitted = Q(:, keep) * (Q(:, keep).' * weightedTarget);
    residualSum = sum((weightedTarget - fitted) .^ 2);
    rSquared = 1 - residualSum / totalSum;
    vif(j) = 1 / max(1 - rSquared, eps);
    if rSquared >= 1 - RANK_TOLERANCE
        vif(j) = Inf;
    end
end
end
