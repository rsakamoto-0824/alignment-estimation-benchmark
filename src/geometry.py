"""Wafer幾何：Shot・Mark配置、Scan方向、極座標（半径 r・方位角 θ）、XY⇔RT変換。

座標の約束（Overlay計測ルールに従う）
- Wafer中心を原点 (0, 0) とし、座標の単位は mm、計測値の単位は nm とする。
- Shot座標はWafer中心基準の絶対座標、Mark座標はShot中心基準の相対座標。
- 解析座標は x = Xmm + markXmm、y = Ymm + markYmm。
- 方位角は θ = atan2(y, x)（+x軸から反時計回り、範囲 (−π, π]）。ASML R&T の T（接線方向）の位置にあたる。
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd

SCAN_PATTERNS = ("alternate_column", "alternate_row", "checkerboard")
SCAN_UP = 1
SCAN_DOWN = 2


@dataclass(frozen=True)
class WaferLayout:
    """有効Shotの Mark 配置。配列はすべて Mark 単位（長さ M）。"""

    wafer_radius_mm: float
    marks: pd.DataFrame  # 標準テーブルの列（shotNo, Direction, Xmm, Ymm, Radius, markNo, markXmm, markYmm）と解析座標
    shots: pd.DataFrame  # 有効Shotの一覧（shotNo, Xmm, Ymm, Radius, Direction, column, row）

    @property
    def x_mm(self) -> np.ndarray:
        return self.marks["x_mm"].to_numpy()

    @property
    def y_mm(self) -> np.ndarray:
        return self.marks["y_mm"].to_numpy()

    @property
    def radius_mm(self) -> np.ndarray:
        return self.marks["r_mm"].to_numpy()

    @property
    def theta(self) -> np.ndarray:
        return self.marks["theta_rad"].to_numpy()

    @property
    def shot_index(self) -> np.ndarray:
        """0始まりの有効Shot番号（Markごと）。"""
        return self.marks["shot_index"].to_numpy()

    @property
    def mark_number(self) -> np.ndarray:
        return self.marks["markNo"].to_numpy()

    @property
    def direction(self) -> np.ndarray:
        return self.marks["Direction"].to_numpy()

    @property
    def n_marks(self) -> int:
        return len(self.marks)

    @property
    def n_shots(self) -> int:
        return len(self.shots)

    @property
    def n_marks_per_shot(self) -> int:
        return int(self.marks["markNo"].max())


def scan_direction(column: np.ndarray, row: np.ndarray, pattern: str) -> np.ndarray:
    if pattern == "alternate_column":
        parity = column % 2
    elif pattern == "alternate_row":
        parity = row % 2
    elif pattern == "checkerboard":
        parity = (column + row) % 2
    else:
        raise ValueError(f"scan_direction_pattern は {SCAN_PATTERNS} のいずれか: {pattern}")
    return np.where(parity == 0, SCAN_UP, SCAN_DOWN)


def build_layout(config: dict) -> WaferLayout:
    """設定から有効Shotと Mark 配置を作る。全 Mark が有効半径（半径 − 端の除外幅）の内側にある Shot を有効とする。"""
    wafer_cfg, shot_cfg = config["wafer"], config["shot"]
    radius_mm = float(wafer_cfg["diameter_mm"]) / 2.0
    usable_radius = radius_mm - float(wafer_cfg.get("edge_exclusion_mm", 0.0))
    width, height = (float(s) for s in shot_cfg["size_mm"])
    offset_x, offset_y = (float(s) for s in shot_cfg["grid_offset_mm"])
    marks_rel = np.asarray(shot_cfg["marks_rel_mm"], dtype=float)
    if width <= 0 or height <= 0:
        raise ValueError("Shot寸法は正の値にする")
    if marks_rel.ndim != 2 or marks_rel.shape[1] != 2 or len(marks_rel) < 2:
        raise ValueError("marks_rel_mm は [[x, y], ...] の形で2個以上指定する")
    if np.any(np.abs(marks_rel[:, 0]) > width / 2) or np.any(np.abs(marks_rel[:, 1]) > height / 2):
        raise ValueError("Mark は Shot の内側に置く")

    n_col = int(np.ceil(radius_mm / width)) + 1
    n_row = int(np.ceil(radius_mm / height)) + 1
    columns, rows = np.meshgrid(np.arange(-n_col, n_col + 1), np.arange(-n_row, n_row + 1))
    columns, rows = columns.ravel(), rows.ravel()
    center_x = columns * width + offset_x
    center_y = rows * height + offset_y
    # Overlay計測ルール：r < R（境界上は除外）
    mark_radius = np.hypot(center_x[:, None] + marks_rel[None, :, 0], center_y[:, None] + marks_rel[None, :, 1])
    valid = (mark_radius < usable_radius).all(axis=1)
    if not valid.any():
        raise ValueError("有効Shotがない。Shot寸法・オフセットを確認する")

    # 露光順の慣例に合わせ、上の行から左→右に番号を付ける
    order = np.lexsort((center_x[valid], -center_y[valid]))
    shot_x, shot_y = center_x[valid][order], center_y[valid][order]
    shot_col, shot_row = columns[valid][order], rows[valid][order]
    direction = scan_direction(shot_col, shot_row, shot_cfg.get("scan_direction_pattern", "alternate_column"))
    shots = pd.DataFrame(
        {
            "shotNo": np.arange(1, shot_x.size + 1),
            "Xmm": shot_x,
            "Ymm": shot_y,
            "Radius": np.hypot(shot_x, shot_y),
            "Direction": direction,
            "column": shot_col,
            "row": shot_row,
        }
    )

    n_per_shot = len(marks_rel)
    shot_index = np.repeat(np.arange(len(shots)), n_per_shot)
    mark_x_rel = np.tile(marks_rel[:, 0], len(shots))
    mark_y_rel = np.tile(marks_rel[:, 1], len(shots))
    x_mm = shot_x[shot_index] + mark_x_rel
    y_mm = shot_y[shot_index] + mark_y_rel
    marks = pd.DataFrame(
        {
            "shotNo": shots["shotNo"].to_numpy()[shot_index],
            "Direction": direction[shot_index],
            "Xmm": shot_x[shot_index],
            "Ymm": shot_y[shot_index],
            "Radius": shots["Radius"].to_numpy()[shot_index],
            "markNo": np.tile(np.arange(1, n_per_shot + 1), len(shots)),
            "markXmm": mark_x_rel,
            "markYmm": mark_y_rel,
            "x_mm": x_mm,
            "y_mm": y_mm,
            "r_mm": np.hypot(x_mm, y_mm),
            "theta_rad": np.arctan2(y_mm, x_mm),
            "shot_index": shot_index,
        }
    )
    return WaferLayout(wafer_radius_mm=radius_mm, marks=marks, shots=shots)


def xy_to_rt(u: np.ndarray, v: np.ndarray, theta: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """XY変位 (u, v) を半径方向 R・接線方向 T に変換する（e_R = (cosθ, sinθ)、e_T = (−sinθ, cosθ)）。"""
    cos_t, sin_t = np.cos(theta), np.sin(theta)
    return u * cos_t + v * sin_t, -u * sin_t + v * cos_t


def rt_to_xy(radial: np.ndarray, tangential: np.ndarray, theta: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    cos_t, sin_t = np.cos(theta), np.sin(theta)
    return radial * cos_t - tangential * sin_t, radial * sin_t + tangential * cos_t


def shot_quadrant(shots: pd.DataFrame) -> np.ndarray:
    """Shot中心の象限（1〜4）。偏角 [0, 90) を第1象限とし、軸上は反時計回りに次の象限へ含める。"""
    angle = np.mod(np.arctan2(shots["Ymm"].to_numpy(), shots["Xmm"].to_numpy()), 2 * np.pi)
    return (np.floor(angle / (np.pi / 2)).astype(int) % 4) + 1


def shot_radial_zone(shots: pd.DataFrame, wafer_radius_mm: float, edges: list[float]) -> np.ndarray:
    """Shot中心の正規化半径による同心円領域（0始まり）。最後の帯は右端を含む。"""
    rho = shots["Radius"].to_numpy() / wafer_radius_mm
    edges_arr = np.asarray(edges, dtype=float)
    index = np.searchsorted(edges_arr, rho, side="right") - 1
    return np.clip(index, 0, edges_arr.size - 2)
