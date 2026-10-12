"""補足検証：Backfitting の始め方と内側の反復の扱いで、GPR の推定精度が変わるか。

本計算の backfit（質的変数を先に初期化し、内側の反復の収束値を直接計算）と、
教科書どおりの Backfitting 2通り（GPR を先に当てはめる／質的変数を先に初期化する）、基底関数での同時推定を、
同じ Wafer・同じ計画で比べる。対象は代表的なカーネル2種（squaredexponential・matern52）× 説明変数（X, Y, 半径）× Shot 数3水準（初期設定は Wafer 50枚）。

使い方
    python -m src.backfit_order_study --config config/default.json --n-wafers 50 --workers 1
"""
from __future__ import annotations

import argparse
import os
import time
from pathlib import Path

for _name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_name, "1")

import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

from .geometry import build_layout  # noqa: E402
from .methods import LevelContext, MethodSpec  # noqa: E402
from .metrics import wafer_metrics  # noqa: E402
from .models.gpr import classic_backfit_gpr, fit_predict_gpr  # noqa: E402
from .sampling import train_mark_mask  # noqa: E402
from .simulation import build_plans, load_config  # noqa: E402
from .wafer_generator import GenerationSettings, WaferGenerator  # noqa: E402

KERNELS = ("squaredexponential", "matern52")
FEATURE_SETS = ("XYR",)
LEVELS = (10, 20, 40)
VARIANTS = ("basis", "backfit", "classic_gp_first", "classic_factor_first")
CLASSIC_MAX_ITERATIONS = 300
_STATE: dict = {}


def _init(config: dict) -> None:
    layout = build_layout(config)
    plans = [p for p in build_plans(layout, config) if p.n_shots in LEVELS]
    specs = [MethodSpec(f"GPR_{k}_{f}_basis", "GPR", f, k, "basis") for k in KERNELS for f in FEATURE_SETS]
    _STATE["generator"] = WaferGenerator(layout, GenerationSettings.from_config(config), int(config["random"]["master_seed"]))
    _STATE["contexts"] = [(p.n_shots, LevelContext(layout, train_mark_mask(layout, p.shot_indices), config, specs)) for p in plans]
    _STATE["config"] = config


def _run_wafer(wafer_id: int) -> list[dict]:
    sample = _STATE["generator"].generate(wafer_id)
    cfg = _STATE["config"]["methods"]
    rows = []
    for n_shots, context in _STATE["contexts"]:
        measured = sample.measured[context.train_mask]
        truth = sample.truth[context.test_mask]
        for kernel in KERNELS:
            for feature_set in FEATURE_SETS:
                gp = context._gp[(kernel, feature_set)]
                for variant in VARIANTS:
                    start = time.perf_counter()
                    estimates, edfs, iterations, converged = [], [], [], True
                    for axis in range(2):
                        y = measured[:, axis]
                        if variant in ("basis", "backfit"):
                            result = fit_predict_gpr(gp, y, context.factors_train, context.factors_test, variant,
                                                     int(cfg["gpr_backfit_max_iterations"]), float(cfg["gpr_backfit_tolerance_nm"]))
                        else:
                            result = classic_backfit_gpr(gp, y, context.factors_train, context.factors_test, variant.removeprefix("classic_"),
                                                         CLASSIC_MAX_ITERATIONS, float(cfg["gpr_backfit_tolerance_nm"]))
                        estimates.append(result.prediction)
                        edfs.append(result.edf)
                        iterations.append(result.n_backfit_iterations)
                        converged &= result.backfit_converged
                    row = {"wafer": wafer_id, "n_shots": n_shots, "kernel": kernel, "feature_set": feature_set, "variant": variant}
                    row.update(wafer_metrics(truth, np.column_stack(estimates), (edfs[0], edfs[1]), context.outer_mask))
                    row.update({"iter_X": iterations[0], "iter_Y": iterations[1], "converged": converged, "seconds": time.perf_counter() - start})
                    rows.append(row)
    return rows


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Backfitting の始め方の補足検証")
    parser.add_argument("--config", default="config/default.json")
    parser.add_argument("--n-wafers", type=int, default=50)
    parser.add_argument("--workers", type=int, default=1)
    parser.add_argument("--results-dir", default="results_backfit_order")
    args = parser.parse_args(argv)
    config = load_config(args.config)
    out_dir = Path(args.results_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    wafer_ids = list(range(args.n_wafers))
    start = time.perf_counter()
    rows: list[dict] = []
    if args.workers <= 1:
        _init(config)
        for done, wafer_id in enumerate(wafer_ids, 1):
            rows.extend(_run_wafer(wafer_id))
            if done % 5 == 0:
                print(f"{done}/{len(wafer_ids)} 枚（{(time.perf_counter() - start) / 60:.1f} 分）", flush=True)
    else:
        import multiprocessing as mp

        with mp.get_context("spawn").Pool(args.workers, initializer=_init, initargs=(config,)) as pool:
            for done, wafer_rows in enumerate(pool.imap_unordered(_run_wafer, wafer_ids), 1):
                rows.extend(wafer_rows)
                if done % 10 == 0:
                    print(f"{done}/{len(wafer_ids)} 枚（{(time.perf_counter() - start) / 60:.1f} 分）", flush=True)
    frame = pd.DataFrame(rows).sort_values(["wafer", "n_shots", "kernel", "feature_set", "variant"])
    frame.to_csv(out_dir / "backfit_order_metrics.csv.gz", index=False, float_format="%.6g", compression="gzip")
    summary = (
        frame.groupby(["n_shots", "variant"])
        .agg(RMSE_XY_mean=("RMSE_XY", "mean"), RMSE_XY_median=("RMSE_XY", "median"), R2_XY_mean=("R2_XY", "mean"),
             iter_mean=("iter_X", "mean"), iter_max=("iter_X", "max"), converged_rate=("converged", "mean"), seconds_mean=("seconds", "mean"))
        .reset_index()
    )
    summary.to_csv(out_dir / "backfit_order_summary.csv", index=False, float_format="%.6g")
    print(summary.to_string(index=False))
    print(f"完了（{(time.perf_counter() - start) / 60:.1f} 分）")


if __name__ == "__main__":
    main()
