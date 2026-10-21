function [outlier, stats] = trainingOutliers(marks, inTrain, sigmaFactor)
%TRAININGOUTLIERS 学習データの異常値：平均から sigmaFactor × σ を超えて離れた Mark（論理ベクトル）。
%   [outlier, stats] = alignest.trainingOutliers(unit.marks, inTrain, sigmaFactor)
%   inTrain は学習 Shot の Mark（論理ベクトル）。平均と σ（標本標準偏差）は、この Wafer・この学習パターンの
%   学習点（その軸が有効な Mark）から X・Y 別に1回だけ求める。|値 − 平均| > sigmaFactor × σ の軸が1つでもあれば、
%   その Mark を異常値とし、X・Y の両方の学習データから除く。
%   stats.mean・stats.std・stats.count は [X, Y] の平均・σ・点数、stats.outlierAxis は軸ごとの判定（Mark × 2）。
arguments
    marks struct
    inTrain logical
    sigmaFactor (1, 1) double {mustBePositive, mustBeFinite}
end
axisNames = ["X", "Y"];
inTrain = inTrain(:);
stats.mean = nan(1, 2);
stats.std = nan(1, 2);
stats.count = zeros(1, 2);
stats.outlierAxis = false(numel(inTrain), 2);
for k = 1:2
    use = inTrain & marks.("valid" + axisNames(k));
    values = marks.("meas" + axisNames(k));
    stats.count(k) = nnz(use);
    if stats.count(k) < 2
        continue   % 1点では σ が決まらないので判定しない
    end
    stats.mean(k) = mean(values(use));
    stats.std(k) = std(values(use));
    stats.outlierAxis(:, k) = use & abs(values - stats.mean(k)) > sigmaFactor * stats.std(k);
end
outlier = any(stats.outlierAxis, 2);
end
