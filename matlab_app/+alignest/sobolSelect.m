function [selected, violation] = sobolSelect(pointsMm, nSelect, fixed, waferRadiusMm, options)
%SOBOLSELECT Sobol 列の点に近い候補（Shot 中心・Mark の位置）を選ぶ（Wafer 上に偏りなく散らばる計測配置。最適化はしない）。
%   selected = alignest.sobolSelect(pointsMm, nSelect, fixed, waferRadiusMm)
%   [selected, violation] = alignest.sobolSelect(..., labels=区分番号, slack=1)
%   pointsMm：候補の位置 [x, y]（mm。行が候補）、nSelect：選ぶ数、fixed：必ず選ぶ候補（論理値。先に入れる）、
%   waferRadiusMm：Wafer の半径。selected：選んだ候補（pointsMm の行番号。選んだ順）。
%   選び方：Sobol 列（alignest.sobolSequence）の点を Wafer を囲む正方形 [−R, R]² に置き、Wafer の外の点は飛ばす。
%   前の点から順に、点に最も近い候補（すべての候補の中で）がまだ選ばれていなければ選ぶ（選ばれていれば、その点は飛ばす。
%   同じ場所に集まらないように）。点を MAX_POINTS_PER_CANDIDATE × 候補の数まで使っても足りなければ、残りは点に最も近い
%   まだ選んでいない候補を選ぶ。乱数は使わないので、同じ候補の配置なら同じ候補を選ぶ。
%   制約（labels：候補 × 制約の種類 の区分番号。同心円・象限・Scan 方向。0 列なら使わない）：区分ごとの数の上限
%   （全候補に占める割合 × 選ぶ数 + slack。alignest.GroupQuota）を超える候補と、選ぶと残りの数で下限に届かなくなる候補は
%   選ばない（それで足りなければ、最後に制約を超えて足す）。violation：区分ごとの数が下限・上限から外れた数の合計（制約つきランダムと同じ数え方）。
arguments
    pointsMm (:, 2) double
    nSelect (1, 1) double {mustBeInteger, mustBeNonnegative}
    fixed logical = false(0, 1)
    waferRadiusMm (1, 1) double {mustBePositive} = 150
    options.labels double = zeros(0, 0)
    options.slack (1, 1) double = 1
end
MAX_POINTS_PER_CANDIDATE = 64;   % 点に近い候補が選ばれてばかりのとき、点を使い切るまでの目安（候補の数の何倍か）
nCandidates = size(pointsMm, 1);
fixed = reshape(fixed, [], 1);
if isempty(fixed)
    fixed = false(nCandidates, 1);
end
if numel(fixed) ~= nCandidates
    error('alignest:sobolSelect', '必ず選ぶ候補の数が候補の数と合いません。');
end
if nSelect > nCandidates
    error('alignest:sobolSelect', '選ぶ数 %d が候補の数 %d より多いです。', nSelect, nCandidates);
end
quota = alignest.GroupQuota(options.labels, nSelect, options.slack, fixed);
selected = find(fixed);
if numel(selected) < nSelect
    points = (2 * alignest.sobolSequence(MAX_POINTS_PER_CANDIDATE * nCandidates) - 1) * waferRadiusMm;
    points = points(hypot(points(:, 1), points(:, 2)) < waferRadiusMm, :);   % Wafer の中の点だけ
    chosen = fixed;
    for p = 1:size(points, 1)
        [~, nearest] = min((pointsMm(:, 1) - points(p, 1)) .^ 2 + (pointsMm(:, 2) - points(p, 2)) .^ 2);
        if ~chosen(nearest) && quota.fits(nearest, nSelect - numel(selected) - 1)
            [chosen, selected, quota] = take(chosen, selected, quota, nearest);
            if numel(selected) >= nSelect
                break
            end
        end
    end
    % 足りなければ、点の順に、点に最も近いまだ選んでいない候補（まず上限の中、それでも足りなければ上限を超えて）
    for ignoreQuota = [false, true]
        for p = 1:size(points, 1)
            if numel(selected) >= nSelect
                break
            end
            remaining = find(~chosen & (ignoreQuota | quota.fitsAll(nSelect - numel(selected) - 1)));
            if isempty(remaining)
                break
            end
            [~, nearest] = min((pointsMm(remaining, 1) - points(p, 1)) .^ 2 + (pointsMm(remaining, 2) - points(p, 2)) .^ 2);
            [chosen, selected, quota] = take(chosen, selected, quota, remaining(nearest));
        end
    end
end
violation = quota.violation();
end

function [chosen, selected, quota] = take(chosen, selected, quota, index)
chosen(index) = true;
selected(end + 1, 1) = index;
quota = quota.add(index);
end
