function values = krigingVariogram(variogramName, params, distance, includeNugget)
%KRIGINGVARIOGRAM バリオグラムのモデル（PyKrige の既定と同じ式。params の最後がナゲット）。
%   linear      : γ(d) = slope·d + nugget
%   power       : γ(d) = scale·d^exponent + nugget（0 < exponent < 2）
%   gaussian    : γ(d) = psill·(1 − exp(−d² / (4/7·range)²)) + nugget
%   exponential : γ(d) = psill·(1 − exp(−d / (range/3))) + nugget
%   spherical   : γ(d) = psill·(3d/(2·range) − d³/(2·range³)) + nugget（d ≤ range）、psill + nugget（d > range）
%                 球形モデルは説明変数が3次元までなら正定値が保証される（XYRT の5列では保証されない）
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
    case "spherical"
        ratio = min(distance / max(params(2), 1e-12), 1);  % range より遠い点は1（頭打ち）
        values = params(1) * (1.5 * ratio - 0.5 * ratio .^ 3) + nugget;
    otherwise
        error('alignest:variogram', 'バリオグラムは linear・gaussian・power・exponential・spherical のいずれかです: %s', ...
            variogramName);
end
end
