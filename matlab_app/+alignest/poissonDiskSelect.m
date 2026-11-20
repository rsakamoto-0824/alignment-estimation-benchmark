function [selected, violation] = poissonDiskSelect(pointsMm, nSelect, fixed, stream, options)
%POISSONDISKSELECT ポアソンディスクサンプリング：選んだ点どうしの距離が d 以上になるように、乱数の順で候補から点を選ぶ。
%   selected = alignest.poissonDiskSelect(pointsMm, nSelect, fixed, stream)
%   [selected, violation] = alignest.poissonDiskSelect(..., labels=区分番号, slack=1)
%   pointsMm：候補の位置 [x, y]（mm。行が候補）、nSelect：選ぶ数、fixed：必ず選ぶ候補（論理値。先に入れる）、
%   stream：乱数（RandStream）。selected：選んだ候補（pointsMm の行番号。必ず選ぶ候補、続けて選んだ順）。
%   選び方（ダーツ投げ）：候補を乱数で並べ、前から順に、選んだ点（必ず選ぶ候補を含む）すべてから d 以上離れていれば選ぶ。
%   d は、nSelect 個を選べる最も大きい値を二分法で探す（点が近づきすぎず、乱数のように偏りなく散らばる。乱数を変えると
%   別の配置になり、同じ乱数なら同じ配置）。必ず選ぶ候補どうしの距離は問わない。
%   制約（labels：候補 × 制約の種類 の区分番号。同心円・象限・Scan 方向。0 列なら使わない）：区分ごとの数の上限
%   （全候補に占める割合 × 選ぶ数 + slack。alignest.GroupQuota）を超える候補と、選ぶと残りの数で下限に届かなくなる候補は
%   選ばない（d = 0 でも足りなければ、乱数の順に制約を超えて足す）。violation：区分ごとの数が下限・上限から外れた数の合計（制約つきランダムと同じ数え方）。
arguments
    pointsMm (:, 2) double
    nSelect (1, 1) double {mustBeInteger, mustBeNonnegative}
    fixed logical = false(0, 1)
    stream = RandStream('mt19937ar', 'Seed', 0)
    options.labels double = zeros(0, 0)
    options.slack (1, 1) double = 1
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
quota = alignest.GroupQuota(options.labels, nSelect, options.slack, fixed);
selected = find(fixed);
if numel(selected) >= nSelect
    violation = quota.violation();
    return
end
order = find(~fixed);
order = order(randperm(stream, numel(order)));
lower = 0;   % d = 0 なら、距離によらず制約の中で選べる
upper = hypot(max(pointsMm(:, 1)) - min(pointsMm(:, 1)), max(pointsMm(:, 2)) - min(pointsMm(:, 2))) + 1;
[best, bestQuota] = dartThrow(pointsMm, selected, order, upper, nSelect, quota);
if numel(best) < nSelect
    [best, bestQuota] = dartThrow(pointsMm, selected, order, lower, nSelect, quota);
    if numel(best) >= nSelect
        for step = 1:BISECTION_STEPS
            middle = (lower + upper) / 2;
            [chosen, chosenQuota] = dartThrow(pointsMm, selected, order, middle, nSelect, quota);
            if numel(chosen) >= nSelect
                lower = middle;
                best = chosen;
                bestQuota = chosenQuota;
            else
                upper = middle;
            end
        end
    else
        % 制約の中では足りない：乱数の順に、まだ選んでいない候補を制約を超えて足す
        for index = reshape(order(~ismember(order, best)), 1, [])
            best(end + 1, 1) = index; %#ok<AGROW>
            bestQuota = bestQuota.add(index);
            if numel(best) >= nSelect
                break
            end
        end
    end
end
selected = best(1:nSelect);
violation = bestQuota.violation();
end

function [chosen, quota] = dartThrow(pointsMm, fixedIndex, order, distanceMm, nSelect, quota)
% 必ず選ぶ候補を入れてから、order の順に、選んだ点すべてから distanceMm 以上離れ、区分の上限を超えない候補を足す
% （nSelect 個で止める）
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
    if ~quota.fits(index, nSelect - nChosen - 1)
        continue
    end
    nChosen = nChosen + 1;
    chosen(nChosen) = index;
    quota = quota.add(index);
    if nChosen >= nSelect
        break
    end
end
chosen = chosen(1:nChosen);
end
