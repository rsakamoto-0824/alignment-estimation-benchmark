function design = designPolynomial(x, y, order, features)
%DESIGNPOLYNOMIAL I 最適・D 最適の基準モデルの設計行列：説明変数 X・Y、または X・Y・半径の多項式。
%   design = alignest.basis.designPolynomial(x, y, order, "XYR")   % x・y は Wafer 半径で割った座標
%   features = "XY" ：x^a y^b（a + b ≤ order。alignest.basis.polynomialDesign と同じ。5次で 21 列）
%   features = "XYR"：x・y・r（r = √(x² + y²)）の order 次までの多項式。r² = x² + y² なので、r の偶数乗の項は x・y の
%     多項式で表せて列が重なる（基準の行列が特異になる）。重ならない列だけにすると、x^a y^b（a + b ≤ order）と
%     r · x^a y^b（a + b ≤ order − 1）になる（r の奇数乗の項は r · (x・y の多項式) で表せるため）。5次で 21 + 15 = 36 列。
arguments
    x double
    y double
    order (1, 1) double {mustBeInteger, mustBeNonnegative}
    features (1, 1) string {mustBeMember(features, ["XY", "XYR"])} = "XYR"
end
x = x(:);
y = y(:);
design = alignest.basis.polynomialDesign(x, y, order);
if features == "XYR" && order >= 1
    radius = hypot(x, y);
    design = [design, radius .* alignest.basis.polynomialDesign(x, y, order - 1)];
end
end
