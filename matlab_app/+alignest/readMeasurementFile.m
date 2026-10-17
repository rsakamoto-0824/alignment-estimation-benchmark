function [raw, sheets, sheetName] = readMeasurementFile(filePath, sheetName)
%READMEASUREMENTFILE Excel（.xlsx・.xlsm・.xls）または CSV の計測データを表として読む。
%   [raw, sheets, sheetName] = alignest.readMeasurementFile(filePath, sheetName)
%   sheetName を省略すると先頭のシートを読む。列名は変えずに読む（標準の項目名は大文字・小文字を区別するため）。
%   Excel 本体は不要（MATLAB の読み込み機能を使う）。
arguments
    filePath (1, 1) string
    sheetName (1, 1) string = ""
end
if ~isfile(filePath)
    error('alignest:fileNotFound', 'ファイルが見つかりません: %s', filePath);
end
[~, ~, extension] = fileparts(filePath);
extension = lower(extension);
switch extension
    case {'.xlsx', '.xlsm', '.xls'}
        sheets = string(sheetnames(filePath));
        if sheetName == ""
            sheetName = sheets(1);
        elseif ~any(sheets == sheetName)
            error('alignest:sheetNotFound', 'シート「%s」がありません。あるシート: %s', sheetName, strjoin(sheets, "、"));
        end
        raw = readtable(filePath, 'Sheet', sheetName, 'VariableNamingRule', 'preserve', 'TextType', 'string');
    case {'.csv', '.txt'}
        sheets = "";
        sheetName = "";
        raw = readtable(filePath, 'VariableNamingRule', 'preserve', 'TextType', 'string');
    otherwise
        error('alignest:fileType', '読み込めるのは .xlsx・.xlsm・.xls・.csv です: %s', extension);
end
if height(raw) == 0
    error('alignest:emptyFile', 'データの行がありません（1行目は項目名、2行目からデータにしてください）。');
end
end
