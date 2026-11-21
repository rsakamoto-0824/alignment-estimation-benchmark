function result = feedbackSimulation(wafers, maps, settings, options)
%FEEDBACKSIMULATION 計測マップをローテーションして FB の補正値を求め、ほかの Wafer に当てた補正残差を求める
%   （「8. 計測マップのローテーション」の「FB の検証」）。
%   result = alignest.feedbackSimulation(wafers, maps, settings)
%   result = alignest.feedbackSimulation(wafers, maps, settings, order="dateTime", splitKind="count", splitValue=3, ...
%       rotationLots=1, model="overlay", transferMethod="values", fullMeasurement=false)
%   wafers：Wafer ごとの label・points（alignest.rotationPoints の列を持つ点の表）・lot（LotID）・dateTime（日時の文字）。
%   maps：alignest.rotationMaps の結果（fullMeasurement が true なら使わない）。settings：アプリの設定（Overlay 補正の
%   モデル settings.overlay、Shot 高次補正の設定 settings.highOrder、Wafer 半径 settings.data.waferRadiusMm）。
%   1. 並べる：options.order が "dateTime"（日時の古い順。読めない日時は後ろに、読み込みの順）・"lot"（LotID の順）・
%      "input"（読み込みの順）。
%   2. 分ける：前から options.splitValue 枚（splitKind = "count"）、または全体の options.splitValue の割合（"ratio"。四捨
%      五入）を FB 側、残りを検証側にする（どちらも1枚以上）。
%   3. ローテーション：FB 側の Wafer に、並べた順に計測マップを当てる。LotID が2つ以上あれば Lot ごと（同じ Lot の Wafer は
%      同じマップ）、無ければ Wafer ごとに数え、options.rotationLots 個ごとに次のマップにする（M 枚の後は1枚目に戻る）。
%      FB 側の Wafer は、そのマップで計測する Shot・Mark の値だけを使う（fullMeasurement なら全点）。
%   4. FB の補正値（options.model）：
%      - "overlay"：「2. 評価の設定と実行」の Overlay 補正のモデル（Wafer 成分 + Shot 共通成分 + Shot ごとの成分）。FB 側で計測した
%        値を Shot・Mark（points.key）ごとに平均し（計測した Wafer だけで）、その値に最小二乗で当てはめた補正量を、検証側の
%        同じ Shot・Mark に当てる（FB の値をそのまま当てる。FB 側で一度も計測していない Shot・Mark は補正しない）
%      - "highOrder"：「6. Shot高次補正」の設定（alignest.shotHighOrder）で求めた補正値を、alignest.transferHighOrder で検証側に
%        当てる（options.transferMethod："values"（点ごとに平均して求め直す）・"coefficients"（補正値を平均する））
%   5. 評価：検証側の Wafer・軸ごとに、補正前の値と補正残差（値 − 補正量）の |平均| + 3σ（同じ点で）。
%   result.summary：wafer（と "すべての検証 Wafer"）・axis・n（値のある点）・nCorrected（補正できた点）・before・residual・
%   improvement（before − residual）[値の単位]。result.assignment：order・wafer・lot・dateTime・role（"FB"・"検証"）・map
%   （当てた計測マップ。検証側は NaN）・measured（FB 側で使った点の数）・available（値のある点の数）。
%   result.measurementRate：FB 側で使った点の割合（measured の和 / available の和）。result.points：検証側の点（wafer の列と
%   correctionX・Y・residualX・Y を足す）。result.description・messages・options
arguments
    wafers struct
    maps
    settings struct
    options.order (1, 1) string {mustBeMember(options.order, ["dateTime", "lot", "input"])} = "dateTime"
    options.splitKind (1, 1) string {mustBeMember(options.splitKind, ["count", "ratio"])} = "ratio"
    options.splitValue (1, 1) double = 0.5
    options.rotationLots (1, 1) double = 1
    options.model (1, 1) string {mustBeMember(options.model, ["overlay", "highOrder"])} = "overlay"
    options.transferMethod (1, 1) string {mustBeMember(options.transferMethod, ["values", "coefficients"])} = "values"
    options.fullMeasurement (1, 1) logical = false
end
ALL_LABEL = "すべての検証 Wafer";
AXIS_NAMES = ["X", "Y"];
nWafers = numel(wafers);
if nWafers < 2
    error('alignest:feedbackSimulation', 'FB 側と検証側に分けるには、Wafer が2枚以上要ります。');
end
if ~(isfinite(options.rotationLots) && options.rotationLots >= 1 && options.rotationLots == round(options.rotationLots))
    error('alignest:feedbackSimulation', 'ローテーションの間隔は 1 以上の整数（何 Lot ごとに次のマップにするか）にしてください。');
end
if ~options.fullMeasurement && (isempty(maps) || ~isstruct(maps))
    error('alignest:feedbackSimulation', '先に計測マップを作ってください。');
end
% 1・2. 並べて分ける
order = waferOrder(wafers, options.order);
nFb = splitCount(nWafers, options.splitKind, options.splitValue);
fbIndex = order(1:nFb);
verifyIndex = order(nFb + 1:end);
% 3. ローテーション
lots = string({wafers.lot});
lots(ismissing(lots)) = "";
byLot = numel(unique(lots(fbIndex))) >= 2 && all(lots(fbIndex) ~= "");
if byLot
    [~, ~, ordinal] = unique(lots(fbIndex), 'stable');   % FB 側の並びで初めて出た順の Lot の番号
else
    ordinal = (1:nFb).';
end
mapOfFb = nan(nFb, 1);
[measured, available] = deal(zeros(nWafers, 1));
fbWafers = wafers(fbIndex);
for j = 1:nFb
    points = fbWafers(j).points;
    hasValue = isfinite(points.valueX) | isfinite(points.valueY);
    available(fbIndex(j)) = nnz(hasValue);
    if ~options.fullMeasurement
        mapOfFb(j) = mod(floor((ordinal(j) - 1) / options.rotationLots), maps.nMaps) + 1;
        inMap = ismember(pointKeys(points, maps.level), maps.table.key(maps.membership(:, mapOfFb(j))));
        points.valueX(~inMap) = NaN;
        points.valueY(~inMap) = NaN;
        points.target(~inMap) = NaN;
        fbWafers(j).points = points;
    end
    measured(fbIndex(j)) = nnz(isfinite(points.valueX) | isfinite(points.valueY));
end
for k = reshape(verifyIndex, 1, [])
    points = wafers(k).points;
    available(k) = nnz(isfinite(points.valueX) | isfinite(points.valueY));
end
verifyWafers = wafers(verifyIndex);
% 4. FB の補正値を求めて検証側に当てる
messages = strings(0, 1);
switch options.model
    case "overlay"
        [corrected, modelText, notes] = applyOverlay(fbWafers, verifyWafers, settings);
    otherwise
        [corrected, modelText, notes] = applyHighOrder(fbWafers, verifyWafers, settings, options.transferMethod);
end
messages = [messages; notes(:)];
% 5. 評価
summaryParts = cell(numel(verifyIndex) + 1, 1);
for j = 1:numel(verifyIndex)
    summaryParts{j} = summaryRows(string(wafers(verifyIndex(j)).label), corrected{j}, AXIS_NAMES);
end
pointsAll = vertcat(corrected{:});
summaryParts{end} = summaryRows(ALL_LABEL, pointsAll, AXIS_NAMES);
summary = vertcat(summaryParts{:});
roles = repmat("検証", nWafers, 1);
roles(fbIndex) = "FB";
mapColumn = nan(nWafers, 1);
mapColumn(fbIndex) = mapOfFb;
[~, position] = ismember((1:nWafers).', order);
assignment = table(position, string({wafers.label}).', lots.', string({wafers.dateTime}).', roles, mapColumn, measured, ...
    available, 'VariableNames', ["order", "wafer", "lot", "dateTime", "role", "map", "measured", "available"]);
assignment = sortrows(assignment, "order");
rate = sum(measured(fbIndex)) / max(sum(available(fbIndex)), 1);
orderNames = struct("dateTime", "日時の古い順", "lot", "LotID の順", "input", "読み込みの順");
splitText = sprintf("FB 側 %d 枚・検証側 %d 枚（%s）", nFb, numel(verifyIndex), orderNames.(options.order));
if options.fullMeasurement
    mapText = "全点を計測";
else
    unitText = ternaryText(byLot, "Lot", "Wafer");
    mapText = sprintf("計測マップ %d 枚を %d %s ごとにローテーション（計測率 %.1f%%）", maps.nMaps, ...
        options.rotationLots, unitText, 100 * rate);
end
result = struct("summary", summary, "assignment", assignment, "measurementRate", rate, "points", pointsAll, ...
    "description", splitText + "、" + mapText + "、" + modelText, "messages", messages, "options", options, ...
    "byLot", byLot);
end

function order = waferOrder(wafers, kind)
% Wafer の並び（FB 側を前から取る）
n = numel(wafers);
inputOrder = (1:n).';
switch kind
    case "dateTime"
        text = string({wafers.dateTime}).';
        times = parseTimes(text);
        seconds_ = posixtime(times);
        seconds_(isnat(times)) = Inf;   % 読めない日時は後ろに
        [~, order] = sortrows([seconds_, inputOrder]);
    case "lot"
        lots = string({wafers.lot}).';
        [~, ~, lotRank] = unique(lots);
        [~, order] = sortrows([lotRank, inputOrder]);
    otherwise
        order = inputOrder;
end
end

function times = parseTimes(text)
% 日時の文字を読む（よく使う形を順に試す。読めなければ NaT）
FORMATS = ["yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy/MM/dd", ...
    "yyyy-MM-dd"];
times = NaT(numel(text), 1);
for format = FORMATS
    missing_ = isnat(times) & strlength(text) > 0;
    if ~any(missing_)
        break
    end
    try
        parsed = datetime(text(missing_), 'InputFormat', format);
        times(missing_) = parsed;
    catch
        % この形では読めない（次の形を試す）
    end
end
end

function n = splitCount(total, kind, value)
% FB 側の枚数（1枚以上、全体 − 1 枚以下）
if kind == "count"
    if ~(isfinite(value) && value == round(value) && value >= 1)
        error('alignest:feedbackSimulation', 'FB 側の枚数は 1 以上の整数にしてください。');
    end
    n = value;
else
    if ~(isfinite(value) && value > 0 && value < 1)
        error('alignest:feedbackSimulation', 'FB 側の割合は 0 より大きく 1 より小さい数にしてください（例：0.5）。');
    end
    n = round(total * value);
end
if n < 1 || n > total - 1
    error('alignest:feedbackSimulation', ['FB 側が %d 枚になります。FB 側・検証側ともに1枚以上になるように、枚数・割合を' ...
        '選んでください（全体 %d 枚）。'], n, total);
end
end

function keys = pointKeys(points, level)
% 計測マップの行と対応させる名前（Mark ごとは Shot と Shot 内の位置、Shot ごとは shotNo）
if level == "shot"
    keys = string(points.shotNo);
else
    keys = points.key;
end
end

function [corrected, modelText, notes] = applyOverlay(fbWafers, verifyWafers, settings)
% 「2. 評価の設定と実行」の Overlay 補正のモデル：FB 側の値を点ごとに平均し、当てはめた補正量を検証側の同じ点に当てる
choice = alignest.overlayChoice(settings);
if ~choice.enabled
    error('alignest:feedbackSimulation', ['「2. 評価の設定と実行」の Overlay 補正のモデルがすべて「なし」です。Wafer 成分・' ...
        'Shot 共通成分・Shot ごとの成分のどれかを選んでください。']);
end
waferRadiusMm = settings.data.waferRadiusMm;
pooled = vertcat(fbWafers.points);
[keys, first, group] = unique(pooled.key, 'stable');
nKeys = numel(keys);
averages = [accumarray(group, pooled.valueX, [nKeys, 1], @meanOmit), accumarray(group, pooled.valueY, [nKeys, 1], @meanOmit)];
geometry = pooled(first, :);
[~, ~, shotIndex] = unique(geometry.shotNo);
marks = struct("Xmm", geometry.Xc, "Ymm", geometry.Yc, "markXmm", geometry.localX, "markYmm", geometry.localY, ...
    "shotIndex", shotIndex);
correction = nan(nKeys, 2);
for a = 1:2
    index = find(isfinite(averages(:, a)));
    if isempty(index)
        continue
    end
    design = alignest.overlayDesign(marks, choice, waferRadiusMm, a, index);
    [q, r, ~] = qr(design, 0);
    diagonal = abs(diag(r));
    rankValue = nnz(diagonal > max(size(design)) * eps(max(diagonal)));
    basis = q(:, 1:rankValue);
    correction(index, a) = basis * (basis.' * averages(index, a));   % 最小二乗の当てはめ（射影）
end
corrected = cell(numel(verifyWafers), 1);
nMissing = 0;
for j = 1:numel(verifyWafers)
    points = verifyWafers(j).points;
    [found, position] = ismember(points.key, keys);
    values = nan(height(points), 2);
    values(found, :) = correction(position(found), :);
    missing = (isfinite(points.valueX) & ~isfinite(values(:, 1))) | (isfinite(points.valueY) & ~isfinite(values(:, 2)));
    nMissing = nMissing + nnz(missing);   % 値はあるのに、FB 側で一度も計測していないので補正できない点
    corrected{j} = withResiduals(points, string(verifyWafers(j).label), values);
end
modelText = "補正：2. の Overlay 補正（" + string(choice.description) + "。FB 側の値を点ごとに平均して当てはめ）";
notes = strings(0, 1);
if nMissing > 0
    notes(end + 1) = sprintf(['FB 側で一度も計測していない Shot・Mark の点 %d 点（検証側）は補正していません' ...
        '（FB 側の Wafer を増やすか、計測マップの数以上の Lot を FB 側にすると、すべての点を計測します）。'], nMissing);
end
end

function [corrected, modelText, notes] = applyHighOrder(fbWafers, verifyWafers, settings, method)
% 「6. Shot高次補正」の設定：FB 側の Wafer で補正値を求め、検証側に当てる（alignest.transferHighOrder）
spec = alignest.valueSpec(settings.data);
if spec.scalar
    error('alignest:feedbackSimulation', ['6. の Shot 高次補正は X・Y の2成分（dx・dy）が要ります。1変数の推定のデータでは' ...
        '「2. の Overlay 補正」を選んでください。']);
end
everything = [fbWafers(:); verifyWafers(:)];
input = struct("label", cellstr(string({everything.label})), "points", {everything.points});
result = alignest.shotHighOrder(input, settings, stages=false);
fbLabels = string({fbWafers.label});
verifyLabels = string({verifyWafers.label});
transfer = alignest.transferHighOrder(result, fbLabels, verifyLabels, settings.data.waferRadiusMm, method=method);
corrected = cell(numel(verifyWafers), 1);
for j = 1:numel(verifyWafers)
    points = verifyWafers(j).points;
    mine = transfer.points(transfer.points.wafer == verifyLabels(j), :);
    % transfer.points は result.points と同じ並び（点の表の並び）なので、Shot・Shot 内の位置で対応させる
    mineKeys = alignest.rotationPoints(mine).key;
    [found, position] = ismember(points.key, mineKeys);
    values = nan(height(points), 2);
    values(found, :) = [mine.transferCorrectionX(position(found)), mine.transferCorrectionY(position(found))];
    corrected{j} = withResiduals(points, verifyLabels(j), values);
end
methodNames = struct("values", "点ごとに平均して求め直す", "coefficients", "補正値を平均する");
modelText = "補正：6. の Shot 高次補正（" + result.description + "。FB 側が複数枚のときは" + methodNames.(method) + "）";
notes = reshape(transfer.messages, [], 1);
end

function points = withResiduals(points, label, correction)
% 検証側の点に、Wafer の名前・補正量・補正残差の列を足す
points.wafer = repmat(label, height(points), 1);
points.correctionX = correction(:, 1);
points.correctionY = correction(:, 2);
points.residualX = points.valueX - correction(:, 1);
points.residualY = points.valueY - correction(:, 2);
end

function rows = summaryRows(label, points, axisNames)
% 1つの Wafer（または検証側すべて）の軸ごとの行：補正できた点で、補正前の値と補正残差の |平均| + 3σ
parts = cell(numel(axisNames), 1);
for a = 1:numel(axisNames)
    values = points.("value" + axisNames(a));
    residual = points.("residual" + axisNames(a));
    compared = isfinite(values) & isfinite(residual);
    before = meanPlus3Sigma(values(compared));
    after = meanPlus3Sigma(residual(compared));
    parts{a} = table(label, axisNames(a), nnz(isfinite(values)), nnz(compared), before, after, before - after, ...
        'VariableNames', ["wafer", "axis", "n", "nCorrected", "before", "residual", "improvement"]);
end
rows = vertcat(parts{:});
end

function value = meanPlus3Sigma(values)
% |平均| + 3σ（σ は不偏標準偏差）。点が2点未満なら NaN（alignest.transferHighOrder と同じ）
values = values(isfinite(values));
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end

function value = meanOmit(values)
values = values(isfinite(values));
value = NaN;
if ~isempty(values)
    value = mean(values);
end
end

function text = ternaryText(condition, whenTrue, whenFalse)
if condition
    text = whenTrue;
else
    text = whenFalse;
end
end
