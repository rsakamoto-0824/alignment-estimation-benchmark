"""面内推定評価ツールの機能仕様書（PowerPoint）を作る。

使い方：python3 build_functional_spec.py [出力 .pptx] [参照デッキ .pptx]
機能の名前・数は features.py（詳細機能一覧 HTML と共通）から取る。画面の画像は ../images（capture_screens.m で撮る）。
"""
from __future__ import annotations

import sys
from pathlib import Path

from deckkit import (ACCENTS, BODY, CONTENT_LEFT, CONTENT_WIDTH, CORAL, CORAL_TINT, DEFAULT_REFERENCE, GOLD,
                     GOLD_TINT, INK, LINE, MUTED, NAVY, PANEL, PURPLE, PURPLE_TINT, TEAL, TEAL_TINT, WHITE, Deck,
                     agenda, arrow, box, card, circle, closing, cover, heading_blocks, node, panel, point_bar, screen,
                     table, tag, text)
from features import APP_NAME, VERSION_NOTE, feature_count, numbered_sections

HERE = Path(__file__).resolve().parent
DEFAULT_OUTPUT = HERE.parent / f"{APP_NAME}_機能仕様書.pptx"
DECK_NAME = f"{APP_NAME} 機能仕様書"
SECTIONS = {section["key"]: section for section in numbered_sections()}


def selected_groups(keys, group_titles=None):
    """選んだタブ（keys は "3" か ["3", "4"]）の中のまとまりと機能"""
    keys = [keys] if isinstance(keys, str) else keys
    groups = []
    for key in keys:
        prefix = "" if len(keys) == 1 else SECTIONS[key]["title"][3:] + "："
        for title, rows in SECTIONS[key]["groups"]:
            if not group_titles or title in group_titles:
                groups.append((prefix + title, rows))
    return groups


def feature_blocks(keys, group_titles=None):
    """features.py の中のタブ（まとまり）ごとに「見出し・機能の名前の並び」を作る"""
    blocks = []
    for title, rows in selected_groups(keys, group_titles):
        first, last = rows[0]["id"], rows[-1]["id"]
        names = "・".join(row["name"] + ("（Pro）" if row["ed"] == "Pro" else "") for row in rows)
        blocks.append((f"{title}　{first}〜{last}", names))
    return blocks


def tab_slide(deck, key, title, image, caption, flow, group_titles=None, image_w=6.55):
    """左に画面の画像と流れ、右に機能の一覧（詳細機能一覧の ID つき）"""
    slide = deck.body("03　機能（タブごと）", title)
    h = screen(slide, image, CONTENT_LEFT, 1.55, image_w, caption)
    y = 1.55 + h + 0.45
    box(slide, CONTENT_LEFT, y, image_w, 6.85 - y, fill=PANEL)
    text(slide, CONTENT_LEFT + 0.2, y + 0.1, image_w - 0.4, 0.3, "使い方の流れ", size=12, color=INK, bold=True)
    text(slide, CONTENT_LEFT + 0.2, y + 0.42, image_w - 0.4, 6.75 - y - 0.42, flow, size=11.5, color=BODY,
         line_spacing=1.1)
    x = CONTENT_LEFT + image_w + 0.35
    w = CONTENT_LEFT + CONTENT_WIDTH - x
    count = sum(len(rows) for _, rows in selected_groups(key, group_titles))
    text(slide, x, 1.5, w, 0.3, f"主な機能（{count} 機能。ID は詳細機能一覧と同じ）", size=11, color=MUTED, bold=True)
    heading_blocks(slide, x, 1.85, w, feature_blocks(key, group_titles), size="auto", gap=0.12)
    return slide


def build(output: Path, reference: Path):
    deck = Deck(DECK_NAME, f"{APP_NAME} 機能仕様書", reference)
    total = feature_count()

    # 1 表紙
    cover(deck, "機能仕様書 ｜ MATLAB アプリ", f"{APP_NAME}\n機能仕様書",
          "LUCAS（Lithography Utilities for Correction Analysis and Sampling Optimization）",
          "アライメント計測値の面内推定を、実データ（Excel）で比べて決めるための画面つきアプリ。何を入れ、何ができ、何が出るかをまとめる。",
          f"{VERSION_NOTE}のコードと README に基づく ｜ 対象：利用者・管理者",
          image="s10_results_chart.png", image_caption="「3. 結果一覧」のグラフ（サンプルデータ）")

    # 2 構成
    agenda(deck, "", "この資料の構成",
           "ゴール：アプリの目的・入力・出力・機能を、画面のタブごとに説明できる状態にする",
           [("概要", "目的と範囲、想定利用者と利用場面、機能の全体像（8 つのタブ）", "p.3–5"),
            ("入力と出力", "読み込むデータの形、前処理と読み込みの条件、書き出すファイル", "p.6–8"),
            ("機能（タブごと）", f"タブごとの画面と主な機能。全 {total} 機能の詳細は別紙「詳細機能一覧」（HTML）", "p.9–18"),
            ("版と非機能", "通常版と Pro 版、動作環境・性能・品質などの要件、制約と注意事項", "p.19–22")])

    # 3 目的と範囲
    slide = deck.body("01　概要", "目的と範囲 ― 計測を減らしても補正できるか確かめる")
    inputs = ["計測データ（Excel・CSV）", "未知の座標の表", "Shot 高次補正の値の表", "設定（JSON）"]
    outputs = ["評価結果・推定値（Excel）", "補正値・計測マップ（Excel・CSV）", "図（PNG・クリップボード）", "設定（JSON）"]
    for index, label in enumerate(inputs):
        color, tint = ACCENTS[index]
        node(slide, 0.6, 1.65 + index * 0.72, 2.9, 0.58, label, fill=tint, size=12.5)
        arrow(slide, 3.55, 1.94 + index * 0.72, 4.45, 2.84)
    box(slide, 4.5, 1.75, 4.3, 2.2, fill=NAVY)
    text(slide, 4.6, 1.85, 4.1, 0.5, APP_NAME, size=19, color=WHITE, bold=True, align="c", anchor="m")
    text(slide, 4.7, 2.4, 3.9, 1.45, "面内推定の手法比較\n補正（Overlay・Shot 高次）の評価\n計測点・Mark 配置・計測マップの最適化",
         size=12.5, color="D9DBEA", align="c", anchor="m")
    for index, label in enumerate(outputs):
        node(slide, 9.83, 1.65 + index * 0.72, 2.9, 0.58, label, fill=PANEL, size=12.5)
        arrow(slide, 8.85, 2.84, 9.78, 1.94 + index * 0.72)
    panel(slide, 0.6, 4.75, 5.95, 2.1, "対象とすること",
          ["学習に使う計測点（Shot・Mark）と推定の手法を、指標で比べる",
           "推定誤差で Overlay 補正・Shot 高次補正がどれだけ悪くなるかを見る",
           "計測していない座標の推定値と、重ね合わせ補正値を求める",
           "計測 Mark の配置・計測マップのローテーションを決める"], fill=TEAL_TINT)
    panel(slide, 6.78, 4.75, 5.95, 2.1, "対象としないこと",
          ["露光装置・計測装置との接続、補正値の自動送信",
           "外部サービス・認証情報の利用（ネットにつながずに使う）",
           "入力ファイルの書き換え（読むだけ。結果は別のファイルに書く）",
           "実データの同梱（リポジトリにはサンプルデータだけ）"], fill=CORAL_TINT)

    # 4 想定利用者と利用場面
    slide = deck.body("01　概要", "想定利用者と利用場面")
    panel(slide, 0.6, 1.55, 3.6, 2.45, "解析担当者（利用者）",
          ["計測データを読み、計測点・手法・補正を比べて決める", "結果を Excel・図で共有する",
           "画面の欄は短い名前。詳しくはメニュー「ヘルプ」"], fill=TEAL_TINT, size=11.5)
    panel(slide, 0.6, 4.2, 3.6, 2.65, "管理者",
          ["既定の設定ファイルで部署の初期値をそろえる", "通常版・Pro 版の exe を作って配る",
           "テストを流し、ヘルプ・README を保守する"], fill=PURPLE_TINT, size=11.5)
    rows = [["想定利用", "使う画面（タブ）", "得られるもの"],
            ["UC1 計測点と推定の手法を比べて決める", "1 → 2 → 3 → 4", "手法 × 学習 Shot 数の指標、推奨の組み合わせ"],
            ["UC2 計測していない座標の値と補正値を見積もる", "1 → 2 → 5", "未知の座標の推定値、重ね合わせ補正値"],
            ["UC3 Shot 高次補正の式・項・回帰を決める", "1・5 → 6", "k パラメータ、補正残差、条件の比較"],
            ["UC4 Shot 内の計測 Mark を減らす配置を決める", "6 → 7", "Mark の数ごとの配置と制御残差・I 効率"],
            ["UC5 FB の計測マップをローテーションして減らす", "1・3・5 → 8", "ローテーションの計測マップ、FB 検証の補正残差"],
            ["UC6 計測配置を見直す（計測を足す・人の配置を比べる）", "3 → 2、8 → 2", "必ず計測する点、Excel 取込の配置"],
            ["UC7 結果を共有し、別の PC で見直す", "3（書き出し・読み込み）", "評価結果・推定値の Excel"]]
    table(slide, 4.45, 1.55, [3.85, 1.85, 2.58], rows, size=11, header_size=12, row_h=0.6)
    text(slide, 4.45, 6.48, 8.28, 0.35, "画面の動き（どのタブをどの順に使うか）は別紙「画面遷移図」で想定利用ごとに示す。",
         size=11, color=MUTED)

    # 5 機能の全体像
    slide = deck.body("01　概要", f"機能の全体像 ― 8 つのタブと共通の機能（全 {total} 機能）")
    blurbs = {
        "1": "計測データを読み込み、列の対応・単位・除外を決めて確かめる",
        "2": "計測点の選び方・比べる手法・評価の条件を決めて評価する",
        "3": "手法 × 学習パターンの指標を比べ、誤差と補正を分析する",
        "4": "計測値・推定値・残差を Wafer 上に描き、条件を並べる",
        "5": "計測していない座標を推定し、重ね合わせ補正値を求める",
        "6": "Shot 高次補正の k を求め、式・くくり・回帰を比べる",
        "7": "Shot 内の計測 Mark の配置を Mark の数ごとに選ぶ",
        "8": "ばらつきで優先度を分けた計測マップを作り、FB で検証する",
    }
    w, h, gap = 2.9, 2.05, 0.177
    for index, key in enumerate("12345678"):
        color, tint = ACCENTS[index % 4]
        x = CONTENT_LEFT + (index % 4) * (w + gap)
        y = 1.6 + (index // 4) * (h + 0.22)
        box(slide, x, y, w, h, fill=WHITE, line=LINE)
        circle(slide, x + 0.2, y + 0.2, 0.5, color, key, size=15)
        text(slide, x + 0.82, y + 0.2, w - 0.95, 0.5, SECTIONS[key]["title"][3:], size=15, color=INK, bold=True,
             anchor="m")
        text(slide, x + 0.2, y + 0.85, w - 0.4, 0.85, blurbs[key], size=12, color=BODY, line_spacing=1.1)
        text(slide, x + 0.2, y + h - 0.38, w - 0.4, 0.3, f"{SECTIONS[key]['count']} 機能", size=11, color=color,
             bold=True, align="r")
    common = SECTIONS["C"]
    box(slide, CONTENT_LEFT, 6.17, CONTENT_WIDTH, 0.7, fill=PANEL)
    text(slide, 0.8, 6.17, 11.8, 0.7,
         f"共通（{common['count']} 機能）：画面の色・文字の大きさ・凡例の位置・Scan 方向の向きと色・乱数の種（メニュー「設定」）、"
         "図の保存とコピー、ヘルプ（機能編・技術編）、通常版と Pro 版", size=12, color=INK, anchor="m")

    # 6 入力データの仕様
    slide = deck.body("02　入力と出力", "読み込むデータの形 ― 1 行目が項目名、2 行目からデータ")
    rows = [["項目名", "意味", "必須", "無いとき"],
            ["Operation・EqpId・LotID", "工程名・装置 ID・ロット ID（このツールで追加した任意の項目）", "", "空。違えば別の計測として扱う"],
            ["Wafer", "ウェハ ID", "", "全行を 1 枚とみなす"],
            ["DateTime", "測定日時", "", "空。違えば別の計測として扱う"],
            ["shotNo", "ショット番号", "", "座標から番号を付ける（上の行から左→右）"],
            ["Direction", "Scan 方向（1・2）", "", "「Scan 方向の付与」の規則で付ける"],
            ["Xmm・Ymm", "ショット中心の座標 [mm]（絶対座標だけなら点の座標）", "○", ""],
            ["Radius", "ショット中心の半径 [mm]", "", "あれば Xmm・Ymm からの値と照合"],
            ["markNo", "ショット内のマーク番号", "", "マーク座標の組ごとに番号を付ける"],
            ["markXmm・markYmm", "ショット中心から見たマーク座標 [mm]", "○※", "絶対座標だけなら任意"],
            ["measX・measY", "マークの測定値 [nm]", "○※", "1 変数なら選んだ列を使う"],
            ["StsX・StsY", "ステータス（0 = 有効、−1 = 未測定）", "", "測定値が空でなければ有効"]]
    table(slide, CONTENT_LEFT, 1.5, [2.55, 5.0, 0.75, 3.83], rows, size=10.5, header_size=11.5, row_h=0.36,
          aligns=["l", "l", "c", "l"], bold_first=True)
    text(slide, CONTENT_LEFT, 6.4, CONTENT_WIDTH, 0.5,
         "※ 座標の定義・推定する値によって任意になる。名前が違う列は「列の対応」で選び直せる。対応づけなかった列（Chuck・Reticle など）は"
         "質的変数・連続値の列に使える。Excel 本体は不要（MATLAB の読み込み機能を使う）。", size=10, color=MUTED)

    # 7 前処理
    slide = deck.body("02　入力と出力", "前処理と読み込みの条件 ― 「この対応で読み込む」で決まる")
    steps = [("列の対応", "標準の項目名に自動で対応づけ、違えば選び直す"),
             ("座標の単位", "mm・µm・nm・m を mm に変換（測定値は nm のまま）"),
             ("行の除外", "有効半径（150 mm）の外、X・Y が両方 0、Sts が −1、異常値（nσ・MAD）"),
             ("座標と重複", "x = Xmm + markXmm。Sts = 0 の値だけ使い、同じ点は平均"),
             ("評価の単位", "Operation × EqpId × LotID × Wafer × DateTime で分ける")]
    for index, (heading, body) in enumerate(steps):
        y = 1.6 + index * 1.04
        color, tint = ACCENTS[index % 4]
        box(slide, CONTENT_LEFT, y, 6.3, 0.86, fill=tint)
        circle(slide, 0.78, y + 0.17, 0.52, color, str(index + 1), size=14)
        text(slide, 1.45, y + 0.06, 1.65, 0.74, heading, size=14, color=INK, bold=True, anchor="m")
        text(slide, 3.05, y + 0.06, 3.75, 0.74, body, size=11.5, color=BODY, anchor="m")
        if index < len(steps) - 1:
            arrow(slide, 1.04, y + 0.86, 1.04, y + 1.04)
    heading_blocks(slide, 7.25, 1.6, 5.48, [
        ("座標の定義", "Shot 中心＋Shot 内の位置（初期値）か、Wafer 上の絶対座標だけ。絶対座標では markXmm・shotNo から"
                    "Shot 中心を決め、無ければ点を 1 つずつ Shot として扱う。"),
        ("推定する値", "X・Y 成分（初期値）か、膜厚・線幅などの 1 つの列（1 変数）。1 変数では RT モデル・Overlay 補正の評価・"
                    "矢印の図を使わない。"),
        ("Scan 方向の付与", "Direction が無い行に、一筆書き（初期値）・shotNo の奇偶・市松模様・行ごと・列ごとの規則で 1・2 を付ける。"
                         "Shot レイアウトで Shot をクリックすると入れ替えられる。"),
        ("結果の確認", "除いた行・まとめた行の数、工程・装置・ロットの一覧を「読み込み結果」と Excel の「説明」に出す。"),
    ], heading_size=13.5, size=12, gap=0.16)

    # 8 出力
    slide = deck.body("02　入力と出力", "書き出すファイル ― 結果・補正値・計測マップ・図・設定")
    rows = [["出力", "形式", "作る画面", "主な中身"],
            ["評価結果", "Excel", "3. 結果一覧", "説明・集計・集計_統計量・Waferのベスト・ワースト・Wafer ごと・学習 Shot・処理時間・設定"],
            ["推定値", "Excel", "3. 結果一覧", "Mark ごとの座標・計測値・推定値・残差・区分・質的変数・Overlay 残差"],
            ["計測マップ", "Excel", "2. 面内推定の設定", "計測マップ（_Mark）・学習パターン・成分の差・成分の係数・統計量の差"],
            ["未知の座標の推定値・補正値", "Excel", "5. 未知の座標の推定", "推定値・説明・補正値・補正の残差・補正に使った点"],
            ["Shot 高次補正", "Excel・CSV", "6. Shot高次補正", "補正の評価・補正値・Shot ごとの補正値・項と VIF・点ごとの値など"],
            ["Mark 配置", "Excel", "7. Mark配置最適化", "説明（I 最適の式）・制御残差・配置・候補の Mark・項と VIF"],
            ["ローテの計測マップ", "Excel", "8. 計測Mapローテ", "計測マップ（_Mark）・ばらつき・説明"],
            ["ばらつき分解の表", "Excel・CSV・コピー", "1.・3.", "値（表）・説明"],
            ["図", "PNG・コピー", "各タブ", "凡例・色の目盛りも入れた 150 dpi の画像（複数の図は横に並べて 1 枚）"],
            ["設定", "JSON", "2. 面内推定の設定", "すべての設定（読み込むと同じ設定に戻る）"]]
    table(slide, CONTENT_LEFT, 1.55, [2.75, 1.75, 2.25, 5.38], rows, size=11, header_size=12, row_h=0.4, bold_first=True)
    point_bar(slide, 6.12, "評価結果・推定値・計測マップ・高次補正の点ごとの値・設定は、このアプリで読み直せる（往復できる）",
              icon="↺", h=0.72, size=13.5)

    # 9〜18 タブごと
    tab_slide(deck, "1", "「1. データ読込」― 読み込んで、データを確かめる", "s03_data_wafermap.png",
              "読み込んだ後の Wafer マップ（サンプルデータ）",
              "① ファイルを選び、座標の定義・推定する値・除外の条件を決める → ② 列の対応・座標の単位を確かめる → "
              "③「この対応で読み込む」→ 右の中のタブで Wafer マップ・Shot レイアウト・ばらつき分解などを見る。")
    tab_slide(deck, "2", "「2. 面内推定の設定」― 計測点の選び方と評価の実行", "s06_settings_points.png",
              "計測設定と計測マップ（I 最適 20 Shot）",
              "上の帯で評価を始める・設定を保存する。中のタブ「計測設定」で ① 粒度 ② アルゴリズム ③ 制約 と学習 Shot 数を決め、"
              "「計測マップを作る」で学習に使う Shot を確かめる。",
              group_titles=["上の帯（評価の実行と設定）", "計測設定（学習に使う計測点）"])

    slide = deck.body("03　機能（タブごと）", "「2. 面内推定の設定」― 比べる手法と評価・Overlay 補正")
    rows = [["系統", "選べるもの", "版"],
            ["GPR", "10 カーネル・ν を指定する Matérn・周期 × 説明変数（X,Y／X,Y,半径）× 質的変数の 6 通りの扱い", "共通"],
            ["TPS", "平滑化 GCV・なし・λ 指定 × 質的変数なし／Backfitting", "共通"],
            ["XY 多項式", "次数を指定（推奨の組み合わせは 5 次）", "共通"],
            ["RBF", "ガウス型の動径基底＋1 次多項式（GCV）", "共通"],
            ["Kriging", "通常・Universal × バリオグラム 5 種 × Backfitting", "共通"],
            ["GAM", "P-spline・ガウス過程の形状関数（REML）× 質的変数あり／なし", "共通"],
            ["Fringe Zernike", "次数 1〜7（Z64 まで）× 質的変数なし／Backfitting", "共通"],
            ["RT モデル", "次数を指定（X・Y を一緒に当てはめる）", "Pro"]]
    table(slide, CONTENT_LEFT, 1.55, [1.75, 4.95, 0.75], rows, size=11, header_size=12, row_h=0.5,
          aligns=["l", "l", "c"], bold_first=True)
    text(slide, CONTENT_LEFT, 6.12, 7.45, 0.75, "質的変数（初期設定：X は Mark 番号、Y は Scan 方向・Mark 番号）と連続値の列を説明変数に"
         "足せる。初期設定は GPR だけ、「推奨の組み合わせ」で GPR・TPS・XY 5 次。", size=11, color=MUTED)
    heading_blocks(slide, 8.4, 1.55, 4.33, feature_blocks("2", ["評価・Overlay 補正"]), size="auto", max_y=3.6)
    panel(slide, 8.4, 3.75, 4.33, 3.1, "Overlay 補正の評価",
          ["実測値で補正した残差：全 Mark の計測値で補正", "推定値で補正した残差：学習しなかった Shot は推定値で補正し、計測値に当てる",
           "推定による変化：2 つの差", "成分：Wafer（なし・1〜5 次）＋Shot 共通（なし・1 次）＋Shot ごと（なし・1 次）。Pro 版は式も入力できる"],
          fill=GOLD_TINT, size=11)

    # 12 評価の仕組みと指標
    slide = deck.body("03　機能（タブごと）", "評価の仕組みと指標 ― 学習しなかった点の計測値と比べる")
    flow = [("学習パターン", "選び方 × 学習 Shot 数で\n学習に使う点を決める", TEAL_TINT),
            ("推定", "学習点の計測値から\n手法ごとに面を推定", PURPLE_TINT),
            ("比較", "学習しなかった点の\n計測値と推定値の差", CORAL_TINT),
            ("集計", "Wafer ごとの指標を\nWafer 間で集計", GOLD_TINT)]
    for index, (heading, body, tint) in enumerate(flow):
        x = CONTENT_LEFT + index * 3.1
        box(slide, x, 1.6, 2.75, 1.35, fill=tint)
        text(slide, x + 0.15, 1.65, 2.45, 0.42, heading, size=15, color=INK, bold=True, align="c")
        text(slide, x + 0.15, 2.08, 2.45, 0.8, body, size=11.5, color=BODY, align="c")
        if index < 3:
            arrow(slide, x + 2.78, 2.27, x + 3.07, 2.27)
    rows = [["区分", "指標・集計"],
            ["推定誤差", "R²・RMSE・MAE・1 Mark の最大誤差・最小誤差（X・Y・X と Y の合計）、外周・内側の RMSE"],
            ["平均値・中央値に対する改善", "学習点の平均値（中央値）を推定値にした場合の RMSE に対する改善量 [nm]・改善率 [%]"],
            ["計測配置の良さ", "I 基準 tr(M⁻¹)・D 基準 det(M)^(−1/p)、全計測に対する I 効率・D 効率"],
            ["Overlay 補正", "OVL 残差（実測値で補正・推定値で補正）・推定による変化・増加の |平均|+3σ（X・Y）"],
            ["集計", "Wafer 間の平均・中央値・ワースト値・95%値。基準の手法との差の平均・95% 区間"]]
    table(slide, CONTENT_LEFT, 3.25, [2.9, 9.23], rows, size=11.5, header_size=12, row_h=0.47, bold_first=True)
    point_bar(slide, 6.2, "実データには真の値が無いので、計測ノイズを含む計測値と比べる（模擬データより誤差は少し大きく出る）",
              icon="!", icon_color=CORAL, h=0.68, size=13)

    tab_slide(deck, ["3", "4"], "「3. 結果一覧」と「4. Waferごとのマップ」", "s10_results_chart.png",
              "グラフ：手法 × 選び方ごとの線（横軸は学習 Shot 数）",
              "評価が終わると開く。表・グラフで手法と学習 Shot 数を比べ、計測配置・誤差の分析・補正の比較の中のタブで掘り下げる。"
              "気になる条件は「4. Waferごとのマップ」で Wafer 上の残差を見る。", image_w=5.6)
    tab_slide(deck, "5", "「5. 未知の座標の推定」― 計測していない点の値と補正値", "s15c_target_compare.png",
              "補正の比較：全計測・一部計測＋面内推定 × 基準の補正・このタブの補正",
              "点を読むか作る →「推定する」→ 補正のモデル（高次の式と項のチェック）を選ぶ →「重ね合わせ補正値を計算する」→ "
              "「全計測と比べる」で、未知の座標の推定値を足した補正で重ね合わせがよくなるかを見る → Excel に書き出す。")
    tab_slide(deck, "6", "「6. Shot高次補正」― k パラメータを求めて比べる", "s16_highorder_summary.png",
              "補正の評価（段階ごとの残差の |平均|+3σ）",
              "① 入力（計測データ・評価の推定値・未知の座標の推定値・Excel）と Wafer → ② 補正の式・くくり・Wafer 補正・Shot 共通補正・"
              "使う項（VIF）→ ③ 回帰 →「補正を計算する」→ 外れ値を除いた |平均|+3σ も見て、比べる（補正の比較・λ のスイープ・k の選定）。")
    tab_slide(deck, "7", "「7. Mark配置最適化」― 少ない Mark でどこまで補正できるか", "s18_marklayout.png",
              "制御残差推移（横軸 I 効率）",
              "入力（座標・計測データ・6. の入力・Excel）→ 必ず計測する Mark → 補正の式と回帰 → 最低数・最大数 → "
              "（乱数 Shot 生成）→「配置を最適化する」→ 推移・配置・表を見て書き出す。")
    tab_slide(deck, "8", "「8. 計測Mapローテ」― ばらつきで計測の頻度を変える", "s20_rotation_map.png",
              "優先度で作ったローテーションの計測マップ",
              "① 入力と対象 → ② ばらつきを求める（Wafer 間の 3σ）→ ③ しきい値で優先度を分けて計測マップを作る → "
              "④ FB 側と検証側に分けて検証し、条件を比べる → 計測マップを書き出す。")

    # 18 共通の機能
    slide = deck.body("03　機能（タブごと）", "共通の機能 ― メニュー・図・ヘルプ・設定ファイル")
    items = [("表示の設定", "文字の大きさ（12〜20 pt）、Scan 方向の向きと色、画面の大きさに合わせる。Pro 版はライト・ダークと"
                       "凡例の位置も。タブは業務のつながりで色分け（2〜5 青・6〜7 橙）。"),
             ("乱数の種", "計測点の選び方と Mark 配置最適化で共通の 1 つの種。同じ種なら同じ結果（評価の結果が変わる設定）。"),
             ("図の保存・コピー", "凡例・色の目盛りも入れた PNG を保存、同じ画像をクリップボードへ。PowerPoint・Teams・メールに貼れる。"),
             ("ヘルプ", "別の窓。機能編（タブごとの使い方・用語）と技術編（式・計算の方法）を左上のボタンで切り替える。"),
             ("設定ファイル", "設定を JSON に保存・読み込み。起動フォルダの既定の設定ファイルで部署の初期値をそろえる。"),
             ("進み具合の窓", "評価・推定値の計算・書き出しで出す。文の行数に合わせて高さを変え、一時中断もここから。")]
    w, h = 3.9, 2.45
    for index, (heading, body) in enumerate(items):
        color, _ = ACCENTS[index % 4]
        x = CONTENT_LEFT + (index % 3) * (w + 0.215)
        y = 1.6 + (index // 3) * (h + 0.25)
        card(slide, x, y, w, h, color, str(index + 1), heading, body, size=13)

    # 19 通常版と Pro 版
    slide = deck.body("04　版と非機能", "通常版と Pro 版 ― 通常版で使わない機能")
    rows = [["設定・機能", "通常版", "Pro 版"],
            ["比べる手法", "RT モデル以外のすべて（GPR・TPS・RBF・Kriging・GAM・XY 多項式・Fringe Zernike）", "すべて（RT モデルも）"],
            ["計測点の選び方", "Shot 単位の I 最適・ランダム", "すべて（D 最適・Sobol 列・ポアソンディスク・Excel 取込・Mark 単位も）"],
            ["Overlay 補正の成分", "組み込みの式（Wafer 成分の次数・1 次）", "「式を入力」も"],
            ["指標・横軸", "Waferベスト/ワーストは R² だけ、補正の悪化は計測 Shot 数・Mark の数", "すべて（RMSE 以降の指標、推定誤差 RMSE の横軸も）"],
            ["表示", "ライトモード、図ごとの既定の凡例の位置", "ダークモード、凡例の位置の変更も"]]
    table(slide, CONTENT_LEFT, 1.5, [2.4, 5.6, 4.13], rows, size=11.5, header_size=12.5, row_h=0.5, bold_first=True)
    items = [("起動", "MATLAB：runAlignmentEstimationAppStandard（通常版）・runAlignmentEstimationApp（Pro 版）。"
                    "通常版の窓の名前に「（通常版）」が付く。"),
             ("設定の読み込み", "通常版で Pro 版の設定・既定の設定ファイルを読むと、使えない設定を使える設定に直して知らせる。"),
             ("配布", "buildStandaloneApp(edition=\"standard\") で通常版の exe（AlignmentEstimationAppStandard）を作る。")]
    for index, (heading, body) in enumerate(items):
        color, _ = ACCENTS[index]
        card(slide, CONTENT_LEFT + index * 4.115, 4.75, 3.9, 2.1, color, str(index + 1), heading, body, size=11.5)

    # 20 非機能要件
    slide = deck.body("04　版と非機能", "非機能要件 ― 動作環境・性能・頑健性・品質")
    rows = [["区分", "要件", "実現のしかた"],
            ["動作環境", "MATLAB R2022b で確認（R2021a 以上を想定）。Toolbox 不要", "最適化・検定は自作（+optim・+stats）。exe は同じ版の MATLAB Runtime で動く"],
            ["性能", "起動・タブの切り替え・評価を軽くする", "3〜8 のタブは初めて開いたときに作る。見えていない図は開いたときに描く。"
             "候補の Shot が同じ Wafer は学習パターンを使い回す"],
            ["時間の見通し", "計算の前に目安、計算中に残り時間を出す", "推定 2 秒/条件＋学習パターンを作る時間で見積もる。実績から残りを出す"],
            ["継続性", "長い計算を止めて続きから計算できる", "一時中断・続きから再開・条件を追加して評価（済んだ組み合わせは使い回す）"],
            ["頑健性", "1 つの手法の失敗で止めない。入力の誤りは理由を出す", "失敗した行は指標を NaN、理由をメモに。注意は橙、止まるエラーは赤の文字"],
            ["使いやすさ", "画面は短い名前、詳しい説明はヘルプ", "ヘルプ（機能編・技術編）、文字の大きさ・色・凡例の設定"],
            ["セキュリティ", "外部サービス・認証情報を使わない。実データを入れない", "ネットにつながずに動く。リポジトリはサンプルデータだけ"],
            ["品質", "計算が正しいこと", "自動テスト 340 件（46 ファイル）、Python 版との照合"]]
    table(slide, CONTENT_LEFT, 1.55, [1.7, 4.6, 5.83], rows, size=11, header_size=12, row_h=0.58, bold_first=True)

    # 21 制約と注意事項
    slide = deck.body("04　版と非機能", "制約と注意事項")
    panel(slide, 0.6, 1.55, 5.95, 5.3, "使うときの注意",
          ["同じ名前の Excel を開いていると書き出せない（閉じてからやり直す）",
           "CSV は UTF-8 で保存したものを読む（Shift_JIS は文字化けのおそれ。Excel のまま読むのがよい）",
           "中断の後に評価の設定・データを変えると再開できない（「評価を始める」から）",
           "列の対応・単位・除外の条件を変えたら、もう一度「この対応で読み込む」",
           "交換法の初期配置の数を増やすと、学習パターンを作る時間がほぼ比例して増える"], size=13)
    panel(slide, 6.78, 1.55, 5.95, 5.3, "前提と確認の範囲",
          ["300 mm Wafer（有効半径 150 mm）が前提の欄がある（同心円の区切り・Wafer の外の判定）",
           "1 変数では RT モデル・Overlay 補正の評価・矢印の図を使わない",
           "評価結果の Excel だけではマップ・誤差の分布は描けない（推定値の Excel も読む）",
           "スタンドアローン版（exe）の作成と動作は、MATLAB Compiler の無い Mac では確認していない",
           "Canon・Nikon の補正の式はルールの式のまま（項・係数番号・符号を変えない）"], size=13, fill=GOLD_TINT)

    # 22 まとめ
    closing(deck, "このアプリでできること",
            [("比べて決める", "計測点の選び方・学習 Shot 数・推定の手法を、実データの指標で比べる"),
             ("補正まで見る", "推定誤差が Overlay 補正・Shot 高次補正をどれだけ悪くするかを確かめる"),
             ("計測を減らす", "Mark 配置・計測マップのローテーションで、補正できる範囲で計測を減らす"),
             ("共有する", "結果・推定値・補正値・計測マップを Excel・図で書き出し、読み直せる")],
            ["画面遷移図（PowerPoint）：想定利用ごとの画面の動き", "詳細設計書（PowerPoint）：クラス・処理・データの設計",
             f"詳細機能一覧（HTML）：全 {total} 機能の内容・操作・出力・実装・版", "README・メニュー「ヘルプ」：使い方と式の詳しい説明"])

    deck.save(output)
    return deck.page


def main():
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUTPUT
    reference = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_REFERENCE
    pages = build(output, reference)
    print(f"書き出しました：{output}（{pages} 枚）")


if __name__ == "__main__":
    main()
