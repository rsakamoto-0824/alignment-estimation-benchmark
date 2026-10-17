function squared = pairwiseSquaredDiff(rowPoints, columnPoints, groups)
%PAIRWISESQUAREDDIFF 説明変数の差の2乗を、説明変数（groups の番号）ごとに足した3次元配列。
%   squared(i, j, g) = Σ_{列 c が g 番} (rowPoints(i, c) − columnPoints(j, c))²
%   groups を省略すると全列を1つにまとめる（距離の2乗）。
if nargin < 3
    groups = ones(1, size(rowPoints, 2));
end
nGroups = max(groups);
squared = zeros(size(rowPoints, 1), size(columnPoints, 1), nGroups);
for column = 1:size(rowPoints, 2)
    difference = rowPoints(:, column) - columnPoints(:, column).';
    squared(:, :, groups(column)) = squared(:, :, groups(column)) + difference .^ 2;
end
end
