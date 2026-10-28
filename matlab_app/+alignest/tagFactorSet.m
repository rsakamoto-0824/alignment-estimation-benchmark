function methods = tagFactorSet(methods, settings)
%TAGFACTORSET 質的変数を使う手法の id・表示名に、使う質的変数の組を付ける（質的変数を変えて条件を追加するとき）。
%   methods = alignest.tagFactorSet(methods, settings)
%   質的変数を使う手法（alignest.usesFactors）の id の最後に "_fs-<組>"（alignest.factorSetKey）、表示名の最後に
%   「｜質的変数：<組>」を付ける。質的変数を1つだけ使う手法（"_1f-<変数>"。alignest.singleFactorMethods）は、
%   その1つの変数の組（この設定で X・Y 成分に選んであるもの）の "_fs-" に置き換える（表示名はそのまま）。
%   推定では alignest.singleFactorSettings が id の組を使うので、評価の設定の質的変数が違っても同じ推定になる
%   （評価済みの手法は、評価したときの設定の質的変数のまま）。
[~, label] = alignest.factorSetKey(settings);
for m = 1:numel(methods)
    method = methods(m);
    if ~alignest.usesFactors(method)
        continue
    end
    restricted = alignest.singleFactorSettings(settings, method);   % "_1f-" ならその変数だけの設定
    key = alignest.factorSetKey(restricted);
    if contains(method.id, "_1f-")
        methods(m).id = extractBefore(method.id, "_1f-") + "_fs-" + key;
    else
        methods(m).id = method.id + "_fs-" + key;
        methods(m).label = method.label + "｜質的変数：" + label;
    end
end
end
