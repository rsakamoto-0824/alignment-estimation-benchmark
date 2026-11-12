function seconds = planSecondsGuide(unit, specs, sampling)
%PLANSECONDSGUIDE 1つの Wafer（配置の種類）で、学習パターンを作る時間の目安 [秒]（学習パターンごと）。
%   seconds = alignest.planSecondsGuide(unit, specs, sampling)   % seconds：1 × 学習パターンの数
%   交換法で解く学習パターンだけ時間がかかるので、それだけを数える（ランダム・Excel で指定は 0）。
%   - I 最適・D 最適（Shot 単位）：alignest.exchangeSecondsGuide（初期配置 1 つ・学習 Shot 1 つあたり約 0.01 秒）
%   - Mark 単位の I 最適・D 最適：SECONDS_PER_MARK_START × 計測する Mark の数 × 初期配置の数 ×
%     (候補の Mark の数 / REFERENCE_MARKS)。交換法は Shot ではなく Mark を1つずつ入れ替えるので、Shot 単位より長い。
%     係数は、同梱の模擬データ（候補 396 Mark・99 Shot、基準モデル XY 5次、反復の上限 300）を MATLAB R2022b（Apple M1 の
%     Mac）で測った値（2026-11-11。初期配置 4・Mark 100〜300 点で、初期配置 1 つ・Mark 1 点あたり 0.005〜0.02 秒、
%     中央の値で約 0.013 秒。各 Shot 1 点以上・Mark 番号の割合の制約あり）。PC の性能・データの大きさで変わる。
%   計測する Mark の数は、計測率なら 計測率 × 候補の Mark の数、数のスイープなら spec.markCount、それ以外は
%   1 Shot あたりの Mark 数 × 候補 Shot 数（alignest.planTrainingShots と同じ）。
arguments
    unit struct
    specs struct
    sampling struct
end
SECONDS_PER_MARK_START = 0.013;
REFERENCE_MARKS = 396;
shots = unit.shots;
candidateShots = find(shots.nValidX + shots.nValidY > 0);
nCandidateShots = numel(candidateShots);
marks = unit.marks;
nCandidateMarks = nnz(ismember(marks.shotIndex, candidateShots) & (marks.validX | marks.validY));
nStarts = sampling.exchangeStarts;
seconds = zeros(1, numel(specs));
for k = 1:numel(specs)
    spec = specs(k);
    hasRate = isfield(spec, "rate") && isfinite(spec.rate);
    switch spec.type
        case {"ioptimal", "doptimal"}
            nShots = spec.nShots;
            if hasRate
                nShots = max(1, round(spec.rate / 100 * nCandidateShots));
            end
            if nShots < nCandidateShots
                seconds(k) = alignest.exchangeSecondsGuide(nShots, nStarts, nCandidateShots);
            end
        case {"mark", "markd"}
            if hasRate
                nMarks = max(1, round(spec.rate / 100 * nCandidateMarks));
            elseif isfield(spec, "markCount") && isfinite(spec.markCount)
                nMarks = max(1, round(spec.markCount));
            else
                nMarks = max(1, round(spec.markPerShot * nCandidateShots));
            end
            if nMarks < nCandidateMarks
                seconds(k) = SECONDS_PER_MARK_START * nMarks * nStarts * nCandidateMarks / REFERENCE_MARKS;
            end
    end
end
end
