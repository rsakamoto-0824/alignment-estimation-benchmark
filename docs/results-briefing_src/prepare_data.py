"""計算結果の CSV から、スライドで使う数値を deck_data.json に書き出す（手で書き写さない）。

使い方（このフォルダで）
    ../../.venv/bin/python prepare_data.py [--results ../../results]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

BASE_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = BASE_DIR.parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from src.geometry import build_layout  # noqa: E402
from src.wafer_generator import GenerationSettings, WaferGenerator  # noqa: E402

FAMILY_ORDER = ("GPR", "TPS", "OK", "UK", "GAM", "XY", "RT")
FAMILY_LABELS = {"GPR": "GPR", "TPS": "TPS", "OK": "Kriging", "UK": "Universal Kriging", "GAM": "GAM", "XY": "XY5次多項式", "RT": "RTモデル"}
FEATURE_LABELS = {"XY": "X, Y", "XYR": "X, Y, 半径", "XYRT": "X, Y, 半径, T", "-": "－"}
MODE_LABELS = {"none": "質的変数なし", "basis": "同時推定", "backfit": "Backfitting", "factor": "質的変数あり"}
FOCUS_LEVELS = (10, 20, 40)


def method_label(row) -> str:
    family = row["family"]
    if family == "GPR":
        return f"GPR {row['variant']}｜{FEATURE_LABELS[row['feature_set']]}｜{MODE_LABELS[row['factor_mode']]}"
    if family in ("OK", "UK"):
        return f"{FAMILY_LABELS[family]} {row['variant']}｜{FEATURE_LABELS[row['feature_set']]}"
    if family in ("TPS", "GAM"):
        return f"{FAMILY_LABELS[family]}｜{FEATURE_LABELS[row['feature_set']]}"
    return row["method"]


def r(value, digits=4):
    if value is None or (isinstance(value, float) and not np.isfinite(value)):
        return None
    return round(float(value), digits)


def metric_block(row) -> dict:
    keys = ["RMSE_XY_mean", "MAE_XY_mean", "R2_XY_mean", "adjR2_XY_mean", "RMSE_XY_outer_mean", "RMSE_XY_inner_mean",
            "RMSE_XY_median", "RMSE_XY_q90", "edf_XY_mean", "seconds_mean", "RMSE_X_mean", "RMSE_Y_mean"]
    return {key.replace("_mean", ""): r(row[key]) for key in keys if key in row}


def data_statistics(config: dict, n_wafers: int) -> dict:
    """模擬データの成分の大きさ（RMS、Wafer の平均）。"""
    layout = build_layout(config)
    generator = WaferGenerator(layout, GenerationSettings.from_config(config), int(config["random"]["master_seed"]))
    stats = {"trend": [], "mark": [], "scan": [], "noise": [], "n_terms": []}
    for wafer_id in range(n_wafers):
        sample = generator.generate(wafer_id)
        stats["trend"].append(np.sqrt(np.mean(sample.trend**2)))
        stats["mark"].append(np.sqrt(np.mean(sample.mark_offset**2)))
        stats["scan"].append(np.sqrt(np.mean(sample.scan_offset**2)))
        stats["noise"].append(np.sqrt(np.mean(sample.noise**2)))
        stats["n_terms"].append(float(np.mean((sample.trend_coefficients != 0).sum(axis=0))))
    outer = layout.radius_mm >= 0.8 * layout.wafer_radius_mm
    return {
        **{f"{key}_rms_mean": r(np.mean(values), 3) for key, values in stats.items() if key != "n_terms"},
        "trend_rms_p10": r(np.percentile(stats["trend"], 10), 3),
        "trend_rms_p90": r(np.percentile(stats["trend"], 90), 3),
        "n_terms_mean": r(np.mean(stats["n_terms"]), 2),
        "n_shots": layout.n_shots,
        "n_marks": layout.n_marks,
        "n_outer_marks": int(outer.sum()),
        "max_mark_radius": r(layout.radius_mm.max(), 2),
    }


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", default=str(PROJECT_ROOT / "results"))
    args = parser.parse_args(argv)
    results = Path(args.results)
    tables = results / "tables"
    config = json.loads((results / "config_used.json").read_text(encoding="utf-8"))
    summary = pd.read_csv(tables / "summary_by_method.csv")
    ranking = pd.read_csv(tables / "ranking_overall.csv")
    feature_family = pd.read_csv(tables / "feature_effect_family.csv")
    feature = pd.read_csv(tables / "feature_effect.csv")
    factor = pd.read_csv(tables / "factor_effect_gpr.csv")
    agreement = pd.read_csv(tables / "metric_agreement.csv")
    usage = pd.read_csv(tables / "gpr_ard_usage.csv")
    recommendation = pd.read_csv(tables / "recommendation.csv")
    plans = pd.read_csv(tables / "sampling_plans.csv")
    frame = pd.read_csv(tables / "per_wafer_metrics.csv.gz")
    run_info = json.loads((results / "run_info.json").read_text(encoding="utf-8"))
    levels = sorted(summary["n_shots"].unique().tolist())
    n_wafers = int(summary["n_wafers"].max())

    data: dict = {
        "run": {
            "n_wafers": n_wafers,
            "n_methods": int(summary["method"].nunique()),
            "levels": levels,
            "n_errors": int(run_info.get("n_errors", 0)),
            "hours": r(run_info.get("seconds_total", 0) / 3600, 2),
            "python": run_info.get("python"),
        },
        "plans": {int(row["n_shots"]): {"n_train_marks": int(row["n_train_marks"]), "i_criterion": r(row["i_criterion"])} for _, row in plans.iterrows()},
        "data": data_statistics(config, n_wafers),
        "config": {
            "coef_std_order0_nm": config["generation"]["coef_std_order0_nm"],
            "coef_std_decay": config["generation"]["coef_std_decay_per_order"],
            "mark_base": config["generation"]["mark_offset_base_nm"],
            "mark_std": config["generation"]["mark_offset_wafer_std_nm"],
            "scan_base": config["generation"]["scan_difference_base_nm"],
            "scan_std": config["generation"]["scan_difference_wafer_std_nm"],
            "constraints": config["sampling"]["constraints"],
        },
    }

    # 系統ごとの最良（Shot 数ごと）
    best_level = {}
    for n_shots, level in summary.groupby("n_shots"):
        best_level[int(n_shots)] = {}
        for family in FAMILY_ORDER:
            rows = level[level["family"] == family]
            if rows.empty:
                continue
            row = rows.loc[rows["RMSE_XY_mean"].idxmin()]
            best_level[int(n_shots)][family] = {"method": row["method"], "label": method_label(row), **metric_block(row)}
    data["best_by_level"] = best_level

    # 系統ごとに1つに固定した最良（全 Shot 数の平均）。GPR は Backfitting を除く（同時推定とほぼ同じ解で、同時推定を代表にする）
    candidates = summary[~((summary["family"] == "GPR") & (summary["factor_mode"] == "backfit"))]
    avg = candidates.groupby(["family", "method"])["RMSE_XY_mean"].mean().reset_index()
    fixed = {}
    for family in FAMILY_ORDER:
        rows = avg[avg["family"] == family]
        if rows.empty:
            continue
        method = rows.loc[rows["RMSE_XY_mean"].idxmin(), "method"]
        per_level = summary[summary["method"] == method].set_index("n_shots")
        info = per_level.iloc[0]
        fixed[family] = {
            "method": method,
            "label": method_label(info),
            "feature_set": info["feature_set"],
            "variant": info["variant"],
            "factor_mode": info["factor_mode"],
            "levels": {int(n): metric_block(row) for n, row in per_level.iterrows()},
        }
    data["best_fixed"] = fixed

    # 総合順位（上位）
    top = ranking.head(15)
    data["ranking_top"] = [
        {"method": row["method"], "label": method_label(row), "avg": r(row["RMSE_XY_avg_levels"]), "mean_wafer_rank": r(row["mean_wafer_rank"], 2),
         "levels": {int(c.split("_")[-1]): r(row[c]) for c in ranking.columns if c.startswith("RMSE_XY_") and c.split("_")[-1].isdigit()}}
        for _, row in top.iterrows()
    ]

    # Shot 数ごとの最良と、差のない設定
    rec = {}
    for n_shots, level in recommendation.groupby("n_shots"):
        tied = level[level["tied_with_best"]]
        best = level.iloc[0]
        rec[int(n_shots)] = {
            "best": best["method"],
            "best_label": method_label(best),
            "best_rmse": r(best["RMSE_XY_mean"]),
            "n_tied": int(len(tied)),
            "tied_families": sorted(tied["family"].unique().tolist()),
            "tied_top": [{"method": t["method"], "label": method_label(t), "rmse": r(t["RMSE_XY_mean"]), "rel": r(t["rel_vs_best_pct"], 2)} for _, t in tied.head(8).iterrows()],
            "within_2pct": int((level["rel_vs_best_pct"] <= 2.0).sum()),
        }
    data["recommendation"] = rec

    # 説明変数の効果（系統ごと）
    fe = {}
    for (comparison, family), rows in feature_family.groupby(["comparison", "family"]):
        fe.setdefault(comparison, {})[family] = {
            int(row["n_shots"]): {"rel": r(row["rel_mean_pct"], 2), "diff": r(row["diff_mean"]), "win": r(row["win_rate"], 3), "sig": row["significant"]}
            for _, row in rows.iterrows()
        }
    data["feature_effect"] = fe
    # 系統の最良設定での説明変数の効果（同じカーネル・質的変数の扱いで説明変数だけ変える）
    fe_best = {}
    for family, info in fixed.items():
        if info["feature_set"] == "-":
            continue
        rows = feature[(feature["family"] == family) & (feature["variant"] == info["variant"]) & (feature["factor_mode"] == info["factor_mode"])]
        fe_best[family] = {
            comparison: {int(row["n_shots"]): {"rel": r(row["rel_mean_pct"], 2), "win": r(row["win_rate"], 3), "sig": row["significant"]} for _, row in part.iterrows()}
            for comparison, part in rows.groupby("comparison")
        }
    data["feature_effect_best"] = fe_best
    # 説明変数の効果の数え上げ：有意に良い・悪い・差なしの設定の数
    counts = {}
    for comparison, rows in feature.groupby("comparison"):
        counts[comparison] = {int(n): rows[rows["n_shots"] == n]["significant"].value_counts().to_dict() for n in levels}
    data["feature_effect_counts"] = counts

    # GPR の質的変数
    overall = factor[factor["variant"] == "全カーネル平均"]
    data["factor_effect"] = {
        comparison: {int(row["n_shots"]): {"rel": r(row["rel_mean_pct"], 2), "diff": r(row["diff_mean"]), "win": r(row["win_rate"], 3), "sig": row["significant"]} for _, row in rows.iterrows()}
        for comparison, rows in overall.groupby("comparison")
    }
    gpr = frame[frame["family"] == "GPR"]
    wide = gpr.pivot_table(index=["wafer", "n_shots", "variant", "feature_set"], columns="factor_mode", values="RMSE_XY")
    diff = (wide["backfit"] - wide["basis"]).dropna()
    backfit_rows = gpr[gpr["factor_mode"] == "backfit"]
    data["backfit_vs_basis"] = {
        "share_within_001": r(np.mean(np.abs(diff) < 0.01), 4),
        "share_within_01": r(np.mean(np.abs(diff) < 0.1), 4),
        "mean_diff": r(diff.mean()),
        "mean_abs_diff": r(np.abs(diff).mean()),
        "iter_mean": r(backfit_rows[["iter_X", "iter_Y"]].to_numpy().mean(), 2),
        "iter_max": int(np.nanmax(backfit_rows[["iter_X", "iter_Y"]].to_numpy())),
        "converged_rate": r(backfit_rows["converged"].mean(), 4),
        "by_level": {int(n): {"mean_diff": r(d.mean()), "share_within_001": r(np.mean(np.abs(d) < 0.01), 4)} for n, d in diff.groupby(level="n_shots")},
    }
    gpr_rows = summary[summary["family"] == "GPR"]
    data["gpr_best_by_mode"] = {
        int(n): {mode: {"method": g.loc[g["RMSE_XY_mean"].idxmin(), "method"], "label": method_label(g.loc[g["RMSE_XY_mean"].idxmin()]),
                        "rmse": r(g["RMSE_XY_mean"].min())} for mode, g in level.groupby("factor_mode")}
        for n, level in gpr_rows.groupby("n_shots")
    }
    gpr_mode = summary[summary["family"] == "GPR"].groupby(["n_shots", "factor_mode"])["RMSE_XY_mean"].agg(["mean", "min"]).reset_index()
    data["gpr_mode_rmse"] = {int(n): {row["factor_mode"]: {"mean": r(row["mean"]), "min": r(row["min"])} for _, row in g.iterrows()} for n, g in gpr_mode.groupby("n_shots")}

    # カーネル（同時推定）
    kernels = {}
    gpr_basis = summary[(summary["family"] == "GPR") & (summary["factor_mode"] == "basis")]
    for n_shots in levels:
        level = gpr_basis[gpr_basis["n_shots"] == n_shots]
        kernels[int(n_shots)] = {f"{row['variant']}|{row['feature_set']}": r(row["RMSE_XY_mean"]) for _, row in level.iterrows()}
    data["kernels"] = kernels
    kernel_avg = gpr_basis.groupby("variant")["RMSE_XY_mean"].mean().sort_values()
    data["kernel_rank"] = [{"kernel": k, "avg": r(v)} for k, v in kernel_avg.items()]

    # バリオグラム
    krig = summary[summary["family"].isin(["OK", "UK"])]
    data["variograms"] = {
        int(n): {f"{row['family']}|{row['variant']}|{row['feature_set']}": r(row["RMSE_XY_mean"]) for _, row in g.iterrows()}
        for n, g in krig.groupby("n_shots")
    }
    vg_avg = krig.groupby(["family", "variant"])["RMSE_XY_mean"].mean().reset_index().sort_values("RMSE_XY_mean")
    data["variogram_rank"] = [{"family": row["family"], "variogram": row["variant"], "avg": r(row["RMSE_XY_mean"])} for _, row in vg_avg.iterrows()]
    nugget = frame[frame["family"].isin(["OK", "UK"])].groupby(["n_shots"])[["aux_X", "aux_Y"]].median()
    data["kriging_nugget_median"] = {int(n): r(row.mean(), 3) for n, row in nugget.iterrows()}
    gp_noise = frame[(frame["family"] == "GPR") & (frame["factor_mode"] == "basis")].groupby("n_shots")[["aux_X", "aux_Y"]].median()
    data["gpr_noise_median"] = {int(n): r(row.mean(), 3) for n, row in gp_noise.iterrows()}

    # 指標の一致
    data["metric_agreement"] = {
        int(n): {row["metric"]: {"spearman": r(row["spearman_vs_RMSE"], 3), "best": row["best_method"], "same": bool(row["same_best_as_RMSE"])} for _, row in g.iterrows()}
        for n, g in agreement.groupby("n_shots")
    }
    # ARD で半径・T を使わなかった割合
    data["ard_usage"] = {
        f"{fs}|{var}": {int(row["n_shots"]): r(row["at_upper_bound_rate"], 3) for _, row in g.iterrows()}
        for (fs, var), g in usage.groupby(["feature_set", "variable"])
    }
    # 計算時間
    timing = summary.copy()
    timing["group"] = np.where(timing["family"] == "GPR", "GPR_" + timing["factor_mode"], timing["family"])
    data["timing_ms"] = {int(n): {g: r(v * 1000, 2) for g, v in grp.groupby("group")["seconds_mean"].mean().items()} for n, grp in timing.groupby("n_shots")}
    # 外周と内側
    data["edge"] = {
        int(n): {family: {"outer": block["RMSE_XY_outer"], "inner": block["RMSE_XY_inner"]} for family, block in fams.items()}
        for n, fams in best_level.items()
    }
    # Backfitting の始め方の補足検証
    order_path = PROJECT_ROOT / "results_backfit_order" / "backfit_order_summary.csv"
    if order_path.exists():
        order = pd.read_csv(order_path)
        data["backfit_order"] = {
            int(n): {row["variant"]: {"rmse": r(row["RMSE_XY_mean"]), "iter_mean": r(row["iter_mean"], 1), "iter_max": int(row["iter_max"]),
                                      "converged": r(row["converged_rate"], 3), "seconds": r(row["seconds_mean"], 3)} for _, row in g.iterrows()}
            for n, g in order.groupby("n_shots")
        }
        metrics = pd.read_csv(PROJECT_ROOT / "results_backfit_order" / "backfit_order_metrics.csv.gz")
        data["backfit_order_n_wafers"] = int(metrics["wafer"].nunique())
    out = BASE_DIR / "deck_data.json"
    out.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{out} を書き出しました（{out.stat().st_size:,} bytes）")


if __name__ == "__main__":
    main()
