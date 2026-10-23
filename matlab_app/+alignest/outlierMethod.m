function method = outlierMethod(settings)
%OUTLIERMETHOD 学習データの異常値の判定のしかた（settings.evaluation.outlierMethod。以前の設定は "sigma"）。
%   "sigma"：平均と σ、"mad"：中央値と MAD（alignest.trainingOutliers）。
method = "sigma";
if isfield(settings, "evaluation") && isfield(settings.evaluation, "outlierMethod")
    method = string(settings.evaluation.outlierMethod);
end
end
