function summary = summarizeResults(results, metricName, statistic)
%SUMMARIZERESULTS 手法 × 学習パターン（Shot 数など）の表にまとめる。
%   ランダムの繰り返しは、まず Wafer ごとに平均してから Wafer 間で集計する（Wafer の重みをそろえるため）。
%   statistic = "mean"（平均）・"median"（中央値）・"worst"（ワースト値）・"p95"（95%値）。alignest.statisticNames を参照。
%   ワースト値・95%値は、誤差（RMSE・MAE・処理時間）なら大きい側、R²・調整済み R² なら小さい側で取る。
%   summary.values（手法 × 列）、summary.counts（集計した Wafer 数）、summary.methodIds / methodLabels、summary.groups
arguments
    results struct
    metricName (1, 1) string = "RMSE_XY"
    statistic (1, 1) string = "mean"
end
methods = results.methods;
groups = results.groups;
perUnit = alignest.perUnitValues(results, metricName);
lowerIsBetter = ~startsWith(metricName, ["R2", "adjR2"]);
if ~any(statistic == alignest.statisticNames())
    error('alignest:statistic', '集計のしかたは %s のいずれかです: %s', strjoin(alignest.statisticNames(), "・"), statistic);
end
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
        values(m, g) = aggregate(unitValues, statistic, lowerIsBetter);
    end
end
summary.values = values;
summary.counts = counts;
summary.methodIds = string({methods.id}).';
summary.methodLabels = string({methods.label}).';
summary.groups = groups;
summary.metricName = metricName;
summary.statistic = statistic;
summary.lowerIsBetter = lowerIsBetter;
end

function value = aggregate(values, statistic, lowerIsBetter)
switch statistic
    case "median"
        value = median(values);
    case "worst"
        if lowerIsBetter
            value = max(values);
        else
            value = min(values);
        end
    case "p95"
        if lowerIsBetter
            value = alignest.stats.percentile(values, 95);
        else
            value = alignest.stats.percentile(values, 5);
        end
    otherwise
        value = mean(values);
end
end
