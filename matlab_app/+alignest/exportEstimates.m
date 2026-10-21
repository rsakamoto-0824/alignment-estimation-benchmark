function exportEstimates(estimates, analysis, filePath, notes, options)
%EXPORTESTIMATES 推定値（評価点ごとの計測値・推定値・残差）と残差の検定結果を Excel ファイル（.xlsx）に書き出す。
%   alignest.exportEstimates(estimates, analysis, filePath, notes)
%   estimates は alignest.collectEstimates、analysis は alignest.residualAnalysis の結果。
%   notes は「説明」シートに書く [項目, 内容] の文字列（2列）。
%   シート：説明／推定値／正規性検定／ANOVA／Overlay残差（options.overlayPoints を渡したとき）。
%   同じ名前のファイルは置き換える（Excel で開いているときは書き出せない）。
arguments
    estimates table
    analysis struct
    filePath (1, 1) string
    notes (:, 2) string = strings(0, 2)
    options.overlayPoints table = table()
end
EXCEL_MAX_DATA_ROWS = 1048575;  % Excel の最大行数 1,048,576 から見出しの1行を除いた数
[~, ~, extension] = fileparts(filePath);
if ~strcmpi(extension, ".xlsx")
    error('alignest:exportType', '書き出し先は .xlsx にしてください: %s', filePath);
end
if max(height(estimates), height(options.overlayPoints)) > EXCEL_MAX_DATA_ROWS
    error('alignest:tooManyRows', '推定値が %d 行あり、Excel の上限（%d 行）を超えます。範囲を絞ってください。', ...
        max(height(estimates), height(options.overlayPoints)), EXCEL_MAX_DATA_ROWS);
end
replaceFile(filePath);

items = ["作成日時"; "評価点の数"; "残差"; "正規性検定"; "ANOVA"; "Overlay残差"; notes(:, 1)];
values = [string(datetime('now', 'Format', 'yyyy/MM/dd HH:mm:ss')); string(height(estimates)); ...
    "残差 = 計測値 − 推定値 [nm]。評価点は学習しなかった Shot の有効な Mark。その軸が無効な点は空欄。"; ...
    "手法 × 学習パターン × 軸ごとに、選んだ Wafer の評価点をまとめて検定。p 値が 0.05 より小さいと正規分布から外れていると判断（判定は Shapiro–Wilk、5000 点を超えるときは Anderson–Darling）。点数が多いと小さなずれでも p 値が小さくなる。"; ...
    "残差の平均が質的変数の水準で違うかの F 検定。一元配置はその変数だけで分けた検定、調整はほかの質的変数も入れた主効果モデル（交互作用なし、Type II）での検定。"; ...
    overlayNote(height(options.overlayPoints)); notes(:, 2)];
writetable(table(items, values, 'VariableNames', ["項目", "内容"]), filePath, 'Sheet', '説明');

points = estimates;
if any(string(points.Properties.VariableNames) == "markIndex")
    points = removevars(points, "markIndex");
end
internal = ["plan", "group", "methodLabel", "methodId", "direction", "shotRowParity", "x", "y", "r", ...
    "measX", "estimateX", "residualX", "measY", "estimateY", "residualY"];
headers = ["学習パターン", "列", "手法", "手法の識別子", "Direction", "Shot行(1=奇数,2=偶数)", "x[mm]", "y[mm]", ...
    "半径[mm]", "計測値X[nm]", "推定値X[nm]", "残差X[nm]", "計測値Y[nm]", "推定値Y[nm]", "残差Y[nm]"];
names = string(points.Properties.VariableNames);
[found, position] = ismember(names, internal);
names(found) = headers(position(found));  % 質的変数に選んだその他の列（質的変数:<列名>）はそのまま
points.Properties.VariableNames = cellstr(names);
writetable(points, filePath, 'Sheet', '推定値');

if height(analysis.normality) > 0
    normality = analysis.normality;
    normality.Properties.VariableNames = cellstr(["手法", "手法の識別子", "列", "軸", "点数", "平均[nm]", ...
        "標準偏差[nm]", "歪度", "尖度(過剰)", "Shapiro-Wilk W", "Shapiro-Wilk p値", "Anderson-Darling A2", ...
        "Anderson-Darling p値", "Jarque-Bera", "Jarque-Bera p値", "判定に使った検定", "判定"]);
    writetable(normality, filePath, 'Sheet', '正規性検定');
end
if height(options.overlayPoints) > 0
    overlay = options.overlayPoints;
    overlay.Properties.VariableNames = cellstr(["Operation", "EqpId", "LotID", "Wafer", "DateTime", "学習パターン", ...
        "列", "手法", "手法の識別子", "shotNo", "markNo", "x[mm]", "y[mm]", "Shotの区分", ...
        "実測値で補正した残差X[nm]", "実測値で補正した残差Y[nm]", "推定値で補正した残差X[nm]", ...
        "推定値で補正した残差Y[nm]", "推定による変化X[nm]", "推定による変化Y[nm]"]);
    writetable(overlay, filePath, 'Sheet', 'Overlay残差');
end
if height(analysis.anova) > 0
    anova = analysis.anova;
    anova.Properties.VariableNames = cellstr(["手法", "手法の識別子", "列", "軸", "質的変数", "水準の数", ...
        "水準ごとの平均残差[nm](点数)", "F(一元配置)", "自由度1", "自由度2", "p値(一元配置)", "η²", ...
        "F(ほかの変数で調整)", "自由度(調整)", "p値(調整)", "メモ", "判定(一元配置)"]);
    writetable(anova, filePath, 'Sheet', 'ANOVA');
end
end

function text = overlayNote(nRows)
if nRows == 0
    text = "なし（Overlay 補正の評価をしない設定）";
else
    text = "全 Mark（学習・評価 Shot）の補正残差。実測値で補正した残差 = 計測値 − 補正量(計測値)、" + ...
        "推定値で補正した残差 = 計測値 − 補正量(学習 Shot は計測値・それ以外は推定値)、推定による変化 = 両者の差 [nm]。";
end
end

function replaceFile(filePath)
if isfile(filePath)
    try
        delete(filePath);
    catch err
        error('alignest:exportLocked', '「%s」を置き換えられません（Excel で開いていないか確かめてください）。理由: %s', ...
            filePath, err.message);
    end
end
end
