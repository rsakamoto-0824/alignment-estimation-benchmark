"""ブースティングの検証の報告書（boosting_study.html）を作る。

使い方（リポジトリの直下で。先に analyze_boosting.py で summary.json と図を作る）
    .venv/bin/python matlab_app/docs/boosting_study/_src/build_report.py
本文・表の数値はすべて summary.json から入れる（手で書き写さない）。
"""
from __future__ import annotations

import json
from html import escape
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUTPUT = HERE.parent / "boosting_study.html"
UPDATED = "2026/10/24"
METHOD_LABELS = {"GPR_none": "GPR（質的変数なし）", "GPR_additive": "GPR（加法カーネル）", "GAM": "GAM（スプライン）"}
METHODS = ["GPR_none", "GPR_additive", "GAM"]
NOISE_LABELS = {"standard": "標準", "high": "2倍"}
SAMPLING_LABELS = {"ioptimal": "I 最適", "random": "ランダム"}
NOISES = ["standard", "high"]
SAMPLINGS = ["ioptimal", "random"]
SHOTS = [10, 20, 30, 40]
SECTIONS = [("summary", "結論"), ("purpose", "目的と問い"), ("method", "検証の方法"),
            ("refit", "結果① 当てはめ直すブースティング"), ("fixed", "結果② ハイパーパラメータ固定"),
            ("stack", "結果③ 別の手法を重ねる"), ("versus", "結果④ 今の手法から選ぶ場合"),
            ("measured", "結果⑤ 計測値で評価した場合"), ("discussion", "考察"), ("proposal", "提案"),
            ("reproduce", "再現方法"), ("limits", "注意と限界")]


def pct(value: float, digits: int = 1) -> str:
    return f"{value:+.{digits}f}%".replace("-", "−")


def interval_text(item: dict) -> str:
    return f"{pct(item['rel'])}（{pct(item['low'])}〜{pct(item['high'])}）"


def pattern_name(noise: str, sampling: str, n_shots: int) -> str:
    return f"ノイズ{NOISE_LABELS[noise]}・{SAMPLING_LABELS[sampling]}・{n_shots} Shot"


def ordered(items: list[dict]) -> list[dict]:
    order = {(n, s, k): i for i, (n, s, k) in enumerate((n, s, k) for n in NOISES for s in SAMPLINGS for k in SHOTS)}
    return sorted(items, key=lambda item: order[(item["noise"], item["sampling"], item["nShots"])])


def section(identifier: str, number: int, kicker: str, title: str, body: str) -> str:
    return f"""
    <section id="{identifier}" class="content-section">
      <div class="section-heading">
        <span class="section-number">{number:02d}</span>
        <div>
          <p class="section-kicker">{kicker}</p>
          <h2>{escape(title)}</h2>
        </div>
      </div>
{body}
    </section>"""


def image_size(file: str) -> tuple[int, int]:
    """PNG の幅と高さ（画面の配置が読み込み中にずれないよう、img に大きさを書く）"""
    header = (HERE.parent / "images" / file).read_bytes()[16:24]
    return int.from_bytes(header[:4], "big"), int.from_bytes(header[4:], "big")


def figure(file: str, alt: str, caption: str) -> str:
    width, height = image_size(file)
    return f"""      <figure class="report-figure">
        <img src="images/{file}" alt="{escape(alt)}" width="{width}" height="{height}" loading="lazy">
        <figcaption>{caption}</figcaption>
      </figure>"""


def table(headers: list[str], rows: list[list[str]], caption: str = "") -> str:
    head = "".join(f"<th scope=\"col\">{h}</th>" for h in headers)
    body = "\n".join("            <tr>" + "".join(f"<td>{c}</td>" for c in row) + "</tr>" for row in rows)
    cap = f"<caption>{caption}</caption>" if caption else ""
    return f"""      <div class="table-wrap">
        <table>
          {cap}
          <thead><tr>{head}</tr></thead>
          <tbody>
{body}
          </tbody>
        </table>
      </div>"""


def build(summary: dict) -> str:
    patterns = summary["patterns"]
    find = {(p["noise"], p["sampling"], p["nShots"], p["method"]): p for p in patterns}
    best = ordered(summary["bestComparison"])
    gam_gap = ordered(summary["gamVsGprAdditive"])
    rules = summary["fixedRule"]
    gains = [b["gain"] for b in best]
    gaps = [g["gap"] for g in gam_gap]
    best_count = sum(b["bestBase"] == "GPR_additive" for b in best)
    gam_iopt = [find[(n, "ioptimal", k, "GAM")]["fixedBest"]["rel"] for n in NOISES for k in (20, 30, 40)]
    gam_random_curve = [find[(n, "random", k, "GAM")]["curve_nu1"][-1] for n in NOISES for k in SHOTS]
    stack_gam = [find[(n, s, k, "GAM")]["stack"]["rel"] for n in NOISES for s in SAMPLINGS for k in SHOTS]
    stack_none = [find[(n, s, k, "GPR_none")]["stack"]["rel"] for n in NOISES for s in SAMPLINGS for k in SHOTS]
    stack_add = [find[(n, s, k, "GPR_additive")]["stack"]["rel"] for n in NOISES for s in SAMPLINGS for k in SHOTS]
    gpr_m5_40 = [find[(n, smp, 40, m)]["curve_nu1"][-1] for n in NOISES for smp in SAMPLINGS
                 for m in ("GPR_none", "GPR_additive")]
    gpr_best = min(find[(n, smp, k, m)]["fixedBest"]["rel"] for n in NOISES for smp in SAMPLINGS for k in SHOTS
                   for m in ("GPR_none", "GPR_additive"))
    pairs_nu = [(p["curve_nu0.5"][-1], p["curve_nu1"][-1]) for p in patterns]
    same_direction = sum((a < 0) == (b < 0) for a, b in pairs_nu)
    stack_gam_never_worse = max(stack_gam) < 0
    add_rule = rules["GPR_additive"]
    gam_rule = rules["GAM"]
    seconds = summary["medianSeconds"]

    summary_body = f"""
      <div class="callout tip">
        <div class="callout-icon" aria-hidden="true">✓</div>
        <div>
          <h3>結論：ブースティングを実装する必要性は低い（今は実装しないことを勧めます）</h3>
          <p>
            模擬データ（Wafer {summary['nWafers']} 枚 × ノイズ2通り）で、学習 Shot 数・選び方・ノイズを変えた 16 パターンを調べました。
            今のツールで最も良い手法 <strong>GPR（加法カーネル）</strong> は 16 パターン中 {best_count} パターンで最良で、
            ブースティングを加えて、しかも結果を見てから最良の設定を選んでも、改善は最大 {pct(min(gains))}（16 パターンで {pct(min(gains))}〜{pct(max(gains))}）でした。
            前もって設定を1つに決めると、GPR（加法カーネル）は平均で {pct(add_rule['overallRel'])}（16 パターン中 {add_rule['nPatternsWorse']} パターンで悪化）になります。
          </p>
        </div>
      </div>
      <div class="card-grid three-columns">
        <article class="feature-card">
          <span class="card-label">Finding 1</span>
          <h3>同じ手法を当てはめ直しても変わらない</h3>
          <p>残差に GPR・GAM を当てはめ直す（ハイパーパラメータも推定し直す）と、どちらも「残差に形は無い」と判断し、推定値はほぼ変わりません（全パターンで変化は最大 {summary['refit']['maxAbsRel']:.1f}%）。</p>
        </article>
        <article class="feature-card">
          <span class="card-label">Finding 2</span>
          <h3>効くのは GAM だけ、しかも条件しだい</h3>
          <p>ハイパーパラメータを固定した古典的なブースティングは、GAM の I 最適・20〜40 Shot で {pct(max(gam_iopt))}〜{pct(min(gam_iopt))} 良くなる一方、ランダムでは 5 回で {pct(min(gam_random_curve))}〜{pct(max(gam_random_curve))} と悪くなります。GPR では多くのパターンで悪化しました。</p>
        </article>
        <article class="feature-card">
          <span class="card-label">Finding 3</span>
          <h3>強めた GAM も GPR に届かない</h3>
          <p>GAM をブースティング・重ねで最も良くした値でも、ブースティングなしの GPR（加法カーネル）より {pct(min(gaps), 0)}〜{pct(max(gaps), 0)} 悪い。ブースティングを入れても、選ぶべき手法は変わりません。</p>
        </article>
      </div>
      <p class="note">
        結論の根拠は 4〜8章、なぜそうなるかは 9章、実装を考える場合の条件は 10章にまとめました。
        数値は、真値（ノイズを足す前の値）に対する評価点の RMSE を Wafer ごとに比べた相対変化の平均です（負なら改善）。
      </p>"""

    purpose_body = """
      <p>
        <strong>ブースティング</strong>は、一度推定したあとの「取り残し（学習点の残差 = 計測値 − 推定値）」に、もう一度モデルを当てはめて足し込み、
        これを何回か繰り返して精度を上げる方法です。弱い（単純な）モデルを積み重ねて強いモデルを作るのが本来の使い方です。
        このツールの GPR・GAM はすでに滑らかさをデータから選ぶ「強い」手法なので、足し込みで本当に良くなるのか、実装する価値があるのかを確かめました。
      </p>
      <ul class="check-list">
        <li>問い1：GPR・GAM の残差に同じ手法を当てはめ直すと、評価点の誤差は小さくなるか。</li>
        <li>問い2：効くとしたら、学習 Shot 数・Shot の選び方・計測ノイズによって効き方は変わるか。回数や縮小率を前もって決められるか。</li>
        <li>問い3：ブースティングを加えた結果は、今のツールにある手法の中から最も良いものを選ぶ場合より良いか（実装しないと得られない改善か）。</li>
      </ul>"""

    method_rows = [
        ["データ", f"このリポジトリの模擬データの作り方（src/wafer_generator.py）で作った Wafer {summary['nWafers']} 枚（99 Shot × 4 Mark = 396 点）。値 = 面内傾向（Zernike 10〜30 項）＋ Mark ごとのずれ ＋ Scan 方向の差 ＋ 計測ノイズ。真値はノイズを足す前の値。"],
        ["ノイズ", "標準（一様分布、幅は中心 ±1 nm → 最外周 ±3 nm）と、その2倍（±2 → ±6 nm）。同じ Wafer でノイズだけを変えた。"],
        ["学習 Shot 数", "10・20・30・40 Shot（全 99 Shot のうち）"],
        ["Shot の選び方", "制約付き I 最適（初期設定）と、制約つきランダム（1回）。どちらもアプリと同じ作り方・同じ制約"],
        ["手法", "GPR（matern52、説明変数 X,Y,半径、質的変数なし）、GPR（同、加法カーネルで Scan 方向・Mark 番号）、GAM（スプライン、説明変数 X,Y,半径、Scan 方向・Mark 番号）。X・Y は別々に当てはめる"],
        ["評価", "学習しなかった Shot の Mark で、真値に対する RMSE（X・Y 合計）。計測値に対する RMSE（アプリの評価と同じ）も求めた"],
    ]
    variants_rows = [
        ["ブースティングなし", "F<sub>0</sub>：手法をそのまま当てはめる（基準）"],
        ["① 当てはめ直す", "r = y − F<sub>m−1</sub>（学習点）に同じ手法を当てはめ直し（ハイパーパラメータ・λ も推定し直す）、F<sub>m</sub> = F<sub>m−1</sub> + h<sub>m</sub>。m = 1〜3"],
        ["② ハイパーパラメータ固定", "同じ。ただし h<sub>m</sub> は F<sub>0</sub> のハイパーパラメータ・λ のまま（古典的な L2 ブースティング）。F<sub>m</sub> = F<sub>m−1</sub> + ν·h<sub>m</sub>、縮小率 ν = 0.5・1、m = 1〜5"],
        ["③ 別の手法を重ねる", "F<sub>0</sub> の残差に別の手法を1回当てはめて足す。GPR には GAM、GAM には GPR（質的変数なし）"],
    ]
    method_body = f"""
      <p>アプリと同じ推定の関数（alignest.models の GPR・GAM）を使い、最初の当てはめはアプリの推定（estimateWafer）と同じ値になることを Wafer・パターンごとに確かめました（差の最大 {summary['maxCheckDiff']:.1g} nm）。</p>
{table(["項目", "内容"], method_rows)}
      <h3>比べたブースティングの変種</h3>
{table(["変種", "やり方（y は学習点の計測値、F は推定値、h は残差に当てはめた値）"], variants_rows)}
      <div class="formula-box">
        <p><span>相対変化</span><span>=</span><span>（変種の RMSE − ブースティングなしの RMSE）÷ ブースティングなしの RMSE × 100 [%]（負なら改善）</span></p>
        <p><span>95% 区間</span><span>=</span><span>Wafer ごとの相対変化の平均 ± t（自由度 {summary['nWafers'] - 1}）× 標準誤差</span></p>
      </div>
      <p class="note">学習 Shot 数 4 × 選び方 2 × ノイズ 2 = 16 パターン、各パターン {summary['nWafers']} 枚。計算は MATLAB R2022b（Apple M1）で、当てはめの時間の合計は約 {summary['secondsTotal'] / 60:.0f} 分（データの読み込み・Shot の選び方を含めて約 6 分）。</p>"""

    refit_body = f"""
      <p>
        残差に同じ手法を当てはめ直すと、推定値はほとんど変わりませんでした（手法 × パターンの {len(patterns)} 組で各 3 回、相対変化の絶対値は平均 {'0.001% 未満' if summary['refit']['meanAbsRel'] < 0.001 else f"{summary['refit']['meanAbsRel']:.3f}%"}、最大 {summary['refit']['maxAbsRel']:.1f}%）。
      </p>
      <div class="callout info">
        <div class="callout-icon" aria-hidden="true">i</div>
        <div>
          <h3>なぜ変わらないか</h3>
          <p>
            GPR は、残差を当てはめるときに信号の大きさ σ<sub>f</sub> をほぼ 0（例：0.003 nm）、ノイズ σ<sub>n</sub> を残差の大きさにし、「残差は形の無いノイズ」と判断します。
            GAM も REML で平滑化を最大にし、罰則の無い部分（定数・1次・質的変数の効果）は最初の当てはめで取り切っているので、足す値はほぼ 0 になります。
            どちらも尤度・REML で滑らかさを選んでいるため、自分の残差に「まだ当てはめられる形」を見つけません。
          </p>
        </div>
      </div>
      <p>このため、ブースティングを実装するなら、2回目以降はハイパーパラメータを固定する（②）など、手法の作りを変える必要があります。</p>"""

    fixed_rows = []
    for noise in NOISES:
        for sampling in SAMPLINGS:
            for n_shots in SHOTS:
                cells = [pattern_name(noise, sampling, n_shots)]
                for method in METHODS:
                    item = find[(noise, sampling, n_shots, method)]["fixedBest"]
                    cells.append(f"ν{item['nu']:g}・{item['round']}回：{interval_text(item)}")
                fixed_rows.append(cells)
    rule_rows = [[METHOD_LABELS[m], f"ν = {rules[m]['nu']:g}・{rules[m]['round']} 回", pct(rules[m]["overallRel"]),
                  f"{rules[m]['nPatternsWorse']} / {rules[m]['nPatterns']}",
                  f"{pct(rules[m]['bestPatternRel'])}〜{pct(rules[m]['worstPatternRel'])}"] for m in METHODS]
    fixed_body = f"""
      <p>2回目以降を最初の当てはめのハイパーパラメータ・λ のままにすると、足す値が 0 でなくなり、推定は「平滑化を弱める」方向に進みます。</p>
{figure("fig1_rounds_ioptimal.png", "I 最適での、回数ごとの相対変化の折れ線。GPR は回数とともに悪化し、GAM は 20〜40 Shot で改善する", "図1　I 最適：回数による変化（線は学習 Shot 数、実線 = ノイズ標準、破線 = ノイズ2倍。0 より下が改善）")}
{figure("fig2_rounds_random.png", "ランダムでの、回数ごとの相対変化の折れ線。GAM も回数とともに悪化する", "図2　ランダム：回数による変化。GAM もほとんどのパターンで悪くなる")}
      <ul class="check-list">
        <li>GPR（質的変数なし・加法カーネル）：多くのパターンで回数とともに悪化します。学習 Shot が多いほど悪化が大きく（40 Shot では ν = 1・5 回で {pct(min(gpr_m5_40))}〜{pct(max(gpr_m5_40))}）、最も良い設定でも改善は最大 {pct(gpr_best)} でした。</li>
        <li>GAM：I 最適の 20〜40 Shot では回数とともに改善し（5 回で {pct(max(gam_iopt))}〜{pct(min(gam_iopt))}）、ランダムでは逆に悪化しました（ν = 1・5 回で {pct(min(gam_random_curve))}〜{pct(max(gam_random_curve))}）。同じ手法でも、Shot の選び方で良し悪しが逆になります。</li>
        <li>学習点の残差は回数とともに小さくなります（学習点に合わせ込む）が、評価点の誤差は良くならないことが多い（図3）。</li>
      </ul>
{figure("fig3_tradeoff.png", "学習点の残差を横軸、評価点の誤差を縦軸にした回数ごとの点の並び", "図3　回数を増やすと学習点の残差（横軸）は小さくなる。評価点の誤差（縦軸）は、GPR では学習 Shot が多いほど増え（10・20 Shot はほぼ横ばい）、GAM は I 最適の 20 Shot 以上で減る")}
      <h3>パターンごとの最も良い設定（結果を見てから選んだ値）</h3>
{table(["パターン", METHOD_LABELS["GPR_none"], METHOD_LABELS["GPR_additive"], METHOD_LABELS["GAM"]], fixed_rows, "各セル：最も良かった縮小率 ν・回数と、そのときの相対変化（95% 区間）")}
      <h3>前もって設定を1つに決めた場合</h3>
      <p>実際に使うときは結果を見てから設定を選べないので、手法ごとに 16 パターンの平均が最も良い ν・回数を1つに決めたときの変化を示します。</p>
{table(["手法", "決めた設定", "16 パターンの平均", "悪化したパターン", "パターンごとの範囲"], rule_rows)}"""

    stack_rows = []
    for noise in NOISES:
        for sampling in SAMPLINGS:
            for n_shots in SHOTS:
                cells = [pattern_name(noise, sampling, n_shots)]
                for method in METHODS:
                    cells.append(interval_text(find[(noise, sampling, n_shots, method)]["stack"]))
                stack_rows.append(cells)
    stack_body = f"""
      <p>同じ手法ではなく、別の手法を残差に1回重ねると（③）、手法によって大きく変わりました。</p>
{figure("fig4_stack.png", "残差に別の手法を重ねたときの相対変化の棒グラフ", "図4　残差に別の手法を1回重ねたときの変化（I 最適。Wafer の平均と 95% 区間）")}
      <ul class="check-list">
        <li>GPR（質的変数なし）＋ GAM：{pct(max(stack_none))}〜{pct(min(stack_none))}。GPR が持たない Mark ごとのずれ・Scan 方向の差を、GAM の質的変数が補うためです。ただし同じことは GPR の加法カーネル（質的変数を入れた GPR）で既にできます。</li>
        <li>GPR（加法カーネル）＋ GAM：{pct(min(stack_add))}〜{pct(max(stack_add))}。加法カーネルが質的変数を扱っているので、重ねても変わりません。</li>
        <li>GAM ＋ GPR：{pct(max(stack_gam))}〜{pct(min(stack_gam))}。GAM が取り残した細かい形を GPR が拾います{'（どのパターンでも平均は悪化しなかった）' if stack_gam_never_worse else ''}。</li>
      </ul>
{table(["パターン", METHOD_LABELS["GPR_none"] + " ＋ GAM", METHOD_LABELS["GPR_additive"] + " ＋ GAM", METHOD_LABELS["GAM"] + " ＋ GPR"], stack_rows, "相対変化（95% 区間）")}"""

    versus_rows = []
    for b, g in zip(best, gam_gap):
        method, config = b["bestBoostMethod"], b["bestBoostConfig"]
        if config.startswith("stack"):
            config_text = config.split(" m=")[0].replace("stack:GAM", "③ ＋GAM").replace("stack:GPR_none", "③ ＋GPR")
        else:
            config_text = config.replace("L2fixed", "② 固定").replace(" m=", "・").replace("ν=", "ν") + " 回"
        versus_rows.append([pattern_name(b["noise"], b["sampling"], b["nShots"]),
                            f"{METHOD_LABELS[b['bestBase']]}　{b['bestBaseRmse']:.3f}",
                            f"{METHOD_LABELS[method]} {escape(config_text)}　{b['bestBoostRmse']:.3f}", pct(b["gain"]),
                            f"{g['gamBest']:.3f}（{pct(g['gap'], 0)}）"])
    versus_body = f"""
      <p>
        実装の必要性は、「ブースティングを入れないと得られない改善があるか」で決まります。パターンごとに、今の手法から最も良いもの（ブースティングなし）と、
        ブースティング・重ねを含めて最も良いものを比べました。どちらも結果を見てから選んだ値なので、ブースティング側に有利な比べ方です。
      </p>
{figure("fig5_best.png", "パターンごとの、既存の手法で最良の RMSE と、ブースティングを含めて最良の RMSE の棒グラフ。ほとんど同じ高さ", "図5　今の手法から選ぶ場合（灰）と、ブースティングを含めた場合（青）。差はほとんど無い")}
{table(["パターン", "今の手法で最良（RMSE nm）", "ブースティングを含めて最良（RMSE nm）", "差", "GAM を最も良くした値（GPR 加法との差）"], versus_rows)}
      <p>
        今の手法の最良は 16 パターン中 {best_count} パターンで GPR（加法カーネル）で、ブースティングを含めても差は {pct(min(gains))}〜{pct(max(gains))} でした。
        最も良い設定はパターンごとに違い（② 固定の ν・回数、③ ＋GAM）、前もって決めると 5章のとおり平均では悪化します。
        GAM を最も良くしても、GPR（加法カーネル）より {pct(min(gaps), 0)}〜{pct(max(gaps), 0)} 悪いままです。
      </p>"""

    measured_body = f"""
      <p>
        アプリは真値ではなく計測値（ノイズを含む）で評価します。計測値に対する RMSE で同じ相対変化を求めると、真値に対する相対変化との相関は {summary['measuredVsTruthCorr']:.2f}、
        改善・悪化の向きが一致した割合は {100 * summary['signAgreement']:.0f}% でした。実データで同じ比較をしても、同じ結論になると考えられます。
      </p>"""

    discussion_body = f"""
      <ul class="check-list">
        <li><strong>GPR・GAM はすでに滑らかさを選んでいる</strong>：ブースティングは「平滑化を弱める」操作です。GPR は尤度、GAM は REML で、そのデータに合う滑らかさを選んでいるので、弱めるとノイズに合わせ込む分だけ悪くなりやすい。当てはめ直す（①）と、手法自身が「もう形は無い」と判断して何も足しません。</li>
        <li><strong>GAM が I 最適で良くなるのは、平滑化が強めに選ばれているため</strong>と考えられます（I 最適は Shot が広く散らばり、GAM の滑らかな面ではとらえ切れない細かい形が残る）。ランダムでは Shot の間の空きが大きく、弱めた平滑化が空きの所で振れて悪化します。ただし、この理由は今回の結果からの推測で、確かめてはいません。</li>
        <li><strong>回数・縮小率は前もって決められない</strong>：良い設定が手法・学習 Shot 数・選び方で変わり、向きが逆になることもあります。実装するなら、学習 Shot を分けて試す交差検証などで Wafer ごとに回数を決める仕組みが要り、計算は（回数 + 1）×（分割数）倍になります。</li>
        <li><strong>時間</strong>：1回の当てはめの中央値は、GPR（加法カーネル）{seconds['GPR_additive|base']:.2f} 秒、GAM {seconds['GAM|base']:.2f} 秒（1 Wafer・1 パターン、X・Y）。ハイパーパラメータ固定の2回目以降は 1回 約 {seconds['GPR_additive|L2fixed']:.3f} 秒と軽いが、交差検証まで入れると評価全体の時間は数倍になります。</li>
      </ul>"""

    proposal_body = f"""
      <ol class="decision-list">
        <li><span>実装</span>ブースティングは今は実装しない。今の手法から選ぶ場合より良くなるのは最大 {pct(min(gains))} で、設定を前もって決めると平均では悪化するため。</li>
        <li><span>使う手法</span>精度を求めるときは GPR（加法カーネル）を使う（16 パターン中 {best_count} パターンで最良）。</li>
        <li><span>GAM を使うとき</span>説明しやすさなどで GAM を使う必要があるときは、ブースティングより「GAM ＋ 残差に GPR」（③）を1回重ねるほうが簡単で、{'どのパターンでも平均は悪化しなかった' if stack_gam_never_worse else '多くのパターンで良くなった'}（{pct(max(stack_gam))}〜{pct(min(stack_gam))}）。必要になったら、この重ねを1つの手法として加えることを検討する。</li>
        <li><span>見直す条件</span>実データで GPR（加法カーネル）の残差に、Wafer をまたいで同じ形が残る場合や、GAM を主に使う運用になった場合は、③ の重ねと交差検証つきのブースティングを実データで試してから判断する。</li>
      </ol>"""

    reproduce_body = f"""
      <ol class="numbered-steps">
        <li><div><strong>模擬データを作る</strong><p>リポジトリの直下で <code>.venv/bin/python matlab_app/docs/boosting_study/_src/make_boosting_data.py &lt;データのフォルダ&gt;</code>。boosting_standard.csv・boosting_high.csv（各 {summary['nWafers']} 枚）ができる。CSV はリポジトリに入れない（.gitignore で除外）。</p></div></li>
        <li><div><strong>検証を実行する（MATLAB）</strong><p>matlab_app と <code>docs/boosting_study/_src</code> をパスに入れ、<code>run_boosting_study("&lt;データのフォルダ&gt;", "&lt;結果の CSV&gt;")</code>。約 6 分（Apple M1）で {summary['nRows']} 行の結果ができる。</p></div></li>
        <li><div><strong>集計と図</strong><p><code>.venv/bin/python matlab_app/docs/boosting_study/_src/analyze_boosting.py &lt;結果の CSV&gt;</code>。images の図と _src/summary.json ができる。</p></div></li>
        <li><div><strong>この報告書を作る</strong><p><code>.venv/bin/python matlab_app/docs/boosting_study/_src/build_report.py</code>。本文と表の数値は summary.json から入る。</p></div></li>
      </ol>"""

    limits_body = f"""
      <ul class="check-list">
        <li>模擬データだけの結果です（Wafer は 16 枚、Shot の配置は1通り）。実データの面内傾向・ノイズの形が模擬データと違えば、効き方も変わり得ます。</li>
        <li>手法の設定は1通り（GPR は matern52・説明変数 X,Y,半径、GAM はスプライン）です。ほかのカーネル・形状関数・質的変数の扱い（Backfitting・混合など）は調べていません。</li>
        <li>ブースティングの回数は最大 5 回、縮小率は 0.5・1 です。縮小率を小さくすると変化はゆっくりになり、5 回目の改善・悪化の向きは、手法 × パターンの {len(pairs_nu)} 組のうち {same_direction} 組で 0.5 と 1 が同じでした。それより小さい縮小率・多い回数は調べていません。</li>
        <li>「最良の設定」「最も良くした値」は結果を見てから選んだ値で、実際に得られる改善より大きく出ます（上限の目安）。</li>
        <li>ランダムの選び方は1通り（各学習 Shot 数で1つの組）です。外部の文献は使っていません（考察の理由は、今回の結果と式からの説明です）。</li>
      </ul>"""

    toc = "\n".join(f'        <li><a href="#{i}">{n}. {escape(t)}</a></li>' for n, (i, t) in enumerate(SECTIONS, 1))
    kickers = ["Summary", "Purpose", "Method", "Result 1", "Result 2", "Result 3", "Result 4", "Result 5",
               "Discussion", "Proposal", "Reproduce", "Limits"]
    bodies = [summary_body, purpose_body, method_body, refit_body, fixed_body, stack_body, versus_body, measured_body,
              discussion_body, proposal_body, reproduce_body, limits_body]
    sections = "".join(section(i, n, k, t, b) for n, ((i, t), k, b) in enumerate(zip(SECTIONS, kickers, bodies), 1))
    return f"""<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="GPR・GAM にブースティングを加えたときの効果を、模擬データで学習 Shot 数・選び方・ノイズを変えて検証した報告書。">
  <title>ブースティングの必要性の検証</title>
  <link rel="icon" href="data:,">
  <link rel="stylesheet" href="procedure-guide.css">
  <style>
    /* 図と表の見出し（テンプレートに無い部品だけを足す） */
    .report-figure {{ margin: 16px 0 22px; }}
    .report-figure img {{ display: block; width: 100%; max-width: 1000px; height: auto;
      border: 1px solid var(--color-slate-200); border-radius: var(--radius-medium-px); background: #fff; }}
    .report-figure figcaption {{ margin-top: 6px; color: var(--color-slate-600); font-size: 0.8rem; }}
    table caption {{ caption-side: top; text-align: left; padding: 6px 0; color: var(--color-slate-600); font-size: 0.8rem; }}
    td {{ font-variant-numeric: tabular-nums; }}
    .formula-box p {{ grid-template-columns: 110px 20px 1fr; }}
    .decision-list li {{ grid-template-columns: 36px 120px 1fr; }}
    @media (max-width: 720px) {{
      .formula-box p, .decision-list li {{ grid-template-columns: 1fr; }}
    }}
    /* 狭い画面：目次のボタンとトップへ戻るを、上に固定した帯（本文の場所を取る）に入れる */
    .mobile-bar {{ display: none; }}
    @media (max-width: 900px) {{
      .mobile-bar {{ position: sticky; top: 0; z-index: 130; display: flex; justify-content: space-between;
        align-items: center; gap: 10px; padding: 8px 14px; background: var(--color-navy-900); }}
      .mobile-bar .toc-toggle {{ position: static; box-shadow: none; }}
      .mobile-top {{ padding: 8px 12px; border: 1px solid var(--overlay-white-16); border-radius: 999px;
        color: var(--color-white); font-size: 0.78rem; font-weight: 700; text-decoration: none; }}
      .mobile-top:focus-visible {{ outline: 2px solid var(--color-white); outline-offset: 2px; }}
      .back-to-top {{ display: none !important; }}
      .hero {{ padding-top: 24px; }}
      .content-section {{ scroll-margin-top: 56px; }}
    }}
  </style>
  <script src="procedure-guide.js" defer></script>
</head>
<body id="top">
  <a class="skip-link" href="#main-content">本文へ移動</a>

  <!-- 狭い画面では、目次のボタンとトップへ戻るを上の帯にまとめ、本文の上に重ねない -->
  <div class="mobile-bar">
    <button id="toc-toggle" class="toc-toggle" type="button" aria-controls="sidebar" aria-expanded="false">
      <span aria-hidden="true">☰</span> 目次
    </button>
    <a class="mobile-top" href="#top"><span aria-hidden="true">↑</span> トップへ戻る</a>
  </div>

  <aside id="sidebar" class="sidebar" aria-label="目次">
    <div class="sidebar-header">
      <p class="eyebrow">Study Report</p>
      <p class="sidebar-title">面内推定評価ツール</p>
      <p class="sidebar-subtitle">ブースティングの必要性</p>
    </div>
    <nav>
      <ol class="toc-list">
{toc}
      </ol>
    </nav>
    <div class="sidebar-footer">
      <span class="status-dot" aria-hidden="true"></span>
      模擬データによる検証
    </div>
  </aside>
  <div id="sidebar-overlay" class="sidebar-overlay" aria-hidden="true"></div>

  <main id="main-content" class="main-content">
    <header class="hero">
      <div class="hero-content">
        <p class="eyebrow">Study Report · GPR / GAM</p>
        <h1>ブースティングを実装する必要性の検証<br><span>GPR・GAM に残差の当てはめを足していく効果</span></h1>
        <p class="hero-lead">
          GPR と GAM にブースティング（取り残しにモデルを当てはめて足していく方法）を加えたとき、推定の精度がどれだけ変わるかを、
          学習 Shot 数・Shot の選び方・計測ノイズを変えた 16 パターンの模擬データで調べ、実装する必要があるかを判断しました。
        </p>
        <div class="hero-badges" aria-label="文書情報">
          <span>データ: 模擬 Wafer {summary['nWafers']} 枚 × ノイズ 2 通り</span>
          <span>パターン: 16（学習 Shot 数 4 × 選び方 2 × ノイズ 2）</span>
          <span>更新日: {UPDATED}</span>
        </div>
      </div>
    </header>
{sections}

    <footer class="page-footer">
      <p>面内推定評価ツール · ブースティングの必要性の検証 · matlab_app/docs/boosting_study</p>
      <p>更新日: {UPDATED} · 版: 1.0</p>
    </footer>
  </main>

  <button id="back-to-top" class="back-to-top" type="button" aria-label="ページ上部へ戻る">
    <span aria-hidden="true">↑</span>
    トップへ戻る
  </button>
</body>
</html>
"""


def main() -> None:
    summary = json.loads((HERE / "summary.json").read_text(encoding="utf-8"))
    OUTPUT.write_text(build(summary), encoding="utf-8")
    print(f"作成しました：{OUTPUT}")


if __name__ == "__main__":
    main()
