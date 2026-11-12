function selection = measurementSelections(unit, sampling)
%MEASUREMENTSELECTIONS 計測マップで指定した Shot・Mark（必ず計測・計測しない）を、Wafer（unit）の番号に直す。
%   selection = alignest.measurementSelections(unit, sampling)
%   sampling.excludedShots（計測しない shotNo）・requiredMarks・excludedMarks（"shotNo-markNo" の文字。
%   alignest.parseMarkKeys）。必ず計測する Shot（sampling.requiredShots）は alignest.requiredShotIndex。
%   selection.excludedShots：計測しない Shot（unit.shots の何番目か）、selection.excludedMarks：計測しない Mark（unit.marks の
%   何番目か。計測しない Shot の Mark も含む）、selection.requiredMarks：必ず計測する Mark（計測しない Mark は除く）、
%   selection.missing：この Wafer に無い指定（"shot 12"・"12-3" の文字）
shots = unit.shots;
marks = unit.marks;
excludedNos = unique(double(fieldOr(sampling, "excludedShots", zeros(1, 0))));
[found, position] = ismember(excludedNos(:), shots.shotNo);
selection.excludedShots = position(found);
missing = "shot " + string(excludedNos(~found));
markKey = [marks.shotNo(:), marks.markNo(:)];
[selection.excludedMarks, missingExcluded] = markPositions(fieldOr(sampling, "excludedMarks", strings(1, 0)), markKey);
selection.excludedMarks = union(selection.excludedMarks, find(ismember(marks.shotIndex, selection.excludedShots)));
[selection.requiredMarks, missingRequired] = markPositions(fieldOr(sampling, "requiredMarks", strings(1, 0)), markKey);
selection.requiredMarks = setdiff(selection.requiredMarks, selection.excludedMarks);
selection.excludedMarks = selection.excludedMarks(:);
selection.requiredMarks = selection.requiredMarks(:);
selection.missing = [reshape(missing, 1, []), missingExcluded, missingRequired];
end

function [index, missing] = markPositions(texts, markKey)
% "shotNo-markNo" の指定を Mark の番号に（無い Mark は missing の文字）
keys = alignest.parseMarkKeys(texts);
[found, index] = ismember(keys, markKey, 'rows');
index = index(found);
missing = reshape(compose("%d-%d", keys(~found, 1), keys(~found, 2)), 1, []);
end

function value = fieldOr(s, name, fallback)
value = fallback;
if isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
end
end
