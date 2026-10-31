function [points, info] = highOrderTargetPoints(unit, targetTable, measuredMarks)
%HIGHORDERTARGETPOINTS 未知の座標の推定値（「6. 未知の座標の推定」）を、Shot 高次補正の点の表にする。
%   [points, info] = alignest.highOrderTargetPoints(unit, targetTable)
%   [points, info] = alignest.highOrderTargetPoints(unit, targetTable, measuredMarks)
%   unit：推定した Wafer（alignest.prepareData の units の1つ）、targetTable：alignest.predictTargets の result.table。
%   measuredMarks（省略可）：一緒に使う計測値の Mark（unit.marks の並びの論理ベクトル。学習に使った Mark など）。
%   未知の座標の点：Shot は点を含む Shot（targetTable.shotIndex）、Shot 内の座標は「点 − その Shot の中心」、値は推定値
%   （estimateX・estimateY）、Scan 方向・Shot 行の奇偶はその Shot のもの。Wafer の外の点（推定の対象外）と、どの Shot にも
%   入らない点は使わない（info に数を返す）。
%   points は alignest.highOrderUnitPoints と同じ形（source は "推定値（未知の座標）"、計測値の Mark は "実測値（学習点）"。
%   alignest.plot.correctionMap と同じ名前）。info.outsideWafer・info.noShot：使わなかった点の数、info.targets・
%   info.measured：使った点の数。
arguments
    unit struct
    targetTable table
    measuredMarks logical = false(0, 1)
end
TARGET_SOURCE = "推定値（未知の座標）";
MEASURED_SOURCE = "実測値（学習点）";
shots = unit.shots;
targets = targetTable;
outside = false(height(targets), 1);
if any(string(targets.Properties.VariableNames) == "outsideWafer")
    outside = targets.outsideWafer;
end
noShot = ~outside & ~(targets.shotIndex >= 1 & targets.shotIndex <= numel(shots.shotNo));
targets = targets(~outside & ~noShot, :);
n = height(targets);
centerX = shots.Xmm(targets.shotIndex);
centerY = shots.Ymm(targets.shotIndex);
points = table(repmat(TARGET_SOURCE, n, 1), string(targets.name), shots.shotNo(targets.shotIndex), centerX(:), ...
    centerY(:), targets.x - centerX(:), targets.y - centerY(:), targets.x, targets.y, targets.estimateX, ...
    targets.estimateY, shots.direction(targets.shotIndex), shots.rowParity(targets.shotIndex), 'VariableNames', ...
    ["source", "name", "shotNo", "Xc", "Yc", "localX", "localY", "x", "y", "valueX", "valueY", "direction", ...
    "rowParity"]);
info = struct("targets", n, "outsideWafer", nnz(outside), "noShot", nnz(noShot), "measured", 0);
if any(measuredMarks)
    measured = alignest.highOrderUnitPoints(unit, MEASURED_SOURCE);
    measured = measured(measuredMarks(:) & (isfinite(measured.valueX) | isfinite(measured.valueY)), :);
    info.measured = height(measured);
    points = [measured; points];
end
end
