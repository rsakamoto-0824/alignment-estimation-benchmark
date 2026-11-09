function target = equalTargets(sizes, nSelect)
%EQUALTARGETS 区分ごとに選ぶ数を、できるだけ均等に決める（小数のまま）。候補の数（sizes）が均等の数より少ない区分は
%   その数まで選び、残りを残りの区分で均等に分ける（水位を決めるように、少ない区分から順に）。
%   target = alignest.equalTargets(sizes, nSelect)
%   sizes：区分ごとの候補の数（列ベクトル）、nSelect：選ぶ数。sum(target) = min(nSelect, sum(sizes))。
%   例：sizes = [30; 30; 30; 10]、nSelect = 100 → [30; 30; 30; 10]、nSelect = 60 → [16.67; 16.67; 16.67; 10]
target = zeros(size(sizes));
remaining = min(nSelect, sum(sizes));
open = sizes > 0;
while any(open)
    level = remaining / nnz(open);
    filled = open & sizes <= level;
    if ~any(filled)
        target(open) = level;
        break
    end
    target(filled) = sizes(filled);   % 候補の少ない区分は全部
    remaining = remaining - sum(sizes(filled));
    open(filled) = false;
end
end
