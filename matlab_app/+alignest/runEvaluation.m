function results = runEvaluation(data, settings, progressFcn, previous, mode)
%RUNEVALUATION 全 Wafer × 学習パターン × 手法 で推定し、指標を表にまとめる。
%   results = alignest.runEvaluation(data, settings, progressFcn)
%   results = alignest.runEvaluation(data, settings, progressFcn, previous)            % 一時中断した評価の続きから
%   results = alignest.runEvaluation(data, settings, progressFcn, previous, "extend")  % 評価済みの結果に条件を足す
%   progressFcn(完了数, 全体数, 説明) は false を返すと一時中断する（省略可）。中断した場合も、それまでの結果を返し、
%   results.cancelled = true、results.resume に続きに要るもの（学習パターンの記憶など）を入れる。
%   previous を渡すと、previous に済んだ組み合わせ（Wafer × 学習パターン × 手法）はそのまま使い、無いものだけを計算する。
%     "resume"（既定）：一時中断した評価の続き。設定は中断したときと同じこと（違えば止める）。
%     "extend"        ：評価済みの結果に、settings で増えた手法・学習パターンを足す。推定の結果を変える設定
%                       （データ・質的変数・制約・評価・Overlay 補正・手法の細かい設定）は評価したときと同じこと
%                       （alignest.extensionConflicts）。手法・学習パターンは評価済みのものと settings のものを合わせる
%                       （評価済みのものが先。学習パターンは Shot 数・計測率の順）。
%   計算時間は前と後を足す。results.pointEstimates は行ごとの評価点の推定値（alignest.filterResults で指標を計算し直す・
%   マップを描き直すときに使う）。results.runSettings は最後に実行したときの設定（続きから再開するときに比べる）。
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
if nargin < 5
    mode = "resume";
end
mode = string(mode);
timer = tic;
methods = alignest.activeMethods(settings);   % 1変数では RT モデルを除く
if isempty(methods)
    error('alignest:noMethod', '比べる手法が選ばれていません。「2. 評価の設定」で手法を1つ以上選んでください。');
end
specs = alignest.buildPlanSpecs(settings.sampling);
units = data.units;
columns = alignest.factorColumnsUsed(settings);
if isfield(data, "attributeNames")
    missingColumns = columns(~ismember(columns, data.attributeNames));
    if ~isempty(missingColumns)
        error('alignest:factorColumn', ['質的変数に選んだ列が、読み込んだデータにありません: %s。' ...
            '「2. 評価の設定」の質的変数を選び直すか、その列を含むファイルを読み込んでください。'], strjoin(missingColumns, "、"));
    end
end
previousSeconds = 0;
logLines = strings(0, 1);
additions = strings(0, 1);
mergedSettings = settings;
planCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
previousRow = containers.Map('KeyType', 'char', 'ValueType', 'double');   % 'Wafer番号|学習パターン|手法' → previous の行
previousPlan = containers.Map('KeyType', 'char', 'ValueType', 'double');  % 'Wafer番号|学習パターン' → previous の学習パターン
if ~isempty(previous)
    requestedIds = string({methods.id});
    requestedLabels = string({specs.label});
    [methods, specs] = checkPrevious(previous, settings, methods, specs, units, mode);
    for k = 1:height(previous.table)
        previousRow(rowKey(previous.table.unitIndex(k), previous.table.plan(k), previous.table.methodId(k))) = k;
    end
    for k = 1:numel(previous.plans)
        previousPlan(planKey(previous.plans(k).unitIndex, previous.plans(k).label)) = k;
    end
    if isfield(previous, "resume") && ~isempty(previous.resume)
        planCache = previous.resume.planCache;
    end
    logLines = previous.log;
    previousSeconds = previous.elapsedSeconds;
    if isfield(previous, "additions")
        additions = previous.additions;
    end
    if mode == "extend"
        mergedSettings = settings;
        mergedSettings.methods = unionSettings(previous.settings.methods, settings.methods);
        newMethods = setdiff(requestedIds, string({previous.methods.id}), 'stable');
        newPlans = setdiff(requestedLabels, string({specsOf(previous).label}), 'stable');
        additions(end + 1, 1) = sprintf("%s に追加：手法 %d（%s）・学習パターン %d（%s）", ...
            string(datetime('now', 'Format', 'yyyy/MM/dd HH:mm:ss')), numel(newMethods), listOrNone(newMethods), ...
            numel(newPlans), listOrNone(newPlans));
    elseif isfield(previous, "settings")
        mergedSettings = previous.settings;   % 続きから再開：前と同じ（追加した評価の続きなら、合わせた設定）
    end
end
nTotal = numel(units) * numel(specs) * numel(methods);
metricList = alignest.metricNames();
template = rowTemplate(metricList);
rows = repmat(template, nTotal, 1);
filled = false(nTotal, 1);
pointEstimates = cell(nTotal, 1);
plans = repmat(alignest.planTemplate(), 0, 1);
recordTiming = isfield(settings.evaluation, "recordTiming") && settings.evaluation.recordTiming;
overlay = alignest.overlayChoice(settings);
projectors = cell(numel(units), 1);  % Overlay 補正の射影は Wafer ごとに1回だけ作る（学習パターン・手法によらない）
warmedUp = false(numel(methods), 1);
if ~isempty(previous) && isfield(previous, "resume") && ~isempty(previous.resume)
    count = min(numel(previous.resume.warmedUp), numel(methods));
    warmedUp(1:count) = previous.resume.warmedUp(1:count);
end
done = previousRow.Count;  % 済んだ組み合わせの数（その分は計算しない）
cancelled = false;
slot = 0;
for u = 1:numel(units)
    unit = units(u);
    for p = 1:numel(specs)
        spec = specs(p);
        reusedPlan = isKey(previousPlan, planKey(u, spec.label));
        needed = ~all(arrayfun(@(method) isKey(previousRow, rowKey(u, spec.label, method.id)), methods));
        if ~reusedPlan && (cancelled || ~needed)
            slot = slot + numel(methods);   % 計算しない（中断の後・済んだ組み合わせだけ）
            continue
        end
        if reusedPlan
            plan = previous.plans(previousPlan(planKey(u, spec.label)));
        else
            plan = alignest.cachedTrainingPlan(unit, spec, settings, planCache);
            plan.unitIndex = u;
            plan.unitLabel = unit.label;
            if plan.message ~= ""
                logLines(end + 1) = unit.label + "｜" + plan.label + "：" + plan.message; %#ok<AGROW>
            end
        end
        plans(end + 1, 1) = plan; %#ok<AGROW>
        planIndex = numel(plans);
        for m = 1:numel(methods)
            slot = slot + 1;
            key = rowKey(u, spec.label, methods(m).id);
            if isKey(previousRow, key)
                row = table2struct(previous.table(previousRow(key), :));
                row.planIndex = planIndex;
                row.methodIndex = m;
                rows(slot) = row;
                filled(slot) = true;
                if isfield(previous, "pointEstimates")
                    pointEstimates{slot} = previous.pointEstimates{previousRow(key)};
                end
                continue
            end
            if cancelled
                continue
            end
            row = template;
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
                        warmUp(unit, plan, methods(m), settings);
                        warmedUp(m) = true;
                    end
                    out = alignest.estimateWafer(unit, plan, methods(m), settings);
                    row = fillMetrics(row, unit, out, settings);
                    pointEstimates{slot} = alignest.compactEstimate(out);
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
            rows(slot) = row;
            filled(slot) = true;
            done = done + 1;
            message = sprintf("%s｜%s｜%s", unit.label, plan.label, methods(m).label);
            if ~progressFcn(done, nTotal, message)
                cancelled = true;   % 残りは計算しないが、済んだ組み合わせ（previous）は最後まで入れる
            end
        end
    end
end
results.table = struct2table(rows(filled));
results.pointEstimates = pointEstimates(filled);
results.plans = plans;
results.methods = methods;
results.specs = specs;
results.unitLabels = string({units.label}).';
results.groups = unique(string({specs.group}), 'stable');
results.settings = mergedSettings;
results.runSettings = settings;
results.dataSummary = data.summary;
results.cancelled = cancelled;
results.resume = [];
if cancelled
    results.resume = struct("planCache", planCache, "warmedUp", warmedUp);
end
results.nTotal = nTotal;
results.elapsedSeconds = previousSeconds + toc(timer);
results.log = logLines;
results.additions = additions;
results.timingRecorded = recordTiming;
results.overlayEvaluated = overlay.enabled;
results.overlayDescription = overlay.description;
results.createdAt = string(datetime('now', 'Format', 'yyyy/MM/dd HH:mm:ss'));
end

function [methods, specs] = checkPrevious(previous, settings, methods, specs, units, mode)
% 続きから再開・条件の追加ができる結果か確かめ、手法・学習パターンを評価済みのものと合わせる
if ~isequal(string(previous.unitLabels(:)), string({units.label}).')
    error(char("alignest:" + mode), '評価したときと Wafer の並びが違います。同じデータを読み込んでから実行してください。');
end
if ~isfield(previous, "plans") || ~all(isfield(previous.plans, "shotIndex")) || isfield(previous, "imported")
    error(char("alignest:" + mode), ['Excel から読み込んだ結果には、続きの計算・条件の追加はできません。' ...
        '「評価を始める」で計算してください。']);
end
previousSpecs = specsOf(previous);
switch mode
    case "resume"
        if ~isfield(previous, "resume") || isempty(previous.resume) || ~previous.cancelled
            error('alignest:resume', '続きから再開できる評価がありません。「評価を始める」で最初から計算してください。');
        end
        if ~isequaln(runSettingsOf(previous), settings)
            error('alignest:resume', ['一時中断した後に評価の設定が変わったので、続きから再開できません。' ...
                '設定を戻すか、「評価を始める」で最初から計算してください。']);
        end
    case "extend"
        conflicts = alignest.extensionConflicts(runSettingsOf(previous), settings);
        if ~isempty(conflicts)
            error('alignest:extend', ['評価したときと次の設定が違うので、評価済みの結果に追加できません：%s。' ...
                '設定を戻すか、「評価を始める」で最初から計算してください。'], strjoin(conflicts, "、"));
        end
        previousGroups = string({previousSpecs.group});
        added = specs(~ismember(string({specs.label}), string({previousSpecs.label})));
        clash = added(ismember(string({added.group}), previousGroups) & string({added.type}) ~= "random");
        if ~isempty(clash)
            error('alignest:extend', ['学習パターン「%s」は評価済みの結果と同じ列（%s）で中身が違います。' ...
                '手動の指定を変えたときは、行を足して指定してください。'], clash(1).label, clash(1).group);
        end
    otherwise
        error('alignest:mode', '実行のしかたは resume または extend です: %s', mode);
end
previousIds = string({previous.methods.id});
methods = [reshape(previous.methods, 1, []), methods(~ismember(string({methods.id}), previousIds))];
newSpecs = specs(~ismember(string({specs.label}), string({previousSpecs.label})));
specs = sortSpecs([reshape(previousSpecs, 1, []), reshape(newSpecs, 1, [])]);
if mode == "extend" && numel(methods) == numel(previous.methods) && isempty(newSpecs)
    error('alignest:extend', ['評価済みの結果に無い手法・学習パターンがありません。「2. 評価の設定」で手法または' ...
        '学習 Shot 数（計測率）を増やしてから実行してください。']);
end
end

function specs = specsOf(results)
% 評価した学習パターンの並び（以前の版の結果には無いので、設定から作り直す）
if isfield(results, "specs")
    specs = results.specs;
else
    specs = alignest.buildPlanSpecs(runSettingsOf(results).sampling);
end
end

function settings = runSettingsOf(results)
if isfield(results, "runSettings")
    settings = results.runSettings;
else
    settings = results.settings;
end
end

function specs = sortSpecs(specs)
% 学習パターンを Shot 数 → 計測率 → 手動 の順、同じ種類は数の小さい順（ランダムは繰り返しの番号順）に並べる
kind = ones(numel(specs), 1);
value = reshape([specs.nShots], [], 1);
isRate = isfinite(reshape([specs.rate], [], 1));
kind(isRate) = 2;
value(isRate) = reshape([specs(isRate).rate], [], 1);
isManual = string({specs.type}).' == "manual";
kind(isManual) = 3;
value(isManual) = find(isManual);
[~, order] = sortrows([kind, value, reshape([specs.repeat], [], 1), (1:numel(specs)).']);
specs = specs(order);
end

function merged = unionSettings(old, new)
% 手法の設定を合わせる（選んだものの和。ほかの設定から作る手法の識別子を、Excel の読み込みで引けるようにするため）
merged = new;
for name = string(fieldnames(old)).'
    if ~isfield(new, name)
        merged.(name) = old.(name);
    elseif isstruct(old.(name)) && isstruct(new.(name))
        merged.(name) = unionSettings(old.(name), new.(name));
    elseif islogical(old.(name)) && islogical(new.(name)) && isscalar(old.(name)) && isscalar(new.(name))
        merged.(name) = old.(name) || new.(name);
    elseif (isstring(old.(name)) && isstring(new.(name))) || (isnumeric(old.(name)) && isnumeric(new.(name)) && ...
            ~isscalar(new.(name)))
        merged.(name) = unique([reshape(old.(name), 1, []), reshape(new.(name), 1, [])], 'stable');
    end
end
end

function key = rowKey(unitIndex, planLabel, methodId)
key = sprintf('%d|%s|%s', unitIndex, planLabel, methodId);
end

function key = planKey(unitIndex, planLabel)
key = sprintf('%d|%s', unitIndex, planLabel);
end

function text = listOrNone(values)
text = "なし";
if ~isempty(values)
    text = strjoin(values, "、");
end
end

function warmUp(unit, plan, method, settings)
% 処理時間を記録するとき、初回だけかかる時間（ファイルの読み込みなど）を除くための予備の推定
try
    alignest.estimateWafer(unit, plan, method, settings);
catch
    % 失敗は本番の推定で記録する
end
end

function row = fillMetrics(row, unit, out, settings)
marks = unit.marks;
outerMm = settings.evaluation.outerRadiusMm;
truthX = marks.measX(out.testIndex.X);
truthY = marks.measY(out.testIndex.Y);
outerX = marks.r(out.testIndex.X) >= outerMm;
outerY = marks.r(out.testIndex.Y) >= outerMm;
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
% 推定のハイパーパラメータを「名前=値」の並びにする（ls：長さスケール、sf：σf、tau：質的変数の項の τ、
% log10Lambda：TPS・RBF・RBFe の平滑化の強さ、rbfeRegions：RBFe で使った領域の数 など）
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

