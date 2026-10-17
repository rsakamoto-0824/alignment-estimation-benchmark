function modes = zernikeModes(maxOrder)
%ZERNIKEMODES 動径次数 n ≤ maxOrder の全モード [n, m] を Fringe 番号順に並べる（行がモード）。
%   Fringe 番号：同じ k = (n+|m|)/2 の中で |m| の大きい順、cos（m > 0）→ sin（m < 0）、m = 0 が最後。
if maxOrder < 0
    error('alignest:zernikeOrder', 'Zernike の次数は0以上にしてください: %d', maxOrder);
end
modes = zeros(0, 2);
for n = 0:maxOrder
    for m = -n:2:n
        modes(end + 1, :) = [n, m]; %#ok<AGROW>
    end
end
index = zeros(size(modes, 1), 1);
for row = 1:size(modes, 1)
    index(row) = fringeIndex(modes(row, 1), modes(row, 2));
end
[~, order] = sort(index);
modes = modes(order, :);
end

function index = fringeIndex(n, m)
k = (n + abs(m)) / 2;
if m == 0
    offset = 2 * k;
else
    offset = 2 * (k - abs(m)) + (m < 0);
end
index = k * k + 1 + offset;
end
