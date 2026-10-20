function result = tpsFitPredict(model, y, options)
%TPSFITPREDICT GCV で λ を選んで TPS を当てはめ、評価点を推定する（前計算は tpsSetup）。
arguments
    model struct
    y (:, 1) double
    options.returnSmoother (1, 1) logical = false
end
result = alignest.models.radialFitPredict(model, y, options.returnSmoother);
end
