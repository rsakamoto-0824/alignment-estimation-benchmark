function [names, headers] = estimateColumnNames(sheet)
%ESTIMATECOLUMNNAMES 推定値の Excel の列：推定値の表の列名（names）と Excel の見出し（headers）。
%   [names, headers] = alignest.estimateColumnNames("points")    % 「推定値」シート（alignest.collectEstimates の表）
%   [names, headers] = alignest.estimateColumnNames("overlay")   % 「Overlay残差」シート
%   alignest.exportEstimates で書き出し、alignest.importEstimates で読み戻すときに同じ対応を使う。
%   「推定値」シートでは、ここに無い列（Operation・Wafer・shotNo など）は列名のまま、
%   質的変数に選んだその他の列は「質的変数:<列名>」のまま書く。
arguments
    sheet (1, 1) string {mustBeMember(sheet, ["points", "overlay"])}
end
if sheet == "points"
    names = ["plan", "group", "methodLabel", "methodId", "direction", "shotRowParity", "x", "y", "r", "role", ...
        "measX", "estimateX", "residualX", "measY", "estimateY", "residualY"];
    headers = ["学習パターン", "列", "手法", "手法の識別子", "Direction", "Shot行(1=奇数,2=偶数)", "x[mm]", "y[mm]", ...
        "半径[mm]", "区分", "計測値X[nm]", "推定値X[nm]", "残差X[nm]", "計測値Y[nm]", "推定値Y[nm]", "残差Y[nm]"];
else
    names = ["Operation", "EqpId", "LotID", "Wafer", "DateTime", "plan", "group", "methodLabel", "methodId", "shotNo", ...
        "markNo", "x", "y", "role", "residualActualX", "residualActualY", "residualEstimatedX", "residualEstimatedY", ...
        "changeX", "changeY"];
    headers = ["Operation", "EqpId", "LotID", "Wafer", "DateTime", "学習パターン", "列", "手法", "手法の識別子", ...
        "shotNo", "markNo", "x[mm]", "y[mm]", "Shotの区分", "実測値で補正した残差X[nm]", "実測値で補正した残差Y[nm]", ...
        "推定値で補正した残差X[nm]", "推定値で補正した残差Y[nm]", "推定による変化X[nm]", "推定による変化Y[nm]"];
end
end
