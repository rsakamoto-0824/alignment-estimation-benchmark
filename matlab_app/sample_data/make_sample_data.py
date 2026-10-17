"""アプリの動作確認用のサンプルデータ（模擬データ、アライメント計測テーブルの標準の項目）を CSV に書き出す。

前回の評価（src/）と同じ模擬データの作り方で Wafer 5枚・全 Shot（99 Shot × 4 Mark）を作り、
実データで起こることを少しだけ入れる：
- 未測定（StsX = -1 または StsY = -1）の点を Wafer ごとに数点
- 同じ点を2回計測した重複行（Wafer・DateTime・座標が同じ行）を Wafer ごとに数行
値は乱数で作ったもので、実データ・社内データは使っていない。

使い方（リポジトリの直下で）
    .venv/bin/python matlab_app/sample_data/make_sample_data.py
Excel 版（sample_alignment.xlsx）は MATLAB で writetable して作る（README を参照）。
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from src.geometry import build_layout  # noqa: E402
from src.simulation import load_config  # noqa: E402
from src.wafer_generator import GenerationSettings, WaferGenerator  # noqa: E402

OUTPUT = Path(__file__).resolve().parent / "sample_alignment.csv"
N_WAFERS = 5
FIRST_WAFER_ID = 100  # 本計算（0〜999）と同じ乱数の Wafer を使う
N_UNMEASURED_PER_WAFER = 4
N_DUPLICATES_PER_WAFER = 3
DUPLICATE_NOISE_NM = 0.3
SEED = 20261017


def main() -> None:
    config = load_config(ROOT / "config" / "default.json")
    layout = build_layout(config)
    generator = WaferGenerator(layout, GenerationSettings.from_config(config), int(config["random"]["master_seed"]))
    rng = np.random.default_rng(SEED)
    marks = layout.marks
    frames = []
    for k in range(N_WAFERS):
        sample = generator.generate(FIRST_WAFER_ID + k)
        frame = pd.DataFrame({
            "Wafer": f"SIM{k + 1:02d}",
            "DateTime": f"2026/10/17 {9 + k:02d}:00:00",
            "shotNo": marks["shotNo"].to_numpy(),
            "Direction": marks["Direction"].to_numpy(),
            "Xmm": marks["Xmm"].to_numpy(),
            "Ymm": marks["Ymm"].to_numpy(),
            "Radius": marks["Radius"].to_numpy(),
            "markNo": marks["markNo"].to_numpy(),
            "markXmm": marks["markXmm"].to_numpy(),
            "markYmm": marks["markYmm"].to_numpy(),
            "measX": np.round(sample.measured[:, 0], 3),
            "measY": np.round(sample.measured[:, 1], 3),
            "StsX": 0,
            "StsY": 0,
        })
        unmeasured = rng.choice(len(frame), size=N_UNMEASURED_PER_WAFER, replace=False)
        for row, axis in zip(unmeasured, rng.integers(0, 2, size=N_UNMEASURED_PER_WAFER)):
            frame.loc[row, "StsX" if axis == 0 else "StsY"] = -1
        duplicates = frame.iloc[rng.choice(len(frame), size=N_DUPLICATES_PER_WAFER, replace=False)].copy()
        duplicates["measX"] = np.round(duplicates["measX"] + rng.normal(0, DUPLICATE_NOISE_NM, len(duplicates)), 3)
        duplicates["measY"] = np.round(duplicates["measY"] + rng.normal(0, DUPLICATE_NOISE_NM, len(duplicates)), 3)
        frames.append(pd.concat([frame, duplicates], ignore_index=True))
    table = pd.concat(frames, ignore_index=True)
    table.to_csv(OUTPUT, index=False, encoding="utf-8")
    print(f"{OUTPUT} を書き出しました（{len(table)} 行）")


if __name__ == "__main__":
    main()
