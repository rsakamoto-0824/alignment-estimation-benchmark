function [dx, dy] = randomShapeField(shapes, index, xMm, yMm)
%RANDOMSHAPEFIELD 乱数の Shot の形（alignest.randomShotShapes）の index 番目の形の値を、Shot 内の好きな位置で求める（ヒートマップ）。
%   [dx, dy] = alignest.randomShapeField(shapes, index, xMm, yMm)
%   xMm・yMm：Shot 内の座標 [mm]（同じ大きさの配列）。dx・dy：計測のばらつき・飛び値を足す前の形の値 [nm]（xMm と同じ大きさ）。
u = xMm(:) / shapes.halfSizeMm(1);
v = yMm(:) / shapes.halfSizeMm(2);
basis = u .^ (shapes.powers(:, 1).') .* v .^ (shapes.powers(:, 2).');
dx = reshape(basis * shapes.coefficientsX(:, index), size(xMm));
dy = reshape(basis * shapes.coefficientsY(:, index), size(xMm));
end
