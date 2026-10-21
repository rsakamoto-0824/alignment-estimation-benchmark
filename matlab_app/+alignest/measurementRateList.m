function rates = measurementRateList(startRate, endRate, stepRate)
%MEASUREMENTRATELIST 計測率 [%] の並び。開始から終了まで刻みごと（終了が刻みに乗らなければ、その手前まで）。
%   rates = alignest.measurementRateList(10, 40, 10)   % 10, 20, 30, 40
%   計測率は候補 Shot（計測値のある Shot）に対する学習 Shot の割合。Wafer ごとに
%   round(計測率 / 100 × 候補 Shot 数) Shot（1 Shot 以上）を学習に使う（alignest.planTrainingShots）。
MAX_COUNTS = 100;     % 並びの数の上限（計算の回数が増えすぎないように）
DIGITS = 6;           % 0.1 のような刻みの足し算の誤差を丸める桁
values = [startRate, endRate, stepRate];
if numel(values) ~= 3 || any(~isfinite(values)) || any(values <= 0) || any(values(1:2) >= 100)
    error('alignest:measurementRate', '計測率の開始・終了は 0 より大きく 100 より小さい値、刻みは 0 より大きい値にしてください。');
end
if endRate < startRate
    error('alignest:measurementRate', '計測率の終了（%g%%）は開始（%g%%）以上にしてください。', endRate, startRate);
end
count = floor(round((endRate - startRate) / stepRate, DIGITS)) + 1;
if count > MAX_COUNTS
    error('alignest:measurementRate', '計測率が %d 通りになります（上限 %d 通り）。刻みを大きくしてください。', ...
        count, MAX_COUNTS);
end
rates = round(startRate + (0:count - 1) * stepRate, DIGITS);
end
