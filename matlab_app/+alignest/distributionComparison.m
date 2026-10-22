function comparison = distributionComparison(data, results, selection, estimates)
%DISTRIBUTIONCOMPARISON 計測値の分布（Wafer 全面・学習データ・予測対象）と、予測対象の実測値と推定値の分布を比べる。
%   comparison = alignest.distributionComparison(data, results, selection, estimates)
%   selection：methodIndex（手法1つ）・groups（学習パターンの列）・unitIndex（Wafer）。estimates はその推定値の表
%   （alignest.collectEstimates）。X・Y それぞれ、次の4つの値の集まりを作る（選んだ Wafer をまとめる）：
%   - 全面：Wafer の有効なすべての Mark の計測値（Wafer ごとに1回）
%   - 学習：学習 Shot の有効な Mark の計測値（学習データの異常値を除く設定なら、評価と同じく除く）
%   - 予測対象（実測）：評価点（学習しなかった Shot の有効な Mark）の計測値
%   - 推定値：評価点の推定値
%   ランダムのくり返しなど、1つの列に学習パターンが複数あるときは、学習と予測対象をまとめて数える。
%   comparison.X / Y：samples（1 × 4 のセル）・names・edges（4つに共通のヒストグラムの区間）・
%   stats（代表統計値の表。alignest.stats.distributionSummary）・js（組ごとの JS ダイバージェンスの表）。
NAMES = ["全面", "学習", "予測対象（実測）", "推定値"];
PAIRS = [1, 2; 1, 3; 2, 3; 3, 4];
PAIR_NOTES = ["学習データが Wafer 全面を代表しているか", "予測対象が Wafer 全面を代表しているか", ...
    "学習データと予測対象が似ているか", "推定値の分布が予測対象の実測値と合っているか"];
settings = results.settings;
plans = results.plans;
planIndex = find(ismember(string({plans.group}), string(selection.groups)) & ...
    ismember([plans.unitIndex], selection.unitIndex) & [plans.ok]);
excludeOutliers = isfield(settings.evaluation, "excludeOutliers") && settings.evaluation.excludeOutliers;
for axisName = ["X", "Y"]
    whole = cell(1, 0);
    train = cell(1, 0);
    for u = unique([plans(planIndex).unitIndex])
        marks = data.units(u).marks;
        whole{end + 1} = marks.("meas" + axisName)(marks.("valid" + axisName)); %#ok<AGROW>
    end
    for p = planIndex
        marks = data.units(plans(p).unitIndex).marks;
        inTrain = ismember(marks.shotIndex, plans(p).shotIndex);
        use = inTrain & marks.("valid" + axisName);
        if excludeOutliers
            use = use & ~alignest.trainingOutliers(marks, inTrain, settings.evaluation.outlierSigma);
        end
        train{end + 1} = marks.("meas" + axisName)(use); %#ok<AGROW>
    end
    samples = {vertcat(whole{:}, zeros(0, 1)), vertcat(train{:}, zeros(0, 1)), ...
        estimates.("meas" + axisName)(isfinite(estimates.("meas" + axisName))), ...
        estimates.("estimate" + axisName)(isfinite(estimates.("estimate" + axisName)))};
    edges = commonEdges(vertcat(samples{:}));
    summaries = repmat(alignest.stats.distributionSummary([]), numel(samples), 1);
    for k = 1:numel(samples)
        summaries(k) = alignest.stats.distributionSummary(samples{k});
    end
    stats = struct2table(summaries);
    stats = [table(NAMES(:), 'VariableNames', "name"), stats]; %#ok<AGROW>
    js = nan(size(PAIRS, 1), 1);
    for k = 1:size(PAIRS, 1)
        js(k) = alignest.stats.jsDivergence(samples{PAIRS(k, 1)}, samples{PAIRS(k, 2)}, edges);
    end
    pairNames = NAMES(PAIRS(:, 1)) + " と " + NAMES(PAIRS(:, 2));
    comparison.(axisName) = struct("samples", {samples}, "names", NAMES, "edges", edges, "stats", stats, ...
        "js", table(pairNames(:), js, PAIR_NOTES(:), 'VariableNames', ["pair", "js", "meaning"]));
end
comparison.nWafers = numel(unique([plans(planIndex).unitIndex]));
comparison.nPlans = numel(planIndex);
end

function edges = commonEdges(values)
% 4つの集まりに共通の区間：まとめた値で Freedman–Diaconis の幅を決め、区間の数を 10〜60 にそろえる
MIN_BINS = 10;
MAX_BINS = 60;
values = values(isfinite(values));
if isempty(values)
    edges = [-1, 1];
    return
end
low = min(values);
high = max(values);
if high <= low
    edges = low + [-0.5, 0.5];
    return
end
spread = alignest.stats.percentile(values, 75) - alignest.stats.percentile(values, 25);
width = 2 * spread / numel(values) ^ (1 / 3);
count = MAX_BINS;
if width > 0
    count = ceil((high - low) / width);
end
count = min(max(count, MIN_BINS), MAX_BINS);
edges = linspace(low, high, count + 1);
end
