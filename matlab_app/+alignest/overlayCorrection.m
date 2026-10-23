function result = overlayCorrection(unit, out, projector, markMask)
%OVERLAYCORRECTION 推定誤差による Overlay 残差の変化を求める（補正モデルは alignest.overlayProjector）。
%   実測値の場 A：全 Mark の計測値（その軸が無効な点は NaN）
%   推定値の場 E：学習 Shot は計測値、学習しなかった Shot は推定値（out.estimate。実際の運用で補正に使う値）
%   - 実測値で補正した残差   R_A = A − 補正量(A)
%   - 推定値で補正した残差   R_E = A − 補正量(E)（推定値から求めた補正を、実際の値に当てたときの残差）
%   - 推定による残差の変化   D = R_E − R_A = 補正量(A) − 補正量(E)
%   補正量は補正モデルの最小二乗の当てはめ（X・Y 別）。全 Mark（学習・評価 Shot）で求める。
%   result.fields：Mark 数 × 2（X, Y）の actual・estimated・residualActual・residualEstimated・change
%   result.metrics：各場の |平均| + 3σ [nm]（X・Y）と、増加量（R_E − R_A の |平均|+3σ の差）
%   markMask（省略可、Mark ごとの論理ベクトル）を渡すと、metrics はその Mark だけで求める（評価点の絞り込み。
%   補正量は全 Mark で求めたまま）。
marks = unit.marks;
n = numel(marks.x);
if nargin < 4 || isempty(markMask)
    markMask = true(n, 1);
end
actual = [marks.measX, marks.measY];
actual(~marks.validX, 1) = NaN;
actual(~marks.validY, 2) = NaN;
estimated = actual;
estimated(out.testIndex.X, 1) = out.estimate.X;
estimated(out.testIndex.Y, 2) = out.estimate.Y;
residualActual = nan(n, 2);
residualEstimated = nan(n, 2);
change = nan(n, 2);
axisNames = ["X", "Y"];
for k = 1:2
    part = projector.(axisNames(k));
    index = part.index;
    fitActual = part.basis * (part.basis.' * actual(index, k));
    fitEstimated = part.basis * (part.basis.' * estimated(index, k));
    residualActual(index, k) = actual(index, k) - fitActual;
    residualEstimated(index, k) = actual(index, k) - fitEstimated;
    change(index, k) = fitActual - fitEstimated;
end
result.fields = struct("actual", actual, "estimated", estimated, "residualActual", residualActual, ...
    "residualEstimated", residualEstimated, "change", change);
for k = 1:2
    axisName = axisNames(k);
    result.metrics.("overlayActual_" + axisName) = meanPlus3Sigma(residualActual(markMask, k));
    result.metrics.("overlayEstimated_" + axisName) = meanPlus3Sigma(residualEstimated(markMask, k));
    result.metrics.("overlayChange_" + axisName) = meanPlus3Sigma(change(markMask, k));
    result.metrics.("overlayIncrease_" + axisName) = result.metrics.("overlayEstimated_" + axisName) - ...
        result.metrics.("overlayActual_" + axisName);
end
end

function value = meanPlus3Sigma(values)
% Overlay の代表値 |平均| + 3σ（σ は不偏標準偏差）。点が2点未満なら NaN
values = values(isfinite(values));
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end
