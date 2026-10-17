function out = cardinalCubic(s)
%CARDINALCUBIC 台が [0, 4) の3次の基本 B スプライン。
out = zeros(size(s));
m0 = s >= 0 & s < 1;
m1 = s >= 1 & s < 2;
m2 = s >= 2 & s < 3;
m3 = s >= 3 & s < 4;
out(m0) = s(m0) .^ 3 / 6;
out(m1) = (-3 * s(m1) .^ 3 + 12 * s(m1) .^ 2 - 12 * s(m1) + 4) / 6;
out(m2) = (3 * s(m2) .^ 3 - 24 * s(m2) .^ 2 + 60 * s(m2) - 44) / 6;
out(m3) = (4 - s(m3)) .^ 3 / 6;
end
