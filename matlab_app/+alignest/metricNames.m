function [names, labels] = metricNames(includeTiming, includeOverlay)
%METRICNAMES 結果の表に入れる指標の列名と、画面に出す名前。
%   includeTiming が true なら、処理時間（seconds：1 枚の X・Y の推定にかかった秒数）も加える（既定 false）。
%   includeOverlay が true なら、Overlay 補正の評価の指標（alignest.overlayMetricNames）も加える（既定 false）。
if nargin < 1
    includeTiming = false;
end
if nargin < 2
    includeOverlay = false;
end
kinds = ["R2", "adjR2", "RMSE", "MAE"];
kindLabels = ["R²", "調整済み R²", "RMSE [nm]", "MAE [nm]"];
axisNames = ["X", "Y", "XY"];
axisLabels = ["X", "Y", "X・Y 合計"];
names = strings(1, 0);
labels = strings(1, 0);
for a = 1:numel(axisNames)
    for k = 1:numel(kinds)
        names(end + 1) = kinds(k) + "_" + axisNames(a); %#ok<AGROW>
        labels(end + 1) = kindLabels(k) + "（" + axisLabels(a) + "）"; %#ok<AGROW>
    end
end
names = [names, "RMSE_XY_outer", "RMSE_XY_inner"];
labels = [labels, "RMSE [nm]（外周）", "RMSE [nm]（内側）"];
if includeOverlay
    [overlayNames, overlayLabels] = alignest.overlayMetricNames();
    names = [names, overlayNames];
    labels = [labels, overlayLabels];
end
if includeTiming
    names = [names, "seconds"];
    labels = [labels, "処理時間 [秒/枚]"];
end
end
