function result = krigingFitPredict(model, y, options)
%KRIGINGFITPREDICT バリオグラムを当てはめ、Kriging で評価点を推定する（前計算は krigingSetup）。
%   推定点は計測点と重ならないので、ナゲットを測定誤差とみなしても厳密補間とみなしても重みは同じになる。
%   有効自由度は、ナゲットを測定誤差とみなした形の学習点の平滑化行列のトレース。
%   ナゲットが0に近い Gaussian バリオグラムは連立方程式が壊れるため、ナゲットに
%   バリオグラムの最大値の 1e-6 倍を足す（Python 版と同じ数値安定化）。
%   options.fixedParams を与えるとバリオグラムを当てはめずにその値を使う（動作確認用）。
arguments
    model struct
    y (:, 1) double
    options.fixedParams double = []
    options.returnSmoother (1, 1) logical = false
end
JITTER_RELATIVE = 1e-6;
if model.krigingType == "universal"
    residual = y - model.driftBasis * (model.driftBasis.' * y);
else
    residual = y;
end
if isempty(options.fixedParams)
    [lags, semivariance] = alignest.models.krigingEmpiricalVariogram(model, residual);
    params = alignest.models.krigingFitVariogram(model.variogramName, lags, semivariance);
else
    params = options.fixedParams(:);
end
gammaTrain = alignest.models.krigingVariogram(model.variogramName, params, model.distance, false);
nugget = params(end) + JITTER_RELATIVE * max(max(gammaTrain(:)) + params(end), 1e-12);
gamma = gammaTrain - nugget * eye(model.n);
gammaTest = alignest.models.krigingVariogram(model.variogramName, params, model.distanceTest, false);
k = size(model.drift, 2);
system = [gamma, model.drift; model.drift.', zeros(k)];
warningState = [warning('off', 'MATLAB:nearlySingularMatrix'), warning('off', 'MATLAB:singularMatrix')];
cleanup = onCleanup(@() warning(warningState));
[lowerFactor, upperFactor, permutation] = lu(system);
solve = @(rhs) upperFactor \ (lowerFactor \ (permutation * rhs));
solution = solve([y; zeros(k, 1)]);
if any(~isfinite(solution))
    inverse = pinv(system);
    solve = @(rhs) inverse * rhs;
    solution = solve([y; zeros(k, 1)]);
end
% 対称な連立方程式なので、推定値 = [γ₀; f₀]ᵀ · system⁻¹ · [y; 0]
result.prediction = gammaTest * solution(1:model.n) + model.driftTest * solution(model.n + 1:end);
weights = solve([eye(model.n); zeros(k, model.n)]);
smoother = gammaTrain * weights(1:model.n, :) + model.drift * weights(model.n + 1:end, :);
result.edf = trace(smoother);
result.params = params;
result.nugget = params(end);
if options.returnSmoother
    % 学習点でも対角をゼロにせず、ナゲットを測定誤差として空間成分を平滑化する。
    result.smoother = smoother;
    result.predictionMatrix = [gammaTest, model.driftTest] * weights;
end
end
