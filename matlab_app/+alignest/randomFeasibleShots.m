function [selected, violation] = randomFeasibleShots(nCandidates, nSelect, labels, slack, stream)
%RANDOMFEASIBLESHOTS 制約（各区分の Shot 数）を満たす組をランダムに選ぶ。制約が無ければ単純なランダム。
%   ランダムに選んでから、違反を増やさない入れ替えを繰り返す。満たせなければ違反の最も少ない組を返す。
%   I 最適の交換法の初期配置にも使う。selected は選んだ候補 Shot（論理ベクトル）。
MAX_TRIES = 5000;
bounds = alignest.shotGroupBounds(labels, nSelect, slack);
selected = false(nCandidates, 1);
selected(randperm(stream, nCandidates, nSelect)) = true;
violation = alignest.shotGroupViolation(selected, labels, bounds);
for trial = 1:MAX_TRIES
    if violation == 0
        break
    end
    inside = find(selected);
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
