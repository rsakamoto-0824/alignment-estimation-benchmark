function edges = activeZoneEdges(settings)
% 同心円の制約の区切り [mm]（I 最適・D 最適・ランダムと Mark 単位の I 最適・D 最適で使うときだけ。Excel で指定では制約を
% 使わないので空）
edges = zeros(1, 0);
if any(ismember(string(settings.sampling.method), ["ioptimal", "doptimal", "random", "mark", "markd"]))
    edges = alignest.zoneEdgesMm(settings.sampling, settings.data.waferRadiusMm);
end
end
