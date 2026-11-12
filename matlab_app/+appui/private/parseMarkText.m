function [keys, ok] = parseMarkText(text)
% 「shotNo-markNo」（例：12-3）を空白・カンマで区切った文字を読み、"12-3" の文字の並び（1 × n。同じ Mark は1つ）にする。
% 空欄は空の並び。全角の数字・空白・カンマ・ハイフンも読む（日本語入力のまま打てるように）。形が違えば ok = false
text = strtrim(regexprep(char(alignest.normalizeNumberText(strjoin(string(text), " "))), '[,、\s]+', ' '));
keys = strings(1, 0);
ok = true;
if isempty(text)
    return
end
try
    pairs = alignest.parseMarkKeys(split(string(text), " "));
catch
    ok = false;
    return
end
keys = reshape(compose("%d-%d", pairs(:, 1), pairs(:, 2)), 1, []);
end
