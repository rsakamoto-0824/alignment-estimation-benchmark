function [rowsU, rowsV, names] = rtDesign(points, order)
%RTDESIGN RT モデル（K次）の基底を、X 方向（u）・Y 方向（v）の変位で書いた行列にする。
%   [rowsU, rowsV, names] = alignest.basis.rtDesign(points, order)
%   points：Wafer 半径で割った座標（点の数 × 2）、order：次数 K。変位を半径方向 R と接線方向 T に分け、R = ρ·M(x, y)、
%   T = ρ·Θ(x, y) とする。局所倍率 M・局所回転 Θ を Zernike 多項式（動径次数 n ≤ K）で展開し、並進2項・非対称倍率・直交度の
%   4項を加える（列の順：並進 X・並進 Y・非対称倍率・直交度・倍率の項・回転の項）。names：項の名前（列の数 × 1）。
x = points(:, 1);
y = points(:, 2);
ones_ = ones(size(x));
zeros_ = zeros(size(x));
modes = alignest.basis.zernikeModes(order);
zernike = alignest.basis.zernikeMatrix(x, y, modes);
rowsU = [ones_, zeros_, x, y, x .* zernike, -y .* zernike];   % R = ρ·Z → (u, v) = Z·(x, y)、T = ρ·Z → (u, v) = Z·(−y, x)
rowsV = [zeros_, ones_, -y, x, y .* zernike, x .* zernike];
labels = compose("Z(%d,%d)", modes(:, 1), modes(:, 2));
names = ["並進 X"; "並進 Y"; "非対称倍率"; "直交度"; "倍率 " + labels; "回転 " + labels];
end
