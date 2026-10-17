function metrics = computeMetrics(truthX, estimateX, edfX, truthY, estimateY, edfY, outerX, outerY)
%COMPUTEMETRICS 推定精度の指標：決定係数 R²、自由度調整済み決定係数、RMSE、MAE（X・Y・XY）。
%   評価点は学習に使わなかった Shot の Mark。実データでは計測値を「真の値」の代わりに使う
%   （計測ノイズを含むので、模擬データの評価より指標は少し悪く出る）。
%   - R²          = 1 − Σ(計測値 − 推定値)² / Σ(計測値 − 計測値の平均)²
%   - 調整済み R²  = 1 − (1 − R²)(n − 1)/(n − p − 1)。p は有効自由度 − 1（切片の分）。n − p − 1 ≤ 0 なら NaN。
%   - XY は X と Y を合わせた評価。R² の分母は軸ごとの平均からの偏差、
%     調整済み R² は 1 − (1 − R²)(n − 2)/(n − p − 2)（n は X と Y の評価点数の和、p は有効自由度の和 − 2）。
%   - RMSE_XY_outer / inner：外周（outerX / outerY が true の点）とそれ以外の RMSE（X・Y 合わせて）。
metrics = struct();
metrics = addAxis(metrics, "X", truthX, estimateX, edfX);
metrics = addAxis(metrics, "Y", truthY, estimateY, edfY);
errorAll = [truthX(:) - estimateX(:); truthY(:) - estimateY(:)];
sse = sum(errorAll .^ 2);
sst = sum((truthX(:) - mean(truthX)) .^ 2) + sum((truthY(:) - mean(truthY)) .^ 2);
n = numel(errorAll);
r2 = NaN;
if sst > 0
    r2 = 1 - sse / sst;
end
p = edfX + edfY - 2;
adjusted = NaN;
if n - p - 2 > 0
    adjusted = 1 - (1 - r2) * (n - 2) / (n - p - 2);
end
metrics.R2_XY = r2;
metrics.adjR2_XY = adjusted;
metrics.RMSE_XY = sqrt(sse / max(n, 1));
metrics.MAE_XY = mean(abs(errorAll));
outer = [outerX(:); outerY(:)];
metrics.RMSE_XY_outer = rmseOf(errorAll(outer));
metrics.RMSE_XY_inner = rmseOf(errorAll(~outer));
metrics.nTest_X = numel(truthX);
metrics.nTest_Y = numel(truthY);
if n == 0
    metrics.RMSE_XY = NaN;
    metrics.MAE_XY = NaN;
end
end

function metrics = addAxis(metrics, axisName, truth, estimate, edf)
truth = truth(:);
estimate = estimate(:);
errorValues = truth - estimate;
n = numel(truth);
sse = sum(errorValues .^ 2);
sst = sum((truth - mean(truth)) .^ 2);
r2 = NaN;
if sst > 0
    r2 = 1 - sse / sst;
end
p = edf - 1;
adjusted = NaN;
if n - p - 1 > 0
    adjusted = 1 - (1 - r2) * (n - 1) / (n - p - 1);
end
metrics.("R2_" + axisName) = r2;
metrics.("adjR2_" + axisName) = adjusted;
metrics.("RMSE_" + axisName) = rmseOf(errorValues);
metrics.("MAE_" + axisName) = meanOrNan(abs(errorValues));
end

function value = rmseOf(errorValues)
value = NaN;
if ~isempty(errorValues)
    value = sqrt(mean(errorValues .^ 2));
end
end

function value = meanOrNan(values)
value = NaN;
if ~isempty(values)
    value = mean(values);
end
end
