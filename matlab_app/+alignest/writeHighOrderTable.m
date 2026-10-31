function writeHighOrderTable(filePath, data, notes)
%WRITEHIGHORDERTABLE Shot 高次補正の書き出しの表を、CSV か Excel（.xlsx）に書く（「7. Shot高次補正」の「書き出し」）。
%   alignest.writeHighOrderTable(filePath, data)
%   alignest.writeHighOrderTable(filePath, data, notes)   % notes：Excel のときだけ「説明」シートに書く行（[項目, 内容]）
%   CSV は UTF-8（先頭に BOM を付ける。Windows の Excel で開いても日本語の列名が化けないように）。値の無いところ（NaN）は空欄
%   にする（0 や NaN の文字にしない）。数は 12 桁まで書く。Excel は「値」シートに書く（同じ名前のファイルは置き換える）。
arguments
    filePath (1, 1) string
    data table
    notes (:, 2) string = strings(0, 2)
end
UTF8_BOM = uint8([239, 187, 191]);
NUMBER_FORMAT = "%.12g";
[~, ~, extension] = fileparts(filePath);
extension = lower(extension);
if ~any(extension == [".csv", ".xlsx"])
    error('alignest:exportType', '書き出し先は .csv か .xlsx にしてください: %s', filePath);
end
if isfile(filePath)
    try
        delete(filePath);
    catch err
        error('alignest:exportLocked', '「%s」を置き換えられません（Excel で開いていないか確かめてください）。理由: %s', ...
            filePath, err.message);
    end
end
if extension == ".xlsx"
    if ~isempty(notes)
        writetable(table(notes(:, 1), notes(:, 2), 'VariableNames', ["項目", "内容"]), filePath, 'Sheet', '説明');
    end
    writetable(data, filePath, 'Sheet', '値');
    return
end
% CSV：数の列は文字にして、NaN を空欄にする
text = data;
for name = string(data.Properties.VariableNames)
    column = data.(name);
    if isnumeric(column) || islogical(column)
        converted = compose(NUMBER_FORMAT, double(column));
        converted(~isfinite(double(column))) = "";
        text.(name) = converted;
    end
end
writetable(text, filePath, 'Encoding', 'UTF-8');
fileId = fopen(filePath, 'r');
bytes = fread(fileId, Inf, 'uint8=>uint8');
fclose(fileId);
fileId = fopen(filePath, 'w');
fwrite(fileId, [UTF8_BOM, reshape(bytes, 1, [])]);
fclose(fileId);
end
