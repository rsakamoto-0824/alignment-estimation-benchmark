function selected = poissonDiskSelect(pointsMm, nSelect, fixed, stream)
%POISSONDISKSELECT ポアソンディスクサンプリング：選んだ点どうしの距離が d 以上になるように、乱数の順で候補から点を選ぶ。
%   selected = alignest.poissonDiskSelect(pointsMm, nSelect, fixed, stream)
%   pointsMm：候補の位置 [x, y]（mm。行が候補）、nSelect：選ぶ数、fixed：必ず選ぶ候補（論理値。先に入れる）、
%   stream：乱数（RandStream）。selected：選んだ候補（pointsMm の行番号。必ず選ぶ候補、続けて選んだ順）。
%   選び方（ダーツ投げ）：候補を乱数で並べ、前から順に、選んだ点（必ず選ぶ候補を含む）すべてから d 以上離れていれば選ぶ。
%   d は、nSelect 個を選べる最も大きい値を二分法で探す（点が近づきすぎず、乱数のように偏りなく散らばる。乱数を変えると
%   別の配置になり、同じ乱数なら同じ配置）。必ず選ぶ候補どうしの距離は問わない。同心円などの制約は使わない。
arguments
    pointsMm (:, 2) double
    nSelect (1, 1) double {mustBeInteger, mustBeNonnegative}
    fixed logical = false(0, 1)
    stream = RandStream('mt19937ar', 'Seed', 0)
end
BISECTION_STEPS = 40;   % 二分法の回数（d を候補の広がりの 2^-40 まで詰める）
nPoints = size(pointsMm, 1);
fixed = reshape(fixed, [], 1);
if isempty(fixed)
    fixed = false(nPoints, 1);
end
if numel(fixed) ~= nPoints
    error('alignest:poissonDisk', '必ず選ぶ候補の数が候補の数と合いません。');
end
if nSelect > nPoints
    error('alignest:poissonDisk', '選ぶ数 %d が候補の数 %d より多いです。', nSelect, nPoints);
end
selected = find(fixed);
if numel(selected) >= nSelect
    return
end
order = find(~fixed);
order = order(randperm(stream, numel(order)));
lower = 0;   % d = 0 なら、すべての候補を選べる
upper = hypot(max(pointsMm(:, 1)) - min(pointsMm(:, 1)), max(pointsMm(:, 2)) - min(pointsMm(:, 2))) + 1;
best = dartThrow(pointsMm, selected, order, upper, nSelect);
if numel(best) < nSelect
    best = dartThrow(pointsMm, selected, order, lower, nSelect);
    for step = 1:BISECTION_STEPS
        middle = (lower + upper) / 2;
        chosen = dartThrow(pointsMm, selected, order, middle, nSelect);
        if numel(chosen) >= nSelect
            lower = middle;
            best = chosen;
        else
            upper = middle;
        end
    end
end
selected = best(1:nSelect);
end

function chosen = dartThrow(pointsMm, fixedIndex, order, distanceMm, nSelect)
% 必ず選ぶ候補を入れてから、order の順に、選んだ点すべてから distanceMm 以上離れた候補を足す（nSelect 個で止める）
chosen = zeros(nSelect, 1);
nChosen = numel(fixedIndex);
chosen(1:nChosen) = fixedIndex;
limit = distanceMm ^ 2;
for index = reshape(order, 1, [])
    if nChosen > 0
        gaps = (pointsMm(chosen(1:nChosen), 1) - pointsMm(index, 1)) .^ 2 + ...
            (pointsMm(chosen(1:nChosen), 2) - pointsMm(index, 2)) .^ 2;
        if min(gaps) < limit
            continue
        end
    end
    nChosen = nChosen + 1;
    chosen(nChosen) = index;
    if nChosen >= nSelect
        break
    end
end
chosen = chosen(1:nChosen);
end
