"""面内推定評価ツールの画面遷移図（想定利用用途ごと、PowerPoint）を作る。

使い方：python3 build_screen_flow.py [出力 .pptx] [参照デッキ .pptx]
画面の画像は ../images（capture_screens.m で、サンプルデータを使って撮る）。
"""
from __future__ import annotations

import sys
from pathlib import Path

from deckkit import (ACCENTS, text_lines, BODY, CONTENT_LEFT, CONTENT_WIDTH, CORAL, CORAL_TINT, DEFAULT_REFERENCE, GOLD,
                     GOLD_TINT, INK, LIGHT2, LINE, MUTED, NAVY, PANEL, PURPLE, PURPLE_TINT, TEAL, TEAL_TINT, WHITE,
                     Deck, arrow, box, card, circle, closing, cover, elbow, node, panel, point_bar, screen,
                     step_circle, table, tag, text)
from features import APP_NAME, VERSION_NOTE

HERE = Path(__file__).resolve().parent
# アプリのタブの見出しの色（業務でつながるタブ：2〜5 は青、6・7 は橙。appui.Core の ESTIMATION_TAB_COLOR・CORRECTION_TAB_COLOR）
ESTIMATION_COLOR, ESTIMATION_TINT = "005CAB", "DCE8F5"
CORRECTION_COLOR, CORRECTION_TINT = "B85C00", "F8E6D3"
OTHER_COLOR, OTHER_TINT = "4A4E69", "ECEDF2"


def tab_colors(number):
    """タブの番号（1〜8）の色と淡い色（アプリの見出しの色分けと同じ）"""
    if 2 <= number <= 5:
        return ESTIMATION_COLOR, ESTIMATION_TINT
    if number in (6, 7):
        return CORRECTION_COLOR, CORRECTION_TINT
    return OTHER_COLOR, OTHER_TINT
DEFAULT_OUTPUT = HERE.parent / f"{APP_NAME}_画面遷移図.pptx"
DECK_NAME = f"{APP_NAME} 画面遷移図"


def chain(slide, steps, y=1.6, h=1.0, x0=CONTENT_LEFT, total_w=CONTENT_WIDTH, gap=0.32, size=11.5):
    """番号つきの手順の箱を横に並べ、矢印でつなぐ。steps は (見出し, 補足) の並び"""
    n = len(steps)
    w = (total_w - gap * (n - 1)) / n
    for index, (heading, note) in enumerate(steps):
        color, tint = ACCENTS[index % 4]
        x = x0 + index * (w + gap)
        box(slide, x, y, w, h, fill=tint)
        step_circle(slide, x + 0.1, y + 0.1, index + 1, color=color, d=0.36, size=11)
        heading_size = size + 1
        while heading_size > 9.5 and text_lines(heading, w - 0.65, heading_size) > 1:
            heading_size -= 0.5   # 見出しが 2 行になるときは小さくする（補足の文と重ならないように）
        text(slide, x + 0.5, y + 0.06, w - 0.55, 0.45, heading, size=heading_size, color=INK, bold=True, anchor="m")
        text(slide, x + 0.12, y + 0.5, w - 0.24, h - 0.52, note, size=size - 1.5, color=BODY)
        if index < n - 1:
            arrow(slide, x + w + 0.02, y + h / 2, x + w + gap - 0.02, y + h / 2, color=INK)


def thumbs_snake(slide, items, y1=1.62, y2=4.3, w=2.75, gap=0.38):
    """画面の画像を 4 枚ずつ 2 段に並べる（2 段目は右から左へ）。items は (画像, 番号, 説明)"""
    positions = []
    for index, (image, number, caption) in enumerate(items):
        row, col = divmod(index, 4)
        if row == 1:
            col = 3 - col
        x = CONTENT_LEFT + col * (w + gap)
        y = y1 if row == 0 else y2
        h = screen(slide, image, x, y, w)
        step_circle(slide, x - 0.1, y - 0.12, number, color=CORAL)
        text(slide, x, y + h + 0.04, w, 0.62, caption, size=10.5, color=INK)
        positions.append((x, y, h, row))
    for index in range(len(positions) - 1):
        x, y, h, row = positions[index]
        nx, ny, nh, nrow = positions[index + 1]
        if row == nrow == 0:
            arrow(slide, x + w + 0.04, y + h / 2, nx - 0.04, ny + nh / 2, color=INK, width=1.75)
        elif row == nrow == 1:
            arrow(slide, x - 0.04, y + h / 2, nx + w + 0.04, ny + nh / 2, color=INK, width=1.75)
        else:
            arrow(slide, x + w / 2, y + h + 0.66, nx + w / 2, ny - 0.14, color=INK, width=1.75)


def screen_node(slide, x, y, w, h, number, title, note, color, tint):
    box(slide, x, y, w, h, fill=tint)
    circle(slide, x + 0.12, y + 0.12, 0.42, color, number, size=13)
    text(slide, x + 0.62, y + 0.08, w - 0.7, 0.5, title, size=13, color=INK, bold=True, anchor="m")
    text(slide, x + 0.14, y + 0.58, w - 0.28, h - 0.62, note, size=9.5, color=BODY)


def build(output: Path, reference: Path):
    deck = Deck(DECK_NAME, f"{APP_NAME} 画面遷移図", reference)

    # 1 表紙
    cover(deck, "画面遷移図 ｜ 想定利用用途ごと", f"{APP_NAME}\n画面遷移図",
          "8 つのタブと別の窓を、想定利用（UC1〜UC7）の順にたどる",
          "どの画面で何を操作すると、どの画面に何が出るか、画面どうしで何を受け渡すかを、実際の画面の画像（サンプルデータ）で示す。",
          f"{VERSION_NOTE}の画面 ｜ 画像は sample_alignment.xlsx（模擬データ 5 枚）",
          image="s06_settings_points.png", image_caption="「2. 面内推定の設定」の計測設定と計測マップ")

    # 2 見方
    slide = deck.body("", "この資料の見方")
    legend = [("画面（タブ）", lambda x, y: node(slide, x, y, 1.6, 0.5, "1. データ読込", fill=TEAL_TINT, size=11, line_color=None)),
              ("別の窓・ダイアログ", lambda x, y: node(slide, x, y, 1.6, 0.5, "ヘルプの窓", fill=NAVY, color=WHITE, size=11,
                                              line_color=None)),
              ("操作で移る・データを渡す", lambda x, y: arrow(slide, x, y + 0.25, x + 1.6, y + 0.25, color=INK, width=1.75)),
              ("やり直し・戻る流れ", lambda x, y: arrow(slide, x, y + 0.25, x + 1.6, y + 0.25, color=CORAL, dashed=True,
                                               width=1.75)),
              ("手順の番号", lambda x, y: step_circle(slide, x + 0.6, y + 0.04, 1))]
    box(slide, CONTENT_LEFT, 1.55, 4.4, 5.3, fill=PANEL)
    text(slide, 0.8, 1.65, 4.0, 0.35, "記号", size=14, color=INK, bold=True)
    for index, (label, draw) in enumerate(legend):
        y = 2.15 + index * 0.9
        draw(0.85, y)
        text(slide, 2.65, y, 2.25, 0.5, label, size=12, color=BODY, anchor="m")
    rows = [["想定利用", "内容", "ページ"],
            ["画面の構成", "メインの窓・8 つのタブ・中のタブ・別の窓", "p.3"],
            ["タブ間の遷移", "画面の移り方とデータの受け渡し", "p.4–5"],
            ["UC1 手法比較の評価", "読み込み → 設定 → 評価 → 結果 → マップ（状態の遷移も）", "p.6–9"],
            ["UC2 未知の座標の推定", "点を作る → 推定 → 重ね合わせ補正値", "p.10"],
            ["UC3 Shot 高次補正", "入力 → 式・項 → 計算 → 比べる", "p.11"],
            ["UC4 Mark 配置最適化", "候補の Mark → 乱数 Shot → 配置を最適化", "p.12"],
            ["UC5 計測Mapローテ", "ばらつき → 計測マップ → FB の検証", "p.13"],
            ["UC6 計測配置の見直し", "結果から計測を足す・人の配置を取り込む", "p.14"],
            ["UC7 結果の共有", "書き出す → 別の PC で読み込む", "p.15"],
            ["共通の操作・画面一覧", "メニュー・ヘルプ・進み具合の窓、全画面の一覧", "p.16–17"]]
    table(slide, 5.25, 1.55, [2.55, 4.4, 0.93], rows, size=11, header_size=12, row_h=0.47, aligns=["l", "l", "c"],
          bold_first=True)

    # 3 画面の構成
    slide = deck.body("画面の構成", "画面の構成 ― メインの窓・8 つのタブ・中のタブ・別の窓")
    node(slide, CONTENT_LEFT, 1.5, 5.2, 0.55, f"メインの窓（{APP_NAME}）", fill=NAVY, color=WHITE, size=13, line_color=None)
    node(slide, 6.0, 1.5, 3.25, 0.55, "メニュー「設定」：色・文字・凡例・Scan・画面・乱数の種", fill=PANEL, size=10, line_color=None)
    node(slide, 9.4, 1.5, 3.33, 0.55, "メニュー「ヘルプ」→ ヘルプの窓", fill=PANEL, size=10, line_color=None)
    columns = [
        ("1. データ読込", ["② 列の対応・座標の単位", "Wafer マップ", "Shot レイアウト", "Shot 重ね合わせ", "質的変数の交互作用", "ばらつき分解（図・表）"]),
        ("2. 面内推定の設定", ["上の帯：評価を始める・設定", "計測設定（計測マップ：成分の差・統計量の差）", "比べる手法", "評価・Overlay 補正"]),
        ("3. 結果一覧", ["［表・グラフ］表・グラフ・基準の手法との比較・Waferベスト/ワースト",
                       "［計測配置］計測を足す場所・計測配置の比較・補正の悪化",
                       "［誤差の分析］推定値と誤差の分布・残差の箱ひげ図・推定値と実測値の散布図・残差と説明変数・分布の比較・処理時間の内訳",
                       "［補正の比較］実測値と推定値の補正・補正残差のばらつき分解"]),
        ("4. Waferごとのマップ", ["マップ（1 つの条件）", "並べて比べる条件", "Shot スタックマップ"]),
        ("5. 未知の座標の推定", ["図", "推定値の表", "補正のモデル（項のチェック）", "補正値", "補正残差のマップ", "補正の比較"]),
        ("6. Shot高次補正", ["［入力と項］Excel・CSV の列・使う項と VIF・k の選定",
                          "［結果］補正の評価・マップ・ヒストグラム・補正値テーブル・書き出し",
                          "［比べる］結果の履歴・他の Wafer の補正・補正の比較・2 つの条件を並べる・λ・c のスイープ・Wafer の比較"]),
        ("7. Mark配置最適化", ["Excel・CSV の列", "候補の Mark", "使う項と VIF", "乱数 Shot 生成", "制御残差推移", "配置", "表"]),
        ("8. 計測Mapローテ", ["ばらつき", "計測マップ", "振り分けの比較", "FB の検証（補正残差・FB 側と計測マップ・条件の比較）", "Excel・CSV の列"]),
    ]
    widths = [1.22, 1.22, 2.15, 1.22, 1.22, 2.15, 1.22, 1.22]
    gap = (CONTENT_WIDTH - sum(widths)) / 7
    x = CONTENT_LEFT
    for index, ((title, items), w) in enumerate(zip(columns, widths)):
        color, tint = tab_colors(index + 1)   # アプリと同じ色分け
        arrow(slide, x + w / 2, 2.05, x + w / 2, 2.3, color=MUTED, head=False)
        box(slide, x, 2.3, w, 0.62, fill=color)
        text(slide, x + 0.04, 2.3, w - 0.08, 0.62, title, size=10.5, color=WHITE, bold=True, align="c", anchor="m")
        box(slide, x, 2.98, w, 3.05, fill=tint)
        text(slide, x + 0.06, 3.04, w - 0.12, 2.95, items, size=9, color=INK, bullets=True, space_after=2)
        x += w + gap
    text(slide, CONTENT_LEFT, 6.12, 2.3, 0.3, "別の窓・ダイアログ", size=11, color=MUTED, bold=True)
    text(slide, 3.0, 6.12, 9.7, 0.3, "見出しの色はアプリのタブの色分け：2〜5（面内推定の流れ）は青、6・7（Shot 内の補正）は橙",
         size=10, color=MUTED, align="r")
    windows = ["ヘルプ（機能編・技術編）", "記録を見る（評価の記録）", "進み具合（一時中断）", "ファイルを選ぶ・保存する", "知らせ（注意・エラー）"]
    for index, label in enumerate(windows):
        node(slide, CONTENT_LEFT + index * 2.45, 6.42, 2.3, 0.45, label, fill=NAVY, color=WHITE, size=10, line_color=None)

    # 4 タブ間の遷移
    slide = deck.body("タブ間の遷移", "タブ間の遷移 ― 主な流れと、画面どうしで渡すもの")
    xs = [0.75, 3.85, 6.95, 10.05]
    w, h = 2.6, 1.0
    nodes = {
        "1": (xs[0], 1.6, "データ読込", "読み込んだデータは 2〜8 のすべてで使う"),
        "2": (xs[1], 1.6, "面内推定の設定", "計測点・手法・評価の条件、評価の実行"),
        "3": (xs[2], 1.6, "結果一覧", "表・グラフ・計測配置・誤差・補正"),
        "4": (xs[3], 1.6, "Waferごとのマップ", "1 つの条件の残差、条件を並べる"),
        "5": (xs[2], 3.65, "未知の座標の推定", "補正のモデルは 2. と同じ設定"),
        "6": (xs[3], 3.65, "Shot高次補正", "入力：1 の計測データ・3 の評価の推定値・5 の推定値・Excel"),
        "7": (xs[3], 5.65, "Mark配置最適化", "入力：座標・1 の計測データ・6 の入力"),
        "8": (xs[1], 5.65, "計測Mapローテ", "入力：1・3・5・6 の Excel、補正：2 か 6"),
    }
    for key, (x, y, title, note) in nodes.items():
        color, tint = tab_colors(int(key))   # アプリと同じ色分け
        screen_node(slide, x, y, w, h, key, title, note, color, tint)
    arrow(slide, xs[0] + w + 0.02, 2.1, xs[1] - 0.02, 2.1, color=INK, width=1.75)
    tag(slide, xs[0] + w - 0.3, 1.3, 1.1, "データ", size=9.5)
    arrow(slide, xs[1] + w + 0.02, 2.1, xs[2] - 0.02, 2.1, color=INK, width=1.75)
    tag(slide, xs[1] + w - 0.45, 1.3, 1.4, "評価が終わると開く", size=9.5)
    arrow(slide, xs[2] + w + 0.02, 2.1, xs[3] - 0.02, 2.1, color=INK, width=1.75)
    tag(slide, xs[2] + w - 0.3, 1.3, 1.1, "条件を選ぶ", size=9.5)
    elbow(slide, [(7.25, 2.6), (7.25, 3.0), (6.15, 3.0), (6.15, 2.62)], color=CORAL, dashed=True, width=1.5)
    tag(slide, 5.6, 3.02, 2.2, "計測を足す場所 → 必ず計測", size=9.5, color=CORAL)
    arrow(slide, 8.6, 2.6, 8.6, 3.63, color=INK, width=1.5)
    tag(slide, 8.65, 2.95, 1.3, "学習パターン", size=9.5, align="l")
    arrow(slide, xs[2] + w + 0.02, 4.15, xs[3] - 0.02, 4.15, color=INK, width=1.5)
    tag(slide, xs[2] + w - 0.2, 3.85, 0.9, "推定値", size=9.5)
    arrow(slide, 11.35, 4.65, 11.35, 5.63, color=INK, width=1.5)
    tag(slide, 11.4, 4.95, 1.4, "入力・式を写す", size=9.5, align="l")
    elbow(slide, [(7.4, 4.65), (7.4, 6.15), (6.47, 6.15)], color=INK, width=1.5)
    tag(slide, 6.45, 5.35, 1.0, "推定値（3・5）", size=9.5, align="l")
    arrow(slide, 5.15, 5.63, 5.15, 2.62, color=CORAL, dashed=True, width=1.5)
    tag(slide, 3.25, 4.0, 1.85, "計測マップの Excel → Excel 取込", size=9.5, color=CORAL, align="r", h=0.5)
    box(slide, 0.75, 3.65, 2.35, 1.85, fill=PANEL)
    text(slide, 0.88, 3.72, 2.1, 1.75, ["実線：操作で移る・データを渡す", "破線：やり直し・戻る流れ", "メニュー「設定」「ヘルプ」は"
                                         "どの画面からも使える"], size=9.5, color=BODY, bullets=True, space_after=2)

    # 5 データの受け渡し
    slide = deck.body("タブ間の遷移", "画面どうしで受け渡すもの")
    rows = [["渡す元", "渡すもの", "受け取る画面", "使い方"],
            ["1. データ読込", "前処理した計測データ", "2〜8 のすべて", "評価・推定・補正・ばらつきの入力"],
            ["2. 面内推定の設定", "評価の結果", "3. 結果一覧・4. マップ", "評価が終わると「3. 結果一覧」を開く"],
            ["3. 結果一覧", "計測を足す場所（候補の Shot・Mark）", "2. 面内推定の設定", "「必ず計測の欄に入れる」で必ず計測する shotNo・Mark に足す"],
            ["3. 結果一覧", "評価の学習パターン", "5. 未知の座標の推定", "学習データに選ぶ（その Wafer の学習 Shot だけで推定）"],
            ["3.・5.", "評価の推定値・未知の座標の推定値", "6.・8.", "Shot 高次補正の入力、ばらつき・FB の入力"],
            ["2. 面内推定の設定", "Overlay 補正のモデル（基準の補正）", "5.・8.", "補正の比較の基準、FB の補正のモデル"],
            ["6. Shot高次補正", "入力のデータ・補正の式・回帰", "7. Mark配置最適化", "入力「6. の入力」、「6. の式を写す」"],
            ["6. Shot高次補正", "Shot 高次補正の設定", "8. 計測Mapローテ", "FB の補正のモデル「6. の Shot 高次補正」"],
            ["6. Shot高次補正", "読み込んだ Excel・CSV", "8. 計測Mapローテ", "入力「6. Shot高次補正で読み込んだデータ」"],
            ["8. 計測Mapローテ", "計測マップの Excel", "2. 面内推定の設定", "計測点の選び方「Excel 取込」で読む（Pro 版）"],
            ["6. Shot高次補正", "点ごとの値（計測データの形）", "1.・6.", "書き出したファイルをそのまま読み直す"]]
    table(slide, CONTENT_LEFT, 1.5, [2.2, 3.2, 2.55, 4.18], rows, size=10.5, header_size=11.5, row_h=0.43, bold_first=True)

    # 6 UC1 全体
    slide = deck.body("UC1　手法比較の評価", "UC1 手法比較の評価 ― 読み込みから結果のマップまで")
    thumbs_snake(slide, [
        ("s02_data_mapping.png", 1, "1. データ読込：ファイルを選び、列の対応・単位を確かめる"),
        ("s03_data_wafermap.png", 2, "「この対応で読み込む」→ Wafer マップで確かめる"),
        ("s06_settings_points.png", 3, "2. 計測設定：選び方・学習 Shot 数、計測マップ"),
        ("s07_settings_methods.png", 4, "比べる手法：推奨の組み合わせなど"),
        ("s08_settings_overlay.png", 5, "評価・Overlay 補正 →「評価を始める」"),
        ("s09_results_table.png", 6, "終わると 3. 結果一覧（表）を開く"),
        ("s10_results_chart.png", 7, "グラフ・計測配置・誤差の分析で比べる"),
        ("s13_map.png", 8, "4. Waferごとのマップで残差を見る"),
    ])

    # 7 UC1 手順
    slide = deck.body("UC1　手法比較の評価", "UC1 の手順 ― 操作と、次に出る画面")
    rows = [["手順", "画面", "操作", "結果・次の画面"],
            ["1", "1. データ読込", "「ファイルを選ぶ…」、座標の定義・推定する値・除外の条件", "② 列の対応・座標の単位の表"],
            ["2", "1. データ読込", "列の対応・単位を確かめて「③ この対応で読み込む」", "読み込み結果、Wafer マップのタブを開く"],
            ["3", "1. データ読込", "Shot レイアウト・Shot 重ね合わせ・ばらつき分解を見る", "必要なら Scan 方向・除外を直して読み直す"],
            ["4", "2. 計測設定", "粒度・アルゴリズム・制約・学習 Shot 数・必ず計測する Shot", "上の帯に計算する組み合わせと時間の目安"],
            ["5", "2. 計測設定", "「計測マップを作る」、図のクリックで必ず計測・計測しない", "計測マップ・成分の差・統計量の差"],
            ["6", "2. 比べる手法", "手法・カーネル・質的変数を選ぶ（推奨の組み合わせ）", "組み合わせの数と目安が変わる"],
            ["7", "2. 評価・Overlay 補正", "外周の半径・異常値の除外・Overlay 補正の成分", "—"],
            ["8", "2. 上の帯", "「評価を始める」（必要なら「一時中断」）", "進み具合の窓 → 3. 結果一覧"],
            ["9", "3. 結果一覧", "指標・集計を選び、表・グラフ・分析のタブを見る、書き出す", "Excel、図の PNG"],
            ["10", "4. Waferごとのマップ", "Wafer・学習パターン・手法を選ぶ、条件を足して並べる", "計測値・推定値・残差のマップ"]]
    table(slide, CONTENT_LEFT, 1.55, [0.7, 2.25, 5.3, 3.88], rows, size=11, header_size=12, row_h=0.46,
          aligns=["c", "l", "l", "l"])

    # 8 UC1 状態の遷移
    slide = deck.body("UC1　手法比較の評価", "評価の状態の遷移 ― 中断・再開・条件の追加・読み込んだ結果")
    states = {"start": (0.75, 1.75, "起動した直後", "データ・結果なし"),
              "data": (3.75, 1.75, "データあり", "評価の前"),
              "running": (6.75, 1.75, "評価中", "進み具合の窓"),
              "done": (9.95, 1.75, "評価済み", "結果一覧・マップ"),
              "paused": (6.75, 4.05, "一時中断", "途中までの結果を出す"),
              "imported": (0.75, 4.05, "読み込んだ結果", "表・グラフ・基準との比較"),
              "imported2": (3.75, 4.05, "＋推定値の Excel", "マップ・誤差の分布も")}
    sw, sh = 2.4, 1.0
    for index, (key, (x, y, title, note)) in enumerate(states.items()):
        color, tint = ACCENTS[index % 4]
        box(slide, x, y, sw, sh, fill=tint, line=color, line_width=1.25)
        text(slide, x, y + 0.08, sw, 0.45, title, size=14, color=INK, bold=True, align="c", anchor="m")
        text(slide, x, y + 0.52, sw, 0.4, note, size=10.5, color=BODY, align="c", anchor="m")
    arrow(slide, 3.17, 2.25, 3.73, 2.25, color=INK, width=1.75)
    tag(slide, 2.35, 1.42, 2.2, "この対応で読み込む", size=9.5)
    arrow(slide, 6.17, 2.25, 6.73, 2.25, color=INK, width=1.75)
    tag(slide, 5.35, 1.42, 2.2, "評価を始める", size=9.5)
    arrow(slide, 9.17, 2.1, 9.93, 2.1, color=INK, width=1.75)
    tag(slide, 8.6, 1.42, 1.9, "すべて計算した", size=9.5)
    arrow(slide, 9.93, 2.5, 9.17, 2.5, color=CORAL, dashed=True, width=1.5)
    tag(slide, 9.0, 2.8, 2.6, "条件を追加して評価（評価中に戻る）", size=9.5, color=CORAL)
    arrow(slide, 7.7, 2.77, 7.7, 4.03, color=INK, width=1.5)
    tag(slide, 6.55, 3.2, 1.1, "一時中断", size=9.5, align="r")
    arrow(slide, 8.2, 4.03, 8.2, 2.77, color=CORAL, dashed=True, width=1.5)
    tag(slide, 8.25, 3.2, 1.4, "続きから再開", size=9.5, color=CORAL, align="l")
    elbow(slide, [(1.95, 2.77), (1.95, 4.03)], color=INK, width=1.5)
    tag(slide, 2.0, 3.2, 1.6, "結果を読み込む…", size=9.5, align="l")
    arrow(slide, 3.17, 4.55, 3.73, 4.55, color=INK, width=1.5)
    tag(slide, 2.55, 5.1, 1.9, "推定値の Excel を読み込む…", size=9.5)
    panel(slide, 9.55, 4.05, 3.18, 2.8, "再開できないとき",
          ["中断の後に評価の設定・データを変えたとき（「評価を始める」から）",
           "計測ファイルを読み直すと、結果は消えて「データあり」に戻る",
           "表示の設定（Scan 方向の向き・色）と 6. の設定は変えても再開できる",
           "追加の評価で変えられないのは推定の結果を変える設定"], fill=GOLD_TINT, size=10.5, heading_size=13)
    panel(slide, 0.75, 5.4, 8.4, 1.45, "読み込んだ結果で使えるもの",
          ["評価結果の Excel だけ：表・グラフ・基準の手法との比較（計測ファイルは不要）",
           "推定値の Excel も読むと：Wafer ごとのマップ・推定値と誤差の分布・散布図・分布の比較"], size=10.5, heading_size=13)

    # 9 UC1 結果の見方
    slide = deck.body("UC1　手法比較の評価", "「3. 結果一覧」の中の移り方 ― 4 つのまとまりと絞り込み")
    chain(slide, [("表・グラフ", "表・グラフ・基準の手法との比較・Waferベスト/ワースト"),
                  ("計測配置", "計測を足す場所・計測配置の比較・補正の悪化"),
                  ("誤差の分析", "誤差の分布・箱ひげ図・散布図・残差と説明変数・分布の比較・処理時間"),
                  ("補正の比較", "実測値と推定値の補正・補正残差のばらつき分解")], y=1.55, h=1.15)
    screen(slide, "s11_results_analysis.png", CONTENT_LEFT, 3.0, 5.9, "誤差の分析：推定値と誤差の分布")
    screen(slide, "s12_results_degradation.png", 6.83, 3.0, 5.9, "計測配置：補正の悪化")
    box(slide, CONTENT_LEFT, 6.45, CONTENT_WIDTH, 0.42, fill=PANEL)
    text(slide, 0.8, 6.45, 11.8, 0.42, "上の「評価点の絞り込み」（半径・Shot の条件）は、表・グラフ・マップのすべてに効く。"
         "右上の 1 段目は書き出し、2 段目は読み込み。", size=11, color=INK, anchor="m")

    # 10 UC2
    slide = deck.body("UC2　未知の座標の推定", "UC2 未知の座標の推定 ― 推定値を足して高次の補正を見積もる")
    chain(slide, [("点を決める", "Excel・CSV を読む、全 Shot に置く・格子で置く"),
                  ("推定する", "Wafer・学習データ・手法。外挿・Wafer の外を知らせる"),
                  ("補正のモデル", "高次の式を選び、項をチェックで選ぶ"),
                  ("補正値を計算", "実測値＋推定値＋未知の座標で当てはめる"),
                  ("全計測と比べる", "①〜④ の補正後の |平均|+3σ を比べる")], y=1.55, h=1.15)
    screen(slide, "s15b_target_model.png", CONTENT_LEFT, 3.0, 5.9, "補正のモデル：式と項のチェック（0次・1次は外せない）")
    screen(slide, "s15c_target_compare.png", 6.83, 3.0, 5.9, "補正の比較：① 全計測・② 一部＋推定（基準）、③・④ 未知の座標を足す")
    box(slide, CONTENT_LEFT, 6.45, CONTENT_WIDTH, 0.42, fill=CORAL_TINT)
    text(slide, 0.8, 6.45, 11.8, 0.42, "④ が ② より小さければ、未知の座標の推定値を足した高次の補正で、一部計測でも重ね合わせがよくなる見込み。"
         "補正残差のマップは並べる・Shot スタックマップ・円も。", size=11, color=INK, anchor="m")

    # 11 UC3
    slide = deck.body("UC3　Shot 高次補正", "UC3 Shot 高次補正 ― 計算して、比べて、決める")
    chain(slide, [("入力と Wafer", "計測データ・評価の推定値・5 の推定値・Excel"),
                  ("式・くくり・項", "補正の式・くくり・Wafer 補正・Shot 共通・VIF"),
                  ("回帰", "最小二乗・Huber・LAD と正則化（L2・L1）"),
                  ("補正を計算する", "補正の評価・マップ・補正値テーブル"),
                  ("比べて決める", "補正の比較・λ のスイープ・k の選定 → 設定に戻す")], y=1.55, h=1.15)
    screen(slide, "s16_highorder_summary.png", CONTENT_LEFT, 3.0, 5.9, "結果：補正の評価（段階ごとの残差）")
    screen(slide, "s17_highorder_map.png", 6.83, 3.0, 5.9, "結果：マップ（高次補正の残差）")
    box(slide, CONTENT_LEFT, 6.45, CONTENT_WIDTH, 0.42, fill=PANEL)
    text(slide, 0.8, 6.45, 11.8, 0.42, "補正の評価には外れ値（中央値 ± n × MAD の外）を除いた |平均|+3σ も出る。設定・入力を変えると「計算し直してください」と出す。",
         size=11, color=INK, anchor="m")

    # 12 UC4
    slide = deck.body("UC4　Mark 配置最適化", "UC4 Mark 配置最適化 ― Mark の数ごとの配置と制御残差")
    chain(slide, [("候補の Mark", "格子で置く・計測データ・6 の入力・Excel"),
                  ("必ず計測", "表のチェック・図のクリック"),
                  ("式と回帰", "補正の式・VIF・6 の式を写す"),
                  ("乱数 Shot 生成", "実測値が無いときの形（最大 1000）"),
                  ("配置を最適化", "Mark の数ごとに I 最適で選ぶ"),
                  ("結果と書き出し", "推移・配置・表、Excel")], y=1.55, h=1.15, size=11)
    screen(slide, "s18_marklayout.png", CONTENT_LEFT, 3.0, 7.0, "制御残差推移（格子 5 × 7 の候補、乱数の Shot 50 通り）")
    panel(slide, 7.95, 3.0, 4.78, 3.85, "見方と注意",
          ["横軸は I 効率・I 基準・Mark の数・D 効率・D 基準から選ぶ", "★ は計測できる Mark をすべて計測したとき",
           "「配置」で Mark の数を選ぶと、計測する Mark と制御残差のスタックマップ", "計算の後に入力・候補・設定を変えると「計算し直してください」",
           "進み具合の窓の「止める」で、済んだ数までの結果を出す"], size=11, heading_size=13)

    # 13 UC5
    slide = deck.body("UC5　計測Mapローテ", "UC5 計測Mapローテ ― ばらつきで計測の頻度を変えて検証する")
    chain(slide, [("入力と対象", "計測データ・推定値・Excel、Operation・装置"),
                  ("ばらつき", "Wafer 間の 3σ（X・Y・|v|）"),
                  ("優先度と計測マップ", "しきい値で分け、M 枚のマップに振り分け"),
                  ("FB の検証", "FB 側の補正値を検証側に当てる"),
                  ("比べて書き出す", "条件の比較 → 計測マップの Excel")], y=1.55, h=1.15)
    for index, (image, caption) in enumerate([("s19_rotation_spread.png", "ばらつき（3σ の分布）"),
                                              ("s20_rotation_map.png", "計測マップ（優先度で振り分け）"),
                                              ("s21_rotation_feedback.png", "FB の検証（補正残差）")]):
        screen(slide, image, CONTENT_LEFT + index * 4.1, 3.0, 3.93, caption)
    box(slide, CONTENT_LEFT, 5.6, CONTENT_WIDTH, 1.25, fill=PANEL)
    text(slide, 0.8, 5.65, 11.8, 1.15, ["書き出した計測マップは「2. 面内推定の設定」の計測点の選び方「Excel 取込」で読み、"
                                         "推定の評価に使える（UC6）。",
                                         "振り分けの比較で、I 最適・D 最適・ポアソンディスク・ランダム・表の順をマップ間の KL・最大の空白などで比べられる。"],
         size=11, color=INK, bullets=True, space_after=3)

    # 14 UC6
    slide = deck.body("UC6　計測配置の見直し", "UC6 計測配置の見直し ― 結果から計測を足す")
    loop = [(1.0, 1.75, "評価する", "2. 評価を始める"), (4.55, 1.75, "誤差の大きい所を見る", "3. 計測を足す場所"),
            (8.1, 1.75, "必ず計測に入れる", "「必ず計測の欄に入れる」"), (8.1, 4.1, "計測マップで確かめる", "2. 計測マップ"),
            (1.0, 4.1, "評価し直す", "評価を始める・条件を追加")]
    for index, (x, y, title, note) in enumerate(loop):
        color, tint = ACCENTS[index % 4]
        box(slide, x, y, 3.0, 1.15, fill=tint)
        circle(slide, x + 0.12, y + 0.12, 0.4, color, str(index + 1), size=12)
        text(slide, x + 0.6, y + 0.08, 2.35, 0.5, title, size=14, color=INK, bold=True, anchor="m")
        text(slide, x + 0.6, y + 0.6, 2.35, 0.45, note, size=11, color=BODY, anchor="m")
    arrow(slide, 4.02, 2.32, 4.53, 2.32, color=INK, width=1.75)
    arrow(slide, 7.57, 2.32, 8.08, 2.32, color=INK, width=1.75)
    arrow(slide, 9.6, 2.92, 9.6, 4.08, color=INK, width=1.75)
    arrow(slide, 8.08, 4.67, 4.02, 4.67, color=INK, width=1.75)
    arrow(slide, 2.5, 4.08, 2.5, 2.92, color=CORAL, dashed=True, width=1.75)
    panel(slide, 4.55, 3.55, 3.0, 2.0, "人・ローテの配置",
          ["Excel にパターン・優先順を書く", "8. の計測マップを書き出す", "→ 2.「Excel 取込」で読む"], fill=PURPLE_TINT, size=10.5,
          heading_size=12.5)
    arrow(slide, 6.05, 5.57, 6.05, 5.95, color=PURPLE, width=1.5, head=False)
    elbow(slide, [(6.05, 5.95), (2.5, 5.95), (2.5, 5.27)], color=PURPLE, width=1.5)
    box(slide, 8.1, 5.6, 4.63, 1.27, fill=PANEL)
    text(slide, 8.25, 5.65, 4.35, 1.17, ["計測配置の比較で、選び方どうし（I 最適・人の配置など）を比べる",
                                          "足した場所を計測したときの推定になる"], size=10.5, color=INK, bullets=True, space_after=2)

    # 15 UC7
    slide = deck.body("UC7　結果の共有", "UC7 結果の共有 ― 書き出して、別の PC で読み込む")
    box(slide, CONTENT_LEFT, 1.6, 3.6, 4.2, fill=TEAL_TINT)
    text(slide, 0.8, 1.7, 3.2, 0.4, "書き出す PC", size=15, color=INK, bold=True)
    text(slide, 0.8, 2.2, 3.2, 3.4, ["3.「結果を Excel に書き出す…」", "3.「推定値を Excel に書き出す…」（範囲を選ぶ）",
                                      "図：「図を画像で保存…」「図をコピー」", "設定：「設定を保存…」"], size=12, color=BODY, bullets=True,
         space_after=4)
    files = ["評価結果.xlsx", "推定値.xlsx", "図.png", "設定.json"]
    for index, label in enumerate(files):
        node(slide, 4.75, 1.75 + index * 1.0, 2.2, 0.62, label, fill=WHITE, size=12)
        arrow(slide, 4.22, 2.06 + index * 1.0, 4.73, 2.06 + index * 1.0, color=INK)
        arrow(slide, 6.97, 2.06 + index * 1.0, 7.48, 2.06 + index * 1.0, color=INK)
    box(slide, 7.5, 1.6, 5.23, 4.2, fill=PURPLE_TINT)
    text(slide, 7.7, 1.7, 4.8, 0.4, "受け取る PC（計測ファイルは不要）", size=15, color=INK, bold=True)
    text(slide, 7.7, 2.2, 4.85, 3.4, ["3.「結果を読み込む…」→ 表・グラフ・基準の手法との比較",
                                       "3.「推定値の Excel を読み込む…」→ マップ・誤差の分布・散布図・分布の比較",
                                       "図は PowerPoint・メールに貼る", "2.「設定を読み込む…」→ 同じ条件で評価し直す"], size=12, color=BODY,
         bullets=True, space_after=4)
    point_bar(slide, 6.05, "読み込んだ推定値はもう一度書き出せない（元のファイルを使う）。計測ファイルを読み直すと読み込んだ結果は消える",
              icon="!", icon_color=CORAL, h=0.75, size=12.5)

    # 16 共通の操作
    slide = deck.body("共通の操作", "どの画面からも使う操作 ― メニュー・ヘルプ・進み具合の窓")
    screen(slide, "s22_help.png", CONTENT_LEFT, 1.55, 5.2, "ヘルプの窓（機能編・技術編を左上で切り替える）")
    items = [("メニュー「設定」", "文字の大きさ、Scan 方向の向きと色、画面の大きさに合わせる、乱数の種（Pro 版はライト・ダーク、凡例の位置も）"),
             ("図の右クリック（Pro 版）", "その図だけの凡例の位置を選ぶ（すべての図の設定に従う、で戻す）"),
             ("進み具合の窓", "評価・推定値の計算・書き出しで出る。「一時中断」（× も同じ）で途中までの結果を残す"),
             ("知らせ", "注意（計算はできる）は橙、処理が止まるエラーは赤の文字か知らせの窓。理由と直し方を書く")]
    for index, (heading, body) in enumerate(items):
        color, _ = ACCENTS[index % 4]
        card(slide, 6.1, 1.55 + index * 1.33, 6.63, 1.2, color, str(index + 1), heading, body, size=11, heading_size=13)

    # 17 画面一覧
    slide = deck.body("画面一覧", "画面一覧 ― 主な操作と移り先")
    rows = [["ID", "画面", "主な操作", "主な移り先・受け渡し"],
            ["G1", "1. データ読込", "ファイルを選ぶ・この対応で読み込む・データの確認", "2〜8（データ）"],
            ["G2", "2. 面内推定の設定", "計測点・手法・評価の条件、計測マップ、評価を始める", "G3（評価が終わると開く）、W3"],
            ["G3", "3. 結果一覧", "指標・集計、表・グラフ・分析、書き出し・読み込み", "G4、G2（計測を足す）、G5・G8（推定値）"],
            ["G4", "4. Waferごとのマップ", "条件を選ぶ・並べる・Shot スタックマップ", "—"],
            ["G5", "5. 未知の座標の推定", "点を作る・推定する・補正のモデル・補正値・全計測と比べる", "G6・G8（推定値）"],
            ["G6", "6. Shot高次補正", "入力・式・回帰、補正を計算する、比べる、書き出す", "G7（入力・式）、G8（補正・Excel）"],
            ["G7", "7. Mark配置最適化", "候補の Mark・乱数 Shot・配置を最適化・書き出す", "—"],
            ["G8", "8. 計測Mapローテ", "ばらつき・計測マップ・FB の検証・書き出す", "G2（Excel 取込）"],
            ["W1", "ヘルプの窓", "機能編・技術編の切り替え", "メニュー「ヘルプ」から"],
            ["W2", "記録を見る", "評価の記録の全文を見る", "G2 の「記録を見る…」から"],
            ["W3", "進み具合の窓", "一時中断（止める）", "計算が終わると閉じる"],
            ["W4", "ファイルの選択・保存", "読む・書くファイルを選ぶ", "各画面の「…」のボタンから"]]
    table(slide, CONTENT_LEFT, 1.55, [0.75, 2.6, 4.9, 3.88], rows, size=11, header_size=12, row_h=0.41,
          aligns=["c", "l", "l", "l"], bold_first=True)

    # 18 まとめ
    closing(deck, "画面の流れの要点",
            [("左から順に", "1 → 2 → 3 → 4 が基本の流れ。評価が終わると結果一覧を開く"),
             ("道具のタブ", "5〜8 は目的ごとの道具。1 のデータと、3・5・6 の結果を受け取って使う"),
             ("やり直しの流れ", "計測を足す・配置を取り込む・条件を足して評価し直すループがある"),
             ("止めても続く", "一時中断・続きから再開・結果の読み込みで、作業を分けられる")],
            ["機能仕様書（PowerPoint）：各画面の機能と入出力", "詳細設計書（PowerPoint）：画面と計算の作り",
             "詳細機能一覧（HTML）：画面の欄・ボタンごとの機能", "メニュー「ヘルプ」の機能編：タブごとの使い方"])

    deck.save(output)
    return deck.page


def main():
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUTPUT
    reference = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_REFERENCE
    pages = build(output, reference)
    print(f"書き出しました：{output}（{pages} 枚）")


if __name__ == "__main__":
    main()
