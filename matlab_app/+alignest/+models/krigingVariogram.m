function values = krigingVariogram(variogramName, params, distance, includeNugget)
%KRIGINGVARIOGRAM バリオグラムのモデル（PyKrige の既定と同じ式。params の最後がナゲット）。
%   linear      : γ(d) = slope·d + nugget
%   power       : γ(d) = scale·d^exponent + nugget（0 < exponent < 2）
%   gaussian    : γ(d) = psill·(1 − exp(−d² / (4/7·range)²)) + nugget
%   exponential : γ(d) = psill·(1 − exp(−d / (range/3))) + nugget
if nargin < 4
    includeNugget = true;
end
nugget = 0;
if includeNugget
    nugget = params(end);
end
switch variogramName
    case "linear"
        values = params(1) * distance + nugget;
    case "power"
        values = params(1) * distance .^ params(2) + nugget;
    case "gaussian"
        values = params(1) * (1 - exp(-(distance .^ 2) / (params(2) * 4 / 7)^2)) + nugget;
    case "exponential"
        values = params(1) * (1 - exp(-distance / (params(2) / 3))) + nugget;
    otherwise
        error('alignest:variogram', 'バリオグラムは linear・gaussian・power・exponential のいずれかです: %s', variogramName);
end
end
