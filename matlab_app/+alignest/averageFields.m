function average = averageFields(points, values)
%AVERAGEFIELDS 複数の Wafer のベクトル場を、同じ座標ごとに平均し、Wafer 間のばらつき（共分散）を求める。
%   average = alignest.averageFields(points, values)
%   points・values は Wafer ごとのセル配列（点数 × 2 の座標 [mm] と、値 [X, Y] [nm]。無効な値は NaN）。
%   座標は 0.001 mm に丸めて同じ点とみなす。
%   average.points    ：座標（K × 2）
%   average.mean      ：X・Y それぞれ、その座標で有効な Wafer の平均（K × 2。無ければ NaN）
%   average.count     ：平均に使った Wafer の数（K × 2）
%   average.covariance：X の分散・Y の分散・X と Y の共分散（K × 3、不偏推定）。X・Y とも有効な Wafer が
%                       2枚以上の座標だけ求め、ほかは NaN（共分散楕円に使う）
DIGITS = 3;
allPoints = vertcat(points{:});
allValues = vertcat(values{:});
[average.points, first, group] = unique(round(allPoints, DIGITS), 'rows', 'stable');
average.points = allPoints(first, :);
nPoints = size(average.points, 1);
average.mean = nan(nPoints, 2);
average.count = zeros(nPoints, 2);
for k = 1:2
    valid = isfinite(allValues(:, k));
    average.count(:, k) = accumarray(group(valid), 1, [nPoints, 1]);
    sums = accumarray(group(valid), allValues(valid, k), [nPoints, 1]);
    positive = average.count(:, k) > 0;
    average.mean(positive, k) = sums(positive) ./ average.count(positive, k);
end
both = all(isfinite(allValues), 2);
nBoth = accumarray(group(both), 1, [nPoints, 1]);
meanBoth = [accumarray(group(both), allValues(both, 1), [nPoints, 1]), ...
    accumarray(group(both), allValues(both, 2), [nPoints, 1])] ./ max(nBoth, 1);
deviation = allValues(both, :) - meanBoth(group(both), :);
products = [deviation(:, 1) .^ 2, deviation(:, 2) .^ 2, deviation(:, 1) .* deviation(:, 2)];
average.covariance = nan(nPoints, 3);
enough = nBoth >= 2;
for column = 1:3
    sums = accumarray(group(both), products(:, column), [nPoints, 1]);
    average.covariance(enough, column) = sums(enough) ./ (nBoth(enough) - 1);
end
end
