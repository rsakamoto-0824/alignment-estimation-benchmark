function [rgb, ok] = hexToRgb(text)
% 「#RRGGBB」（# は無くてもよい。全角も読む）を RGB（0〜1）にする。読めなければ ok = false
rgb = [0, 0, 0];
text = upper(strtrim(alignest.normalizeNumberText(string(text))));
text = erase(text, "#");
ok = strlength(text) == 6 && ~isempty(regexp(text, '^[0-9A-F]{6}$', 'once'));
if ok
    rgb = double(hex2dec(reshape(char(text), 2, 3).')).' / 255;
end
end
