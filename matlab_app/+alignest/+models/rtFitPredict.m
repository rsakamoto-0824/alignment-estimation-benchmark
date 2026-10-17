function result = rtFitPredict(trainU, trainV, testU, testV, measuredU, measuredV, order)
%RTFITPREDICT RT モデル（K次）の最小二乗。X・Y を同時に当てはめる。座標は Wafer 半径で割った値（点数 × 2）。
%   変位を半径方向 R と接線方向 T に分け、R = ρ·M(x, y)、T = ρ·Θ(x, y) とする。
%   局所倍率マップ M・局所回転マップ Θ をそれぞれ Zernike 多項式（動径次数 n ≤ K）で展開し、
%   並進2項・非対称倍率・直交度の4項を加える（Python 版の RT K次と同じ定義）。XY に換算した最大次数は K+1。
%   trainU / testU は X の計測値がある点、trainV / testV は Y の計測値がある点（X と Y で点が違ってもよい）。
PINV_RELATIVE_TOLERANCE = 1e-10;
designTrain = [rtRows(trainU, order, "u"); rtRows(trainV, order, "v")];
designTest = [rtRows(testU, order, "u"); rtRows(testV, order, "v")];
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

function rows = rtRows(points, order, component)
% RT の基底を XY 変位の片方（u = X 方向、v = Y 方向）で書いた行
x = points(:, 1);
y = points(:, 2);
ones_ = ones(size(x));
zeros_ = zeros(size(x));
zernike = alignest.basis.zernikeMatrix(x, y, alignest.basis.zernikeModes(order));
if component == "u"
    fixed = [ones_, zeros_, x, y];   % 並進x、並進y、非対称倍率、直交度
    radial = x .* zernike;           % R = ρ·Z → (u, v) = Z·(x, y)
    tangential = -y .* zernike;      % T = ρ·Z → (u, v) = Z·(−y, x)
else
    fixed = [zeros_, ones_, -y, x];
    radial = y .* zernike;
    tangential = x .* zernike;
end
rows = [fixed, radial, tangential];
end
