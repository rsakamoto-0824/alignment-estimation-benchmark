function bounds = shotGroupBounds(labels, nSelect, slack, equal)
%SHOTGROUPBOUNDS 制約の区分ごとの Shot 数の下限・上限：全候補に占める割合 × 選ぶ数 を中心に ±slack。
%   bounds = alignest.shotGroupBounds(labels, nSelect, slack)
%   bounds = alignest.shotGroupBounds(labels, nSelect, slack, equal)
%   labels は 候補 Shot × 制約の種類 の区分番号（1始まり）。bounds(p).lower / upper は区分ごとの列ベクトル。
%   equal（制約の種類ごとの論理値、省略時はすべて false）が true の種類は、割合ではなく区分ごとの数をできるだけ均等に
%   する（選ぶ数 / 区分の数。候補がそれより少ない区分はその数まで選び、残りを残りの区分で均等に分ける）。均等の種類には
%   slack を使わず、割り切れないときの1つの差だけを許す（Mark 単位の計画の「Mark 番号ごとの数を均等にする」）。
if nargin < 4 || isempty(equal)
    equal = false(1, size(labels, 2));
end
nCandidates = size(labels, 1);
bounds = struct("lower", {}, "upper", {});
for p = 1:size(labels, 2)
    sizes = accumarray(labels(:, p), 1);
    if equal(p)
        target = alignest.equalTargets(sizes, nSelect);
        bounds(p).lower = floor(target + 1e-9);
        bounds(p).upper = min(sizes, ceil(target - 1e-9));
        continue
    end
    target = nSelect * sizes / nCandidates;
    bounds(p).lower = max(0, floor(target) - slack);
    bounds(p).upper = min(sizes, ceil(target) + slack);
end
end
