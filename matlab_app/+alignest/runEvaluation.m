function results = runEvaluation(data, settings, progressFcn, previous)
%RUNEVALUATION 全 Wafer × 学習パターン × 手法 で推定し、指標を表にまとめる。
%   results = alignest.runEvaluation(data, settings, progressFcn)
%   results = alignest.runEvaluation(data, settings, progressFcn, previous)   % 一時中断した評価の続きから
%   progressFcn(完了数, 全体数, 説明) は false を返すと一時中断する（省略可）。中断した場合も、それまでの結果を返し、
%   results.cancelled = true、results.resume に続きに要るもの（学習パターンの記憶など）を入れる。
%   previous に一時中断した結果を渡すと、済んだ組み合わせ・学習パターンはそのまま使い、残りだけを計算する
%   （設定とデータは中断したときと同じこと。呼ぶ側で確かめる）。計算時間は中断の前と後を足す。
%   学習パターン（どの Shot を学習に使うか）は、候補 Shot と計測できた Mark が同じ Wafer どうしで共通にする
%   （同じ Shot で比べるため。乱数も同じ値から始める）。
%   1つの手法が失敗しても止めずに、その行の指標を NaN、note に理由を入れて続ける。
%   settings.evaluation.recordTiming が true なら、各手法を最初に使う前に1回だけ予備の推定をして（結果は捨てる）、
%   ファイルの読み込みなど初回だけの時間を処理時間に入れない。処理時間（seconds）は1枚の X・Y の推定にかかった秒数。
if nargin < 3 || isempty(progressFcn)
    progressFcn = @(varargin) true;
end
if nargin < 4
    previous = [];
end
timer = tic;
methods = alignest.buildMethodList(settings.methods);
if isempty(methods)
    error('alignest:noMethod', '比べる手法が選ばれていません。「2. 評価の設定」で手法を1つ以上選んでください。');
end
specs = alignest.buildPlanSpecs(settings.sampling);
units = data.units;
choice = alignest.factorChoice(settings);
if isfield(data, "attributeNames")
    missingColumns = choice.columns(~ismember(choice.columns, data.attributeNames));
    if ~isempty(missingColumns)
        error('alignest:factorColumn', ['質的変数に選んだ列が、読み込んだデータにありません: %s。' ...
            '「2. 評価の設定」の質的変数を選び直すか、その列を含むファイルを読み込んでください。'], strjoin(missingColumns, "、"));
    end
end
nTotal = numel(units) * numel(specs) * numel(methods);
metricList = alignest.metricNames();
rows = repmat(rowTemplate(metricList), nTotal, 1);
plans = repmat(planTemplate(), 0, 1);
planCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
logLines = strings(0, 1);
done = 0;
cancelled = false;
recordTiming = isfield(settings.evaluation, "recordTiming") && settings.evaluation.recordTiming;
overlay = alignest.overlayChoice(settings);
projectors = cell(numel(units), 1);  % Overlay 補正の射影は Wafer ごとに1回だけ作る（学習パターン・手法によらない）
warmedUp = false(numel(methods), 1);
nResumed = 0;            % 一時中断の前に済んだ組み合わせの数（その分は計算しない）
previousSeconds = 0;
if ~isempty(previous)
    if ~isfield(previous, "resume") || isempty(previous.resume) || height(previous.table) > nTotal || ...
            numel(previous.methods) ~= numel(methods)
        error('alignest:resume', '続きから再開できる評価がありません。「評価を始める」で最初から計算してください。');
    end
    nResumed = height(previous.table);
    rows(1:nResumed) = table2struct(previous.table);
    plans = previous.plans;
    planCache = previous.resume.planCache;
    warmedUp = previous.resume.warmedUp;
    logLines = previous.log;
    previousSeconds = previous.elapsedSeconds;
end
pairIndex = 0;
for u = 1:numel(units)
    unit = units(u);
    for p = 1:numel(specs)
        pairIndex = pairIndex + 1;
        if pairIndex <= numel(plans)
            % 一時中断の前に作った学習パターン
            plan = plans(pairIndex);
            planIndex = pairIndex;
        else
            plan = alignest.cachedTrainingPlan(unit, specs(p), settings, planCache);
            plan.unitIndex = u;
            plan.unitLabel = unit.label;
            plans(end + 1, 1) = plan; %#ok<AGROW>
            planIndex = numel(plans);
            if plan.message ~= ""
                logLines(end + 1) = unit.label + "｜" + plan.label + "：" + plan.message; %#ok<AGROW>
            end
        end
        for m = 1:numel(methods)
            done = done + 1;
            if done <= nResumed
                continue
            end
            row = rowTemplate(metricList);
            row.Operation = unit.operation;
            row.EqpId = unit.eqpId;
            row.LotID = unit.lotId;
            row.Wafer = unit.label;
            row.DateTime = unit.dateTime;
            row.unitIndex = u;
            row.planIndex = planIndex;
            row.plan = plan.label;
            row.group = plan.group;
            row.planType = plan.type;
            row.repeat = plan.repeat;
            row.nShots = plan.nShots;
            row.methodIndex = m;
            row.methodId = methods(m).id;
            row.methodLabel = methods(m).label;
            row.family = methods(m).family;
            row.featureSet = methods(m).featureSet;
            row.variant = methods(m).variant;
            row.factorMode = methods(m).factorMode;
            row.criterionI = plan.criterionI;
            row.criterionD = plan.criterionD;
            row.efficiencyI = plan.efficiencyI;
            row.efficiencyD = plan.efficiencyD;
            if plan.ok
                try
                    if recordTiming && ~warmedUp(m)
                        warmUp(unit, plan.shotIndex, methods(m), settings);
                        warmedUp(m) = true;
                    end
                    out = alignest.estimateWafer(unit, plan.shotIndex, methods(m), settings);
                    row = fillMetrics(row, unit, out, settings);
                    if overlay.enabled
                        if isempty(projectors{u})
                            projectors{u} = alignest.overlayProjector(unit, overlay, settings.data.waferRadiusMm);
                        end
                        row = copyFields(row, alignest.overlayCorrection(unit, out, projectors{u}).metrics);
                    end
                    if ~out.converged
                        logLines(end + 1) = unit.label + "｜" + plan.label + "｜" + methods(m).label + ...
                            "：最適化または Backfitting が反復上限内に収束しませんでした。最終反復の推定値を出力しています。"; %#ok<AGROW>
                    end
                catch err
                    row.note = string(err.message);
                    logLines(end + 1) = unit.label + "｜" + plan.label + "｜" + methods(m).label + "：" + err.message; %#ok<AGROW>
                end
            else
                row.note = "学習パターンを作れませんでした：" + plan.message;
            end
            rows(done) = row;
            message = sprintf("%s｜%s｜%s", unit.label, plan.label, methods(m).label);
            if ~progressFcn(done, nTotal, message)
                cancelled = true;
                break
            end
        end
        if cancelled
            break
        end
    end
    if cancelled
        break
    end
end
rows = rows(1:done);
results.table = struct2table(rows);
results.plans = plans;
results.methods = methods;
results.unitLabels = string({units.label}).';
results.groups = unique(string({specs.group}), 'stable');
results.settings = settings;
results.dataSummary = data.summary;
results.cancelled = cancelled;
results.resume = [];
if cancelled
    results.resume = struct("planCache", planCache, "warmedUp", warmedUp);
end
results.nTotal = nTotal;
results.elapsedSeconds = previousSeconds + toc(timer);
results.log = logLines;
results.timingRecorded = recordTiming;
results.overlayEvaluated = overlay.enabled;
results.overlayDescription = overlay.description;
results.createdAt = string(datetime('now', 'Format', 'yyyy/MM/dd HH:mm:ss'));
end

function warmUp(unit, shotIndex, method, settings)
% 処理時間を記録するとき、初回だけかかる時間（ファイルの読み込みなど）を除くための予備の推定
try
    alignest.estimateWafer(unit, shotIndex, method, settings);
catch
    % 失敗は本番の推定で記録する
end
end

function row = fillMetrics(row, unit, out, settings)
marks = unit.marks;
ratio = settings.evaluation.outerRadiusRatio;
radius = settings.data.waferRadiusMm;
truthX = marks.measX(out.testIndex.X);
truthY = marks.measY(out.testIndex.Y);
outerX = marks.r(out.testIndex.X) / radius >= ratio;
outerY = marks.r(out.testIndex.Y) / radius >= ratio;
metrics = alignest.computeMetrics(truthX, out.estimate.X, out.edf(1), truthY, out.estimate.Y, out.edf(2), outerX, outerY, ...
    marks.measX(out.trainIndex.X), marks.measY(out.trainIndex.Y));
for name = string(fieldnames(metrics)).'
    if isfield(row, name)
        row.(name) = metrics.(name);
    end
end
row.nTest_X = metrics.nTest_X;
row.nTest_Y = metrics.nTest_Y;
if isfield(settings.evaluation, "excludeOutliers") && settings.evaluation.excludeOutliers
    row.nOutliers = numel(out.outlierIndex);
end
row.edf_X = out.edf(1);
row.edf_Y = out.edf(2);
row.aux_X = out.aux(1);
row.aux_Y = out.aux(2);
row.converged = out.converged;
row.seconds = out.seconds;
row.hyperparameters = extraText(out.extra);
end

function row = copyFields(row, values)
for name = string(fieldnames(values)).'
    row.(name) = values.(name);
end
end

function text = extraText(extra)
% GPR の超パラメータを「名前=値」の並びにする（ls：長さスケール、sf：σf、tau：質的変数の項の τ）
names = string(fieldnames(extra));
parts = strings(size(names));
for k = 1:numel(names)
    parts(k) = sprintf("%s=%.4g", names(k), extra.(names(k)));
end
text = strjoin(parts, " ");
end

function row = rowTemplate(metricList)
row = struct("Operation", "", "EqpId", "", "LotID", "", "Wafer", "", "DateTime", "", "unitIndex", 0, "planIndex", 0, "plan", "", "group", "", ...
    "planType", "", "repeat", 0, "nShots", 0, "methodIndex", 0, "methodId", "", "methodLabel", "", ...
    "family", "", "featureSet", "", "variant", "", "factorMode", "", "criterionI", NaN, "criterionD", NaN, ...
    "efficiencyI", NaN, "efficiencyD", NaN);
for name = metricList
    row.(name) = NaN;
end
for name = alignest.overlayMetricNames()
    row.(name) = NaN;
end
row.nTest_X = 0;
row.nTest_Y = 0;
row.nOutliers = NaN;   % 学習データから除いた異常値の Mark 数（除かない設定では NaN）
row.edf_X = NaN;
row.edf_Y = NaN;
row.aux_X = NaN;
row.aux_Y = NaN;
row.converged = false;
row.seconds = NaN;
row.hyperparameters = "";
row.note = "";
end

function plan = planTemplate()
plan = struct("label", "", "group", "", "type", "", "repeat", 0, "shotIndex", zeros(0, 1), ...
    "shotNos", zeros(0, 1), "nShots", 0, "criterion", NaN, "violation", 0, "criterionI", NaN, "criterionD", NaN, ...
    "ok", false, "message", "", "requiredShotIndex", zeros(0, 1), "rate", NaN, "efficiencyI", NaN, "efficiencyD", NaN, ...
    "seconds", 0, "reused", false, ...
    "unitIndex", 0, "unitLabel", "");
end
