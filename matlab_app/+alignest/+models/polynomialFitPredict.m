function result = polynomialFitPredict(trainXY, testXY, y, order)
%POLYNOMIALFITPREDICT XY N次多項式（x^a y^b、a + b ≤ N）の最小二乗。座標は Wafer 半径で割った値。
%   推定行列は特異値分解の擬似逆行列（相対の打ち切り 1e-10、Python 版の numpy.linalg.pinv と同じ）。
%   有効自由度は当てはめ行列のトレース（係数の数。点が足りないときは階数）。
PINV_RELATIVE_TOLERANCE = 1e-10;
designTrain = alignest.basis.polynomialDesign(trainXY(:, 1), trainXY(:, 2), order);
designTest = alignest.basis.polynomialDesign(testXY(:, 1), testXY(:, 2), order);
inverse = pseudoInverse(designTrain, PINV_RELATIVE_TOLERANCE);
result.prediction = designTest * (inverse * y(:));
result.edf = trace(designTrain * inverse);
result.nCoef = size(designTrain, 2);
end

function inverse = pseudoInverse(matrix, relativeTolerance)
singularValues = svd(matrix);
tolerance = 0;
if ~isempty(singularValues)
    tolerance = relativeTolerance * max(singularValues);
end
inverse = pinv(matrix, tolerance);
end
