function handle = zoneRings(ax, radiiMm)
%ZONERINGS 同心円の制約の区切り（Shot 中心の半径 [mm]）を、破線の円と半径の文字で描く。
%   handle = alignest.plot.zoneRings(ax, radiiMm)   % handle は凡例に使う最初の円（区切りが無ければ空）
%   区切りの半径は alignest.zoneEdgesMm。区画は Shot 中心の半径で決まるので、Shot の枠と合わせて見る。
RING_COLOR = [0.85, 0.33, 0.10];
RING_WIDTH = 1.3;
LABEL_ANGLE = 5 * pi / 12;   % 半径の文字を置く向き（上のやや右。区切りどうしの文字が重ならないように）
LABEL_FONT_SIZE = 8;
handle = gobjects(0);
radiiMm = reshape(radiiMm(isfinite(radiiMm) & radiiMm > 0), 1, []);
if isempty(radiiMm)
    return
end
angle = linspace(0, 2 * pi, 361);
wasHeld = ishold(ax);
hold(ax, 'on');
for k = 1:numel(radiiMm)
    ring = plot(ax, radiiMm(k) * cos(angle), radiiMm(k) * sin(angle), '-.', 'Color', RING_COLOR, ...
        'LineWidth', RING_WIDTH, 'HandleVisibility', 'off', 'HitTest', 'off');
    if k == 1
        ring.HandleVisibility = 'on';
        ring.DisplayName = '同心円の区切り';
        handle = ring;
    end
    text(ax, radiiMm(k) * cos(LABEL_ANGLE), radiiMm(k) * sin(LABEL_ANGLE), sprintf(' %g mm', radiiMm(k)), ...
        'Color', RING_COLOR, 'FontSize', LABEL_FONT_SIZE, 'FontWeight', 'bold', 'VerticalAlignment', 'middle', ...
        'BackgroundColor', [1, 1, 1], 'Margin', 0.5, 'HitTest', 'off', 'Clipping', 'on');
end
if ~wasHeld
    hold(ax, 'off');
end
end
