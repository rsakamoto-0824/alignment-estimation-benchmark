function [kernel, grads, noiseVar] = gprKernel(gp, logParams, part)
%GPRKERNEL カーネル行列と、対数パラメータでの微分（ノイズ以外）。
%   part = "train"（学習点どうし、既定）または "cross"（評価点 × 学習点、微分なし）。
%   grads は 学習点数 × 学習点数 × （パラメータ数 − 1） の配列。nargout < 2 なら作らない。
if nargin < 3
    part = "train";
end
p = splitParams(gp, logParams);
if part == "train"
    squared = gp.trainSq;
    total = gp.trainSqTotal;
else
    squared = gp.crossSq;
    total = gp.crossSqTotal;
end
wantGrads = nargout >= 2 && part == "train";
if gp.family == "per"
    [kernel, grads] = periodicKernel(gp, p, squared, wantGrads);
elseif gp.ard
    r2 = zeros(size(total));
    for group = 1:gp.nLength
        r2 = r2 + squared(:, :, group) / p.lengths(group)^2;
    end
else
    r2 = total / p.lengths(1)^2;
end
if gp.family ~= "per"
    [kernel, grads] = stationaryPart(gp, p, squared, r2, wantGrads);
end
noiseVar = p.noiseVar;
for k = 1:gp.nCategorical
    if part == "train"
        same = gp.categorical(k).trainSame;
    else
        same = gp.categorical(k).crossSame;
    end
    kernel = kernel + p.categoricalVar(k) * same;
    if wantGrads
        grads(:, :, gp.categoricalOffset + k - 1) = 2 * p.categoricalVar(k) * same;
    end
end
end

function [kernel, grads] = stationaryPart(gp, p, squared, r2, wantGrads)
% 距離 r²（長さスケールで割った）だけで決まるカーネルと、対数パラメータでの微分（質的変数の項は呼んだ側で足す）
grads = [];
[profile, slope, alphaDerivative] = kernelProfile(gp, r2, p.alpha);
kernel = p.signalVar * profile;
if wantGrads
    grads = zeros(size(kernel, 1), size(kernel, 2), gp.nParams - 1);
    if gp.ard
        for group = 1:gp.nLength
            grads(:, :, group) = p.signalVar * slope .* (-2 * squared(:, :, group) / p.lengths(group)^2);
        end
    else
        grads(:, :, 1) = p.signalVar * slope .* (-2 * r2);
    end
    grads(:, :, gp.nLength + 1) = 2 * kernel;
    if gp.hasAlpha
        grads(:, :, gp.nLength + 2) = p.signalVar * alphaDerivative;
    end
end
end

function [kernel, grads] = periodicKernel(gp, p, squared, wantGrads)
% 周期カーネル σf² exp(−2 Σ_j sin²(π d_j / p) / ℓ_j²)（d_j：説明変数 j ごとの距離、p：周期 = p.alpha の位置のパラメータ）。
% 微分：d/dlog ℓ_j = K · 4 sin²(φ_j)/ℓ_j²、d/dlog p = K · Σ_j 2 φ_j sin(2φ_j)/ℓ_j²（φ_j = π d_j / p）、d/dlog σf = 2K
grads = [];
period = p.alpha;
nGroups = size(squared, 3);
exponent = zeros(size(squared, 1), size(squared, 2));
phases = cell(nGroups, 1);
for group = 1:nGroups
    ell = p.lengths(min(group, gp.nLength));
    phases{group} = pi * sqrt(max(squared(:, :, group), 0)) / period;
    exponent = exponent - 2 * sin(phases{group}) .^ 2 / ell ^ 2;
end
kernel = p.signalVar * exp(exponent);
if ~wantGrads
    return
end
grads = zeros(size(kernel, 1), size(kernel, 2), gp.nParams - 1);
periodGrad = zeros(size(kernel));
for group = 1:nGroups
    lengthIndex = min(group, gp.nLength);
    ell = p.lengths(lengthIndex);
    grads(:, :, lengthIndex) = grads(:, :, lengthIndex) + kernel .* (4 * sin(phases{group}) .^ 2 / ell ^ 2);
    periodGrad = periodGrad + 2 * phases{group} .* sin(2 * phases{group}) / ell ^ 2;
end
grads(:, :, gp.nLength + 1) = 2 * kernel;
grads(:, :, gp.nLength + 2) = kernel .* periodGrad;
end

function p = splitParams(gp, logParams)
logParams = logParams(:);
p.lengths = exp(logParams(1:gp.nLength));
p.signalVar = exp(2 * logParams(gp.nLength + 1));
p.alpha = 1;
if gp.hasAlpha
    p.alpha = exp(logParams(gp.nLength + 2));
end
p.categoricalVar = exp(2 * logParams(gp.categoricalOffset:gp.categoricalOffset + gp.nCategorical - 1));
p.noiseVar = exp(2 * logParams(end));
end

function [profile, slope, alphaDerivative] = kernelProfile(gp, r2, alpha)
% g(r²)、h = dg/d(r²)、dg/dlog α（σf² を掛ける前）
alphaDerivative = [];
family = gp.family;
switch family
    case "se"
        profile = exp(-0.5 * r2);
        slope = -0.5 * profile;
    case "rq"
        u = 1 + r2 / (2 * alpha);
        profile = u .^ (-alpha);
        slope = -0.5 * u .^ (-alpha - 1);
        alphaDerivative = alpha * profile .* (-log(u) + r2 ./ (2 * alpha * u));
    case "exp"
        r = sqrt(max(r2, 0));
        profile = exp(-r);
        slope = zeros(size(r));
        positive = r > 0;
        slope(positive) = -profile(positive) ./ (2 * r(positive));
    case "m32"
        r = sqrt(max(r2, 0));
        e = exp(-sqrt(3) * r);
        profile = (1 + sqrt(3) * r) .* e;
        slope = -1.5 * e;
    case "m52"
        r = sqrt(max(r2, 0));
        e = exp(-sqrt(5) * r);
        profile = (1 + sqrt(5) * r + (5 / 3) * r2) .* e;
        slope = -(5 / 6) * (1 + sqrt(5) * r) .* e;
    case "mnu"
        [profile, slope] = maternProfile(gp.nu, r2);
    otherwise
        error('alignest:kernel', '未知のカーネルの種類です: %s', family);
end
end

function [profile, slope] = maternProfile(nu, r2)
% 任意の ν の Matérn：g = c z^ν K_ν(z)、z = √(2ν) r、c = 2^(1−ν)/Γ(ν)。
% dg/dz = −c z^ν K_{ν−1}(z)、dz/d(r²) = ν/z より h = dg/d(r²) = −c ν z^(ν−1) K_{ν−1}(z)。
% 大きい z で桁あふれ・桁落ちしないよう、指数で尺度を変えたベッセル関数（besselk(·, ·, 1) = K·e^z）を対数で使う。
% r = 0 では g = 1。h は勾配で r² を掛けて使うだけなので 0 にしておく（ν ≤ 1 では r → 0 で発散するため）。
r = sqrt(max(r2, 0));
z = sqrt(2 * nu) * r;
profile = ones(size(z));
slope = zeros(size(z));
positive = z > 0;
logC = (1 - nu) * log(2) - gammaln(nu);
zp = z(positive);
profile(positive) = exp(logC + nu * log(zp) + log(besselk(nu, zp, 1)) - zp);
slope(positive) = -nu * exp(logC + (nu - 1) * log(zp) + log(besselk(nu - 1, zp, 1)) - zp);
end
