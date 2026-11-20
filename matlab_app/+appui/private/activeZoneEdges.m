function edges = activeZoneEdges(settings)
% 同心円の制約の区切り [mm]（半径の制約を使い、Excel で指定のほかの選び方を選んだときだけ。Excel で指定では制約を
% 使わないので空）
edges = zeros(1, 0);
if any(~ismember(string(settings.sampling.method), ["excel", "manual", "file"]))
    edges = alignest.zoneEdgesMm(settings.sampling, settings.data.waferRadiusMm);
end
end
