"""追加検証の資料に載せる数式を PNG 画像にする（描き方は ../deck_common/formula_renderer.py）。

使い方: ../../.venv/bin/python render_formulas.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "deck_common"))
from formula_renderer import render_all  # noqa: E402

OUTPUT_DIR = Path(__file__).with_name("formulas")

# key: (数式, 文字サイズpt)
FORMULAS = {
    "basis_model": (r"$y = \beta_0 + F\gamma + g(\mathbf{z}) + \varepsilon,\qquad g \sim \mathcal{GP}(0,\ k_{\mathrm{space}})$", 19),
    "additive_kernel": (r"$k(i, j) = k_{\mathrm{space}}(\mathbf{z}_i, \mathbf{z}_j) + \tau_s^2\,[s_i = s_j] + \tau_m^2\,[m_i = m_j]$", 19),
    "interaction_term": (r"$+\ \tau_{sm}^2\,[s_i = s_j\ \mathrm{and}\ m_i = m_j]$", 17),
    "relation": (r"$\gamma \sim N(0,\ \tau^2 I)\ \Rightarrow\ \mathrm{Cov}(F\gamma) = \tau^2 F F^{\top},\qquad \tau \rightarrow \infty\ \Rightarrow\ \mathrm{basis}$", 17),
    "shrinkage": (r"$\hat{\gamma}_k \approx \frac{n_k \tau^2}{n_k \tau^2 + \sigma^2}\ \bar{r}_k$", 21),
    "mixed_model": (r"$y = \beta_0 + \gamma_s s + g(\mathbf{z}) + \varepsilon,\qquad k = k_{\mathrm{space}} + \tau_m^2\,[m_i = m_j]$", 19),
}
WHITE_KEYS: set[str] = set()


if __name__ == "__main__":
    render_all(FORMULAS, OUTPUT_DIR, WHITE_KEYS)
