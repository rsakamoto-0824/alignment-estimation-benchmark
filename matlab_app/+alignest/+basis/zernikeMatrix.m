function values = zernikeMatrix(xNorm, yNorm, modes)
%ZERNIKEMATRIX 正規化座標 (x/R, y/R) で、RMS 正規化した実数値 Zernike 多項式を並べた行列（点数 × モード数）。
%   Z_n^m = N R_n^|m|(ρ) cos(mθ)（m ≥ 0）、N R_n^|m|(ρ) sin(|m|θ)（m < 0）、N = sqrt(2(n+1)/(1+δ_m0))。
rho = hypot(xNorm(:), yNorm(:));
theta = atan2(yNorm(:), xNorm(:));
values = zeros(numel(rho), size(modes, 1));
for column = 1:size(modes, 1)
    n = modes(column, 1);
    m = modes(column, 2);
    radial = zeros(size(rho));
    for s = 0:(n - abs(m)) / 2
        coefficient = (-1)^s * factorial(n - s) / ...
            (factorial(s) * factorial((n + abs(m)) / 2 - s) * factorial((n - abs(m)) / 2 - s));
        radial = radial + coefficient * rho .^ (n - 2 * s);
    end
    if m == 0
        normalization = sqrt(n + 1);
        angular = ones(size(theta));
    else
        normalization = sqrt(2 * (n + 1));
        if m > 0
            angular = cos(m * theta);
        else
            angular = sin(-m * theta);
        end
    end
    values(:, column) = normalization * radial .* angular;
end
end
