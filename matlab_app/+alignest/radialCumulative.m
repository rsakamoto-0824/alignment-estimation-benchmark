function cumulative = radialCumulative(radiusMm, values, ratesPercent)
%RADIALCUMULATIVE 半径 0 から外へ向かって値を足した累積 [%]（全体 = 100%）と、累積率ごとの半径。
%   cumulative = alignest.radialCumulative(radiusMm, values)
%   cumulative = alignest.radialCumulative(radiusMm, values, ratesPercent)   % 例：ratesPercent = [50, 80]
%   radiusMm：点の Wafer 中心からの半径 [mm]、values：点の値（指標の 3σ。値の無い点・負の値は使わない）。
%   cumulative.radiusMm・percent：累積の線（半径の小さい順。先頭は 半径 0・累積 0%）。percent(i) = 半径 radiusMm(i) までの
%   点の値の和 ÷ 全点の値の和 × 100。
%   cumulative.rates・rateRadiiMm：累積率 [%] と、累積の線がその累積率になる半径 [mm]（線の折れ点の間は直線でつなぐ。
%   求められないときは NaN）。cumulative.total：値の和、cumulative.nPoints：使った点の数。
arguments
    radiusMm double
    values double
    ratesPercent double = zeros(1, 0)
end
radiusMm = reshape(radiusMm, [], 1);
values = reshape(values, [], 1);
if numel(radiusMm) ~= numel(values)
    error('alignest:radialCumulative', '半径と値の数が違います。');
end
used = isfinite(radiusMm) & isfinite(values) & values >= 0;
[sortedRadius, order] = sort(radiusMm(used));
sortedValues = values(used);
sortedValues = sortedValues(order);
total = sum(sortedValues);
cumulative.radiusMm = [0; sortedRadius];
cumulative.percent = [0; 100 * cumsum(sortedValues) / total];
if ~(total > 0)
    cumulative.percent = nan(size(cumulative.radiusMm));
end
cumulative.rates = reshape(ratesPercent, 1, []);
cumulative.rateRadiiMm = arrayfun(@(rate) radiusAt(cumulative.radiusMm, cumulative.percent, rate), cumulative.rates);
cumulative.total = total;
cumulative.nPoints = nnz(used);
end

function radius = radiusAt(radiusMm, percent, rate)
% 累積の線が rate [%] になる半径（初めて rate 以上になる折れ点と、その前の折れ点の間を直線でつなぐ）
radius = NaN;
if ~(rate >= 0 && rate <= 100) || any(isnan(percent))
    return
end
index = find(percent >= rate - 1e-9, 1);
if isempty(index)
    return
end
if index == 1
    radius = radiusMm(1);
    return
end
rise = percent(index) - percent(index - 1);
radius = radiusMm(index - 1) + (rate - percent(index - 1)) / rise * (radiusMm(index) - radiusMm(index - 1));
end
