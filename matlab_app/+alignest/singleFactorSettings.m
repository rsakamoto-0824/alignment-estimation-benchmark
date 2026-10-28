function [settings, key] = singleFactorSettings(settings, method)
%SINGLEFACTORSETTINGS 手法の id に質的変数の指定があれば、settings.factors をその変数だけにした設定を返す。
%   質的変数を1つだけ使う手法（id の最後が "_1f-<変数>"。alignest.singleFactorMethods）：その変数だけにする
%   （X・Y 成分ともに。その成分で選んでいなかった変数なら、その成分は質的変数なし）。key は変数。
%   質的変数の組を持つ手法（id の最後が "_fs-<組>"。質的変数を変えて条件を追加した手法。alignest.tagFactorSet）：
%   組のとおりにする（評価の設定の質的変数によらない）。key は組（alignest.factorSetKey と同じ書き方）。
%   ほかの手法では settings をそのまま返し、key は ""。
SEPARATOR = "_1f-";
SET_SEPARATOR = "_fs-";
key = "";
id = string(method.id);
if contains(id, SET_SEPARATOR)
    key = extractAfter(id, SET_SEPARATOR);
    settings.factors = factorsFromKey(key);
    return
end
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

function factors = factorsFromKey(key)
% "_fs-" の組（"scan+mark"・"scan+mark~scan"・"none"）を settings.factors の形にする
parts = split(key, "~");
if isscalar(parts)
    parts = [parts; parts];   % X・Y で同じ
end
factors = struct();
for k = 1:2
    names = strings(1, 0);
    if parts(k) ~= "none"
        names = split(parts(k), "+").';
    end
    part = struct("scan", any(names == "scan"), "mark", any(names == "mark"), "shotRowParity", any(names == "row"), ...
        "columns", extractAfter(names(startsWith(names, "列:")), "列:"));
    if k == 1
        factors = part;
    else
        factors.y = part;
    end
end
factors.separateY = true;
factors.evaluateSingles = false;
end
