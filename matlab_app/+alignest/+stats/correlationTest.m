function result = correlationTest(x, y)
%CORRELATIONTEST 2つの量の相関係数（Pearson）と、相関が 0 かの t 検定の p 値（両側）、回帰直線 y = a + b·x。
%   result = alignest.stats.correlationTest(x, y)
%   result.n（両方とも数の点の数）・r・p・intercept（a）・slope（b）。点が3点未満、またはどちらかの値がすべて同じ
%   ときは r・p を NaN にする。t = r √((n − 2) / (1 − r²)) の p 値は正則化不完全ベータ関数で求める
%   （Toolbox の tcdf を使わない）。
x = double(x(:));
y = double(y(:));
use = isfinite(x) & isfinite(y);
x = x(use);
y = y(use);
n = numel(x);
result = struct("n", n, "r", NaN, "p", NaN, "intercept", NaN, "slope", NaN);
if n < 3
    return
end
dx = x - mean(x);
dy = y - mean(y);
sxx = sum(dx .^ 2);
syy = sum(dy .^ 2);
if sxx <= 0 || syy <= 0
    return
end
result.r = max(-1, min(1, sum(dx .* dy) / sqrt(sxx * syy)));
result.slope = sum(dx .* dy) / sxx;
result.intercept = mean(y) - result.slope * mean(x);
df = n - 2;
if abs(result.r) >= 1
    result.p = 0;
else
    t = result.r * sqrt(df / (1 - result.r ^ 2));
    result.p = betainc(df / (df + t ^ 2), df / 2, 0.5);
end
end
