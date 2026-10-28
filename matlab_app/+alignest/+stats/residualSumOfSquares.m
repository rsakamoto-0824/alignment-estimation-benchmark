function [rss, rankValue] = residualSumOfSquares(design, y)
%RESIDUALSUMOFSQUARES 最小二乗の残差平方和と計画行列の階数（列の重なりは QR 分解の対角で判定する）。
%   [rss, rankValue] = alignest.stats.residualSumOfSquares(design, y)
[q, r, ~] = qr(design, 0);
diagonal = abs(diag(r));
if isempty(diagonal)
    rankValue = 0;
else
    rankValue = nnz(diagonal > max(size(design)) * eps(max(diagonal)));
end
q = q(:, 1:rankValue);
residual = y - q * (q.' * y);
rss = sum(residual .^ 2);
end
