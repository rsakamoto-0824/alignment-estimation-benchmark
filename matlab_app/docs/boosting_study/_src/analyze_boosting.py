"""ブースティングの検証結果（run_boosting_study.m の CSV）を集計し、図と要約（JSON）を作る。

使い方（リポジトリの直下で）
    .venv/bin/python matlab_app/docs/boosting_study/_src/analyze_boosting.py <結果の CSV>
出力：matlab_app/docs/boosting_study/images/*.png（図）、_src/summary.json（報告書に使う数値）。
相対変化 = (変種の RMSE − ブースティングなしの RMSE) / ブースティングなしの RMSE × 100 [%]（負なら改善）。
Wafer ごとに求めて平均し、95% 区間は Wafer 間の t 分布（自由度 = Wafer 数 − 1）で求める。
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
from scipy import stats  # noqa: E402

HERE = Path(__file__).resolve().parent
IMAGES = HERE.parent / "images"
FONT = "Hiragino Sans"
METHODS = ["GPR_none", "GPR_additive", "GAM"]
METHOD_LABELS = {"GPR_none": "GPR（質的変数なし）", "GPR_additive": "GPR（加法カーネル）", "GAM": "GAM（スプライン）"}
NOISE_LABELS = {"standard": "ノイズ標準", "high": "ノイズ2倍"}
SAMPLING_LABELS = {"ioptimal": "I 最適", "random": "ランダム"}
SHOT_COUNTS = [10, 20, 30, 40]
SHOT_COLORS = {10: "#9ecae1", 20: "#4292c6", 30: "#2171b5", 40: "#08306b"}
METHOD_COLORS = {"GPR_none": "#8c8c8c", "GPR_additive": "#1f5fa8", "GAM": "#d4730b"}
DPI = 150
KEY = ["noise", "sampling", "nShots", "wafer", "method"]


def load(path: Path) -> pd.DataFrame:
    rows = pd.read_csv(path)
    base = rows[rows.variant == "base"][KEY + ["rmseTruth", "rmseMeasured", "rmseTrain"]]
    base = base.rename(columns={"rmseTruth": "baseTruth", "rmseMeasured": "baseMeasured", "rmseTrain": "baseTrain"})
    rows = rows.merge(base, on=KEY, how="left")
    rows["relTruth"] = 100 * (rows.rmseTruth - rows.baseTruth) / rows.baseTruth
    rows["relMeasured"] = 100 * (rows.rmseMeasured - rows.baseMeasured) / rows.baseMeasured
    rows["config"] = rows.variant + np.where(rows.variant == "L2fixed", " ν=" + rows.nu.astype(str), "") + \
        " m=" + rows["round"].astype(int).astype(str)
    return rows


def interval(values: np.ndarray) -> tuple[float, float, float]:
    """平均と 95% 区間（t 分布）"""
    values = values[np.isfinite(values)]
    mean = float(np.mean(values))
    if len(values) < 2:
        return mean, float("nan"), float("nan")
    half = float(stats.t.ppf(0.975, len(values) - 1) * np.std(values, ddof=1) / np.sqrt(len(values)))
    return mean, mean - half, mean + half


def summarize(rows: pd.DataFrame) -> dict:
    summary: dict = {"nWafers": int(rows.wafer.nunique()), "nRows": int(len(rows)),
                     "maxCheckDiff": float(rows.checkDiff.max(skipna=True)),
                     "secondsTotal": float(rows.seconds.sum())}
    refit = rows[rows.variant == "L2refit"]
    summary["refit"] = {"maxAbsRel": float(refit.relTruth.abs().max()),
                        "meanAbsRel": float(refit.relTruth.abs().mean())}
    patterns = []
    for (noise, sampling, n_shots, method), group in rows.groupby(["noise", "sampling", "nShots", "method"]):
        base = group[group.variant == "base"]
        entry = {"noise": noise, "sampling": sampling, "nShots": int(n_shots), "method": method,
                 "baseTruth": float(base.rmseTruth.mean()), "baseMeasured": float(base.rmseMeasured.mean()),
                 "baseTrain": float(base.rmseTrain.mean())}
        fixed = group[group.variant == "L2fixed"]
        by_config = fixed.groupby(["nu", "round"]).relTruth.mean()
        best_nu, best_round = by_config.idxmin()
        best = fixed[(fixed.nu == best_nu) & (fixed["round"] == best_round)]
        mean, low, high = interval(best.relTruth.to_numpy())
        entry["fixedBest"] = {"nu": float(best_nu), "round": int(best_round), "rel": mean, "low": low, "high": high,
                              "win": float((best.relTruth < 0).mean()),
                              "relMeasured": float(best.relMeasured.mean())}
        for nu in sorted(fixed.nu.unique()):
            curve = [0.0] + [float(fixed[(fixed.nu == nu) & (fixed["round"] == m)].relTruth.mean())
                             for m in sorted(fixed["round"].unique())]
            entry[f"curve_nu{nu:g}"] = curve
        # Wafer ごとに最も良い回数を後から選べたとき（真値を知っている場合）の上限
        per_wafer = group[group.variant.isin(["base", "L2fixed"])].groupby("wafer").rmseTruth.min()
        entry["oracleRel"] = float(np.mean(100 * (per_wafer.values - base.set_index("wafer").rmseTruth[per_wafer.index].values)
                                           / base.set_index("wafer").rmseTruth[per_wafer.index].values))
        stack = group[group.variant.str.startswith("stack")]
        mean, low, high = interval(stack.relTruth.to_numpy())
        entry["stack"] = {"partner": stack.variant.iloc[0].split(":")[1], "rel": mean, "low": low, "high": high,
                          "win": float((stack.relTruth < 0).mean()), "relMeasured": float(stack.relMeasured.mean())}
        patterns.append(entry)
    summary["patterns"] = patterns
    # 既存の手法の中で最も良いもの（パターンごと、Wafer の平均）と、ブースティングを含めて最も良いものの比較
    best_rows = []
    for (noise, sampling, n_shots), group in rows.groupby(["noise", "sampling", "nShots"]):
        means = group.groupby(["method", "config"]).rmseTruth.mean()
        base_means = means[[(m, c) for m, c in means.index if c.startswith("base")]]
        boosted = means[[(m, c) for m, c in means.index if not c.startswith("base") and not c.startswith("L2refit")]]
        best_base = base_means.idxmin()
        best_boost = boosted.idxmin()
        best_rows.append({"noise": noise, "sampling": sampling, "nShots": int(n_shots),
                          "bestBase": best_base[0], "bestBaseRmse": float(base_means.min()),
                          "bestBoost": f"{best_boost[0]} {best_boost[1]}", "bestBoostMethod": best_boost[0],
                          "bestBoostConfig": best_boost[1], "bestBoostRmse": float(boosted.min()),
                          "gain": float(100 * (boosted.min() - base_means.min()) / base_means.min())})
    summary["bestComparison"] = best_rows
    # GAM をブースティング・重ねで強めた最良（後から選んだ値）と、ブースティングなしの GPR（加法カーネル）の差
    gam_rows = []
    for (noise, sampling, n_shots), group in rows.groupby(["noise", "sampling", "nShots"]):
        gam = group[(group.method == "GAM") & (group.variant != "L2refit")].groupby("config").rmseTruth.mean()
        additive = group[(group.method == "GPR_additive") & (group.variant == "base")].rmseTruth.mean()
        gam_rows.append({"noise": noise, "sampling": sampling, "nShots": int(n_shots), "gamBest": float(gam.min()),
                         "gamBestConfig": gam.idxmin(), "gprAdditive": float(additive),
                         "gap": float(100 * (gam.min() - additive) / additive)})
    summary["gamVsGprAdditive"] = gam_rows
    summary["medianSeconds"] = {f"{m}|{v}": float(t) for (m, v), t in
                                rows.groupby(["method", "variant"]).seconds.median().items()}
    # 回数・縮小率を手法ごとに1つに決めたとき（全パターンで平均が最も良い組）
    rules = {}
    fixed = rows[rows.variant == "L2fixed"]
    for method, group in fixed.groupby("method"):
        overall = group.groupby(["nu", "round"]).relTruth.mean()
        nu, round_ = overall.idxmin()
        chosen = group[(group.nu == nu) & (group["round"] == round_)]
        by_pattern = chosen.groupby(["noise", "sampling", "nShots"]).relTruth.mean()
        rules[method] = {"nu": float(nu), "round": int(round_), "overallRel": float(overall.min()),
                         "worstPatternRel": float(by_pattern.max()), "bestPatternRel": float(by_pattern.min()),
                         "nPatternsWorse": int((by_pattern > 0).sum()), "nPatterns": int(len(by_pattern))}
    summary["fixedRule"] = rules
    # 計測値で評価した相対変化と、真値で評価した相対変化の一致（アプリは計測値で評価する）
    boosted = rows[rows.variant != "base"]
    summary["measuredVsTruthCorr"] = float(np.corrcoef(boosted.relTruth, boosted.relMeasured)[0, 1])
    summary["signAgreement"] = float((np.sign(boosted.relTruth) == np.sign(boosted.relMeasured)).mean())
    return summary


def style() -> None:
    plt.rcParams.update({"font.family": FONT, "font.size": 9, "axes.grid": True, "grid.color": "#dddddd",
                         "axes.spines.top": False, "axes.spines.right": False})


def figure_curves(summary: dict, sampling: str, path: Path) -> None:
    """L2fixed の回数ごとの相対変化（手法 × 縮小率、線は学習 Shot 数、実線 = ノイズ標準、破線 = ノイズ2倍）"""
    patterns = [p for p in summary["patterns"] if p["sampling"] == sampling]
    fig, axes = plt.subplots(2, 3, figsize=(10, 5.6), sharex=True)
    for row, nu in enumerate([0.5, 1.0]):
        for col, method in enumerate(METHODS):
            ax = axes[row, col]
            for p in patterns:
                if p["method"] != method:
                    continue
                curve = p[f"curve_nu{nu:g}"]
                ax.plot(range(len(curve)), curve, marker="o", markersize=3, color=SHOT_COLORS[p["nShots"]],
                        linestyle="-" if p["noise"] == "standard" else "--",
                        label=f"{p['nShots']} Shot・{NOISE_LABELS[p['noise']]}")
            ax.axhline(0, color="#444444", linewidth=0.8)
            ax.set_title(f"{METHOD_LABELS[method]}（ν = {nu:g}）", fontsize=9)
            if col == 0:
                ax.set_ylabel("真値に対する RMSE の変化 [%]")
            if row == 1:
                ax.set_xlabel("ブースティングの回数 m（0 = なし）")
    handles, labels = axes[0, 0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", ncol=4, fontsize=8, frameon=False)
    fig.suptitle(f"ハイパーパラメータ固定の L2 ブースティング：回数による変化（{SAMPLING_LABELS[sampling]}、Wafer の平均）",
                 fontsize=10)
    fig.tight_layout(rect=(0, 0.08, 1, 0.96))
    fig.savefig(path, dpi=DPI)
    plt.close(fig)


def figure_tradeoff(rows: pd.DataFrame, path: Path) -> None:
    """学習点の残差（当てはめの良さ）と評価点の誤差の関係：回数を増やすと学習点には合うが評価点は良くならない"""
    fig, axes = plt.subplots(1, 3, figsize=(10, 3.4))
    pick = rows[(rows.noise == "standard") & (rows.sampling == "ioptimal") & (rows.variant.isin(["base", "L2fixed"]))
                & ((rows.variant == "base") | (rows.nu == 1.0))]
    for ax, method in zip(axes, METHODS):
        for n_shots in SHOT_COUNTS:
            group = pick[(pick.method == method) & (pick.nShots == n_shots)]
            if group.empty:
                continue
            curve = group.groupby("round")[["rmseTrain", "rmseTruth"]].mean()
            ax.plot(curve.rmseTrain, curve.rmseTruth, marker="o", markersize=3, color=SHOT_COLORS[n_shots],
                    label=f"{n_shots} Shot")
            ax.annotate("m=0", (curve.rmseTrain.iloc[0], curve.rmseTruth.iloc[0]), fontsize=7, color="#555555",
                        xytext=(3, 3), textcoords="offset points")
        ax.set_title(METHOD_LABELS[method], fontsize=9)
        ax.set_xlabel("学習点の残差の RMSE [nm]")
    axes[0].set_ylabel("評価点の真値に対する RMSE [nm]")
    axes[0].legend(fontsize=8, frameon=False)
    fig.suptitle("回数 m を増やしたときの、学習点の残差と評価点の誤差（ν = 1、ノイズ標準、I 最適、Wafer の平均）", fontsize=10)
    fig.tight_layout(rect=(0, 0, 1, 0.93))
    fig.savefig(path, dpi=DPI)
    plt.close(fig)


def figure_best(summary: dict, path: Path) -> None:
    """パターンごとの、既存の手法で最も良い RMSE と、ブースティングを含めて最も良い RMSE"""
    best = pd.DataFrame(summary["bestComparison"])
    fig, axes = plt.subplots(1, 4, figsize=(10, 3.2), sharey=True)
    best["order"] = best.noise.map({"standard": 0, "high": 1}) * 2 + best.sampling.map({"ioptimal": 0, "random": 1})
    best = best.sort_values(["order", "nShots"])
    for ax, ((noise, sampling), group) in zip(axes, best.groupby(["noise", "sampling"], sort=False)):
        group = group.sort_values("nShots")
        x = np.arange(len(group))
        ax.bar(x - 0.18, group.bestBaseRmse, 0.36, color="#9aa7b8", label="既存の手法で最良")
        ax.bar(x + 0.18, group.bestBoostRmse, 0.36, color="#1f5fa8", label="ブースティングを含めて最良")
        ax.set_xticks(x, [f"{n}" for n in group.nShots])
        ax.set_xlabel("学習 Shot 数")
        ax.set_title(f"{NOISE_LABELS[noise]}・{SAMPLING_LABELS[sampling]}", fontsize=9)
    axes[0].set_ylabel("真値に対する RMSE [nm]")
    axes[0].legend(fontsize=7.5, frameon=False, loc="upper right")
    fig.suptitle("既存の手法の中から選ぶ場合と、ブースティングを加えた場合（Wafer の平均。どちらも最良のものを後から選んだ値）",
                 fontsize=10)
    fig.tight_layout(rect=(0, 0, 1, 0.9))
    fig.savefig(path, dpi=DPI)
    plt.close(fig)


def figure_stack(summary: dict, path: Path) -> None:
    """残差に別の手法を重ねたときの相対変化（手法ごと、学習 Shot 数、ノイズ標準・I 最適とランダム）"""
    patterns = pd.DataFrame([{**{k: p[k] for k in ("noise", "sampling", "nShots", "method")},
                              "rel": p["stack"]["rel"], "low": p["stack"]["low"], "high": p["stack"]["high"]}
                             for p in summary["patterns"]])
    fig, axes = plt.subplots(1, 2, figsize=(10, 3.2), sharey=True)
    for ax, noise in zip(axes, ["standard", "high"]):
        group = patterns[(patterns.noise == noise) & (patterns.sampling == "ioptimal")]
        shots = sorted(group.nShots.unique())
        x = np.arange(len(shots))
        for k, method in enumerate(METHODS):
            part = group[group.method == method].set_index("nShots").loc[shots]
            ax.bar(x + (k - 1) * 0.26, part.rel, 0.26, color=METHOD_COLORS[method],
                   yerr=[part.rel - part.low, part.high - part.rel], capsize=2, error_kw={"linewidth": 0.7},
                   label=METHOD_LABELS[method] + {"GPR_none": " ＋ GAM", "GPR_additive": " ＋ GAM",
                                                  "GAM": " ＋ GPR"}[method])
        ax.axhline(0, color="#444444", linewidth=0.8)
        ax.set_xticks(x, [str(n) for n in shots])
        ax.set_xlabel("学習 Shot 数")
        ax.set_title(f"{NOISE_LABELS[noise]}・I 最適", fontsize=9)
    axes[0].set_ylabel("真値に対する RMSE の変化 [%]")
    axes[0].legend(fontsize=7.5, frameon=False)
    fig.suptitle("残差に別の手法を1回重ねたときの変化（Wafer の平均と 95% 区間）", fontsize=10)
    fig.tight_layout(rect=(0, 0, 1, 0.9))
    fig.savefig(path, dpi=DPI)
    plt.close(fig)


def main() -> None:
    rows = load(Path(sys.argv[1]))
    summary = summarize(rows)
    IMAGES.mkdir(exist_ok=True)
    style()
    figure_curves(summary, "ioptimal", IMAGES / "fig1_rounds_ioptimal.png")
    figure_curves(summary, "random", IMAGES / "fig2_rounds_random.png")
    figure_tradeoff(rows, IMAGES / "fig3_tradeoff.png")
    figure_stack(summary, IMAGES / "fig4_stack.png")
    figure_best(summary, IMAGES / "fig5_best.png")
    (HERE / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"集計しました：{len(rows)} 行、Wafer {summary['nWafers']} 枚")


if __name__ == "__main__":
    main()
