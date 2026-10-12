"""比較する手法の一覧と、Shot 数ごとの前計算（学習点・評価点が同じなら全 Wafer で共通）。

手法の識別子（method）
- GPR_<カーネル>_<説明変数>_<質的変数の扱い>   例：GPR_ardmatern52_XYR_backfit
- TPS_<説明変数>
- OK_<バリオグラム>_<説明変数>（通常 Kriging）、UK_<バリオグラム>_<説明変数>（Universal Kriging）
- GAM_<説明変数>（Scan方向・Mark番号を質的変数として含む）
- XY5、RT4、RT5（説明変数・質的変数は使わない）
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field

import numpy as np

from .basis import distance_features, factor_design, feature_groups
from .geometry import WaferLayout
from .models.gam import AdditiveModel
from .models.gpr import GaussianProcess, KernelSpec, PairwiseGeometry, fit_predict_gpr
from .models.kriging import Kriging
from .models.linear_models import polynomial_operator, rt_operator
from .models.tps import ThinPlateSpline

FAMILY_ORDER = ("GPR", "TPS", "OK", "UK", "GAM", "XY", "RT")


@dataclass(frozen=True)
class MethodSpec:
    method: str
    family: str  # GPR, TPS, OK, UK, GAM, XY, RT
    feature_set: str  # XY, XYR, XYRT、または "-"（使わない）
    variant: str  # カーネル名・バリオグラム名・次数など
    factor_mode: str  # none, basis, backfit、GAM は "factor"、使わない手法は "none"


def build_method_specs(config: dict) -> list[MethodSpec]:
    cfg = config["methods"]
    specs: list[MethodSpec] = []
    for feature_set in cfg["feature_sets"]:
        for kernel in cfg["gpr_kernels"]:
            for mode in cfg["gpr_factor_modes"]:
                specs.append(MethodSpec(f"GPR_{kernel}_{feature_set}_{mode}", "GPR", feature_set, kernel, mode))
        specs.append(MethodSpec(f"TPS_{feature_set}", "TPS", feature_set, "tps", "none"))
        for kriging, family in (("ordinary", "OK"), ("universal", "UK")):
            for variogram in cfg["kriging_variograms"]:
                specs.append(MethodSpec(f"{family}_{variogram}_{feature_set}", family, feature_set, variogram, "none"))
        specs.append(MethodSpec(f"GAM_{feature_set}", "GAM", feature_set, "pspline", "factor"))
    order = int(cfg["polynomial_order"])
    specs.append(MethodSpec(f"XY{order}", "XY", "-", f"order{order}", "none"))
    for rt_order in cfg["rt_orders"]:
        specs.append(MethodSpec(f"RT{rt_order}", "RT", "-", f"order{rt_order}", "none"))
    return specs


@dataclass
class MethodOutput:
    estimate: np.ndarray  # (評価点, 2)
    edf: tuple[float, float]
    aux: tuple[float, float]  # 手法ごとの代表的な診断値（GPR: σn [nm]、Kriging: ナゲット、TPS: log10 nλ、GAM: log10 λ の平均）
    iterations: tuple[float, float]  # Backfitting の反復回数（他は NaN）
    converged: bool
    seconds: float
    extra: dict = field(default_factory=dict)  # GPR の超パラメータ（ls<番号>_<軸>：長さスケール、sf_<軸>：σf、alpha_<軸>：α）


class LevelContext:
    """1つの Shot 数（= 1つのサンプリング計画）での前計算。"""

    def __init__(self, layout: WaferLayout, train_mask: np.ndarray, config: dict, specs: list[MethodSpec]):
        cfg = config["methods"]
        self.train_mask = train_mask
        self.test_mask = ~train_mask
        self.n_train = int(train_mask.sum())
        self.n_test = int(self.test_mask.sum())
        radius = layout.wafer_radius_mm
        x, y = layout.x_mm, layout.y_mm
        factors = factor_design(layout.direction, layout.mark_number, layout.n_marks_per_shot)
        self.factors_train = factors[train_mask]
        self.factors_test = factors[self.test_mask]
        self.outer_mask = (layout.radius_mm[self.test_mask] / radius) >= float(config["evaluation"]["outer_radius_ratio"])
        self.cfg = cfg
        self.specs = {spec.method: spec for spec in specs}
        self._gp: dict[tuple[str, str], GaussianProcess] = {}
        self._tps: dict[str, ThinPlateSpline] = {}
        self._kriging: dict[tuple[str, str, str], Kriging] = {}
        self._gam: dict[str, AdditiveModel] = {}
        self._linear = {}

        needed_sets = {spec.feature_set for spec in specs if spec.feature_set != "-"}
        geometries = {}
        features = {}
        for feature_set in needed_sets:
            feats = distance_features(x, y, feature_set, radius)
            features[feature_set] = (feats[train_mask], feats[self.test_mask])
            geometries[feature_set] = PairwiseGeometry.build(feats[train_mask], feats[self.test_mask], feature_groups(feature_set))
        grid_cfg = cfg["tps_lambda_grid"]
        log10_grid = np.linspace(grid_cfg["log10_min"], grid_cfg["log10_max"], int(grid_cfg["n"]))
        points = {
            "x": x / radius,
            "y": y / radius,
            "r": layout.radius_mm / radius,
            "theta": layout.theta,
        }
        points_train = {key: value[train_mask] for key, value in points.items()}
        points_test = {key: value[self.test_mask] for key, value in points.items()}
        xy_norm = np.column_stack([x, y]) / radius
        for spec in specs:
            if spec.family == "GPR":
                key = (spec.variant, spec.feature_set)
                if key not in self._gp:
                    self._gp[key] = GaussianProcess(
                        KernelSpec.parse(spec.variant), geometries[spec.feature_set], int(cfg["gpr_optimizer_max_iterations"])
                    )
            elif spec.family == "TPS":
                self._tps[spec.feature_set] = ThinPlateSpline(*features[spec.feature_set], log10_grid)
            elif spec.family in ("OK", "UK"):
                kind = "ordinary" if spec.family == "OK" else "universal"
                self._kriging[(spec.family, spec.variant, spec.feature_set)] = Kriging(
                    *features[spec.feature_set], kind, spec.variant, int(cfg["kriging_nlags"])
                )
            elif spec.family == "GAM":
                self._gam[spec.feature_set] = AdditiveModel(
                    points_train,
                    points_test,
                    spec.feature_set,
                    self.factors_train,
                    self.factors_test,
                    int(cfg["gam_basis_per_axis"]),
                    int(cfg["gam_basis_radius"]),
                    int(cfg["gam_basis_angle"]),
                )
            elif spec.family == "XY":
                self._linear[spec.method] = polynomial_operator(xy_norm[train_mask], xy_norm[self.test_mask], int(cfg["polynomial_order"]))
            elif spec.family == "RT":
                order = int(spec.variant.removeprefix("order"))
                self._linear[spec.method] = rt_operator(xy_norm[train_mask], xy_norm[self.test_mask], order)

    def run(self, method: str, measured_train: np.ndarray) -> MethodOutput:
        """measured_train (学習点, 2) から評価点の推定値を求める。"""
        spec = self.specs[method]
        start = time.perf_counter()
        nan2 = (float("nan"), float("nan"))
        if spec.family in ("XY", "RT"):
            operator = self._linear[method]
            estimate = operator.apply(measured_train)
            return MethodOutput(estimate, (operator.edf_x, operator.edf_y), nan2, nan2, True, time.perf_counter() - start)

        columns, edfs, aux, iterations = [], [], [], []
        extra: dict[str, float] = {}
        converged = True
        for axis in range(2):
            axis_name = "XY"[axis]
            y = measured_train[:, axis]
            if spec.family == "GPR":
                result = fit_predict_gpr(
                    self._gp[(spec.variant, spec.feature_set)],
                    y,
                    self.factors_train,
                    self.factors_test,
                    spec.factor_mode,
                    int(self.cfg["gpr_backfit_max_iterations"]),
                    float(self.cfg["gpr_backfit_tolerance_nm"]),
                )
                columns.append(result.prediction)
                edfs.append(result.edf)
                aux.append(float(np.exp(result.log_params[-1])))
                iterations.append(float(result.n_backfit_iterations) if spec.factor_mode == "backfit" else float("nan"))
                converged &= result.backfit_converged and result.optimizer_converged
                gp = self._gp[(spec.variant, spec.feature_set)]
                for index, value in enumerate(np.exp(result.log_params[: gp.n_length])):
                    extra[f"ls{index}_{axis_name}"] = float(value)
                extra[f"sf_{axis_name}"] = float(np.exp(result.log_params[gp.n_length]))
                if gp.kernel.family == "rq":
                    extra[f"alpha_{axis_name}"] = float(np.exp(result.log_params[gp.n_length + 1]))
            elif spec.family == "TPS":
                result = self._tps[spec.feature_set].fit_predict(y)
                columns.append(result.prediction)
                edfs.append(result.edf)
                aux.append(result.log10_lambda)
                iterations.append(float("nan"))
            elif spec.family in ("OK", "UK"):
                result = self._kriging[(spec.family, spec.variant, spec.feature_set)].fit_predict(y)
                columns.append(result.prediction)
                edfs.append(result.edf)
                aux.append(float(result.params[-1]))
                iterations.append(float("nan"))
            elif spec.family == "GAM":
                result = self._gam[spec.feature_set].fit_predict(y)
                columns.append(result.prediction)
                edfs.append(result.edf)
                aux.append(float(np.mean(result.log10_lambda)))
                iterations.append(float("nan"))
            else:
                raise ValueError(f"未知の手法: {method}")
        return MethodOutput(
            np.column_stack(columns),
            (edfs[0], edfs[1]),
            (aux[0], aux[1]),
            (iterations[0], iterations[1]),
            converged,
            time.perf_counter() - start,
            extra,
        )
