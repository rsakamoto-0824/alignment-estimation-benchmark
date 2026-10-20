function result = spatialBackfit(fitSpatial, y, factorsTrain, factorsTest, options)
%SPATIALBACKFIT TPS・Kriging の空間成分と質的変数の固定効果を交互に推定。
% 平滑化・バリオグラムを残差から更新し、その固定時の内側の交互反復は
% C'*(I-S)*(y-C*beta)=0 の解で収束まで進める（GPR の Backfitting と同じ考え方）。
% 自由度は最終パラメータを固定した合成平滑化行列の trace。選択の不確実性は含めない。
arguments
    fitSpatial function_handle
    y (:, 1) double
    factorsTrain double
    factorsTest double
    options.maxIterations (1, 1) double {mustBeInteger, mustBePositive} = 20
    options.tolerance (1, 1) double {mustBeFinite, mustBePositive} = 1e-3
end
n = numel(y);
[design, designTest] = alignest.basis.independentColumns( ...
    [ones(n, 1), factorsTrain], [ones(size(factorsTest, 1), 1), factorsTest]);
center = mean(design(:, 2:end), 1);
codes = design(:, 2:end) - center;
codesTest = designTest(:, 2:end) - center;
if isempty(codes)
    result = fitSpatial(y);
    result.backfitConverged = true;
    result.nBackfitIterations = 0;
    result.factorEffects = zeros(0, 1);
    return
end
effects = codes \ (y - mean(y));
previousFitted = [];
converged = false;
for iteration = 1:options.maxIterations
    spatial = fitSpatial(y - codes * effects);
    residualOperator = eye(n) - spatial.smoother;
    gram = codes.' * residualOperator * codes;
    % 空間モデルの非罰則項と一致する分類は識別不能なので、微小な数値誤差を逆数にしない。
    rankTolerance = max(size(gram)) * eps(max(norm(codes.' * codes, 2), 1));
    effectOperator = pinv(gram, rankTolerance) * (codes.' * residualOperator);
    nextEffects = effectOperator * y;
    fitted = spatial.smoother * y + residualOperator * codes * nextEffects;
    change = sqrt(mean((codes * (nextEffects - effects)).^2));
    fitChange = Inf;
    if ~isempty(previousFitted)
        fitChange = sqrt(mean((fitted - previousFitted).^2));
    end
    effects = nextEffects;
    previousFitted = fitted;
    if max(change, fitChange) < options.tolerance
        converged = true;
        break
    end
end
result = spatial;
result.prediction = spatial.predictionMatrix * y + (codesTest - spatial.predictionMatrix * codes) * effects;
result.smoother = spatial.smoother + residualOperator * codes * effectOperator;
result.predictionMatrix = spatial.predictionMatrix + (codesTest - spatial.predictionMatrix * codes) * effectOperator;
result.edf = trace(result.smoother);
result.factorEffects = effects;
result.backfitConverged = converged;
result.nBackfitIterations = iteration;
if any(~isfinite(result.prediction)) || ~isfinite(result.edf)
    error('alignest:spatialBackfit', 'Backfitting の推定値を計算できませんでした。学習点と質的変数の組を確認してください。');
end
end
