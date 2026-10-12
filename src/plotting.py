"""図の作成（計算結果の CSV・npz だけを読む。計算処理とは分離している）。

使い方
    python -m src.plotting --results results

色は全図で同じ意味に固定する。
- 手法の系統：GPR＝青、TPS＝橙、Kriging＝アクア、Universal Kriging＝黄、GAM＝マゼンタ、XY5＝緑、RT＝紫
- 説明変数の組：X,Y＝薄い青、X,Y,半径＝青、X,Y,半径,T＝濃い青（入れ子の順序を明度で表す）
- GPR の質的変数の扱い：使わない＝灰、基底関数で同時推定＝青、Backfitting＝橙
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
from matplotlib.colors import LinearSegmentedColormap  # noqa: E402
from matplotlib.patches import Circle, Rectangle  # noqa: E402

DPI = 220
FONT_FAMILY = ["Hiragino Sans", "BIZ UDGothic", "Yu Gothic", "Meiryo", "Noto Sans CJK JP", "DejaVu Sans"]
INK = "#0b0b0b"
INK_SECONDARY = "#52514e"
INK_MUTED = "#898781"
GRID = "#e1e0d9"
AXIS = "#c3c2b7"
NEUTRAL_FILL = "#f0efec"
FAMILY_ORDER = ("GPR", "TPS", "OK", "UK", "GAM", "XY", "RT")
FAMILY_COLORS = {"GPR": "#2a78d6", "TPS": "#eb6834", "OK": "#1baf7a", "UK": "#eda100", "GAM": "#e87ba4", "XY": "#008300", "RT": "#4a3aa7"}
FAMILY_LABELS = {"GPR": "GPR", "TPS": "TPS", "OK": "Kriging", "UK": "Universal Kriging", "GAM": "GAM", "XY": "XY5次多項式", "RT": "RTモデル"}
FEATURE_ORDER = ("XY", "XYR", "XYRT")
FEATURE_COLORS = {"XY": "#86b6ef", "XYR": "#2a78d6", "XYRT": "#104281"}
FEATURE_LABELS = {"XY": "X, Y", "XYR": "X, Y, 半径", "XYRT": "X, Y, 半径, T", "-": "（固定の基底）"}
MODE_ORDER = ("none", "basis", "backfit")
MODE_COLORS = {"none": "#898781", "basis": "#2a78d6", "backfit": "#eb6834"}
MODE_LABELS = {"none": "質的変数なし", "basis": "基底関数で同時推定", "backfit": "Backfitting"}
KERNEL_ORDER = (
    "exponential", "squaredexponential", "matern32", "matern52", "rationalquadratic",
    "ardexponential", "ardsquaredexponential", "ardmatern32", "ardmatern52", "ardrationalquadratic",
)
VARIOGRAM_ORDER = ("linear", "gaussian", "power", "exponential")
DIVERGING = LinearSegmentedColormap.from_list("blue_red", ["#104281", "#3987e5", "#f0efec", "#e66767", "#9e2a2a"])
SEQUENTIAL = LinearSegmentedColormap.from_list("blue_seq", ["#f3f8fe", "#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"])
SHOT_SIZE_MM = (22.0, 26.0)
WAFER_RADIUS_MM = 150.0
FOCUS_LEVELS = (10, 20, 40)


def available_fonts() -> list[str]:
    installed = {font.name for font in matplotlib.font_manager.fontManager.ttflist}
    return [name for name in FONT_FAMILY if name in installed] or ["DejaVu Sans"]


def setup_style() -> None:
    plt.rcParams.update(
        {
            "font.family": available_fonts(),
            "font.size": 9,
            "axes.titlesize": 10,
            "axes.labelsize": 9,
            "axes.edgecolor": AXIS,
            "axes.labelcolor": INK,
            "axes.titlecolor": INK,
            "axes.grid": True,
            "grid.color": GRID,
            "grid.linewidth": 0.6,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "xtick.color": INK_SECONDARY,
            "ytick.color": INK_SECONDARY,
            "legend.frameon": False,
            "legend.fontsize": 8.5,
            "figure.facecolor": "white",
            "savefig.facecolor": "white",
            "axes.unicode_minus": False,
        }
    )


def save(fig, folder: Path, name: str) -> None:
    fig.savefig(folder / name, dpi=DPI, bbox_inches="tight")
    plt.close(fig)
    print(folder / name)


def method_label(row) -> str:
    family = row["family"]
    if family == "GPR":
        return f"GPR {row['variant']}（{FEATURE_LABELS[row['feature_set']]}・{MODE_LABELS[row['factor_mode']]}）"
    if family in ("OK", "UK"):
        return f"{FAMILY_LABELS[family]} {row['variant']}（{FEATURE_LABELS[row['feature_set']]}）"
    if family in ("TPS", "GAM"):
        return f"{FAMILY_LABELS[family]}（{FEATURE_LABELS[row['feature_set']]}）"
    return row["method"]


# ----------------------------------------------------------------------------
# 1. 配置とサンプリング計画
# ----------------------------------------------------------------------------
def plot_layout(tables: Path, figures: Path) -> None:
    shots = pd.read_csv(tables / "layout_shots.csv")
    marks = pd.read_csv(tables / "layout_marks.csv")
    plans = pd.read_csv(tables / "sampling_plans.csv").set_index("n_shots")
    levels = [n for n in (10, 20, 30, 40) if n in plans.index]
    fig, axes = plt.subplots(1, len(levels), figsize=(3.0 * len(levels), 3.2))
    for ax, n_shots in zip(np.atleast_1d(axes), levels):
        chosen = {int(v) for v in plans.loc[n_shots, "shotNo"].split()}
        ax.add_patch(Circle((0, 0), WAFER_RADIUS_MM, fill=False, color=AXIS, lw=1))
        for _, shot in shots.iterrows():
            selected = int(shot["shotNo"]) in chosen
            face = ("#2a78d6" if shot["Direction"] == 1 else "#eb6834") if selected else "white"
            ax.add_patch(
                Rectangle(
                    (shot["Xmm"] - SHOT_SIZE_MM[0] / 2, shot["Ymm"] - SHOT_SIZE_MM[1] / 2), *SHOT_SIZE_MM,
                    facecolor=face, edgecolor=AXIS, lw=0.6, alpha=0.85 if selected else 1.0,
                )
            )
        ax.scatter(marks["x_mm"], marks["y_mm"], s=1.2, color=INK_MUTED, zorder=3, lw=0)
        ax.set_xlim(-155, 155)
        ax.set_ylim(-155, 155)
        ax.set_aspect("equal")
        ax.grid(False)
        ax.set_xticks([])
        ax.set_yticks([])
        for spine in ax.spines.values():
            spine.set_visible(False)
        ax.set_title(f"{n_shots} Shot（{plans.loc[n_shots, 'n_train_marks']} Mark）")
    handles = [Rectangle((0, 0), 1, 1, fc="#2a78d6"), Rectangle((0, 0), 1, 1, fc="#eb6834"), Rectangle((0, 0), 1, 1, fc="white", ec=AXIS)]
    fig.legend(handles, ["計測Shot（Scan方向1）", "計測Shot（Scan方向2）", "未計測Shot（推定する）"], loc="lower center", ncol=3, bbox_to_anchor=(0.5, -0.04))
    save(fig, figures, "fig01_layout_sampling.png")


# ----------------------------------------------------------------------------
# 2. 模擬データの成分
# ----------------------------------------------------------------------------
def plot_components(results: Path, figures: Path, config: dict) -> None:
    samples = np.load(results / "samples" / "sample_predictions.npz")
    marks = pd.read_csv(results / "tables" / "layout_marks.csv")
    x, y = marks["x_mm"].to_numpy(), marks["y_mm"].to_numpy()
    trend = samples["w0__trend"][:, 0]
    offsets = samples["w0__mark_offset"][:, 0] + samples["w0__scan_offset"][:, 0]
    noise = samples["w0__noise"][:, 0]
    panels = [
        ("面内傾向（Zernike）", trend),
        ("Mark番号のOffset＋Scan方向の差", offsets),
        ("計測ノイズ（一様分布）", noise),
        ("計測値（合計）", trend + offsets + noise),
    ]
    fig, axes = plt.subplots(1, 5, figsize=(17, 3.4), gridspec_kw={"width_ratios": [1, 1, 1, 1, 1.25]}, layout="constrained")
    for ax, (title, values) in zip(axes[:4], panels):
        limit = float(np.max(np.abs(values)))
        sc = ax.scatter(x, y, c=values, cmap=DIVERGING, vmin=-limit, vmax=limit, s=9, lw=0)
        ax.add_patch(Circle((0, 0), WAFER_RADIUS_MM, fill=False, color=AXIS, lw=0.8))
        ax.set_aspect("equal")
        ax.set_xlim(-155, 155)
        ax.set_ylim(-155, 155)
        ax.set_xticks([])
        ax.set_yticks([])
        ax.grid(False)
        for spine in ax.spines.values():
            spine.set_visible(False)
        ax.set_title(title)
        cbar = fig.colorbar(sc, ax=ax, fraction=0.046, pad=0.01, shrink=0.85)
        cbar.ax.set_title("X [nm]", fontsize=8)
        cbar.outline.set_visible(False)
    gen = config["generation"]
    radius = np.linspace(0, 147, 200)
    ratio = radius / marks["r_mm"].max()
    width = gen["noise_halfwidth_center_nm"] + (gen["noise_halfwidth_edge_nm"] - gen["noise_halfwidth_center_nm"]) * ratio ** gen["noise_radial_power"]
    ax = axes[4]
    ax.fill_between(radius, -width, width, color="#cde2fb", lw=0)
    ax.plot(radius, width, color="#2a78d6", lw=2)
    ax.plot(radius, -width, color="#2a78d6", lw=2)
    ax.scatter(marks["r_mm"], noise, s=4, color=INK_SECONDARY, lw=0)
    ax.set_xlabel("Mark の半径 [mm]")
    ax.set_ylabel("ノイズ [nm]")
    ax.set_title("ノイズの幅：中心 ±1 → 最外周 ±3 nm")
    save(fig, figures, "fig02_data_components.png")


# ----------------------------------------------------------------------------
# 3. 系統ごとの最良（RMSE と Shot 数）
# ----------------------------------------------------------------------------
def _best_rows(summary: pd.DataFrame) -> pd.DataFrame:
    """系統ごとに、全 Shot 数の平均 RMSE が最小の設定を1つ選ぶ（Shot 数で設定を変えない）。

    GPR は Backfitting を候補から外す（同時推定とほぼ同じ解で、実装の簡単な同時推定を代表にする）。
    """
    candidates = summary[~((summary["family"] == "GPR") & (summary["factor_mode"] == "backfit"))]
    avg = candidates.groupby(["family", "method"])["RMSE_XY_mean"].mean().reset_index()
    chosen = avg.loc[avg.groupby("family")["RMSE_XY_mean"].idxmin(), "method"]
    return summary[summary["method"].isin(chosen)]


def plot_rmse_vs_shots(summary: pd.DataFrame, figures: Path) -> None:
    best = _best_rows(summary)
    fig, axes = plt.subplots(1, 2, figsize=(12, 4.2))
    for metric, ax, ylabel in (("RMSE_XY_mean", axes[0], "RMSE（X・Y）[nm]"), ("R2_XY_mean", axes[1], "決定係数 R²（X・Y）")):
        for family in FAMILY_ORDER:
            rows = best[best["family"] == family].sort_values("n_shots")
            if rows.empty:
                continue
            ax.plot(rows["n_shots"], rows[metric], color=FAMILY_COLORS[family], lw=2, marker="o", ms=4.5, label=method_label(rows.iloc[0]))
        ax.set_xlabel("計測 Shot 数")
        ax.set_ylabel(ylabel)
        ax.set_xticks(sorted(best["n_shots"].unique()))
    axes[0].set_ylim(bottom=0)
    axes[1].set_ylim(top=1.0)
    axes[0].legend(loc="upper right", fontsize=7.5)
    fig.suptitle("系統ごとの最良の設定（全 Shot 数の平均 RMSE で1つ選んだもの。GPR は同時推定から選択）", y=1.02)
    save(fig, figures, "fig03_rmse_vs_shots_family.png")


def plot_family_feature_heatmap(summary: pd.DataFrame, figures: Path) -> None:
    """行＝系統×説明変数（×GPR の質的変数の扱い）。各行で全 Shot 数平均が最良の変種を1つ選ぶ。"""
    rows = []
    for family in FAMILY_ORDER:
        sub = summary[summary["family"] == family]
        if family == "GPR":
            groups = [(fs, mode) for mode in MODE_ORDER for fs in FEATURE_ORDER]
        elif family in ("XY", "RT"):
            groups = [(None, None)]
        else:
            groups = [(fs, None) for fs in FEATURE_ORDER]
        for feature_set, mode in groups:
            part = sub
            if feature_set:
                part = part[part["feature_set"] == feature_set]
            if mode:
                part = part[part["factor_mode"] == mode]
            if family in ("XY", "RT"):
                for method, mpart in part.groupby("method"):
                    rows.append((method, mpart.set_index("n_shots")["RMSE_XY_mean"], family))
                continue
            avg = part.groupby("method")["RMSE_XY_mean"].mean()
            best_method = avg.idxmin()
            mpart = part[part["method"] == best_method]
            info = mpart.iloc[0]
            label = f"{FAMILY_LABELS[family]}｜{FEATURE_LABELS[feature_set]}"
            if mode:
                label += f"｜{MODE_LABELS[mode]}"
            if family in ("GPR", "OK", "UK"):
                label += f"｜{info['variant']}"
            rows.append((label, mpart.set_index("n_shots")["RMSE_XY_mean"], family))
    levels = sorted(summary["n_shots"].unique())
    matrix = np.array([[series.get(n, np.nan) for n in levels] for _, series, _ in rows])
    fig, ax = plt.subplots(figsize=(15, 0.27 * len(rows) + 1.0))
    vmax = float(np.nanpercentile(matrix, 98))
    image = ax.imshow(matrix, cmap=SEQUENTIAL, vmin=0, vmax=vmax, aspect="auto")
    for i in range(matrix.shape[0]):
        for j in range(matrix.shape[1]):
            value = matrix[i, j]
            ax.text(j, i, f"{value:.2f}", ha="center", va="center", fontsize=8.5, color="white" if value > 0.55 * vmax else INK)
    ax.set_xticks(range(len(levels)), [f"{n}" for n in levels])
    ax.set_yticks(range(len(rows)), [label for label, _, _ in rows], fontsize=8.5)
    for tick, (_, _, family) in zip(ax.get_yticklabels(), rows):
        tick.set_color(INK)
    ax.set_xlabel("計測 Shot 数")
    ax.grid(False)
    cbar = fig.colorbar(image, ax=ax, fraction=0.03, pad=0.02)
    cbar.set_label("RMSE（X・Y）[nm]、1000枚の平均")
    cbar.outline.set_visible(False)
    save(fig, figures, "fig04_family_feature_heatmap.png")


# ----------------------------------------------------------------------------
# 4. 説明変数の効果
# ----------------------------------------------------------------------------
def plot_feature_effect(effect: pd.DataFrame, figures: Path) -> None:
    families = [f for f in FAMILY_ORDER if f in effect["family"].unique()]
    fig, axes = plt.subplots(1, len(families), figsize=(3.2 * len(families), 3.0), sharey=True, layout="constrained")
    for ax, family in zip(np.atleast_1d(axes), families):
        for comparison, color, label in (("XYR-XY", FEATURE_COLORS["XYR"], "半径を追加"), ("XYRT-XY", FEATURE_COLORS["XYRT"], "半径＋Tを追加")):
            rows = effect[(effect["family"] == family) & (effect["comparison"] == comparison)].sort_values("n_shots")
            ax.plot(rows["n_shots"], rows["rel_mean_pct"], color=color, lw=2, marker="o", ms=4, label=label)
        ax.axhline(0, color=INK_MUTED, lw=1)
        ax.set_title(FAMILY_LABELS[family])
        ax.set_xlabel("計測 Shot 数")
    np.atleast_1d(axes)[0].set_ylabel("RMSE の変化 [%]\n（X, Y のみとの比、負＝改善）")
    handles, labels = np.atleast_1d(axes)[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="outside lower center", ncol=2)
    save(fig, figures, "fig05_feature_effect.png")


# ----------------------------------------------------------------------------
# 5. GPR の質的変数の扱い
# ----------------------------------------------------------------------------
def plot_factor_effect(frame: pd.DataFrame, summary: pd.DataFrame, figures: Path) -> None:
    gpr = summary[summary["family"] == "GPR"]
    fig, ax = plt.subplots(figsize=(5.4, 3.5))
    for mode in MODE_ORDER:
        rows = gpr[gpr["factor_mode"] == mode].groupby("n_shots")["RMSE_XY_outer_mean"].mean()
        inner = gpr[gpr["factor_mode"] == mode].groupby("n_shots")["RMSE_XY_inner_mean"].mean()
        ax.plot(rows.index, rows.values, color=MODE_COLORS[mode], lw=2, marker="o", ms=4, label=f"{MODE_LABELS[mode]}：外周")
        ax.plot(inner.index, inner.values, color=MODE_COLORS[mode], lw=1.6, ls="--", label=f"{MODE_LABELS[mode]}：内側")
    ax.set_xlabel("計測 Shot 数")
    ax.set_ylabel("RMSE（X・Y）[nm]")
    ax.set_title("GPR の外周（半径 ≥ 120 mm）と内側（30設定の平均）", fontsize=9)
    ax.set_ylim(bottom=0)
    ax.legend(fontsize=7.5, ncol=2)
    save(fig, figures, "fig06_factor_edge.png")

    fig, ax = plt.subplots(figsize=(6.2, 3.6))
    wide = frame[frame["family"] == "GPR"].pivot_table(index=["wafer", "n_shots", "variant", "feature_set"], columns="factor_mode", values="RMSE_XY")
    diff = (wide["backfit"] - wide["basis"]).dropna()
    clipped = np.clip(diff.to_numpy(), -0.5, 0.5)
    ax.hist(clipped, bins=np.linspace(-0.5, 0.5, 81), color=MODE_COLORS["backfit"], lw=0)
    ax.set_yscale("log")
    ax.set_xlabel("RMSE の差 Backfitting − 同時推定 [nm]（±0.5 で打ち切り）")
    ax.set_ylabel("件数（Wafer×Shot数×設定）")
    share = float(np.mean(np.abs(diff) < 0.01))
    ax.set_title(f"差が 0.01 nm 未満：{share * 100:.1f}%")
    save(fig, figures, "fig06_backfit_diff.png")


# ----------------------------------------------------------------------------
# 6. カーネル・バリオグラム
# ----------------------------------------------------------------------------
def plot_kernel_heatmap(summary: pd.DataFrame, figures: Path) -> None:
    gpr = summary[(summary["family"] == "GPR") & (summary["factor_mode"] == "basis")]
    levels = [n for n in FOCUS_LEVELS if n in gpr["n_shots"].unique()]
    fig, axes = plt.subplots(1, len(levels), figsize=(4.2 * len(levels), 4.4))
    for ax, n_shots in zip(np.atleast_1d(axes), levels):
        level = gpr[gpr["n_shots"] == n_shots]
        matrix = np.array([[level[(level["variant"] == k) & (level["feature_set"] == f)]["RMSE_XY_mean"].mean() for f in FEATURE_ORDER] for k in KERNEL_ORDER])
        best = np.nanmin(matrix)
        image = ax.imshow(matrix / best, cmap=SEQUENTIAL, vmin=1.0, vmax=1.5, aspect="auto")
        for i in range(matrix.shape[0]):
            for j in range(matrix.shape[1]):
                ax.text(j, i, f"{matrix[i, j]:.2f}", ha="center", va="center", fontsize=7.5, color="white" if matrix[i, j] / best > 1.3 else INK, fontweight="bold" if matrix[i, j] == best else "normal")
        ax.set_xticks(range(3), [FEATURE_LABELS[f] for f in FEATURE_ORDER], fontsize=7.5)
        ax.set_yticks(range(len(KERNEL_ORDER)), KERNEL_ORDER if ax is np.atleast_1d(axes)[0] else [""] * len(KERNEL_ORDER), fontsize=7.5)
        ax.set_title(f"{n_shots} Shot")
        ax.grid(False)
    cbar = fig.colorbar(image, ax=axes, fraction=0.02, pad=0.02)
    cbar.set_label("最良との比（RMSE）")
    cbar.outline.set_visible(False)
    fig.suptitle("GPR のカーネル × 説明変数（質的変数は基底関数で同時推定）：RMSE [nm]、1000枚の平均", y=1.0)
    save(fig, figures, "fig07_kernel_heatmap.png")


def plot_variogram(summary: pd.DataFrame, figures: Path) -> None:
    """Kriging・Universal Kriging のバリオグラム別（説明変数は X, Y）。GPR の最良を参考に重ねる。"""
    krig = summary[summary["family"].isin(["OK", "UK"]) & (summary["feature_set"] == "XY")]
    colors = {"linear": "#2a78d6", "gaussian": "#eb6834", "power": "#1baf7a", "exponential": "#4a3aa7"}
    best = _best_rows(summary)
    gpr = best[best["family"] == "GPR"].sort_values("n_shots")
    fig, axes = plt.subplots(1, 2, figsize=(11, 3.8), sharey=True, layout="constrained")
    for ax, family in zip(axes, ("OK", "UK")):
        for variogram in VARIOGRAM_ORDER:
            rows = krig[(krig["family"] == family) & (krig["variant"] == variogram)].sort_values("n_shots")
            ax.plot(rows["n_shots"], rows["RMSE_XY_mean"], color=colors[variogram], lw=2, marker="o", ms=4, label=variogram)
        ax.plot(gpr["n_shots"], gpr["RMSE_XY_mean"], color=INK_MUTED, lw=1.5, ls="--", label="参考：GPR の最良")
        ax.set_title(f"{FAMILY_LABELS[family]}（説明変数 X, Y）")
        ax.set_xlabel("計測 Shot 数")
        ax.set_ylim(bottom=0)
    axes[0].set_ylabel("RMSE（X・Y）[nm]")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="outside right center")
    save(fig, figures, "fig08_variogram.png")


# ----------------------------------------------------------------------------
# 7. 4つの指標
# ----------------------------------------------------------------------------
def plot_metrics(summary: pd.DataFrame, figures: Path) -> None:
    best = _best_rows(summary)
    fig, axes = plt.subplots(1, 4, figsize=(15, 3.6), layout="constrained")
    for ax, (metric, label) in zip(axes, (("R2_XY_mean", "決定係数 R²"), ("adjR2_XY_mean", "自由度調整済み決定係数"), ("RMSE_XY_mean", "RMSE [nm]"), ("MAE_XY_mean", "MAE [nm]"))):
        for family in FAMILY_ORDER:
            rows = best[best["family"] == family].sort_values("n_shots")
            ax.plot(rows["n_shots"], rows[metric], color=FAMILY_COLORS[family], lw=2, marker="o", ms=3.5, label=FAMILY_LABELS[family])
        ax.set_title(label)
        ax.set_xlabel("計測 Shot 数")
        if metric.startswith(("RMSE", "MAE")):
            ax.set_ylim(bottom=0)
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="outside right center", fontsize=8)
    save(fig, figures, "fig09_metrics.png")


# ----------------------------------------------------------------------------
# 8. 外周と内側、計算時間、ARD の変数の使われ方、分布
# ----------------------------------------------------------------------------
def plot_edge(summary: pd.DataFrame, figures: Path) -> None:
    best = _best_rows(summary)
    levels = [n for n in FOCUS_LEVELS if n in best["n_shots"].unique()]
    fig, axes = plt.subplots(1, len(levels), figsize=(4.4 * len(levels), 3.6), sharey=True)
    for ax, n_shots in zip(np.atleast_1d(axes), levels):
        level = best[best["n_shots"] == n_shots].set_index("family").reindex(FAMILY_ORDER).dropna(subset=["method"])
        positions = np.arange(len(level))
        ax.bar(positions - 0.2, level["RMSE_XY_inner_mean"], width=0.38, color=[FAMILY_COLORS[f] for f in level.index], alpha=0.45, label="内側（半径 < 120 mm）")
        ax.bar(positions + 0.2, level["RMSE_XY_outer_mean"], width=0.38, color=[FAMILY_COLORS[f] for f in level.index], label="外周（半径 ≥ 120 mm）")
        ax.set_xticks(positions, [FAMILY_LABELS[f].replace("Universal ", "U.") for f in level.index], rotation=35, ha="right", fontsize=7.5)
        ax.set_title(f"{n_shots} Shot")
    np.atleast_1d(axes)[0].set_ylabel("RMSE（X・Y）[nm]")
    np.atleast_1d(axes)[0].legend(fontsize=7.5)
    save(fig, figures, "fig10_edge_inner.png")


def plot_maps(results: Path, summary: pd.DataFrame, figures: Path) -> None:
    samples = np.load(results / "samples" / "sample_predictions.npz")
    marks = pd.read_csv(results / "tables" / "layout_marks.csv")
    plans = pd.read_csv(results / "tables" / "sampling_plans.csv").set_index("n_shots")
    best = _best_rows(summary)
    families = ["GPR", "GAM", "TPS", "XY"]
    levels = [n for n in (10, 40) if n in plans.index]
    truth = samples["w0__trend"] + samples["w0__mark_offset"] + samples["w0__scan_offset"]
    fig, axes = plt.subplots(len(levels), len(families) + 1, figsize=(3.0 * (len(families) + 1), 3.0 * len(levels)))
    limit_truth = float(np.max(np.abs(truth[:, 0])))
    for row, n_shots in enumerate(levels):
        chosen = {int(v) for v in plans.loc[n_shots, "shotNo"].split()}
        train = marks["shotNo"].isin(chosen).to_numpy()
        ax = axes[row, 0]
        ax.scatter(marks["x_mm"], marks["y_mm"], c=truth[:, 0], cmap=DIVERGING, vmin=-limit_truth, vmax=limit_truth, s=6, lw=0)
        ax.scatter(marks["x_mm"][train], marks["y_mm"][train], facecolors="none", edgecolors=INK, s=10, lw=0.5)
        ax.set_title(f"真値 X（○計測 {n_shots} Shot）", fontsize=9)
        for col, family in enumerate(families, start=1):
            method = best[best["family"] == family]["method"].iloc[0]
            key = f"w0__est__{n_shots}__{method}"
            ax = axes[row, col]
            if key not in samples:
                ax.axis("off")
                continue
            error = np.full(len(marks), np.nan)
            error[~train] = samples[key][:, 0] - truth[~train, 0]
            ax.scatter(marks["x_mm"][~train], marks["y_mm"][~train], c=error[~train], cmap=DIVERGING, vmin=-6, vmax=6, s=6, lw=0)
            ax.scatter(marks["x_mm"][train], marks["y_mm"][train], color=AXIS, s=4, lw=0)
            rmse = float(np.sqrt(np.nanmean(error**2)))
            ax.set_title(f"{FAMILY_LABELS[family]} 誤差 X（RMSE {rmse:.2f}）", fontsize=9)
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
    save(fig, figures, "fig11_error_maps.png")


def plot_timing(summary: pd.DataFrame, figures: Path) -> None:
    rows = summary.copy()
    rows["group"] = rows["family"]
    rows.loc[rows["family"] == "GPR", "group"] = "GPR_" + rows.loc[rows["family"] == "GPR", "factor_mode"]
    order = ["GPR_none", "GPR_basis", "GPR_backfit", "TPS", "OK", "UK", "GAM", "XY", "RT"]
    labels = {"GPR_none": "GPR（質的変数なし）", "GPR_basis": "GPR（同時推定）", "GPR_backfit": "GPR（Backfitting）"}
    fig, ax = plt.subplots(figsize=(8, 3.6))
    for n_shots, marker in ((10, "o"), (40, "s")):
        level = rows[rows["n_shots"] == n_shots].groupby("group")["seconds_mean"].mean().reindex(order)
        colors = [FAMILY_COLORS[g.split("_")[0]] for g in order]
        ax.scatter(range(len(order)), level.values * 1000, color=colors, marker=marker, s=40, zorder=3, label=f"{n_shots} Shot")
    ax.set_yscale("log")
    ax.set_xticks(range(len(order)), [labels.get(g, FAMILY_LABELS.get(g, g)) for g in order], rotation=30, ha="right", fontsize=8)
    ax.set_ylabel("1枚あたりの計算時間 [ms]（X・Y の合計）")
    ax.legend()
    save(fig, figures, "fig12_timing.png")


def plot_ard_usage(usage: pd.DataFrame, figures: Path) -> None:
    fig, ax = plt.subplots(figsize=(6.5, 3.4))
    for (feature_set, variable), color, style in (
        (("XYR", "r"), FEATURE_COLORS["XYR"], "-"),
        (("XYRT", "r"), FEATURE_COLORS["XYRT"], "-"),
        (("XYRT", "T"), FEATURE_COLORS["XYRT"], "--"),
    ):
        rows = usage[(usage["feature_set"] == feature_set) & (usage["variable"] == variable)].sort_values("n_shots")
        label = f"{FEATURE_LABELS[feature_set]} の {'半径' if variable == 'r' else 'T'}"
        ax.plot(rows["n_shots"], 100 * rows["at_upper_bound_rate"], color=color, ls=style, lw=2, marker="o", ms=4, label=label)
    ax.set_xlabel("計測 Shot 数")
    ax.set_ylabel("使われなかった割合 [%]")
    ax.set_title("ARD カーネルで長さスケールが上限（=その変数を無視）になった割合")
    ax.set_ylim(0, 100)
    ax.legend()
    save(fig, figures, "fig13_ard_usage.png")


def plot_distribution(frame: pd.DataFrame, summary: pd.DataFrame, figures: Path) -> None:
    best = _best_rows(summary)
    levels = [n for n in FOCUS_LEVELS if n in best["n_shots"].unique()]
    fig, axes = plt.subplots(1, len(levels), figsize=(4.4 * len(levels), 3.6), sharey=True)
    for ax, n_shots in zip(np.atleast_1d(axes), levels):
        data, colors, names = [], [], []
        for family in FAMILY_ORDER:
            method = best[best["family"] == family]["method"]
            if method.empty:
                continue
            values = frame[(frame["n_shots"] == n_shots) & (frame["method"] == method.iloc[0])]["RMSE_XY"].dropna()
            data.append(values)
            colors.append(FAMILY_COLORS[family])
            names.append(FAMILY_LABELS[family].replace("Universal ", "U."))
        parts = ax.boxplot(data, patch_artist=True, showfliers=False, widths=0.6, medianprops={"color": INK, "lw": 1.2})
        for patch, color in zip(parts["boxes"], colors):
            patch.set_facecolor(color)
            patch.set_alpha(0.75)
            patch.set_edgecolor(color)
        ax.set_xticks(range(1, len(names) + 1), names, rotation=35, ha="right", fontsize=7.5)
        ax.set_title(f"{n_shots} Shot")
    np.atleast_1d(axes)[0].set_ylabel("Wafer ごとの RMSE（X・Y）[nm]")
    save(fig, figures, "fig14_distribution.png")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="結果の図を作る")
    parser.add_argument("--results", default="results")
    args = parser.parse_args(argv)
    results = Path(args.results)
    tables = results / "tables"
    figures = results / "figures"
    figures.mkdir(parents=True, exist_ok=True)
    setup_style()
    with open(results / "config_used.json", encoding="utf-8") as handle:
        config = json.load(handle)
    frame = pd.read_csv(tables / "per_wafer_metrics.csv.gz")
    summary = pd.read_csv(tables / "summary_by_method.csv")
    plot_layout(tables, figures)
    plot_components(results, figures, config)
    plot_rmse_vs_shots(summary, figures)
    plot_family_feature_heatmap(summary, figures)
    plot_feature_effect(pd.read_csv(tables / "feature_effect_family.csv"), figures)
    plot_factor_effect(frame, summary, figures)
    plot_kernel_heatmap(summary, figures)
    plot_variogram(summary, figures)
    plot_metrics(summary, figures)
    plot_edge(summary, figures)
    plot_maps(results, summary, figures)
    plot_timing(summary, figures)
    plot_ard_usage(pd.read_csv(tables / "gpr_ard_usage.csv"), figures)
    plot_distribution(frame, summary, figures)


if __name__ == "__main__":
    main()
