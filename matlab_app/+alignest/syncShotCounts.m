function sampling = syncShotCounts(sampling)
%SYNCSHOTCOUNTS 学習 Shot 数の並び（nShots）と、開始・終了・刻み（nShotsStart・nShotsEnd・nShotsStep）をそろえる。
%   開始・終了・刻みから作った並びが nShots と同じなら、そのまま返す。違う場合（以前の設定ファイル、または
%   nShots だけを変えた場合）は nShots を正とし、開始 = 最小、終了 = 最大、刻み = 間隔の最大公約数 にする。
%   nShots が等間隔でなければ、間の Shot 数が加わる（例：10 20 50 → 10 20 30 40 50）。
counts = unique(round(sampling.nShots(:).'));
fromSweep = [];
if all(isfield(sampling, ["nShotsStart", "nShotsEnd", "nShotsStep"]))
    try
        fromSweep = alignest.shotCountList(sampling.nShotsStart, sampling.nShotsEnd, sampling.nShotsStep);
    catch
        fromSweep = [];
    end
end
if isempty(counts)
    if isempty(fromSweep)
        error('alignest:nShots', '学習 Shot 数がありません。開始・終了・刻みを入れてください。');
    end
    sampling.nShots = fromSweep;
    return
end
if isequal(fromSweep, counts)
    sampling.nShots = counts;
    return
end
step = 1;
gaps = diff(counts);
if ~isempty(gaps)
    step = gaps(1);
    for gap = gaps(2:end)
        step = gcd(step, gap);
    end
end
sampling.nShotsStart = counts(1);
sampling.nShotsEnd = counts(end);
sampling.nShotsStep = step;
sampling.nShots = alignest.shotCountList(counts(1), counts(end), step);
end
