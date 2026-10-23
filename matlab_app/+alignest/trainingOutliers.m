function [outlier, stats] = trainingOutliers(marks, inTrain, sigmaFactor, method)
%TRAININGOUTLIERS 学習データの異常値：中心から n × ばらつき を超えて離れた Mark（論理ベクトル）。
%   [outlier, stats] = alignest.trainingOutliers(unit.marks, inTrain, n)            % 平均と σ（既定）
%   [outlier, stats] = alignest.trainingOutliers(unit.marks, inTrain, n, "mad")     % 中央値と MAD
%   inTrain は学習に使う Mark（論理ベクトル）。中心とばらつきは、この Wafer・この学習パターンの学習点
%   （その軸が有効な Mark）から X・Y 別に1回だけ求める。
%   - method = "sigma"：中心 = 平均、ばらつき = σ（標本標準偏差）
%   - method = "mad"  ：中心 = 中央値、ばらつき = 1.4826 × MAD（MAD = 中央値からの差の絶対値の中央値。
%                       1.4826 を掛けると、正規分布では σ と同じ大きさになる。外れ値に引きずられにくい）
%   |値 − 中心| > n × ばらつき の軸が1つでもあれば、その Mark を異常値とし、X・Y の両方の学習データから除く。
%   stats.center・stats.spread・stats.count は [X, Y] の中心・ばらつき・点数、stats.outlierAxis は軸ごとの判定
%   （Mark × 2）。stats.mean・stats.std は以前の呼び出しとの互換のため、center・spread と同じ値。
arguments
    marks struct
    inTrain logical
    sigmaFactor (1, 1) double {mustBePositive, mustBeFinite}
    method (1, 1) string {mustBeMember(method, ["sigma", "mad"])} = "sigma"
end
MAD_TO_SIGMA = 1.4826;   % 正規分布で MAD を σ に直す係数（1 / Φ⁻¹(3/4)）
axisNames = ["X", "Y"];
inTrain = inTrain(:);
stats.center = nan(1, 2);
stats.spread = nan(1, 2);
stats.count = zeros(1, 2);
stats.outlierAxis = false(numel(inTrain), 2);
stats.method = method;
for k = 1:2
    use = inTrain & marks.("valid" + axisNames(k));
    values = marks.("meas" + axisNames(k));
    stats.count(k) = nnz(use);
    if stats.count(k) < 2
        continue   % 1点ではばらつきが決まらないので判定しない
    end
    if method == "mad"
        stats.center(k) = median(values(use));
        stats.spread(k) = MAD_TO_SIGMA * median(abs(values(use) - stats.center(k)));
    else
        stats.center(k) = mean(values(use));
        stats.spread(k) = std(values(use));
    end
    stats.outlierAxis(:, k) = use & abs(values - stats.center(k)) > sigmaFactor * stats.spread(k);
end
stats.mean = stats.center;
stats.std = stats.spread;
outlier = any(stats.outlierAxis, 2);
end
