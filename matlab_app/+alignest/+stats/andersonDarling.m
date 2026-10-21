function [a2, p] = andersonDarling(values)
%ANDERSONDARLING Anderson–Darling の正規性検定（平均・標準偏差をデータから推定する場合）。
%   [a2, p] = alignest.stats.andersonDarling(values)
%   a2 は検定統計量 A²（SciPy の anderson と同じ値）。p 値は補正した A*² = A²(1 + 0.75/n + 2.25/n²) から
%   D'Agostino & Stephens (1986) の近似式で求める。点数が 8 未満、または値がすべて同じときは NaN。
MIN_POINTS = 8;
x = sort(values(isfinite(values)));
x = x(:);
n = numel(x);
a2 = NaN;
p = NaN;
if n < MIN_POINTS || std(x) <= 0
    return
end
z = (x - mean(x)) / std(x);
weights = 2 * (1:n).' - 1;
% log(1 − Φ(z)) は log Φ(−z) として求める（裾で桁落ちしないように）
logTerms = log(alignest.stats.normalCdf(z)) + log(alignest.stats.normalCdf(-flipud(z)));
a2 = -n - sum(weights .* logTerms) / n;
adjusted = a2 * (1 + 0.75 / n + 2.25 / n ^ 2);
if adjusted >= 0.6
    p = exp(1.2937 - 5.709 * adjusted + 0.0186 * adjusted ^ 2);
elseif adjusted >= 0.34
    p = exp(0.9177 - 4.279 * adjusted - 1.38 * adjusted ^ 2);
elseif adjusted >= 0.2
    p = 1 - exp(-8.318 + 42.796 * adjusted - 59.938 * adjusted ^ 2);
else
    p = 1 - exp(-13.436 + 101.14 * adjusted - 223.73 * adjusted ^ 2);
end
p = min(max(p, 0), 1);
end
