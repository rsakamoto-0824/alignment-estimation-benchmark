function summary = distributionSummary(values)
%DISTRIBUTIONSUMMARY 値の分布の代表的な統計値：点数・平均・標準偏差（不偏）・中央値・最小・最大・|平均|+3σ。
%   NaN は除く。点数が 0 なら点数以外は NaN（標準偏差は2点以上で求める）。
values = values(isfinite(values));
values = values(:);
summary = struct("n", numel(values), "mean", NaN, "std", NaN, "median", NaN, "min", NaN, "max", NaN, ...
    "meanPlus3Sigma", NaN);
if isempty(values)
    return
end
summary.mean = mean(values);
summary.median = median(values);
summary.min = min(values);
summary.max = max(values);
if numel(values) >= 2
    summary.std = std(values);
    summary.meanPlus3Sigma = abs(summary.mean) + 3 * summary.std;
end
end
