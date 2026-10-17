function fit = gprCondition(gp, logParams, y, basis)
%GPRCONDITION 超パラメータを固定して β・K_y⁻¹(y − Hβ)・有効自由度を求める。
%   有効自由度は学習点の当てはめ行列 S = I − σn² P のトレース（P = K_y⁻¹ − K_y⁻¹H(HᵀK_y⁻¹H)⁻¹HᵀK_y⁻¹）。
%   数値の安定のため、K_y の対角に trace(K_y)/n の 1e-10 倍を足す（Python 版と同じ）。
y = y(:);
logParams = logParams(:);
n = gp.nTrain;
[kernel, ~, noiseVar] = alignest.models.gprKernel(gp, logParams, "train");
covariance = kernel + noiseVar * eye(n);
jitter = 1e-10 * trace(covariance) / n;
[upperFactor, failed] = chol(covariance + jitter * eye(n));
while failed
    % 丸め誤差で正定値にならないときだけ、足す量を増やす
    jitter = max(jitter * 100, 1e-12);
    [upperFactor, failed] = chol(covariance + jitter * eye(n));
end
inverseFactor = upperFactor \ eye(n);
covarianceInverse = inverseFactor * inverseFactor.';
kinvH = covarianceInverse * basis;
gram = basis.' * kinvH;
warningState = [warning('off', 'MATLAB:nearlySingularMatrix'), warning('off', 'MATLAB:singularMatrix')];
cleanup = onCleanup(@() warning(warningState));
beta = gram \ (kinvH.' * y);
a = covarianceInverse * (y - basis * beta);
traceP = trace(covarianceInverse) - trace(gram \ (kinvH.' * kinvH));
fit = struct("logParams", logParams, "beta", beta, "alphaVector", a, ...
    "edf", n - noiseVar * traceP, "nll", NaN, "converged", true, "nEvaluations", 0);
end
