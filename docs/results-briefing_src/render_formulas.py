"""スライドに載せる数式を PNG 画像にする（matplotlib の mathtext を使用）。

画像は「指定したポイント数の文字サイズ」で描き、formulas/formulas.json にインチ単位の幅・高さを書き出す。
スライド側はその寸法のまま配置する。
使い方: ../../.venv/bin/python render_formulas.py
"""
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from PIL import Image  # noqa: E402

OUTPUT_DIR = Path(__file__).with_name("formulas")
DPI = 300
PAD_INCH = 0.04
INK_COLOR = "#1E1C33"
WHITE_COLOR = "#FFFFFF"

plt.rcParams["mathtext.fontset"] = "stix"
plt.rcParams["font.family"] = "STIXGeneral"

# key: (数式, 文字サイズpt)
FORMULAS = {
    "data_model": (r"$m_i = f(x_i, y_i) + o_{k(i)} + \frac{s(i)}{2}\,\delta + \varepsilon_i$", 22),
    "trend": (r"$f(x, y) = \sum_{j \in S} c_j\, Z_j(\rho, \theta),\quad |S| \in \{10, \ldots, 30\},\quad c_j \sim N(0,\ \sigma_{n_j}^2)$", 18),
    "coef_std": (r"$\sigma_n = 8 \times 0.75^{\,n}\ \mathrm{nm}\quad (n \leq 10)$", 18),
    "noise": (r"$\varepsilon_i \sim U(-a_i,\ a_i),\quad a_i = 1 + 2\,(r_i / r_{\max})^3\ \mathrm{nm}$", 18),
    "i_optimal": (r"$\min_{S}\ \mathrm{tr}\!\left(M_S^{-1}\right),\quad M_S = \sum_{s \in S} B_s^{\top} B_s$", 20),
    "gpr_model": (r"$y = H\beta + g(\mathbf{z}) + \varepsilon,\quad g \sim \mathcal{GP}(0,\ k(\mathbf{z}, \mathbf{z}')),\quad \varepsilon \sim N(0, \sigma_n^2)$", 18),
    "gpr_white": (r"$y = H\beta + g(\mathbf{z}) + \varepsilon$", 22),
    "profile_lik": (r"$\hat{\theta} = \arg\max_{\theta}\ \max_{\beta}\ \log p(y \mid \theta, \beta)$", 18),
    "tps": (r"$\min_f\ \sum_i (y_i - f(\mathbf{z}_i))^2 + n\lambda\, \mathbf{w}^{\top}\Phi\, \mathbf{w},\quad \phi(r) = r^2 \log r$", 18),
    "kriging": (r"$\hat{y}_0 = \sum_i \lambda_i y_i,\quad \sum_i \lambda_i f(\mathbf{z}_i) = f(\mathbf{z}_0)$", 18),
    "gam": (r"$y = \beta_0 + s(x, y) + s(r) + s_{\circ}(T) + \alpha_{\mathrm{scan}} + \gamma_{\mathrm{mark}} + \varepsilon$", 18),
    "rt": (r"$R = \rho\, M(x, y),\quad T = \rho\, \Theta(x, y),\quad M, \Theta = \sum_{n \leq K} c_{nm} Z_n^m$", 18),
    "r2": (r"$R^2 = 1 - \frac{\sum (y - \hat{y})^2}{\sum (y - \bar{y})^2}$", 18),
    "adj_r2": (r"$R^2_{\mathrm{adj}} = 1 - (1 - R^2)\,\frac{n - 1}{n - p - 1},\quad p = \mathrm{tr}(S) - 1$", 18),
    "rmse_mae": (r"$\mathrm{RMSE} = \sqrt{\frac{1}{n}\sum e_i^2},\qquad \mathrm{MAE} = \frac{1}{n}\sum |e_i|$", 18),
    "theta": (r"$T = \theta = \mathrm{atan2}(y, x)\ \rightarrow\ (\cos\theta,\ \sin\theta)$", 18),
    "backfit": (r"$\hat{\gamma} \leftarrow (F^{\top}F)^{-1}F^{\top}(y - \hat{g}),\qquad \hat{g},\ \hat{\theta} \leftarrow \mathrm{GPR}(y - F\hat{\gamma})$", 18),
}
WHITE_KEYS = {"gpr_white"}


def render(key, tex, size_pt, color):
    fig = plt.figure(figsize=(0.01, 0.01))
    fig.text(0, 0, tex, fontsize=size_pt, color=color)
    path = OUTPUT_DIR / f"{key}.png"
    fig.savefig(path, dpi=DPI, transparent=True, bbox_inches="tight", pad_inches=PAD_INCH)
    plt.close(fig)
    with Image.open(path) as image:
        width_px, height_px = image.size
    return {"file": path.name, "w": width_px / DPI, "h": height_px / DPI}


def main():
    OUTPUT_DIR.mkdir(exist_ok=True)
    sizes = {}
    for key, (tex, size_pt) in FORMULAS.items():
        color = WHITE_COLOR if key in WHITE_KEYS else INK_COLOR
        sizes[key] = render(key, tex, size_pt, color)
    (OUTPUT_DIR / "formulas.json").write_text(json.dumps(sizes, indent=2), encoding="utf-8")
    for key, info in sizes.items():
        print(f"{key:14s} {info['w']:.2f} x {info['h']:.2f} in")


if __name__ == "__main__":
    main()
