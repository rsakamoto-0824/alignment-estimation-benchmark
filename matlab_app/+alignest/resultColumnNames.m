function [names, headers] = resultColumnNames(includeOverlay)
%RESULTCOLUMNNAMES 評価結果の Excel の「Waferごと」シートの列：結果の表の列名（names）と Excel の見出し（headers）。
%   alignest.exportResults で書き出し、alignest.importResults で読み戻すときに同じ対応を使う。
%   includeOverlay が true なら Overlay 補正の評価の指標の列も入れる。
[metricNames, metricLabels] = alignest.metricNames();
if includeOverlay
    [overlayNames, overlayLabels] = alignest.overlayMetricNames();
    metricNames = [metricNames, overlayNames];
    metricLabels = [metricLabels, overlayLabels];
end
names = ["Operation", "EqpId", "LotID", "Wafer", "DateTime", "plan", "group", "nShots", "criterionI", "criterionD", ...
    "efficiencyI", "efficiencyD", "methodLabel", "methodId", metricNames, ...
    "nTest_X", "nTest_Y", "nOutliers", "edf_X", "edf_Y", "aux_X", "aux_Y", "converged", "seconds", "hyperparameters", "note"];
headers = ["Operation", "EqpId", "LotID", "Wafer", "DateTime", "学習パターン", "列", "学習Shot数", "I基準tr(M⁻¹)", ...
    "D基準det(M)^(-1/p)", "I効率(全計測に対する)", "D効率(全計測に対する)", "手法", "手法の識別子", metricLabels, ...
    "評価点数X", "評価点数Y", "学習から除いた異常値の数", "有効自由度X", "有効自由度Y", "補助値X", "補助値Y", "最適化の収束", ...
    "計算時間[秒]", "超パラメータ", "メモ"];
end
