function [values, keys, labels] = explanatoryValues(estimates, units, unitLabels)
%EXPLANATORYVALUES 推定値の表（alignest.collectEstimates）の点ごとの説明変数（残差の傾向を調べる横軸）。
%   [values, keys, labels] = alignest.explanatoryValues(estimates, units, unitLabels)
%   values は点 × 説明変数の表（列は keys）：x・y（Wafer 上の座標 [mm]）・r（半径 [mm]）・theta（方位角 [度]、
%   −180〜180）・markX・markY（Shot 内の座標 [mm]）・shotX・shotY（Shot 中心の座標 [mm]）。
%   Shot 内・Shot 中心の座標は、計測データの Wafer（units、名前は unitLabels）と推定値の表の markIndex から引く
%   （units を省く・Excel から読み込んだ推定値で markIndex が無いときは NaN）。labels は画面に出す名前。
keys = ["x", "y", "r", "theta", "markX", "markY", "shotX", "shotY"];
labels = ["Wafer 上の X [mm]", "Wafer 上の Y [mm]", "半径 [mm]", "方位角 [度]", "Shot 内の X [mm]（markXmm）", ...
    "Shot 内の Y [mm]（markYmm）", "Shot 中心の X [mm]", "Shot 中心の Y [mm]"];
n = height(estimates);
values = array2table(nan(n, numel(keys)), 'VariableNames', cellstr(keys));
values.x = estimates.x;
values.y = estimates.y;
values.r = hypot(estimates.x, estimates.y);
values.theta = atan2d(estimates.y, estimates.x);
if nargin < 3 || isempty(units) || ~any(string(estimates.Properties.VariableNames) == "markIndex")
    return
end
[~, unitOfRow] = ismember(string(estimates.Wafer), string(unitLabels));
for u = unique(unitOfRow(unitOfRow > 0)).'
    rows = unitOfRow == u;
    index = estimates.markIndex(rows);
    marks = units(u).marks;
    values.markX(rows) = marks.markXmm(index);
    values.markY(rows) = marks.markYmm(index);
    values.shotX(rows) = marks.Xmm(index);
    values.shotY(rows) = marks.Ymm(index);
end
end
