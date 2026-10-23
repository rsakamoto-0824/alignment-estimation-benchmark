function settings = upgradeRadiusSettings(settings)
%UPGRADERADIUSSETTINGS 以前の設定の「Wafer 半径に対する比」を、mm の絶対値の項目に直す。
%   settings = alignest.upgradeRadiusSettings(settings)
%   同心円の区切り sampling.constraints.radialZoneEdges（比）→ radialZoneEdgesMm [mm]、
%   外周とみなす半径 evaluation.outerRadiusRatio（比）→ outerRadiusMm [mm]。
%   mm の項目が無いときだけ、比 × Wafer 半径（data.waferRadiusMm。無ければ 150 mm）で作る。比の項目は消す。
%   設定ファイル・評価結果の Excel の「設定」シート（alignest.loadSettings）と、画面に渡す設定（setSettings）で使う。
DEFAULT_RADIUS_MM = 150;
if ~isstruct(settings)
    return
end
radiusMm = DEFAULT_RADIUS_MM;
if isfield(settings, "data") && isstruct(settings.data) && isfield(settings.data, "waferRadiusMm")
    radiusMm = double(settings.data.waferRadiusMm);
end
if isfield(settings, "sampling") && isstruct(settings.sampling) && isfield(settings.sampling, "constraints") && ...
        isstruct(settings.sampling.constraints)
    constraints = settings.sampling.constraints;
    if isfield(constraints, "radialZoneEdges")
        if ~isfield(constraints, "radialZoneEdgesMm")
            constraints.radialZoneEdgesMm = reshape(double(constraints.radialZoneEdges), 1, []) * radiusMm;
        end
        constraints = rmfield(constraints, "radialZoneEdges");
    end
    settings.sampling.constraints = constraints;
end
if isfield(settings, "evaluation") && isstruct(settings.evaluation) && isfield(settings.evaluation, "outerRadiusRatio")
    if ~isfield(settings.evaluation, "outerRadiusMm")
        settings.evaluation.outerRadiusMm = double(settings.evaluation.outerRadiusRatio) * radiusMm;
    end
    settings.evaluation = rmfield(settings.evaluation, "outerRadiusRatio");
end
end
