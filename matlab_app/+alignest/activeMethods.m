function [methods, note] = activeMethods(settings)
%ACTIVEMETHODS 比べる手法の一覧（alignest.buildMethodList）から、推定する値に使えない手法を除く。
%   [methods, note] = alignest.activeMethods(settings)
%   1変数の推定（alignest.valueSpec）では、X・Y の2成分を同時に当てはめる RT モデルを除く（除いたら note に理由）。
methods = alignest.buildMethodList(settings.methods);
note = "";
if isfield(settings, "data") && alignest.valueSpec(settings.data).scalar
    isRt = string({methods.family}) == "RT";
    if any(isRt)
        methods = methods(~isRt);
        note = "1変数の推定なので、RT モデル（X・Y の2成分を同時に当てはめる）は比べません。";
    end
end
end
