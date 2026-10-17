function [value, gradient] = gprObjective(gp, logParams, y, basis)
%GPROBJECTIVE 負の対数周辺尤度（平均の係数 β を一般化最小二乗で消去したプロファイル尤度）とその勾配。
%   fitrgp の既定（FitMethod = 'exact'）と同じ基準。行列が正定値にならないときは大きな値と勾配0を返す。
FAILED_OBJECTIVE = 1e20;
y = y(:);
logParams = logParams(:);
n = gp.nTrain;
[kernel, grads, noiseVar] = alignest.models.gprKernel(gp, logParams, "train");
covariance = kernel + noiseVar * eye(n);
[upperFactor, failed] = chol(covariance);
if failed
    value = FAILED_OBJECTIVE;
    gradient = zeros(size(logParams));
    return
end
inverseFactor = upperFactor \ eye(n);
covarianceInverse = inverseFactor * inverseFactor.';
kinvH = covarianceInverse * basis;
kinvY = covarianceInverse * y;
gram = basis.' * kinvH;
% 特異に近いだけなら解を使う（Python 版の numpy.linalg.solve と同じ）。完全に特異なら Inf になるので失敗にする
warningState = [warning('off', 'MATLAB:nearlySingularMatrix'), warning('off', 'MATLAB:singularMatrix')];
cleanup = onCleanup(@() warning(warningState));
beta = gram \ (basis.' * kinvY);
if any(~isfinite(beta))
    value = FAILED_OBJECTIVE;
    gradient = zeros(size(logParams));
    return
end
a = kinvY - kinvH * beta;
residual = y - basis * beta;
logDet = 2 * sum(log(diag(upperFactor)));
value = 0.5 * (residual.' * a) + 0.5 * logDet + 0.5 * n * log(2 * pi);
weight = covarianceInverse - a * a.';
gradient = zeros(numel(logParams), 1);
for k = 1:size(grads, 3)
    gradient(k) = 0.5 * sum(weight .* grads(:, :, k), 'all');
end
gradient(end) = noiseVar * trace(weight);
if ~isfinite(value) || any(~isfinite(gradient))
    value = FAILED_OBJECTIVE;
    gradient = zeros(size(logParams));
end
end
