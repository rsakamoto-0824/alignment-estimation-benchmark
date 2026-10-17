function design = polynomialDesign(x, y, order)
%POLYNOMIALDESIGN x^a y^b（a + b ≤ order）を次数順に並べた設計行列。5次なら21列。
if order < 0
    error('alignest:polynomialOrder', '多項式の次数は0以上にしてください: %d', order);
end
x = x(:);
y = y(:);
nColumns = (order + 1) * (order + 2) / 2;
design = zeros(numel(x), nColumns);
column = 0;
for degree = 0:order
    for powerY = 0:degree
        column = column + 1;
        design(:, column) = x .^ (degree - powerY) .* y .^ powerY;
    end
end
end
