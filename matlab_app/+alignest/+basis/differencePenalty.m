function penalty = differencePenalty(nBasis)
%DIFFERENCEPENALTY 係数の2階差分の罰則行列 DᵀD（P-spline）。
difference = diff(eye(nBasis), 2, 1);
penalty = difference.' * difference;
end
