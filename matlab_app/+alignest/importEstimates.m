function imported = importEstimates(filePath)
%IMPORTESTIMATES 「推定値を Excel に書き出す」（alignest.exportEstimates）で書き出したファイルを読み、推定値の表に戻す。
%   imported = alignest.importEstimates(filePath)
%   imported.estimates    ：「推定値」シート。列名は alignest.collectEstimates の表と同じ（区分は role 列。
%                           以前の版で区分の列が無いファイルは、すべて「評価」とする）
%   imported.overlayPoints：「Overlay残差」シート（無ければ空の表）
%   imported.hasTraining  ：学習データの行（区分が「学習」）があるか（分布の比較で Wafer 全面・学習の分布に使う）
%   imported.file         ：読んだファイル
%   評価結果の Excel（alignest.importResults）と組にして、Wafer マップ・推定値と誤差の分布・散布図・分布の比較を、
%   計測ファイルを読まずに描くために使う（書き出した手法・学習パターン・Wafer の範囲だけ）。
arguments
    filePath (1, 1) string
end
POINT_TEXT = ["Operation", "EqpId", "LotID", "Wafer", "DateTime", "plan", "group", "methodLabel", "methodId", "role"];
POINT_REQUIRED = ["Wafer", "plan", "group", "methodId", "x", "y", "measX", "estimateX", "measY", "estimateY"];
if ~isfile(filePath)
    error('alignest:importEstimates', 'ファイルが見つかりません: %s', filePath);
end
try
    sheets = string(sheetnames(filePath));
catch err
    error('alignest:importEstimates', 'Excel ファイルとして読めません: %s（%s）', filePath, err.message);
end
if ~any(sheets == "推定値")
    error('alignest:importEstimates', ['「推定値」のシートがありません。このアプリの「推定値を Excel に書き出す」で' ...
        '書き出したファイルを選んでください: %s'], filePath);
end
[names, headers] = alignest.estimateColumnNames("points");
% 見出しの変わらない列（Operation・Wafer・shotNo など）は、列名と見出しが同じ
textHeaders = [headers(ismember(names, POINT_TEXT)), POINT_TEXT];
[sheet, fileHeaders] = alignest.readSheetTable(filePath, "推定値", textHeaders, "質的変数:");
renamed = fileHeaders;
[found, position] = ismember(fileHeaders, headers);
renamed(found) = names(position(found));
sheet.Properties.VariableNames = cellstr(renamed);
missing = POINT_REQUIRED(~ismember(POINT_REQUIRED, renamed));
if ~isempty(missing)
    error('alignest:importEstimates', ['「推定値」のシートに必要な列（%s）がありません。このアプリの' ...
        '「推定値を Excel に書き出す」で書き出したファイルを選んでください。'], strjoin(missing, "、"));
end
n = height(sheet);
defaults = struct("Operation", strings(n, 1), "EqpId", strings(n, 1), "LotID", strings(n, 1), ...
    "DateTime", strings(n, 1), "methodLabel", sheet.methodId, "shotNo", nan(n, 1), "markNo", nan(n, 1), ...
    "direction", nan(n, 1), "shotRowParity", nan(n, 1), "r", hypot(sheet.x, sheet.y), "role", repmat("評価", n, 1));
for name = string(fieldnames(defaults)).'
    if ~ismember(name, renamed)
        sheet.(name) = defaults.(name);
    end
end
% 残差は計測値 − 推定値（Excel の値が無いときも同じ式で作る）
sheet.residualX = sheet.measX - sheet.estimateX;
sheet.residualY = sheet.measY - sheet.estimateY;
order = ["Operation", "EqpId", "LotID", "Wafer", "DateTime", "plan", "group", "methodLabel", "methodId", "shotNo", ...
    "markNo", "direction", "shotRowParity", "x", "y", "r", "role", "measX", "estimateX", "residualX", "measY", ...
    "estimateY", "residualY"];
factorColumns = string(sheet.Properties.VariableNames(startsWith(sheet.Properties.VariableNames, "質的変数:")));
imported.estimates = sheet(:, [order, factorColumns]);
imported.hasTraining = any(startsWith(imported.estimates.role, "学習"));
imported.overlayPoints = table();
if any(sheets == "Overlay残差")
    [overlayNames, overlayHeaders] = alignest.estimateColumnNames("overlay");
    textNames = ["Operation", "EqpId", "LotID", "Wafer", "DateTime", "plan", "group", "methodLabel", "methodId", "role"];
    [overlay, overlayFileHeaders] = alignest.readSheetTable(filePath, "Overlay残差", ...
        overlayHeaders(ismember(overlayNames, textNames)));
    if all(ismember(overlayHeaders, overlayFileHeaders))
        overlay = overlay(:, overlayHeaders);
        overlay.Properties.VariableNames = cellstr(overlayNames);
        imported.overlayPoints = overlay;
    end
end
imported.file = filePath;
end
