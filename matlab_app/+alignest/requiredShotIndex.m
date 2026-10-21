function [index, details] = requiredShotIndex(shots, candidates, sampling)
%REQUIREDSHOTINDEX 必ず計測する Shot（I 最適・ランダムで学習に必ず入れる Shot）の番号（shots の何番目か）。
%   [index, details] = alignest.requiredShotIndex(unit.shots, candidates, sampling)
%   sampling.requiredShots（指定した shotNo）と、sampling.requireOuterShots が true なら最外周の Shot
%   （alignest.outerShots）を合わせる。計測値の無い Shot（candidates に無い）は入れない。
%   details.specified・details.outer：指定・最外周から入れた Shot、details.missingNos：この Wafer に無い、
%   または計測値の無い指定の shotNo。
specifiedNos = zeros(0, 1);
if isfield(sampling, "requiredShots")
    specifiedNos = unique(sampling.requiredShots(:));
end
[found, position] = ismember(specifiedNos, shots.shotNo);
usable = found;
usable(found) = ismember(position(found), candidates);
details.specified = position(usable);
details.missingNos = specifiedNos(~usable);
details.outer = zeros(0, 1);
if isfield(sampling, "requireOuterShots") && sampling.requireOuterShots
    details.outer = intersect(find(alignest.outerShots(shots)), candidates);
end
index = union(details.specified, details.outer);
index = index(:);
end
