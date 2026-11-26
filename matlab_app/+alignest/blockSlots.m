function slots = blockSlots(blocks)
%BLOCKSLOTS 候補ごとの基底の行（行の数が違ってよい）を、行の番号ごとに並べ直す（alignest.blockSwapValues に渡す形）。
%   slots = alignest.blockSlots(blocks)
%   blocks{c}：候補 c の基底の行（行 × 項）。slots{i}：各候補の i 行目を並べた行列（候補 × 項）。行の数が i より少ない
%   候補は 0 の行（0 の行は情報行列に何も足さないので、基準は変わらない）。
nCandidates = numel(blocks);
nParams = size(blocks{1}, 2);
counts = cellfun(@(block) size(block, 1), blocks);
slots = cell(1, max([counts(:); 0]));
for i = 1:numel(slots)
    slots{i} = zeros(nCandidates, nParams);
    for c = find(counts(:).' >= i)
        slots{i}(c, :) = blocks{c}(i, :);
    end
end
end
