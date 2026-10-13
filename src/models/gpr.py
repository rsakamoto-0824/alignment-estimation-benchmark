"""ガウス過程回帰（GPR）。MATLAB fitrgp の10種類のカーネルと、質的変数の3つの扱い方。

カーネル（r は長さスケールで割った距離。ARD は説明変数ごとに長さスケールを持つ）
- exponential           : σf² exp(−r)
- squaredexponential    : σf² exp(−r²/2)
- matern32              : σf² (1 + √3 r) exp(−√3 r)
- matern52              : σf² (1 + √5 r + 5r²/3) exp(−√5 r)
- rationalquadratic     : σf² (1 + r²/(2α))^(−α)
- ard***                : 上の5種類の ARD 版
fitrgp の既定（FitMethod = 'exact'、BasisFunction = 'constant'）に合わせ、
平均の基底関数 H の係数 β は一般化最小二乗で求め（尤度から消去したプロファイル尤度）、
超パラメータ（長さスケール・σf・α・ノイズ σn）は対数周辺尤度の最大化で決める（初期値も fitrgp と同じ考え方）。

質的変数（Scan方向・Mark番号）の扱い方
- none    : 使わない（基底は定数のみ）
- basis   : 効果コードを基底関数 H に加え、β と同時に推定する（fitrgp の BasisFunction に行列を渡すのと同じ）
- basis_int : basis に Scan方向 × Mark番号 の交互作用の列（効果コードの積）を加える
- additive  : 加法カーネル。k = k_空間 + τ_scan²·[Scan方向が同じ] + τ_mark²·[Mark番号が同じ]、基底は定数のみ。
              質的変数の効果を平均0・分散 τ² の確率変数とみなす（変量効果）ので、点が少ないと効果を0へ縮める。
              τ も周辺尤度で推定する。τ → ∞ の極限が basis と同じになる（tests/test_gpr_additive.py で確認）
- additive_int : additive に τ_int²·[Scan方向と Mark番号の両方が同じ] を加える（交互作用）
- mixed     : 混合。Scan方向（2水準）は基底関数（固定効果）、Mark番号は加法カーネル（変量効果）。
              2水準しかない Scan方向は τ の推定が不安定で 0 に縮みやすいため、固定効果にする
- mixed_int : mixed に交互作用の項 τ_int²·[両方が同じ] を加える
- backfit : Backfitting。質的変数の効果を計測値の群平均で初期化し、
            ① 効果を除いた残差で GPR の超パラメータを推定し直す（前回の値から開始）
            ② 超パラメータを固定して GPR と質的変数を交互に当てはめ直す
            を、効果と超パラメータが変わらなくなるまで繰り返す。
            ②の内側の交互当てはめは収束値（質的変数を基底に入れた一般化最小二乗の解）を直接計算して高速化する
            （収束値が一致することは tests/test_gpr.py で確認）。
backfit は同じ尤度を「超パラメータ」と「平均の係数」で交互に最大化する座標上昇法なので、
収束すれば basis（同時最大化）と同じ停留点に着く。両者の差は、異なる局所解に着く場合と、反復が収束しない場合に出る。
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
from scipy.linalg import cho_factor, cho_solve, LinAlgError
from scipy.optimize import minimize

KERNEL_NAMES = (
    "exponential",
    "squaredexponential",
    "matern32",
    "matern52",
    "rationalquadratic",
    "ardexponential",
    "ardsquaredexponential",
    "ardmatern32",
    "ardmatern52",
    "ardrationalquadratic",
)
FACTOR_MODES = ("none", "basis", "backfit", "basis_int", "additive", "additive_int", "mixed", "mixed_int")
ADDITIVE_MODES = ("additive", "additive_int", "mixed", "mixed_int")  # 質的変数のカーネル項を持つ扱い方
MIXED_MODES = ("mixed", "mixed_int")  # Scan方向を基底関数にも入れる扱い方
LOG_2PI = np.log(2.0 * np.pi)
SQRT3 = np.sqrt(3.0)
SQRT5 = np.sqrt(5.0)
# 超パラメータの探索範囲（説明変数は Wafer 半径で割った無次元量、σ は学習データの標準偏差に対する倍率）
LENGTH_SCALE_BOUNDS = (1e-3, 1e3)
SIGNAL_STD_BOUNDS = (1e-3, 1e3)
NOISE_STD_BOUNDS = (1e-2, 1e1)  # 下限は fitrgp の SigmaLowerBound 既定（1e-2 × std(y)）に合わせる
ALPHA_BOUNDS = (1e-3, 1e3)
CATEGORICAL_STD_BOUNDS = (1e-4, 1e1)  # 質的変数のカーネル項 τ（学習データの標準偏差に対する倍率）。下限は「効果なし」まで縮められる値
CATEGORICAL_STD_START = 0.2  # τ の初期値（学習データの標準偏差に対する倍率）
FAILED_OBJECTIVE = 1e20
BACKFIT_PARAM_TOLERANCE = 1e-3  # 超パラメータ（対数）の変化がこれ未満で収束とみなす


@dataclass(frozen=True)
class KernelSpec:
    name: str
    family: str  # exp, se, m32, m52, rq
    ard: bool

    @classmethod
    def parse(cls, name: str) -> "KernelSpec":
        if name not in KERNEL_NAMES:
            raise ValueError(f"カーネルは {KERNEL_NAMES} のいずれか: {name}")
        ard = name.startswith("ard")
        base = name[3:] if ard else name
        family = {
            "exponential": "exp",
            "squaredexponential": "se",
            "matern32": "m32",
            "matern52": "m52",
            "rationalquadratic": "rq",
        }[base]
        return cls(name, family, ard)


@dataclass(frozen=True)
class PairwiseGeometry:
    """説明変数の差の2乗を説明変数ごとにまとめたもの（Shot 配置が同じなら全 Wafer で共通）。"""

    train_sq: np.ndarray  # (G, n, n)
    cross_sq: np.ndarray  # (G, m, n) 評価点 × 学習点
    feature_std: np.ndarray  # (G,) 学習点での各説明変数の標準偏差（初期値に使う）

    @classmethod
    def build(cls, train: np.ndarray, test: np.ndarray, groups: np.ndarray) -> "PairwiseGeometry":
        n_groups = int(groups.max()) + 1
        train_sq = np.zeros((n_groups, train.shape[0], train.shape[0]))
        cross_sq = np.zeros((n_groups, test.shape[0], train.shape[0]))
        feature_std = np.zeros(n_groups)
        for column, group in enumerate(groups):
            diff = train[:, column][:, None] - train[:, column][None, :]
            train_sq[group] += diff**2
            cross_sq[group] += (test[:, column][:, None] - train[:, column][None, :]) ** 2
        for group in range(n_groups):
            # 1変数を複数列に展開した場合（cos θ, sin θ）は各列の標準偏差の2乗和の平方根
            feature_std[group] = np.sqrt(np.sum(np.var(train[:, groups == group], axis=0)))
        return cls(train_sq, cross_sq, np.maximum(feature_std, 1e-3))

    @property
    def n_groups(self) -> int:
        return self.train_sq.shape[0]


@dataclass(frozen=True)
class CategoricalComponent:
    """質的変数のカーネル項 τ²·[水準が同じ] の 0/1 行列（学習点どうし、評価点 × 学習点）。"""

    name: str
    train_same: np.ndarray  # (n, n)
    cross_same: np.ndarray  # (m, n)

    @classmethod
    def build(cls, name: str, train_levels: np.ndarray, test_levels: np.ndarray) -> "CategoricalComponent":
        train_levels = np.asarray(train_levels)
        test_levels = np.asarray(test_levels)
        return cls(
            name,
            (train_levels[:, None] == train_levels[None, :]).astype(float),
            (test_levels[:, None] == train_levels[None, :]).astype(float),
        )


@dataclass
class GPFit:
    log_params: np.ndarray
    beta: np.ndarray
    alpha_vector: np.ndarray  # K_y⁻¹ (y − Hβ)
    nll: float
    edf: float
    converged: bool
    n_evaluations: int
    extra: dict = field(default_factory=dict)


class GaussianProcess:
    """1つのカーネル・1つの説明変数の組での GPR。学習点・評価点は固定し、目的変数だけを差し替えて使う。"""

    def __init__(
        self,
        kernel: KernelSpec,
        geometry: PairwiseGeometry,
        max_iterations: int = 300,
        categorical: tuple[CategoricalComponent, ...] = (),
    ):
        self.kernel = kernel
        self.geometry = geometry
        self.max_iterations = int(max_iterations)
        self.categorical = tuple(categorical)
        self.n_length = geometry.n_groups if kernel.ard else 1
        self.n_train = geometry.train_sq.shape[1]
        self._train_sq_total = geometry.train_sq.sum(axis=0)
        self._cross_sq_total = geometry.cross_sq.sum(axis=0)

    # ---- パラメータの並び：[log ℓ (1 または G 個), log σf, (log α), log τ (質的変数の項ごと), log σn]
    @property
    def n_params(self) -> int:
        return self.n_length + 1 + (1 if self.kernel.family == "rq" else 0) + len(self.categorical) + 1

    @property
    def categorical_offset(self) -> int:
        """log τ が始まる位置。"""
        return self.n_length + 1 + (1 if self.kernel.family == "rq" else 0)

    def initial_log_params(self, y: np.ndarray) -> np.ndarray:
        """fitrgp の既定の初期値：ℓ = 説明変数の標準偏差（等方は平均）、σf = σn = std(y)/√2、α = 1。"""
        std_y = max(float(np.std(y)), 1e-6)
        if self.kernel.ard:
            lengths = self.geometry.feature_std
        else:
            lengths = np.array([np.mean(self.geometry.feature_std)])
        params = list(np.log(lengths)) + [np.log(std_y / np.sqrt(2.0))]
        if self.kernel.family == "rq":
            params.append(0.0)
        params += [np.log(CATEGORICAL_STD_START * std_y)] * len(self.categorical)
        params.append(np.log(std_y / np.sqrt(2.0)))
        return np.array(params)

    def bounds(self, y: np.ndarray) -> list[tuple[float, float]]:
        std_y = max(float(np.std(y)), 1e-6)
        result = [tuple(np.log(LENGTH_SCALE_BOUNDS))] * self.n_length
        result.append((np.log(SIGNAL_STD_BOUNDS[0] * std_y), np.log(SIGNAL_STD_BOUNDS[1] * std_y)))
        if self.kernel.family == "rq":
            result.append(tuple(np.log(ALPHA_BOUNDS)))
        result += [(np.log(CATEGORICAL_STD_BOUNDS[0] * std_y), np.log(CATEGORICAL_STD_BOUNDS[1] * std_y))] * len(self.categorical)
        result.append((np.log(NOISE_STD_BOUNDS[0] * std_y), np.log(NOISE_STD_BOUNDS[1] * std_y)))
        return result

    def _split(self, log_params: np.ndarray) -> tuple[np.ndarray, float, float, np.ndarray, float]:
        lengths = np.exp(log_params[: self.n_length])
        signal_var = float(np.exp(2.0 * log_params[self.n_length]))
        alpha = float(np.exp(log_params[self.n_length + 1])) if self.kernel.family == "rq" else 1.0
        start = self.categorical_offset
        categorical_var = np.exp(2.0 * log_params[start : start + len(self.categorical)])
        noise_var = float(np.exp(2.0 * log_params[-1]))
        return lengths, signal_var, alpha, categorical_var, noise_var

    def categorical_std(self, log_params: np.ndarray) -> dict[str, float]:
        """推定した質的変数の項の τ（名前ごと）。"""
        _, _, _, categorical_var, _ = self._split(log_params)
        return {component.name: float(np.sqrt(var)) for component, var in zip(self.categorical, categorical_var)}

    def _scaled_sq(self, sq_by_group: np.ndarray, sq_total: np.ndarray, lengths: np.ndarray) -> np.ndarray:
        if self.kernel.ard:
            return np.tensordot(1.0 / lengths**2, sq_by_group, axes=1)
        return sq_total / lengths[0] ** 2

    def _profile(self, r2: np.ndarray, alpha: float) -> tuple[np.ndarray, np.ndarray | None, np.ndarray | None]:
        """g(r²)、h = dg/d(r²)、dg/dlog α を返す（σf² を掛ける前）。"""
        family = self.kernel.family
        if family == "se":
            g = np.exp(-0.5 * r2)
            return g, -0.5 * g, None
        if family == "rq":
            u = 1.0 + r2 / (2.0 * alpha)
            g = u ** (-alpha)
            h = -0.5 * u ** (-alpha - 1.0)
            dalpha = alpha * g * (-np.log(u) + r2 / (2.0 * alpha * u))
            return g, h, dalpha
        r = np.sqrt(np.maximum(r2, 0.0))
        if family == "exp":
            g = np.exp(-r)
            with np.errstate(divide="ignore", invalid="ignore"):
                h = np.where(r > 0, -g / (2.0 * np.where(r > 0, r, 1.0)), 0.0)
            return g, h, None
        if family == "m32":
            e = np.exp(-SQRT3 * r)
            return (1.0 + SQRT3 * r) * e, -1.5 * e, None
        if family == "m52":
            e = np.exp(-SQRT5 * r)
            return (1.0 + SQRT5 * r + (5.0 / 3.0) * r2) * e, -(5.0 / 6.0) * (1.0 + SQRT5 * r) * e, None
        raise ValueError(family)

    def _kernel_and_grads(self, log_params: np.ndarray) -> tuple[np.ndarray, list[np.ndarray], float]:
        lengths, signal_var, alpha, categorical_var, noise_var = self._split(log_params)
        r2 = self._scaled_sq(self.geometry.train_sq, self._train_sq_total, lengths)
        g, h, dalpha = self._profile(r2, alpha)
        kernel = signal_var * g
        grads = []
        if self.kernel.ard:
            for group in range(self.n_length):
                grads.append(signal_var * h * (-2.0 * self.geometry.train_sq[group] / lengths[group] ** 2))
        else:
            grads.append(signal_var * h * (-2.0 * r2))
        grads.append(2.0 * kernel)
        if dalpha is not None:
            grads.append(signal_var * dalpha)
        for component, var in zip(self.categorical, categorical_var):
            kernel = kernel + var * component.train_same
            grads.append(2.0 * var * component.train_same)
        return kernel, grads, noise_var

    def cross_kernel(self, log_params: np.ndarray) -> np.ndarray:
        lengths, signal_var, alpha, categorical_var, _ = self._split(log_params)
        r2 = self._scaled_sq(self.geometry.cross_sq, self._cross_sq_total, lengths)
        cross = signal_var * self._profile(r2, alpha)[0]
        for component, var in zip(self.categorical, categorical_var):
            cross = cross + var * component.cross_same
        return cross

    def objective(self, log_params: np.ndarray, y: np.ndarray, basis: np.ndarray) -> tuple[float, np.ndarray]:
        """負の対数周辺尤度（β を消去したプロファイル尤度）とその勾配。"""
        kernel, grads, noise_var = self._kernel_and_grads(log_params)
        ky = kernel + noise_var * np.eye(self.n_train)
        try:
            factor = cho_factor(ky, lower=True, check_finite=False)
        except LinAlgError:
            return FAILED_OBJECTIVE, np.zeros_like(log_params)
        ky_inv = cho_solve(factor, np.eye(self.n_train), check_finite=False)
        kinv_h = ky_inv @ basis
        kinv_y = ky_inv @ y
        try:
            beta = np.linalg.solve(basis.T @ kinv_h, basis.T @ kinv_y)
        except np.linalg.LinAlgError:
            return FAILED_OBJECTIVE, np.zeros_like(log_params)
        a = kinv_y - kinv_h @ beta
        residual = y - basis @ beta
        log_det = 2.0 * np.sum(np.log(np.diag(factor[0])))
        value = 0.5 * float(residual @ a) + 0.5 * log_det + 0.5 * self.n_train * LOG_2PI
        weight = ky_inv - np.outer(a, a)
        gradient = np.array([0.5 * np.sum(weight * grad) for grad in grads] + [noise_var * np.trace(weight)])
        if not np.isfinite(value) or not np.all(np.isfinite(gradient)):
            return FAILED_OBJECTIVE, np.zeros_like(log_params)
        return value, gradient

    def fit(self, y: np.ndarray, basis: np.ndarray, start: np.ndarray | None = None) -> GPFit:
        x0 = self.initial_log_params(y) if start is None else start
        bounds = self.bounds(y)
        x0 = np.clip(x0, [b[0] for b in bounds], [b[1] for b in bounds])
        result = minimize(
            self.objective,
            x0,
            args=(y, basis),
            jac=True,
            method="L-BFGS-B",
            bounds=bounds,
            options={"maxiter": self.max_iterations},
        )
        log_params = result.x
        if not np.isfinite(result.fun) or result.fun >= FAILED_OBJECTIVE:
            log_params = x0
        return self.condition(log_params, y, basis, nll=float(result.fun), converged=bool(result.success), n_evaluations=int(result.nfev))

    def condition(self, log_params: np.ndarray, y: np.ndarray, basis: np.ndarray, nll: float = float("nan"), converged: bool = True, n_evaluations: int = 0) -> GPFit:
        """超パラメータを固定して β・K_y⁻¹(y − Hβ)・有効自由度を求める。"""
        kernel, _, noise_var = self._kernel_and_grads(log_params)
        ky = kernel + noise_var * np.eye(self.n_train)
        factor = cho_factor(ky + 1e-10 * np.trace(ky) / self.n_train * np.eye(self.n_train), lower=True, check_finite=False)
        ky_inv = cho_solve(factor, np.eye(self.n_train), check_finite=False)
        kinv_h = ky_inv @ basis
        gram = basis.T @ kinv_h
        beta = np.linalg.solve(gram, kinv_h.T @ y)
        a = ky_inv @ (y - basis @ beta)
        # 学習点の当てはめ値 ŷ = S y、S = I − σn² P、P = K_y⁻¹ − K_y⁻¹ H (Hᵀ K_y⁻¹ H)⁻¹ Hᵀ K_y⁻¹
        trace_p = np.trace(ky_inv) - np.trace(np.linalg.solve(gram, kinv_h.T @ kinv_h))
        edf = self.n_train - noise_var * trace_p
        return GPFit(log_params, beta, a, nll, float(edf), converged, n_evaluations)

    def fitted_train(self, fit: GPFit, basis: np.ndarray) -> np.ndarray:
        kernel, _, _ = self._kernel_and_grads(fit.log_params)
        return basis @ fit.beta + kernel @ fit.alpha_vector

    def predict(self, fit: GPFit, basis_test: np.ndarray) -> np.ndarray:
        return basis_test @ fit.beta + self.cross_kernel(fit.log_params) @ fit.alpha_vector


@dataclass
class FactorGPResult:
    prediction: np.ndarray
    edf: float
    log_params: np.ndarray
    n_backfit_iterations: int
    backfit_converged: bool
    optimizer_converged: bool
    factor_effects: np.ndarray  # 質的変数の効果コードの係数（none では空）


def fit_predict_gpr(
    gp: GaussianProcess,
    y: np.ndarray,
    factors_train: np.ndarray,
    factors_test: np.ndarray,
    mode: str,
    backfit_max_iterations: int = 20,
    backfit_tolerance: float = 1e-3,
) -> FactorGPResult:
    """質的変数の扱い方 mode で GPR を当てはめ、評価点を推定する。"""
    n_train, n_test = factors_train.shape[0], factors_test.shape[0]
    ones_train, ones_test = np.ones((n_train, 1)), np.ones((n_test, 1))
    if mode == "none":
        fit = gp.fit(y, ones_train)
        return FactorGPResult(gp.predict(fit, ones_test), fit.edf, fit.log_params, 0, True, fit.converged, np.zeros(0))
    if mode in ("basis", "basis_int"):
        # basis_int では factors_train / factors_test に交互作用の列を含めて渡す
        basis_train = np.hstack([ones_train, factors_train])
        basis_test = np.hstack([ones_test, factors_test])
        fit = gp.fit(y, basis_train)
        return FactorGPResult(gp.predict(fit, basis_test), fit.edf, fit.log_params, 0, True, fit.converged, fit.beta[1:])
    if mode in ADDITIVE_MODES:
        if not gp.categorical:
            raise ValueError("加法カーネルには質的変数のカーネル項（categorical）を持つ GaussianProcess を渡す")
        if mode in MIXED_MODES:
            # factors_train / factors_test には固定効果にする列（Scan方向の効果コード）だけを渡す
            basis_train, basis_test = np.hstack([ones_train, factors_train]), np.hstack([ones_test, factors_test])
        else:
            basis_train, basis_test = ones_train, ones_test
        fit = gp.fit(y, basis_train)
        return FactorGPResult(gp.predict(fit, basis_test), fit.edf, fit.log_params, 0, True, fit.converged, fit.beta[1:])
    if mode != "backfit":
        raise ValueError(f"質的変数の扱いは {FACTOR_MODES} のいずれか: {mode}")

    # 質的変数の列は学習点で中心化し、定数は GPR 側に持たせる（識別のため）
    center = factors_train.mean(axis=0)
    design = factors_train - center
    joint_basis_train = np.hstack([ones_train, design])
    joint_basis_test = np.hstack([ones_test, factors_test - center])
    # 初期値：質的変数の効果を計測値から最小二乗（群平均）で求め、その残差から GPR を始める
    effects, *_ = np.linalg.lstsq(design, y - y.mean(), rcond=None)
    log_params = None
    converged = False
    optimizer_ok = True
    iteration = 0
    for iteration in range(1, backfit_max_iterations + 1):
        # GPR の段：質的変数の効果を除いた残差で超パラメータを推定し直す（前回の値から開始）
        fit = gp.fit(y - design @ effects, ones_train, start=log_params)
        params_change = float("inf") if log_params is None else float(np.max(np.abs(fit.log_params - log_params)))
        log_params = fit.log_params
        optimizer_ok = fit.converged
        # 質的変数の段：超パラメータを固定して GPR と質的変数を交互に当てはめ直したときの収束値を直接求める
        # （固定した超パラメータでの Backfitting の極限は、質的変数を基底に入れた一般化最小二乗の解に一致する）
        joint = gp.condition(log_params, y, joint_basis_train)
        new_effects = joint.beta[1:]
        change = float(np.sqrt(np.mean((design @ (new_effects - effects)) ** 2)))
        effects = new_effects
        if change < backfit_tolerance and params_change < BACKFIT_PARAM_TOLERANCE:
            converged = True
            break
    final = gp.condition(log_params, y, joint_basis_train)
    return FactorGPResult(gp.predict(final, joint_basis_test), final.edf, log_params, iteration, converged, optimizer_ok, final.beta[1:])


def classic_backfit_gpr(
    gp: GaussianProcess,
    y: np.ndarray,
    factors_train: np.ndarray,
    factors_test: np.ndarray,
    order: str,
    max_iterations: int = 200,
    tolerance: float = 1e-3,
) -> FactorGPResult:
    """補足検証用：内側の反復を省略しない、教科書どおりの Backfitting。

    1回の反復で「GPR を残差に当てはめ直す（超パラメータも推定し直す）」と「質的変数の効果を最小二乗で求め直す」を1回ずつ行う。
    order = "gp_first"     : 効果0から始める（GPR を先に当てはめる）
    order = "factor_first" : 効果を計測値の群平均で初期化する（本計算の backfit と同じ初期値）
    """
    if order not in ("gp_first", "factor_first"):
        raise ValueError("order は gp_first か factor_first")
    n_train, n_test = factors_train.shape[0], factors_test.shape[0]
    ones_train, ones_test = np.ones((n_train, 1)), np.ones((n_test, 1))
    center = factors_train.mean(axis=0)
    design = factors_train - center
    if order == "gp_first":
        effects = np.zeros(design.shape[1])
    else:
        effects, *_ = np.linalg.lstsq(design, y - y.mean(), rcond=None)
    log_params = None
    converged = False
    optimizer_ok = True
    iteration = 0
    for iteration in range(1, max_iterations + 1):
        fit = gp.fit(y - design @ effects, ones_train, start=log_params)
        params_change = float("inf") if log_params is None else float(np.max(np.abs(fit.log_params - log_params)))
        log_params = fit.log_params
        optimizer_ok = fit.converged
        smooth = gp.fitted_train(fit, ones_train)
        new_effects, *_ = np.linalg.lstsq(design, y - smooth, rcond=None)
        change = float(np.sqrt(np.mean((design @ (new_effects - effects)) ** 2)))
        effects = new_effects
        if change < tolerance and params_change < BACKFIT_PARAM_TOLERANCE:
            converged = True
            break
    final = gp.condition(log_params, y - design @ effects, ones_train)
    prediction = gp.predict(final, ones_test) + (factors_test - center) @ effects
    joint = gp.condition(log_params, y, np.hstack([ones_train, design]))
    return FactorGPResult(prediction, joint.edf, log_params, iteration, converged, optimizer_ok, effects)
