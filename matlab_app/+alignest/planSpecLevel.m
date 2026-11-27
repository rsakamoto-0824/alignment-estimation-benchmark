function level = planSpecLevel(spec)
%PLANSPECLEVEL 学習パターンの仕様（alignest.buildPlanSpecs の1つ）が Shot を選ぶか Mark を選ぶか："shot"・"mark"。
%   level = alignest.planSpecLevel(spec)
%   Mark 単位の選び方（alignest.markPlanTypes）と、Excel 取込で markNo の列がある指定は "mark"、ほかは "shot"。
markLevel = ismember(spec.type, alignest.markPlanTypes()) || ...
    (any(spec.type == ["manual", "file"]) && isfield(spec, "markNos") && ~isempty(spec.markNos));
level = "shot";
if markLevel
    level = "mark";
end
end
