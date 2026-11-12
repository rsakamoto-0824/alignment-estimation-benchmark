function ranking = waferRanking(results, metrics, overallMetrics)
%WAFERRANKING Wafer のベスト・平均・ワースト：手法 × 学習パターンの列 × 指標ごとに、最も良い・平均に近い・最も悪い Wafer。
%   ranking = alignest.waferRanking(results)
%   ranking = alignest.waferRanking(results, metrics, overallMetrics)
%   metrics：比べる指標（既定：結果の指標すべて。処理時間を除く）。
%   overallMetrics：総合の順位に使う指標（既定：RMSE（X・Y 合計）と、Overlay 補正を評価したときは推定値で補正した残差 X・Y）。
%   推定誤差と補正残差のように、指標によってベスト・ワーストの Wafer が違うことがあるので、指標ごとに出す。
%   Wafer ごとの値は alignest.perUnitValues と同じ（ランダムの繰り返しは平均）。評価した Wafer のうち値のある Wafer で比べる。
%   ベスト・ワースト：指標の良い向き（alignest.metricHigherIsBetter）で最も良い・悪い Wafer。
%   平均：Wafer の値の平均に最も近い Wafer（その条件の代表の Wafer）。同じ値・同じ近さなら先の Wafer。
%   順位：1 = 最も良い。同じ値の Wafer は順位の平均。
%   総合：overallMetrics の順位の平均（値の無い指標は除く）が最も小さい Wafer をベスト、最も大きい Wafer をワースト、
%   順位の平均の平均（全 Wafer に値があれば真ん中の順位 (n + 1) / 2）に最も近い Wafer を平均とする。
%   ranking.table：1行 = 手法 × 列 × 指標（指標の行の後に総合の行。metric = "overall"）。列：
%     methodIndex, methodId, method, group, metric, metricLabel, nWafers, mean,
%     bestUnit, bestWafer, bestValue, averageUnit, averageWafer, averageValue, worstUnit, worstWafer, worstValue
%     （unit は results.unitLabels の番号、Wafer はその名前。総合の行の値は順位の平均）
%   ranking.units：評価した Wafer の番号（alignest.evaluatedUnits）、ranking.unitLabels：その名前、
%   ranking.metrics・metricLabels・higherIsBetter・overallMetrics：使った指標、
%   ranking.values{m, g}・ranking.ranks{m, g}：Wafer（ranking.units の順）× 指標 の値と順位、
%   ranking.overallRank{m, g}：Wafer ごとの総合の順位の平均
arguments
    results struct
    metrics (1, :) string = defaultMetrics(results)
    overallMetrics (1, :) string = defaultOverallMetrics(results)
end
metrics = metrics(ismember(metrics, string(results.table.Properties.VariableNames)));
overallMetrics = overallMetrics(ismember(overallMetrics, metrics));
units = reshape(alignest.evaluatedUnits(results), [], 1);
groups = reshape(string(results.groups), 1, []);
nUnits = numel(units);
nMethods = numel(results.methods);
nGroups = numel(groups);
nMetrics = numel(metrics);
higher = reshape(alignest.metricHigherIsBetter(metrics), 1, []);

ranking.units = units;
ranking.unitLabels = reshape(string(results.unitLabels(units)), [], 1);
ranking.metrics = metrics;
ranking.metricLabels = metricLabels(results, metrics);
ranking.higherIsBetter = higher;
ranking.overallMetrics = overallMetrics;

% Wafer ごとの値（ランダムの繰り返しは平均）。手法 × 列 × 指標ごとに perUnitValues を呼ぶと遅いので、まとめて平均する
values = waferValues(results, units, groups, metrics);
ranking.values = cell(nMethods, nGroups);
ranking.ranks = cell(nMethods, nGroups);
ranking.overallRank = cell(nMethods, nGroups);
overallColumns = ismember(metrics, overallMetrics);
nRows = nMethods * nGroups * (nMetrics + 1);
rows = emptyRows(nRows);
row = 0;
methodIds = string({results.methods.id});
methodLabels = string({results.methods.label});
for m = 1:nMethods
    for g = 1:nGroups
        unitValues = reshape(values(:, m, g, :), nUnits, nMetrics);
        ranks = nan(nUnits, nMetrics);
        for k = 1:nMetrics
            ranks(:, k) = rankColumn(unitValues(:, k), higher(k));
        end
        if any(overallColumns)
            overall = mean(ranks(:, overallColumns), 2, 'omitnan');
        else
            overall = nan(nUnits, 1);
        end
        ranking.values{m, g} = unitValues;
        ranking.ranks{m, g} = ranks;
        ranking.overallRank{m, g} = overall;
        for k = 1:nMetrics + 1
            row = row + 1;
            rows.methodIndex(row) = m;
            rows.methodId(row) = methodIds(m);
            rows.method(row) = methodLabels(m);
            rows.group(row) = groups(g);
            if k <= nMetrics
                rows.metric(row) = metrics(k);
                rows.metricLabel(row) = ranking.metricLabels(k);
                picked = pick(unitValues(:, k), higher(k));
            else
                rows.metric(row) = "overall";
                rows.metricLabel(row) = "総合（順位の平均）";
                picked = pick(overall, false);
            end
            rows.nWafers(row) = picked.count;
            rows.mean(row) = picked.mean;
            for kind = ["best", "average", "worst"]
                position = picked.(kind);
                if position > 0
                    rows.(kind + "Unit")(row) = units(position);
                    rows.(kind + "Wafer")(row) = ranking.unitLabels(position);
                    rows.(kind + "Value")(row) = picked.values(position);
                end
            end
        end
    end
end
ranking.table = struct2table(rows);
end

function values = waferValues(results, units, groups, metrics)
% Wafer × 手法 × 列 × 指標 の値（同じ Wafer・手法・列の行の平均。NaN は除く。行が無ければ NaN）。
% alignest.perUnitValues と同じ値を、指標ごとに1回の集計で求める
table_ = results.table;
nUnits = numel(units);
nMethods = numel(results.methods);
nGroups = numel(groups);
[~, unitPosition] = ismember(table_.unitIndex, units);
[~, groupIndex] = ismember(string(table_.group), groups);
keep = unitPosition > 0 & groupIndex > 0 & table_.methodIndex >= 1 & table_.methodIndex <= nMethods;
cellIndex = sub2ind([nUnits, nMethods, nGroups], unitPosition(keep), table_.methodIndex(keep), groupIndex(keep));
nCells = nUnits * nMethods * nGroups;
values = nan(nUnits, nMethods, nGroups, numel(metrics));
for k = 1:numel(metrics)
    metric = table_.(metrics(k))(keep);
    valid = ~isnan(metric);
    sums = accumarray(cellIndex(valid), metric(valid), [nCells, 1]);
    counts = accumarray(cellIndex(valid), 1, [nCells, 1]);
    averaged = sums ./ counts;   % 値の無い組は 0 / 0 = NaN
    values(:, :, :, k) = reshape(averaged, nUnits, nMethods, nGroups);
end
end

function rank = rankColumn(values, higherIsBetter)
% 順位（1 = 最も良い）。同じ値は順位の平均、値の無い Wafer は NaN
rank = nan(size(values));
valid = find(~isnan(values));
if isempty(valid)
    return
end
key = values(valid);
if higherIsBetter
    key = -key;
end
[sortedKey, order] = sort(key);
[~, ~, tie] = unique(sortedKey);
averaged = accumarray(tie, (1:numel(valid)).', [], @mean);
rank(valid(order)) = averaged(tie);
end

function picked = pick(values, higherIsBetter)
% 値のある Wafer のうち、最も良い・平均に最も近い・最も悪い Wafer の位置（無ければ 0）
picked = struct("values", values, "count", 0, "mean", NaN, "best", 0, "average", 0, "worst", 0);
valid = find(~isnan(values));
if isempty(valid)
    return
end
picked.count = numel(valid);
picked.mean = mean(values(valid));
if higherIsBetter
    [~, best] = max(values(valid));
    [~, worst] = min(values(valid));
else
    [~, best] = min(values(valid));
    [~, worst] = max(values(valid));
end
[~, average] = min(abs(values(valid) - picked.mean));
picked.best = valid(best);
picked.average = valid(average);
picked.worst = valid(worst);
end

function rows = emptyRows(n)
rows = struct("methodIndex", zeros(n, 1), "methodId", strings(n, 1), "method", strings(n, 1), ...
    "group", strings(n, 1), "metric", strings(n, 1), "metricLabel", strings(n, 1), "nWafers", zeros(n, 1), ...
    "mean", nan(n, 1), "bestUnit", zeros(n, 1), "bestWafer", strings(n, 1), "bestValue", nan(n, 1), ...
    "averageUnit", zeros(n, 1), "averageWafer", strings(n, 1), "averageValue", nan(n, 1), ...
    "worstUnit", zeros(n, 1), "worstWafer", strings(n, 1), "worstValue", nan(n, 1));
end

function labels = metricLabels(results, metrics)
[names, allLabels] = alignest.metricNames(true, true, resultSpec(results));
labels = metrics;
[found, position] = ismember(metrics, names);
labels(found) = allLabels(position(found));
end

function metrics = defaultMetrics(results)
% 結果の指標すべて（処理時間は Wafer の良し悪しではないので除く）
overlay = isfield(results, "overlayEvaluated") && results.overlayEvaluated;
metrics = alignest.metricNames(false, overlay, resultSpec(results));
end

function metrics = defaultOverallMetrics(results)
% 推定誤差の代表（RMSE（X・Y 合計））と、Overlay 補正を評価したときは推定値で補正した残差（X・Y）。
% 結果に無い指標（1変数の Overlay の指標など）は、使う指標を決めるときに除く
metrics = "RMSE_XY";
if isfield(results, "overlayEvaluated") && results.overlayEvaluated
    metrics = [metrics, "overlayEstimated_X", "overlayEstimated_Y"];
end
end

function spec = resultSpec(results)
% 評価した設定の推定する値（1変数なら X・Y 別と Overlay の指標が無い）
source = struct();
if isfield(results, "settings") && isfield(results.settings, "data")
    source = results.settings.data;
end
spec = alignest.valueSpec(source);
end
