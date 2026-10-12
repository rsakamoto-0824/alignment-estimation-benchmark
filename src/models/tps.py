"""薄板スプライン（TPS、平滑化つき）。

f(z) = Σ w_i φ(‖z − z_i‖) + c₀ + cᵀz、φ(r) = r² log r。
3次元以上の説明変数にも同じ φ を使う（scipy の RBFInterpolator の thin_plate_spline と同じ一般化。
r² log r はどの次元でも2階の条件付き正定値なので解が一意に決まる）。

計測ノイズを含むため補間（λ = 0）ではなく平滑化 TPS とし、λ は一般化交差検証（GCV）で Wafer ごとに選ぶ：
  min ‖y − f‖² + nλ wᵀΦw、 制約 Pᵀw = 0（P = [1, z]）
P の直交補空間 Q₂ で B = Q₂ᵀΦQ₂ = U D Uᵀ と固有分解すると（Wahba の方法）、
  残差 = nλ Q₂ U (D + nλ)⁻¹ Uᵀ Q₂ᵀ y、 tr(I − S) = Σ nλ / (dᵢ + nλ)
となり、λ を変えても固有分解は1回で済む。学習点が同じ（Shot 配置が同じ）なら全 Wafer で共通に使える。
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy.spatial.distance import cdist


def tps_kernel(distance: np.ndarray) -> np.ndarray:
    with np.errstate(divide="ignore", invalid="ignore"):
        values = distance**2 * np.log(distance)
    return np.where(distance > 0, values, 0.0)


@dataclass
class TPSResult:
    prediction: np.ndarray
    edf: float
    log10_lambda: float


class ThinPlateSpline:
    """学習点・評価点を固定した平滑化 TPS（目的変数だけ差し替える）。"""

    def __init__(self, train: np.ndarray, test: np.ndarray, log10_grid: np.ndarray):
        n = train.shape[0]
        self.n = n
        self.phi = tps_kernel(cdist(train, train))
        self.phi_test = tps_kernel(cdist(test, train))
        self.poly = np.hstack([np.ones((n, 1)), train])
        self.poly_test = np.hstack([np.ones((test.shape[0], 1)), test])
        if n <= self.poly.shape[1]:
            raise ValueError("TPS の学習点が多項式部分の項数以下")
        q_full, r_full = np.linalg.qr(self.poly, mode="complete")
        k = self.poly.shape[1]
        self.q1, self.r1, self.q2 = q_full[:, :k], r_full[:k], q_full[:, k:]
        eigval, eigvec = np.linalg.eigh(self.q2.T @ self.phi @ self.q2)
        self.eigval = np.maximum(eigval, 0.0)  # 条件付き正定値なので理論上 ≥ 0（丸め誤差を切る）
        self.basis = self.q2 @ eigvec  # (n, n−k)
        scale = float(np.mean(self.eigval)) if np.mean(self.eigval) > 0 else 1.0
        self.n_lambda_grid = scale * 10.0 ** np.asarray(log10_grid, dtype=float)  # nλ の候補

    def fit_predict(self, y: np.ndarray) -> TPSResult:
        projected = self.basis.T @ y  # Uᵀ Q₂ᵀ y
        shrink = self.n_lambda_grid[:, None] / (self.eigval[None, :] + self.n_lambda_grid[:, None])  # (L, n−k)
        rss = np.sum((shrink * projected[None, :]) ** 2, axis=1)
        trace_residual = shrink.sum(axis=1)
        gcv = self.n * rss / trace_residual**2
        best = int(np.argmin(gcv))
        n_lambda = self.n_lambda_grid[best]
        weights = self.basis @ (projected / (self.eigval + n_lambda))
        poly_target = y - self.phi @ weights - n_lambda * weights
        coefficients = np.linalg.solve(self.r1, self.q1.T @ poly_target)
        prediction = self.phi_test @ weights + self.poly_test @ coefficients
        edf = self.n - trace_residual[best]
        return TPSResult(prediction, float(edf), float(np.log10(n_lambda)))
