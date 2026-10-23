function handles = scanFrames(ax, centers, sizeMm, directions, insetRatio)
%SCANFRAMES Shot の枠を Scan 方向の色で描き、枠の左上に方向の印（▲ = 1、▼ = 2）を付ける。
%   handles = alignest.plot.scanFrames(ax, centers, sizeMm, directions, insetRatio)
%   centers は Shot 中心 [x, y]（mm）、sizeMm は [幅, 高さ]、directions は Shot ごとの Scan 方向（1・2。無ければ NaN）。
%   insetRatio は枠を Shot の内側に縮める割合（0 なら Shot の外形。計測マップでは塗りの枠と重ならないように内側に描く）。
%   handles は凡例に使う Scan 方向ごとの線（色と印を1つにした凡例。方向の無い Shot は灰色の細い枠）。
%   色だけで区別しないよう、印の形（▲・▼）でも方向を示す。
NO_DIRECTION_COLOR = [0.62, 0.62, 0.62];
FRAME_LINE_WIDTH = 1.4;
MARKER_SIZE = 4;
MARKER_POSITION = 0.62;   % 印を置く位置（Shot の半分の大きさに対する割合。左上）
if nargin < 5
    insetRatio = 0;
end
handles = gobjects(0);
if isempty(centers) || any(~isfinite(sizeMm)) || any(sizeMm <= 0)
    return
end
[colors, markers] = alignest.plot.scanColors();
directions = reshape(double(directions), [], 1);
if numel(directions) ~= size(centers, 1)
    directions = nan(size(centers, 1), 1);
end
wasHeld = ishold(ax);
hold(ax, 'on');
half = sizeMm / 2 * (1 - insetRatio);
cornerX = [-1, 1, 1, -1, -1, NaN] * half(1);
cornerY = [-1, -1, 1, 1, -1, NaN] * half(2);
noDirection = ~ismember(directions, [1, 2]);
if any(noDirection)
    alignest.plot.shotFrames(ax, centers(noDirection, :), sizeMm, NO_DIRECTION_COLOR);
end
for level = 1:2
    select = directions == level;
    if ~any(select)
        continue
    end
    lineX = (centers(select, 1) + cornerX).';
    lineY = (centers(select, 2) + cornerY).';
    plot(ax, lineX(:), lineY(:), '-', 'Color', colors(level, :), 'LineWidth', FRAME_LINE_WIDTH, ...
        'HandleVisibility', 'off', 'HitTest', 'off');
    % 印の線（凡例の見本）。枠の線は上で別に描くので、ここでは印だけにする
    handles(end + 1) = plot(ax, centers(select, 1) - MARKER_POSITION * half(1), ...
        centers(select, 2) + MARKER_POSITION * half(2), markers(level), 'LineStyle', 'none', 'Color', colors(level, :), ...
        'MarkerFaceColor', colors(level, :), 'MarkerSize', MARKER_SIZE, 'LineWidth', FRAME_LINE_WIDTH, ...
        'DisplayName', sprintf('Scan %d（%s）', level, ternary(level == 1, '▲', '▼')), ...
        'HitTest', 'off'); %#ok<AGROW>
end
if ~wasHeld
    hold(ax, 'off');
end
end

function value = ternary(condition, whenTrue, whenFalse)
if condition
    value = whenTrue;
else
    value = whenFalse;
end
end
