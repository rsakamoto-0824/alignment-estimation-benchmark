function values = stationaryKernel(kernel, a, b, lengthScale)
%STATIONARYKERNEL 点どうしの距離だけで決まる（等方の）カーネルの値 k(a, b)（σf = 1）。GAM のガウス過程の形状関数で使う。
%   values = alignest.models.stationaryKernel(kernel, a, b, lengthScale)
%   a・b は 点の数 × 次元 の座標、lengthScale は長さスケール（r = 距離 / 長さスケール）。
%   kernel（式は GPR の alignest.models.gprKernel と同じ）：
%     exponential        exp(−r)
%     squaredexponential exp(−r²/2)
%     matern32           (1 + √3 r) exp(−√3 r)
%     matern52           (1 + √5 r + 5r²/3) exp(−√5 r)
%     rationalquadratic  (1 + r²/(2α))^(−α)、α = 1 に固定（GPR では α も推定するが、GAM では長さスケールだけ選ぶ）
%     matern_nu<ν>       2^(1−ν)/Γ(ν) · z^ν K_ν(z)、z = √(2ν) r（例：matern_nu1.5 は matern32 と同じ）
RATIONAL_QUADRATIC_ALPHA = 1;
kernel = string(kernel);
r2 = alignest.basis.pairwiseSquaredDiff(a, b) / lengthScale ^ 2;
r = sqrt(max(r2, 0));
switch kernel
    case "exponential"
        values = exp(-r);
    case "squaredexponential"
        values = exp(-0.5 * r2);
    case "matern32"
        values = (1 + sqrt(3) * r) .* exp(-sqrt(3) * r);
    case "matern52"
        values = (1 + sqrt(5) * r + 5 / 3 * r2) .* exp(-sqrt(5) * r);
    case "rationalquadratic"
        values = (1 + r2 / (2 * RATIONAL_QUADRATIC_ALPHA)) .^ (-RATIONAL_QUADRATIC_ALPHA);
    otherwise
        nu = str2double(extractAfter(kernel, "matern_nu"));
        if ~startsWith(kernel, "matern_nu") || isnan(nu)
            error('alignest:kernel', 'GAM のガウス過程のカーネルは %s のいずれかです: %s', ...
                strjoin(alignest.models.gamKernelChoices(), "・"), kernel);
        end
        alignest.models.maternNuCheck(nu);
        values = maternValues(nu, r);
end
end

function values = maternValues(nu, r)
% 大きい z で桁あふれしないよう、指数で尺度を変えたベッセル関数（besselk(·, ·, 1) = K·e^z）を対数で使う。r = 0 では 1
z = sqrt(2 * nu) * r;
values = ones(size(z));
positive = z > 0;
logC = (1 - nu) * log(2) - gammaln(nu);
zp = z(positive);
values(positive) = exp(logC + nu * log(zp) + log(besselk(nu, zp, 1)) - zp);
end
