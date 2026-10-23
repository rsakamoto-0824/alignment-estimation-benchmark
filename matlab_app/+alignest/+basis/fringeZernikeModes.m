function modes = fringeZernikeModes(order)
%FRINGEZERNIKEMODES Fringe Zernike の次数 k までのモード [n, m]（Fringe 番号 Z1〜Z(k+1)² の順。行がモード）。
%   modes = alignest.basis.fringeZernikeModes(k)
%   Fringe の次数 k = (n + |m|)/2。k = 1：Z1〜Z4（ピストン・チルト・パワー）、k = 2：Z1〜Z9、k = 3：Z1〜Z16、
%   k = 4：Z1〜Z25、k = 5：Z1〜Z36。次数 k までのモードは動径次数 n ≤ 2k の中にあり、Fringe 番号順の先頭
%   (k+1)² 個がちょうど次数 k までになる（alignest.basis.zernikeModes の並び）。
if order < 0 || order ~= round(order)
    error('alignest:zernikeOrder', 'Fringe Zernike の次数は 0 以上の整数にしてください: %g', order);
end
modes = alignest.basis.zernikeModes(2 * order);
modes = modes(1:(order + 1)^2, :);
end
