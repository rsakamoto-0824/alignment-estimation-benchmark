function [raw, info] = readHighOrderFile(filePath, sheetName)
%READHIGHORDERFILE Shot 高次補正の入力にする Excel・CSV を読み、項目（alignest.highOrderColumns）に合う列を見出しから推定する。
%   [raw, info] = alignest.readHighOrderFile(filePath)
%   [raw, info] = alignest.readHighOrderFile(filePath, sheetName)
%   列の名前は自由（読んだ後で、項目ごとにファイルの列を選ぶ。alignest.prepareHighOrderData で Wafer ごとのデータにする）。
%   推定：見出しが項目名と同じ列、大文字・小文字だけ違う列、別名（highOrderColumns の aliases）の列の順に探す。任意の項目で、
%   値がすべて空の列（書き出した推定値の markNo など）は推定しない。
%   シートを指定しないときは、「推定値」のシート（このアプリが書き出した推定値の Excel）があればそれを、無ければ先頭の
%   シートを読む。
%   raw：読んだ表。info.file（ファイル名）・path・sheet（読んだシート。CSV は ""）・sheets（シートの一覧）・rows（行の数）・
%   columns（ファイルの列の名前）・mapping（推定した対応。項目名 → ファイルの列。見つからなければ ""）。
arguments
    filePath (1, 1) string
    sheetName (1, 1) string = ""
end
PREFERRED_SHEET = "推定値";   % このアプリが書き出した推定値の Excel のシート
[~, ~, extension] = fileparts(filePath);
if sheetName == "" && any(lower(extension) == [".xlsx", ".xlsm", ".xls"]) && isfile(filePath)
    if any(string(sheetnames(filePath)) == PREFERRED_SHEET)
        sheetName = PREFERRED_SHEET;
    end
end
[raw, sheets, sheetName] = alignest.readMeasurementFile(filePath, sheetName);
if height(raw) == 0
    error('alignest:highOrderFile', 'ファイルに行がありません: %s', filePath);
end
columnNames = string(raw.Properties.VariableNames);
mapping = struct();
for column = alignest.highOrderColumns()
    name = string(column.name);
    mapping.(name) = "";
    for candidate = [name, column.aliases]
        match = columnNames(columnNames == candidate);
        if isempty(match)
            match = columnNames(strcmpi(columnNames, candidate));
        end
        if ~isempty(match) && (column.required || ~all(ismissing(raw.(match(1)))))
            mapping.(name) = match(1);
            break
        end
    end
end
[~, name, extension] = fileparts(filePath);
info = struct("file", string(name) + string(extension), "path", filePath, "sheet", string(sheetName), ...
    "sheets", string(sheets), "rows", height(raw), "columns", columnNames, "mapping", mapping);
end
