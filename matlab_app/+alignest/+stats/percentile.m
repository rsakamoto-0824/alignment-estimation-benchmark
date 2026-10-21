function value = percentile(values, percent)
%PERCENTILE 百分位点。Excel の PERCENTILE.INC（NumPy の既定）と同じ線形補間で求める。
%   value = alignest.stats.percentile(values, 95)
%   NaN は除く。値が無ければ NaN。MATLAB 本体だけで動かすため、Toolbox の prctile は使わない。
values = sort(values(~isnan(values)));
n = numel(values);
if n == 0
    value = NaN;
    return
end
position = 1 + (n - 1) * percent / 100;
lowerIndex = floor(position);
upperIndex = min(lowerIndex + 1, n);
value = values(lowerIndex) + (position - lowerIndex) * (values(upperIndex) - values(lowerIndex));
end
