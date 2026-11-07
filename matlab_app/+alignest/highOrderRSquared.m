function [rSquared, adjusted] = highOrderRSquared(values, residuals, leverage)
%HIGHORDERRSQUARED Shot 高次補正の回帰の決定係数 R² と自由度調整済決定係数を求める。
%   [rSquared, adjusted] = alignest.highOrderRSquared(values, residuals, leverage)
%   values：補正前の値 [nm]、residuals：補正した後の残差 [nm]、leverage：点ごとのハット行列の対角（alignest.robustRidgeFit の
%   fit.leverage。足すと回帰の自由度）。どれも同じ点の並び。補正できた点（値と残差のある点）だけを使う。
%     R² = 1 − SSE / SST            SSE = Σ 残差²、SST = Σ (値 − 値の平均)²
%     調整済 R² = 1 − (SSE / (n − p)) / (SST / (n − 1))
%   n：点の数、p：回帰の自由度（leverage の和）。最小二乗では求めた係数の数と同じで、正則化では係数の数より小さい（有効自由度）。
%   ロバスト回帰・正則化では、残差の二乗和を最小にしていないので 0 より小さくなることがある。
%   値がすべて同じ・点が2点未満なら NaN。n − p が 0 に近い（点の数と自由度が同じ）ときは adjusted が NaN。
DEGREES_TOLERANCE = 1e-6;   % n − p がこれ以下なら、残差の自由度が無いとみなす
use = isfinite(values) & isfinite(residuals) & isfinite(leverage);
n = nnz(use);
[rSquared, adjusted] = deal(NaN);
if n < 2
    return
end
total = sum((values(use) - mean(values(use))) .^ 2);
if total <= 0
    return
end
sumSquares = sum(residuals(use) .^ 2);
rSquared = 1 - sumSquares / total;
remaining = n - sum(leverage(use));
if remaining > DEGREES_TOLERANCE
    adjusted = 1 - (sumSquares / remaining) / (total / (n - 1));
end
end
