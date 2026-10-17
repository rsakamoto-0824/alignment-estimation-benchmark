function [params, cost] = krigingFitVariogram(variogramName, lags, semivariance)
%KRIGINGFITVARIOGRAM 経験バリオグラムにモデルを当てはめる（PyKrige と同じ初期値・範囲・soft_l1 損失）。
%   最小化する値：½ Σ ρ(f_i²)、ρ(z) = 2(√(1+z) − 1)、f_i = モデル − 経験値（SciPy least_squares の soft_l1 と同じ）。
%   Python 版は SciPy の least_squares（信頼領域法）、この版は上下限つき準ニュートン法で解く。
%   soft_l1 の損失は局所解を持つことがあり、解き方の違いで別の局所解に止まる場合がある
%   （模擬データの照合 96 件中 1 件）。そのため PyKrige の初期値に加えて、形のパラメータ（べき指数・range）を
%   いくつか決め、残りの係数（scale・nugget）を最小二乗で合わせた初期値からも解き、
%   損失が最も小さい解を使う（同じ値なら PyKrige の初期値の解）。
variogramName = string(variogramName);
semivarianceMin = min(semivariance);
semivarianceMax = max(max(semivariance), 1e-12);
lagSpan = max(max(lags) - min(lags), 1e-12);
switch variogramName
    case "linear"
        starts = [(semivarianceMax - semivarianceMin) / lagSpan; semivarianceMin];
        lower = [0; 0];
        upper = [Inf; semivarianceMax];
    case "power"
        starts = [(semivarianceMax - semivarianceMin) / lagSpan; 1.1; semivarianceMin];
        lower = [0; 0.001; 0];
        upper = [Inf; 1.999; semivarianceMax];
        shapes = [0.5, 1, 1.5, 1.999];
    otherwise
        starts = [semivarianceMax - semivarianceMin; 0.25 * max(lags); semivarianceMin];
        lower = [0; 0; 0];
        upper = [10 * semivarianceMax; max(lags); semivarianceMax];
        shapes = [0.1, 0.5, 1] * max(lags);
end
if variogramName ~= "linear"
    for shape = shapes
        starts(:, end + 1) = linearStart(variogramName, shape, lags, semivariance, lower, upper); %#ok<AGROW>
    end
end
objective = @(p) softL1Cost(variogramName, p, lags, semivariance);
params = [];
cost = Inf;
for k = 1:size(starts, 2)
    start = min(max(starts(:, k), lower), upper);
    [candidate, candidateCost] = alignest.optim.minimizeBox(objective, start, lower, upper, ...
        maxIterations=1000, gradientTolerance=1e-10, functionTolerance=1e-12);
    if isempty(params) || candidateCost < cost - 1e-12 * max(abs(cost), 1)
        params = candidate;
        cost = candidateCost;
    end
end
end

function [cost, gradient] = softL1Cost(variogramName, params, lags, semivariance)
residual = alignest.models.krigingVariogram(variogramName, params, lags) - semivariance;
cost = sum(sqrt(1 + residual .^ 2) - 1);
weight = residual ./ sqrt(1 + residual .^ 2);
gradient = jacobian(variogramName, params, lags).' * weight;
end

function J = jacobian(variogramName, params, lags)
% モデルの値のパラメータによる微分（列がパラメータ）
d = lags(:);
switch variogramName
    case "linear"
        J = [d, ones(size(d))];
    case "power"
        logD = zeros(size(d));
        logD(d > 0) = log(d(d > 0));
        J = [d .^ params(2), params(1) * d .^ params(2) .* logD, ones(size(d))];
    case "gaussian"
        width = max(params(2) * 4 / 7, 1e-12);
        e = exp(-(d .^ 2) / width^2);
        J = [1 - e, -params(1) * e .* (2 * d .^ 2 / width^3) * (4 / 7), ones(size(d))];
    case "exponential"
        width = max(params(2) / 3, 1e-12);
        e = exp(-d / width);
        J = [1 - e, -params(1) * e .* (d / width^2) / 3, ones(size(d))];
end
end

function start = linearStart(variogramName, shape, lags, semivariance, lower, upper)
% 形のパラメータを固定すると、モデルは scale（または psill）と nugget の1次式になるので最小二乗で合わせる
unitShape = alignest.models.krigingVariogram(variogramName, [1; shape; 0], lags(:));
coefficients = [unitShape, ones(numel(lags), 1)] \ semivariance(:);
start = min(max([coefficients(1); shape; coefficients(2)], lower), upper);
end
