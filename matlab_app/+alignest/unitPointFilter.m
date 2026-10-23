function mask = unitPointFilter(unit, filter)
%UNITPOINTFILTER 1つの Wafer の Mark（unit.marks の並び）のうち、評価点の絞り込みの条件に合うもの（論理ベクトル）。
%   mask = alignest.unitPointFilter(unit, filter)   % filter は alignest.defaultPointFilter と同じ形
%   最外周は Shot の配置から決める（alignest.outerShots）。Scan 方向が無い Wafer では、Scan 方向の条件に合う点は無い。
marks = unit.marks;
direction = nan(numel(marks.x), 1);
if unit.hasDirection
    direction = marks.direction;
end
outerShot = alignest.outerShots(unit.shots);
points = struct("r", marks.r, "shotNo", marks.shotNo, "direction", direction, "outer", outerShot(marks.shotIndex));
mask = alignest.pointFilterMask(filter, points);
end
