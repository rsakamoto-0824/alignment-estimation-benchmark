function [mask, text, active] = pointFilterMask(filter, points)
%POINTFILTERMASK 評価点の絞り込みの条件に合う点（論理ベクトル）と、条件の説明。
%   [mask, text, active] = alignest.pointFilterMask(filter, points)
%   filter は alignest.defaultPointFilter と同じ形。points は点ごとの値を持つ構造体または表：
%     r（Mark の半径 [mm]）・shotNo・direction（Scan 方向。無ければ NaN）・outer（最外周の Shot の Mark か。
%     分からなければ空 [] → 最外周の条件は使えない）。
%   text は条件の説明（例：「半径 0〜100 mm・Scan 方向 1」。絞り込まないなら「絞り込みなし」）、active は絞り込むか。
%   points を空 [] にすると、説明と active だけを返す（mask は空）。
arguments
    filter struct
    points = []
end
parts = strings(1, 0);
if filter.radiusMinMm > 0 || isfinite(filter.radiusMaxMm)
    parts(end + 1) = sprintf("半径 %g〜%s mm", filter.radiusMinMm, ...
        ternary(isfinite(filter.radiusMaxMm), sprintf("%g", filter.radiusMaxMm), ""));
end
shotNos = reshape(double(filter.shotNos), 1, []);
switch string(filter.shotMode)
    case "include"
        parts(end + 1) = "shotNo " + strjoin(string(shotNos), " ") + " だけ";
    case "exclude"
        parts(end + 1) = "shotNo " + strjoin(string(shotNos), " ") + " を除く";
end
if filter.scan > 0
    parts(end + 1) = sprintf("Scan 方向 %d", filter.scan);
end
switch string(filter.outer)
    case "only"
        parts(end + 1) = "最外周の Shot だけ";
    case "exclude"
        parts(end + 1) = "最外周の Shot を除く";
end
active = ~isempty(parts);
text = "絞り込みなし";
if active
    text = strjoin(parts, "・");
end
mask = true(0, 1);
if isempty(points)
    return
end
r = double(points.r(:));
mask = r >= filter.radiusMinMm & r < filter.radiusMaxMm;
shotNo = double(points.shotNo(:));
switch string(filter.shotMode)
    case "include"
        mask = mask & ismember(shotNo, shotNos);
    case "exclude"
        mask = mask & ~ismember(shotNo, shotNos);
end
if filter.scan > 0
    mask = mask & double(points.direction(:)) == filter.scan;
end
if string(filter.outer) ~= "all"
    outer = [];
    if isstruct(points) && isfield(points, "outer")
        outer = points.outer;
    elseif istable(points) && any(points.Properties.VariableNames == "outer")
        outer = points.outer;
    end
    if isempty(outer) && ~isempty(r)
        error('alignest:pointFilter', ['この結果では最外周の Shot が分からないため、最外周で絞り込めません' ...
            '（Excel から読み込んだ推定値には Shot の配置がありません）。']);
    end
    if string(filter.outer) == "only"
        mask = mask & logical(outer(:));
    else
        mask = mask & ~logical(outer(:));
    end
end
end

function value = ternary(condition, whenTrue, whenFalse)
if condition
    value = whenTrue;
else
    value = whenFalse;
end
end
