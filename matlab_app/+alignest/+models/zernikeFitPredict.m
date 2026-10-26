function result = zernikeFitPredict(trainXY, testXY, y, order, options)
%ZERNIKEFITPREDICT Fringe Zernike 多項式（次数 k：Z1〜Z(k+1)²）の最小二乗。座標は Wafer 半径で割った値（ρ ≤ 1）。
%   result = alignest.models.zernikeFitPredict(trainXY, testXY, y, order)
%   result = alignest.models.zernikeFitPredict(..., returnSmoother=true)   % 質的変数の Backfitting 用に
%   当てはめ行列 result.smoother（学習点の値 → 学習点の当てはめ値）と result.predictionMatrix（→ 評価点）も返す
%   （alignest.models.spatialBackfit）。
%   Z_n^m は RMS 正規化した実数値 Zernike 多項式（alignest.basis.zernikeMatrix）、並びは Fringe 番号
%   （alignest.basis.fringeZernikeModes）。XY 多項式（polynomialFitPredict）と同じく、推定行列は特異値分解の擬似逆行列
%   （相対の打ち切り 1e-10）で、学習点が項数より少ないときは最小ノルムの解になる。
%   有効自由度は当てはめ行列のトレース（項数。点が足りないときは階数）。
arguments
    trainXY double
    testXY double
    y double
    order (1, 1) double
    options.returnSmoother (1, 1) logical = false
end
PINV_RELATIVE_TOLERANCE = 1e-10;
modes = alignest.basis.fringeZernikeModes(order);
designTrain = alignest.basis.zernikeMatrix(trainXY(:, 1), trainXY(:, 2), modes);
designTest = alignest.basis.zernikeMatrix(testXY(:, 1), testXY(:, 2), modes);
singularValues = svd(designTrain);
tolerance = 0;
if ~isempty(singularValues)
    tolerance = PINV_RELATIVE_TOLERANCE * max(singularValues);
end
inverse = pinv(designTrain, tolerance);
coefficients = inverse * y(:);
result.prediction = designTest * coefficients;
result.coefficients = coefficients;
result.edf = trace(designTrain * inverse);
result.nCoef = size(modes, 1);
if options.returnSmoother
    result.smoother = designTrain * inverse;
    result.predictionMatrix = designTest * inverse;
end
end
