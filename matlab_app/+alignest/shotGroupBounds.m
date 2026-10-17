function bounds = shotGroupBounds(labels, nSelect, slack)
%SHOTGROUPBOUNDS 制約の区分ごとの Shot 数の下限・上限：全候補に占める割合 × 選ぶ数 を中心に ±slack。
%   labels は 候補 Shot × 制約の種類 の区分番号（1始まり）。bounds(p).lower / upper は区分ごとの列ベクトル。
nCandidates = size(labels, 1);
bounds = struct("lower", {}, "upper", {});
for p = 1:size(labels, 2)
    sizes = accumarray(labels(:, p), 1);
    target = nSelect * sizes / nCandidates;
    bounds(p).lower = max(0, floor(target) - slack);
    bounds(p).upper = min(sizes, ceil(target) + slack);
end
end
