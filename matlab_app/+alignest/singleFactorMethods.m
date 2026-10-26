function methods = singleFactorMethods(methods, settings)
%SINGLEFACTORMETHODS 質的変数を使う手法に、チェックした質的変数を1つだけ使う手法を足す。
%   methods = alignest.singleFactorMethods(methods, settings)
%   settings.factors.evaluateSingles が true で、チェックした質的変数（X・Y 成分の選択を合わせたもの）が2つ以上あると
%   き、質的変数を使う手法（alignest.usesFactors）ごとに、その後ろへ変数ごとの手法を足す（全部を使う手法も残す）。
%   id の最後に "_1f-<変数>"（scan・mark・row・列:<列名>）、表示名の最後に「｜質的変数：<名前>だけ」を付ける。
%   推定では alignest.singleFactorSettings が、その変数だけを使う設定にする。
if ~isfield(settings, "factors") || ~isfield(settings.factors, "evaluateSingles") || ~settings.factors.evaluateSingles
    return
end
[keys, labels] = checkedFactors(settings);
if numel(keys) < 2
    return
end
expanded = cell(1, numel(methods));
for m = 1:numel(methods)
    parent = methods(m);
    group = parent;
    if alignest.usesFactors(parent)
        for k = 1:numel(keys)
            single = parent;
            single.id = parent.id + "_1f-" + keys(k);
            single.label = parent.label + "｜質的変数：" + labels(k) + "だけ";
            group(end + 1) = single; %#ok<AGROW>
        end
    end
    expanded{m} = group;
end
methods = [expanded{:}];
end

function [keys, labels] = checkedFactors(settings)
% X・Y 成分でチェックした質的変数（決まった順：Scan 方向・Mark 番号・Shot 行の奇偶・その他の列）
choices = [alignest.factorChoice(settings, "X"), alignest.factorChoice(settings, "Y")];
keys = strings(1, 0);
labels = strings(1, 0);
if any([choices.scan])
    keys(end + 1) = "scan";
    labels(end + 1) = "Scan 方向";
end
if any([choices.mark])
    keys(end + 1) = "mark";
    labels(end + 1) = "Mark 番号";
end
if any([choices.row])
    keys(end + 1) = "row";
    labels(end + 1) = "Shot 行の奇偶";
end
columns = unique([choices.columns], 'stable');
keys = [keys, "列:" + columns];
labels = [labels, "列「" + columns + "」"];
end
