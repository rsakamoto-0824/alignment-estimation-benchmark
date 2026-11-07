function result = rtFitPredict(trainU, trainV, testU, testV, measuredU, measuredV, order)
%RTFITPREDICT RT モデル（K次）の最小二乗。X・Y を同時に当てはめる。座標は Wafer 半径で割った値（点数 × 2）。
%   変位を半径方向 R と接線方向 T に分け、R = ρ·M(x, y)、T = ρ·Θ(x, y) とする。
%   局所倍率マップ M・局所回転マップ Θ をそれぞれ Zernike 多項式（動径次数 n ≤ K）で展開し、
%   並進2項・非対称倍率・直交度の4項を加える（Python 版の RT K次と同じ定義）。XY に換算した最大次数は K+1。
%   trainU / testU は X の計測値がある点、trainV / testV は Y の計測値がある点（X と Y で点が違ってもよい）。
PINV_RELATIVE_TOLERANCE = 1e-10;
designTrain = [rowsOf(trainU, order, 1); rowsOf(trainV, order, 2)];
designTest = [rowsOf(testU, order, 1); rowsOf(testV, order, 2)];
singularValues = svd(designTrain);
tolerance = 0;
if ~isempty(singularValues)
    tolerance = PINV_RELATIVE_TOLERANCE * max(singularValues);
end
inverse = pinv(designTrain, tolerance);
estimate = designTest * (inverse * [measuredU(:); measuredV(:)]);
hat = designTrain * inverse;
nU = size(trainU, 1);
result.predictionU = estimate(1:size(testU, 1));
result.predictionV = estimate(size(testU, 1) + 1:end);
result.edfU = trace(hat(1:nU, 1:nU));
result.edfV = trace(hat(nU + 1:end, nU + 1:end));
result.nCoef = size(designTrain, 2);
end

function rows = rowsOf(points, order, component)
% RT の基底（alignest.basis.rtDesign）の X 方向（1）か Y 方向（2）の行
[rowsU, rowsV] = alignest.basis.rtDesign(points, order);
rows = rowsU;
if component == 2
    rows = rowsV;
end
end
