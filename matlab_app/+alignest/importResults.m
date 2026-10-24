function results = importResults(filePath)
%IMPORTRESULTS 「結果を Excel に書き出す」（alignest.exportResults）で書き出したファイルを読み、評価の結果に戻す。
%   results = alignest.importResults(filePath)
%   「Waferごと」シートから結果の表を、「学習Shot」から学習パターンを、「説明」から作成日時などを、
%   「設定」から評価の設定を作り直す。表・グラフ・基準の手法との比較（alignest.summarizeResults など）に使える。
%   推定値そのものは Excel に無いので、Wafer マップ・推定値の分析は、計測ファイルを読み込んで評価し直すと使える。
%   results.imported に読んだファイルを入れる（画面で読み込んだ結果と見分けるため）。
arguments
    filePath (1, 1) string
end
TEXT_COLUMNS = ["Operation", "EqpId", "LotID", "Wafer", "DateTime", "plan", "group", "methodLabel", "methodId", ...
    "hyperparameters", "note"];
REQUIRED_COLUMNS = ["Wafer", "plan", "group", "methodLabel", "methodId"];
PLAN_FAILED_PREFIX = "学習パターンを作れませんでした";
if ~isfile(filePath)
    error('alignest:importResults', 'ファイルが見つかりません: %s', filePath);
end
try
    sheets = string(sheetnames(filePath));
catch err
    error('alignest:importResults', 'Excel ファイルとして読めません: %s（%s）', filePath, err.message);
end
if ~any(sheets == "Waferごと")
    error('alignest:importResults', ['「Waferごと」のシートがありません。このアプリの「結果を Excel に書き出す」で' ...
        '書き出したファイルを選んでください: %s'], filePath);
end

% 結果の表（Waferごと）：見出しを結果の表の列名に戻す。無い列（以前の版のファイルなど）は空・NaN にする
[allNames, allHeaders] = alignest.resultColumnNames(true);
LEGACY_HEADERS = ["超パラメータ", "ハイパーパラメータ"];   % 以前の版の見出し → 今の見出し（1行に1組）
[raw, fileHeaders] = alignest.readSheetTable(filePath, "Waferごと", ...
    [allHeaders(ismember(allNames, TEXT_COLUMNS)), LEGACY_HEADERS(:, 1).']);
for k = 1:size(LEGACY_HEADERS, 1)
    if any(fileHeaders == LEGACY_HEADERS(k, 1)) && ~any(fileHeaders == LEGACY_HEADERS(k, 2))
        raw = renamevars(raw, LEGACY_HEADERS(k, 1), LEGACY_HEADERS(k, 2));
        fileHeaders(fileHeaders == LEGACY_HEADERS(k, 1)) = LEGACY_HEADERS(k, 2);
    end
end
overlayNames = alignest.overlayMetricNames();
overlayEvaluated = any(ismember(allHeaders(ismember(allNames, overlayNames)), fileHeaders));
[names, headers] = alignest.resultColumnNames(overlayEvaluated);
missingRequired = REQUIRED_COLUMNS(~ismember(headers(ismember(names, REQUIRED_COLUMNS)), fileHeaders));
if ~isempty(missingRequired)
    error('alignest:importResults', ['「Waferごと」のシートに必要な列（%s）がありません。このアプリの' ...
        '「結果を Excel に書き出す」で書き出したファイルを選んでください。'], ...
        strjoin(headers(ismember(names, missingRequired)), "、"));
end
present = ismember(headers, fileHeaders);
isText = ismember(names, TEXT_COLUMNS);
nRows = height(raw);
table_ = table();
for k = 1:numel(names)
    if present(k)
        values = raw.(headers(k));
    elseif isText(k)
        values = strings(nRows, 1);
    else
        values = nan(nRows, 1);
    end
    table_.(names(k)) = values;
end
table_.converged = table_.converged == 1;

% 設定（JSON を1行ずつ書いたシート）。無ければ初期設定
settings = alignest.defaultSettings();
if any(sheets == "設定")
    lines = alignest.readSheetTable(filePath, "設定", strings(1, 0), "");   % すべて文字列
    if height(lines) > 0
        settings = alignest.loadSettings(strjoin(lines{:, 1}, newline), "text");
    end
end

% 手法：設定から作った手法の並びに同じ識別子があれば、その中身（推定のしかた）を使う
[methodIds, firstRow] = unique(table_.methodId, 'stable');
try
    known = alignest.buildMethodList(settings.methods);
catch
    known = struct("id", {}, "family", {}, "featureSet", {}, "variant", {}, "factorMode", {}, "label", {});
end
methods = repmat(struct("id", "", "family", "", "featureSet", "", "variant", "", "factorMode", "", "label", ""), ...
    1, numel(methodIds));   % alignest.buildMethodList と同じ横の並び
for m = 1:numel(methodIds)
    match = find(string({known.id}) == methodIds(m), 1);
    if ~isempty(match)
        methods(m) = known(match);
    else
        methods(m).id = methodIds(m);
        methods(m).family = extractBefore(methodIds(m) + "_", "_");
    end
    methods(m).label = table_.methodLabel(firstRow(m));
end
[~, table_.methodIndex] = ismember(table_.methodId, methodIds);
for name = ["family", "featureSet", "variant", "factorMode"]
    methodValues = string({methods.(name)});
    table_.(name) = reshape(methodValues(table_.methodIndex), [], 1);
end

% Wafer と学習パターン（Wafer × 学習パターンの組を、評価した順に並べる）
unitLabels = unique(table_.Wafer, 'stable');
[~, table_.unitIndex] = ismember(table_.Wafer, unitLabels);
pairKeys = table_.Wafer + newline + table_.plan;
[~, firstOfPair, table_.planIndex] = unique(pairKeys, 'stable');
plans = repmat(alignest.planTemplate(), numel(firstOfPair), 1);
for p = 1:numel(firstOfPair)
    row = firstOfPair(p);
    inPlan = table_.planIndex == p;
    plans(p).label = table_.plan(row);
    plans(p).group = table_.group(row);
    plans(p).unitIndex = table_.unitIndex(row);
    plans(p).unitLabel = table_.Wafer(row);
    plans(p).nShots = table_.nShots(row);
    plans(p).criterionI = table_.criterionI(row);
    plans(p).criterionD = table_.criterionD(row);
    plans(p).efficiencyI = table_.efficiencyI(row);
    plans(p).efficiencyD = table_.efficiencyD(row);
    plans(p).ok = ~any(startsWith(table_.note(inPlan), PLAN_FAILED_PREFIX));
end
if any(sheets == "学習Shot")
    plans = addPlanDetails(plans, filePath);
end
table_.planType = strings(nRows, 1);
table_.repeat = zeros(nRows, 1);

% 説明：作成日時・計算時間・途中で止めたか・処理時間の記録・Overlay 補正のモデル・計算の注意
descriptions = strings(0, 2);
if any(sheets == "説明")
    sheet = alignest.readSheetTable(filePath, "説明", strings(1, 0), "");
    if width(sheet) >= 2
        descriptions = [sheet{:, 1}, sheet{:, 2}];
    end
end
results = struct();
results.table = table_;
results.plans = plans;
results.methods = methods;
results.unitLabels = unitLabels;
results.groups = unique(table_.group, 'stable').';
results.settings = settings;
results.dataSummary = struct("messages", describedValues(descriptions, "データの確認"));
results.cancelled = describedValue(descriptions, "途中で止めたか") == "true";
results.resume = [];
results.nTotal = nRows;
results.elapsedSeconds = str2double(describedValue(descriptions, "計算時間 [秒]"));
results.log = describedValues(descriptions, "計算の注意");
results.timingRecorded = startsWith(describedValue(descriptions, "処理時間の記録"), "記録した");
results.overlayEvaluated = overlayEvaluated;
results.overlayDescription = "";
overlayText = describedValue(descriptions, "Overlay 補正の評価");
if overlayEvaluated && contains(overlayText, "補正モデル：") && contains(overlayText, "（X・Y 別に")
    results.overlayDescription = extractBetween(overlayText, "補正モデル：", "（X・Y 別に");
end
results.createdAt = describedValue(descriptions, "作成日時");
results.sourceFile = describedValue(descriptions, "読み込んだファイル");
results.imported = filePath;
end

function plans = addPlanDetails(plans, filePath)
% 「学習Shot」シートの Shot 番号・計算時間・メモなどを、Wafer と学習パターンの名前で合わせて入れる
TEXT_HEADERS = ["Wafer", "学習パターン", "学習ShotのshotNo", "メモ"];
[sheet, headers] = alignest.readSheetTable(filePath, "学習Shot", TEXT_HEADERS);
if ~all(ismember(["Wafer", "学習パターン"], headers))
    return
end
keys = sheet.("Wafer") + newline + sheet.("学習パターン");
for p = 1:numel(plans)
    row = find(keys == plans(p).unitLabel + newline + plans(p).label, 1);
    if isempty(row)
        continue
    end
    if ismember("学習ShotのshotNo", headers)
        shotNos = str2double(split(strtrim(sheet.("学習ShotのshotNo")(row))));
        plans(p).shotNos = shotNos(isfinite(shotNos));
    end
    if ismember("制約の違反量", headers)
        plans(p).violation = sheet.("制約の違反量")(row);
    end
    if ismember("学習パターンの計算時間[秒]", headers)
        plans(p).seconds = sheet.("学習パターンの計算時間[秒]")(row);
    end
    if ismember("同じ配置のWaferから使い回し", headers)
        plans(p).reused = sheet.("同じ配置のWaferから使い回し")(row) == 1;
    end
    if ismember("メモ", headers)
        plans(p).message = sheet.("メモ")(row);
    end
end
end

function value = describedValue(descriptions, item)
% 「説明」シートの項目の内容（無ければ ""）
value = "";
row = find(descriptions(:, 1) == item, 1);
if ~isempty(row)
    value = descriptions(row, 2);
end
end

function values = describedValues(descriptions, item)
values = descriptions(descriptions(:, 1) == item, 2);
end
