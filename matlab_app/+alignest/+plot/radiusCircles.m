function items = radiusCircles(ax, radiiMm)
%RADIUSCIRCLES Wafer 中心を中心とする半径 radiiMm [mm] の円を、今の図に重ねて描く（凡例の名前は「半径 R mm」）。
%   items = alignest.plot.radiusCircles(ax, radiiMm)
%   items：描いた線（凡例に入れるとき使う）。radiiMm が空なら何も描かない。
CIRCLE_COLOR = [0.10, 0.10, 0.10];
CIRCLE_STYLE = '-.';
CIRCLE_WIDTH = 1.2;
N_ANGLES = 361;
items = gobjects(0);
radiiMm = reshape(radiiMm(isfinite(radiiMm) & radiiMm > 0), 1, []);
if isempty(radiiMm)
    return
end
angle = linspace(0, 2 * pi, N_ANGLES);
held = ishold(ax);
hold(ax, 'on');
for r = radiiMm
    items(end + 1) = plot(ax, r * cos(angle), r * sin(angle), CIRCLE_STYLE, 'Color', CIRCLE_COLOR, ...
        'LineWidth', CIRCLE_WIDTH, 'DisplayName', sprintf('半径 %g mm', r), 'HitTest', 'off'); %#ok<AGROW>
end
if ~held
    hold(ax, 'off');
end
end
