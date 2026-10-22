function [sheet, headers] = readSheetTable(filePath, sheetName, textHeaders, textPrefixes)
%READSHEETTABLE Excel のシートを、見出しをそのまま列名にして読む（書き出した評価結果・推定値の読み込みで使う）。
%   [sheet, headers] = alignest.readSheetTable(filePath, sheetName, textHeaders)
%   [sheet, headers] = alignest.readSheetTable(filePath, sheetName, textHeaders, textPrefixes)
%   textHeaders に挙げた見出しの列と、見出しが textPrefixes のどれかで始まる列は文字列として読む
%   （引用符・行頭の空白は書いたとおりに残し、空のセルは ""）。それ以外の列は数値（空・読めないセルは NaN）。
%   headers はシートの見出し（左から順）。
arguments
    filePath (1, 1) string
    sheetName (1, 1) string
    textHeaders string = strings(1, 0)
    textPrefixes string = strings(1, 0)
end
options = detectImportOptions(filePath, 'Sheet', sheetName, 'VariableNamingRule', 'preserve');
headers = string(options.VariableNames);
isText = ismember(headers, textHeaders);
for prefix = reshape(textPrefixes, 1, [])
    isText = isText | startsWith(headers, prefix);
end
if any(isText)
    options = setvartype(options, cellstr(headers(isText)), 'string');
    options = setvaropts(options, cellstr(headers(isText)), 'QuoteRule', 'keep', 'WhitespaceRule', 'preserve');
end
if any(~isText)
    options = setvartype(options, cellstr(headers(~isText)), 'double');
end
sheet = readtable(filePath, options);
for header = headers(isText)
    values = sheet.(header);
    values(ismissing(values)) = "";
    sheet.(header) = values;
end
end
