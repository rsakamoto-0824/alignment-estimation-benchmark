function points = highOrderUnitPoints(unit, sourceLabel)
%HIGHORDERUNITPOINTS 1つの Wafer の計測データ（alignest.prepareData の units の1つ）を、Shot 高次補正の点の表にする。
%   points = alignest.highOrderUnitPoints(unit)
%   points = alignest.highOrderUnitPoints(unit, sourceLabel)   % 点の種類の名前（既定は "計測値"）
%   点の表（alignest.shotHighOrder の入力の形）：source（点の種類）・name（名前。ここでは空）・shotNo・Xc・Yc（Shot 中心の
%   Wafer 上の座標 [mm]）・localX・localY（Shot 内の座標 markXmm・markYmm [mm]）・x・y（Wafer 上の座標 [mm]）・
%   valueX・valueY（measX・measY [nm]。StsX・StsY が有効でない値は NaN。Overlay 計測ルールのとおり、未測定を 0 にしない）・
%   direction（Scan 方向 1・2。分からなければ NaN）・rowParity（Shot 行の奇偶。1 = 奇数行・2 = 偶数行。上の行から数える）。
arguments
    unit struct
    sourceLabel (1, 1) string = "計測値"
end
marks = unit.marks;
n = numel(marks.x);
valueX = marks.measX(:);
valueY = marks.measY(:);
valueX(~marks.validX(:)) = NaN;
valueY(~marks.validY(:)) = NaN;
points = table(repmat(sourceLabel, n, 1), strings(n, 1), marks.shotNo(:), marks.Xmm(:), marks.Ymm(:), ...
    marks.markXmm(:), marks.markYmm(:), marks.x(:), marks.y(:), valueX, valueY, marks.direction(:), ...
    marks.shotRowParity(:), 'VariableNames', ["source", "name", "shotNo", "Xc", "Yc", "localX", "localY", "x", "y", ...
    "valueX", "valueY", "direction", "rowParity"]);
end
