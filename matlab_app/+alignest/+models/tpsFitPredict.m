function result = tpsFitPredict(model, y)
%TPSFITPREDICT GCV で λ を選んで TPS を当てはめ、評価点を推定する（前計算は tpsSetup）。
y = y(:);
projected = model.basis.' * y;  % Uᵀ Q₂ᵀ y
shrink = model.nLambdaGrid ./ (model.eigval.' + model.nLambdaGrid);  % 候補数 × (n − k)
rss = sum((shrink .* projected.') .^ 2, 2);
traceResidual = sum(shrink, 2);
gcv = model.n * rss ./ traceResidual .^ 2;
[~, best] = min(gcv);
nLambda = model.nLambdaGrid(best);
weights = model.basis * (projected ./ (model.eigval + nLambda));
polyTarget = y - model.phi * weights - nLambda * weights;
coefficients = model.r1 \ (model.q1.' * polyTarget);
result.prediction = model.phiTest * weights + model.polyTest * coefficients;
result.edf = model.n - traceResidual(best);
result.log10Lambda = log10(nLambda);
end
