function result = rbfFitPredict(model, y)
%RBFFITPREDICT 広がりと平滑化を学習データの GCV だけで選ぶ。
best = Inf;
for k = 1:numel(model.candidates)
    candidate = alignest.models.radialFitPredict(model.candidates{k}, y);
    if candidate.gcv < best
        result = candidate;
        result.lengthScale = model.lengthScales(k);
        best = candidate.gcv;
    end
end
if ~isfinite(best)
    error('alignest:rbfFit', 'RBF の平滑化を選べませんでした。学習点と計測値を確認してください。');
end
end
