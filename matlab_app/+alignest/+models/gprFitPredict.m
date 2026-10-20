function result = gprFitPredict(trainFeatures, testFeatures, groups, y, kernelName, factorMode, factors, options)
%GPRFITPREDICT 質的変数の扱い方 factorMode で GPR を当てはめ、評価点を推定する。
%   factors は質的変数の水準（列ベクトル。使えない変数は空）：
%     scanTrain/Test（Scan方向）、markTrain/Test（Mark番号）、任意の rowTrain/Test（Shot行の奇偶）
%   options（省略可）
%     maxIterations         : 最適化の反復の上限（既定 300）
%     backfitMaxIterations  : Backfitting の反復の上限（既定 20）
%     backfitTolerance      : Backfitting の効果の変化の閾値 [nm]（既定 1e-3）
%     fixedLogParams        : 超パラメータを固定する（動作確認用。空なら推定する）
%   基底関数と質的変数のカーネル項の作り方は gprModeSetup。
arguments
    trainFeatures double
    testFeatures double
    groups double
    y (:, 1) double
    kernelName (1, 1) string
    factorMode (1, 1) string
    factors struct
    options.maxIterations (1, 1) double = 300
    options.backfitMaxIterations (1, 1) double = 20
    options.backfitTolerance (1, 1) double = 1e-3
    options.fixedLogParams double = []
end
BACKFIT_PARAM_TOLERANCE = 1e-3;
[gp, basisTrain, basisTest, factorTrain, factorTest] = alignest.models.gprModeSetup(trainFeatures, testFeatures, ...
    groups, kernelName, factorMode, factors, options.maxIterations);

if factorMode ~= "backfit"
    if isempty(options.fixedLogParams)
        fit = alignest.models.gprFit(gp, y, basisTrain);
    else
        fit = alignest.models.gprCondition(gp, options.fixedLogParams, y, basisTrain);
    end
    prediction = alignest.models.gprPredict(gp, fit, basisTest);
    result = packResult(gp, fit, prediction, 0, true, fit.converged, fit.beta(2:end));
    return
end

% Backfitting：質的変数の列は学習点で中心化し、定数は GPR 側に持たせる（識別のため）
center = mean(factorTrain, 1);
centered = factorTrain - center;
onesTrain = ones(size(trainFeatures, 1), 1);
jointTrain = [onesTrain, centered];
jointTest = [ones(size(testFeatures, 1), 1), factorTest - center];
if isempty(centered)
    effects = zeros(0, 1);
else
    effects = lsqminnorm(centered, y - mean(y));  % 初期値：計測値の群平均（最小二乗）
end
logParams = options.fixedLogParams;
converged = false;
optimizerConverged = true;
lastNll = NaN;
iteration = 0;
for iteration = 1:options.backfitMaxIterations
    % GPR の段：質的変数の効果を除いた残差で超パラメータを推定し直す（前回の値から開始）
    if isempty(options.fixedLogParams)
        fit = alignest.models.gprFit(gp, y - centered * effects, onesTrain, logParams);
        if isempty(logParams)
            paramsChange = Inf;
        else
            paramsChange = max(abs(fit.logParams - logParams));
        end
        logParams = fit.logParams;
        optimizerConverged = fit.converged;
        lastNll = fit.nll;
    else
        paramsChange = 0;
    end
    % 質的変数の段：超パラメータを固定した交互の当てはめの収束値（質的変数を基底に入れた一般化最小二乗の解）
    joint = alignest.models.gprCondition(gp, logParams, y, jointTrain);
    newEffects = joint.beta(2:end);
    change = sqrt(mean((centered * (newEffects - effects)) .^ 2));
    if isempty(change) || isnan(change)
        change = 0;
    end
    effects = newEffects;
    if change < options.backfitTolerance && paramsChange < BACKFIT_PARAM_TOLERANCE
        converged = true;
        break
    end
end
final = alignest.models.gprCondition(gp, logParams, y, jointTrain);
final.nll = lastNll;
prediction = alignest.models.gprPredict(gp, final, jointTest);
result = packResult(gp, final, prediction, iteration, converged, optimizerConverged, final.beta(2:end));
end

function result = packResult(gp, fit, prediction, nBackfit, backfitConverged, optimizerConverged, effects)
logParams = fit.logParams(:);
result.prediction = prediction;
result.edf = fit.edf;
result.logParams = logParams;
result.nll = fit.nll;
result.nBackfitIterations = nBackfit;
result.backfitConverged = backfitConverged;
result.optimizerConverged = optimizerConverged;
result.factorEffects = effects;
result.lengthScales = exp(logParams(1:gp.nLength)).';
result.signalStd = exp(logParams(gp.nLength + 1));
result.alpha = NaN;
if gp.hasAlpha
    result.alpha = exp(logParams(gp.nLength + 2));
end
result.noiseStd = exp(logParams(end));
result.tau = struct();
for k = 1:gp.nCategorical
    result.tau.(gp.categorical(k).name) = exp(logParams(gp.categoricalOffset + k - 1));
end
end
