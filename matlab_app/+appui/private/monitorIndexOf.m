function [index, monitor] = monitorIndexOf(position)
% 窓（Position = [左, 下, 幅, 高さ]）の中心がある画面（モニター）の番号と位置 [左, 下, 幅, 高さ]。
% どの画面にも入らないときは、中心に最も近い画面
monitors = get(groot, 'MonitorPositions');
if isempty(monitors)
    monitors = get(groot, 'ScreenSize');
end
center = position(1:2) + position(3:4) / 2;
inside = center(1) >= monitors(:, 1) & center(1) < monitors(:, 1) + monitors(:, 3) & ...
    center(2) >= monitors(:, 2) & center(2) < monitors(:, 2) + monitors(:, 4);
if any(inside)
    index = find(inside, 1);
else
    centers = monitors(:, 1:2) + monitors(:, 3:4) / 2;
    [~, index] = min(hypot(centers(:, 1) - center(1), centers(:, 2) - center(2)));
end
monitor = monitors(index, :);
end
