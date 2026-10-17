function summary = summarizeResults(results, metricName, statistic)
%SUMMARIZERESULTS 手法 × 学習パターン（Shot 数など）の表にまとめる。
%   ランダムの繰り返しは、まず Wafer ごとに平均してから Wafer 間で集計する（Wafer の重みをそろえるため）。
%   statistic = "mean"（平均）または "median"（中央値）。
%   summary.values（手法 × 列）、summary.counts（集計した Wafer 数）、summary.methodIds / methodLabels、summary.groups
arguments
    results struct
    metricName (1, 1) string = "RMSE_XY"
    statistic (1, 1) string = "mean"
end
methods = results.methods;
groups = results.groups;
perUnit = alignest.perUnitValues(results, metricName);
values = nan(numel(methods), numel(groups));
counts = zeros(numel(methods), numel(groups));
for m = 1:numel(methods)
    for g = 1:numel(groups)
        unitValues = perUnit{m, g};
        unitValues = unitValues(~isnan(unitValues));
        counts(m, g) = numel(unitValues);
        if isempty(unitValues)
            continue
        end
        if statistic == "median"
            values(m, g) = median(unitValues);
        else
            values(m, g) = mean(unitValues);
        end
    end
end
summary.values = values;
summary.counts = counts;
summary.methodIds = string({methods.id}).';
summary.methodLabels = string({methods.label}).';
summary.groups = groups;
summary.metricName = metricName;
summary.statistic = statistic;
summary.lowerIsBetter = ~startsWith(metricName, ["R2", "adjR2"]);
end
