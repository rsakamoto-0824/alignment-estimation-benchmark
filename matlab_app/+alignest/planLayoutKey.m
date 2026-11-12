function key = planLayoutKey(unit)
%PLANLAYOUTKEY Wafer の「配置の種類」の目印（使える Mark の座標と Scan 方向）。
%   key = alignest.planLayoutKey(unit)   % 文字の並び（char）
%   使える Mark（X か Y の値がある Mark）の座標と Scan 方向が同じ Wafer は、同じ学習パターンを使い回す
%   （alignest.cachedTrainingPlan）。評価にかかる時間の目安（alignest.estimateRunSeconds）でも、学習パターンを作る回数を
%   この目印の種類の数で数える。
marks = unit.marks;
usable = marks.validX | marks.validY;
key = sprintf('%.3f,', [marks.x(usable); marks.y(usable); marks.direction(usable)]);
end
