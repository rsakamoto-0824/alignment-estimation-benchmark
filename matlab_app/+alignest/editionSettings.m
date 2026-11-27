function [settings, changes] = editionSettings(settings, edition)
%EDITIONSETTINGS 通常版で使えない設定を、通常版で使える設定に直す（Pro 版はそのまま）。
%   [settings, changes] = alignest.editionSettings(settings, edition)
%   edition："standard"（通常版）・"pro"（Pro 版）。通常版で使えるのは次のとおり（ほかの設定・タブは Pro 版と同じ）。
%   - 比べる手法：RT モデル以外のすべて（GPR・TPS・RBF・Kriging・Universal Kriging・GAM・XY 多項式・Fringe Zernike。
%     RT モデルは使わない）
%   - 計測点の選び方：Shot 単位の I 最適・ランダム（D 最適・Sobol 列・ポアソンディスク・Excel 取込・Mark 単位は使わない。
%     Mark 単位の選び方は同じアルゴリズムの Shot 単位にする。残らなければ I 最適）
%   - Overlay 補正の成分：組み込みの式だけ（「式を入力」は使わない。Wafer 成分は次数、Shot 共通成分は「なし」、
%     Shot ごとの成分は「1次」にする）
%   changes：直した項目の説明（設定を読み込んだときの知らせに使う。直すものが無ければ空）。
arguments
    settings struct
    edition (1, 1) string {mustBeMember(edition, ["standard", "pro"])}
end
STANDARD_SAMPLING = ["ioptimal", "random"];
changes = strings(0, 1);
if edition == "pro"
    return
end
% 比べる手法
methods = settings.methods;
proMethods = {"RT モデル", ["rt", "enabled"]};   % Pro 版だけの手法
dropped = strings(1, 0);
for k = 1:size(proMethods, 1)
    path = proMethods{k, 2};
    if isfield(methods, path(1)) && isfield(methods.(path(1)), path(2)) && logical(methods.(path(1)).(path(2)))
        methods.(path(1)).(path(2)) = false;
        dropped(end + 1) = proMethods{k, 1}; %#ok<AGROW>
    end
end
settings.methods = methods;
if ~isempty(dropped)
    changes(end + 1) = "比べる手法：" + strjoin(dropped, "・") + "（通常版は RT モデルを使わない）";
end
% 計測点の選び方（Shot 単位の I 最適・ランダム）
sampling = settings.sampling;
chosen = alignest.convertSamplingMethods(string(sampling.method), "shot");   % Mark 単位は同じアルゴリズムの Shot 単位
if isfield(sampling, "unit") && string(sampling.unit) == "mark"
    changes(end + 1) = "データの粒度：Mark 単位 → Shot 単位";
end
[~, names] = alignest.samplingUnitMethods("shot");
shotMethods = alignest.samplingUnitMethods("shot");
removedMethods = setdiff(chosen, STANDARD_SAMPLING, 'stable');
kept = chosen(ismember(chosen, STANDARD_SAMPLING));
if isempty(kept)
    kept = "ioptimal";
end
if ~isempty(removedMethods)
    [~, position] = ismember(removedMethods, shotMethods);
    changes(end + 1) = "計測点の選び方：" + strjoin(names(position), "・") + "（通常版は I 最適・ランダム）";
end
sampling.unit = "shot";
sampling.method = kept;
if isfield(sampling, "layoutPlans")
    sampling.layoutPlans = strings(0, 1);   % Excel 取込の学習パターン（選んでいれば上の「Excel 取込」で知らせる）
end
if isfield(sampling, "layoutFile")
    sampling.layoutFile = "";
end
settings.sampling = sampling;
% Overlay 補正の成分（式を入力しない）
if isfield(settings, "overlay")
    overlay = settings.overlay;
    formulas = strings(1, 0);
    if isfield(overlay, "waferUseFormula") && logical(overlay.waferUseFormula)
        overlay.waferUseFormula = false;
        formulas(end + 1) = "Wafer 成分";
    end
    if isfield(overlay, "shotCommon") && string(overlay.shotCommon) == "formula"
        overlay.shotCommon = "none";
        formulas(end + 1) = "Shot 共通成分";
    end
    if isfield(overlay, "perShot") && string(overlay.perShot) == "formula"
        overlay.perShot = "linear";
        formulas(end + 1) = "Shot ごとの成分";
    end
    settings.overlay = overlay;
    if ~isempty(formulas)
        changes(end + 1) = "Overlay 補正の式：" + strjoin(formulas, "・") + "（通常版は組み込みの式）";
    end
end
end
