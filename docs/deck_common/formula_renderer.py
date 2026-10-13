"""スライドに載せる数式を PNG 画像にする共通部品（matplotlib の mathtext を使用）。

画像は「指定したポイント数の文字サイズ」で描き、出力先の formulas.json にインチ単位の幅・高さを書き出す。
スライド側はその寸法のまま配置する（deck_kit.js の addFormula）。
"""
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from PIL import Image  # noqa: E402

DPI = 300
PAD_INCH = 0.04
INK_COLOR = "#1E1C33"
WHITE_COLOR = "#FFFFFF"

plt.rcParams["mathtext.fontset"] = "stix"
plt.rcParams["font.family"] = "STIXGeneral"


def render(output_dir: Path, key: str, tex: str, size_pt: float, color: str) -> dict:
    fig = plt.figure(figsize=(0.01, 0.01))
    fig.text(0, 0, tex, fontsize=size_pt, color=color)
    path = output_dir / f"{key}.png"
    fig.savefig(path, dpi=DPI, transparent=True, bbox_inches="tight", pad_inches=PAD_INCH)
    plt.close(fig)
    with Image.open(path) as image:
        width_px, height_px = image.size
    return {"file": path.name, "w": width_px / DPI, "h": height_px / DPI}


def render_all(formulas: dict[str, tuple[str, float]], output_dir: Path, white_keys: set[str] = frozenset()) -> None:
    """formulas = {key: (数式, 文字サイズpt)} をすべて描いて formulas.json に寸法を書き出す。"""
    output_dir.mkdir(exist_ok=True)
    sizes = {}
    for key, (tex, size_pt) in formulas.items():
        sizes[key] = render(output_dir, key, tex, size_pt, WHITE_COLOR if key in white_keys else INK_COLOR)
    (output_dir / "formulas.json").write_text(json.dumps(sizes, indent=2), encoding="utf-8")
    for key, info in sizes.items():
        print(f"{key:14s} {info['w']:.2f} x {info['h']:.2f} in")
