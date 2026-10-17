function penalty = differencePenalty(nBasis, cyclic)
%DIFFERENCEPENALTY 係数の2階差分の罰則行列 DᵀD（P-spline）。cyclic なら端と端をつなぐ。
if nargin < 2
    cyclic = false;
end
if cyclic
    difference = zeros(nBasis, nBasis);
    for i = 1:nBasis
        difference(i, i) = 1;
        difference(i, mod(i, nBasis) + 1) = -2;
        difference(i, mod(i + 1, nBasis) + 1) = 1;
    end
else
    difference = diff(eye(nBasis), 2, 1);
end
penalty = difference.' * difference;
end
