function names = factorNames(factors)
%FACTORNAMES 質的変数の水準の構造体（<名前>Train・<名前>Test の組）にある変数の名前を、決まった順に並べる。
%   Scan 方向（scan）・Mark 番号（mark）・Shot 行の奇偶（row）をこの順に先に、その他の列（col_…）はその後に
%   構造体の項目の順で並べる（効果コードの列の順をいつも同じにするため）。
fields = string(fieldnames(factors)).';
names = extractBefore(fields(endsWith(fields, "Train")), strlength(fields(endsWith(fields, "Train"))) - 4);
standard = ["scan", "mark", "row"];
names = [standard(ismember(standard, names)), names(~ismember(names, standard))];
end
