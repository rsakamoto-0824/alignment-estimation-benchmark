"""Kriging（通常 Kriging：Ordinary）と Universal Kriging。

バリオグラムのモデルと当てはめ方は PyKrige の既定に合わせる（d は説明変数空間の距離）。
- linear      : γ(d) = slope·d + nugget
- power       : γ(d) = scale·d^exponent + nugget（0 < exponent < 2）
- gaussian    : γ(d) = psill·(1 − exp(−d² / (4/7·range)²)) + nugget
- exponential : γ(d) = psill·(1 − exp(−d / (range/3))) + nugget
経験バリオグラムは距離の範囲を nlags（既定6）個の等幅の区間に分けた平均で求め、
scipy の least_squares（soft_l1 損失、PyKrige と同じ初期値・範囲）でモデルを当てはめる。

- 通常 Kriging   ：ドリフトは定数（未知の平均）。経験バリオグラムは計測値そのもので求める。
- Universal Kriging：ドリフトは説明変数の1次式 [1, z]。経験バリオグラムはドリフトを最小二乗で除いた残差で求める
  （PyKrige は生の値で求めるが、トレンドがあるとバリオグラムが過大になるため残差を使う）。

推定点は計測点と重ならないので、ナゲットを測定誤差とみなしても（平滑化）、厳密補間とみなしても重みは同じになる。
学習点での平滑化行列（有効自由度の計算用）は、ナゲットを測定誤差とみなす形で求める。
ナゲットが0に近い Gaussian バリオグラムは連立方程式の条件数が 1e18 を超えて解が壊れるため、
ナゲットにバリオグラムの最大値の 1e-6 倍を足す（GPR のジッターと同じ数値安定化。精度への影響は無視できる）。
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy.linalg import LinAlgError, lu_factor, lu_solve
from scipy.optimize import least_squares
from scipy.spatial.distance import cdist, pdist

VARIOGRAMS = ("linear", "gaussian", "power", "exponential")
JITTER_RELATIVE = 1e-6
KRIGING_TYPES = ("ordinary", "universal")


def variogram_function(model: str, params: np.ndarray, distance: np.ndarray, include_nugget: bool = True) -> np.ndarray:
    nugget = params[-1] if include_nugget else 0.0
    if model == "linear":
        return params[0] * distance + nugget
    if model == "power":
        return params[0] * distance ** params[1] + nugget
    if model == "gaussian":
        return params[0] * (1.0 - np.exp(-(distance**2) / (params[1] * 4.0 / 7.0) ** 2)) + nugget
    if model == "exponential":
        return params[0] * (1.0 - np.exp(-distance / (params[1] / 3.0))) + nugget
    raise ValueError(f"バリオグラムは {VARIOGRAMS} のいずれか: {model}")


def _fit_variogram(model: str, lags: np.ndarray, semivariance: np.ndarray) -> np.ndarray:
    """PyKrige の _calculate_variogram_model と同じ初期値・範囲・損失で当てはめる。"""
    s_min, s_max = float(np.min(semivariance)), float(np.max(semivariance))
    lag_span = max(float(np.max(lags) - np.min(lags)), 1e-12)
    s_max = max(s_max, 1e-12)
    if model == "linear":
        x0 = [(s_max - s_min) / lag_span, s_min]
        bounds = ([0.0, 0.0], [np.inf, s_max])
    elif model == "power":
        x0 = [(s_max - s_min) / lag_span, 1.1, s_min]
        bounds = ([0.0, 0.001, 0.0], [np.inf, 1.999, s_max])
    else:
        x0 = [s_max - s_min, 0.25 * float(np.max(lags)), s_min]
        bounds = ([0.0, 0.0, 0.0], [10.0 * s_max, float(np.max(lags)), s_max])
    x0 = np.clip(np.asarray(x0, dtype=float), bounds[0], bounds[1])

    def residuals(params):
        return variogram_function(model, params, lags) - semivariance

    result = least_squares(residuals, x0, bounds=bounds, loss="soft_l1")
    return result.x


@dataclass
class KrigingResult:
    prediction: np.ndarray
    edf: float
    params: np.ndarray


class Kriging:
    """学習点・評価点を固定した Kriging（目的変数だけ差し替える）。"""

    def __init__(self, train: np.ndarray, test: np.ndarray, kriging_type: str, variogram: str, nlags: int = 6):
        if kriging_type not in KRIGING_TYPES:
            raise ValueError(f"Kriging の種類は {KRIGING_TYPES} のいずれか: {kriging_type}")
        if variogram not in VARIOGRAMS:
            raise ValueError(f"バリオグラムは {VARIOGRAMS} のいずれか: {variogram}")
        self.kriging_type = kriging_type
        self.variogram = variogram
        n = train.shape[0]
        self.n = n
        self.dist = cdist(train, train)
        self.dist_test = cdist(test, train)
        if kriging_type == "ordinary":
            self.drift = np.ones((n, 1))
            self.drift_test = np.ones((test.shape[0], 1))
        else:
            self.drift = np.hstack([np.ones((n, 1)), train])
            self.drift_test = np.hstack([np.ones((test.shape[0], 1)), test])
        # 経験バリオグラムの区間（PyKrige と同じ：最小〜最大距離を nlags 等分、最後の端は +0.001）
        self.pair_distance = pdist(train)
        d_min, d_max = float(self.pair_distance.min()), float(self.pair_distance.max())
        edges = d_min + (d_max - d_min) / nlags * np.arange(nlags + 1)
        edges[-1] = d_max + 0.001
        self.pair_bin = np.searchsorted(edges, self.pair_distance, side="right") - 1
        self.nlags = nlags
        self.pair_i, self.pair_j = np.triu_indices(n, k=1)
        self._drift_projector = None
        if kriging_type == "universal":
            q_mat, _ = np.linalg.qr(self.drift)
            self._drift_projector = q_mat

    def empirical_variogram(self, values: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        semi = 0.5 * (values[self.pair_i] - values[self.pair_j]) ** 2
        lags, semivariance = [], []
        for lag in range(self.nlags):
            in_bin = self.pair_bin == lag
            if np.any(in_bin):
                lags.append(float(self.pair_distance[in_bin].mean()))
                semivariance.append(float(semi[in_bin].mean()))
        return np.array(lags), np.array(semivariance)

    def fit_predict(self, y: np.ndarray) -> KrigingResult:
        if self._drift_projector is not None:
            residual = y - self._drift_projector @ (self._drift_projector.T @ y)
        else:
            residual = y
        lags, semivariance = self.empirical_variogram(residual)
        params = _fit_variogram(self.variogram, lags, semivariance)
        gamma_train = variogram_function(self.variogram, params, self.dist, include_nugget=False)
        nugget = params[-1] + JITTER_RELATIVE * max(float(gamma_train.max()) + params[-1], 1e-12)
        # ナゲットを測定誤差とみなした形：Γ_e = g(d) − nugget·I（g はナゲットを除いた部分、g(0) = 0）
        gamma = gamma_train - nugget * np.eye(self.n)
        gamma_test = variogram_function(self.variogram, params, self.dist_test, include_nugget=False)
        k = self.drift.shape[1]
        system = np.block([[gamma, self.drift], [self.drift.T, np.zeros((k, k))]])
        rhs = np.concatenate([y, np.zeros(k)])
        try:
            factor = lu_factor(system, check_finite=False)
            solution = lu_solve(factor, rhs, check_finite=False)
            if not np.all(np.isfinite(solution)):
                raise LinAlgError("non-finite")
            solve = lambda b: lu_solve(factor, b, check_finite=False)  # noqa: E731
        except (LinAlgError, ValueError):
            pinv = np.linalg.pinv(system)
            solution = pinv @ rhs
            solve = lambda b: pinv @ b  # noqa: E731
        # 対称な連立方程式なので、推定値 = [γ₀; f₀]ᵀ · system⁻¹ · [y; 0]
        prediction = gamma_test @ solution[: self.n] + self.drift_test @ solution[self.n :]
        # 学習点の平滑化行列 S（目標は g(d)：ナゲットなし）
        unit_rhs = np.vstack([np.eye(self.n), np.zeros((k, self.n))])
        weights = solve(unit_rhs)
        smoother = gamma_train @ weights[: self.n] + self.drift @ weights[self.n :]
        return KrigingResult(prediction, float(np.trace(smoother)), params)
