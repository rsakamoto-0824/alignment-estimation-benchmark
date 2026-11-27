function key = planLayoutKey(unit, level)
%PLANLAYOUTKEY Wafer の「配置の種類」の目印。同じ目印の Wafer は、同じ学習パターンを使い回す（alignest.cachedTrainingPlan）。
%   key = alignest.planLayoutKey(unit)           % Mark 単位の計画の目印（使える Mark の座標と Scan 方向）
%   key = alignest.planLayoutKey(unit, "shot")   % Shot 単位の計画の目印（全 Shot の中心の座標・Scan 方向と、計測値のある
%                                                % Shot か。Shot の中の一部の Mark の値が無くても同じ目印）
%   key は文字の並び（char）。評価にかかる時間の目安（alignest.estimateRunSeconds）でも、学習パターンを作る回数を
%   この目印の種類の数で数える。Shot 単位の計画は、候補の Shot（計測値が1点以上ある Shot）が同じなら選ぶ Shot が
%   同じなので、Wafer ごとに Mark の欠けが少しずつ違っても作り直さない（I 基準・D 基準だけ、その Wafer の Mark で求め直す）。
arguments
    unit struct
    level (1, 1) string {mustBeMember(level, ["mark", "shot"])} = "mark"
end
if level == "shot"
    shots = unit.shots;
    candidate = double(shots.nValidX + shots.nValidY > 0);
    key = sprintf('%.3f,', [shots.Xmm(:); shots.Ymm(:); shots.direction(:); candidate(:)]);
    return
end
marks = unit.marks;
usable = marks.validX | marks.validY;
key = sprintf('%.3f,', [marks.x(usable); marks.y(usable); marks.direction(usable)]);
end
