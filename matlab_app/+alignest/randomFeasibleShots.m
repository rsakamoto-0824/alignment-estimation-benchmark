function [selected, violation] = randomFeasibleShots(nCandidates, nSelect, labels, slack, stream, fixed, equal)
%RANDOMFEASIBLESHOTS 制約（各区分の Shot 数）を満たす組をランダムに選ぶ。制約が無ければ単純なランダム。
%   ランダムに選んでから、違反を増やさない入れ替えを繰り返す。満たせなければ違反の最も少ない組を返す。
%   I 最適の交換法の初期配置にも使う。selected は選んだ候補 Shot（論理ベクトル）。
%   fixed（候補 Shot の論理ベクトル、省略可）の Shot は必ず選び、入れ替えない（必ず計測する Shot）。
%   fixed の数は nSelect より少ないこと。equal（制約の種類ごとの論理値、省略可）は alignest.shotGroupBounds と同じ
%   （true の種類は区分ごとの数を均等にする）。
MAX_TRIES = 5000;
if nargin < 6 || isempty(fixed)
    fixed = false(nCandidates, 1);
end
fixed = fixed(:);
if nargin < 7
    equal = [];
end
bounds = alignest.shotGroupBounds(labels, nSelect, slack, equal);
selected = fixed;
free = find(~fixed);
selected(free(randperm(stream, numel(free), nSelect - nnz(fixed)))) = true;
violation = alignest.shotGroupViolation(selected, labels, bounds);
for trial = 1:MAX_TRIES
    if violation == 0
        break
    end
    inside = find(selected & ~fixed);
    outside = find(~selected);
    candidate = selected;
    candidate(inside(randi(stream, numel(inside)))) = false;
    candidate(outside(randi(stream, numel(outside)))) = true;
    candidateViolation = alignest.shotGroupViolation(candidate, labels, bounds);
    if candidateViolation <= violation
        selected = candidate;
        violation = candidateViolation;
    end
end
end
