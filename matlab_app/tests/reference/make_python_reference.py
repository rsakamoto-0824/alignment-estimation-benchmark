"""MATLAB 版の照合用に、Python 版（src/）の計算結果を JSON に書き出す。

模擬データ（本計算と同じ設定・乱数）の Wafer 3枚と、10 Shot・20 Shot の計画を使い、
- 超パラメータを固定したときの GPR の目的関数・勾配・推定値（決まった計算なので完全に一致するはず）
- 最適化まで含めた GPR の推定値と対数周辺尤度（最適化の方法が違うので近い値になるはず）
- TPS・Kriging（経験バリオグラム、Python が当てはめた値での推定）・GAM（REML 基準、推定）・XY5・RT4/5・指標
を書き出す。

使い方（リポジトリの直下で）
    .venv/bin/python matlab_app/tests/reference/make_python_reference.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from src.geometry import build_layout  # noqa: E402
from src.methods import LevelContext, MethodSpec  # noqa: E402
from src.metrics import wafer_metrics  # noqa: E402
from src.models.gpr import fit_predict_gpr  # noqa: E402
from src.models.kriging import _fit_variogram  # noqa: E402
from src.sampling import i_criterion, shot_information, train_mark_mask  # noqa: E402
from src.simulation import build_plans, load_config  # noqa: E402
from src.wafer_generator import GenerationSettings, WaferGenerator  # noqa: E402

OUTPUT = Path(__file__).resolve().parent / "python_reference.json"
WAFER_IDS = (0, 1, 2)
LEVELS = (10, 20)
FIXED_GPR_CASES = [
    ("matern52", "XYR", "none"),
    ("matern52", "XYR", "basis"),
    ("matern52", "XYR", "basis_int"),
    ("matern52", "XYR", "additive"),
    ("matern52", "XYR", "additive_int"),
    ("matern52", "XYR", "mixed"),
    ("matern52", "XYR", "mixed_int"),
    ("ardexponential", "XYRT", "basis"),
    ("rationalquadratic", "XY", "additive"),
    ("ardrationalquadratic", "XYR", "mixed_int"),
    ("squaredexponential", "XYRT", "none"),
    ("exponential", "XY", "basis"),
    ("ardmatern32", "XYRT", "additive"),
]
FITTED_GPR_CASES = [
    ("matern52", "XYR", "none"),
    ("matern52", "XYR", "basis"),
    ("matern52", "XYR", "backfit"),
    ("matern52", "XYR", "additive"),
    ("matern52", "XYR", "mixed"),
    ("ardmatern52", "XYRT", "basis"),
    ("rationalquadratic", "XY", "additive_int"),
]
FEATURE_SETS = ("XY", "XYR", "XYRT")
VARIOGRAMS = ("linear", "gaussian", "power", "exponential")


def as_list(array):
    return np.asarray(array, dtype=float).tolist()


def gpr_basis(context: LevelContext, mode: str):
    """fit_predict_gpr と同じ基底（定数・効果コード）。"""
    ones_train = np.ones((context.n_train, 1))
    ones_test = np.ones((context.n_test, 1))
    if mode == "basis":
        return np.hstack([ones_train, context.factors_train]), np.hstack([ones_test, context.factors_test])
    if mode == "basis_int":
        return np.hstack([ones_train, context.factors_int_train]), np.hstack([ones_test, context.factors_int_test])
    if mode in ("mixed", "mixed_int"):
        return np.hstack([ones_train, context.factors_train[:, :1]]), np.hstack([ones_test, context.factors_test[:, :1]])
    return ones_train, ones_test


def main() -> None:
    config = load_config(ROOT / "config" / "default.json")
    layout = build_layout(config)
    plans = {plan.n_shots: plan for plan in build_plans(layout, config)}
    generator = WaferGenerator(layout, GenerationSettings.from_config(config), int(config["random"]["master_seed"]))
    samples = [generator.generate(wafer_id) for wafer_id in WAFER_IDS]
    marks = layout.marks
    reference: dict = {
        "layout": {
            "Xmm": as_list(marks["Xmm"]),
            "Ymm": as_list(marks["Ymm"]),
            "markXmm": as_list(marks["markXmm"]),
            "markYmm": as_list(marks["markYmm"]),
            "markNo": as_list(marks["markNo"]),
            "Direction": as_list(marks["Direction"]),
            "shotNo": as_list(marks["shotNo"]),
            "shot_index": as_list(marks["shot_index"]),
            "wafer_radius_mm": layout.wafer_radius_mm,
        },
        "wafers": [{"measured": as_list(s.measured), "truth": as_list(s.truth)} for s in samples],
        "levels": {},
    }
    # 計画の I 基準（MATLAB で同じ Shot を選んだときの基準値を照合する）
    info = shot_information(layout, int(config["sampling"]["design_xy_order"]))
    for n_shots in LEVELS:
        plan = plans[n_shots]
        train_mask = train_mark_mask(layout, plan.shot_indices)
        specs = []
        for kernel, feature_set, mode in sorted(set(FIXED_GPR_CASES + FITTED_GPR_CASES)):
            specs.append(MethodSpec(f"GPR_{kernel}_{feature_set}_{mode}", "GPR", feature_set, kernel, mode))
        for feature_set in FEATURE_SETS:
            specs.append(MethodSpec(f"TPS_{feature_set}", "TPS", feature_set, "tps", "none"))
            specs.append(MethodSpec(f"GAM_{feature_set}", "GAM", feature_set, "pspline", "factor"))
        for variogram in VARIOGRAMS:
            for family in ("OK", "UK"):
                specs.append(MethodSpec(f"{family}_{variogram}_XYR", family, "XYR", variogram, "none"))
        specs += [MethodSpec("XY5", "XY", "-", "order5", "none"), MethodSpec("RT4", "RT", "-", "order4", "none"),
                  MethodSpec("RT5", "RT", "-", "order5", "none")]
        context = LevelContext(layout, train_mask, config, specs)
        level: dict = {
            "shot_indices": [int(i) for i in plan.shot_indices],
            "criterion_trace": float(i_criterion(info[plan.shot_indices].sum(axis=0))),
            "fixed_gpr": [],
            "fitted_gpr": [],
            "tps": [],
            "kriging": [],
            "gam": [],
            "linear": [],
        }
        measured_train = [s.measured[train_mask] for s in samples]
        truth_test = [s.truth[~train_mask] for s in samples]

        # 超パラメータを固定した GPR（wafer 0、X）
        y = measured_train[0][:, 0]
        for kernel, feature_set, mode in FIXED_GPR_CASES:
            spec = context.specs[f"GPR_{kernel}_{feature_set}_{mode}"]
            gp = context._gp[context._gp_key(spec)]
            basis_train, basis_test = gpr_basis(context, mode)
            start = gp.initial_log_params(y)
            log_params = start + 0.3 * np.sin(np.arange(1, start.size + 1))
            value, gradient = gp.objective(log_params, y, basis_train)
            fit = gp.condition(log_params, y, basis_train)
            level["fixed_gpr"].append({
                "kernel": kernel, "feature_set": feature_set, "mode": mode,
                "log_params": as_list(log_params), "start": as_list(start),
                "value": float(value), "gradient": as_list(gradient),
                "prediction": as_list(gp.predict(fit, basis_test)), "edf": float(fit.edf),
            })

        # 最適化まで含めた GPR（3枚 × X・Y）
        for kernel, feature_set, mode in FITTED_GPR_CASES:
            spec = context.specs[f"GPR_{kernel}_{feature_set}_{mode}"]
            gp = context._gp[context._gp_key(spec)]
            for wafer in range(len(samples)):
                for axis in range(2):
                    y = measured_train[wafer][:, axis]
                    if mode in ("mixed", "mixed_int"):
                        factors_train, factors_test = context.factors_train[:, :1], context.factors_test[:, :1]
                    elif mode == "basis_int":
                        factors_train, factors_test = context.factors_int_train, context.factors_int_test
                    else:
                        factors_train, factors_test = context.factors_train, context.factors_test
                    result = fit_predict_gpr(gp, y, factors_train, factors_test, mode, 20, 1e-3)
                    if mode == "backfit":
                        center = context.factors_train.mean(axis=0)
                        basis_train = np.hstack([np.ones((context.n_train, 1)), context.factors_train - center])
                    else:
                        basis_train, _ = gpr_basis(context, mode)
                    nll = gp.objective(result.log_params, y, basis_train)[0]
                    level["fitted_gpr"].append({
                        "kernel": kernel, "feature_set": feature_set, "mode": mode, "wafer": wafer, "axis": axis,
                        "log_params": as_list(result.log_params), "nll": float(nll),
                        "prediction": as_list(result.prediction), "edf": float(result.edf),
                        "rmse_truth": float(np.sqrt(np.mean((result.prediction - truth_test[wafer][:, axis]) ** 2))),
                    })

        for wafer in range(len(samples)):
            for axis in range(2):
                y = measured_train[wafer][:, axis]
                for feature_set in FEATURE_SETS:
                    result = context._tps[feature_set].fit_predict(y)
                    level["tps"].append({"feature_set": feature_set, "wafer": wafer, "axis": axis,
                                         "prediction": as_list(result.prediction), "edf": result.edf,
                                         "log10_lambda": result.log10_lambda})
                    model = context._gam[feature_set]
                    result = model.fit_predict(y)
                    xty, yty = model.design.T @ y, float(y @ y)
                    fixed_lambda = np.linspace(-1.0, 1.0, len(model.penalties))
                    level["gam"].append({
                        "feature_set": feature_set, "wafer": wafer, "axis": axis,
                        "prediction": as_list(result.prediction), "edf": result.edf,
                        "log10_lambda": as_list(result.log10_lambda),
                        "criterion": model._solve(result.log10_lambda, xty, yty)[0],
                        "fixed_log10_lambda": as_list(fixed_lambda),
                        "fixed_criterion": model._solve(fixed_lambda, xty, yty)[0],
                        "fixed_prediction": as_list(model.design_test @ model._solve(fixed_lambda, xty, yty)[1]),
                    })
                for variogram in VARIOGRAMS:
                    for family in ("OK", "UK"):
                        model = context._kriging[(family, variogram, "XYR")]
                        if model._drift_projector is not None:
                            residual = y - model._drift_projector @ (model._drift_projector.T @ y)
                        else:
                            residual = y
                        lags, semivariance = model.empirical_variogram(residual)
                        params = _fit_variogram(variogram, lags, semivariance)
                        result = model.fit_predict(y)
                        level["kriging"].append({
                            "family": family, "variogram": variogram, "wafer": wafer, "axis": axis,
                            "lags": as_list(lags), "semivariance": as_list(semivariance), "params": as_list(params),
                            "prediction": as_list(result.prediction), "edf": result.edf,
                        })
            for name in ("XY5", "RT4", "RT5"):
                operator = context._linear[name]
                estimate = operator.apply(measured_train[wafer])
                level["linear"].append({"name": name, "wafer": wafer, "prediction": as_list(estimate),
                                        "edf": [operator.edf_x, operator.edf_y]})
        # 指標（wafer 0 の TPS XYR の推定値で）
        estimate = np.column_stack([np.asarray(level["tps"][1]["prediction"]), np.asarray(level["tps"][4]["prediction"])])
        assert level["tps"][1]["feature_set"] == "XYR" and level["tps"][1]["axis"] == 0
        assert level["tps"][4]["feature_set"] == "XYR" and level["tps"][4]["axis"] == 1
        outer = (layout.radius_mm[~train_mask] / layout.wafer_radius_mm) >= 0.8
        edf = (level["tps"][1]["edf"], level["tps"][4]["edf"])
        level["metrics"] = {"estimate": as_list(estimate), "edf": list(edf),
                            "values": wafer_metrics(truth_test[0], estimate, edf, outer)}
        reference["levels"][str(n_shots)] = level
    OUTPUT.write_text(json.dumps(reference), encoding="utf-8")
    print(f"{OUTPUT} を書き出しました（{OUTPUT.stat().st_size:,} bytes）")


if __name__ == "__main__":
    main()
