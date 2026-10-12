"""計測Shotの選び方：制約条件付きI最適計画（交換法）。

- 選ぶ単位は Shot で、選んだ Shot の全 Mark を計測する（Mark番号の質的変数がいつも全水準そろう）。
- 計画の基準モデルは XY N次多項式（初期設定 N = 5、X・Y 共通の21項）。全 Mark での設計行列の
  正規直交基底 B を作り、Shot ごとの情報行列 F_s = B_sᵀ B_s の和 M で評価する。
  I基準：全 Mark での平均予測分散 ∝ tr(M⁻¹)（B が正規直交なので重み行列は単位行列の定数倍）。
- 制約：同心円領域・4象限・Scan方向ごとの Shot 数を、全 Shot に占める割合 × 選ぶ数 ± slack に収める。
  Scan方向の制約は、質的変数（Scan方向）を推定するために両方向を必ず含める役割もある。
- 交換法（Fedorov型）は制約を満たす交換だけを受け入れ、複数の初期配置から始めて最良を採る。
計画は面内傾向の値に依存しないので、Shot数ごとに1回だけ作り、全 Wafer で共通に使う。
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .basis import polynomial_design
from .geometry import WaferLayout, shot_quadrant, shot_radial_zone

REGULARIZATION = 1e-10


@dataclass(frozen=True)
class SamplingPlan:
    n_shots: int
    shot_indices: np.ndarray  # 0始まりの有効Shot番号（昇順）
    criterion_value: float  # tr(M⁻¹)/全Mark数（小さいほど良い）
    feasible: bool


def constraint_partitions(layout: WaferLayout, constraints: dict) -> dict[str, np.ndarray]:
    partitions = {}
    if constraints.get("radial_zone_edges"):
        partitions["radial_zone"] = shot_radial_zone(layout.shots, layout.wafer_radius_mm, constraints["radial_zone_edges"])
    if constraints.get("quadrants"):
        partitions["quadrant"] = shot_quadrant(layout.shots)
    if constraints.get("scan_direction"):
        partitions["scan_direction"] = layout.shots["Direction"].to_numpy()
    return partitions


def group_bounds(partitions: dict[str, np.ndarray], n_select: int, slack: int) -> dict[str, dict]:
    """各グループの Shot 数の下限・上限。全 Shot に占める割合 × 選ぶ数 を中心に ±slack。"""
    bounds = {}
    for name, labels in partitions.items():
        bounds[name] = {}
        for label in np.unique(labels):
            size = int(np.sum(labels == label))
            target = n_select * size / labels.size
            low = max(0, int(np.floor(target)) - slack)
            high = min(size, int(np.ceil(target)) + slack)
            bounds[name][label] = (low, high)
    return bounds


def violation_count(selected: np.ndarray, partitions: dict, bounds: dict) -> int:
    """制約の違反量（下限に足りない数＋上限を超えた数の合計）。0なら制約を満たす。"""
    total = 0
    for name, labels in partitions.items():
        for label, (low, high) in bounds[name].items():
            count = int(np.sum(labels[selected] == label))
            total += max(0, low - count) + max(0, count - high)
    return total


def shot_information(layout: WaferLayout, xy_order: int) -> np.ndarray:
    """Shot ごとの情報行列 F_s (Shot数 × p × p)。基底は全 Mark で正規直交化した XY 多項式。"""
    design = polynomial_design(layout.x_mm / layout.wafer_radius_mm, layout.y_mm / layout.wafer_radius_mm, xy_order)
    q_mat, _ = np.linalg.qr(design)
    info = np.zeros((layout.n_shots, q_mat.shape[1], q_mat.shape[1]))
    for shot in range(layout.n_shots):
        block = q_mat[layout.shot_index == shot]
        info[shot] = block.T @ block
    return info


def i_criterion(info_sum: np.ndarray) -> float:
    """tr(M⁻¹)。特異なら無限大。"""
    regularized = info_sum + REGULARIZATION * np.eye(info_sum.shape[0])
    try:
        chol = np.linalg.cholesky(regularized)
    except np.linalg.LinAlgError:
        return float("inf")
    inv_chol = np.linalg.inv(chol)
    return float(np.sum(inv_chol**2))


def _feasible_start(n_candidates: int, n_select: int, partitions: dict, bounds: dict, rng: np.random.Generator, max_tries: int = 5000) -> np.ndarray:
    """制約を満たす初期配置をランダムに作る（違反を増やさない交換を繰り返す）。"""
    selected = np.zeros(n_candidates, dtype=bool)
    selected[rng.choice(n_candidates, size=n_select, replace=False)] = True
    current = violation_count(selected, partitions, bounds)
    for _ in range(max_tries):
        if current == 0:
            return selected
        trial = selected.copy()
        trial[rng.choice(np.flatnonzero(selected))] = False
        trial[rng.choice(np.flatnonzero(~selected))] = True
        trial_violation = violation_count(trial, partitions, bounds)
        if trial_violation <= current:
            selected, current = trial, trial_violation
    raise RuntimeError("制約を満たす初期配置が見つからない。slack を大きくするか制約を緩める")


def constrained_i_optimal(
    layout: WaferLayout,
    n_shots: int,
    xy_order: int,
    constraints: dict,
    rng: np.random.Generator,
    n_starts: int = 30,
    max_iterations: int = 300,
) -> SamplingPlan:
    """制約付きI最適な Shot の組を交換法で探す。"""
    if not 1 <= n_shots < layout.n_shots:
        raise ValueError(f"選ぶ Shot 数は 1〜{layout.n_shots - 1}: {n_shots}")
    info = shot_information(layout, xy_order)
    partitions = constraint_partitions(layout, constraints)
    bounds = group_bounds(partitions, n_shots, int(constraints.get("slack", 1)))
    n_candidates = layout.n_shots
    best_selected, best_value = None, float("inf")
    for _ in range(n_starts):
        selected = _feasible_start(n_candidates, n_shots, partitions, bounds, rng)
        current_info = info[selected].sum(axis=0)
        current_value = i_criterion(current_info)
        for _ in range(max_iterations):
            best_swap, best_swap_value = None, current_value
            for out_shot in np.flatnonzero(selected):
                for in_shot in np.flatnonzero(~selected):
                    trial = selected.copy()
                    trial[out_shot], trial[in_shot] = False, True
                    if partitions and violation_count(trial, partitions, bounds):
                        continue
                    value = i_criterion(current_info - info[out_shot] + info[in_shot])
                    if value < best_swap_value - 1e-12 * abs(best_swap_value):
                        best_swap, best_swap_value = (out_shot, in_shot), value
            if best_swap is None:
                break
            selected[best_swap[0]], selected[best_swap[1]] = False, True
            current_info = current_info - info[best_swap[0]] + info[best_swap[1]]
            current_value = best_swap_value
        if current_value < best_value:
            best_selected, best_value = selected.copy(), current_value
    feasible = violation_count(best_selected, partitions, bounds) == 0
    return SamplingPlan(n_shots, np.flatnonzero(best_selected), best_value / layout.n_marks, feasible)


def train_mark_mask(layout: WaferLayout, shot_indices: np.ndarray) -> np.ndarray:
    """選んだ Shot に属する Mark なら True。"""
    return np.isin(layout.shot_index, shot_indices)
