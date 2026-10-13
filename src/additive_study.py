"""追加検証の集計と図：GPR の質的変数を加法カーネル（変量効果）で扱った場合。

本計算（results/）の GPR（none・basis・backfit）と、追加計算（results_additive/）の basis_int・additive・additive_int、
混合（results_mixed/）の mixed・mixed_int を、同じ Wafer・同じ計画で比べる。
交互作用ありの模擬データでの補足検証（results_interaction/）もまとめる。

使い方
    python -m src.additive_study

出力：results_additive/tables/（要約表）と results_additive/figures/（図）
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
from matplotlib.patches import Circle  # noqa: E402

from .geometry import build_layout  # noqa: E402
from .plotting import AXIS, DIVERGING, INK, INK_MUTED, WAFER_RADIUS_MM, save, setup_style  # noqa: E402
from .wafer_generator import GenerationSettings, WaferGenerator  # noqa: E402

MAIN_METRIC = "RMSE_XY"
REPRESENTATIVE = ("matern52", "XYR")  # 本計算で推奨した GPR の設定（カーネル、説明変数）
FEATURE_SETS = ("XY", "XYR")
MODE_ORDER = ("none", "basis", "backfit", "basis_int", "additive", "additive_int", "mixed", "mixed_int")
MODE_LABELS = {
    "none": "質的変数なし",
    "basis": "基底関数で同時推定",
    "backfit": "Backfitting",
    "basis_int": "同時推定＋交互作用",
    "additive": "加法カーネル",
    "additive_int": "加法カーネル＋交互作用",
    "mixed": "混合（Scan 固定・Mark 変量）",
    "mixed_int": "混合＋交互作用",
}
MODE_COLORS = {
    "none": "#898781",
    "basis": "#2a78d6",
    "backfit": "#86b6ef",
    "basis_int": "#104281",
    "additive": "#eb6834",
    "additive_int": "#a33a14",
    "mixed": "#1baf7a",
    "mixed_int": "#0b6e4f",
}
DASHED_MODES = ("backfit", "basis_int", "additive_int", "mixed_int")
MAP_LABELS = {"basis": "同時推定", "mixed": "混合"}  # 誤差マップの見出しは短くする
PAIRS = (
    ("additive", "basis"), ("additive", "none"), ("additive_int", "additive"), ("basis_int", "basis"), ("additive_int", "basis_int"),
    ("mixed", "basis"), ("mixed", "additive"), ("mixed", "none"), ("mixed_int", "mixed"), ("mixed_int", "additive_int"), ("mixed_int", "basis_int"),
)
Z_95 = 1.96
TAU_ZERO_NM = 0.05  # τ がこれ未満なら「ほぼ 0 に縮んだ」とみなす
MAP_WAFER = 0
MAP_LEVELS = (10, 40)


def load_gpr(results: Path, extra_dirs: list[Path]) -> pd.DataFrame:
    main = pd.read_csv(results / "tables" / "per_wafer_metrics.csv.gz")
    main = main[(main["family"] == "GPR") & main["feature_set"].isin(FEATURE_SETS)]
    frames = [main]
    for folder in extra_dirs:
        path = folder / "tables" / "per_wafer_metrics.csv.gz"
        if path.exists():
            extra = pd.read_csv(path)
            frames.append(extra[[c for c in extra.columns if c in main.columns or c.startswith("tau_")]])
    frame = pd.concat(frames, ignore_index=True)
    frame["error"] = frame["error"].fillna("")
    return frame[frame["error"] == ""]


def paired(frame: pd.DataFrame, keys: list[str], new: str, base: str, metric: str = MAIN_METRIC) -> pd.DataFrame:
    wide = frame.pivot_table(index=["wafer", "n_shots", *keys], columns="factor_mode", values=metric)
    if new not in wide or base not in wide:
        return pd.DataFrame()
    diff = (wide[new] - wide[base]).dropna()
    rel = ((wide[new] - wide[base]) / wide[base]).dropna()
    data = pd.concat([diff.rename("diff"), rel.rename("rel")], axis=1).reset_index()
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


def mode_summary(frame: pd.DataFrame) -> pd.DataFrame:
    """Shot 数 × 扱い方：20設定（カーネル10 × 説明変数2）の平均・最良と、代表の設定（matern52・X,Y,半径）の値。"""
    per_config = frame.groupby(["n_shots", "factor_mode", "variant", "feature_set"])[[MAIN_METRIC, "MAE_XY", "R2_XY", "adjR2_XY", "RMSE_XY_outer", "RMSE_XY_inner", "seconds"]].mean().reset_index()
    records = []
    for (n_shots, mode), group in per_config.groupby(["n_shots", "factor_mode"]):
        best = group.loc[group[MAIN_METRIC].idxmin()]
        rep = group[(group["variant"] == REPRESENTATIVE[0]) & (group["feature_set"] == REPRESENTATIVE[1])]
        rep = rep.iloc[0] if len(rep) else None
        record = {
            "n_shots": n_shots,
            "factor_mode": mode,
            "mean_over_configs": group[MAIN_METRIC].mean(),
            "best_config": f"{best['variant']}_{best['feature_set']}",
            "best_rmse": best[MAIN_METRIC],
            "seconds_mean": group["seconds"].mean(),
        }
        if rep is not None:
            for key in (MAIN_METRIC, "MAE_XY", "R2_XY", "adjR2_XY", "RMSE_XY_outer", "RMSE_XY_inner"):
                record[f"rep_{key}"] = rep[key]
        records.append(record)
    return pd.DataFrame(records)


def wafer_quantiles(frame: pd.DataFrame) -> pd.DataFrame:
    rep = frame[(frame["variant"] == REPRESENTATIVE[0]) & (frame["feature_set"] == REPRESENTATIVE[1])]
    return rep.groupby(["n_shots", "factor_mode"])[MAIN_METRIC].describe(percentiles=[0.5, 0.9]).reset_index()


def kernel_table(frame: pd.DataFrame) -> pd.DataFrame:
    sub = frame[frame["factor_mode"].isin(["basis", "additive", "mixed"])]
    table = sub.groupby(["variant", "feature_set", "factor_mode"])[MAIN_METRIC].mean().unstack(["feature_set", "factor_mode"])
    table.columns = [f"{fs}_{mode}" for fs, mode in table.columns]
    lo = sub[sub["n_shots"] == sub["n_shots"].min()].groupby(["variant", "factor_mode"])[MAIN_METRIC].mean().unstack()
    lo.columns = [f"lo_{mode}" for mode in lo.columns]
    return table.join(lo).sort_values("XYR_additive").reset_index()


def true_effect_scale(config: dict, n_wafers: int) -> dict[str, float]:
    """模擬データの質的変数の効果の大きさ（Wafer ごとの値の中央値）。τ の推定値と比べる目安。

    Scan：方向1・2 の効果は ±δ/2 なので、2水準の値の標準偏差は |δ|/2。
    Mark：4水準のオフセットの標準偏差（母分散の形、自由度 n）。
    """
    layout = build_layout(config)
    generator = WaferGenerator(layout, GenerationSettings.from_config(config), int(config["random"]["master_seed"]))
    scan, mark = [], []
    for wafer_id in range(n_wafers):
        sample = generator.generate(wafer_id)
        scan.append(np.abs(sample.scan_difference) / 2.0)
        mark.append(sample.mark_offset_by_mark.std(axis=0))
    scan, mark = np.array(scan), np.array(mark)
    return {"scan_X": float(np.median(scan[:, 0])), "scan_Y": float(np.median(scan[:, 1])),
            "mark_X": float(np.median(mark[:, 0])), "mark_Y": float(np.median(mark[:, 1]))}


def tau_summary(frame: pd.DataFrame) -> pd.DataFrame:
    rep = frame[(frame["variant"] == REPRESENTATIVE[0]) & (frame["feature_set"] == REPRESENTATIVE[1]) & frame["factor_mode"].isin(["additive", "additive_int", "mixed", "mixed_int"])]
    records = []
    for (n_shots, mode), group in rep.groupby(["n_shots", "factor_mode"]):
        for name in ("scan", "mark", "scan_mark"):
            cols = [f"tau_{name}_X", f"tau_{name}_Y"]
            if not set(cols) <= set(group.columns):
                continue
            for axis, col in zip("XY", cols):
                values = group[col].dropna().to_numpy()
                if values.size == 0:
                    continue
                records.append({"n_shots": n_shots, "factor_mode": mode, "term": name, "axis": axis,
                                "median": float(np.median(values)), "q25": float(np.percentile(values, 25)),
                                "q75": float(np.percentile(values, 75)), "near_zero_rate": float(np.mean(values < TAU_ZERO_NM))})
    return pd.DataFrame(records)


def scan_collapse_table(frame: pd.DataFrame) -> pd.DataFrame:
    """加法カーネルで Scan方向の τ がほぼ 0 に縮んだ Wafer と、そうでない Wafer での同時推定との差（代表の設定）。

    Scan方向は2水準しかないので τ_s の推定が不安定になる。τ_s ≈ 0 だと Scan方向の差を推定しないので精度が落ちる。
    """
    rep = frame[(frame["variant"] == REPRESENTATIVE[0]) & (frame["feature_set"] == REPRESENTATIVE[1])]
    additive = rep[rep["factor_mode"] == "additive"].set_index(["wafer", "n_shots"])
    basis = rep[rep["factor_mode"] == "basis"].set_index(["wafer", "n_shots"])[MAIN_METRIC]
    additive = additive.assign(diff=additive[MAIN_METRIC] - basis)
    additive["scan_collapsed"] = (additive[["tau_scan_X", "tau_scan_Y"]] < TAU_ZERO_NM).any(axis=1)
    records = []
    for n_shots, group in additive.groupby(level="n_shots"):
        collapsed = group[group["scan_collapsed"]]
        kept = group[~group["scan_collapsed"]]
        records.append({
            "n_shots": n_shots,
            "collapsed_rate": float(group["scan_collapsed"].mean()),
            "diff_collapsed": float(collapsed["diff"].mean()) if len(collapsed) else float("nan"),
            "diff_kept": float(kept["diff"].mean()) if len(kept) else float("nan"),
            "n_collapsed": int(len(collapsed)),
        })
    return pd.DataFrame(records)


def interaction_tables(path: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    frame = pd.read_csv(path / "tables" / "per_wafer_metrics.csv.gz")
    frame["error"] = frame["error"].fillna("")
    frame = frame[frame["error"] == ""]
    summary = frame.groupby(["n_shots", "method", "family", "factor_mode"])[MAIN_METRIC].agg(["mean", "median"]).reset_index()
    gpr = frame[frame["family"] == "GPR"]
    pairs = pd.concat([paired(gpr, ["variant", "feature_set"], new, base) for new, base in PAIRS], ignore_index=True)
    return summary, pairs


# ---------------------------------------------------------------------------- 図
def plot_mode_lines(summary: pd.DataFrame, tps: pd.Series, figures: Path) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(12, 4.2), layout="constrained")
    for mode in MODE_ORDER:
        rows = summary[summary["factor_mode"] == mode].sort_values("n_shots")
        if rows.empty:
            continue
        style = "--" if mode in DASHED_MODES else "-"
        axes[0].plot(rows["n_shots"], rows["rep_RMSE_XY"], color=MODE_COLORS[mode], ls=style, lw=2, marker="o", ms=4, label=MODE_LABELS[mode])
    axes[0].plot(tps.index, tps.values, color=INK_MUTED, lw=1.2, ls=":", label="参考：TPS（X, Y, 半径）")
    axes[0].set_title("GPR matern52・X, Y, 半径（本計算で推奨した設定）")
    axes[0].set_xlabel("計測 Shot 数")
    axes[0].set_ylabel("RMSE（X・Y）[nm]、1000枚の平均")
    axes[0].set_ylim(bottom=0)
    base = summary[summary["factor_mode"] == "basis"].set_index("n_shots")["rep_RMSE_XY"]
    for mode in MODE_ORDER:
        rows = summary[summary["factor_mode"] == mode].set_index("n_shots")["rep_RMSE_XY"]
        if rows.empty or mode in ("basis", "none"):  # 質的変数なしは比が大きすぎるので左の図だけに示す
            continue
        style = "--" if mode in DASHED_MODES else "-"
        axes[1].plot(rows.index, 100 * (rows / base - 1), color=MODE_COLORS[mode], ls=style, lw=2, marker="o", ms=4, label=MODE_LABELS[mode])
    axes[1].axhline(0, color=AXIS, lw=1)
    axes[1].set_title("同時推定（基底関数）との比 [%]（負＝良い、質的変数なしは除く）")
    axes[1].set_xlabel("計測 Shot 数")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="outside right center")
    save(fig, figures, "figA1_mode_rmse.png")


def plot_tau(tau: pd.DataFrame, truth: dict, figures: Path) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(11, 3.8), sharey=True, layout="constrained")
    colors = {"scan": "#2a78d6", "mark": "#eb6834", "scan_mark": "#1baf7a"}
    names = {"scan": "τ Scan方向", "mark": "τ Mark番号", "scan_mark": "τ 交互作用"}
    for ax, axis in zip(axes, "XY"):
        for term in ("scan", "mark", "scan_mark"):
            rows = tau[(tau["factor_mode"] == "additive_int") & (tau["term"] == term) & (tau["axis"] == axis)].sort_values("n_shots")
            if rows.empty:
                continue
            ax.plot(rows["n_shots"], rows["median"], color=colors[term], lw=2, marker="o", ms=4, label=f"{names[term]}（中央値）")
            ax.fill_between(rows["n_shots"], rows["q25"], rows["q75"], color=colors[term], alpha=0.15, lw=0)
        ax.axhline(truth[f"scan_{axis}"], color=colors["scan"], ls=":", lw=1.2, label="真の大きさ：Scan（|δ|/2 の中央値）")
        ax.axhline(truth[f"mark_{axis}"], color=colors["mark"], ls=":", lw=1.2, label="真の大きさ：Mark（4水準の標準偏差の中央値）")
        ax.axhline(0, color=colors["scan_mark"], ls=":", lw=1.2, label="真の大きさ：交互作用（0）")
        ax.set_title(f"{axis} 成分")
        ax.set_xlabel("計測 Shot 数")
    axes[0].set_ylabel("推定した τ [nm]（帯は 25〜75% 点）")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="outside right center", fontsize=8)
    fig.suptitle("加法カーネル＋交互作用で推定した τ（GPR matern52・X, Y, 半径）")
    save(fig, figures, "figA2_tau.png")


def plot_maps(results: Path, additive: Path, mixed: Path, figures: Path) -> None:
    main_samples = np.load(results / "samples" / "sample_predictions.npz")
    add_samples = np.load(additive / "samples" / "sample_predictions.npz")
    marks = pd.read_csv(results / "tables" / "layout_marks.csv")
    plans = pd.read_csv(results / "tables" / "sampling_plans.csv").set_index("n_shots")
    prefix = f"w{MAP_WAFER}"
    truth = main_samples[f"{prefix}__trend"] + main_samples[f"{prefix}__mark_offset"] + main_samples[f"{prefix}__scan_offset"]
    method = lambda mode: f"GPR_{REPRESENTATIVE[0]}_{REPRESENTATIVE[1]}_{mode}"  # noqa: E731
    columns = [("none", main_samples), ("basis", main_samples), ("additive", add_samples)]
    mixed_path = mixed / "samples" / "sample_predictions.npz"
    if mixed_path.exists():
        columns.append(("mixed", np.load(mixed_path)))
    fig, axes = plt.subplots(len(MAP_LEVELS), len(columns) + 1, figsize=(3.0 * (len(columns) + 1), 3.0 * len(MAP_LEVELS)))
    limit = float(np.max(np.abs(truth[:, 0])))
    for row, n_shots in enumerate(MAP_LEVELS):
        chosen = {int(v) for v in plans.loc[n_shots, "shotNo"].split()}
        train = marks["shotNo"].isin(chosen).to_numpy()
        ax = axes[row, 0]
        ax.scatter(marks["x_mm"], marks["y_mm"], c=truth[:, 0], cmap=DIVERGING, vmin=-limit, vmax=limit, s=6, lw=0)
        ax.scatter(marks["x_mm"][train], marks["y_mm"][train], facecolors="none", edgecolors=INK, s=10, lw=0.5)
        ax.set_title(f"真値 X（○計測 {n_shots} Shot）", fontsize=9)
        for col, (mode, samples) in enumerate(columns, start=1):
            key = f"{prefix}__est__{n_shots}__{method(mode)}"
            ax = axes[row, col]
            error = samples[key][:, 0] - truth[~train, 0]
            ax.scatter(marks["x_mm"][~train], marks["y_mm"][~train], c=error, cmap=DIVERGING, vmin=-6, vmax=6, s=6, lw=0)
            ax.scatter(marks["x_mm"][train], marks["y_mm"][train], color=AXIS, s=4, lw=0)
            ax.set_title(f"{MAP_LABELS.get(mode, MODE_LABELS[mode])}（RMSE {np.sqrt(np.mean(error**2)):.2f}）", fontsize=9)
        for ax in axes[row]:
            ax.set_aspect("equal")
            ax.set_xlim(-155, 155)
            ax.set_ylim(-155, 155)
            ax.set_xticks([])
            ax.set_yticks([])
            ax.grid(False)
            ax.add_patch(Circle((0, 0), WAFER_RADIUS_MM, fill=False, color=AXIS, lw=0.8))
            for spine in ax.spines.values():
                spine.set_visible(False)
    sm = plt.cm.ScalarMappable(cmap=DIVERGING, norm=plt.Normalize(-6, 6))
    cbar = fig.colorbar(sm, ax=axes[:, 1:], fraction=0.02, pad=0.01)
    cbar.set_label("推定誤差 X [nm]（灰色の点は計測した Mark）")
    cbar.outline.set_visible(False)
    save(fig, figures, "figA3_error_maps.png")


def plot_interaction(summary: pd.DataFrame, figures: Path) -> None:
    fig, ax = plt.subplots(figsize=(7.5, 4.0), layout="constrained")
    for mode in ("none", "basis", "basis_int", "additive", "additive_int", "mixed", "mixed_int"):
        rows = summary[(summary["family"] == "GPR") & (summary["factor_mode"] == mode)].sort_values("n_shots")
        if rows.empty:
            continue
        style = "--" if mode in DASHED_MODES else "-"
        ax.plot(rows["n_shots"], rows["mean"], color=MODE_COLORS[mode], ls=style, lw=2, marker="o", ms=4, label=MODE_LABELS[mode])
    tps = summary[summary["family"] == "TPS"].sort_values("n_shots")
    ax.plot(tps["n_shots"], tps["mean"], color=INK_MUTED, lw=1.2, ls=":", label="参考：TPS（X, Y, 半径）")
    ax.set_title("交互作用ありの模擬データ（GPR matern52・X, Y, 半径）")
    ax.set_xlabel("計測 Shot 数")
    ax.set_ylabel("RMSE（X・Y）[nm]、1000枚の平均")
    ax.set_ylim(bottom=0)
    fig.legend(*ax.get_legend_handles_labels(), loc="outside right center", fontsize=8)
    save(fig, figures, "figA4_interaction.png")


def plot_distribution(frame: pd.DataFrame, figures: Path) -> None:
    rep = frame[(frame["variant"] == REPRESENTATIVE[0]) & (frame["feature_set"] == REPRESENTATIVE[1])]
    levels = (10, 20, 40)
    modes = tuple(m for m in ("none", "basis", "additive", "mixed") if m in set(rep["factor_mode"]))
    fig, axes = plt.subplots(1, len(levels), figsize=(12, 3.4), layout="constrained")
    for ax, n_shots in zip(axes, levels):
        data = [rep[(rep["n_shots"] == n_shots) & (rep["factor_mode"] == mode)][MAIN_METRIC].to_numpy() for mode in modes]
        parts = ax.boxplot(data, patch_artist=True, showfliers=False, widths=0.6, medianprops={"color": INK, "lw": 1.2})
        for patch, mode in zip(parts["boxes"], modes):
            patch.set_facecolor(MODE_COLORS[mode])
            patch.set_alpha(0.75)
            patch.set_edgecolor(MODE_COLORS[mode])
        ax.set_xticks(range(1, len(modes) + 1), [MODE_LABELS[m].replace("（", "\n（") for m in modes], fontsize=7.5)
        ax.set_title(f"{n_shots} Shot")
    axes[0].set_ylabel("Wafer ごとの RMSE（X・Y）[nm]")
    save(fig, figures, "figA5_distribution.png")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="加法カーネルの追加検証の集計と図")
    parser.add_argument("--results", default="results")
    parser.add_argument("--additive", default="results_additive")
    parser.add_argument("--mixed", default="results_mixed")
    parser.add_argument("--interaction", default="results_interaction")
    args = parser.parse_args(argv)
    results, additive, interaction = Path(args.results), Path(args.additive), Path(args.interaction)
    mixed = Path(args.mixed)
    tables = additive / "tables"
    figures = additive / "figures"
    figures.mkdir(parents=True, exist_ok=True)
    setup_style()

    frame = load_gpr(results, [additive, mixed])
    summary = mode_summary(frame)
    rep_keys = ["variant", "feature_set"]
    rep = frame[(frame["variant"] == REPRESENTATIVE[0]) & (frame["feature_set"] == REPRESENTATIVE[1])]
    pairs_rep = pd.concat([paired(rep, rep_keys, new, base) for new, base in PAIRS], ignore_index=True)
    config_mean = frame.groupby(["wafer", "n_shots", "factor_mode"])[MAIN_METRIC].mean().reset_index()
    config_mean["variant"] = "20設定の平均"
    config_mean["feature_set"] = "-"
    pairs_all = pd.concat([paired(config_mean, rep_keys, new, base) for new, base in PAIRS], ignore_index=True)
    ranking = frame.groupby(["variant", "feature_set", "factor_mode"])[MAIN_METRIC].mean().sort_values().reset_index().head(20)
    with open(results / "config_used.json", encoding="utf-8") as handle:
        config = json.load(handle)
    truth = true_effect_scale(config, int(frame["wafer"].nunique()))
    tau = tau_summary(frame)
    main_all = pd.read_csv(results / "tables" / "summary_by_method.csv")
    tps = main_all[main_all["method"] == "TPS_XYR"].set_index("n_shots")["RMSE_XY_mean"]

    outputs = {
        "mode_summary.csv": summary,
        "mode_paired_representative.csv": pairs_rep,
        "mode_paired_all_configs.csv": pairs_all,
        "mode_wafer_quantiles.csv": wafer_quantiles(frame),
        "kernel_basis_vs_additive.csv": kernel_table(frame),
        "ranking_with_additive.csv": ranking,
        "tau_summary.csv": tau,
        "scan_tau_collapse.csv": scan_collapse_table(frame),
    }
    if (interaction / "tables" / "per_wafer_metrics.csv.gz").exists():
        inter_summary, inter_pairs = interaction_tables(interaction)
        outputs["interaction_summary.csv"] = inter_summary
        outputs["interaction_paired.csv"] = inter_pairs
        plot_interaction(inter_summary, figures)
    tables.mkdir(parents=True, exist_ok=True)
    for name, table in outputs.items():
        table.to_csv(tables / name, index=False, float_format="%.6g")
        print(f"{tables / name}（{len(table)} 行）")
    (tables / "true_effect_scale.json").write_text(json.dumps(truth, indent=2), encoding="utf-8")
    plot_mode_lines(summary, tps, figures)
    plot_tau(tau, truth, figures)
    plot_maps(results, additive, mixed, figures)
    plot_distribution(frame, figures)


if __name__ == "__main__":
    main()
