function keys = parseMarkKeys(texts)
%PARSEMARKKEYS 計測マップで指定した Mark の文字（"shotNo-markNo"。例 "12-3"）を [shotNo, markNo] の行に直す。
%   keys = alignest.parseMarkKeys(texts)
%   texts：文字の並び（空なら 0 行）。形が違う文字はエラー（alignest:markKeys）。同じ Mark は1つにまとめる。
texts = reshape(string(texts), [], 1);
texts = strtrim(texts(strtrim(texts) ~= ""));
keys = zeros(numel(texts), 2);
for k = 1:numel(texts)
    parts = split(texts(k), "-");
    numbers = str2double(parts);
    if numel(parts) ~= 2 || any(~isfinite(numbers)) || any(numbers ~= round(numbers))
        error('alignest:markKeys', 'Mark の指定は「shotNo-markNo」（例：12-3）にしてください: %s', texts(k));
    end
    keys(k, :) = numbers.';
end
keys = unique(keys, 'rows', 'stable');
end
