function comparison = layoutComparison(results, methodIndex, metric, statistic)
%LAYOUTCOMPARISON 計測配置の選び方（I 最適・D 最適・ランダム・優先順・人の選択・Mark 単位）どうしを比べる表。
%   comparison = alignest.layoutComparison(results, methodIndex, metric, statistic)
%   1つの手法（results.methods(methodIndex)）について、学習パターンの列（results.groups）ごとに、指標 metric の
%   Wafer の集計 statistic（alignest.summarizeResults と同じ。ランダムのくり返しは Wafer ごとに平均）と、
%   学習 Shot 数・計測する Mark 数・I 基準・D 基準（Wafer の平均）を並べる。
%   comparison は表：group（列）・type（選び方：ioptimal・doptimal・random・file・manual・mark・markd）・typeLabel・
%   nShots（学習 Shot 数の平均）・nMarks（計測する Mark 数の平均。以前の結果・読み込んだ結果では NaN）・value・
%   criterionI・criterionD・efficiencyI・efficiencyD（全計測に対する効率 0〜1 の Wafer の平均）・
%   nWafers・sd（Wafer 間の標準偏差）・se（平均の標準誤差 = sd / √nWafers）・minValue・maxValue（Wafer の最小・最大）。
%   エラーバーは sd・se・minValue・maxValue から描く（alignest.layoutErrorBars）。
%   comparison.Properties.UserData に指標の名前・小さいほど良いか・選び方の数。
%   選び方は行の planType（評価した結果）から、無ければ列の名前の先頭（"I最適 20 Shot" など）から決める。
TYPES = ["ioptimal", "doptimal", "random", "file", "manual", "mark", "markd"];
LABELS = ["I 最適", "D 最適", "ランダム", "優先順", "人の選択・手動", "Mark 単位の I 最適", "Mark 単位の D 最適"];
PREFIXES = ["I最適", "D最適", "ランダム", "優先順", "", "Mark最適", "MarkD最適"];
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
plans = results.plans;
for g = 1:n
    rows = table_(table_.group == groups(g), :);
    if ~isempty(rows) && any(string(rows.Properties.VariableNames) == "planType") && rows.planType(1) ~= ""
        types(g) = rows.planType(1);
    else
        types(g) = typeFromName(groups(g), results, PREFIXES, TYPES);
    end
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
end
[~, position] = ismember(types, TYPES);
typeLabel = strings(n, 1);
typeLabel(position > 0) = LABELS(position(position > 0));
typeLabel(position == 0) = "（不明）";
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
    efficiencyI, efficiencyD, nWafers, sd, se, minValue, maxValue, ...
    'VariableNames', ["group", "type", "typeLabel", "nShots", "nMarks", "value", "criterionI", "criterionD", ...
    "efficiencyI", "efficiencyD", "nWafers", "sd", "se", "minValue", "maxValue"]);
comparison.Properties.UserData = struct("metric", metric, "statistic", statistic, "lowerIsBetter", ...
    summary.lowerIsBetter, "nTypes", numel(unique(types(types ~= ""))), "methodLabel", results.methods(methodIndex).label);
end

function type = typeFromName(name, results, prefixes, types)
% 列の名前の先頭（選び方を比べたときの名前）から選び方を決める。無ければ設定の選び方（1つのとき）
type = "";
for k = 1:numel(prefixes)
    if prefixes(k) ~= "" && startsWith(name, prefixes(k) + " ")
        type = types(k);
        return
    end
end
methods = string(results.settings.sampling.method);
if isscalar(methods)
    type = methods;
elseif ~contains(name, " Shot") && ~startsWith(name, "計測率")
    type = "manual";
end
end
