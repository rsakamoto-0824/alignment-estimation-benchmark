"""ブースティングの検証に使う模擬データ（真値つき）を CSV に書き出す。

前回の評価（src/）と同じ模擬データの作り方で、Wafer を N_WAFERS 枚作る（全 Shot・全 Mark、未測定・重複なし）。
計測ノイズの大きさを変えた2通りを書き出す：
- standard：設定どおり（一様ノイズ、幅は中心 ±1 nm → 最外周 ±3 nm）
- high    ：ノイズを2倍（中心 ±2 nm → 最外周 ±6 nm）
列はアプリの標準の項目（Wafer・shotNo・Direction・Xmm・Ymm・markNo・markXmm・markYmm・measX・measY）と、
真値 truthX・truthY（ノイズを足す前の値。アプリでは「その他の列」として読み込まれる）。
値は乱数で作ったもので、実データ・社内データは使っていない。

使い方（リポジトリの直下で）
    .venv/bin/python matlab_app/docs/boosting_study/_src/make_boosting_data.py <出力フォルダ>
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))

from src.geometry import build_layout  # noqa: E402
from src.simulation import load_config  # noqa: E402
from src.wafer_generator import GenerationSettings, WaferGenerator  # noqa: E402

N_WAFERS = 16
FIRST_WAFER_ID = 300          # 本計算（0〜999）・動作確認の見本（100〜104）と別の Wafer
NOISE_SCALES = {"standard": 1.0, "high": 2.0}


def main() -> None:
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    output.mkdir(parents=True, exist_ok=True)
    config = load_config(ROOT / "config" / "default.json")
    layout = build_layout(config)
    generator = WaferGenerator(layout, GenerationSettings.from_config(config), int(config["random"]["master_seed"]))
    marks = layout.marks
    samples = [generator.generate(FIRST_WAFER_ID + k) for k in range(N_WAFERS)]
    for name, scale in NOISE_SCALES.items():
        frames = []
        for k, sample in enumerate(samples):
            measured = sample.truth + scale * sample.noise
            frames.append(pd.DataFrame({
                "Wafer": f"BST{k + 1:02d}",
                "shotNo": marks["shotNo"].to_numpy(),
                "Direction": marks["Direction"].to_numpy(),
                "Xmm": marks["Xmm"].to_numpy(),
                "Ymm": marks["Ymm"].to_numpy(),
                "markNo": marks["markNo"].to_numpy(),
                "markXmm": marks["markXmm"].to_numpy(),
                "markYmm": marks["markYmm"].to_numpy(),
                "measX": np.round(measured[:, 0], 4),
                "measY": np.round(measured[:, 1], 4),
                "truthX": np.round(sample.truth[:, 0], 4),
                "truthY": np.round(sample.truth[:, 1], 4),
            }))
        path = output / f"boosting_{name}.csv"
        pd.concat(frames, ignore_index=True).to_csv(path, index=False, encoding="utf-8")
        print(f"{path}（Wafer {N_WAFERS} 枚、ノイズ ×{scale:g}）")


if __name__ == "__main__":
    main()
