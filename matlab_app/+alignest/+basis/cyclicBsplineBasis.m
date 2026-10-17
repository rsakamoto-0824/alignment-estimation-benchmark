function basis = cyclicBsplineBasis(values, startValue, period, nBasis)
%CYCLICBSPLINEBASIS 周期 period の3次 B スプライン（nBasis 個、各点で基底の和は1）。方位角 θ に使う。
if nBasis < 4
    error('alignest:cyclicBasis', '周期スプラインの基底は4個以上にしてください: %d', nBasis);
end
u = mod(values(:) - startValue, period) / (period / nBasis);
basis = zeros(numel(u), nBasis);
for j = 0:nBasis - 1
    basis(:, j + 1) = alignest.basis.cardinalCubic(mod(u - j, nBasis));
end
end
