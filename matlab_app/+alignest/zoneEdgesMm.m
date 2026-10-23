function edges = zoneEdgesMm(sampling, waferRadiusMm)
%ZONEEDGESMM 同心円の制約の区切り [mm]（Shot 中心の半径。小さい順、0 より大きく Wafer 半径より小さい値だけ）。
%   edges = alignest.zoneEdgesMm(settings.sampling, settings.data.waferRadiusMm)
%   sampling.constraints.radialZoneEdgesMm を使う（以前の比の項目 radialZoneEdges だけなら 比 × Wafer 半径）。
%   区切りが無ければ空（1 × 0）。I 最適・ランダムの区画分け（alignest.planTrainingShots）と、Wafer マップの区切り線で使う。
edges = zeros(1, 0);
if ~isfield(sampling, "constraints")
    return
end
constraints = sampling.constraints;
if isfield(constraints, "radialZoneEdgesMm")
    values = double(constraints.radialZoneEdgesMm);
elseif isfield(constraints, "radialZoneEdges")
    values = double(constraints.radialZoneEdges) * waferRadiusMm;
else
    return
end
values = reshape(values(isfinite(values)), 1, []);
edges = unique(values(values > 0 & values < waferRadiusMm));
end
