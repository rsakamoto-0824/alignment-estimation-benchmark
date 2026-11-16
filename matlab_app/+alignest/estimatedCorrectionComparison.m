function comparison = estimatedCorrectionComparison(data, results, selection, settings, options)
%ESTIMATEDCORRECTIONCOMPARISON 実測値で求めた補正と、推定値で求めた補正を、実測値に当てて比べる（「4. 結果一覧」）。
%   comparison = alignest.estimatedCorrectionComparison(data, results, selection, settings)
%   comparison = alignest.estimatedCorrectionComparison(..., cache=推定結果の Map, progressFcn=@(done, total) true)
%   data：計測データ（alignest.prepareData）、results：評価の結果（alignest.runEvaluation）、selection：methodIndex（手法。
%   results.methods の何番目か）・groups（学習パターンの列。results.groups の値）・unitIndex（Wafer。data.units の何番目か）。
%   settings：補正のモデルは「2. 評価の設定」の Overlay 補正の評価（settings.overlay：Wafer 成分・Shot 共通成分・Shot ごとの
%   成分。alignest.overlayChoice・overlayProjector）と settings.data.waferRadiusMm。補正は最小二乗で、全 Mark で求める
%   （alignest.overlayCorrection と同じ）。
%   - 実測値で補正：全 Mark の計測値で補正を求め、計測値 − 補正量 を残差とする
%   - 推定値で補正：学習に使った Mark は計測値、ほかの Mark は推定値で補正を求め、その補正量を計測値に当てた 計測値 − 補正量 を
%     残差とする（実際の運用で、推定値から補正を求めたときの残差）
%   補正の段階（Wafer 成分だけ・＋Shot 共通成分・全成分（＋Shot ごとの成分））の残差も同じように求める（使わない成分の段階は
%   前の段階と同じ値）。比べる範囲は、すべての点（scope = "すべての点"：残差のある全 Mark）と、推定対象の点（"推定対象の点"：
%   学習に使わなかった Mark。推定値が補正に入る点）の2つ。
%   comparison.table：手法・学習パターン・Wafer（と、すべての Wafer をまとめた行）・範囲・軸ごとの表。n（比べた点）・before
%   （補正前の |平均|+3σ）・measuredWaferStage・measuredCommonStage・measured（実測値で補正した残差。Wafer 成分だけ・＋Shot 共通
%   成分・全成分）・estimatedWaferStage・estimatedCommonStage・estimated（推定値で補正した残差。同じ段階）・difference
%   （estimated − measured）・correctionDifference（推定値で求めた補正量 − 実測値で求めた補正量 の |平均|+3σ）[nm]
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
SCOPES = ["すべての点", "推定対象の点"];
AXIS_NAMES = ["X", "Y"];
choice = alignest.overlayChoice(settings);
if ~choice.enabled
    error('alignest:estimatedCorrection', ['「2. 評価の設定」の Overlay 補正の評価がすべて「なし」です。Wafer 成分・' ...
        'Shot 共通成分・Shot ごとの成分のどれかを選んでください。']);
end
stages = stageChoices(choice);
plans = results.plans;
planIndex = find(ismember(string({plans.group}), string(selection.groups)) & ...
    ismember([plans.unitIndex], selection.unitIndex) & [plans.ok]);
methodIndex = reshape(selection.methodIndex, 1, []);
messages = strings(0, 1);
cancelled = false;
if isempty(planIndex) || isempty(methodIndex)
    error('alignest:estimatedCorrection', '比べる手法・学習パターン・Wafer を選んでください（学習パターンを作れた Wafer）。');
end
waferRadiusMm = settings.data.waferRadiusMm;
projectors = containers.Map('KeyType', 'double', 'ValueType', 'any');   % Wafer の番号 → 段階ごとの補正モデル
planLabels = unique(string({plans(planIndex).label}), 'stable');
parts = cell(numel(planLabels) * numel(methodIndex), 1);
nTotal = numel(parts);
done = 0;
for L = 1:numel(planLabels)
    mine = planIndex(string({plans(planIndex).label}) == planLabels(L));
    for m = methodIndex
        done = done + 1;
        method = results.methods(m);
        pooled = cell(numel(mine), 1);   % Wafer ごとの点の値（すべての Wafer をまとめる行に使う）
        rowParts = cell(numel(mine) + 1, 1);
        for j = 1:numel(mine)
            p = mine(j);
            unit = data.units(plans(p).unitIndex);
            try
                out = cachedEstimate(options.cache, unit, plans(p), p, m, method, results.settings);
                if ~isKey(projectors, plans(p).unitIndex)
                    projectors(plans(p).unitIndex) = arrayfun(@(stage) stageProjector(unit, stage, waferRadiusMm), stages, ...
                        'UniformOutput', false);
                end
                pooled{j} = pointValues(unit, plans(p), out, projectors(plans(p).unitIndex));
            catch err
                messages(end + 1, 1) = unit.label + "｜" + plans(p).label + "｜" + method.label + "：" + err.message; %#ok<AGROW>
                continue
            end
            rowParts{j} = waferRows(method.label, planLabels(L), string(unit.label), pooled{j}, SCOPES, AXIS_NAMES);
        end
        pooled = pooled(~cellfun(@isempty, pooled));
        if isempty(pooled)
            continue
        end
        rowParts{end} = waferRows(method.label, planLabels(L), ALL_LABEL, joinValues(pooled), SCOPES, AXIS_NAMES);
        parts{done} = vertcat(rowParts{:});
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
comparison = struct("table", vertcat(parts{:}), "description", string(choice.description), ...
    "messages", messages, "cancelled", cancelled);
end

function stages = stageChoices(choice)
% 補正の段階の補正モデル：Wafer 成分だけ・＋Shot 共通成分・全成分（＋Shot ごとの成分）。成分の無い段階は補正しない
waferOnly = choice;
waferOnly.shotCommon = "none";
waferOnly.perShot = "none";
withCommon = choice;
withCommon.perShot = "none";
stages = [waferOnly, withCommon, choice];
for k = 1:numel(stages)
    stages(k).enabled = stages(k).waferOrder > 0 || stages(k).waferUseFormula || stages(k).shotCommon ~= "none" || ...
        stages(k).perShot ~= "none";
end
end

function projector = stageProjector(unit, stage, waferRadiusMm)
% 段階の補正モデル（成分が無ければ []：補正しない）
projector = [];
if stage.enabled
    projector = alignest.overlayProjector(unit, stage, waferRadiusMm);
end
end

function values = pointValues(unit, plan, out, projectors)
% 1つの Wafer の点ごとの値：計測値（actual）、段階ごとの実測値で補正した残差・推定値で補正した残差（Mark 数 × 2 × 段階）、
% 推定対象の点（学習に使わなかった Mark）
marks = unit.marks;
n = numel(marks.x);
actual = [marks.measX, marks.measY];
actual(~marks.validX, 1) = NaN;
actual(~marks.validY, 2) = NaN;
[measured, estimated] = deal(nan(n, 2, numel(projectors)));
for s = 1:numel(projectors)
    if isempty(projectors{s})
        measured(:, :, s) = actual;   % 成分の無い段階は補正しない（残差 = 計測値）
        estimated(:, :, s) = actual;
        continue
    end
    correction = alignest.overlayCorrection(unit, out, projectors{s});
    measured(:, :, s) = correction.fields.residualActual;
    estimated(:, :, s) = correction.fields.residualEstimated;
end
values = struct("actual", actual, "measured", measured, "estimated", estimated, ...
    "target", ~alignest.trainingMarks(unit, plan));
end

function joined = joinValues(parts)
% Wafer ごとの点の値を縦につなぐ（すべての Wafer の行）
items = [parts{:}];
joined = struct("actual", vertcat(items.actual), "measured", vertcat(items.measured), ...
    "estimated", vertcat(items.estimated), "target", vertcat(items.target));
end

function rows = waferRows(methodLabel, planLabel, waferLabel, values, scopes, axisNames)
% 1つの手法・学習パターン・Wafer の、範囲 × 軸の行
parts = cell(numel(scopes) * numel(axisNames), 1);
k = 0;
for s = 1:numel(scopes)
    inScope = true(size(values.target));
    if s == 2
        inScope = values.target;
    end
    for a = 1:numel(axisNames)
        k = k + 1;
        parts{k} = comparisonRow(methodLabel, planLabel, waferLabel, scopes(s), axisNames(a), values, inScope, a);
    end
end
rows = vertcat(parts{:});
end

function row = comparisonRow(methodLabel, planLabel, waferLabel, scope, axisName, values, inScope, a)
% 1つの手法・学習パターン・Wafer・範囲・軸の比べた値（どちらの全成分の残差もある点）
measured = squeeze(values.measured(:, a, :));
estimated = squeeze(values.estimated(:, a, :));
if isvector(measured) && size(values.measured, 1) == 1
    measured = reshape(measured, 1, []);   % 点が1つのとき
    estimated = reshape(estimated, 1, []);
end
compared = inScope(:) & isfinite(measured(:, end)) & isfinite(estimated(:, end));
% 補正量の差 = 推定値で求めた補正量 − 実測値で求めた補正量 = 実測値で補正した残差 − 推定値で補正した残差
correctionDifference = measured(compared, end) - estimated(compared, end);
row = table(string(methodLabel), string(planLabel), string(waferLabel), string(scope), string(axisName), nnz(compared), ...
    meanPlus3Sigma(values.actual(compared, a)), meanPlus3Sigma(measured(compared, 1)), ...
    meanPlus3Sigma(measured(compared, 2)), meanPlus3Sigma(measured(compared, 3)), ...
    meanPlus3Sigma(estimated(compared, 1)), meanPlus3Sigma(estimated(compared, 2)), ...
    meanPlus3Sigma(estimated(compared, 3)), ...
    meanPlus3Sigma(estimated(compared, 3)) - meanPlus3Sigma(measured(compared, 3)), meanPlus3Sigma(correctionDifference), ...
    'VariableNames', ["method", "plan", "wafer", "scope", "axis", "n", "before", "measuredWaferStage", ...
    "measuredCommonStage", "measured", "estimatedWaferStage", "estimatedCommonStage", "estimated", "difference", ...
    "correctionDifference"]);
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

function value = meanPlus3Sigma(values)
% |平均| + 3σ（σ は不偏標準偏差）。点が2点未満なら NaN
values = values(isfinite(values));
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end
