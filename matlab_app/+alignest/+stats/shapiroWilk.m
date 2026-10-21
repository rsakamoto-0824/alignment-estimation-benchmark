function [w, p] = shapiroWilk(values)
%SHAPIROWILK Shapiro–Wilk の正規性検定（Royston 1995 の近似、AS R94。SciPy の shapiro と同じ計算）。
%   [w, p] = alignest.stats.shapiroWilk(values)
%   w は検定統計量 W（1 に近いほど正規分布に近い）、p は p 値（小さいほど正規分布から外れている）。
%   近似が使える 3 ≤ n ≤ 5000 のときだけ計算する。範囲外、または値がすべて同じときは NaN。
MIN_POINTS = 3;
MAX_POINTS = 5000;
x = sort(values(isfinite(values)));
x = x(:);
n = numel(x);
w = NaN;
p = NaN;
if n < MIN_POINTS || n > MAX_POINTS || x(end) - x(1) <= eps(max(abs(x)))
    return
end
a = coefficients(n);
centered = x - mean(x);
w = min(1, (a.' * centered) ^ 2 / (sum(a .^ 2) * sum(centered .^ 2)));
if n == 3
    % n = 3 は W の分布が厳密に分かる
    p = max(0, 6 / pi * (asin(sqrt(w)) - pi / 3));
    return
end
logOneMinusW = log(1 - w);
if n <= 11
    gamma = polyval([0.459, -2.273], n);
    if logOneMinusW >= gamma
        p = 0;
        return
    end
    transformed = -log(gamma - logOneMinusW);
    mu = polyval([-0.0006714, 0.025054, -0.39978, 0.5440], n);
    sigma = exp(polyval([-0.0020322, 0.062767, -0.77857, 1.3822], n));
else
    logN = log(n);
    transformed = logOneMinusW;
    mu = polyval([0.0038915, -0.083751, -0.31082, -1.5861], logN);
    sigma = exp(polyval([0.0030302, -0.082676, -0.4803], logN));
end
p = alignest.stats.normalCdf(-(transformed - mu) / sigma);
end

function a = coefficients(n)
% 正規順序統計量の期待値 m から作る係数（両端の1〜2個は Royston の多項式で補正し、Σa² = 1 にする）
if n == 3
    a = [-sqrt(0.5); 0; sqrt(0.5)];
    return
end
m = alignest.stats.normalInverse(((1:n).' - 0.375) / (n + 0.25));
sumSquares = sum(m .^ 2);
u = 1 / sqrt(n);
last = polyval([-2.706056, 4.434685, -2.071190, -0.147981, 0.221157, 0], u) + m(n) / sqrt(sumSquares);
if n > 5
    secondLast = polyval([-3.582633, 5.682633, -1.752461, -0.293762, 0.042981, 0], u) + m(n - 1) / sqrt(sumSquares);
    phi = (sumSquares - 2 * m(n) ^ 2 - 2 * m(n - 1) ^ 2) / (1 - 2 * last ^ 2 - 2 * secondLast ^ 2);
    a = m / sqrt(phi);
    a([1, 2, n - 1, n]) = [-last; -secondLast; secondLast; last];
else
    phi = (sumSquares - 2 * m(n) ^ 2) / (1 - 2 * last ^ 2);
    a = m / sqrt(phi);
    a([1, n]) = [-last; last];
end
end
