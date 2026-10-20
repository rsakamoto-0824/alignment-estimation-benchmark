function result = radialFitPredict(model, y, returnSmoother)
%RADIALFITPREDICT 学習データの GCV で平滑化を選び、TPS または RBF を推定する。
if nargin < 3
    returnSmoother = false;
end
y = y(:);
projected = model.basis.' * y;
shrink = model.nLambdaGrid ./ (model.eigval.' + model.nLambdaGrid);
rss = sum((shrink .* projected.') .^ 2, 2);
traceResidual = sum(shrink, 2);
gcv = model.n * rss ./ traceResidual .^ 2;
[result.gcv, best] = min(gcv);
nLambda = model.nLambdaGrid(best);
weights = model.basis * (projected ./ (model.eigval + nLambda));
polyTarget = y - model.phi * weights - nLambda * weights;
coefficients = model.r1 \ (model.q1.' * polyTarget);
result.prediction = model.phiTest * weights + model.polyTest * coefficients;
result.edf = model.n - traceResidual(best);
result.log10Lambda = log10(nLambda);
if returnSmoother
    weightMatrix = (model.basis ./ (model.eigval + nLambda).') * model.basis.';
    polynomialMatrix = model.r1 \ (model.q1.' * (eye(model.n) - (model.phi + nLambda * eye(model.n)) * weightMatrix));
    result.smoother = eye(model.n) - nLambda * weightMatrix;
    result.predictionMatrix = model.phiTest * weightMatrix + model.polyTest * polynomialMatrix;
end
end
