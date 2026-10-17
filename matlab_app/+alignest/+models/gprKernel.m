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
if gp.ard
    r2 = zeros(size(total));
    for group = 1:gp.nLength
        r2 = r2 + squared(:, :, group) / p.lengths(group)^2;
    end
else
    r2 = total / p.lengths(1)^2;
end
[profile, slope, alphaDerivative] = kernelProfile(gp.family, r2, p.alpha);
kernel = p.signalVar * profile;
noiseVar = p.noiseVar;
wantGrads = nargout >= 2 && part == "train";
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

function [profile, slope, alphaDerivative] = kernelProfile(family, r2, alpha)
% g(r²)、h = dg/d(r²)、dg/dlog α（σf² を掛ける前）
alphaDerivative = [];
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
    otherwise
        error('alignest:kernel', '未知のカーネルの種類です: %s', family);
end
end
