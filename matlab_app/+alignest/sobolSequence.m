function points = sobolSequence(n)
%SOBOLSEQUENCE 2次元の Sobol 列（[0, 1) × [0, 1) に均等に散らばる点の並び。低食い違い量列）の最初の n 点。
%   points = alignest.sobolSequence(n)   % n × 2（1列目 = 1次元目、2列目 = 2次元目）
%   先頭の (0, 0) は飛ばし、2点目から返す。前から何点取っても、点が全体に偏りなく散らばる（乱数より隙間・重なりが少ない）。
%   作り方（Bratley・Fox の Gray コード法。MATLAB 本体だけで計算し、Statistics and Machine Learning Toolbox の sobolset は
%   使わない）：方向数 v_k（32 ビットの整数）を次元ごとに決め、x_i = x_(i−1) XOR v_c（c = i − 1 の2進数で最も下の 0 の位置）。
%   1次元目：v_k = 2^(32−k)（van der Corput 列）。2次元目：原始多項式 x + 1（Joe・Kuo の方向数 m_1 = 1）から
%   v_k = v_(k−1) XOR (v_(k−1) ≫ 1)。Toolbox の sobolset(2, 'PointOrder', 'graycode') の2点目からと同じ点
%   （2026-11-19 に 1023 点で一致を確認。sobolset の既定の並び 'standard' とは順が違うが、前から 2^k 点の集合は同じ）。
arguments
    n (1, 1) double {mustBeInteger, mustBeNonnegative}
end
BITS = 32;
SCALE = 2 ^ BITS;
directions = zeros(BITS, 2, 'uint32');
for k = 1:BITS
    directions(k, 1) = uint32(2 ^ (BITS - k));
end
directions(1, 2) = uint32(2 ^ (BITS - 1));
for k = 2:BITS
    previous = directions(k - 1, 2);
    directions(k, 2) = bitxor(previous, bitshift(previous, -1));
end
points = zeros(n, 2);
current = zeros(1, 2, 'uint32');
for i = 1:n
    c = lowestZeroBit(i - 1);   % 1 始まり
    current = bitxor(current, directions(c, :));
    points(i, :) = double(current) / SCALE;
end
end

function position = lowestZeroBit(value)
% value の2進数で最も下の 0 のビットの位置（1 始まり）
position = 1;
while bitand(value, 1) == 1
    value = bitshift(value, -1);
    position = position + 1;
end
end
