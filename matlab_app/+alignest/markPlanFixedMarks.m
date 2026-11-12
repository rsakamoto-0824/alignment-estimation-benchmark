function [fixedMarks, details] = markPlanFixedMarks(unit, sampling)
%MARKPLANFIXEDMARKS Mark 単位の I 最適・D 最適で必ず計測する Mark（unit.marks の何番目か。列ベクトル）。
%   [fixedMarks, details] = alignest.markPlanFixedMarks(unit, sampling)
%   次の Mark を合わせる（計測しない Shot・Mark（alignest.measurementSelections）は除く）：
%   - Wafer 中心に最も近い Mark（計測しない Mark を除いた候補から1つ）
%   - 必ず計測する Mark（sampling.requiredMarks。"shotNo-markNo"）
%   - 必ず計測する Shot（alignest.requiredShotIndex：指定した shotNo と、最外周を必ず計測するなら最外周の Shot）の
%     Mark すべて（Shot 単位の計画で Shot を計測するのと同じ意味）
%   候補の Mark は、X か Y の値がある Shot（候補 Shot）の、X か Y の値がある Mark。
%   details.center：Wafer 中心に最も近い Mark、details.requiredShots：必ず計測する Shot（unit.shots の何番目か。
%   計測しない Shot を除く）、details.missingShotNos：この Wafer に無い、または値の無い必ず計測する shotNo、
%   details.selection：alignest.measurementSelections の結果
arguments
    unit struct
    sampling struct
end
shots = unit.shots;
marks = unit.marks;
candidateShots = find(shots.nValidX + shots.nValidY > 0);
selection = alignest.measurementSelections(unit, sampling);
isCandidate = ismember(marks.shotIndex, candidateShots) & (marks.validX | marks.validY);
isCandidate(selection.excludedMarks) = false;
candidates = find(isCandidate);
[requiredShots, required] = alignest.requiredShotIndex(shots, candidateShots, sampling);
requiredShots = setdiff(requiredShots, selection.excludedShots);
details = struct("center", zeros(0, 1), "requiredShots", requiredShots(:), "missingShotNos", required.missingNos(:), ...
    "selection", selection);
fixedMarks = zeros(0, 1);
if isempty(candidates)
    return
end
[~, nearest] = min(hypot(marks.x(candidates), marks.y(candidates)));
details.center = candidates(nearest);
fromShots = candidates(ismember(marks.shotIndex(candidates), requiredShots));
fixedMarks = union(union(details.center, intersect(selection.requiredMarks, candidates)), fromShots);
fixedMarks = fixedMarks(:);
end
