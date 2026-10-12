"""推定精度の指標：決定係数 R²、自由度調整済み決定係数、RMSE、MAE。

評価は未計測 Shot の全 Mark（評価点）で、計測ノイズを含まない真値と推定値を比べる。
- R²        = 1 − Σ(真値 − 推定値)² / Σ(真値 − 真値の平均)²
- 調整済み R² = 1 − (1 − R²)(n − 1)/(n − p − 1)
  n は評価点の数、p はモデルの有効自由度から切片の1を引いた値。
  有効自由度は学習点での当てはめ行列（平滑化行列）のトレース。多項式・RT は係数の数、
  GPR・TPS・Kriging・GAM は平滑化の強さに応じた実効的な係数の数になる。n − p − 1 ≤ 0 なら定義しない（NaN）。
- XY は X と Y を合わせた評価。R² の分母は軸ごとの平均からの偏差、調整済み R² は
  1 − (1 − R²)(n − 2)/(n − p − 2)（n は評価点数の2倍、p は X と Y の有効自由度の和 − 2）。
"""
from __future__ import annotations

import numpy as np

AXIS_NAMES = ("X", "Y", "XY")


def regression_metrics(truth: np.ndarray, estimate: np.ndarray, edf: float) -> dict[str, float]:
    """1つの軸（または X・Y を並べた値）の指標。edf は切片を含む有効自由度。"""
    truth = np.asarray(truth, dtype=float).ravel()
    estimate = np.asarray(estimate, dtype=float).ravel()
    error = truth - estimate
    n = truth.size
    sse = float(np.sum(error**2))
    sst = float(np.sum((truth - truth.mean()) ** 2))
    r2 = 1.0 - sse / sst if sst > 0 else float("nan")
    p = edf - 1.0
    adj = 1.0 - (1.0 - r2) * (n - 1) / (n - p - 1) if n - p - 1 > 0 else float("nan")
    return {
        "R2": r2,
        "adjR2": float(adj),
        "RMSE": float(np.sqrt(sse / n)),
        "MAE": float(np.mean(np.abs(error))),
    }


def wafer_metrics(truth: np.ndarray, estimate: np.ndarray, edf_xy: tuple[float, float], outer_mask: np.ndarray) -> dict[str, float]:
    """truth, estimate は (評価点, 2)。X・Y・XY の4指標と、外周・内側の RMSE（XY）を返す。"""
    result: dict[str, float] = {}
    for axis, column in (("X", 0), ("Y", 1)):
        for key, value in regression_metrics(truth[:, column], estimate[:, column], edf_xy[column]).items():
            result[f"{key}_{axis}"] = value
    # XY をまとめた R² は軸ごとの平均値の違いを含めないよう、X と Y それぞれの平均からの偏差で分母を作る
    error = truth - estimate
    sse = float(np.sum(error**2))
    sst = float(np.sum((truth - truth.mean(axis=0)) ** 2))
    n = truth.size
    r2 = 1.0 - sse / sst if sst > 0 else float("nan")
    p = edf_xy[0] + edf_xy[1] - 2.0
    result["R2_XY"] = r2
    result["adjR2_XY"] = float(1.0 - (1.0 - r2) * (n - 2) / (n - p - 2)) if n - p - 2 > 0 else float("nan")
    result["RMSE_XY"] = float(np.sqrt(sse / n))
    result["MAE_XY"] = float(np.mean(np.abs(error)))
    for name, mask in (("outer", outer_mask), ("inner", ~outer_mask)):
        result[f"RMSE_XY_{name}"] = float(np.sqrt(np.mean(error[mask] ** 2))) if mask.any() else float("nan")
    return result
