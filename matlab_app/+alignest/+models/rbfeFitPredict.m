function result = rbfeFitPredict(model, y)
%RBFEFITPREDICT RBFe（仮）：領域ごとに GCV で λ を選んで TPS を当てはめ、重みでつなぎ合わせて評価点を推定する。
%   result = alignest.models.rbfeFitPredict(model, y)   % model は alignest.models.rbfeSetup の結果
%   学習点での当てはめ値は Σ_k W_k(x) f_k(x)（f_k は領域 k の TPS）。全体の平滑化行列 S = Σ_k diag(W_k) E_k S_k E_kᵀ
%   （S_k は領域の TPS の平滑化行列、E_k は領域の学習点を選ぶ行列）から有効自由度 trace(S) を求める。
%   result.prediction：評価点の推定値、result.edf：有効自由度、result.log10Lambda：領域の log10 λ の平均、
%   result.log10Lambdas：領域ごとの log10 λ、result.nRegions：使った領域の数、
%   result.smoother・result.predictionMatrix：学習点・評価点の推定値を y から求める行列（Backfitting で使う）。
y = y(:);
smoother = zeros(model.nTrain);
predictionMatrix = zeros(model.nTest, model.nTrain);
log10Lambdas = zeros(model.nRegions, 1);
for k = 1:model.nRegions
    region = model.regions(k);
    local = alignest.models.radialFitPredict(region.tps, y(region.train), true);
    log10Lambdas(k) = local.log10Lambda;
    smoother(region.train, region.train) = smoother(region.train, region.train) + ...
        model.weightTrain(region.train, k) .* local.smoother;
    predictionMatrix(region.test, region.train) = predictionMatrix(region.test, region.train) + ...
        model.weightTest(region.test, k) .* local.predictionMatrix;
end
result.prediction = predictionMatrix * y;
result.edf = trace(smoother);
result.log10Lambda = mean(log10Lambdas);
result.log10Lambdas = log10Lambdas;
result.nRegions = model.nRegions;
result.smoother = smoother;
result.predictionMatrix = predictionMatrix;
end
