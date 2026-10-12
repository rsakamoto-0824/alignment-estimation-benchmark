"""結果の集計（per_wafer_metrics.csv.gz → results/tables/ の要約表）。

使い方
    python -m src.summarize --results results

作る表
- summary_by_method.csv     : Shot 数 × 手法ごとの平均・中央値・標準偏差など（全指標）
- ranking_overall.csv       : 全 Shot 数を通した順位（平均 RMSE と、Wafer ごとの順位の平均）
- best_by_family.csv        : Shot 数 × 手法の系統ごとの最良の設定
- feature_effect.csv        : 説明変数を足した効果（XYR−XY、XYRT−XY、XYRT−XYR）。同じ Wafer どうしの差
- feature_effect_family.csv : 上の表を系統ごとにまとめたもの（各系統の設定の平均）
- factor_effect_gpr.csv     : GPR の質的変数の扱い（basis−none、backfit−none、backfit−basis）
- metric_agreement.csv      : 4指標（RMSE・MAE・R²・調整済み R²）で手法の順位がどれだけ一致するか
- gpr_ard_usage.csv         : ARD カーネルで半径・T の長さスケールが上限に張り付いた割合（その変数を使わなかった割合）
- recommendation.csv        : Shot 数ごとの最良と、それと差がない（同じ Wafer どうしの差の95%信頼区間が0を含む）設定
差の信頼区間は Wafer をまたいだ対応のある差の平均 ± 1.96 × 標準誤差。
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

from .models.gpr import LENGTH_SCALE_BOUNDS

MAIN_METRIC = "RMSE_XY"
METRICS = (
    "RMSE_XY", "MAE_XY", "R2_XY", "adjR2_XY",
    "RMSE_X", "RMSE_Y", "MAE_X", "MAE_Y", "R2_X", "R2_Y", "adjR2_X", "adjR2_Y",
    "RMSE_XY_outer", "RMSE_XY_inner",
)
KEY_COLUMNS = ["method", "family", "feature_set", "variant", "factor_mode"]
FEATURE_PAIRS = (("XYR", "XY"), ("XYRT", "XY"), ("XYRT", "XYR"))
FACTOR_PAIRS = (("basis", "none"), ("backfit", "none"), ("backfit", "basis"))
Z_95 = 1.96
AT_UPPER_BOUND = 0.999 * LENGTH_SCALE_BOUNDS[1]
FAMILY_ORDER = ("GPR", "TPS", "OK", "UK", "GAM", "XY", "RT")


def load_metrics(results_dir: Path) -> pd.DataFrame:
    frame = pd.read_csv(results_dir / "tables" / "per_wafer_metrics.csv.gz")
    frame["error"] = frame["error"].fillna("")
    frame["edf_XY"] = frame["edf_X"] + frame["edf_Y"]
    frame["seconds_per_wafer"] = frame["seconds"]
    return frame


def summary_by_method(frame: pd.DataFrame) -> pd.DataFrame:
    ok = frame[frame["error"] == ""]
    grouped = ok.groupby(["n_shots", *KEY_COLUMNS], sort=False)
    parts = {
        "n_wafers": grouped["wafer"].nunique(),
        **{f"{m}_mean": grouped[m].mean() for m in METRICS},
        **{f"{m}_median": grouped[m].median() for m in ("RMSE_XY", "MAE_XY", "R2_XY", "adjR2_XY")},
        **{f"{m}_std": grouped[m].std() for m in ("RMSE_XY", "MAE_XY", "R2_XY", "adjR2_XY")},
        "RMSE_XY_q90": grouped["RMSE_XY"].quantile(0.9),
        "edf_XY_mean": grouped["edf_XY"].mean(),
        "seconds_mean": grouped["seconds"].mean(),
        "converged_rate": grouped["converged"].mean(),
        "iter_mean": grouped["iter_X"].mean(),
    }
    summary = pd.DataFrame(parts).reset_index()
    errors = frame[frame["error"] != ""].groupby(["n_shots", "method"]).size().rename("n_errors")
    summary = summary.merge(errors, on=["n_shots", "method"], how="left").fillna({"n_errors": 0})
    summary["RMSE_XY_sem"] = summary["RMSE_XY_std"] / np.sqrt(summary["n_wafers"])
    summary["rank_in_level"] = summary.groupby("n_shots")["RMSE_XY_mean"].rank(method="min").astype(int)
    return summary.sort_values(["n_shots", "RMSE_XY_mean"]).reset_index(drop=True)


def ranking_overall(frame: pd.DataFrame, summary: pd.DataFrame) -> pd.DataFrame:
    ok = frame[frame["error"] == ""].copy()
    ok["wafer_rank"] = ok.groupby(["wafer", "n_shots"])[MAIN_METRIC].rank(method="average")
    mean_rank = ok.groupby("method")["wafer_rank"].mean().rename("mean_wafer_rank")
    pivot = summary.pivot_table(index="method", columns="n_shots", values="RMSE_XY_mean")
    pivot.columns = [f"RMSE_XY_{c}" for c in pivot.columns]
    keys = summary.drop_duplicates("method").set_index("method")[KEY_COLUMNS[1:]]
    table = keys.join(pivot).join(mean_rank)
    table["RMSE_XY_avg_levels"] = pivot.mean(axis=1)
    table["rank_avg_levels"] = table["RMSE_XY_avg_levels"].rank(method="min").astype(int)
    return table.sort_values("RMSE_XY_avg_levels").reset_index()


def best_by_family(summary: pd.DataFrame) -> pd.DataFrame:
    idx = summary.groupby(["n_shots", "family"])["RMSE_XY_mean"].idxmin()
    best = summary.loc[idx].copy()
    best["family"] = pd.Categorical(best["family"], FAMILY_ORDER, ordered=True)
    return best.sort_values(["n_shots", "family"]).reset_index(drop=True)


def _paired(frame: pd.DataFrame, column: str, new: str, base: str, keys: list[str], metric: str = MAIN_METRIC) -> pd.DataFrame:
    """column の値 new と base で、同じ Wafer・Shot 数・keys の metric の差（new − base）をまとめる。"""
    valid = frame["error"] == "" if "error" in frame.columns else True
    subset = frame[frame[column].isin([new, base]) & valid]
    wide = subset.pivot_table(index=["wafer", "n_shots", *keys], columns=column, values=metric).dropna()
    diff = (wide[new] - wide[base]).rename("diff")
    rel = ((wide[new] - wide[base]) / wide[base]).rename("rel")
    data = pd.concat([diff, rel], axis=1).reset_index()
    grouped = data.groupby(["n_shots", *keys])
    out = pd.DataFrame(
        {
            "diff_mean": grouped["diff"].mean(),
            "diff_sem": grouped["diff"].std() / np.sqrt(grouped["diff"].count()),
            "rel_mean_pct": 100 * grouped["rel"].mean(),
            "win_rate": grouped["diff"].apply(lambda d: float(np.mean(d < 0))),
            "n": grouped["diff"].count(),
        }
    ).reset_index()
    out["ci_low"] = out["diff_mean"] - Z_95 * out["diff_sem"]
    out["ci_high"] = out["diff_mean"] + Z_95 * out["diff_sem"]
    out["significant"] = np.where(out["ci_high"] < 0, "better", np.where(out["ci_low"] > 0, "worse", "ns"))
    out.insert(0, "comparison", f"{new}-{base}")
    return out


def feature_effect(frame: pd.DataFrame) -> pd.DataFrame:
    with_features = frame[frame["feature_set"] != "-"]
    parts = [_paired(with_features, "feature_set", new, base, ["family", "variant", "factor_mode"]) for new, base in FEATURE_PAIRS]
    return pd.concat(parts, ignore_index=True)


def feature_effect_family(frame: pd.DataFrame) -> pd.DataFrame:
    """系統ごと：各 Wafer で系統内の設定（カーネル・バリオグラム・質的変数の扱い）の差を平均してから集計する。"""
    with_features = frame[(frame["feature_set"] != "-") & (frame["error"] == "")]
    family_mean = with_features.groupby(["wafer", "n_shots", "family", "feature_set"])[MAIN_METRIC].mean().reset_index()
    parts = [_paired(family_mean, "feature_set", new, base, ["family"]) for new, base in FEATURE_PAIRS]
    return pd.concat(parts, ignore_index=True)


def factor_effect_gpr(frame: pd.DataFrame) -> pd.DataFrame:
    gpr = frame[frame["family"] == "GPR"]
    parts = [_paired(gpr, "factor_mode", new, base, ["variant", "feature_set"]) for new, base in FACTOR_PAIRS]
    overall = []
    gpr_mean = gpr[gpr["error"] == ""].groupby(["wafer", "n_shots", "factor_mode"])[MAIN_METRIC].mean().reset_index()
    gpr_mean["variant"] = "全カーネル平均"
    gpr_mean["feature_set"] = "全説明変数"
    for new, base in FACTOR_PAIRS:
        overall.append(_paired(gpr_mean, "factor_mode", new, base, ["variant", "feature_set"]))
    return pd.concat(overall + parts, ignore_index=True)


def metric_agreement(summary: pd.DataFrame) -> pd.DataFrame:
    """Shot 数ごとに、RMSE の順位と他の指標の順位の Spearman 相関（R² 系は大きいほど良いので符号を反転）。"""
    records = []
    for n_shots, level in summary.groupby("n_shots"):
        ranks = {
            "RMSE": level["RMSE_XY_mean"].rank(),
            "MAE": level["MAE_XY_mean"].rank(),
            "R2": (-level["R2_XY_mean"]).rank(),
            "adjR2": (-level["adjR2_XY_mean"]).rank(),
        }
        best_rmse = level.loc[level["RMSE_XY_mean"].idxmin(), "method"]
        for name, rank in ranks.items():
            records.append(
                {
                    "n_shots": n_shots,
                    "metric": name,
                    "spearman_vs_RMSE": float(np.corrcoef(ranks["RMSE"], rank)[0, 1]),
                    "best_method": level.loc[rank.idxmin(), "method"],
                    "same_best_as_RMSE": level.loc[rank.idxmin(), "method"] == best_rmse,
                }
            )
    return pd.DataFrame(records)


def gpr_ard_usage(frame: pd.DataFrame) -> pd.DataFrame:
    """ARD カーネルで、半径（番号2）と T（番号3）の長さスケールが上限に張り付いた割合。"""
    ard = frame[(frame["family"] == "GPR") & frame["variant"].str.startswith("ard") & (frame["error"] == "")]
    records = []
    for (n_shots, feature_set), group in ard.groupby(["n_shots", "feature_set"]):
        for index, name in ((0, "x"), (1, "y"), (2, "r"), (3, "T")):
            columns = [f"ls{index}_X", f"ls{index}_Y"]
            if not set(columns) <= set(group.columns):
                continue
            values = group[columns].to_numpy().ravel()
            values = values[np.isfinite(values)]
            if values.size == 0:
                continue
            records.append(
                {
                    "n_shots": n_shots,
                    "feature_set": feature_set,
                    "variable": name,
                    "at_upper_bound_rate": float(np.mean(values >= AT_UPPER_BOUND)),
                    "median_length_scale": float(np.median(values)),
                    "n_fits": int(values.size),
                }
            )
    return pd.DataFrame(records)


def recommendation(frame: pd.DataFrame, summary: pd.DataFrame) -> pd.DataFrame:
    """Shot 数ごとの最良と、それと統計的に差がない設定（対応のある差の95%信頼区間が0を含む）。"""
    records = []
    ok = frame[frame["error"] == ""]
    for n_shots, level in summary.groupby("n_shots"):
        best = level.loc[level["RMSE_XY_mean"].idxmin()]
        best_values = ok[(ok["n_shots"] == n_shots) & (ok["method"] == best["method"])].set_index("wafer")[MAIN_METRIC]
        level_frame = ok[ok["n_shots"] == n_shots].pivot_table(index="wafer", columns="method", values=MAIN_METRIC)
        for _, row in level.sort_values("RMSE_XY_mean").iterrows():
            diff = (level_frame[row["method"]] - best_values).dropna()
            sem = diff.std() / np.sqrt(len(diff)) if len(diff) > 1 else np.nan
            low = diff.mean() - Z_95 * sem
            records.append(
                {
                    "n_shots": n_shots,
                    "method": row["method"],
                    "family": row["family"],
                    "feature_set": row["feature_set"],
                    "variant": row["variant"],
                    "factor_mode": row["factor_mode"],
                    "RMSE_XY_mean": row["RMSE_XY_mean"],
                    "diff_vs_best": diff.mean(),
                    "ci_low": low,
                    "ci_high": diff.mean() + Z_95 * sem,
                    "rel_vs_best_pct": 100 * diff.mean() / best["RMSE_XY_mean"],
                    "tied_with_best": bool(row["method"] == best["method"] or (np.isfinite(low) and low <= 0)),
                }
            )
    return pd.DataFrame(records)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="per_wafer_metrics から要約表を作る")
    parser.add_argument("--results", default="results")
    args = parser.parse_args(argv)
    results_dir = Path(args.results)
    tables = results_dir / "tables"
    frame = load_metrics(results_dir)
    summary = summary_by_method(frame)
    outputs = {
        "summary_by_method.csv": summary,
        "ranking_overall.csv": ranking_overall(frame, summary),
        "best_by_family.csv": best_by_family(summary),
        "feature_effect.csv": feature_effect(frame),
        "feature_effect_family.csv": feature_effect_family(frame),
        "factor_effect_gpr.csv": factor_effect_gpr(frame),
        "metric_agreement.csv": metric_agreement(summary),
        "gpr_ard_usage.csv": gpr_ard_usage(frame),
        "recommendation.csv": recommendation(frame, summary),
    }
    for name, table in outputs.items():
        table.to_csv(tables / name, index=False, float_format="%.6g")
        print(f"{tables / name}（{len(table)} 行）")


if __name__ == "__main__":
    main()
