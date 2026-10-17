function basis = bsplineBasis(values, lower, upper, nBasis)
%BSPLINEBASIS 区間 [lower, upper] の等間隔ノット3次 B スプライン（P-spline の基底、点数 × nBasis）。
%   区間外の値は端に寄せる。基底 j の台は [t_j, t_{j+4})、t_j = lower + 幅·(j − 3)（j は0始まり）。
degree = 3;
nSegments = nBasis - degree;
if nSegments < 1
    error('alignest:bsplineBasis', 'B スプラインの基底の数は %d より多くしてください: %d', degree, nBasis);
end
step = (upper - lower) / nSegments;
clipped = min(max(values(:), lower), upper);
basis = zeros(numel(clipped), nBasis);
for j = 0:nBasis - 1
    knot = lower + step * (j - degree);
    basis(:, j + 1) = alignest.basis.cardinalCubic((clipped - knot) / step);
end
end
