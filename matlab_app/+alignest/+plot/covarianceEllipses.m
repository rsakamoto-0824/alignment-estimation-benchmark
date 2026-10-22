function handle = covarianceEllipses(ax, centers, covariance, radiusScale)
%COVARIANCEELLIPSES 点ごとの共分散 [X の分散, Y の分散, X・Y の共分散] の楕円を、centers を中心に描く。
%   楕円の向きは共分散行列の固有ベクトル、半径は √固有値 × radiusScale（σ の倍数 × 矢印の倍率）。
%   楕円の色は X・Y の相関係数の絶対値 |r|（0〜1。灰色 → 紫）。図の色の対応（colormap）は矢印の長さに使うので、
%   楕円の色は RGB で直接付け、目盛りは alignest.plot.correlationScale で図の中に描く。
%   handle.UserData は楕円ごとの |r|。値が NaN の点は描かない。描くものが無ければ空の図形を返す。
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
correlation = zeros(numel(usable), 1);
for k = 1:numel(usable)
    c = covariance(usable(k), :);
    [vectors, values] = eig([c(1), c(3); c(3), c(2)], 'vector');
    shape = vectors * diag(sqrt(max(values, 0)) * radiusScale) * circle;
    vertices((k - 1) * SEGMENTS + (1:SEGMENTS), :) = centers(usable(k), :) + shape.';
    correlation(k) = absoluteCorrelation(c);
end
faces = reshape(1:SEGMENTS * numel(usable), SEGMENTS, numel(usable)).';
colors = alignest.plot.correlationScale();
rgb = interp1(linspace(0, 1, size(colors, 1)), colors, correlation);
% 線の色は頂点ごとの RGB（EdgeColor = 'flat'）。1つの楕円の頂点はすべて同じ色
handle = patch(ax, 'Faces', faces, 'Vertices', vertices, 'FaceVertexCData', repelem(rgb, SEGMENTS, 1), ...
    'FaceColor', 'none', 'EdgeColor', 'flat', 'EdgeAlpha', ELLIPSE_ALPHA, 'LineWidth', 0.8, 'UserData', correlation);
end

function value = absoluteCorrelation(c)
% 相関係数の絶対値。どちらかの分散が 0 なら相関は決まらないので 0 とする
denominator = sqrt(c(1) * c(2));
value = 0;
if denominator > 0
    value = min(abs(c(3)) / denominator, 1);
end
end
