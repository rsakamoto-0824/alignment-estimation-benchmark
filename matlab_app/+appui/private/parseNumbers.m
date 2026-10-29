function [values, ok] = parseNumbers(text)
% 空白・カンマ区切りの数字を読む。空欄は空の並び。全角の数字・空白・カンマも読む（日本語入力のまま打てるように）
text = strtrim(regexprep(char(alignest.normalizeNumberText(strjoin(string(text), " "))), '[,、\s]+', ' '));
if isempty(text)
    values = zeros(1, 0);
    ok = true;
    return
end
values = str2double(split(string(text), " ")).';
ok = all(isfinite(values));
end
