"""一般化加法モデル（GAM、正規分布・恒等リンク）。

y = β₀ + s(x, y) [+ s(r)] [+ s_周期(θ)] + Scan方向の効果 + Mark番号の効果 + ε

- s(x, y)   : 3次 B スプラインのテンソル積（各軸 8 基底、[−1, 1]）。罰則は各軸の2階差分の和（P-spline）。
- s(r)      : 3次 B スプライン（8 基底、[0, 1]）、2階差分の罰則。
- s_周期(θ) : 周期3次 B スプライン（8 基底、[−π, π)）、周期的な2階差分の罰則。T（方位角）は ±180° でつながる。
- Scan方向・Mark番号：効果コードの質的変数（罰則なし）。
- 各平滑項は学習点での和が0になるよう制約し（mgcv と同じ QR 分解による吸収）、切片と重ならないようにする。
- 平滑化パラメータ λ（平滑項ごと）は制限付き最尤（REML）で Wafer ごとに選ぶ（mgcv の method = "REML" と同じ基準）。
  学習点が少ない（10 Shot = 40点）と係数の数が点数を超え、GCV は補間（有効自由度 = 点数）を選んで破綻するため。
  −2 l_R(λ) = (n − M_p) log σ̂² + log|XᵀX + S_λ| − Σ_j r_j log λ_j、 σ̂² = (RSS + β̂ᵀS_λβ̂)/(n − M_p)
  （M_p は罰則のない係数の数、r_j は j 番目の罰則行列の階数）
座標は Wafer 半径で割った値を使う。学習点が同じ（Shot 配置が同じ）なら設計行列は全 Wafer で共通。
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy.interpolate import BSpline
from scipy.optimize import minimize

from ..basis import FEATURE_SETS

LOG10_LAMBDA_BOUNDS = (-8.0, 8.0)
LOG10_LAMBDA_START_GRID = np.linspace(-6.0, 6.0, 13)
RIDGE = 1e-9


def bspline_basis(values: np.ndarray, lower: float, upper: float, n_basis: int, degree: int = 3) -> np.ndarray:
    """区間 [lower, upper] の等間隔ノット B スプライン（P-spline の基底）。"""
    n_segments = n_basis - degree
    if n_segments < 1:
        raise ValueError("基底の数は次数+1より多くする")
    step = (upper - lower) / n_segments
    knots = lower + step * np.arange(-degree, n_segments + degree + 1)
    clipped = np.clip(values, lower, upper)
    return BSpline.design_matrix(clipped, knots, degree).toarray()


def _cardinal_cubic(s: np.ndarray) -> np.ndarray:
    """台が [0, 4) の3次の基本 B スプライン。"""
    out = np.zeros_like(s)
    m0 = (s >= 0) & (s < 1)
    m1 = (s >= 1) & (s < 2)
    m2 = (s >= 2) & (s < 3)
    m3 = (s >= 3) & (s < 4)
    out[m0] = s[m0] ** 3 / 6.0
    out[m1] = (-3 * s[m1] ** 3 + 12 * s[m1] ** 2 - 12 * s[m1] + 4) / 6.0
    out[m2] = (3 * s[m2] ** 3 - 24 * s[m2] ** 2 + 60 * s[m2] - 44) / 6.0
    out[m3] = (4 - s[m3]) ** 3 / 6.0
    return out


def cyclic_bspline_basis(values: np.ndarray, start: float, period: float, n_basis: int) -> np.ndarray:
    """周期 period の3次 B スプライン（n_basis 個、各基底の和は常に1）。"""
    if n_basis < 4:
        raise ValueError("周期スプラインの基底は4個以上にする")
    u = np.mod(values - start, period) / (period / n_basis)
    return np.column_stack([_cardinal_cubic(np.mod(u - j, n_basis)) for j in range(n_basis)])


def difference_penalty(n_basis: int, cyclic: bool = False) -> np.ndarray:
    if cyclic:
        diff = np.zeros((n_basis, n_basis))
        for i in range(n_basis):
            diff[i, i] = 1.0
            diff[i, (i + 1) % n_basis] = -2.0
            diff[i, (i + 2) % n_basis] = 1.0
    else:
        diff = np.diff(np.eye(n_basis), 2, axis=0)
    return diff.T @ diff


def centering_matrix(basis_train: np.ndarray) -> np.ndarray:
    """学習点での和が0になる係数空間の基底 Z（k × (k−1)）。"""
    constraint = basis_train.sum(axis=0)[:, None]
    q_mat, _ = np.linalg.qr(constraint, mode="complete")
    return q_mat[:, 1:]


@dataclass
class GAMResult:
    prediction: np.ndarray
    edf: float
    log10_lambda: np.ndarray


class AdditiveModel:
    """学習点・評価点を固定した GAM（目的変数だけ差し替える）。"""

    def __init__(
        self,
        train_points: dict,
        test_points: dict,
        feature_set: str,
        factors_train: np.ndarray,
        factors_test: np.ndarray,
        n_basis_axis: int = 8,
        n_basis_radius: int = 8,
        n_basis_angle: int = 8,
    ):
        """train_points / test_points は {'x','y','r','theta'}（x, y, r は Wafer 半径で割った値）。"""
        if feature_set not in FEATURE_SETS:
            raise ValueError(f"説明変数の組は {FEATURE_SETS} のいずれか: {feature_set}")
        smooth_builders = [("xy", lambda p: _tensor_basis(p, n_basis_axis), _tensor_penalty(n_basis_axis))]
        if feature_set in ("XYR", "XYRT"):
            smooth_builders.append(
                ("r", lambda p: bspline_basis(p["r"], 0.0, 1.0, n_basis_radius), difference_penalty(n_basis_radius))
            )
        if feature_set == "XYRT":
            smooth_builders.append(
                (
                    "theta",
                    lambda p: cyclic_bspline_basis(p["theta"], -np.pi, 2 * np.pi, n_basis_angle),
                    difference_penalty(n_basis_angle, cyclic=True),
                )
            )
        n_train = len(train_points["x"])
        blocks_train = [np.ones((n_train, 1)), factors_train]
        blocks_test = [np.ones((len(test_points["x"]), 1)), factors_test]
        penalties = []
        ranks = []
        offset = 1 + factors_train.shape[1]
        for _, builder, penalty in smooth_builders:
            basis_train = builder(train_points)
            basis_test = builder(test_points)
            z_mat = centering_matrix(basis_train)
            blocks_train.append(basis_train @ z_mat)
            blocks_test.append(basis_test @ z_mat)
            width = z_mat.shape[1]
            reduced = z_mat.T @ penalty @ z_mat
            penalties.append((slice(offset, offset + width), reduced))
            ranks.append(int(np.linalg.matrix_rank(reduced, tol=1e-9 * np.abs(reduced).max())))
            offset += width
        self.names = [name for name, _, _ in smooth_builders]
        self.design = np.hstack(blocks_train)
        self.design_test = np.hstack(blocks_test)
        self.penalties = penalties
        self.gram = self.design.T @ self.design
        self.n = n_train
        self.n_coef = self.design.shape[1]
        self.penalty_ranks = np.array(ranks)
        self.n_unpenalized = self.n_coef - int(self.penalty_ranks.sum())
        if self.n_unpenalized >= self.n:
            raise ValueError("GAM の罰則のない係数の数が学習点の数以上")

    def _penalty_matrix(self, log10_lambda: np.ndarray) -> np.ndarray:
        total = RIDGE * np.eye(self.n_coef)
        for (block, penalty), value in zip(self.penalties, log10_lambda):
            total[block, block] += 10.0**value * penalty
        return total

    def _solve(self, log10_lambda: np.ndarray, xty: np.ndarray, yty: float) -> tuple[float, np.ndarray, float]:
        """REML 基準（−2 l_R、定数を除く）・係数・有効自由度。"""
        system = self.gram + self._penalty_matrix(log10_lambda)
        try:
            chol = np.linalg.cholesky(system)
        except np.linalg.LinAlgError:
            return float("inf"), np.zeros(self.n_coef), float(self.n)
        inv_chol = np.linalg.inv(chol)
        system_inv = inv_chol.T @ inv_chol
        coef = system_inv @ xty
        edf = float(np.sum(system_inv * self.gram))
        rss = max(yty - 2.0 * coef @ xty + coef @ self.gram @ coef, 0.0)
        penalty_value = 0.0
        for (block, penalty), value in zip(self.penalties, log10_lambda):
            penalty_value += 10.0**value * float(coef[block] @ penalty @ coef[block])
        dof = self.n - self.n_unpenalized
        sigma2 = (rss + penalty_value) / dof
        if sigma2 <= 0:
            return float("inf"), coef, edf
        log_det = 2.0 * float(np.sum(np.log(np.diag(chol))))
        log_det_penalty = float(np.sum(self.penalty_ranks * np.asarray(log10_lambda) * np.log(10.0)))
        criterion = dof * np.log(sigma2) + log_det - log_det_penalty
        return float(criterion), coef, edf

    def fit_predict(self, y: np.ndarray) -> GAMResult:
        xty = self.design.T @ y
        yty = float(y @ y)
        n_smooth = len(self.penalties)
        start_scores = [self._solve(np.full(n_smooth, value), xty, yty)[0] for value in LOG10_LAMBDA_START_GRID]
        start = np.full(n_smooth, LOG10_LAMBDA_START_GRID[int(np.argmin(start_scores))])
        result = minimize(
            lambda v: self._solve(v, xty, yty)[0],
            start,
            method="L-BFGS-B",
            bounds=[LOG10_LAMBDA_BOUNDS] * n_smooth,
            options={"eps": 1e-4},
        )
        best = result.x if np.isfinite(result.fun) and result.fun <= min(start_scores) else start
        _, coef, edf = self._solve(best, xty, yty)
        return GAMResult(self.design_test @ coef, edf, best)


def _tensor_basis(points: dict, n_basis: int) -> np.ndarray:
    basis_x = bspline_basis(points["x"], -1.0, 1.0, n_basis)
    basis_y = bspline_basis(points["y"], -1.0, 1.0, n_basis)
    return np.einsum("ni,nj->nij", basis_x, basis_y).reshape(len(points["x"]), -1)


def _tensor_penalty(n_basis: int) -> np.ndarray:
    penalty = difference_penalty(n_basis)
    identity = np.eye(n_basis)
    return np.kron(penalty, identity) + np.kron(identity, penalty)
