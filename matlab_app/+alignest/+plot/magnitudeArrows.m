function handle = magnitudeArrows(ax, points, vectors, scaleMmPerNm, options)
%MAGNITUDEARROWS 矢印（ベクトル）を、長さ |v| [nm] を色にして描く。図の右に色の目盛り（上に「|v| [nm]」）を付ける。
%   handle = alignest.plot.magnitudeArrows(ax, points, vectors, scaleMmPerNm)
%   points は矢印の根元 [x, y]（mm）、vectors は値 [X, Y]（nm）。矢印の長さは 値 × scaleMmPerNm [mm]。
%   図の色の対応（colormap と色の範囲）を矢印の長さ用にする。色の範囲は 0〜options.magnitudeLimit
%   （0 なら描く矢印の最大）。どちらかの値が NaN の点と長さ 0 の点は描かない。描くものが無ければ空の図形を返す。
%   矢印はまとめて1つの図形（線の集まり）で描くので、点が多くても速い。
arguments
    ax
    points double
    vectors double
    scaleMmPerNm (1, 1) double {mustBePositive}
    options.magnitudeLimit (1, 1) double {mustBeNonnegative} = 0
    options.lineWidth (1, 1) double {mustBePositive} = 1
end
HEAD_RATIO = 0.3;          % 矢じりの長さ（矢印の長さに対する割合）
HEAD_ANGLE_DEG = 25;       % 矢じりの開き（片側）
handle = gobjects(0);
magnitude = hypot(vectors(:, 1), vectors(:, 2));
usable = all(isfinite(points), 2) & isfinite(magnitude) & magnitude > 0;
if ~any(usable)
    return
end
base = points(usable, :);
shaft = vectors(usable, :) * scaleMmPerNm;
magnitude = magnitude(usable);
tip = base + shaft;
direction = shaft ./ hypot(shaft(:, 1), shaft(:, 2));
headLength = HEAD_RATIO * hypot(shaft(:, 1), shaft(:, 2));
angle = deg2rad(HEAD_ANGLE_DEG);
rotate = @(d, a) [d(:, 1) * cos(a) - d(:, 2) * sin(a), d(:, 1) * sin(a) + d(:, 2) * cos(a)];
wingA = tip - headLength .* rotate(direction, angle);
wingB = tip - headLength .* rotate(direction, -angle);
% 矢印ごとに 根元・先・矢じりの両端 の4点、線は 根元→先・先→矢じり2本（2点の面は線として描かれる）
n = size(base, 1);
vertices = reshape(permute(cat(3, base, tip, wingA, wingB), [3, 1, 2]), 4 * n, 2);
offset = 4 * (0:n - 1).';
faces = [offset + [1, 2]; offset + [2, 3]; offset + [2, 4]];
limit = options.magnitudeLimit;
if limit <= 0
    limit = max(magnitude);
end
% 頂点ごとの色は縦の並び（矢印が1本のとき repelem(スカラー, 4) は横になるので、縦にそろえる）
handle = patch(ax, 'Faces', faces, 'Vertices', vertices, 'FaceVertexCData', repelem(magnitude(:), 4, 1), ...
    'FaceColor', 'none', 'EdgeColor', 'flat', 'LineWidth', options.lineWidth);
colormap(ax, magnitudeColormap());
caxis(ax, [0, max(limit, eps)]);
bar = colorbar(ax);
bar.Title.String = '|v| [nm]';
end

function colors = magnitudeColormap()
% 青（短い）→ 緑 → 橙 → 赤（長い）。白い背景でも短い矢印が見えるように薄い色を使わない
LEVELS = 256;
STOPS = [0, 1 / 3, 2 / 3, 1];
STOP_COLORS = [0.15, 0.35, 0.80; 0.10, 0.62, 0.45; 0.95, 0.60, 0.10; 0.80, 0.08, 0.08];
colors = interp1(STOPS, STOP_COLORS, linspace(0, 1, LEVELS));
end
