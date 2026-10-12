"""固定した基底の最小二乗モデル：XY N次多項式と RT モデル。

どちらも推定値は計測値の線形写像（推定行列 L）なので、Shot 配置が同じなら L を1回作れば全 Wafer に使える。
説明変数の組（XY / XYR / XYRT）や質的変数は使わない（基底が座標の式で決まっているため）。

- XY N次多項式：X・Y それぞれ x^a y^b（a + b ≤ N、5次で21項）を独立に当てはめる。
- RT モデル（K次）：変位を半径方向 R と接線方向 T に分け、R = ρ·M(x, y)、T = ρ·Θ(x, y) とする。
  局所倍率マップ M・局所回転マップ Θ をそれぞれ Zernike 多項式（動径次数 n ≤ K）で展開し、
  並進2項・非対称倍率・直交度の4項を加える（wafer_rt_simulation の「RT K次」と同じ定義）。
  XY に換算した最大次数は K+1。X・Y を同時に当てはめる。
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ..basis import polynomial_design
from ..zernike import zernike_matrix_xy, zernike_modes

PINV_RCOND = 1e-10


@dataclass(frozen=True)
class LinearOperator:
    """推定値 = matrix_test @ 計測値。X・Y を積み重ねた [X; Y] の形で持つ。"""

    name: str
    matrix_test: np.ndarray  # (2m, 2n)
    edf_x: float
    edf_y: float
    n_coef: int
    rank: int

    def apply(self, measured_train: np.ndarray) -> np.ndarray:
        """measured_train (n, 2) → 評価点の推定値 (m, 2)。"""
        stacked = np.concatenate([measured_train[:, 0], measured_train[:, 1]])
        estimate = self.matrix_test @ stacked
        half = estimate.size // 2
        return np.column_stack([estimate[:half], estimate[half:]])


def _operator(name: str, design_train: np.ndarray, design_test: np.ndarray) -> LinearOperator:
    pinv = np.linalg.pinv(design_train, rcond=PINV_RCOND)
    hat = design_train @ pinv
    n = design_train.shape[0] // 2
    rank = int(np.linalg.matrix_rank(design_train))
    return LinearOperator(
        name=name,
        matrix_test=design_test @ pinv,
        edf_x=float(np.trace(hat[:n, :n])),
        edf_y=float(np.trace(hat[n:, n:])),
        n_coef=design_train.shape[1],
        rank=rank,
    )


def _block_diagonal(design: np.ndarray) -> np.ndarray:
    zeros = np.zeros_like(design)
    return np.block([[design, zeros], [zeros, design]])


def polynomial_operator(train_xy: np.ndarray, test_xy: np.ndarray, order: int) -> LinearOperator:
    """XY N次多項式。train_xy, test_xy は Wafer 半径で割った (点数, 2)。"""
    design_train = polynomial_design(train_xy[:, 0], train_xy[:, 1], order)
    design_test = polynomial_design(test_xy[:, 0], test_xy[:, 1], order)
    return _operator(f"XY{order}", _block_diagonal(design_train), _block_diagonal(design_test))


def rt_design(points_xy: np.ndarray, order: int) -> np.ndarray:
    """RT K次の基底を XY 変位で書いた設計行列（[u; v] に対する 2点数 × 項数）。"""
    x, y = points_xy[:, 0], points_xy[:, 1]
    ones, zeros = np.ones_like(x), np.zeros_like(x)
    u_cols = [ones, zeros, x, y]  # 並進x、並進y、非対称倍率、直交度
    v_cols = [zeros, ones, -y, x]
    zern = zernike_matrix_xy(x, y, zernike_modes(order), "rms")
    for column in range(zern.shape[1]):
        values = zern[:, column]
        u_cols.append(x * values)  # R = ρ·Z → (u, v) = Z·(x, y)
        v_cols.append(y * values)
    for column in range(zern.shape[1]):
        values = zern[:, column]
        u_cols.append(-y * values)  # T = ρ·Z → (u, v) = Z·(−y, x)
        v_cols.append(x * values)
    return np.vstack([np.column_stack(u_cols), np.column_stack(v_cols)])


def rt_operator(train_xy: np.ndarray, test_xy: np.ndarray, order: int) -> LinearOperator:
    return _operator(f"RT{order}", rt_design(train_xy, order), rt_design(test_xy, order))
