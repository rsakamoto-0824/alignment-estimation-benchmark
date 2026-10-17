function exportResults(results, filePath, sourceFile)
%EXPORTRESULTS 評価結果を Excel ファイル（.xlsx）に書き出す。Excel 本体は不要。
%   シート：説明／集計（XY の RMSE・MAE・R²・調整済み R²、X・Y の RMSE）／Waferごと／学習Shot／設定
%   同じ名前のファイルがあれば置き換える（Excel で開いているときは書き出せない）。
arguments
    results struct
    filePath (1, 1) string
    sourceFile (1, 1) string = ""
end
SUMMARY_METRICS = ["RMSE_XY", "MAE_XY", "R2_XY", "adjR2_XY", "RMSE_X", "RMSE_Y"];
[~, ~, extension] = fileparts(filePath);
if ~strcmpi(extension, ".xlsx")
    error('alignest:exportType', '書き出し先は .xlsx にしてください: %s', filePath);
end
if isfile(filePath)
    try
        delete(filePath);
    catch err
        error('alignest:exportLocked', '「%s」を置き換えられません（Excel で開いていないか確かめてください）。理由: %s', ...
            filePath, err.message);
    end
end
[metricNames, metricLabels] = alignest.metricNames();

% 説明
summary = results.dataSummary;
items = ["作成日時"; "読み込んだファイル"; "Wafer（評価の単位）の数"; "学習 Shot の選び方"; "学習パターン"; ...
    "比べた手法の数"; "計算時間 [秒]"; "途中で止めたか"; "評価の考え方"; "差の割合"];
values = [results.createdAt; sourceFile; string(numel(results.unitLabels)); samplingLabel(results.settings.sampling); ...
    strjoin(results.groups, "、"); string(numel(results.methods)); sprintf("%.1f", results.elapsedSeconds); ...
    string(results.cancelled); ...
    "学習 Shot の計測値で推定し、学習しなかった Shot の計測値（有効な点）と比べる。計測ノイズを含むので値は少し悪く出る。"; ...
    "集計シートの値は Wafer ごとの値（ランダムの繰り返しは平均）の平均。"];
values = [values; summary.messages(:); results.log(:)];
items = [items; repmat("データの確認", numel(summary.messages), 1); repmat("計算の注意", numel(results.log), 1)];
writetable(table(items, values, 'VariableNames', ["項目", "内容"]), filePath, 'Sheet', '説明');

% 集計（手法 × 学習パターン）
for metric = SUMMARY_METRICS
    aggregated = alignest.summarizeResults(results, metric, "mean");
    sheet = table(aggregated.methodLabels, 'VariableNames', "手法");
    for g = 1:numel(aggregated.groups)
        sheet.(aggregated.groups(g)) = aggregated.values(:, g);
    end
    sheet.("手法の識別子") = aggregated.methodIds;
    writetable(sheet, filePath, 'Sheet', char("集計_" + metric));
end

% Wafer ごと
perWafer = results.table;
keep = ["Wafer", "DateTime", "plan", "group", "nShots", "methodLabel", "methodId", metricNames, ...
    "nTest_X", "nTest_Y", "edf_X", "edf_Y", "aux_X", "aux_Y", "converged", "seconds", "hyperparameters", "note"];
perWafer = perWafer(:, keep);
headers = ["Wafer", "DateTime", "学習パターン", "列", "学習Shot数", "手法", "手法の識別子", metricLabels, ...
    "評価点数X", "評価点数Y", "有効自由度X", "有効自由度Y", "補助値X", "補助値Y", "最適化の収束", "計算時間[秒]", ...
    "超パラメータ", "メモ"];
perWafer.Properties.VariableNames = cellstr(headers);
writetable(perWafer, filePath, 'Sheet', 'Waferごと');

% 学習 Shot
plans = results.plans;
shotList = strings(numel(plans), 1);
for k = 1:numel(plans)
    shotList(k) = strjoin(string(plans(k).shotNos(:).'), " ");
end
planTable = table(string({plans.unitLabel}).', string({plans.label}).', [plans.nShots].', shotList, ...
    [plans.criterion].', [plans.violation].', string({plans.message}).', ...
    'VariableNames', ["Wafer", "学習パターン", "学習Shot数", "学習ShotのshotNo", "I基準tr(M⁻¹)", "制約の違反量", "メモ"]);
writetable(planTable, filePath, 'Sheet', '学習Shot');

% 設定（JSON を1行ずつ）
settingsLines = splitlines(string(jsonencode(results.settings, 'PrettyPrint', true)));
writetable(table(settingsLines, 'VariableNames', "設定（JSON）"), filePath, 'Sheet', '設定');
end

function label = samplingLabel(sampling)
switch string(sampling.method)
    case "ioptimal"
        label = "制約付き I 最適";
    case "random"
        label = sprintf("制約つきランダム（%d 回）", sampling.randomRepeats);
    otherwise
        label = "手動で指定";
end
end
