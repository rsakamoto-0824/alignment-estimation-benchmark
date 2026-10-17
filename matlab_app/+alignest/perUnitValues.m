function perUnit = perUnitValues(results, metricName)
%PERUNITVALUES 手法 × 列（results.groups）ごとに、Wafer ごとの指標の値（ランダムの繰り返しは平均）を並べる。
%   perUnit{m, g} は Wafer 数の列ベクトル（その Wafer に結果が無ければ NaN）。
table_ = results.table;
nUnits = numel(results.unitLabels);
nMethods = numel(results.methods);
groups = results.groups;
perUnit = cell(nMethods, numel(groups));
[~, groupIndex] = ismember(table_.group, groups);
metric = table_.(metricName);
for m = 1:nMethods
    for g = 1:numel(groups)
        select = table_.methodIndex == m & groupIndex == g;
        sums = accumarray(table_.unitIndex(select), metric(select), [nUnits, 1], @(v) mean(v, 'omitnan'), NaN);
        perUnit{m, g} = sums;
    end
end
end
