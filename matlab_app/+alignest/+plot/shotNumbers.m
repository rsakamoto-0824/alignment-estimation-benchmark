function labels = shotNumbers(ax, centers, shotNos)
%SHOTNUMBERS Shot 中心に shotNo を小さな灰色の文字で重ねて描く（Wafer ごとのマップ・Shot 高次補正のマップの「Shot 番号」）。
%   labels = alignest.plot.shotNumbers(ax, centers, shotNos)
%   centers：Shot 中心の座標 [x, y]（mm、Shot 数 × 2）、shotNos：Shot の番号（同じ数）。文字はクリックを図に渡し
%   （HitTest = off）、凡例には出さない。図の範囲の外の文字は描かない（Clipping）。
FONT_SIZE = 7;
TEXT_COLOR = [0.35, 0.35, 0.35];
labels = gobjects(0);
if isempty(centers) || numel(shotNos) ~= size(centers, 1)
    return
end
usable = all(isfinite(centers), 2) & isfinite(shotNos(:));
labels = text(ax, centers(usable, 1), centers(usable, 2), string(shotNos(usable)), 'FontSize', FONT_SIZE, ...
    'Color', TEXT_COLOR, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'Clipping', 'on', ...
    'HitTest', 'off', 'HandleVisibility', 'off', 'Tag', 'keepColor');
end
