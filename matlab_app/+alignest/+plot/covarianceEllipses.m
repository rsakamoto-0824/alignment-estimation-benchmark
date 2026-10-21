function handle = covarianceEllipses(ax, centers, covariance, radiusScale)
%COVARIANCEELLIPSES 点ごとの共分散 [X の分散, Y の分散, X・Y の共分散] の楕円を、centers を中心に描く。
%   楕円の向きは共分散行列の固有ベクトル、半径は √固有値 × radiusScale（σ の倍数 × 矢印の倍率）。
%   楕円の色は X・Y の相関係数の絶対値 |r|（0〜1）。図の色の対応（colormap と色の範囲）を |r| 用にして、
%   右に色の目盛り（上に「|r|」）を付ける。値が NaN の点は描かない。描くものが無ければ空の図形を返す。
SEGMENTS = 36;
ELLIPSE_ALPHA = 0.85;
angle = linspace(0, 2 * pi, SEGMENTS + 1);
angle = angle(1:end - 1);   % 面（patch）は最後の点から最初の点へ自動で閉じる
circle = [cos(angle); sin(angle)];
usable = find(all(isfinite(covariance), 2) & all(isfinite(centers), 2));
handle = gobjects(0);
if isempty(usable)
    return
end
vertices = zeros(SEGMENTS * numel(usable), 2);
correlation = zeros(SEGMENTS * numel(usable), 1);
for k = 1:numel(usable)
    c = covariance(usable(k), :);
    [vectors, values] = eig([c(1), c(3); c(3), c(2)], 'vector');
    shape = vectors * diag(sqrt(max(values, 0)) * radiusScale) * circle;
    rows = (k - 1) * SEGMENTS + (1:SEGMENTS);
    vertices(rows, :) = centers(usable(k), :) + shape.';
    correlation(rows) = absoluteCorrelation(c);
end
faces = reshape(1:SEGMENTS * numel(usable), SEGMENTS, numel(usable)).';
% 線の色は頂点ごとの値（EdgeColor = 'flat'）。1つの楕円の頂点はすべて同じ |r|
handle = patch(ax, 'Faces', faces, 'Vertices', vertices, 'FaceVertexCData', correlation, 'FaceColor', 'none', ...
    'EdgeColor', 'flat', 'EdgeAlpha', ELLIPSE_ALPHA, 'LineWidth', 0.8);
colormap(ax, correlationColormap());
caxis(ax, [0, 1]);
bar = colorbar(ax);
% 横の長い説明は隣の図と重なるので、目盛りの上に短く書く（説明は図の下の文と凡例）
bar.Title.String = '|r|';
end

function value = absoluteCorrelation(c)
% 相関係数の絶対値。どちらかの分散が 0 なら相関は決まらないので 0 とする
denominator = sqrt(c(1) * c(2));
value = 0;
if denominator > 0
    value = min(abs(c(3)) / denominator, 1);
end
end

function colors = correlationColormap()
% 灰色（相関なし）→ 橙 → 濃い紫（強い相関）。白い背景でも 0 付近の楕円が見えるように灰色から始める
LEVELS = 256;
STOPS = [0, 0.5, 1];
STOP_COLORS = [0.60, 0.60, 0.60; 0.93, 0.55, 0.13; 0.45, 0.05, 0.45];
colors = interp1(STOPS, STOP_COLORS, linspace(0, 1, LEVELS));
end
