function results = runEvaluation(data, settings, progressFcn)
%RUNEVALUATION 全 Wafer × 学習パターン × 手法 で推定し、指標を表にまとめる。
%   results = alignest.runEvaluation(data, settings, progressFcn)
%   progressFcn(完了数, 全体数, 説明) は false を返すと途中で止める（省略可）。止めた場合も、それまでの結果を返す。
%   学習パターン（どの Shot を学習に使うか）は、候補 Shot と計測できた Mark が同じ Wafer どうしで共通にする
%   （同じ Shot で比べるため。乱数も同じ値から始める）。
%   1つの手法が失敗しても止めずに、その行の指標を NaN、note に理由を入れて続ける。
if nargin < 3 || isempty(progressFcn)
    progressFcn = @(varargin) true;
end
timer = tic;
methods = alignest.buildMethodList(settings.methods);
if isempty(methods)
    error('alignest:noMethod', '比べる手法が選ばれていません。「2. 評価の設定」で手法を1つ以上選んでください。');
end
specs = alignest.buildPlanSpecs(settings.sampling);
units = data.units;
nTotal = numel(units) * numel(specs) * numel(methods);
metricList = alignest.metricNames();
rows = repmat(rowTemplate(metricList), nTotal, 1);
plans = repmat(planTemplate(), 0, 1);
planCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
logLines = strings(0, 1);
done = 0;
cancelled = false;
for u = 1:numel(units)
    unit = units(u);
    for p = 1:numel(specs)
        plan = cachedPlan(unit, specs(p), settings, planCache);
        plan.unitIndex = u;
        plan.unitLabel = unit.label;
        plans(end + 1, 1) = plan; %#ok<AGROW>
        planIndex = numel(plans);
        if plan.message ~= ""
            logLines(end + 1) = unit.label + "｜" + plan.label + "：" + plan.message; %#ok<AGROW>
        end
        for m = 1:numel(methods)
            done = done + 1;
            row = rowTemplate(metricList);
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
            if plan.ok
                try
                    out = alignest.estimateWafer(unit, plan.shotIndex, methods(m), settings);
                    row = fillMetrics(row, unit, out, settings);
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
results.elapsedSeconds = toc(timer);
results.log = logLines;
results.createdAt = string(datetime('now', 'Format', 'yyyy/MM/dd HH:mm:ss'));
end

function plan = cachedPlan(unit, spec, settings, planCache)
% 候補 Shot と使える Mark が同じ Wafer では、同じ学習パターンを使う（手動はそのまま作る）
if spec.type == "manual"
    plan = alignest.planTrainingShots(unit, spec, settings.sampling, settings.data.waferRadiusMm);
    plan = addPlanFields(plan);
    return
end
marks = unit.marks;
usable = marks.validX | marks.validY;
signature = sprintf('%.3f,', [marks.x(usable); marks.y(usable); marks.direction(usable)]);
key = [char(spec.label), '|', signature];
if isKey(planCache, key)
    cached = planCache(key);
    plan = cached.plan;
    shotKey = round([unit.shots.Xmm, unit.shots.Ymm], 3);
    [~, plan.shotIndex] = ismember(cached.coordinates, shotKey, 'rows');
    plan.shotNos = unit.shots.shotNo(plan.shotIndex);
    return
end
plan = alignest.planTrainingShots(unit, spec, settings.sampling, settings.data.waferRadiusMm);
plan = addPlanFields(plan);
planCache(key) = struct("plan", plan, ...
    "coordinates", round([unit.shots.Xmm(plan.shotIndex), unit.shots.Ymm(plan.shotIndex)], 3));
end

function plan = addPlanFields(plan)
plan.unitIndex = 0;
plan.unitLabel = "";
end

function row = fillMetrics(row, unit, out, settings)
marks = unit.marks;
ratio = settings.evaluation.outerRadiusRatio;
radius = settings.data.waferRadiusMm;
truthX = marks.measX(out.testIndex.X);
truthY = marks.measY(out.testIndex.Y);
outerX = marks.r(out.testIndex.X) / radius >= ratio;
outerY = marks.r(out.testIndex.Y) / radius >= ratio;
metrics = alignest.computeMetrics(truthX, out.estimate.X, out.edf(1), truthY, out.estimate.Y, out.edf(2), outerX, outerY);
for name = string(fieldnames(metrics)).'
    if isfield(row, name)
        row.(name) = metrics.(name);
    end
end
row.nTest_X = metrics.nTest_X;
row.nTest_Y = metrics.nTest_Y;
row.edf_X = out.edf(1);
row.edf_Y = out.edf(2);
row.aux_X = out.aux(1);
row.aux_Y = out.aux(2);
row.converged = out.converged;
row.seconds = out.seconds;
row.hyperparameters = extraText(out.extra);
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
row = struct("Wafer", "", "DateTime", "", "unitIndex", 0, "planIndex", 0, "plan", "", "group", "", ...
    "planType", "", "repeat", 0, "nShots", 0, "methodIndex", 0, "methodId", "", "methodLabel", "", ...
    "family", "", "featureSet", "", "variant", "", "factorMode", "");
for name = metricList
    row.(name) = NaN;
end
row.nTest_X = 0;
row.nTest_Y = 0;
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
    "shotNos", zeros(0, 1), "nShots", 0, "criterion", NaN, "violation", 0, "ok", false, "message", "", ...
    "unitIndex", 0, "unitLabel", "");
end
