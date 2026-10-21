function [deviation, count] = waferSpread(results, metricName)
%WAFERSPREAD 手法 × 学習パターンの列ごとの、Wafer 間の標準偏差と Wafer 数（グラフのエラーバーに使う）。
%   Wafer ごとの値（ランダムのくり返しは平均。alignest.perUnitValues）の標準偏差（不偏）。2枚未満なら NaN。
perUnit = alignest.perUnitValues(results, metricName);
deviation = nan(size(perUnit));
count = zeros(size(perUnit));
for k = 1:numel(perUnit)
    values = perUnit{k};
    values = values(~isnan(values));
    count(k) = numel(values);
    if count(k) >= 2
        deviation(k) = std(values);
    end
end
end
