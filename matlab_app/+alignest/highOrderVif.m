function [terms, info] = highOrderVif(terms, local, valid, threshold)
%HIGHORDERVIF Shot 高次補正の式の項の VIF（分散拡大係数）を求め、しきい値で外す項（k パラメータ）を選ぶ。
%   [terms, info] = alignest.highOrderVif(terms, local, valid, threshold)
%   terms：alignest.highOrderTerms の表。local：点ごとの Shot 内の座標 [mm]（点の数 × 2）。valid：点ごとに dx・dy の値が
%   あるか（点の数 × 2。dx の式の項は1列目が true の点、dy の式の項は2列目が true の点で求める）。
%   threshold：「VIF で選ぶ」のしきい値（省略・NaN なら選ばない）。
%   terms に列を足して返す：
%   - vifAll：式のすべての項で求めた VIF
%   - vifUsed：使う項（terms.used）だけで求めた VIF（使わない項は NaN）
%   - vifRemoved：しきい値で選ぶと外れる項の、外す直前の VIF（外れない項は NaN）。removalOrder：外す順番（外れない項は NaN）
%   info.suggestedExcluded：しきい値で選んだときに外す k の番号、info.points：VIF に使った点の数（dx・dy）、
%   info.positions：そのうち Shot 内の位置の数（同じ位置の点は1つにまとめ、点の数を重みにする）。
%   選び方（high-order-correction-report の reduce_terms_by_vif と同じ）：VIF がしきい値以上の高次項があれば、その中で
%   次数の最も高い項（同じ次数なら VIF の最も大きい項）を外し、VIF を求め直す。しきい値以上が1次の項だけなら、高次項の中で
%   VIF の最も大きい項を外す（1次の項と似た高次項）。VIF の最も大きい項を単純に外すと、y^3 を外して y^6 を残すような
%   選び方になるため、低い次数の項を残す（多項式の階層を保つ）。k1〜k6（定数・1次）は外さない。
%   VIF は Shot 内の座標だけで決まり、値（計測値・推定値）には依らない。
arguments
    terms table
    local double
    valid logical
    threshold double = NaN
end
POSITION_DIGITS = 4;   % 同じ位置とみなす Shot 内の座標の桁（mm の小数点以下。0.1 µm）
axisNames = ["dx", "dy"];
n = height(terms);
[terms.vifAll, terms.vifUsed, terms.vifRemoved, terms.removalOrder] = deal(nan(n, 1));
info = struct("suggestedExcluded", zeros(1, 0), "points", [0, 0], "positions", [0, 0]);
for a = 1:2
    rows = find(terms.axis == axisNames(a));
    use = valid(:, a) & all(isfinite(local), 2);
    info.points(a) = nnz(use);
    if ~any(use)
        continue
    end
    [positions, ~, group] = unique(round(local(use, :), POSITION_DIGITS), 'rows');
    weights = accumarray(group, 1);
    info.positions(a) = size(positions, 1);
    powers = [terms.xPower(rows), terms.yPower(rows)];
    A = positions(:, 1) .^ (powers(:, 1).') .* positions(:, 2) .^ (powers(:, 2).');
    isIntercept = terms.order(rows) == 0;
    terms.vifAll(rows) = alignest.varianceInflation(A, isIntercept, weights);
    usedRows = terms.used(rows);
    terms.vifUsed(rows(usedRows)) = alignest.varianceInflation(A(:, usedRows), isIntercept(usedRows), weights);
    if isfinite(threshold)
        removal = reduceByVif(A, terms.order(rows), weights, threshold);
        terms.vifRemoved(rows(removal(:, 1))) = removal(:, 2);
        terms.removalOrder(rows(removal(:, 1))) = (1:size(removal, 1)).';
        info.suggestedExcluded = [info.suggestedExcluded, reshape(terms.k(rows(removal(:, 1))), 1, [])];
    end
end
end

function removal = reduceByVif(A, order, weights, threshold)
% すべての項の VIF がしきい値より小さくなるまで高次項を1つずつ外す。removal は [外した列, 外す直前の VIF]（外した順）
keep = true(numel(order), 1);
isProtected = order <= 1;
removal = zeros(0, 2);
while true
    kept = find(keep);
    vif = alignest.varianceInflation(A(:, kept), order(kept) == 0, weights);
    if ~(max(vif, [], 'omitnan') >= threshold)
        break
    end
    removable = vif;
    removable(isProtected(kept)) = -Inf;
    over = removable >= threshold;
    if any(over)
        candidate = find(over);
        candidateOrder = order(kept(candidate));
        candidate = candidate(candidateOrder == max(candidateOrder));
        [largest, best] = max(removable(candidate));
        position = candidate(best);
    else
        [largest, position] = max(removable);
    end
    if ~(largest > -Inf)
        break   % 外せる高次項が残っていない（1次の項どうしが似ている）
    end
    removal(end + 1, :) = [kept(position), largest]; %#ok<AGROW>
    keep(kept(position)) = false;
end
end
