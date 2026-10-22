function metrics = computeMetrics(truthX, estimateX, edfX, truthY, estimateY, edfY, outerX, outerY, trainX, trainY)
%COMPUTEMETRICS 推定精度の指標：決定係数 R²、RMSE、MAE（X・Y・XY）。
%   評価点は学習に使わなかった Shot の Mark。実データでは計測値を「真の値」の代わりに使う
%   （計測ノイズを含むので、模擬データの評価より指標は少し悪く出る）。
%   - R²          = 1 − Σ(計測値 − 推定値)² / Σ(計測値 − 計測値の平均)²
%   - XY は X と Y を合わせた評価。R² の分母は軸ごとの平均からの偏差。
%   edfX・edfY（有効自由度）は使わない（以前の呼び出しとの互換のため残す）。
%   - RMSE_XY_outer / inner：外周（outerX / outerY が true の点）とそれ以外の RMSE（X・Y 合わせて）。
%   - 学習点の計測値 trainX・trainY を渡すと、学習点の平均値・中央値（軸ごと）をそのまま全評価点の推定値にした場合の
%     RMSE（X・Y 合わせて）と、それに対する改善量・改善率も求める（alignest.baselineImprovement）。
%     改善量 = 平均値（中央値）の RMSE − 手法の RMSE [nm]、改善率 = 改善量 / 平均値（中央値）の RMSE × 100 [%]。
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
metrics.R2_XY = r2;
metrics.RMSE_XY = sqrt(sse / max(n, 1));
metrics.MAE_XY = mean(abs(errorAll));
outer = [outerX(:); outerY(:)];
metrics.RMSE_XY_outer = rmseOf(errorAll(outer));
metrics.RMSE_XY_inner = rmseOf(errorAll(~outer));
metrics.nTest_X = numel(truthX);
metrics.nTest_Y = numel(truthY);
if nargin >= 10
    for kind = ["Mean", "Median"]
        baseline = alignest.baselineImprovement(truthX, truthY, trainX, trainY, lower(kind), metrics.RMSE_XY);
        metrics.("RMSE_XY_base" + kind) = baseline.rmse;
        metrics.("improve" + kind + "_XY") = baseline.improvement;
        metrics.("improve" + kind + "Pct_XY") = baseline.percent;
    end
end
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
metrics.("R2_" + axisName) = r2;
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
