function handle = shotFrames(ax, centers, sizeMm, color)
%SHOTFRAMES Shot の枠（長方形）を細い線で描く。centers は Shot 中心 [x, y]（mm）、sizeMm は [幅, 高さ]（mm）。
%   多数の Shot を1本の線（NaN で区切る）として描くので速い。中心が無い・大きさが分からないときは何もしない。
FRAME_COLOR = [0.62, 0.62, 0.62];
FRAME_LINE_WIDTH = 0.5;
if nargin < 4
    color = FRAME_COLOR;
end
handle = gobjects(0);
if isempty(centers) || any(~isfinite(sizeMm)) || any(sizeMm <= 0)
    return
end
half = sizeMm / 2;
cornerX = [-1, 1, 1, -1, -1, NaN] * half(1);
cornerY = [-1, -1, 1, 1, -1, NaN] * half(2);
lineX = (centers(:, 1) + cornerX).';
lineY = (centers(:, 2) + cornerY).';
handle = plot(ax, lineX(:), lineY(:), '-', 'Color', color, 'LineWidth', FRAME_LINE_WIDTH, 'HandleVisibility', 'off');
end
