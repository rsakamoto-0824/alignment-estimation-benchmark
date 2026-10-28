function [key, label] = factorSetKey(settings)
%FACTORSETKEY 推定に使う質的変数の組（settings.factors）を、手法の id に付ける短い文字（key）と表示名（label）にする。
%   [key, label] = alignest.factorSetKey(settings)
%   key：X 成分の変数を "+" でつないだもの（scan・mark・row・列:<列名>。例："scan+mark"、無ければ "none"）。
%   Y 成分の選択が X 成分と違えば "X の組~Y の組"（例："scan+mark~scan"）。
%   label：例「Scan 方向・Mark 番号」、X・Y で違えば「X：Scan 方向・Mark 番号／Y：Scan 方向」、無ければ「なし」。
%   質的変数を変えて条件を追加して評価するとき、足す手法の id の最後に "_fs-<key>" を付けて、その手法が使う
%   質的変数を手法の中に持たせる（alignest.tagFactorSet・alignest.singleFactorSettings）。
[keysX, namesX] = keysOf(alignest.factorChoice(settings, "X"));
[keysY, namesY] = keysOf(alignest.factorChoice(settings, "Y"));
key = joinKeys(keysX);
label = joinNames(namesX);
if ~isequal(keysX, keysY)
    key = key + "~" + joinKeys(keysY);
    label = "X：" + label + "／Y：" + joinNames(namesY);
end
end

function [keys, names] = keysOf(choice)
keys = strings(1, 0);
names = strings(1, 0);
if choice.scan
    keys(end + 1) = "scan";
    names(end + 1) = "Scan 方向";
end
if choice.mark
    keys(end + 1) = "mark";
    names(end + 1) = "Mark 番号";
end
if choice.row
    keys(end + 1) = "row";
    names(end + 1) = "Shot 行の奇偶";
end
keys = [keys, "列:" + choice.columns];
names = [names, "列「" + choice.columns + "」"];
end

function text = joinKeys(keys)
text = "none";
if ~isempty(keys)
    text = strjoin(keys, "+");
end
end

function text = joinNames(names)
text = "なし";
if ~isempty(names)
    text = strjoin(names, "・");
end
end
