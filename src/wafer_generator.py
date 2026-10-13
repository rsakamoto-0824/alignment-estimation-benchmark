"""模擬アライメント計測値の生成。

1枚の Wafer の Mark ごとの値（X・Y それぞれ、単位 nm）は次の4成分の和とする。

1. 面内傾向：RMS 正規化 Zernike（動径次数 n ≤ 10 の66項）からランダムに10〜30項を選び、係数を正規乱数で与える。
   係数の標準偏差は高次ほど小さくする（σ_n = σ_0 · decay^n）。X と Y は別々に項を選ぶ。
2. Shot形状ばらつき：Mark番号ごとのオフセット（全Shot共通）。基準パターンに Wafer ごとの正規乱数を足す。
3. Scan方向の差：Wafer ごとの差 δ（基準値＋正規乱数）を、Scan方向1に +δ/2、方向2に −δ/2 として足す。
   補足検証用の交互作用（設定 scan_mark_interaction_std_nm、既定は0）を入れると、差が Mark 番号ごとに変わる：
   δ_k = δ + c_k（c_k は Wafer・Mark ごとの正規乱数）。Scan 方向で Shot の形が変わる状況にあたる。
4. 計測ノイズ：一様分布 U(−a, a)。幅 a は半径とともに増え、最外周の Mark で最大（初期設定 ±3 nm）。
   a(r) = a_中心 + (a_端 − a_中心)·(r / r_最外周)^p

真値（推定精度の評価に使う値）は 1〜3 の和、計測値は 1〜4 の和とする。
乱数は Wafer 番号と成分ごとに別の系列を使うので、ある成分の設定を変えても他の成分の値は変わらない。
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .geometry import SCAN_UP, WaferLayout
from .zernike import zernike_matrix_xy, zernike_modes

TREND_STREAM = 0
OFFSET_STREAM = 1
NOISE_STREAM = 2
INTERACTION_STREAM = 3  # 交互作用は別の系列にし、既定（0）のときに他の成分の値を変えない
AXES = ("X", "Y")


@dataclass(frozen=True)
class GenerationSettings:
    zernike_max_order: int
    n_terms_min: int
    n_terms_max: int
    coef_std_order0_nm: float
    coef_std_decay_per_order: float
    mark_offset_base_nm: np.ndarray  # (Mark数, 2)
    mark_offset_wafer_std_nm: float
    scan_difference_base_nm: np.ndarray  # (2,)
    scan_difference_wafer_std_nm: float
    noise_halfwidth_center_nm: float
    noise_halfwidth_edge_nm: float
    noise_radial_power: float
    scan_mark_interaction_std_nm: float = 0.0

    @classmethod
    def from_config(cls, config: dict) -> "GenerationSettings":
        gen = config["generation"]
        n_min, n_max = (int(v) for v in gen["n_terms_range"])
        settings = cls(
            zernike_max_order=int(gen["zernike_max_order"]),
            n_terms_min=n_min,
            n_terms_max=n_max,
            coef_std_order0_nm=float(gen["coef_std_order0_nm"]),
            coef_std_decay_per_order=float(gen["coef_std_decay_per_order"]),
            mark_offset_base_nm=np.asarray(gen["mark_offset_base_nm"], dtype=float),
            mark_offset_wafer_std_nm=float(gen["mark_offset_wafer_std_nm"]),
            scan_difference_base_nm=np.asarray(gen["scan_difference_base_nm"], dtype=float),
            scan_difference_wafer_std_nm=float(gen["scan_difference_wafer_std_nm"]),
            noise_halfwidth_center_nm=float(gen["noise_halfwidth_center_nm"]),
            noise_halfwidth_edge_nm=float(gen["noise_halfwidth_edge_nm"]),
            noise_radial_power=float(gen["noise_radial_power"]),
            scan_mark_interaction_std_nm=float(gen.get("scan_mark_interaction_std_nm", 0.0)),
        )
        settings.validate()
        return settings

    def validate(self) -> None:
        n_modes = len(zernike_modes(self.zernike_max_order))
        if not 1 <= self.n_terms_min <= self.n_terms_max <= n_modes:
            raise ValueError(f"n_terms_range は 1 ≤ 最小 ≤ 最大 ≤ {n_modes}（項の総数）にする")
        if self.coef_std_order0_nm <= 0 or not 0 < self.coef_std_decay_per_order <= 1:
            raise ValueError("係数の標準偏差は正、減衰率は 0 < decay ≤ 1 にする")
        if self.mark_offset_base_nm.ndim != 2 or self.mark_offset_base_nm.shape[1] != 2:
            raise ValueError("mark_offset_base_nm は [[x, y], ...]（Mark数 × 2）にする")
        if self.scan_difference_base_nm.shape != (2,):
            raise ValueError("scan_difference_base_nm は [x, y] にする")
        if min(self.mark_offset_wafer_std_nm, self.scan_difference_wafer_std_nm) < 0:
            raise ValueError("標準偏差は0以上にする")
        if not 0 <= self.noise_halfwidth_center_nm <= self.noise_halfwidth_edge_nm:
            raise ValueError("ノイズ幅は 0 ≤ 中心 ≤ 端 にする")
        if self.noise_radial_power <= 0:
            raise ValueError("noise_radial_power は正の値にする")
        if self.scan_mark_interaction_std_nm < 0:
            raise ValueError("scan_mark_interaction_std_nm は0以上にする")


@dataclass(frozen=True)
class WaferSample:
    """1枚分の値。配列は (Mark数, 2)（列0が X、列1が Y）。"""

    wafer_id: int
    trend: np.ndarray
    mark_offset: np.ndarray
    scan_offset: np.ndarray
    noise: np.ndarray
    trend_coefficients: np.ndarray  # (モード数, 2)。選ばなかった項は0
    mark_offset_by_mark: np.ndarray  # (Mark番号数, 2)
    scan_difference: np.ndarray  # (2,) 方向1 − 方向2（Mark によらない部分）
    scan_mark_interaction: np.ndarray  # (Mark番号数, 2) Mark ごとの Scan 差の上乗せ c_k（既定は0）

    @property
    def truth(self) -> np.ndarray:
        return self.trend + self.mark_offset + self.scan_offset

    @property
    def measured(self) -> np.ndarray:
        return self.truth + self.noise


class WaferGenerator:
    """配置を固定して、Wafer 番号から再現可能に模擬データを作る。"""

    def __init__(self, layout: WaferLayout, settings: GenerationSettings, master_seed: int):
        if settings.mark_offset_base_nm.shape[0] != layout.n_marks_per_shot:
            raise ValueError("mark_offset_base_nm の行数を Shot あたりの Mark 数にそろえる")
        self.layout = layout
        self.settings = settings
        self.master_seed = int(master_seed)
        self.modes = zernike_modes(settings.zernike_max_order)
        self.mode_orders = np.array([n for n, _ in self.modes])
        self.zernike_at_marks = zernike_matrix_xy(
            layout.x_mm / layout.wafer_radius_mm, layout.y_mm / layout.wafer_radius_mm, self.modes, "rms"
        )
        self.coef_std = settings.coef_std_order0_nm * settings.coef_std_decay_per_order**self.mode_orders
        self.noise_halfwidth = noise_halfwidth(layout.radius_mm, settings)

    def _rng(self, wafer_id: int, stream: int) -> np.random.Generator:
        return np.random.default_rng([self.master_seed, int(wafer_id), stream])

    def generate(self, wafer_id: int) -> WaferSample:
        s = self.settings
        n_modes = len(self.modes)
        rng_trend = self._rng(wafer_id, TREND_STREAM)
        coefficients = np.zeros((n_modes, 2))
        for axis in range(2):
            n_terms = int(rng_trend.integers(s.n_terms_min, s.n_terms_max + 1))
            chosen = rng_trend.choice(n_modes, size=n_terms, replace=False)
            coefficients[chosen, axis] = rng_trend.normal(0.0, self.coef_std[chosen])
        trend = self.zernike_at_marks @ coefficients

        rng_offset = self._rng(wafer_id, OFFSET_STREAM)
        by_mark = s.mark_offset_base_nm + rng_offset.normal(0.0, s.mark_offset_wafer_std_nm, s.mark_offset_base_nm.shape)
        scan_difference = s.scan_difference_base_nm + rng_offset.normal(0.0, s.scan_difference_wafer_std_nm, 2)
        mark_offset = by_mark[self.layout.mark_number - 1]
        sign = np.where(self.layout.direction == SCAN_UP, 0.5, -0.5)
        interaction = np.zeros_like(s.mark_offset_base_nm)
        if s.scan_mark_interaction_std_nm > 0:
            rng_interaction = self._rng(wafer_id, INTERACTION_STREAM)
            interaction = rng_interaction.normal(0.0, s.scan_mark_interaction_std_nm, s.mark_offset_base_nm.shape)
        scan_offset = sign[:, None] * (scan_difference[None, :] + interaction[self.layout.mark_number - 1])

        rng_noise = self._rng(wafer_id, NOISE_STREAM)
        noise = rng_noise.uniform(-1.0, 1.0, (self.layout.n_marks, 2)) * self.noise_halfwidth[:, None]
        return WaferSample(
            wafer_id=int(wafer_id),
            trend=trend,
            mark_offset=mark_offset,
            scan_offset=scan_offset,
            noise=noise,
            trend_coefficients=coefficients,
            mark_offset_by_mark=by_mark,
            scan_difference=scan_difference,
            scan_mark_interaction=interaction,
        )


def noise_halfwidth(radius_mm: np.ndarray, settings: GenerationSettings) -> np.ndarray:
    """一様ノイズの幅 a(r)。最外周の Mark（r が最大の点）でちょうど端の値になる。"""
    ratio = radius_mm / float(np.max(radius_mm))
    span = settings.noise_halfwidth_edge_nm - settings.noise_halfwidth_center_nm
    return settings.noise_halfwidth_center_nm + span * ratio**settings.noise_radial_power
