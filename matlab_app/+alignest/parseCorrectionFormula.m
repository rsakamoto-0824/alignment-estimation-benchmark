function terms = parseCorrectionFormula(text, name)
%PARSECORRECTIONFORMULA 補正量の式（例：k1 + k3*x + k5*y + k7*x^2）を読み、項（x・y のべき）の表にする。
%   terms = alignest.parseCorrectionFormula(text)
%   terms = alignest.parseCorrectionFormula(text, name)   % name はエラーの文に出す式の名前（例："Wafer 成分の dx"）
%   terms は 項の数 × 3 の行列 [項の番号, x のべき, y のべき]（alignest.overlayTerms と同じ形）。
%   書き方：
%   - 項を + または − でつなぐ。各項は、係数（k1・a など英字で始まる名前、または数）と x・y のべき
%     （x、x^2、x*y、x^2*y など）を * でつないだもの。係数だけの項は定数（並進）。
%   - 係数の値は最小二乗で求めるので、係数の名前・符号・数は補正量に影響しない（項の形だけを使う）。
%   - 先頭の「dx =」「dy =」は無視する。全角の英数字・記号、−・×・²・³ も読める。x・y の大文字・小文字は区別しない。
%   - 同じべきの項が2回あれば1つにまとめる。かっこは使えない（展開して書く）。べきは 0〜MAX_POWER の整数。
arguments
    text
    name (1, 1) string = "補正の式"
end
MAX_POWER = 9;
FULL_WIDTH_FIRST = 65281;   % 全角の「！」（U+FF01）。ここから「～」（U+FF5E）までを半角にする
FULL_WIDTH_LAST = 65374;
FULL_WIDTH_OFFSET = 65248;  % U+FEE0
original = strtrim(string(text));
if ~isscalar(original) || ismissing(original) || original == ""
    error('alignest:overlayFormula', '%s が空です。例：k1 + k3*x + k5*y', name);
end
codes = double(char(original));
fullWidth = codes >= FULL_WIDTH_FIRST & codes <= FULL_WIDTH_LAST;
codes(fullWidth) = codes(fullWidth) - FULL_WIDTH_OFFSET;
codes(codes == 12288) = 32;   % 全角の空白
formula = string(char(codes));
formula = replace(formula, ["−", "×", "・", "²", "³"], ["-", "*", "*", "^2", "^3"]);
formula = regexprep(formula, '\s+', '');
if count(formula, "=") > 1
    error('alignest:overlayFormula', '%s に「=」が2つ以上あります：%s', name, original);
elseif contains(formula, "=")
    formula = extractAfter(formula, "=");   % 「dx =」などの左辺
end
if contains(formula, ["(", ")", "[", "]", "{", "}"])
    error('alignest:overlayFormula', '%s にかっこは使えません。展開して、項を + でつないでください：%s', name, original);
end
parts = split(formula, ["+", "-"]).';
if parts(1) == ""
    parts = parts(2:end);   % 先頭の符号（例：−k1 + …）
end
if isempty(parts) || any(parts == "")
    error('alignest:overlayFormula', '%s の + や − の前後に項がありません：%s', name, original);
end
powers = zeros(numel(parts), 2);
for k = 1:numel(parts)
    powers(k, :) = termPowers(parts(k), name, original, MAX_POWER);
end
powers = unique(powers, 'rows', 'stable');
terms = [(1:size(powers, 1)).', powers];
end

function power = termPowers(term, name, original, maxPower)
% 1つの項の x・y のべき。係数（英字で始まる名前・数）は読み飛ばす
power = [0, 0];
for factor = split(term, "*").'
    if factor == ""
        error('alignest:overlayFormula', '%s の「%s」に * が続いています：%s', name, term, original);
    end
    text = char(factor);
    lower_ = lower(text);
    if ~isempty(regexp(text, '^\d+(\.\d*)?([eE]\d+)?$', 'once'))
        continue   % 数の係数
    end
    if ~isempty(regexp(lower_, '^([xy](\^\d+)?)+$', 'once'))
        % x・y のべきの積（x*y を xy、x^2*y を x^2y と続けて書いてもよい）
        % 形は上で確かめたので、ここでは文字と（あれば）べきの数字を取り出すだけ（2つ目の組は空でも必ず返る）
        tokens = regexp(lower_, '([xy])\^?(\d*)', 'tokens');
        for t = 1:numel(tokens)
            exponent = 1;
            if numel(tokens{t}) >= 2 && ~isempty(tokens{t}{2})
                exponent = str2double(tokens{t}{2});
            end
            column = 1 + (tokens{t}{1} == 'y');
            power(column) = power(column) + exponent;
        end
        continue
    end
    if ~isempty(regexp(lower_, '^[xy]', 'once'))
        error('alignest:overlayFormula', ['%s の「%s」を読めません。x・y のべきは x^2、x*y のように書き、係数の名前は' ...
            ' x・y 以外の英字（k1 など）で始めてください：%s'], name, factor, original);
    end
    if isempty(regexp(text, '^[A-Za-z_][A-Za-z0-9_]*$', 'once'))
        error('alignest:overlayFormula', '%s の「%s」を読めません（使える文字は英数字・+ − * ^ =）：%s', name, factor, original);
    end
    % それ以外は係数の名前（k1 など）
end
if any(power > maxPower)
    error('alignest:overlayFormula', '%s の「%s」のべきが大きすぎます（%d 以下にしてください）：%s', name, term, maxPower, ...
        original);
end
end
