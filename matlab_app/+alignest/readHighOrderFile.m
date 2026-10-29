function [data, info] = readHighOrderFile(filePath, sheetName)
%READHIGHORDERFILE Shot 高次補正の入力にする Excel・CSV（Wafer ごとの dx・dy の値）を読み、Wafer ごとのデータにする。
%   [data, info] = alignest.readHighOrderFile(filePath)
%   [data, info] = alignest.readHighOrderFile(filePath, sheetName)
%   列は Overlay 計測ルールの標準の項目名（大文字・小文字の違いは同じ名前とみなす）：Xmm・Ymm（Shot 中心の Wafer 上の
%   座標 [mm]）・markXmm・markYmm（Shot 内の座標 [mm]）・measX・measY（値 [nm]）は必須。Wafer・shotNo・markNo・
%   StsX・StsY・DateTime などは任意（無いときの扱いは「1. データの読み込み」と同じ。alignest.standardColumns）。
%   measX・measY の代わりに、dx・dy の列、またはこのアプリが書き出した推定値の列（推定値X[nm]・推定値Y[nm]）も使える。
%   シートを指定しないときは、「推定値」のシートがあればそれを、無ければ先頭のシートを読む。任意の項目の列で値が
%   すべて空の列は使わない（無い列と同じに扱う）。
%   前処理は「1. データの読み込み」と同じ alignest.prepareData（座標の単位は mm・nm、有効な点は半径 150 mm 未満、
%   StsX・StsY が 0 でない値は使わない、同じ点の行は平均）。data は alignest.prepareData の結果（data.units が Wafer）。
%   info.file・info.sheet：読んだファイル・シート、info.rows：行の数、info.mapping：使った列の対応（項目 → ファイルの列）。
arguments
    filePath (1, 1) string
    sheetName (1, 1) string = ""
end
PREFERRED_SHEET = "推定値";   % このアプリが書き出した推定値の Excel のシート
VALID_RADIUS_MM = 150;        % Overlay 計測ルール：有効な点は半径 150 mm 未満
VALUE_ALIASES = struct("measX", ["dx", "推定値X[nm]"], "measY", ["dy", "推定値Y[nm]"]);
[~, ~, extension] = fileparts(filePath);
if sheetName == "" && any(lower(extension) == [".xlsx", ".xlsm", ".xls"]) && isfile(filePath)
    sheets = string(sheetnames(filePath));
    if any(sheets == PREFERRED_SHEET)
        sheetName = PREFERRED_SHEET;
    end
end
[raw, ~, sheetName] = alignest.readMeasurementFile(filePath, sheetName);
if height(raw) == 0
    error('alignest:highOrderFile', 'ファイルに行がありません: %s', filePath);
end
columnNames = string(raw.Properties.VariableNames);
mapping = alignest.guessColumnMapping(columnNames);
for name = ["measX", "measY"]
    if mapping.(name) == ""
        for alias = VALUE_ALIASES.(name)
            match = columnNames(strcmpi(columnNames, alias));
            if ~isempty(match)
                mapping.(name) = match(1);
                break
            end
        end
    end
end
required = ["Xmm", "Ymm", "markXmm", "markYmm", "measX", "measY"];
% 任意の項目で、列はあるが値がすべて空の列（書き出した推定値の markNo・Direction など）は使わない
for name = string(fieldnames(mapping)).'
    if mapping.(name) ~= "" && ~any(required == name) && all(ismissing(raw.(mapping.(name))))
        mapping.(name) = "";
    end
end
missing = required(arrayfun(@(name) mapping.(name) == "", required));
if ~isempty(missing)
    error('alignest:highOrderFile', ['Shot 高次補正に要る列がありません: %s。1行目の見出しに Xmm・Ymm（Shot 中心の座標 [mm]）・' ...
        'markXmm・markYmm（Shot 内の座標 [mm]）・measX・measY（値 [nm]。dx・dy でもよい）を書いてください' ...
        '（ファイルの列：%s）。'], strjoin(missing, "・"), strjoin(columnNames, "・"));
end
data = alignest.prepareData(raw, mapping, validRadiusMm=VALID_RADIUS_MM);
[~, name, extension] = fileparts(filePath);
info = struct("file", string(name) + string(extension), "sheet", string(sheetName), "rows", height(raw), ...
    "mapping", mapping);
end
