function [settings, key] = singleFactorSettings(settings, method)
%SINGLEFACTORSETTINGS 質的変数を1つだけ使う手法（id の最後が "_1f-<変数>"。alignest.singleFactorMethods）なら、
%   settings.factors をその変数だけにした設定を返す（X・Y 成分ともに。その成分で選んでいなかった変数なら、
%   その成分は質的変数なし）。ほかの手法では settings をそのまま返す。key は変数（scan・mark・row・列:<列名>。無ければ ""）。
SEPARATOR = "_1f-";
key = "";
id = string(method.id);
if ~contains(id, SEPARATOR)
    return
end
key = extractAfter(id, SEPARATOR);
factors = struct();
for axisName = ["X", "Y"]
    choice = alignest.factorChoice(settings, axisName);
    part = struct("scan", choice.scan && key == "scan", "mark", choice.mark && key == "mark", ...
        "shotRowParity", choice.row && key == "row", "columns", strings(1, 0));
    if startsWith(key, "列:")
        column = extractAfter(key, "列:");
        part.columns = choice.columns(choice.columns == column);
    end
    if axisName == "X"
        factors = part;
    else
        factors.y = part;
    end
end
factors.separateY = true;
factors.evaluateSingles = false;
settings.factors = factors;
end
