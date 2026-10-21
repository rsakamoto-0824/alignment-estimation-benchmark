function summary = scatterSummary(measured, estimated)
%SCATTERSUMMARY 推定値と実測値の散布図の要約：点数・相関係数 r・決定係数 r²・回帰直線（推定値 = a + b·実測値）・RMSE。
%   NaN の点は使わない。点数が2未満、または値がすべて同じなら r・回帰直線は NaN。
measured = measured(:);
estimated = estimated(:);
valid = isfinite(measured) & isfinite(estimated);
x = measured(valid);
y = estimated(valid);
summary = struct("n", numel(x), "r", NaN, "r2", NaN, "slope", NaN, "intercept", NaN, "rmse", NaN);
if isempty(x)
    return
end
summary.rmse = sqrt(mean((y - x) .^ 2));
if numel(x) < 2
    return
end
dx = x - mean(x);
dy = y - mean(y);
if sum(dx .^ 2) > 0 && sum(dy .^ 2) > 0
    summary.r = sum(dx .* dy) / sqrt(sum(dx .^ 2) * sum(dy .^ 2));
    summary.r2 = summary.r ^ 2;
end
if sum(dx .^ 2) > 0
    summary.slope = sum(dx .* dy) / sum(dx .^ 2);
    summary.intercept = mean(y) - summary.slope * mean(x);
end
end
