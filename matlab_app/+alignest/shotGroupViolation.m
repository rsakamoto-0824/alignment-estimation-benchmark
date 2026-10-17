function total = shotGroupViolation(selected, labels, bounds)
%SHOTGROUPVIOLATION 制約の違反量（下限に足りない Shot 数 ＋ 上限を超えた Shot 数 の合計）。0 なら制約を満たす。
%   selected は選んだ候補 Shot（論理ベクトル）。
total = 0;
for p = 1:numel(bounds)
    counts = accumarray(labels(selected, p), 1, [numel(bounds(p).lower), 1]);
    total = total + sum(max(0, bounds(p).lower - counts) + max(0, counts - bounds(p).upper));
end
end
