function comparison = layoutComparison(results, methodIndex, metric, statistic, data)
%LAYOUTCOMPARISON 計測配置の選び方（I 最適・D 最適・ランダム・Sobol 列・ポアソンディスク・Excel の優先順とパターン・
%   Mark 単位）どうしを比べる表。
%   comparison = alignest.layoutComparison(results, methodIndex, metric, statistic)
%   comparison = alignest.layoutComparison(..., data)   % 計測率（rate）を求めるための読み込んだデータ（alignest.prepareData）
%   1つの手法（results.methods(methodIndex)）について、学習パターンの列（results.groups）ごとに、指標 metric の
%   Wafer の集計 statistic（alignest.summarizeResults と同じ。ランダムのくり返しは Wafer ごとに平均）と、
%   学習 Shot 数・計測する Mark 数・I 基準・D 基準（Wafer の平均）を並べる。
%   comparison は表：group（列）・type（選び方：ioptimal・doptimal・random・sobol・poisson・file（Excel の優先順。以前の
%   ファイルの優先順）・manual（Excel のパターン。以前の手動・人の選択）・mark・markd・markrandom・marksobol・
%   markpoisson）・typeLabel・
%   nShots（学習 Shot 数の平均）・nMarks（計測する Mark 数の平均。以前の結果・読み込んだ結果では NaN）・value・
%   criterionI・criterionD・efficiencyI・efficiencyD（全計測に対する効率 0〜1 の Wafer の平均）・rate（計測率 [%]：計測率で
%   決めた学習パターンはその値、ほかは 計測する Mark の数 / 候補の全 Mark の数 × 100 の Wafer の平均。data が無い・Wafer が
%   合わないときは NaN）・
%   nWafers・sd（Wafer 間の標準偏差）・se（平均の標準誤差 = sd / √nWafers）・minValue・maxValue（Wafer の最小・最大）。
%   エラーバーは sd・se・minValue・maxValue から描く（alignest.layoutErrorBars）。
%   comparison.Properties.UserData に指標の名前・小さいほど良いか・選び方の数。
%   選び方は alignest.groupSelectionTypes（行の planType、無ければ列の名前の先頭）。
summary = alignest.summarizeResults(results, metric, statistic);
table_ = results.table(results.table.methodIndex == methodIndex, :);
groups = reshape(string(summary.groups), [], 1);
n = numel(groups);
types = strings(n, 1);
nShots = nan(n, 1);
nMarks = nan(n, 1);
criterionI = nan(n, 1);
criterionD = nan(n, 1);
efficiencyI = nan(n, 1);
efficiencyD = nan(n, 1);
rate = nan(n, 1);
plans = results.plans;
if nargin < 5
    data = [];
end
[groupTypes, groupLabels] = alignest.groupSelectionTypes(results);   % 列ごとの選び方
[~, groupIndex] = ismember(groups, reshape(string(results.groups), [], 1));
typeLabel = repmat("（不明）", n, 1);
types(groupIndex > 0) = groupTypes(groupIndex(groupIndex > 0));
typeLabel(groupIndex > 0) = groupLabels(groupIndex(groupIndex > 0));
for g = 1:n
    rows = table_(table_.group == groups(g), :);
    if ~isempty(rows)
        nShots(g) = mean(rows.nShots, 'omitnan');
        criterionI(g) = mean(rows.criterionI, 'omitnan');
        criterionD(g) = mean(rows.criterionD, 'omitnan');
        if any(string(rows.Properties.VariableNames) == "efficiencyI")
            efficiencyI(g) = mean(rows.efficiencyI, 'omitnan');
            efficiencyD(g) = mean(rows.efficiencyD, 'omitnan');
        end
    end
    inGroup = string({plans.group}) == groups(g);
    if isfield(plans, "nMarks") && any(inGroup)
        counts = [plans(inGroup).nMarks];
        if any(counts > 0)
            nMarks(g) = mean(counts(counts > 0));
        end
    end
    rate(g) = groupRate(plans(inGroup), data, results);
end
values = summary.values(summary.methodIds == results.methods(methodIndex).id, :);
if isempty(values)
    values = nan(1, n);
end
% Wafer ごとの値（ランダムのくり返しは平均）のばらつき：エラーバーに使う
perUnit = alignest.perUnitValues(results, metric);
[~, groupPosition] = ismember(groups, string(results.groups));
nWafers = zeros(n, 1);
sd = nan(n, 1);
minValue = nan(n, 1);
maxValue = nan(n, 1);
for g = 1:n
    if groupPosition(g) == 0
        continue
    end
    unitValues = perUnit{methodIndex, groupPosition(g)};
    unitValues = unitValues(isfinite(unitValues));
    nWafers(g) = numel(unitValues);
    if nWafers(g) >= 2
        sd(g) = std(unitValues);
    end
    if nWafers(g) >= 1
        minValue(g) = min(unitValues);
        maxValue(g) = max(unitValues);
    end
end
se = sd ./ sqrt(nWafers);
comparison = table(groups, types, typeLabel, nShots, nMarks, reshape(values, [], 1), criterionI, criterionD, ...
    efficiencyI, efficiencyD, rate, nWafers, sd, se, minValue, maxValue, ...
    'VariableNames', ["group", "type", "typeLabel", "nShots", "nMarks", "value", "criterionI", "criterionD", ...
    "efficiencyI", "efficiencyD", "rate", "nWafers", "sd", "se", "minValue", "maxValue"]);
comparison.Properties.UserData = struct("metric", metric, "statistic", statistic, "lowerIsBetter", ...
    summary.lowerIsBetter, "nTypes", numel(unique(types(types ~= ""))), "methodLabel", results.methods(methodIndex).label);
end

function value = groupRate(plans, data, results)
% 列の計測率 [%]（Wafer の平均）：計測率で決めた学習パターンはその値、ほかは 計測する Mark の数 / 候補の全 Mark の数。
% 求められない（読み込んだデータが無い・Wafer の名前が合わない）ときは NaN
values = nan(1, numel(plans));
for k = 1:numel(plans)
    plan = plans(k);
    if isfield(plan, "rate") && isfinite(plan.rate)
        values(k) = plan.rate;
        continue
    end
    if isempty(data) || ~isfield(plan, "unitIndex") || plan.unitIndex < 1 || plan.unitIndex > numel(data.units) || ...
            ~isfield(plan, "nMarks") || plan.nMarks <= 0
        continue
    end
    unit = data.units(plan.unitIndex);
    if isfield(results, "unitLabels") && plan.unitIndex <= numel(results.unitLabels) && ...
            string(results.unitLabels(plan.unitIndex)) ~= string(unit.label)
        continue   % 別のデータの結果
    end
    candidates = ismember(unit.marks.shotIndex, find(unit.shots.nValidX + unit.shots.nValidY > 0)) & ...
        (unit.marks.validX | unit.marks.validY);
    values(k) = 100 * plan.nMarks / max(nnz(candidates), 1);
end
value = mean(values, 'omitnan');
end
