function edges = activeZoneEdges(settings)
% 同心円の制約の区切り [mm]（I 最適・ランダムで使うときだけ。手動・ファイルの優先順では制約を使わないので空）
edges = zeros(1, 0);
if any(ismember(string(settings.sampling.method), ["ioptimal", "doptimal", "random"]))
    edges = alignest.zoneEdgesMm(settings.sampling, settings.data.waferRadiusMm);
end
end
