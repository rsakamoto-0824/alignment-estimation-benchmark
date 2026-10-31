function [columnX, columnY, valueLabel] = highOrderValueColumns(value)
%HIGHORDERVALUECOLUMNS Shot 高次補正の結果の点の表（alignest.shotHighOrder の result.points）で、書き出す値の列と名前。
%   [columnX, columnY, valueLabel] = alignest.highOrderValueColumns(value)
%   value："residual"（高次補正の残差）・"correction"（補正量）・"linear"（Shot ごとの1次（k1〜k6）で補正した残差）・
%   "value"（補正前の値）。
arguments
    value (1, 1) string {mustBeMember(value, ["residual", "correction", "linear", "value"])}
end
switch value
    case "residual"
        [columnX, columnY, valueLabel] = deal("residualX", "residualY", "高次補正の残差");
    case "correction"
        [columnX, columnY, valueLabel] = deal("correctionX", "correctionY", "補正量");
    case "linear"
        [columnX, columnY, valueLabel] = deal("linearResidualX", "linearResidualY", "Shot ごとの1次で補正した残差");
    otherwise
        [columnX, columnY, valueLabel] = deal("valueX", "valueY", "補正前の値");
end
end
