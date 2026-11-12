function comparison = estimatedCorrectionComparison(data, results, selection, settings, options)
%ESTIMATEDCORRECTIONCOMPARISON 実測値で求めた Shot 高次補正と、推定値で求めた Shot 高次補正を、実測値に当てて比べる（「4. 結果一覧」）。
%   comparison = alignest.estimatedCorrectionComparison(data, results, selection, settings)
%   comparison = alignest.estimatedCorrectionComparison(..., cache=推定結果の Map, progressFcn=@(done, total) true)
%   data：計測データ（alignest.prepareData）、results：評価の結果（alignest.runEvaluation）、selection：methodIndex（手法。
%   results.methods の何番目か）・groups（学習パターンの列。results.groups の値）・unitIndex（Wafer。data.units の何番目か）。
%   settings：補正のモデル（settings.highOrder。「7. Shot高次補正」と同じ Wafer 高次補正・Shot 共通補正・Shot ごとの補正・回帰）と
%   settings.data.waferRadiusMm。
%   - 実測値で補正：Wafer の全 Mark の計測値で alignest.shotHighOrder を求め、計測値 − 補正量 を残差とする
%   - 推定値で補正：学習パターンごと・手法ごとに、学習に使った Mark は計測値（学習データの異常値として除いた Mark は使わない）、
%     ほかの Mark は推定値で alignest.shotHighOrder を求め、その補正量を計測値に当てた 計測値 − 補正量 を残差とする
%   どちらも、補正の段階（Wafer 高次補正だけ・＋Shot 共通補正）の残差も同じように求める。比べるのは、どちらの残差もある Mark。
%   comparison.table：手法・学習パターン・Wafer（と、すべての Wafer をまとめた行）・軸ごとの表。n（比べた点）・before（補正前の
%   |平均|+3σ）・measuredWaferStage・measuredCommonStage・measured（実測値で補正した残差。Wafer 高次補正だけ・＋Shot 共通補正・
%   高次補正）・estimatedWaferStage・estimatedCommonStage・estimated（推定値で補正した残差。同じ段階）・difference（estimated −
%   measured）・correctionDifference（推定値で求めた補正量 − 実測値で求めた補正量 の |平均|+3σ）[nm]
%   comparison.description：補正のモデル、comparison.messages：知らせ、comparison.cancelled：途中で止めたか
arguments
    data struct
    results struct
    selection struct
    settings struct
    options.cache = []
    options.progressFcn = []
end
ALL_LABEL = "すべての Wafer";
AXIS_NAMES = ["X", "Y"];
plans = results.plans;
planIndex = find(ismember(string({plans.group}), string(selection.groups)) & ...
    ismember([plans.unitIndex], selection.unitIndex) & [plans.ok]);
methodIndex = reshape(selection.methodIndex, 1, []);
messages = strings(0, 1);
cancelled = false;
if isempty(planIndex) || isempty(methodIndex)
    error('alignest:estimatedCorrection', '比べる手法・学習パターン・Wafer を選んでください（学習パターンを作れた Wafer）。');
end
unitIndexes = unique([plans(planIndex).unitIndex], 'stable');
measuredWafers = struct("label", {}, "points", {});
for u = unitIndexes
    measuredWafers(end + 1) = struct("label", string(data.units(u).label), ...
        "points", alignest.highOrderUnitPoints(data.units(u))); %#ok<AGROW>
end
measured = alignest.shotHighOrder(measuredWafers, settings);
planLabels = unique(string({plans(planIndex).label}), 'stable');
parts = cell(numel(planLabels) * numel(methodIndex), 1);
nTotal = numel(parts);
done = 0;
for L = 1:numel(planLabels)
    mine = planIndex(string({plans(planIndex).label}) == planLabels(L));
    for m = methodIndex
        done = done + 1;
        method = results.methods(m);
        estimatedWafers = struct("label", {}, "points", {});
        for p = mine
            unit = data.units(plans(p).unitIndex);
            try
                out = cachedEstimate(options.cache, unit, plans(p), p, m, method, results.settings);
            catch err
                messages(end + 1, 1) = unit.label + "｜" + plans(p).label + "｜" + method.label + "：" + err.message; %#ok<AGROW>
                continue
            end
            points = alignest.highOrderUnitPoints(unit, "推定値");
            [points.valueX, points.valueY] = estimatedValues(unit, plans(p), out);
            estimatedWafers(end + 1) = struct("label", string(unit.label), "points", points); %#ok<AGROW>
        end
        if isempty(estimatedWafers)
            continue
        end
        try
            estimated = alignest.shotHighOrder(estimatedWafers, settings);
        catch err
            messages(end + 1, 1) = planLabels(L) + "｜" + method.label + "：" + err.message; %#ok<AGROW>
            continue
        end
        waferLabels = string({estimatedWafers.label});
        rowParts = cell(numel(waferLabels) + 1, 2);
        pooledMeasured = cell(numel(waferLabels), 1);
        pooledEstimated = cell(numel(waferLabels), 1);
        for w = 1:numel(waferLabels)
            pooledMeasured{w} = measured.points(measured.points.wafer == waferLabels(w), :);
            pooledEstimated{w} = estimated.points(estimated.points.wafer == waferLabels(w), :);
            for a = 1:2
                rowParts{w, a} = comparisonRow(method.label, planLabels(L), waferLabels(w), AXIS_NAMES(a), ...
                    pooledMeasured{w}, pooledEstimated{w});
            end
        end
        for a = 1:2
            rowParts{end, a} = comparisonRow(method.label, planLabels(L), ALL_LABEL, AXIS_NAMES(a), ...
                vertcat(pooledMeasured{:}), vertcat(pooledEstimated{:}));
        end
        parts{done} = [vertcat(rowParts{:, 1}); vertcat(rowParts{:, 2})];
        if ~isempty(options.progressFcn) && ~options.progressFcn(done, nTotal)
            cancelled = true;
            break
        end
    end
    if cancelled
        break
    end
end
parts = parts(~cellfun(@isempty, parts));
if isempty(parts)
    error('alignest:estimatedCorrection', '比べられる組み合わせがありませんでした。%s', strjoin(messages, " "));
end
comparison = struct("table", vertcat(parts{:}), "description", string(measured.description), ...
    "messages", messages, "cancelled", cancelled);
end

function out = cachedEstimate(cache, unit, plan, planIndex, methodIndex, method, settings)
% 推定結果（alignest.estimateWafer）。画面の推定結果の Map があれば使い回す（キーは alignest.collectEstimates と同じ）
key = sprintf('%d|%d|%d', plan.unitIndex, planIndex, methodIndex);
useCache = isa(cache, 'containers.Map');
if useCache && isKey(cache, key)
    out = cache(key);
    return
end
out = alignest.estimateWafer(unit, plan, method, settings);
if useCache
    cache(key) = out; %#ok<NASGU> containers.Map は参照で共有される
end
end

function [valueX, valueY] = estimatedValues(unit, plan, out)
% 推定値で補正するときの値：学習に使った Mark は計測値（学習データの異常値として除いた Mark は NaN）、評価点は推定値
marks = unit.marks;
n = numel(marks.x);
inTrain = alignest.trainingMarks(unit, plan);
if isfield(out, "outlierIndex")
    inTrain(out.outlierIndex) = false;
end
valueX = nan(n, 1);
valueY = nan(n, 1);
useX = inTrain(:) & marks.validX(:);
useY = inTrain(:) & marks.validY(:);
valueX(useX) = marks.measX(useX);
valueY(useY) = marks.measY(useY);
valueX(out.testIndex.X) = out.estimate.X;
valueY(out.testIndex.Y) = out.estimate.Y;
end

function row = comparisonRow(methodLabel, planLabel, waferLabel, axisName, measuredPoints, estimatedPoints)
% 1つの手法・学習パターン・Wafer・軸の比べた値。点の行は同じ Mark の順（どちらも alignest.highOrderUnitPoints の順）
measuredValue = measuredPoints.("value" + axisName);
measuredResidual = measuredPoints.("residual" + axisName);
estimatedValue = estimatedPoints.("value" + axisName);
% 推定値で求めた補正量（段階ごと）＝ 推定値 − その残差。計測値に当てた残差 ＝ 計測値 − 補正量
correctionEstimated = estimatedValue - estimatedPoints.("residual" + axisName);
waferEstimated = estimatedValue - estimatedPoints.("waferResidual" + axisName);
commonEstimated = estimatedValue - estimatedPoints.("commonResidual" + axisName);
estimatedResidual = measuredValue - correctionEstimated;
compared = isfinite(measuredResidual) & isfinite(estimatedResidual);
correctionMeasured = measuredValue - measuredResidual;
row = table(string(methodLabel), string(planLabel), string(waferLabel), string(axisName), nnz(compared), ...
    meanPlus3Sigma(measuredValue(compared)), meanPlus3Sigma(measuredPoints.("waferResidual" + axisName)(compared)), ...
    meanPlus3Sigma(measuredPoints.("commonResidual" + axisName)(compared)), meanPlus3Sigma(measuredResidual(compared)), ...
    meanPlus3Sigma(measuredValue(compared) - waferEstimated(compared)), ...
    meanPlus3Sigma(measuredValue(compared) - commonEstimated(compared)), meanPlus3Sigma(estimatedResidual(compared)), ...
    meanPlus3Sigma(estimatedResidual(compared)) - meanPlus3Sigma(measuredResidual(compared)), ...
    meanPlus3Sigma(correctionEstimated(compared) - correctionMeasured(compared)), 'VariableNames', ["method", "plan", ...
    "wafer", "axis", "n", "before", "measuredWaferStage", "measuredCommonStage", "measured", "estimatedWaferStage", ...
    "estimatedCommonStage", "estimated", "difference", "correctionDifference"]);
end

function value = meanPlus3Sigma(values)
% |平均| + 3σ（σ は不偏標準偏差）。点が2点未満なら NaN（alignest.shotHighOrder と同じ）
values = values(isfinite(values));
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end
