function [names, labels] = metricNames()
%METRICNAMES 結果の表に入れる指標の列名と、画面に出す名前。
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
end
