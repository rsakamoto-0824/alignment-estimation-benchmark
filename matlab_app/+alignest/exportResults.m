function exportResults(results, filePath, sourceFile)
%EXPORTRESULTS 評価結果を Excel ファイル（.xlsx）に書き出す。Excel 本体は不要。
%   シート：説明／集計_<指標>（XY の RMSE・MAE・R²、X・Y の RMSE、平均値・中央値に対する改善率。Wafer の平均）／
%   集計_統計量（同じ指標の 平均・中央値・ワースト値・95%値 を縦に並べた表）／Waferごと／学習Shot／
%   処理時間（処理時間を記録したときだけ。手法 × 学習パターンの列ごとの 1 枚あたりの秒数）／設定
%   同じ名前のファイルがあれば置き換える（Excel で開いているときは書き出せない）。
arguments
    results struct
    filePath (1, 1) string
    sourceFile (1, 1) string = ""
end
SUMMARY_METRICS = ["RMSE_XY", "MAE_XY", "R2_XY", "RMSE_X", "RMSE_Y", "improveMeanPct_XY", ...
    "improveMedianPct_XY"];
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
[overlayNames, overlayLabels] = alignest.overlayMetricNames();
if isfield(results, "overlayEvaluated") && results.overlayEvaluated
    SUMMARY_METRICS = [SUMMARY_METRICS, "overlayEstimated_X", "overlayEstimated_Y", "overlayIncrease_X", "overlayIncrease_Y"];
    metricNames = [metricNames, overlayNames];
    metricLabels = [metricLabels, overlayLabels];
end

% 説明
summary = results.dataSummary;
timingRecorded = isfield(results, "timingRecorded") && results.timingRecorded;
overlayEvaluated = isfield(results, "overlayEvaluated") && results.overlayEvaluated;
choice = alignest.factorChoice(results.settings, "X");
choiceY = alignest.factorChoice(results.settings, "Y");
items = ["作成日時"; "読み込んだファイル"; "工程（Operation）"; "装置（EqpId）"; "ロット（LotID）"; ...
    "Scan 方向（Direction）"; "質的変数"; ...
    "Wafer（評価の単位）の数"; "学習 Shot の選び方"; "学習パターン"; ...
    "比べた手法の数"; "計算時間 [秒]"; "途中で止めたか"; "処理時間の記録"; "評価の考え方"; "差の割合"; ...
    "ワースト値・95%値"; "I 基準・D 基準"; "Overlay 補正の評価"; "学習データの異常値"];
values = [results.createdAt; sourceFile; listText(summaryField(summary, "operations")); ...
    listText(summaryField(summary, "eqpIds")); listText(summaryField(summary, "lotIds")); directionText(summary); ...
    factorText(choice, choiceY); string(numel(results.unitLabels)); ...
    samplingLabel(results.settings.sampling); strjoin(results.groups, "、"); string(numel(results.methods)); ...
    sprintf("%.1f", results.elapsedSeconds); string(results.cancelled); ...
    ternary(timingRecorded, "記録した（「処理時間」シート。各手法の初回は予備の推定をして、読み込みの時間を除いた）", ...
    "記録しない（「Waferごと」の計算時間は参考値）"); ...
    "学習 Shot の計測値で推定し、学習しなかった Shot の計測値（有効な点）と比べる。計測ノイズを含むので値は少し悪く出る。"; ...
    "集計_<指標> シートの値は Wafer ごとの値（ランダムの繰り返しは平均）の平均。中央値・ワースト値・95%値は「集計_統計量」。"; ...
    "ワースト値は最も悪い Wafer の値（RMSE・MAE は最大、R² は最小）。95%値は 95% の Wafer がそれより良い値（RMSE・MAE は 95 パーセント点、R² は 5 パーセント点。Excel の PERCENTILE.INC と同じ補間）。"; ...
    "学習 Shot の組の評価指標（XY 多項式の基準モデル、候補の全 Mark で正規直交化）。I 基準 = tr(M⁻¹)、D 基準 = det(M)^(−1/p)。小さいほど良い。全候補を使うと I 基準 = 項数、D 基準 = 1。全計測に対する I 効率 = 項数 / I 基準、D 効率 = 1 / D 基準（0〜1。1 なら全計測と同じ、大きいほど良い）。"; ...
    overlayText(results, overlayEvaluated); outlierText(results.settings)];
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

% 集計の統計量（指標 × 集計のしかた × 手法 を縦に並べる）
[statisticList, statisticLabels] = alignest.statisticNames();
blocks = cell(0, 1);
for metric = SUMMARY_METRICS
    for k = 1:numel(statisticList)
        aggregated = alignest.summarizeResults(results, metric, statisticList(k));
        nMethods = numel(aggregated.methodLabels);
        block = table(repmat(metricLabels(metricNames == metric), nMethods, 1), repmat(statisticLabels(k), nMethods, 1), ...
            aggregated.methodLabels, aggregated.methodIds, 'VariableNames', ["指標", "集計", "手法", "手法の識別子"]);
        for g = 1:numel(aggregated.groups)
            block.(aggregated.groups(g)) = aggregated.values(:, g);
        end
        blocks{end + 1, 1} = block; %#ok<AGROW>
    end
end
writetable(vertcat(blocks{:}), filePath, 'Sheet', '集計_統計量');

% Wafer ごと
[keep, headers] = alignest.resultColumnNames(isfield(results, "overlayEvaluated") && results.overlayEvaluated);
perWafer = results.table(:, keep);
perWafer.Properties.VariableNames = cellstr(headers);
writetable(perWafer, filePath, 'Sheet', 'Waferごと');

% 学習 Shot
plans = results.plans;
shotList = strings(numel(plans), 1);
for k = 1:numel(plans)
    shotList(k) = strjoin(string(plans(k).shotNos(:).'), " ");
end
planTable = table(string({plans.unitLabel}).', string({plans.label}).', [plans.nShots].', shotList, ...
    [plans.criterionI].', [plans.criterionD].', [plans.efficiencyI].', [plans.efficiencyD].', [plans.violation].', ...
    [plans.seconds].', [plans.reused].', string({plans.message}).', 'VariableNames', ["Wafer", "学習パターン", ...
    "学習Shot数", "学習ShotのshotNo", "I基準tr(M⁻¹)", "D基準det(M)^(-1/p)", "I効率(全計測に対する)", ...
    "D効率(全計測に対する)", "制約の違反量", "学習パターンの計算時間[秒]", "同じ配置のWaferから使い回し", "メモ"]);
writetable(planTable, filePath, 'Sheet', '学習Shot');

% 処理時間（記録したときだけ）
if timingRecorded
    writetable(timingTable(results), filePath, 'Sheet', '処理時間');
end

% 設定（JSON を1行ずつ）
settingsLines = splitlines(string(jsonencode(results.settings, 'PrettyPrint', true)));
writetable(table(settingsLines, 'VariableNames', "設定（JSON）"), filePath, 'Sheet', '設定');
end

function timing = timingTable(results)
% 手法 × 学習パターンの列ごとの 1 枚あたりの処理時間（推定できた Wafer × 学習パターンの各回）
table_ = results.table;
methodColumn = strings(0, 1);
idColumn = strings(0, 1);
groupColumn = strings(0, 1);
statistics = zeros(0, 6);
for m = 1:numel(results.methods)
    for g = 1:numel(results.groups)
        seconds = table_.seconds(table_.methodIndex == m & table_.group == results.groups(g) & table_.note == "");
        seconds = seconds(isfinite(seconds));
        methodColumn(end + 1, 1) = results.methods(m).label; %#ok<AGROW>
        idColumn(end + 1, 1) = results.methods(m).id; %#ok<AGROW>
        groupColumn(end + 1, 1) = results.groups(g); %#ok<AGROW>
        if isempty(seconds)
            statistics(end + 1, :) = [NaN, NaN, NaN, NaN, 0, 0]; %#ok<AGROW>
        else
            statistics(end + 1, :) = [mean(seconds), median(seconds), alignest.stats.percentile(seconds, 95), ...
                max(seconds), sum(seconds), numel(seconds)]; %#ok<AGROW>
        end
    end
end
timing = table(methodColumn, idColumn, groupColumn, statistics(:, 1), statistics(:, 2), statistics(:, 3), ...
    statistics(:, 4), statistics(:, 5), statistics(:, 6), 'VariableNames', ["手法", "手法の識別子", "列", ...
    "平均[秒/枚]", "中央値[秒/枚]", "95%値[秒/枚]", "最大[秒/枚]", "合計[秒]", "回数"]);
end

function text = overlayText(results, evaluated)
if ~evaluated
    text = "しない（補正モデルの成分がすべて「なし」）";
    return
end
text = "補正モデル：" + results.overlayDescription + "（X・Y 別に最小二乗）。実測値で補正した残差、推定値で補正した残差" + ...
    "（学習 Shot は計測値、それ以外は推定値で補正を求め、実際の値に当てた残差）、推定による変化（両者の差）を、" + ...
    "全 Mark の |平均|+3σ [nm] で「Waferごと」に出す。増加 = 推定値で補正 − 実測値で補正。";
end

function value = summaryField(summary, name)
value = strings(1, 0);
if isfield(summary, name)
    value = summary.(name);
end
end

function text = listText(values)
if isempty(values)
    text = "（列なし・空）";
else
    text = strjoin(string(values), "、");
end
end

function text = factorText(choice, choiceY)
% 推定に使った質的変数（GPR・GAM・Backfitting）。X 成分と Y 成分で違えば別々に書く
text = usedText(choice);
if ~isequal(choice, choiceY)
    text = "X 成分：" + text + "／Y 成分：" + usedText(choiceY);
end
text = text + "（GPR・GAM・TPS／RBF／Kriging の Backfitting で使う）";
end

function text = usedText(choice)
names = ["Scan 方向", "Mark 番号", "Shot 行の奇偶"];
used = names([choice.scan, choice.mark, choice.row]);
used = [used, "列 " + choice.columns];
text = "なし";
if ~isempty(used)
    text = strjoin(used, "、");
end
end

function text = directionText(summary)
text = ternary(summary.hasDirection, "あり", "なし");
if isfield(summary, "directionSource")
    text = summary.directionSource;
    if isfield(summary, "nDirectionAssigned") && summary.nDirectionAssigned > 0
        [ruleNames, ruleLabels] = alignest.directionRules();
        text = text + sprintf("（規則で付けた行：%d、規則：%s）", summary.nDirectionAssigned, ...
            ruleLabels(ruleNames == summary.directionRule));
    end
end
end

function value = ternary(condition, whenTrue, whenFalse)
if condition
    value = whenTrue;
else
    value = whenFalse;
end
end

function label = samplingLabel(sampling)
switch string(sampling.method)
    case "ioptimal"
        label = "制約付き I 最適";
    case "random"
        label = sprintf("制約つきランダム（%d 回）", sampling.randomRepeats);
    case "file"
        label = sprintf("ファイルの優先順（%s、%d 行。優先度 1 = 必ず計測、0 = 計測しない）", sampling.priorityFile, ...
            numel(sampling.priorityShots));
    otherwise
        label = "手動で指定";
        return
end
if isfield(sampling, "countBy") && sampling.countBy == "rate"
    label = label + "。学習 Shot 数は計測率（Wafer の候補 Shot 数に対する割合）で決めた";
end
if any(string(sampling.method) == ["ioptimal", "random"])
    required = strings(0, 1);
    if isfield(sampling, "requiredShots") && ~isempty(sampling.requiredShots)
        required(end + 1) = "shotNo " + strjoin(string(sampling.requiredShots), " ");
    end
    if isfield(sampling, "requireOuterShots") && sampling.requireOuterShots
        required(end + 1) = "最外周の Shot";
    end
    if ~isempty(required)
        label = label + "。必ず計測する Shot：" + strjoin(required, "・") + "（残りを選んだ）";
    end
end
end

function text = outlierText(settings)
% 学習データの異常値を除いたかどうかと、その決め方
text = "除かない";
if isfield(settings.evaluation, "excludeOutliers") && settings.evaluation.excludeOutliers
    text = sprintf(['除いた（Wafer・学習パターンごとに学習点の平均と σ を X・Y 別に求め、|値 − 平均| > %g σ の軸が' ...
        'ある Mark を X・Y の両方の学習データから除いた。「Waferごと」の「学習から除いた異常値の数」）'], ...
        settings.evaluation.outlierSigma);
end
end
