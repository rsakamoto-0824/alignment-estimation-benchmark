"""追加検証（GPR の加法カーネル）の集計表から、スライドで使う数値を deck_data.json に書き出す（手で書き写さない）。

前提：python -m src.additive_study を実行して results_additive/tables/ ができていること。
使い方（このフォルダで）
    ../../.venv/bin/python prepare_data.py
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import numpy as np
import pandas as pd

BASE_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = BASE_DIR.parents[1]
MAIN = PROJECT_ROOT / "results" / "tables"
# 動作確認では環境変数で別の結果フォルダを指定できる
ADDITIVE = Path(os.environ.get("ADDITIVE_DIR", PROJECT_ROOT / "results_additive"))
INTERACTION = Path(os.environ.get("INTERACTION_DIR", PROJECT_ROOT / "results_interaction"))
MODES = ("none", "basis", "backfit", "basis_int", "additive", "additive_int")


def r(value, digits=4):
    if value is None or (isinstance(value, float) and not np.isfinite(value)):
        return None
    return round(float(value), digits)


def paired_block(table: pd.DataFrame) -> dict:
    return {
        comparison: {int(row["n_shots"]): {"rel": r(row["rel_mean_pct"], 2), "diff": r(row["diff_mean"]), "win": r(row["win_rate"], 3), "sig": row["significant"]}
                     for _, row in part.iterrows()}
        for comparison, part in table.groupby("comparison")
    }


def main() -> None:
    tables = ADDITIVE / "tables"
    summary = pd.read_csv(tables / "mode_summary.csv")
    levels = sorted(summary["n_shots"].unique().tolist())
    data: dict = {"levels": levels}
    run_info = json.loads((ADDITIVE / "run_info.json").read_text(encoding="utf-8"))
    data["run"] = {"n_wafers": int(run_info["n_wafers"]), "hours": r(run_info["seconds_total"] / 3600, 2), "n_errors": int(run_info["n_errors"])}
    config = json.loads((ADDITIVE / "config_used.json").read_text(encoding="utf-8"))
    data["config"] = {"kernels": config["methods"]["gpr_kernels"], "feature_sets": config["methods"]["feature_sets"]}

    data["modes"] = {}
    for mode, part in summary.groupby("factor_mode"):
        data["modes"][mode] = {
            int(row["n_shots"]): {
                "rep": r(row["rep_RMSE_XY"]), "rep_mae": r(row["rep_MAE_XY"]), "rep_r2": r(row["rep_R2_XY"]), "rep_adj": r(row["rep_adjR2_XY"]),
                "rep_outer": r(row["rep_RMSE_XY_outer"]), "rep_inner": r(row["rep_RMSE_XY_inner"]),
                "mean": r(row["mean_over_configs"]), "best": r(row["best_rmse"]), "best_config": row["best_config"],
                "seconds": r(row["seconds_mean"], 5),
            }
            for _, row in part.iterrows()
        }
    data["paired_rep"] = paired_block(pd.read_csv(tables / "mode_paired_representative.csv"))
    data["paired_all"] = paired_block(pd.read_csv(tables / "mode_paired_all_configs.csv"))
    quantiles = pd.read_csv(tables / "mode_wafer_quantiles.csv")
    data["quantiles"] = {
        mode: {int(row["n_shots"]): {"median": r(row["50%"]), "q90": r(row["90%"])} for _, row in part.iterrows()}
        for mode, part in quantiles.groupby("factor_mode")
    }
    kernels = pd.read_csv(tables / "kernel_basis_vs_additive.csv")
    data["kernels"] = [{key: (r(value) if isinstance(value, float) else value) for key, value in row.items()} for _, row in kernels.iterrows()]
    ranking = pd.read_csv(tables / "ranking_with_additive.csv")
    data["ranking"] = [{"variant": row["variant"], "feature_set": row["feature_set"], "mode": row["factor_mode"], "rmse": r(row["RMSE_XY"])} for _, row in ranking.head(10).iterrows()]
    tau = pd.read_csv(tables / "tau_summary.csv")
    data["tau"] = {}
    for (mode, term, axis), part in tau.groupby(["factor_mode", "term", "axis"]):
        data["tau"].setdefault(mode, {}).setdefault(term, {})[axis] = {
            int(row["n_shots"]): {"median": r(row["median"], 3), "q25": r(row["q25"], 3), "q75": r(row["q75"], 3), "zero": r(row["near_zero_rate"], 3)}
            for _, row in part.iterrows()
        }
    data["truth"] = {key: r(value, 3) for key, value in json.loads((tables / "true_effect_scale.json").read_text()).items()}
    collapse = pd.read_csv(tables / "scan_tau_collapse.csv")
    data["scan_collapse"] = {int(row["n_shots"]): {"rate": r(row["collapsed_rate"], 3), "diff_collapsed": r(row["diff_collapsed"]), "diff_kept": r(row["diff_kept"])}
                             for _, row in collapse.iterrows()}
    mixed_info = PROJECT_ROOT / "results_mixed" / "run_info.json"
    if mixed_info.exists():
        info = json.loads(mixed_info.read_text(encoding="utf-8"))
        data["run_mixed"] = {"hours": r(info["seconds_total"] / 3600, 2), "n_errors": int(info["n_errors"])}

    main_summary = pd.read_csv(MAIN / "summary_by_method.csv")
    data["tps"] = {int(row["n_shots"]): r(row["RMSE_XY_mean"]) for _, row in main_summary[main_summary["method"] == "TPS_XYR"].iterrows()}
    best_main = main_summary.loc[main_summary.groupby("n_shots")["RMSE_XY_mean"].idxmin()]
    data["best_main"] = {int(row["n_shots"]): {"method": row["method"], "rmse": r(row["RMSE_XY_mean"])} for _, row in best_main.iterrows()}

    if (tables / "interaction_summary.csv").exists():
        inter = pd.read_csv(tables / "interaction_summary.csv")
        data["interaction"] = {
            (row["factor_mode"] if row["family"] == "GPR" else "tps"): {} for _, row in inter.iterrows()
        }
        for _, row in inter.iterrows():
            key = row["factor_mode"] if row["family"] == "GPR" else "tps"
            data["interaction"][key][int(row["n_shots"])] = r(row["mean"])
        data["interaction_paired"] = paired_block(pd.read_csv(tables / "interaction_paired.csv"))
        inter_config = json.loads((INTERACTION / "config_used.json").read_text(encoding="utf-8"))
        data["interaction_std"] = inter_config["generation"]["scan_mark_interaction_std_nm"]
    out = BASE_DIR / "deck_data.json"
    out.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{out} を書き出しました（{out.stat().st_size:,} bytes）")


if __name__ == "__main__":
    main()
