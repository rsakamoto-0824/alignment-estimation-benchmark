function [estimates, messages, cancelled, overlayPoints] = collectEstimates(data, results, selection, options)
%COLLECTESTIMATES 選んだ Wafer × 学習パターン × 手法 の推定値を、評価点ごとの表にまとめる。
%   [estimates, messages, cancelled] = alignest.collectEstimates(data, results, selection)
%   selection.methodIndex：手法（results.methods の何番目か）、selection.groups：学習パターンの列（results.groups の値）、
%   selection.unitIndex：Wafer（data.units の何番目か）。
%   評価点は学習しなかった Shot の有効な Mark（評価と同じ）。残差 = 計測値 − 推定値。その軸が無効な点は NaN。
%   options.cache       ：推定結果を使い回す containers.Map（キーは 'Wafer|学習パターン|手法' の番号。画面のマップと共通）
%   options.progressFcn ：progressFcn(完了数, 全体数) が false を返すと途中で止める（cancelled = true）
%   options.maxRows     ：表の行数の上限。超えそうなら計算する前に止める（Excel の行数の上限のため）
%   options.includeTraining：true なら学習 Shot の有効な Mark の行も入れる（推定値・残差は NaN。Excel では空欄）。
%     表の role 列は「評価」「学習」「学習（異常値として除外）」。分析・散布図などは評価の行だけを使う（既定 false）。
%   推定できなかった組み合わせは飛ばし、理由を messages に入れる。
%   質的変数に選んだファイルのその他の列（results.settings.factors.columns）は「質的変数:<列名>」の列として加える。
%   overlayPoints：Overlay 補正の評価をするとき（alignest.overlayChoice）、全 Mark（学習・評価 Shot）の
%   実測値で補正した残差・推定値で補正した残差・推定による変化（alignest.overlayCorrection）。しないときは空の表。
arguments
    data struct
    results struct
    selection struct
    options.cache = []
    options.progressFcn = []
    options.maxRows (1, 1) double = Inf
    options.includeTraining (1, 1) logical = false
end
plans = results.plans;
planIndex = find(ismember(string({plans.group}), string(selection.groups)) & ...
    ismember([plans.unitIndex], selection.unitIndex) & [plans.ok]);
methodIndex = selection.methodIndex(:).';
upperBound = 0;
for p = planIndex
    upperBound = upperBound + numel(methodIndex) * numel(data.units(plans(p).unitIndex).marks.x);
end
if upperBound > options.maxRows
    error('alignest:tooManyRows', ['推定値の表が最大 %d 行になり、上限 %d 行を超えます。' ...
        '手法・学習パターン・Wafer を絞ってください。'], upperBound, options.maxRows);
end
nTotal = numel(planIndex) * numel(methodIndex);
columns = alignest.factorColumnsUsed(results.settings);
parts = cell(nTotal, 1);
overlayParts = cell(nTotal, 1);
overlay = alignest.overlayChoice(results.settings);
projectors = containers.Map('KeyType', 'double', 'ValueType', 'any');
messages = strings(0, 1);
cancelled = false;
done = 0;
for p = planIndex
    plan = plans(p);
    unit = data.units(plan.unitIndex);
    for m = methodIndex
        done = done + 1;
        method = results.methods(m);
        try
            out = cachedEstimate(options.cache, unit, plan, p, m, method, results.settings);
            parts{done} = pointTable(unit, plan, method, out, columns, options.includeTraining);
            if overlay.enabled
                if ~isKey(projectors, plan.unitIndex)
                    projectors(plan.unitIndex) = alignest.overlayProjector(unit, overlay, ...
                        results.settings.data.waferRadiusMm);
                end
                correction = alignest.overlayCorrection(unit, out, projectors(plan.unitIndex));
                overlayParts{done} = overlayTable(unit, plan, method, out, correction);
            end
        catch err
            messages(end + 1) = unit.label + "｜" + plan.label + "｜" + method.label + "：" + err.message; %#ok<AGROW>
        end
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
overlayParts = overlayParts(~cellfun(@isempty, overlayParts));
if isempty(overlayParts)
    overlayPoints = table();
else
    overlayPoints = vertcat(overlayParts{:});
end
if isempty(parts)
    estimates = pointTable(emptyUnit(), struct("label", "", "group", ""), struct("label", "", "id", ""), [], columns, false);
else
    estimates = vertcat(parts{:});
end
end

function out = cachedEstimate(cache, unit, plan, planIndex, methodIndex, method, settings)
key = sprintf('%d|%d|%d', plan.unitIndex, planIndex, methodIndex);
useCache = isa(cache, 'containers.Map');  % 空の Map は isempty が true になるので型で判定する
if useCache && isKey(cache, key)
    out = cache(key);
    return
end
out = alignest.estimateWafer(unit, plan.shotIndex, method, settings);
if useCache
    cache(key) = out; %#ok<NASGU> containers.Map は参照で共有される
end
end

function points = pointTable(unit, plan, method, out, columns, includeTraining)
% 1つの Wafer × 学習パターン × 手法 の評価点の表（includeTraining なら学習 Shot の有効な Mark の行も、Mark の順に入れる）
marks = unit.marks;
role = strings(0, 1);
if isempty(out)
    index = zeros(0, 1);
    estimateX = zeros(0, 1);
    estimateY = zeros(0, 1);
else
    index = union(out.testIndex.X(:), out.testIndex.Y(:));
    if includeTraining
        index = find(marks.validX | marks.validY);
    end
    role = repmat("評価", numel(index), 1);
    inTrain = ismember(marks.shotIndex(index), plan.shotIndex);
    role(inTrain) = "学習";
    if isfield(out, "outlierIndex")
        role(inTrain & ismember(index, out.outlierIndex)) = "学習（異常値として除外）";
    end
    estimateX = nan(numel(marks.x), 1);
    estimateY = nan(numel(marks.x), 1);
    estimateX(out.testIndex.X) = out.estimate.X;
    estimateY(out.testIndex.Y) = out.estimate.Y;
    estimateX = estimateX(index);
    estimateY = estimateY(index);
end
n = numel(index);
measX = nan(n, 1);
measY = nan(n, 1);
if n > 0
    measX(marks.validX(index)) = marks.measX(index(marks.validX(index)));
    measY(marks.validY(index)) = marks.measY(index(marks.validY(index)));
end
direction = nan(n, 1);
if n > 0 && unit.hasDirection
    direction = marks.direction(index);
end
text = @(value) repmat(string(value), n, 1);
points = table(text(unit.operation), text(unit.eqpId), text(unit.lotId), text(unit.label), text(unit.dateTime), ...
    text(plan.label), text(plan.group), text(method.label), text(method.id), pick(marks, "shotNo", index), ...
    pick(marks, "markNo", index), ...
    direction, pick(marks, "shotRowParity", index), pick(marks, "x", index), pick(marks, "y", index), ...
    pick(marks, "r", index), role, measX, estimateX, measX - estimateX, measY, estimateY, measY - estimateY, ...
    'VariableNames', ["Operation", "EqpId", "LotID", "Wafer", "DateTime", "plan", "group", "methodLabel", "methodId", ...
    "shotNo", "markNo", "direction", "shotRowParity", "x", "y", "r", "role", "measX", "estimateX", "residualX", ...
    "measY", "estimateY", "residualY"]);
points.markIndex = index(:);  % unit.marks の何番目か（散布図の色分けで、その他の列の値を引くため。Excel には出さない）
for column = columns
    values = strings(n, 1);
    position = find(string(unit.attributeNames) == column, 1);
    if n > 0 && ~isempty(position)
        values = marks.attributes(index, position);
    end
    points.("質的変数:" + column) = values;
end
end

function points = overlayTable(unit, plan, method, out, correction)
% 1つの Wafer × 学習パターン × 手法 の、有効な全 Mark の補正残差（学習 Shot の Mark も含む）
marks = unit.marks;
index = find(marks.validX | marks.validY);
n = numel(index);
role = repmat("学習", n, 1);
role(~ismember(marks.shotIndex(index), plan.shotIndex)) = "評価";
fields = correction.fields;
text = @(value) repmat(string(value), n, 1);
points = table(text(unit.operation), text(unit.eqpId), text(unit.lotId), text(unit.label), text(unit.dateTime), ...
    text(plan.label), text(plan.group), text(method.label), text(method.id), marks.shotNo(index), marks.markNo(index), ...
    marks.x(index), marks.y(index), role, fields.residualActual(index, 1), fields.residualActual(index, 2), ...
    fields.residualEstimated(index, 1), fields.residualEstimated(index, 2), fields.change(index, 1), ...
    fields.change(index, 2), 'VariableNames', ["Operation", "EqpId", "LotID", "Wafer", "DateTime", "plan", "group", ...
    "methodLabel", "methodId", "shotNo", "markNo", "x", "y", "role", "residualActualX", "residualActualY", ...
    "residualEstimatedX", "residualEstimatedY", "changeX", "changeY"]);
end

function values = pick(marks, name, index)
if isfield(marks, name)
    values = marks.(name)(index);
else
    values = zeros(0, 1);
end
values = values(:);
end

function unit = emptyUnit()
unit = struct("operation", "", "eqpId", "", "lotId", "", "attributeNames", strings(1, 0), "label", "", "dateTime", "", ...
    "hasDirection", false, ...
    "marks", struct("x", zeros(0, 1)));
end
