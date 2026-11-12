function variance = gprPredictVariance(gp, fit, trainBasis, testBasis)
%GPRPREDICTVARIANCE GPR の評価点での推定の分散（予測分布の分散。推定した面のばらつき）[値の単位の2乗]。
%   variance = alignest.models.gprPredictVariance(gp, fit, trainBasis, testBasis)
%   gp：alignest.models.gprModeSetup の結果、fit：ハイパーパラメータと β（alignest.models.gprCondition の結果）、
%   trainBasis・testBasis：学習点・評価点の基底関数の行列 H・H*（平均の項。gprPredict と同じ）。
%   基底関数の係数 β も推定する GPR の予測分散（Rasmussen & Williams (2006) 式 2.42）：
%     V(x*) = k(x*, x*) − k*' K_y⁻¹ k* + r' (H' K_y⁻¹ H)⁻¹ r、 r = h* − H' K_y⁻¹ k*
%   K_y = K + σn² I（学習点どうしのカーネル + 計測のばらつき）、k* は評価点と学習点のカーネル、k(x*, x*) は評価点の事前分散
%   （σf² + 質的変数の項の分散 τ² の和。距離 0 のカーネルの値）。計測のばらつき σn² は含めない（推定した面の分散）。
%   数値の安定のため、K_y の対角に gprCondition と同じ量を足す。丸め誤差で負になった値は 0 にする。
n = gp.nTrain;
logParams = fit.logParams(:);
[kernel, ~, noiseVar] = alignest.models.gprKernel(gp, logParams, "train");
covariance = kernel + noiseVar * eye(n);
jitter = 1e-10 * trace(covariance) / n;
[upperFactor, failed] = chol(covariance + jitter * eye(n));
while failed
    jitter = max(jitter * 100, 1e-12);
    [upperFactor, failed] = chol(covariance + jitter * eye(n));
end
cross = alignest.models.gprKernel(gp, logParams, "cross");   % 評価点 × 学習点
solved = upperFactor.' \ cross.';                             % L⁻¹ k*（列が評価点）
reduction = sum(solved .^ 2, 1).';                            % k*' K_y⁻¹ k*
signalVar = exp(2 * logParams(gp.nLength + 1));
categoricalVar = exp(2 * logParams(gp.categoricalOffset:gp.categoricalOffset + gp.nCategorical - 1));
prior = signalVar + sum(categoricalVar);                      % k(x*, x*)
variance = prior - reduction;
if ~isempty(trainBasis)
    % 基底関数の係数 β の推定のばらつきの分
    kinvH = upperFactor \ (upperFactor.' \ trainBasis);       % K_y⁻¹ H
    gram = trainBasis.' * kinvH;                              % H' K_y⁻¹ H
    residualBasis = testBasis.' - kinvH.' * cross.';          % r（基底の数 × 評価点）
    warningState = [warning('off', 'MATLAB:nearlySingularMatrix'), warning('off', 'MATLAB:singularMatrix')];
    cleanup = onCleanup(@() warning(warningState));
    variance = variance + sum(residualBasis .* (gram \ residualBasis), 1).';
end
variance = max(variance, 0);
end
