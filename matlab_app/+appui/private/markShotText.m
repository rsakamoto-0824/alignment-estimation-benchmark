function text = markShotText(unit, plan, nCandidates)
% Mark 単位の計画で計測する Shot の数と、Shot あたりの最も少ない計測 Mark 数（例：「全 99 Shot で1点以上」）
counts = accumarray(unit.marks.shotIndex(plan.markIndex), 1, [numel(unit.shots.shotNo), 1]);
measured = nnz(counts > 0);
if measured >= nCandidates
    text = sprintf("全 %d Shot で%d点以上", measured, min(counts(counts > 0)));
else
    text = sprintf("%d / %d Shot を計測", measured, nCandidates);
end
end
