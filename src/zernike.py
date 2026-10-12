"""実数値Zernike多項式。

定義（本プロジェクトの約束）
- 動径次数 n、方位次数 m（|m| ≤ n、n − |m| は偶数）。
- Z_n^m(ρ, θ) = N_n^m R_n^{|m|}(ρ) cos(mθ)   (m ≥ 0)
  Z_n^m(ρ, θ) = N_n^m R_n^{|m|}(ρ) sin(|m|θ)  (m < 0)
- R_n^m(ρ) = Σ_{s=0}^{(n−m)/2} (−1)^s (n−s)! / [s! ((n+m)/2−s)! ((n−m)/2−s)!] ρ^{n−2s}、R_n^m(1) = 1。
- 正規化：
  - "rms"  : N_n^m = sqrt(2(n+1)/(1+δ_{m0}))。単位円板上の平均で (1/π)∫ Z_j Z_k dA = δ_jk（Noll流）。
  - "none" : N_n^m = 1（Fringe流の非正規化。縁 ρ = 1 での振幅が1）。
- θ は +x 軸から反時計回り。ρ = r / R_w。
- モード番号は Fringe 番号を使う（同じ k = (n+|m|)/2 の中で |m| の大きい順、cos → sin、m = 0 が最後）。
  標準の Fringe 番号は k ≤ 5 の Z1〜Z36（と例外の Z37 = (12, 0)）だけに定まっている。n ≤ 7 のうち
  k ≥ 6 の (6,±6)・(7,±5)・(7,±7) は、同じ並べ方を延長した番号（37〜40, 50, 51）を使い、ラベルに「*」を付けて区別する。
  この延長番号の37は、37項 Fringe セットの Z37 = (12, 0) とは別物である。
"""
from __future__ import annotations

from math import factorial

import numpy as np

NORMALIZATIONS = ("rms", "none")


STANDARD_FRINGE_MAX_GROUP = 5


def fringe_index(n: int, m: int) -> int:
    """Fringe番号（1始まり）。例：(0,0)→1, (1,1)→2, (1,−1)→3, (2,0)→4, (4,0)→9, (6,0)→16, (10,0)→36。

    k = (n+|m|)/2 ≥ 6 は延長番号（is_standard_fringe で区別する）。
    """
    _check_mode(n, m)
    k = (n + abs(m)) // 2
    if m == 0:
        offset = 2 * k
    else:
        offset = 2 * (k - abs(m)) + (0 if m > 0 else 1)
    return k * k + 1 + offset


def zernike_modes(max_order: int) -> list[tuple[int, int]]:
    """動径次数 n ≤ max_order の全モード (n, m) を Fringe 番号順に返す。n ≤ 7 なら36項。"""
    if max_order < 0:
        raise ValueError("max_order は0以上")
    modes = [(n, m) for n in range(max_order + 1) for m in range(-n, n + 1, 2)]
    return sorted(modes, key=lambda mode: fringe_index(*mode))


def is_standard_fringe(n: int, m: int) -> bool:
    return (n + abs(m)) // 2 <= STANDARD_FRINGE_MAX_GROUP


def mode_label(n: int, m: int) -> str:
    star = "" if is_standard_fringe(n, m) else "*"
    return f"Z{fringe_index(n, m)}{star}(n={n},m={m})"


def _check_mode(n: int, m: int) -> None:
    if n < 0 or abs(m) > n or (n - abs(m)) % 2 != 0:
        raise ValueError(f"不正なZernikeモード (n={n}, m={m})")


def radial_polynomial(n: int, m: int, rho: np.ndarray) -> np.ndarray:
    _check_mode(n, m)
    m = abs(m)
    rho = np.asarray(rho, dtype=float)
    result = np.zeros_like(rho)
    for s in range((n - m) // 2 + 1):
        coefficient = (-1) ** s * factorial(n - s) / (
            factorial(s) * factorial((n + m) // 2 - s) * factorial((n - m) // 2 - s)
        )
        result = result + coefficient * rho ** (n - 2 * s)
    return result


def normalization_factor(n: int, m: int, normalization: str) -> float:
    if normalization == "rms":
        return float(np.sqrt(2.0 * (n + 1) / (2.0 if m == 0 else 1.0)))
    if normalization == "none":
        return 1.0
    raise ValueError(f"normalization は {NORMALIZATIONS} のいずれか: {normalization}")


def zernike(n: int, m: int, rho: np.ndarray, theta: np.ndarray, normalization: str = "rms") -> np.ndarray:
    radial = radial_polynomial(n, m, rho)
    angular = np.cos(m * theta) if m >= 0 else np.sin(-m * theta)
    return normalization_factor(n, m, normalization) * radial * angular


def zernike_matrix_xy(
    x_norm: np.ndarray, y_norm: np.ndarray, modes: list[tuple[int, int]], normalization: str = "rms"
) -> np.ndarray:
    """正規化座標 (x/R_w, y/R_w) で全モードを並べた行列 (点数 × モード数)。

    Zernike多項式は x, y の多項式なので中心でも滑らか。中心で θ が不定でも m > 0 の項は ρ^m を因子に持ち0になる。
    """
    rho = np.hypot(x_norm, y_norm)
    theta = np.arctan2(y_norm, x_norm)
    return np.column_stack([zernike(n, m, rho, theta, normalization) for n, m in modes])


def disk_quadrature(n_rho: int = 16, n_theta: int = 64) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """単位円板の求積点と重み（重みの合計は1＝円板平均）。

    ρ方向はガウス・ルジャンドル（重み ρ を含めて変数変換）、θ方向は等間隔。
    x, y の多項式（次数 ≤ 2·n_rho − 2 かつ方位調和 < n_theta）を厳密に積分できる。
    """
    nodes, weights = np.polynomial.legendre.leggauss(n_rho)
    rho = 0.5 * (nodes + 1.0)
    rho_weight = 0.5 * weights * rho * 2.0  # ∫_0^1 f ρ dρ を平均にするため ×2（∫_0^1 ρ dρ = 1/2）
    theta = 2.0 * np.pi * np.arange(n_theta) / n_theta
    rho_grid, theta_grid = np.meshgrid(rho, theta, indexing="ij")
    weight_grid = np.repeat(rho_weight[:, None], n_theta, axis=1) / n_theta
    x = (rho_grid * np.cos(theta_grid)).ravel()
    y = (rho_grid * np.sin(theta_grid)).ravel()
    return x, y, weight_grid.ravel()


def project_onto_zernike(
    values: np.ndarray, x_quad: np.ndarray, y_quad: np.ndarray, weights: np.ndarray, modes: list[tuple[int, int]]
) -> np.ndarray:
    """求積点上の値を RMS 正規化 Zernike 係数に分解する（円板上の直交性を使う）。

    values の形は (求積点数,) または (求積点数, 列数)。
    """
    basis = zernike_matrix_xy(x_quad, y_quad, modes, "rms")
    return basis.T @ (weights[:, None] * values if values.ndim == 2 else weights * values)
