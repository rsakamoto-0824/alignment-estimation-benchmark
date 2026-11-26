function text = tableText(data)
% 表（table）を、Excel・PowerPoint の表に貼り付けられる文字（1行目が列名、列はタブ区切り、行は改行）にする。
% 数は 12 桁まで書き、値の無いところ（NaN）は空欄にする（alignest.writeHighOrderTable の CSV と同じ書き方）
NUMBER_FORMAT = "%.12g";
names = string(data.Properties.VariableNames);
cells = strings(height(data), numel(names));
for k = 1:numel(names)
    column = data.(names(k));
    if isnumeric(column) || islogical(column)
        converted = compose(NUMBER_FORMAT, double(column));
        converted(~isfinite(double(column))) = "";
    else
        converted = string(column);
        converted(ismissing(converted)) = "";
    end
    cells(:, k) = reshape(converted, [], 1);
end
lines = strjoin(names, sprintf('\t'));
if ~isempty(cells)
    lines = [lines; join(cells, sprintf('\t'), 2)];
end
text = char(strjoin(lines, newline));
end
