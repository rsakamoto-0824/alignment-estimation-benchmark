function comparison = pairedComparison(results, referenceId, metricName)
%PAIREDCOMPARISON 基準の手法と、同じ Wafer・同じ学習パターンどうしで比べる。
%   誤差の指標（RMSE・MAE）：差の割合 = 平均[(手法 − 基準) / 基準] × 100 [%]。負なら基準より良い。
%   R²・改善量・改善率    ：差 = 平均[手法 − 基準]。正なら基準より良い。
%   良かった割合：基準より良かった Wafer の割合。95% 区間は Wafer 間のばらつきから求めた平均の区間（正規近似で 平均 ± 1.96 × 標準誤差）。
arguments
    results struct
    referenceId (1, 1) string
    metricName (1, 1) string = "RMSE_XY"
end
methods = results.methods;
reference = find(string({methods.id}) == referenceId, 1);
if isempty(reference)
    error('alignest:reference', '基準の手法が結果にありません: %s', referenceId);
end
lowerIsBetter = ~alignest.metricHigherIsBetter(metricName);
perUnit = alignest.perUnitValues(results, metricName);
groups = results.groups;
names = strings(0, 1);
groupColumn = strings(0, 1);
difference = zeros(0, 1);
lowerBound = zeros(0, 1);
upperBound = zeros(0, 1);
winRate = zeros(0, 1);
nUnits = zeros(0, 1);
for m = 1:numel(methods)
    if m == reference
        continue
    end
    for g = 1:numel(groups)
        target = perUnit{m, g};
        base = perUnit{reference, g};
        usable = ~isnan(target) & ~isnan(base);
        if lowerIsBetter
            usable = usable & base > 0;
            change = (target(usable) - base(usable)) ./ base(usable) * 100;
            better = target(usable) < base(usable);
        else
            change = target(usable) - base(usable);
            better = target(usable) > base(usable);
        end
        names(end + 1, 1) = methods(m).label; %#ok<AGROW>
        groupColumn(end + 1, 1) = groups(g); %#ok<AGROW>
        nUnits(end + 1, 1) = numel(change); %#ok<AGROW>
        if isempty(change)
            difference(end + 1, 1) = NaN; %#ok<AGROW>
            lowerBound(end + 1, 1) = NaN; %#ok<AGROW>
            upperBound(end + 1, 1) = NaN; %#ok<AGROW>
            winRate(end + 1, 1) = NaN; %#ok<AGROW>
            continue
        end
        standardError = std(change) / sqrt(numel(change));
        difference(end + 1, 1) = mean(change); %#ok<AGROW>
        lowerBound(end + 1, 1) = mean(change) - 1.96 * standardError; %#ok<AGROW>
        upperBound(end + 1, 1) = mean(change) + 1.96 * standardError; %#ok<AGROW>
        winRate(end + 1, 1) = mean(better); %#ok<AGROW>
    end
end
comparison = table(names, groupColumn, difference, lowerBound, upperBound, winRate, nUnits, ...
    'VariableNames', ["method", "group", "difference", "lower95", "upper95", "winRate", "nWafers"]);
comparison.Properties.UserData = struct("referenceLabel", methods(reference).label, "lowerIsBetter", lowerIsBetter, ...
    "metricName", metricName);
end
