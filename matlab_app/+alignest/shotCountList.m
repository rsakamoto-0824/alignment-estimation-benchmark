function counts = shotCountList(startCount, endCount, stepCount)
%SHOTCOUNTLIST 学習 Shot 数の並び。開始から終了まで刻みごと（終了が刻みに乗らなければ、その手前まで）。
%   counts = alignest.shotCountList(10, 40, 5)   % 10, 15, 20, 25, 30, 35, 40
MAX_COUNTS = 100;  % 並びの数の上限（計算の回数が増えすぎないように）
values = [startCount, endCount, stepCount];
if numel(values) ~= 3 || any(~isfinite(values)) || any(values < 1) || any(values ~= round(values))
    error('alignest:nShots', '学習 Shot 数の開始・終了・刻みは、それぞれ 1 以上の整数にしてください。');
end
if endCount < startCount
    error('alignest:nShots', '学習 Shot 数の終了（%d）は開始（%d）以上にしてください。', endCount, startCount);
end
counts = startCount:stepCount:endCount;
if numel(counts) > MAX_COUNTS
    error('alignest:nShots', '学習 Shot 数が %d 通りになります（上限 %d 通り）。刻みを大きくしてください。', ...
        numel(counts), MAX_COUNTS);
end
end
