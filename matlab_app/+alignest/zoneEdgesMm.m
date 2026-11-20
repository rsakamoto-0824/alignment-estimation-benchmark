function edges = zoneEdgesMm(sampling, waferRadiusMm)
%ZONEEDGESMM 同心円の制約の区切り [mm]（Wafer 中心からの半径。Shot 単位の計画は Shot 中心、Mark 単位の計画は Mark の
%   半径で区画に分ける。小さい順、0 より大きく Wafer 半径より小さい値だけ）。
%   edges = alignest.zoneEdgesMm(settings.sampling, settings.data.waferRadiusMm)
%   sampling.constraints.radialZoneEdgesMm を使う（以前の比の項目 radialZoneEdges だけなら 比 × Wafer 半径）。
%   区切りが無い、または半径の制約を使わない（sampling.constraints.radialZones が false）ときは空（1 × 0）。
%   計測点の選び方の区画分け（alignest.planTrainingShots）と、Wafer マップの区切り線で使う。
edges = zeros(1, 0);
if ~isfield(sampling, "constraints")
    return
end
constraints = sampling.constraints;
if isfield(constraints, "radialZones") && ~logical(constraints.radialZones)
    return
end
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
