"""面内推定評価ツールの詳細設計書（PowerPoint）を作る。

使い方：python3 build_detailed_design.py [出力 .pptx] [参照デッキ .pptx]
ファイルの行数・関数の数は、作るときに matlab_app のコードから数える（コードを直しても数が古くならないように）。
"""
from __future__ import annotations

import sys
from pathlib import Path

from deckkit import (ACCENTS, BODY, CONTENT_LEFT, CONTENT_WIDTH, CORAL, CORAL_TINT, DEFAULT_REFERENCE, GOLD,
                     GOLD_TINT, INK, LINE, MUTED, NAVY, NAVY_PANEL, PANEL, PURPLE, PURPLE_TINT, TEAL, TEAL_TINT, WHITE,
                     Deck, agenda, arrow, box, card, circle, closing, cover, elbow, heading_blocks, node, panel,
                     point_bar, table, tag, text)
from features import APP_NAME, VERSION_NOTE

HERE = Path(__file__).resolve().parent
APP_ROOT = HERE.parent.parent.parent   # matlab_app
DEFAULT_OUTPUT = HERE.parent / f"{APP_NAME}_詳細設計書.pptx"
DECK_NAME = f"{APP_NAME} 詳細設計書"
TAB_FILES = [("Core.m", "共通：プロパティ・定数、起動（startApp）、タブを作る（ensureTab）、図の保存・コピー"),
             ("DataTab.m", "1. データ読込"), ("SettingsTab.m", "2. 面内推定の設定（計測点・手法・評価・Overlay の欄）"),
             ("RunTab.m", "2. の上の帯（評価の実行・中断・再開・条件の追加）と計測マップ"),
             ("ResultsTab.m", "3. 結果一覧"), ("MapTab.m", "4. Waferごとのマップ"), ("TargetTab.m", "5. 未知の座標の推定"),
             ("HighOrderTab.m", "6. 入力・式・計算・評価・マップ・補正値"),
             ("HighOrderCompareTab.m", "6. 補正の比較・2 つの条件・Wafer の比較・項の組み合わせ"),
             ("HighOrderAnalysisTab.m", "6. ヒストグラム・書き出し"), ("HighOrderSweepTab.m", "6. λ・c のスイープ"),
             ("HighOrderHistoryTab.m", "6. k の選定・結果の履歴・他の Wafer の補正"),
             ("MarkLayoutTab.m", "7. Mark配置最適化"), ("RotationTab.m", "8. 計測Mapローテ"),
             ("Display.m", "メニュー「ヘルプ」と表示の設定（色・文字・凡例・画面の大きさ）"),
             ("ProgressWindow.m", "計算中の進み具合の窓")]


def line_count(path: Path) -> int:
    with open(path, encoding="utf-8") as handle:
        return sum(1 for _ in handle)


def code_numbers():
    appui = {name: line_count(APP_ROOT / "+appui" / name) for name, _ in TAB_FILES}
    alignest_files = sorted((APP_ROOT / "+alignest").rglob("*.m"))
    packages = {}
    for path in alignest_files:
        package = path.parent.name if path.parent.name != "+alignest" else "+alignest"
        packages[package] = packages.get(package, 0) + 1
    tests = sorted((APP_ROOT / "tests").glob("Test*.m"))
    return {"appui": appui, "alignest_files": len(alignest_files),
            "alignest_lines": sum(line_count(p) for p in alignest_files), "packages": packages, "test_files": len(tests)}


def build(output: Path, reference: Path):
    numbers = code_numbers()
    deck = Deck(DECK_NAME, f"{APP_NAME} 詳細設計書", reference)

    # 1 表紙
    cover(deck, "詳細設計書 ｜ MATLAB アプリ", f"{APP_NAME}\n詳細設計書",
          "画面（+appui）と計算（+alignest）の作り、データ・設定・ファイルの形",
          "起動の手順、タブの作り方、評価の処理の流れ、各計算の関数、設定とファイル、性能・版・テスト・配布の設計をまとめる。保守する人向け。",
          f"{VERSION_NOTE}のコード ｜ MATLAB R2022b・Toolbox 不要",
          image="s16_highorder_summary.png", image_caption="「6. Shot高次補正」の補正の評価")

    # 2 構成
    agenda(deck, "", "この資料の構成",
           "ゴール：どこに何が書いてあり、処理がどの順で動くかを追って、安全に直せる状態にする",
           [("構成", "レイヤー、クラスの構成、ファイルと責務", "p.3–5"),
            ("画面の制御", "起動の手順、タブを初めて開いたときに作る仕組み、状態と表示の設定", "p.6–9"),
            ("計算の設計", "評価の流れ、学習パターン、推定モデル、指標、補正・配置・ローテ", "p.10–18"),
            ("データ・品質", "設定とファイル、エラー処理、性能、版、テスト、配布、保守", "p.19–27")])

    # 3 レイヤー
    slide = deck.body("01　構成", "システムの構成 ― 画面と計算を分ける")
    layers = [("起動", "runAlignmentEstimationApp（Pro 版）・runAlignmentEstimationAppStandard（通常版）→ AlignmentEstimationApp(visible, lazyTabs, edition)", PANEL),
              ("画面（+appui）", "タブごとのクラス 16 ファイル＋private/ の小さな関数。欄・表・図を作り、計算を呼んで結果を出す（計算はしない）", TEAL_TINT),
              ("計算（+alignest）", "読み込み・前処理・計測点の選び方・推定・指標・集計・書き出し、Shot 高次補正、Mark 配置、ローテ", PURPLE_TINT),
              ("基盤のパッケージ", "+models（推定モデル）・+basis（基底・特徴量）・+optim（上下限つき最適化）・+plot（図）・+stats（検定・百分位）", GOLD_TINT)]
    for index, (heading, body, fill) in enumerate(layers):
        y = 1.6 + index * 1.15
        box(slide, CONTENT_LEFT, y, 8.6, 0.98, fill=fill)
        text(slide, 0.8, y + 0.05, 2.3, 0.88, heading, size=14.5, color=INK, bold=True, anchor="m")
        text(slide, 3.1, y + 0.05, 6.0, 0.88, body, size=11.5, color=BODY, anchor="m")
        if index < 3:
            arrow(slide, 4.9, y + 0.98, 4.9, y + 1.15, color=INK)
    side = [("help/help.html", "メニュー「ヘルプ」の中身（機能編・技術編）。exe にも入れる"),
            ("build/buildStandaloneApp.m", "MATLAB Compiler で exe を作る（版を選べる）"),
            ("tests/", f"自動テスト（{numbers['test_files']} ファイル・333 件）と Python 版の基準値"),
            ("sample_data/", "模擬データ・未知の座標の例・1 変数の見本")]
    y = 1.6
    for heading, body in side:
        box(slide, 9.45, y, 3.28, 1.02, fill=WHITE, line=LINE)
        text(slide, 9.6, y + 0.06, 3.0, 0.35, heading, size=11.5, color=INK, bold=True)
        text(slide, 9.6, y + 0.42, 3.0, 0.58, body, size=10, color=BODY)
        y += 1.15
    point_bar(slide, 6.25, f"計算は MATLAB 本体だけで動く。+alignest は {numbers['alignest_files']} ファイル・約 "
              f"{numbers['alignest_lines'] / 10000:.1f} 万行で、Toolbox を使わない（+optim・+stats で代わりに計算）", icon="i", h=0.62,
              size=12.5)

    # 4 クラス構成
    slide = deck.body("01　構成", "クラスの構成 ― タブごとのクラスを多重継承でまとめる")
    node(slide, 3.9, 1.55, 5.5, 0.62, "AlignmentEstimationApp（画面の本体）", fill=NAVY, color=WHITE, size=14, line_color=None)
    tabs = [name[:-2] for name, _ in TAB_FILES if name not in ("Core.m", "ProgressWindow.m")]
    per_row, w, gap = 5, 2.2, 0.2
    x0 = CONTENT_LEFT + (CONTENT_WIDTH - per_row * w - (per_row - 1) * gap) / 2
    for index, name in enumerate(tabs):
        row, col = divmod(index, per_row)
        color, tint = ACCENTS[index % 4]
        node(slide, x0 + col * (w + gap), 2.65 + row * 0.78, w, 0.58, name, fill=tint, size=11, line_color=None)
    arrow(slide, 6.65, 2.17, 6.65, 2.62, color=INK, head=False)
    tag(slide, 6.75, 2.2, 3.0, "受け継ぐ（< で並べる）", size=10, align="l")
    node(slide, 3.9, 5.35, 5.5, 0.62, "appui.Core（Abstract・handle）", fill=PANEL, size=14, line_color=INK)
    arrow(slide, 6.65, 5.1, 6.65, 5.33, color=INK)
    tag(slide, 6.75, 5.0, 3.6, "どのタブのクラスも Core を受け継ぐ", size=10, align="l")
    text(slide, CONTENT_LEFT, 6.1, CONTENT_WIDTH, 0.8,
         ["Core がデータ・結果・画面の部品（Controls）・定数を持ち、どのタブの関数からも同じ app で読める（ほかのタブの関数も呼べる）",
          "ProgressWindow は別のクラス（計算中の窓）。private/ の関数（placeholder・tableText など）はいくつかのタブで使う"],
         size=11, color=BODY, bullets=True, space_after=2)

    # 5 ファイルと責務
    slide = deck.body("01　構成", "画面のファイルと責務（+appui）")
    rows = [["ファイル", "責務", "行数"]]
    for name, role in TAB_FILES:
        rows.append([name, role, f"{numbers['appui'][name]:,}"])
    table(slide, CONTENT_LEFT, 1.45, [2.75, 8.18, 1.2], rows, size=10, header_size=11, row_h=0.29,
          aligns=["l", "l", "r"], bold_first=True)
    total = sum(numbers["appui"].values())
    text(slide, CONTENT_LEFT, 6.6, CONTENT_WIDTH, 0.28, f"合計 {total:,} 行（作るときにコードから数えた値）",
         size=10, color=MUTED, align="r")

    # 6 起動の手順
    slide = deck.body("02　画面の制御", "起動の手順（startApp）")
    steps = [("版の確認", "edition が \"pro\"・\"standard\" か確かめる（違えば alignest:edition）"),
             ("初期設定", "siteDefaults（既定の設定ファイルを重ねる）→ editionSettings（通常版で使えない設定を直す）"),
             ("窓とタブ", "uifigure・RootGrid（スクロール）・TabGroup と 8 つのタブ（中身はまだ作らない）"),
             ("1・2 のタブ", "buildDataTab・buildSettingsTab・buildRunTab で中身を作る"),
             ("メニュー", "「設定」（色・文字・凡例・Scan・画面・乱数の種）と「ヘルプ」"),
             ("文字と設定", "prepareFonts → settingsToControls（設定を欄に）→ 計算する組み合わせの表示"),
             ("表示の設定", "画面を出すとき：前回の色・文字の大きさ・凡例・保存した項の組み合わせ（getpref）"),
             ("残りのタブ", "lazyTabs = false なら LAZY_TABS を ensureTab ですべて作る"),
             ("大きさの監視", "SizeChangedFcn と、別の画面に移ったかを 1 秒ごとに見るタイマー")]
    for index, (heading, body) in enumerate(steps):
        col, row = divmod(index, 5)
        x = CONTENT_LEFT + col * 6.17
        y = 1.55 + row * 1.06
        color, tint = ACCENTS[index % 4]
        box(slide, x, y, 5.95, 0.9, fill=tint)
        circle(slide, x + 0.14, y + 0.2, 0.5, color, str(index + 1), size=13)
        text(slide, x + 0.8, y + 0.05, 1.55, 0.8, heading, size=12.5, color=INK, bold=True, anchor="m")
        text(slide, x + 2.35, y + 0.05, 3.5, 0.8, body, size=10.5, color=BODY, anchor="m")
    box(slide, 6.77, 5.79, 5.95, 0.9, fill=PANEL)
    text(slide, 6.95, 5.79, 5.6, 0.9, "既定の設定ファイルが読めないときは、アプリの初期設定で開き、記録と知らせに理由を出す（起動は止めない）",
         size=10.5, color=INK, anchor="m")

    # 7 タブを初めて開いたときに作る
    slide = deck.body("02　画面の制御", "タブを初めて開いたときに作る（ensureTab）")
    flow = [("タブを選ぶ", "onTabChanged、openTab、そのタブの公開の関数（97 個）の先頭"),
            ("作ったか", "BuiltTabs に名前があれば何もしない"),
            ("作る", "「タブを準備しています」の窓 → build〇〇Tab（results は 3 と 4 を一緒に）"),
            ("仕上げ", "finishBuiltTab：文字の大きさ・決まった大きさ・文字の大きさの監視・画面の色"),
            ("状態を出す", "results → refreshResultControls、highOrder → 項の組み合わせ")]
    for index, (heading, body) in enumerate(flow):
        x = CONTENT_LEFT + index * 2.47
        color, tint = ACCENTS[index % 4]
        box(slide, x, 1.6, 2.2, 2.05, fill=tint)
        circle(slide, x + 0.15, 1.72, 0.45, color, str(index + 1), size=12)
        text(slide, x + 0.7, 1.7, 1.45, 0.5, heading, size=13, color=INK, bold=True, anchor="m")
        text(slide, x + 0.15, 2.3, 1.9, 1.3, body, size=10.5, color=BODY)
        if index < 4:
            arrow(slide, x + 2.22, 2.62, x + 2.45, 2.62, color=INK)
    rows = [["LAZY_TABS の名前", "作るタブ", "作る前でも使えるもの"],
            ["results", "3. 結果一覧・4. Waferごとのマップ", "評価の結果（Results）。作るときに表・グラフへ出す"],
            ["target", "5. 未知の座標の推定", "読み込んだデータ"],
            ["highOrder", "6. Shot高次補正", "保存した項の組み合わせ（設定）"],
            ["markLayout", "7. Mark配置最適化", "設定 markLayout"],
            ["rotation", "8. 計測Mapローテ", "読み込んだデータ・評価の推定値"]]
    table(slide, CONTENT_LEFT, 3.95, [2.4, 3.9, 5.83], rows, size=11, header_size=12, row_h=0.42, bold_first=True)
    text(slide, CONTENT_LEFT, 6.55, CONTENT_WIDTH, 0.32, "作る途中でエラーになったら部品を消して BuiltTabs に入れない（次に開いたときに作り直す）。"
         "画面を出さない AlignmentEstimationApp(false) は起動のときにすべて作る。", size=10.5, color=MUTED)

    # 8 状態
    slide = deck.body("02　画面の制御", "画面の状態（Core のプロパティ）")
    rows = [["プロパティ", "中身", "作る・変える処理"],
            ["RawTable・FilePath・SheetName", "読んだファイルの表と場所", "loadFile"],
            ["Data・AppliedMapping", "前処理したデータ（data.units）と使った列の対応", "applyMapping → alignest.prepareData"],
            ["Settings", "すべての設定（JSON と同じ形）", "settingsToControls・controlsToSettings・setSettings"],
            ["Results・BaseResults・ResultFilter", "評価の結果（絞り込んだ後・前）と絞り込みの条件", "runEvaluation・filterResults"],
            ["MapCache・MapConditions", "マップの推定値の記憶、並べて比べる条件", "showMap・addMapCondition"],
            ["ImportedEstimates", "読み込んだ推定値の Excel", "importEstimates"],
            ["TargetRun", "未知の座標の推定の結果", "estimateTargets・computeTargetOverlay"],
            ["HighOrderFile・HighOrderRun・HighOrderHistory など", "6. の入力・結果・比較・スイープ・履歴", "computeHighOrder ほか"],
            ["MarkLayoutInput・MarkLayoutStudy など", "7. の候補の Mark・乱数の形・結果", "optimizeMarkLayout ほか"],
            ["RotationVariability・RotationMaps など", "8. のばらつき・計測マップ・検証の履歴", "computeRotationVariability ほか"],
            ["Theme・FontSize・LegendLocation", "表示の設定（getpref に保存）", "setTheme・setFontSize・setLegendLocation"],
            ["BuiltTabs・Edition", "作ったタブ、版", "ensureTab・startApp"]]
    table(slide, CONTENT_LEFT, 1.5, [3.9, 4.6, 3.63], rows, size=10.5, header_size=11.5, row_h=0.4, bold_first=True)

    # 9 表示の設定と部品
    slide = deck.body("02　画面の制御", "画面の部品・表示の設定・保存先")
    items = [("Controls（構造体）", "画面の部品をすべて名前で持つ（例：c.summaryTable・c.chartAxes）。テストも名前で触る"),
             ("画面の色", "Palette（ライト・ダーク）。setColors で部品の種類ごとにまとめて塗る。新しい色にすでになっている所は変えない"),
             ("文字の大きさ", "FONT_SIZE（16）との比を、欄・表・図の文字と FixedSizes（決まった幅・高さ）に掛ける"),
             ("窓の大きさ", "1440 × 900 まで。1200 × 700 より小さいとスクロール。大きさを変え終えたら図を描き直す（0.5 秒）"),
             ("保存先（getpref）", "グループ AlignmentEstimationApp：theme・fontSize・legendLocation・legendOverrides・highOrderTermSets"),
             ("定数", "Core の properties (Constant)。色・大きさ・上限・時間などの意味のある値はここにまとめる")]
    for index, (heading, body) in enumerate(items):
        color, _ = ACCENTS[index % 4]
        x = CONTENT_LEFT + (index % 2) * 6.17
        y = 1.55 + (index // 2) * 1.78
        card(slide, x, y, 5.96, 1.62, color, str(index + 1), heading, body, size=11.5, heading_size=14)

    # 10 処理の流れ
    slide = deck.body("03　計算の設計", "データ読込から評価までの処理の流れ")
    pipe = [("readMeasurementFile", "Excel・CSV を表に"), ("guessColumnMapping", "列の対応を推定"),
            ("prepareData", "前処理・評価の単位に分ける"), ("runEvaluation", "全組み合わせを推定・指標"),
            ("summarizeResults", "手法 × 学習パターンに集計"), ("filterResults", "絞り込みで計算し直す")]
    for index, (name, note) in enumerate(pipe):
        x = CONTENT_LEFT + index * 2.05
        color, tint = ACCENTS[index % 4]
        box(slide, x, 1.65, 1.85, 1.3, fill=tint)
        text(slide, x + 0.05, 1.7, 1.75, 0.55, name, size=10.5, color=INK, bold=True, align="c", anchor="m")
        text(slide, x + 0.05, 2.25, 1.75, 0.65, note, size=10.5, color=BODY, align="c")
        if index < len(pipe) - 1:
            arrow(slide, x + 1.87, 2.3, x + 2.03, 2.3, color=INK)
    blocks = [("data（prepareData の結果）", "data.units：評価の単位ごとの構造体（label・shots・marks（x・y・measX・measY・validX・validY・markNo・"
                                           "shotIndex・attributes）・Shot の大きさ・Scan 方向）。data.summary：除いた行・まとめた行の数と注意。"
                                           "data.attributeNames：その他の列"),
              ("results（runEvaluation の結果）", "table（Wafer × 学習パターン × 手法の指標）・plans（学習パターン）・methods・groups・"
                                                "pointEstimates（評価点の推定値）・settings／runSettings・evaluatedUnits・unitLabels・"
                                                "cancelled と resume（中断の続き）・log・elapsedSeconds"),
              ("書き出し", "exportResults・exportEstimates が results から Excel を作り、importResults・importEstimates で戻す")]
    heading_blocks(slide, CONTENT_LEFT, 3.3, CONTENT_WIDTH, blocks, heading_size=13, size=11.5, gap=0.15)

    # 11 評価のループ
    slide = deck.body("03　計算の設計", "評価のループ（runEvaluation）")
    box(slide, CONTENT_LEFT, 1.55, 7.2, 5.3, fill=PANEL)
    lines = ["activeMethods(settings)：比べる手法の並び（1 変数では RT を除く）",
             "buildPlanSpecs(settings.sampling)：学習パターンの仕様（選び方 × 数）",
             "evaluationUnitIndex：評価に使う Wafer を決める",
             "for Wafer（評価の単位）",
             "    for 学習パターン：planLayoutKey で同じ配置の Wafer は作った計画を使い回す（cachedTrainingPlan）",
             "        for 手法：estimateWafer（異常値の除外 → 当てはめ → 評価点の推定）",
             "            computeMetrics（推定誤差の指標）・overlayCorrection（Overlay 補正の評価）",
             "            progressFcn(完了数, 全体数, 説明) が false なら中断（resume に続きを入れる）",
             "            失敗した手法は指標を NaN、note に理由（止めない）",
             "summarizeResults で集計、results に計算時間・記録・設定を入れる"]
    text(slide, 0.8, 1.65, 6.85, 5.1, lines, size=11, color=INK, font="BIZ UDGothic", space_after=4)
    panel(slide, 8.05, 1.55, 4.68, 2.5, "続きから再開（\"resume\"）",
          ["previous に済んだ組み合わせ（Wafer｜学習パターン｜手法）はそのまま使う", "設定が中断したときと違えば止める（sameRunSettings）",
           "計算時間は前と後を足す"], fill=TEAL_TINT, size=11, heading_size=13)
    panel(slide, 8.05, 4.25, 4.68, 2.6, "条件の追加（\"extend\"）",
          ["増えた手法・学習パターン・Wafer だけを計算して足す", "推定の結果を変える設定（データ・質的変数・制約・評価・Overlay・手法の細部）は同じこと"
                                                  "（extensionConflicts）", "学習パターンは Shot 数・計測率の順に並べ直す"],
          fill=PURPLE_TINT, size=11, heading_size=13)

    # 12 学習パターン
    slide = deck.body("03　計算の設計", "学習パターン（計測点の選び方）の作り方")
    rows = [["選び方", "主な関数", "要点"],
            ["I 最適（Shot・Mark）", "constrainedIOptimal・blockSwapValues", "基準モデルの平均予測分散 tr(M⁻¹) を交換法で小さく。候補の値は Woodbury の式でまとめて求める"],
            ["D 最適（Shot・Mark）", "exchangeDesign・designCriteria", "det(M) を大きく（D 基準 det(M)^(−1/p) を小さく）。I 最適と同じ制約・必ず計測"],
            ["Sobol 列", "sobolSequence・sobolSelect・GroupQuota", "Bratley・Fox の Gray コード法の点に近い Shot を順に。区画の上限・下限を見る"],
            ["ポアソンディスク", "poissonDiskSelect", "距離 d 以上のダーツ投げ。d は数を選べる最大の値を二分法で探す"],
            ["ランダム", "randomFeasibleShots・markPlanTypes", "制約を満たす組を乱数で。繰り返し回数だけ作る（同じ種なら同じ組）"],
            ["Excel 取込", "readLayoutPlans・parseLayoutPlans", "パターン（1・0）と優先順（1・2・3…）の列。計測マップの Excel も読む"],
            ["共通", "planTrainingShots・trainingMarks・requiredShotIndex・outerShots", "必ず計測する Shot・Mark を先に入れる。制約の違反量を記録する"]]
    table(slide, CONTENT_LEFT, 1.5, [2.4, 3.85, 5.88], rows, size=10.5, header_size=11.5, row_h=0.55, bold_first=True)
    text(slide, CONTENT_LEFT, 6.05, CONTENT_WIDTH, 0.8,
         "基準モデル：basis.designPolynomial（X,Y,半径 は x^a y^b（a+b ≤ 次数）と r·x^a y^b（a+b ≤ 次数−1）、5 次で 36 項）。"
         "I 基準・D 基準は候補の全 Mark で正規直交化した M から求め、全計測では I = p・D = 1。", size=10.5, color=MUTED)

    # 13 推定モデル
    slide = deck.body("03　計算の設計", "推定モデル（+models）と手法の組み立て")
    rows = [["系統", "主な関数", "要点"],
            ["GPR", "gprSetup・gprFit・gprObjective・gprPredict・gprPredictVariance", "対数周辺尤度を minimizeBox で最大化。加法カーネル・同時推定・Backfitting"],
            ["TPS・RBF", "tpsSetup・tpsFitPredict・rbfFitPredict", "平滑化・広がりは GCV。質的変数は spatialBackfit"],
            ["Kriging", "krigingEmpiricalVariogram・krigingFitVariogram・krigingFitPredict", "経験バリオグラムに当てはめて推定。Universal は 1 次のトレンド"],
            ["GAM", "gamSetup・gamShapeFit・gamCriterion・gamFitPredict", "P-spline・ガウス過程の形状関数、λ は REML"],
            ["多項式・RT・Zernike", "polynomialFitPredict・rtFitPredict・zernikeFitPredict", "最小二乗。RT は X・Y を一緒に当てはめる"],
            ["組み立て", "buildMethodList・completeMethodSettings・activeMethods", "設定から手法の並び（id・名前・系統・中身）を作る"],
            ["振り分け", "estimateWafer", "学習点・評価点を作り、手法の系統で +models の関数を呼ぶ"]]
    table(slide, CONTENT_LEFT, 1.5, [2.2, 5.0, 4.93], rows, size=10.5, header_size=11.5, row_h=0.58, bold_first=True)
    text(slide, CONTENT_LEFT, 6.3, CONTENT_WIDTH, 0.55, "質的変数は basis.effectCoding（効果コード）、連続値の列は continuousFeatures で説明変数に足す。"
         "1 つの手法の失敗は estimateWafer の外で受け止め、評価を止めない。", size=10.5, color=MUTED)

    # 14 指標・集計・分析
    slide = deck.body("03　計算の設計", "指標・集計・分析の関数")
    blocks = [("指標", "computeMetrics：R²・RMSE・MAE・MaxAE・MinAE（X・Y・XY）、外周・内側の RMSE。baselineImprovement：平均値・中央値に対する改善"),
              ("集計", "summarizeResults・perUnitValues：Wafer ごと（ランダムは平均）→ 平均・中央値・ワースト値・95%値（stats.percentile = PERCENTILE.INC）"),
              ("絞り込み", "filterResults・pointFilterMask：results.pointEstimates から、条件に合う評価点だけで指標を計算し直す"),
              ("比較", "pairedComparison（基準の手法）・waferRanking（ベスト・ワースト・総合）・layoutComparison（計測配置）・overlayDegradation"),
              ("分析", "residualAnalysis（stats.normalityTests・shapiroWilk・andersonDarling・anovaMainEffects）・distributionComparison（jsDivergence）・"
                       "residualFactors・timingBreakdown・measurementCandidates"),
              ("ばらつき分解", "varianceDecomposition（入れ子の分散分析、モーメント法）・dataVarianceDecomposition・correctionVarianceDecomposition・componentCoefficients")]
    heading_blocks(slide, CONTENT_LEFT, 1.55, CONTENT_WIDTH, blocks, size="auto", gap=0.2)

    # 15 Overlay 補正
    slide = deck.body("03　計算の設計", "Overlay 補正の評価の作り")
    rows = [["場", "求め方"],
            ["実測値で補正した残差", "全 Mark の計測値で補正のモデルを当てはめ、計測値 − 補正量"],
            ["推定値で補正した残差", "学習 Shot は計測値、学習しなかった Shot は推定値で当てはめ、その補正を計測値に当てる"],
            ["推定による変化", "推定値で補正した残差 − 実測値で補正した残差（= 2 つの補正量の差）"]]
    table(slide, CONTENT_LEFT, 1.5, [3.0, 9.13], rows, size=11.5, header_size=12, row_h=0.5, bold_first=True)
    blocks = [("設計行列（overlayDesign・overlayTerms）", "Wafer 成分（Shot 中心を Wafer 半径で割った座標の 0〜5 次）・Shot 共通成分（Shot 内の座標、全 Shot で同じ係数）・"
                                                    "Shot ごとの成分（Shot ごとに別の係数）を横に並べ、X・Y 別に最小二乗"),
              ("補正量だけを使う（overlayProjector）", "成分どうしで重なる項・決まらない係数があっても、当てはめた値は一つに決まるので、係数は求めずに射影で補正量を出す"),
              ("式の入力（parseCorrectionFormula）", "項を + − でつなぎ、係数 × x・y のべき（9 まで）。全角も読む。係数の名前・符号は補正量に影響しない（項の形だけ使う）"),
              ("指標", "OVL 残差（実測値で補正・推定値で補正）・推定による変化・増加の |平均|+3σ（X・Y）の 8 つを results.table に足す")]
    heading_blocks(slide, CONTENT_LEFT, 3.75, CONTENT_WIDTH, blocks, heading_size=13, size=11, gap=0.1)

    # 16 Shot 高次補正
    slide = deck.body("04　補正・配置・ローテ", "Shot 高次補正の計算（shotHighOrder）")
    pipe = [("入力", "prepareHighOrderData\nreadHighOrderFile"), ("項", "highOrderTerms\nhighOrderVif"),
            ("確かめ", "shotHighOrder\n(checkOnly)"), ("当てはめ", "highOrderSequential\nrobustRidgeFit"),
            ("評価", "highOrderRSquared\nhighOrderOutliers"), ("出力", "exportHighOrder\nwriteHighOrderTable")]
    for index, (heading, names) in enumerate(pipe):
        x = CONTENT_LEFT + index * 2.05
        color, tint = ACCENTS[index % 4]
        box(slide, x, 1.6, 1.85, 1.35, fill=tint)
        text(slide, x + 0.05, 1.65, 1.75, 0.4, heading, size=13, color=INK, bold=True, align="c")
        text(slide, x + 0.05, 2.08, 1.75, 0.8, names, size=9.5, color=BODY, align="c")
        if index < 5:
            arrow(slide, x + 1.87, 2.27, x + 2.03, 2.27, color=INK)
    blocks = [("当てはめの順", "Wafer 高次補正（Wafer 成分・Wafer RT）→ Shot 共通補正（計算・入力）→ k の組ごと（Wafer 内・選択 Wafer・Scan 方向・行の偶奇・Shot）"),
              ("回帰（robustRidgeFit）", "列を平均 0・標準偏差 1 にそろえ、最小二乗・Huber・LAD（重み付き最小二乗の繰り返し、尺度は MAD × 1.4826）と、"
                                       "選んだ次数の項だけに L2・L1（座標降下法）。1 点抜きの誤差も返す"),
              ("点が足りない組", "全体の項を減らす・その組だけ減らす・補正しない（shortage）。k1〜k6 も決まらない組は補正しない"),
              ("比べる", "compareHighOrderConditions（条件の比較）・compareHighOrderShots（2 つの条件）・sweepHighOrder（λ・c）・"
                        "transferHighOrder（他の Wafer）・highOrderTermSelection（変数重要度・ステップワイズ）")]
    heading_blocks(slide, CONTENT_LEFT, 3.25, CONTENT_WIDTH, blocks, heading_size=13, size=11, gap=0.12)

    # 17 Mark 配置とローテ
    slide = deck.body("04　補正・配置・ローテ", "Mark 配置最適化と計測Mapローテの計算")
    panel(slide, CONTENT_LEFT, 1.55, 5.95, 5.3, "Mark 配置最適化（markLayoutStudy）",
          ["markCandidates：候補の Mark（同じ位置は 1 つ、上の行・左から番号）",
           "iOptimalMarks：Mark の数ごとに I(S) = Σ trace(M_S⁻¹ W)、W = F'F / N を交換法（修正 Fedorov 法）で最小に。必ず計測は入れ替えない",
           "randomShotShapes：次数ごとの大きさ・ばらつき・飛び値で乱数の Shot の形",
           "evaluateMarkLayouts：配置の Mark で当てはめ、すべての候補で制御残差（最小二乗・L2 は係数の式をまとめて使う）",
           "markLayoutCriterion・exportMarkLayouts・exportMarkSelection：式の説明と書き出し"],
          fill=TEAL_TINT, size=11, heading_size=13.5)
    panel(slide, 6.78, 1.55, 5.95, 5.3, "計測Mapローテ（rotationMaps ほか）",
          ["markVariability：同じ Shot・Mark の Wafer 間の 3σ（X・Y・|v|）、radialCumulative：半径の累積",
           "rotationMaps：しきい値で優先度、頻度 n の点を n 組に振り分け、組 g を (m−1) mod n = g のマップへ",
           "rotationCriterionExchange・rotationCriterionBasis：I・D 最適の振り分け（入れ替えで基準の和を小さく）",
           "compareRotationAssignments・rotationMapMetrics：KL・最大の空白・I/D 基準で比べる",
           "feedbackSimulation：FB 側と検証側に分け、FB の補正値を当てた補正残差。exportRotationMaps"],
          fill=PURPLE_TINT, size=11, heading_size=13.5)

    # 18 未知の座標
    slide = deck.body("04　補正・配置・ローテ", "未知の座標の推定と重ね合わせ補正値")
    chain_items = [("点の表", "readTargetPoints・targetGrid"), ("Shot を探す", "targetsAtShots（点を含む Shot・Scan 方向）"),
                   ("推定", "predictTargets → estimateWafer（点を値の無い Mark として足す）"), ("判定", "凸包の外 0.5 mm 超は外挿、半径 150 mm 以上は Wafer の外"),
                   ("補正値", "targetOverlayCorrection（実測値＋推定値で当てはめ）"), ("書き出し", "exportTargetEstimates")]
    for index, (heading, body) in enumerate(chain_items):
        x = CONTENT_LEFT + index * 2.05
        color, tint = ACCENTS[index % 4]
        box(slide, x, 1.6, 1.85, 2.1, fill=tint)
        circle(slide, x + 0.12, 1.7, 0.42, color, str(index + 1), size=12)
        text(slide, x + 0.6, 1.68, 1.2, 0.48, heading, size=12, color=INK, bold=True, anchor="m")
        text(slide, x + 0.12, 2.25, 1.62, 1.4, body, size=9.5, color=BODY)
        if index < 5:
            arrow(slide, x + 1.87, 2.65, x + 2.03, 2.65, color=INK)
    blocks = [("評価と同じ計算", "学習しなかった Mark と同じ点を渡すと、評価の推定値と一致する（テストで確認）。学習データは全 Mark か評価の学習パターン"),
              ("学習に無い Mark 番号", "Mark 番号の効果を全 Mark の平均（効果コード 0）として推定し、メッセージに出す"),
              ("補正値の係数", "mm の座標での値（1 次は nm/mm = ppm）。重なる項・決まらない項は前の成分（Wafer → Shot 共通 → Shot ごと）に含めて 0 とし、メモに書く")]
    heading_blocks(slide, CONTENT_LEFT, 4.0, CONTENT_WIDTH, blocks, heading_size=13, size=11.5, gap=0.14)

    # 19 設定
    slide = deck.body("05　データ・品質", "設定データ（settings）― JSON と同じ形の構造体")
    rows = [["区分", "主な項目", "例"],
            ["data", "座標の定義・推定する値・有効半径・Scan 方向の付与・除外", "coordinateMode・valueColumn・directionRule"],
            ["factors", "質的変数（X・Y で別）", "Scan 方向・Mark 番号・ファイルの列"],
            ["sampling", "計測点の選び方・粒度・制約・学習 Shot/Mark 数・必ず計測・乱数の種", "method・unit・nShotsStart・seed"],
            ["methods", "比べる手法とその中身", "gpr・tps・rbf・kriging・gam・polynomial・rt・zernike"],
            ["evaluation", "外周の半径・異常値の除外・処理時間・評価に使う Wafer", "outerRadiusMm・outlierMethod"],
            ["overlay", "Overlay 補正の成分と式", "waferOrder・shotCommon・perShot・式"],
            ["highOrder", "6. の式・くくり・Wafer 補正・Shot 共通・項・回帰・項の組み合わせ", "maker・unit・lambda・termSets"],
            ["markLayout", "7. の式・回帰・Mark の数・乱数の形・座標", "minMarks・shapes・orderSigmaNm"],
            ["display", "Scan 方向の向きと色（推定の結果は変わらない）", "scan1Up・色"]]
    table(slide, CONTENT_LEFT, 1.5, [1.65, 6.0, 4.48], rows, size=10.5, header_size=11.5, row_h=0.42, bold_first=True)
    flow = ["defaultSettings", "siteDefaults", "loadSettings・upgrade〇〇", "editionSettings", "settingsToControls"]
    for index, label in enumerate(flow):
        x = CONTENT_LEFT + index * 2.47
        node(slide, x, 5.95, 2.2, 0.55, label, fill=PANEL, size=10.5, line_color=None)
        if index < 4:
            arrow(slide, x + 2.22, 6.22, x + 2.45, 6.22, color=INK)
    text(slide, CONTENT_LEFT, 6.55, CONTENT_WIDTH, 0.32, "欄から設定へは controlsToSettings、評価の前に validateSettings。以前の設定は upgrade〇〇 で今の形に直す。",
         size=10, color=MUTED)

    # 20 ファイル入出力
    slide = deck.body("05　データ・品質", "ファイルの読み書き")
    rows = [["ファイル", "読む", "書く"],
            ["計測データ（Excel・CSV）", "readMeasurementFile・readSheetTable", "—（入力は書き換えない）"],
            ["設定（JSON）", "loadSettings・siteDefaults", "saveSettings"],
            ["評価結果・推定値（Excel）", "importResults・importEstimates", "exportResults・exportEstimates"],
            ["計測マップ（Excel）", "readLayoutPlans（Excel 取込）", "exportMeasurementMap（RunTab）"],
            ["未知の座標（Excel・CSV）", "readTargetPoints", "exportTargetEstimates"],
            ["Shot 高次補正（Excel・CSV）", "readHighOrderFile", "exportHighOrder・writeHighOrderTable（CSV は UTF-8・BOM）"],
            ["Mark 配置（Excel・CSV）", "markLayoutFileData", "exportMarkLayouts・exportMarkSelection"],
            ["ローテ（Excel・CSV）", "rotationColumns・loadRotationFile", "exportRotationMaps"],
            ["ばらつき分解の表", "—", "exportVarianceTable（Excel・CSV）・copyVarianceTable（tableText）"],
            ["図（PNG）", "—", "saveFigureImage・copyFigureImage（150 dpi、複数の図は横に並べる）"]]
    table(slide, CONTENT_LEFT, 1.5, [3.0, 4.2, 4.93], rows, size=10.5, header_size=11.5, row_h=0.43, bold_first=True)
    text(slide, CONTENT_LEFT, 6.35, CONTENT_WIDTH, 0.5, "Excel の列名と見出しの対応は estimateColumnNames・resultColumnNames に 1 か所でまとめ、書き出しと読み込みで共通に使う。",
         size=10.5, color=MUTED)

    # 21 エラー処理
    slide = deck.body("05　データ・品質", "エラー処理と入力チェック")
    items = [("エラーの識別子", "error('alignest:〇〇', 理由と直し方) で止める（例：alignest:noData・noMethod・edition・factorColumn）。テストは識別子で確かめる"),
             ("画面の知らせ", "止まるエラーは知らせの窓（uialert）か赤の文字、計算はできる注意は橙の文字。欄の下に理由を出す"),
             ("評価を止めない", "1 つの手法の失敗は、その行の指標を NaN、note に理由。評価の最後に「推定できなかった組み合わせ」を記録に出す"),
             ("計算の前の確かめ", "validateSettings（評価）、shotHighOrder の checkOnly（決まらない項）、式の読み方（parseCorrectionFormula）"),
             ("古い結果", "設定・入力を変えた後は「計算し直してください」と出し、書き出すときに計算し直す"),
             ("起動を止めない", "既定の設定ファイル・表示の設定が読めないときは、初期値で開いて理由を出す")]
    for index, (heading, body) in enumerate(items):
        color, _ = ACCENTS[index % 4]
        x = CONTENT_LEFT + (index % 2) * 6.17
        y = 1.55 + (index // 2) * 1.78
        card(slide, x, y, 5.96, 1.62, color, str(index + 1), heading, body, size=11.5, heading_size=14)

    # 22 性能
    slide = deck.body("06　性能・版・テスト・配布", "性能の設計 ― 部品を減らし、計算をまとめる")
    rows = [["しくみ", "内容", "効く所"],
            ["タブを初めて開いたときに作る", "3〜8 のタブ（LAZY_TABS）は開くまで部品を作らない", "起動・文字の大きさ・色の切り替え"],
            ["見えていない図は後で描く", "読み込みの直後は見ている図だけ描き、ほかは開いたときに描く（ResizedCharts）", "この対応で読み込む"],
            ["色をまとめて塗る", "部品の種類ごとにまとめて色を入れ、新しい色になっている所は変えない", "ライト・ダークの切り替え"],
            ["文字の大きさを読み直さない", "標準の大きさのときは図の文字を読み直さない", "表示の切り替え"],
            ["交換法の候補をまとめて計算", "blockSwapValues：入れ替えの候補の基準を一度に求める（選ぶ点・値は以前と同じ）", "I 最適・D 最適の学習パターン"],
            ["学習パターンを使い回す", "planLayoutKey：値の無い Mark が同じ Wafer は作った計画を使う", "評価の全体の時間"],
            ["時間の目安", "estimateRunSeconds・planSecondsGuide・exchangeSecondsGuide", "計算の前の見通し"]]
    table(slide, CONTENT_LEFT, 1.5, [3.2, 5.9, 3.03], rows, size=10.5, header_size=11.5, row_h=0.55, bold_first=True)
    text(slide, CONTENT_LEFT, 6.05, CONTENT_WIDTH, 0.8, "交換法の時間は初期配置の数にほぼ比例する（初期配置 1 つ・学習 Shot 1 つあたり約 0.01 秒、"
         "M1 Mac・模擬データ）。Mark 単位は Mark を 1 つずつ入れ替えるので長い。", size=10.5, color=MUTED)

    # 23 版
    slide = deck.body("06　性能・版・テスト・配布", "版（通常版・Pro 版）の実現")
    node(slide, CONTENT_LEFT, 1.65, 3.3, 0.8, "edition（\"pro\"・\"standard\"）", fill=NAVY, color=WHITE, size=13, line_color=None)
    targets = [(4.55, 1.35, "設定を直す", "alignest.editionSettings：手法・選び方・Overlay の式を通常版で使える値に。直した項目を返す"),
               (4.55, 2.65, "欄を作らない", "isPro(app)：SettingsTab で Pro 版だけの手法の欄を作らず、選択肢を絞る"),
               (4.55, 3.95, "読み込みで知らせる", "setSettings・settingsToControls が editionSettings を通し、変えたら知らせる"),
               (4.55, 5.25, "配布物を分ける", "buildStandaloneApp(edition=)：実行ファイルの名前と出力フォルダを版ごとに")]
    for index, (x, y, heading, body) in enumerate(targets):
        color, tint = ACCENTS[index % 4]
        box(slide, x, y, 8.18, 1.08, fill=tint)
        text(slide, x + 0.2, y + 0.05, 2.1, 0.98, heading, size=13.5, color=INK, bold=True, anchor="m")
        text(slide, x + 2.35, y + 0.05, 5.7, 0.98, body, size=11, color=BODY, anchor="m")
        elbow(slide, [(3.9, 2.05), (4.2, 2.05), (4.2, y + 0.54), (4.53, y + 0.54)], color=INK)
    text(slide, CONTENT_LEFT, 2.7, 3.3, 3.5, ["入口：runAlignmentEstimationApp・runAlignmentEstimationAppStandard",
                                              "Core.Edition に持つ", "ほかのタブ・計算の関数は版で変えない（同じコード）",
                                              "テスト：tests/TestEdition.m"], size=11, color=BODY, bullets=True, space_after=4)

    # 24 テスト
    slide = deck.body("06　性能・版・テスト・配布", "テストと検証")
    rows = [["区分", "主なテストファイル", "確かめること"],
            ["読み込み・前処理", "TestDataPreparation・TestAbsoluteScalar", "列の対応・単位・除外・重複・絶対座標・1 変数"],
            ["評価・集計・書き出し", "TestEvaluation・TestFilterExtendTiming・TestResultsImport", "指標の定義、絞り込み、条件の追加、Excel の往復"],
            ["計測点の選び方", "TestMeasurementPlan・TestLayoutDesignZernike・TestPlanModelAndDefaults", "制約・必ず計測・Sobol・ポアソン・Excel 取込・Mark 単位"],
            ["推定モデル", "TestSpatialModels・TestModelOptions・TestGprVariance", "カーネル・Backfitting・GPR の推定の分散"],
            ["Python 版との照合", "TestPythonReference", "GPR・TPS・Kriging・GAM・I 最適が Python 版と一致"],
            ["Shot 高次補正", "TestShotHighOrder（7 ファイル）", "式の項・VIF・回帰・くくり・段階・スイープ・書き出し"],
            ["配置・ローテ", "TestMarkLayout・TestRotationMaps", "I 最適の配置・乱数の形・優先度・振り分け・FB"],
            ["画面の流れ", "TestAppWorkflow・TestScreenFitAndOverlays・TestEdition ほか", "画面の操作から Excel まで、遅延のタブ、版"]]
    table(slide, CONTENT_LEFT, 1.5, [2.4, 5.2, 4.53], rows, size=10.5, header_size=11.5, row_h=0.5, bold_first=True)
    text(slide, CONTENT_LEFT, 6.1, CONTENT_WIDTH, 0.75, f"cd tests; runAllTests で全 333 件（{numbers['test_files']} ファイル）。"
         "画面のテストは AlignmentEstimationApp(false)（画面を出さない）。ヘルプ・表示の設定の保存先（getpref）に書かない作り。", size=10.5,
         color=MUTED)

    # 25 配布
    slide = deck.body("06　性能・版・テスト・配布", "ビルドと配布（buildStandaloneApp）")
    rows = [["指定", "作るもの"],
            ["buildStandaloneApp", "Pro 版の実行ファイル AlignmentEstimationApp（画面だけのアプリ）"],
            ["edition=\"standard\"", "通常版の実行ファイル AlignmentEstimationAppStandard"],
            ["makeInstaller=true", "インストーラー（MATLAB Runtime をネットから入れる形）"],
            ["runtimeDelivery=\"installer\"", "Runtime 入りのインストーラー（ネットに出られない PC 用、数 GB）"],
            ["outputFolder", "出力先（既定は build/output/<OS の種類>/<版>/）"]]
    table(slide, CONTENT_LEFT, 1.5, [3.6, 8.53], rows, size=11.5, header_size=12, row_h=0.5, bold_first=True)
    panel(slide, CONTENT_LEFT, 4.75, 5.95, 2.1, "必要なもの",
          ["作る PC：MATLAB と MATLAB Compiler", "使う PC：作ったときと同じ版の MATLAB Runtime（無料）", "help/help.html を一緒に入れる"],
          size=12.5)
    panel(slide, 6.78, 4.75, 5.95, 2.1, "確認の範囲",
          ["Mac では Windows 用の exe は作れない", "この Mac（Compiler なし）では exe の作成と動作は未確認",
           "MATLAB の中での画面・計算・テストは確認済み"], size=12.5, fill=GOLD_TINT)

    # 26 保守
    slide = deck.body("06　性能・版・テスト・配布", "保守の指針 ― 何を直すときに、どこを見るか")
    rows = [["直したいこと", "見る場所"],
            ["画面の初期値・既定の手法", "+alignest/defaultSettings.m・recommendedMethods.m（部署ごとなら既定の設定ファイル）"],
            ["色・大きさ・上限などの値", "+appui/Core.m の properties (Constant)"],
            ["欄の文字・配置・説明", "各タブのファイルの build〇〇Tab（詳しい説明は help/help.html に書く）"],
            ["計算の中身", "+alignest の関数（画面のファイルには計算を書かない）"],
            ["Excel の列名", "estimateColumnNames・resultColumnNames（書き出しと読み込みで共通）"],
            ["設定の項目を足す", "defaultSettings → settingsToControls・controlsToSettings → validateSettings → editionSettings"],
            ["Pro 版だけにする", "editionSettings と SettingsTab の isPro の分岐、TestEdition"],
            ["直した後", "runAllTests、README と help.html、必要なら exe を作り直す"]]
    table(slide, CONTENT_LEFT, 1.5, [3.4, 8.73], rows, size=11, header_size=12, row_h=0.5, bold_first=True)
    text(slide, CONTENT_LEFT, 6.2, CONTENT_WIDTH, 0.65, "メーカーの補正の式（Canon・Nikon）はルールの式のまま。項・係数番号・符号を変えない。"
         "意味のある値は定数にし、名前から目的が分かるようにする。", size=10.5, color=MUTED)

    # 27 まとめ
    closing(deck, "設計の要点",
            [("画面と計算を分ける", "+appui は欄と表示だけ、計算は +alignest。計算は MATLAB 本体だけで動く"),
             ("1 つの app に集める", "タブごとのクラスを多重継承でまとめ、状態は Core のプロパティに持つ"),
             ("軽く起動する", "タブは初めて開いたときに作り、見えない図は後で描く"),
             ("止めずに続ける", "失敗は NaN と理由、中断と再開、古い結果の知らせ")],
            ["機能仕様書（PowerPoint）：機能と入出力", "画面遷移図（PowerPoint）：想定利用ごとの画面の流れ",
             "詳細機能一覧（HTML）：機能ごとの実装の関数", "README・管理者向け資料：使い方・保守の手順"])

    deck.save(output)
    return deck.page


def main():
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUTPUT
    reference = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_REFERENCE
    pages = build(output, reference)
    print(f"書き出しました：{output}（{pages} 枚）")


if __name__ == "__main__":
    main()
