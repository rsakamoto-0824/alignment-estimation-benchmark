function [start, lower, upper] = gprInitialParams(gp, y)
%GPRINITIALPARAMS ハイパーパラメータ（対数）の初期値と探索範囲。
%   初期値は fitrgp の既定と同じ考え方：ℓ = 説明変数の標準偏差（等方は平均）、σf = σn = std(y)/√2、α = 1。
%   説明変数は Wafer 半径で割った無次元量、σ の範囲は学習データの標準偏差に対する倍率で決める。
LENGTH_SCALE_BOUNDS = [1e-3, 1e3];
SIGNAL_STD_BOUNDS = [1e-3, 1e3];
NOISE_STD_BOUNDS = [1e-2, 1e1];        % 下限は fitrgp の SigmaLowerBound 既定（1e-2 × std(y)）に合わせる
ALPHA_BOUNDS = [1e-3, 1e3];
CATEGORICAL_STD_BOUNDS = [1e-4, 1e1];  % 質的変数の項 τ。下限は「効果なし」まで縮められる値
CATEGORICAL_STD_START = 0.2;
stdY = max(std(y(:), 1), 1e-6);
if gp.ard
    lengths = gp.featureStd(:);
else
    lengths = mean(gp.featureStd);
end
start = [log(lengths); log(stdY / sqrt(2))];
lower = [repmat(log(LENGTH_SCALE_BOUNDS(1)), gp.nLength, 1); log(SIGNAL_STD_BOUNDS(1) * stdY)];
upper = [repmat(log(LENGTH_SCALE_BOUNDS(2)), gp.nLength, 1); log(SIGNAL_STD_BOUNDS(2) * stdY)];
if gp.hasAlpha
    start = [start; 0];
    lower = [lower; log(ALPHA_BOUNDS(1))];
    upper = [upper; log(ALPHA_BOUNDS(2))];
end
start = [start; repmat(log(CATEGORICAL_STD_START * stdY), gp.nCategorical, 1); log(stdY / sqrt(2))];
lower = [lower; repmat(log(CATEGORICAL_STD_BOUNDS(1) * stdY), gp.nCategorical, 1); log(NOISE_STD_BOUNDS(1) * stdY)];
upper = [upper; repmat(log(CATEGORICAL_STD_BOUNDS(2) * stdY), gp.nCategorical, 1); log(NOISE_STD_BOUNDS(2) * stdY)];
end
