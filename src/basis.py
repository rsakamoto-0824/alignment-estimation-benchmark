"""説明変数・質的変数・多項式基底の作り方。

説明変数の組（座標は Wafer 半径 R_w = 150 mm で割って単位をそろえる）
- XY   : (x, y)
- XYR  : (x, y, r)
- XYRT : (x, y, r, T)。T は ASML R&T の接線方向の位置＝方位角 θ = atan2(y, x)。
  距離で類似度を測る手法（GPR・TPS・Kriging）では ±180° の境目で値が飛ばないよう (cos θ, sin θ) の2列に展開する。
  GAM では θ のまま周期（cyclic）スプラインで扱う（feature_frame を使う）。
質的変数：Scan方向（2水準）と Mark番号（4水準）。和が0になる効果コード（effect coding）で表す。
"""
from __future__ import annotations

import numpy as np

FEATURE_SETS = ("XY", "XYR", "XYRT")


def polynomial_design(x: np.ndarray, y: np.ndarray, order: int) -> np.ndarray:
    """x^a y^b（a + b ≤ order）を次数順に並べた設計行列。5次なら21列。"""
    if order < 0:
        raise ValueError("多項式の次数は0以上")
    columns = [x ** (degree - b) * y**b for degree in range(order + 1) for b in range(degree + 1)]
    return np.column_stack(columns)


def distance_features(x_mm: np.ndarray, y_mm: np.ndarray, feature_set: str, wafer_radius_mm: float) -> np.ndarray:
    """距離ベースの手法に渡す説明変数の行列（点数 × 次元）。"""
    if feature_set not in FEATURE_SETS:
        raise ValueError(f"説明変数の組は {FEATURE_SETS} のいずれか: {feature_set}")
    x = np.asarray(x_mm, dtype=float) / wafer_radius_mm
    y = np.asarray(y_mm, dtype=float) / wafer_radius_mm
    columns = [x, y]
    if feature_set in ("XYR", "XYRT"):
        columns.append(np.hypot(x, y))
    if feature_set == "XYRT":
        theta = np.arctan2(y, x)
        columns += [np.cos(theta), np.sin(theta)]
    return np.column_stack(columns)


def feature_groups(feature_set: str) -> np.ndarray:
    """distance_features の各列が属する説明変数の番号。ARD カーネルは番号ごとに長さスケールを1つ持つ。

    XYRT の cos θ・sin θ は T（方位角）1変数の展開なので同じ番号にする。
    """
    groups = {"XY": [0, 1], "XYR": [0, 1, 2], "XYRT": [0, 1, 2, 3, 3]}
    if feature_set not in groups:
        raise ValueError(f"説明変数の組は {FEATURE_SETS} のいずれか: {feature_set}")
    return np.array(groups[feature_set])


def effect_coding(levels: np.ndarray, all_levels: np.ndarray) -> np.ndarray:
    """質的変数の効果コード（水準数 − 1 列）。最後の水準の行は全列 −1。"""
    levels = np.asarray(levels)
    all_levels = np.asarray(all_levels)
    if not np.isin(levels, all_levels).all():
        raise ValueError("未知の水準がある")
    columns = []
    for level in all_levels[:-1]:
        columns.append((levels == level).astype(float) - (levels == all_levels[-1]).astype(float))
    return np.column_stack(columns) if columns else np.zeros((levels.size, 0))


def factor_design(direction: np.ndarray, mark_number: np.ndarray, n_marks_per_shot: int) -> np.ndarray:
    """Scan方向（1列）と Mark番号（水準数−1列）の効果コードを横に並べる。"""
    scan = effect_coding(direction, np.array([1, 2]))
    mark = effect_coding(mark_number, np.arange(1, n_marks_per_shot + 1))
    return np.hstack([scan, mark])
