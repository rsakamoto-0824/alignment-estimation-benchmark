classdef GroupQuota
    %GROUPQUOTA 制約の区分（同心円・象限・Scan 方向）ごとの数の下限・上限と、選んだ数。
    %   Sobol 列・ポアソンディスク（alignest.sobolSelect・poissonDiskSelect）で、区分ごとの数をそろえるのに使う。
    %   quota = alignest.GroupQuota(labels, nSelect, slack, fixed)
    %   labels：候補 × 制約の種類 の区分番号（0 列なら制約なし）、nSelect：選ぶ数、slack：許容幅、fixed：先に選んだ候補
    %   （論理値）。下限・上限は 全候補に占める割合 × 選ぶ数 ∓ slack（alignest.shotGroupBounds。I 最適・ランダムと同じ）。
    %   quota.fits(c, slotsAfter)：候補 c を足しても上限を超えず、足した後に残る選ぶ数 slotsAfter で下限に届くか（下限に
    %   足りない区分の不足の合計が slotsAfter 以下か。制約の種類ごとに確かめる）、quota.fitsAll(slotsAfter)：候補ごとの
    %   fits、quota = quota.add(c)：c を選んだことにする、quota.violation()：区分ごとの数が下限・上限から外れた数の合計。

    properties (SetAccess = private)
        Labels   % 候補 × 制約の種類 の区分番号（1, 2, … に詰めたもの）
        Lower    % 制約の種類ごとの、区分ごとの下限（cell）
        Upper    % 制約の種類ごとの、区分ごとの上限（cell）
        Counts   % 制約の種類ごとの、区分ごとの選んだ数（cell）
    end

    methods
        function quota = GroupQuota(labels, nSelect, slack, fixed)
            fixed = reshape(logical(fixed), [], 1);
            nCandidates = numel(fixed);
            if isempty(labels)
                labels = zeros(nCandidates, 0);
            end
            if size(labels, 1) ~= nCandidates
                error('alignest:groupQuota', '制約の区分の数が候補の数と合いません。');
            end
            for p = 1:size(labels, 2)
                [~, ~, labels(:, p)] = unique(labels(:, p));
            end
            quota.Labels = labels;
            bounds = alignest.shotGroupBounds(labels, nSelect, slack);
            nTypes = size(labels, 2);
            [quota.Lower, quota.Upper, quota.Counts] = deal(cell(1, nTypes));
            for p = 1:nTypes
                quota.Lower{p} = bounds(p).lower;
                quota.Upper{p} = bounds(p).upper;
                quota.Counts{p} = accumarray(labels(fixed, p), 1, [numel(bounds(p).lower), 1]);
            end
        end

        function yes = fits(quota, index, slotsAfter)
            % 候補 index を足しても、どの区分も上限を超えず、残りの slotsAfter 個で下限に届くか
            yes = true;
            for p = 1:numel(quota.Counts)
                group = quota.Labels(index, p);
                counts = quota.Counts{p};
                if counts(group) >= quota.Upper{p}(group)
                    yes = false;
                    return
                end
                counts(group) = counts(group) + 1;
                if sum(max(0, quota.Lower{p} - counts)) > slotsAfter
                    yes = false;
                    return
                end
            end
        end

        function mask = fitsAll(quota, slotsAfter)
            % 候補ごとの fits（列ベクトル）
            mask = true(size(quota.Labels, 1), 1);
            for p = 1:numel(quota.Counts)
                groups = quota.Labels(:, p);
                counts = quota.Counts{p};
                deficit = sum(max(0, quota.Lower{p} - counts));
                reduces = counts(groups) < quota.Lower{p}(groups);   % 足すと不足が1つ減る区分の候補
                mask = mask & counts(groups) < quota.Upper{p}(groups) & deficit - reduces <= slotsAfter;
            end
        end

        function quota = add(quota, index)
            % 候補 index を選んだことにする
            for p = 1:numel(quota.Counts)
                group = quota.Labels(index, p);
                quota.Counts{p}(group) = quota.Counts{p}(group) + 1;
            end
        end

        function value = violation(quota)
            % 区分ごとの数が下限より少ない分と上限より多い分の合計
            value = 0;
            for p = 1:numel(quota.Counts)
                value = value + sum(max(0, quota.Lower{p} - quota.Counts{p}) + max(0, quota.Counts{p} - quota.Upper{p}));
            end
        end
    end
end
