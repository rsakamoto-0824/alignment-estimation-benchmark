function result = rbfFitPredict(model, y, options)
%RBFFITPREDICT 広がりと平滑化を学習データの GCV だけで選ぶ。
%   options.returnSmoother が true なら、選んだ広がり・平滑化での平滑化行列と推定行列も返す
%   （質的変数の Backfitting で使う。alignest.models.spatialBackfit を参照）。
arguments
    model struct
    y (:, 1) double
    options.returnSmoother (1, 1) logical = false
end
best = Inf;
bestIndex = 0;
for k = 1:numel(model.candidates)
    candidate = alignest.models.radialFitPredict(model.candidates{k}, y);
    if candidate.gcv < best
        result = candidate;
        bestIndex = k;
        best = candidate.gcv;
    end
end
if ~isfinite(best)
    error('alignest:rbfFit', 'RBF の平滑化を選べませんでした。学習点と計測値を確認してください。');
end
if options.returnSmoother
    result = alignest.models.radialFitPredict(model.candidates{bestIndex}, y, true);
end
result.lengthScale = model.lengthScales(bestIndex);
end
