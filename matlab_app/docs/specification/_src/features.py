"""面内推定評価ツールの詳細機能一覧（機能仕様書・詳細機能一覧 HTML の共通の元データ）。

1 つの機能 = 1 行。列は次のとおり（HTML の表の列と同じ順）。
- name：機能の名前（画面の欄・ボタンの名前に合わせる）
- desc：何をするか
- ops：利用者が操作する欄・ボタン、入力
- out：結果・出力（画面・ファイル）
- impl：主な実装（+alignest・+appui の関数）
- ed：版（"共通" = 通常版・Pro 版の両方、"Pro" = Pro 版だけ、"一部" = 通常版は選択肢を絞る）
内容は matlab_app/README.md とコード（2026-11-27、main 19acdf9）に合わせる。
"""
from __future__ import annotations

APP_NAME = "面内推定評価ツール"
APP_FORMAL = "Lithography Utilities for Correction Analysis and Sampling Optimization（LUCAS）"
VERSION_NOTE = "2026年11月27日時点"

EDITION_LABELS = {"共通": "通常版・Pro 版", "Pro": "Pro 版だけ", "一部": "通常版は一部"}


def F(name, desc, ops, out, impl, ed="共通", std_desc=None, std_ops=None):
    """1 つの機能。ed = "一部" の機能は、通常版の内容（std_desc・std_ops）も書く（詳細機能一覧 HTML は通常版の内容を出す）"""
    return {"name": name, "desc": desc, "ops": ops, "out": out, "impl": impl, "ed": ed,
            "std_desc": std_desc or desc, "std_ops": std_ops or ops}


SECTIONS = [
    {
        "key": "1", "title": "1. データ読込", "file": "DataTab.m",
        "summary": "Excel・CSV の計測データを読み込み、列の対応・座標の単位・除外の条件を決めて前処理する。読み込んだデータを "
                   "Wafer マップ・Shot レイアウト・ばらつき分解などで確かめる。",
        "groups": [
            ("① ファイルと読み込みの条件", [
                F("ファイルを選ぶ", "Excel（.xlsx）・CSV（UTF-8）の計測データを読む。Excel はシートを選べる。",
                  "「ファイルを選ぶ…」、シート", "② 列の対応の表", "readMeasurementFile, readSheetTable"),
                F("座標の定義", "Shot 中心＋Shot 内の位置（初期値）か、Wafer 上の絶対座標だけ。絶対座標では shotNo・"
                  "markXmm から Shot 中心を決め、無ければ点を1つずつ Shot とする。",
                  "座標の定義（shotMark・absolute）", "解析座標 x = Xmm + markXmm", "prepareData"),
                F("推定する値", "X・Y 成分（measX・measY）か、ファイルの1つの列（膜厚・線幅など）を1変数として推定する。"
                  "1変数では RT モデル・Overlay 補正の評価・矢印の図を使わない。",
                  "推定する値、値の単位", "1変数の指標名（例：RMSE [nm]（Thickness_nm））", "valueSpec, prepareData"),
                F("有効半径", "Wafer 中心からの半径がこの値以上の点を除く（初期値 150 mm）。", "有効半径 [mm]",
                  "除いた行の数（読み込み結果）", "prepareData"),
                F("Scan 方向の付与", "Direction の列が無い・空の行に、規則で Scan 方向 1・2 を付ける（一筆書き（初期値）・"
                  "shotNo の奇偶・市松模様・行ごと・列ごと・付けない。1 と 2 の入れ替えも）。",
                  "Scan 方向の付与、付ける 1 と 2 を入れ替える", "付けた行の数と規則（読み込み結果・Excel の説明）", "directionRules, prepareData"),
                F("行の除外条件", "測定値 X・Y が両方 0 の行、StsX または StsY が −1 の行を除く（どちらも初期値オフ）。",
                  "除外のチェック 2 つ", "条件ごとの除外件数", "prepareData"),
                F("異常値を除外", "Wafer ごとに、中心から n × ばらつきより外れた Mark を X・Y の両方で無効にする"
                  "（平均と σ、または中央値と MAD。初期値オフ、n = 3）。", "異常値を除外、n、判定の方法",
                  "除いた Mark の数", "trainingOutliers, outlierMethod"),
            ]),
            ("② 列の対応・座標の単位", [
                F("列の対応", "ファイルの列を標準の項目（Operation・EqpId・LotID・Wafer・DateTime・shotNo・Direction・"
                  "Xmm・Ymm・Radius・markNo・markXmm・markYmm・measX・measY・StsX・StsY）に対応づける。名前から自動で推定し、"
                  "プルダウンで選び直せる。", "列の対応の表", "対応づけた列", "guessColumnMapping, standardColumns"),
                F("座標の単位", "座標の列ごとに入力の単位（mm・µm・nm・m）を選ぶ。値の大きさが目安から外れると ⚠ と合いそうな単位を出す。",
                  "座標の単位の表、「値の大きさから単位を推定」「まとめて選ぶ」", "変換後の値 [mm] と確認の結果",
                  "coordinateUnits, checkCoordinateUnits"),
                F("その他の列", "標準の項目にしなかった列（Chuck・Reticle など）を Mark ごとの値として残す。質的変数・連続値の列に使える。",
                  "—", "質的変数・連続値の列の候補", "prepareData, numericColumns"),
            ]),
            ("③ この対応で読み込む", [
                F("前処理", "解析座標を求め、StsX・StsY が有効な値だけを使い、同じ点の重複を平均する。評価の単位は "
                  "Operation × EqpId × LotID × Wafer × DateTime。", "「③ この対応で読み込む」",
                  "読み込み結果（除いた行・まとめた行の数、工程・装置・ロットの一覧）", "prepareData, shotSize"),
            ]),
            ("読み込んだデータの確認（右の中のタブ）", [
                F("Wafer マップ", "計測値のベクトルと X・Y のヒートマップを並べる。Shot の枠（Scan 方向の色分け）・同心円の区切り・"
                  "Wafer ごと／平均（全 Wafer・LotID・EqpId・Operation・Slot の偶奇）と共分散楕円。",
                  "Wafer、値、色の点の大きさと形、Shot の枠", "Wafer マップの図", "plot.waferMap, plot.covarianceEllipses"),
                F("Shot レイアウト", "Shot の配置（枠・shotNo・S1/S2）と計測した Mark の位置、Shot 内の Mark の位置と番号。"
                  "Shot をクリックするとその shotNo の Scan 方向を入れ替える。", "Shot のクリック", "Shot レイアウトの図",
                  "plot.shotLayout, setScanDirection"),
                F("Shot 重ね合わせ", "選んだ Wafer の全 Shot を Shot 内の座標で重ねたベクトル場と共分散楕円。Scan 方向で分けられる。",
                  "Wafer、Scan 方向で分ける", "Shot 重ね合わせの図", "plot.shotOverlayMap, drawShotOverlay"),
                F("質的変数の交互作用", "Wafer ごとに面内の傾向（XY 多項式、初期 3 次）を除いた残りで、質的変数の効果と2つずつの交互作用を"
                  "検定し、説明変数・カーネルを選ぶ目安を出す。", "質的変数、次数、「調べる」", "交互作用の図と検定の表",
                  "factorInteractions, stats.interactionTests"),
                F("ばらつき分解（Lot・Wafer・Shot 間）", "計測値のばらつきを Lot 間・Wafer 間・Shot 間・その他に分ける（入れ子の分散分析、"
                  "モーメント法）。縦軸は 3σ の配分の積み上げ（全体の 3σ を ◆）か分散。Operation ごとに並べる。凡例は右の列にまとめ、"
                  "4 つの図の大きさをそろえる。", "分け方、縦軸", "積み上げ棒と分散の割合の表",
                  "dataVarianceDecomposition, varianceDecomposition, plot.varianceBars"),
                F("ばらつき分解の絞り込み", "装置（EqpId）・ロット（LotID）・Operation、またはファイルのその他の列（Chuck など）を選び、"
                  "1 つの値の計測（その他の列は Mark）だけで分ける。", "絞り込み（列・値）", "絞り込んだ結果",
                  "dataVarianceDecomposition（column）"),
                F("ばらつき分解（成分）", "Wafer ごとの全体 Shift・Wafer 倍率・回転と Wafer 成分の残留（Wafer レベルの回帰残差の 3σ）、"
                  "Shot 倍率・回転と Shot 共通成分の残留（Shot レベルの回帰残差の 3σ）を X・Y 別に表とグラフに並べる（上の段 Wafer、下の段 Shot）。",
                  "分け方「成分」", "回帰係数・残留の表・グラフ", "componentCoefficients"),
                F("ばらつき分解の図・表の保存とコピー", "図を PNG で保存・クリップボードにコピー、表を Excel（「値」「説明」）・CSV に保存・"
                  "タブ区切りでコピー（Excel・PowerPoint の表に貼れる）。", "「図を保存…」「図をコピー」「表を保存…」「表をコピー」",
                  "PNG、Excel・CSV、クリップボード", "exportVarianceTable, copyVarianceTable, tableText"),
            ]),
        ],
    },
    {
        "key": "2", "title": "2. 面内推定の設定", "file": "SettingsTab.m・RunTab.m",
        "summary": "計測点の選び方・学習 Shot/Mark 数・比べる手法・評価と Overlay 補正の条件を決め、評価を実行する。"
                   "上の帯（評価の実行・設定の保存）はどの中のタブでも見える。",
        "groups": [
            ("上の帯（評価の実行と設定）", [
                F("評価を始める", "全 Wafer × 学習パターン × 手法で推定し、学習しなかった点の計測値と比べて指標を求める。進み具合と残り時間を出し、"
                  "終わると「3. 結果一覧」を開く。1つの手法が失敗しても止めずに、その行を NaN と理由にして続ける。",
                  "「評価を始める」", "結果一覧・マップ、記録", "runEvaluation, estimateWafer, computeMetrics"),
                F("一時中断・続きから再開", "計算中の組み合わせが終わったところで止め、途中までの結果を出す。残りの組み合わせだけを後から計算する。",
                  "進み具合の窓の「一時中断」、「続きから再開」", "途中までの結果", "runEvaluation（resume）, sameRunSettings"),
                F("条件を追加して評価", "評価の後に増やした手法・学習パターン・Wafer だけを計算して、今の結果に足す。推定の結果を変える設定は変えられない。",
                  "「条件を追加して評価」", "足した結果", "runEvaluation（extend）, extensionConflicts"),
                F("設定の保存・読み込み・初期化", "設定を JSON に保存・読み込み、初期設定に戻す。起動フォルダの既定の設定ファイル"
                  "（alignment_estimation_defaults.json）があれば初期設定に重ねる。", "「設定を保存…」「設定を読み込む…」「初期設定に戻す」",
                  "設定 JSON", "saveSettings, loadSettings, siteDefaults, defaultSettings"),
                F("計算時間の目安", "推定の時間（1 条件 2 秒、ν を指定した Matérn は 6 秒）と学習パターンを作る時間（交換法）の和を出す。",
                  "—（設定を変えるたびに更新）", "目安の文", "estimateRunSeconds, planSecondsGuide, exchangeSecondsGuide"),
                F("記録を見る", "データの確認・学習パターン・推定できなかった組み合わせなどの全文を別の窓で見る。", "「記録を見る…」",
                  "記録の窓", "showRunLog"),
            ]),
            ("計測設定（学習に使う計測点）", [
                F("データの粒度", "Shot 単位（Shot を選び、その Mark をすべて使う）か Mark 単位（Mark を選ぶ）。", "① データの粒度",
                  "—", "normalizeSamplingUnit, samplingUnitMethods", "一部",
                  std_desc="Shot 単位（Shot を選び、その Mark をすべて使う）。"),
                F("アルゴリズム", "I 最適・D 最適・Sobol 列・ポアソンディスク・ランダム・Excel 取込から複数選び、選び方どうしを比べる。"
                  "通常版は I 最適・ランダムだけ。", "② アルゴリズム（Ctrl・Shift で複数）", "学習パターン",
                  "buildPlanSpecs, planTrainingShots", "一部",
                  std_desc="I 最適・ランダムから選ぶ（両方選ぶと選び方どうしを比べる）。"),
                F("I 最適・D 最適", "基準モデル（X,Y,半径 か X,Y の多項式、初期 5 次）の平均予測分散（I）または det(M)（D）がよくなる組を"
                  "交換法で探す（交換法の初期配置の数は初期値 3）。必ず計測する点は入れ替えない。", "基準モデルの次数・説明変数、交換法の初期配置の数",
                  "学習パターン、I 基準・D 基準", "constrainedIOptimal, exchangeDesign, blockSwapValues, designCriteria", "一部",
                  std_desc="I 最適：基準モデル（X,Y,半径 か X,Y の多項式、初期 5 次）の平均予測分散がよくなる組を交換法で探す（交換法の"
                           "初期配置の数は初期値 3）。必ず計測する点は入れ替えない。"),
                F("Sobol 列・ポアソンディスク", "Sobol 列の点に近い Shot を順に選ぶ／選んだ点どうしの距離が d 以上になるように選ぶ。",
                  "アルゴリズムの選択", "学習パターン", "sobolSequence, sobolSelect, poissonDiskSelect", "Pro"),
                F("ランダム", "制約を満たす組を乱数で選び、指定回数くり返す（乱数の種が同じなら同じ組）。", "ランダムの繰り返し回数",
                  "学習パターン（#1, #2, …）", "randomFeasibleShots"),
                F("Excel 取込", "人が決めた計測配置（パターン = 1・0、優先順 = 1・2・3…）の表を読む。計測マップの Excel も読める。",
                  "「Excel ファイルを読み込む…」", "学習パターン", "readLayoutPlans, parseLayoutPlans", "Pro"),
                F("制約", "半径（同心円の区切り [mm]）・4 象限・Scan 方向の区画ごとの数を、全候補の割合 × 選ぶ数 ± 許容幅にそろえる。",
                  "③ 制約（半径・象限・Scan 方向・許容幅）", "制約の違反量", "GroupQuota, shotGroupBounds, shotGroupViolation"),
                F("学習 Shot/Mark 数", "開始・終了・刻み（Shot 数の初期値 20〜80、刻み 5）か計測率 [%]（初期値 30〜80 %、刻み 10）でスイープする。"
                  "Mark 単位は Mark 数・1 Shot あたりの数も。",
                  "開始・終了・刻み、計測率で決める", "学習 Shot 数の並び（上限 100 通り）", "shotCountList, measurementRateList"),
                F("必ず計測する Shot", "指定した shotNo と、選べば最外周の Shot を先に学習に入れ、残りを選ぶ（拡張 I 最適計画）。",
                  "必ず計測する shotNo、最外周の Shot をすべて必ず計測する", "必ず計測する Shot の数", "requiredShotIndex, outerShots"),
                F("必ず計測する Mark・計測しない Shot/Mark", "Mark 単位で必ず選ぶ Mark、選ばない（評価には使う）Shot・Mark を指定する。",
                  "shotNo-markNo を空白区切り、計測マップのクリック", "—", "markPlanFixedMarks, parseMarkKeys", "一部",
                  std_desc="選ばない（評価には使う）Shot を指定する（Mark の指定は Mark 単位の Pro 版）。"),
                F("Mark 単位の制約", "Shot ごとに n 点の計測を必須にする、Mark 番号ごとの計測数を全計測の割合・均等にそろえる。",
                  "Shot ごとに n 点、Mark 番号ごとの計測数", "—", "trainingMarks, markPlanTypes", "Pro"),
                F("計測マップ", "Wafer と学習パターンを選んで、必ず計測（橙）・計測（青）・計測しない（白）・計測値なし（灰）の Shot を描く。"
                  "Scan 方向の色・同心円の区切りも描ける（最大 6 枚並べる）。", "Wafer、学習パターン、「計測マップを作る」",
                  "計測マップの図、Shot 数・計測率・I/D 基準・違反量", "drawMeasurementMap, plot.measurementMap"),
                F("計測マップのクリック指定", "図の Shot（Mark）をクリックして必ず計測・計測しない・指定を外すを切り替える。2 点の四角でまとめて指定もできる。",
                  "「クリックで」、範囲で選ぶ（2点をクリック）", "必ず計測・計測しないの欄", "setMeasurementSelection"),
                F("統計量の差・成分の差", "計測配置の点だけの統計量（平均・中央値・分散・最大・最小）と Overlay 補正の成分を、全計測と比べる。",
                  "下のタブ「統計量の差」「成分の差」", "差の表", "planStatisticsDifference, planComponentDifference"),
                F("計測マップの書き出し", "選んだ Wafer のすべての学習パターンを Excel に書く（計測マップ・学習パターン・成分の差・成分の係数・統計量の差）。",
                  "「Excel に書き出す…」「図を画像で保存…」", "Excel、PNG", "exportMeasurementMap"),
            ]),
            ("比べる手法", [
                F("推奨の組み合わせ・すべて選ぶ", "初期設定は GPR だけ。「推奨の組み合わせ」で GPR・TPS・XY 5 次多項式、「すべて選ぶ」ですべて"
                  "（通常版は RT モデルを除く）。",
                  "ボタン", "選んだ手法", "recommendedMethods"),
                F("GPR（ガウス過程回帰）", "10 カーネル・ν を指定する Matérn・周期カーネル × 説明変数（X,Y／X,Y,半径）× 質的変数の 6 通りの扱い"
                  "（使わない・同時推定・Backfitting・同時推定＋交互作用・加法カーネル・加法カーネル＋交互作用）。",
                  "カーネル、説明変数、質的変数の扱い", "GPR の手法", "models.gprFit, models.gprPredict, models.gprPredictVariance"),
                F("TPS（薄板スプライン）", "平滑化を GCV で選ぶ・なし・log10 λ を指定（複数で比べる）× 質的変数なし／Backfitting。",
                  "平滑化、Backfitting", "TPS の手法", "models.tpsFitPredict, models.spatialBackfit"),
                F("RBF", "ガウス型の動径基底関数＋1 次多項式。広がりと平滑化は GCV。", "チェック", "RBF の手法", "models.rbfFitPredict"),
                F("Kriging・Universal Kriging", "バリオグラム（linear・gaussian・power・exponential・spherical）× 質的変数なし／Backfitting。",
                  "バリオグラム", "Kriging の手法", "models.krigingFitPredict, models.krigingFitVariogram"),
                F("GAM", "形状関数（P-spline・ガウス過程回帰）を項ごとに選び、λ は REML。質的変数あり／なし。", "形状関数、カーネル",
                  "GAM の手法", "models.gamFitPredict, models.gamShapeFit"),
                F("XY 多項式", "次数を指定する多項式。", "次数", "多項式の手法", "models.polynomialFitPredict"),
                F("RT モデル", "X・Y を一緒に当てはめる RT モデル（次数を指定。1 変数では使わない）。", "次数", "RT モデルの手法",
                  "models.rtFitPredict", "Pro"),
                F("Fringe Zernike", "Fringe 番号の Zernike 多項式（次数 1〜7、Z64 まで）を単位円の座標で最小二乗近似。", "次数",
                  "Zernike の手法", "models.zernikeFitPredict, basis.fringeZernikeModes"),
                F("質的変数", "Scan 方向・Mark 番号・Shot 行の奇偶・Slot の偶奇・ファイルの列を選ぶ。X 成分と Y 成分で別にできる"
                  "（初期設定は X 成分が Mark 番号、Y 成分が Scan 方向・Mark 番号）。",
                  "質的変数の選択", "—", "factorNames, factorChoice, basis.effectCoding"),
                F("連続値の列", "数値の列を説明変数に足す（Wafer ごとに平均 0、座標と同じ標準偏差にそろえる）。", "連続値の列",
                  "手法の名前に列が付く", "continuousFeatures, numericColumns"),
                F("XY 1 次を除いてから推定", "学習点で XY 1 次を当てはめて除いてから推定する（初期設定は使わない）。", "チェック", "—", "estimateWafer"),
            ]),
            ("評価・Overlay 補正", [
                F("外周とみなす半径", "Mark の半径がこの値以上を外周として、外周・内側の RMSE を出す（初期値 120 mm）。", "外周とみなす Mark の半径 [mm]",
                  "外周・内側の RMSE", "computeMetrics"),
                F("学習データの異常値の除外", "学習点の平均と σ（または MAD）から n × σ を超える Mark を X・Y の両方から除いて推定する。",
                  "チェック、n、nσ・MAD", "学習から除いた異常値の数", "trainingOutliers"),
                F("処理時間の記録", "各手法の最初の推定の前に予備の推定をして、初回だけの時間を除いた処理時間を記録する。", "チェック",
                  "Excel の「処理時間」", "runEvaluation"),
                F("評価に使う Wafer", "すべて・枚数・割合で、先頭からかランダムに Wafer を選ぶ。", "評価に使う Wafer の欄",
                  "評価した Wafer", "evaluationUnitIndex"),
                F("Overlay 補正の評価の成分", "Wafer 成分（なし・1〜5 次）・Shot 共通成分（なし・1 次）・Shot ごとの成分（なし・1 次）を組み合わせ、"
                  "推定誤差で Overlay 残差がどれだけ増えるかを評価する（「5. 未知の座標の推定」の補正の比較の基準の補正にもなる）。",
                  "成分ごとのプルダウン", "OVL の 8 つの指標", "overlayCorrection, overlayDesign, overlayTerms"),
                F("補正の式の入力", "各成分で「式を入力」を選び、dx・dy の式（例：k1 + k3*x + k5*y）を書く。誤りは赤字で出して評価しない。",
                  "dx =・dy = の欄", "入力した式の補正", "parseCorrectionFormula", "Pro"),
            ]),
        ],
    },
    {
        "key": "3", "title": "3. 結果一覧", "file": "ResultsTab.m",
        "summary": "評価の結果を表・グラフで比べ、計測配置・誤差・補正の観点で分析する。中のタブは 表・グラフ／計測配置／誤差の分析／補正の比較 の4つのまとまり。",
        "groups": [
            ("上の欄（絞り込み・書き出し・読み込み）", [
                F("評価点の絞り込み", "半径・Scan 方向・最外周・shotNo の条件に合う評価点だけで指標を計算し直す（表・グラフ・マップに効く）。",
                  "半径の下限・上限、Shot の条件", "絞り込んだ指標", "filterResults, pointFilterMask"),
                F("結果を Excel に書き出す", "説明・集計・集計_統計量・Waferのベスト・ワースト・Wafer ごと・学習 Shot・処理時間・設定のシートを書く。",
                  "「結果を Excel に書き出す…」", "評価結果の Excel", "exportResults"),
                F("推定値を Excel に書き出す", "Mark ごとの座標・計測値・推定値・残差・区分・質的変数（と Overlay 残差）を書く。範囲を選べる。",
                  "「推定値を Excel に書き出す…」", "推定値の Excel", "exportEstimates, collectEstimates"),
                F("結果を読み込む", "書き出した評価結果の Excel から、表・グラフ・基準の手法との比較を描き直す（計測ファイル不要）。",
                  "「結果を読み込む…」", "結果一覧", "importResults"),
                F("推定値の Excel を読み込む", "同じ評価の推定値の Excel を組にして、マップ・誤差の分布・散布図・分布の比較も使えるようにする。",
                  "「推定値の Excel を読み込む…」", "マップ・分析の図", "importEstimates"),
            ]),
            ("表・グラフ", [
                F("表", "手法 × 学習パターンの指標（各列の最良に ★）。集計は平均・中央値・ワースト値・95%値。", "指標、集計",
                  "結果の表", "summarizeResults, metricNames, statisticNames"),
                F("グラフ", "手法 × 計測点の選び方ごとの線。横軸は学習 Shot 数（計測率）か I 基準・D 基準。エラーバー・Wafer ごとの点も描ける。",
                  "手法、選び方、横軸、エラーバー", "グラフ（PNG 保存・コピー）", "groupSelectionTypes, layoutErrorBars"),
                F("基準の手法との比較", "同じ Wafer・学習パターンどうしの差の平均・95% 区間・基準より良かった Wafer の割合。", "基準の手法",
                  "比較の表", "pairedComparison"),
                F("Waferベスト/ワースト", "指標ごとのベスト・平均に近い・ワーストの Wafer と、選んだ指標の順位の平均による総合。",
                  "手法、学習パターン、総合に使う指標", "2 つの表", "waferRanking, perUnitValues", "一部",
                  std_desc="R²（X・Y・X と Y の合計）ごとのベスト・平均に近い・ワーストの Wafer と、R²（X と Y の合計）の順位による総合"
                           "（RMSE [nm] 以降の指標は Pro 版）。"),
            ]),
            ("計測配置", [
                F("計測を足す場所", "推定誤差か GPR の推定の分散が大きい上位 n、または閾値より大きい Shot・Mark を、値のヒートマップと出す。"
                  "選んだ候補を「必ず計測」の欄に入れる。", "基準・値・集計・単位・選び方、「候補を出す」「必ず計測の欄に入れる」",
                  "候補の表とヒートマップ", "measurementCandidates, plot.valueHeatmap"),
                F("Mark の Shot を入れる", "単位を Mark にして出した候補のうち「足す」を選んだ Mark のある Shot を、必ず計測する shotNo に足す"
                  "（同じ Shot は 1 つ。Shot 単位の学習パターンに効く）。", "「Mark の Shot を入れる」", "必ず計測する shotNo",
                  "addMeasurementCandidates（shot）"),
                F("計測配置の比較", "選び方ごとに、計測する Mark の数・学習 Shot 数・D 効率・I 効率に対する指標と I 基準・D 基準を比べる。",
                  "横軸、エラーバー", "比較の図・表", "layoutComparison, drawLayoutComparison"),
                F("補正の悪化", "計測 Shot 数（初期値）・計測する Mark の数・推定誤差 RMSE に対する、推定による重ね合わせ補正の悪化を"
                  "手法 × 選び方の線で描く。", "手法、選び方、横軸", "悪化の図", "overlayDegradation", "一部",
                  std_desc="計測 Shot 数（初期値）・計測する Mark の数に対する、推定による重ね合わせ補正の悪化を手法 × 選び方の線で描く"
                           "（推定誤差 RMSE の横軸は Pro 版）。"),
            ]),
            ("誤差の分析", [
                F("推定値と誤差の分布", "ヒストグラム・正規性検定（Shapiro–Wilk・Anderson–Darling）・ANOVA。手法を複数選んで並べる。",
                  "手法、学習パターン、Wafer", "分布の図と検定の表", "residualAnalysis, stats.normalityTests, stats.anovaMainEffects"),
                F("残差の箱ひげ図", "ANOVA の質的変数の水準ごとの残差を、手法で色分けして並べる。", "質的変数、手法", "箱ひげ図",
                  "plot.residualBoxplot"),
                F("推定値と実測値の散布図", "推定値と実測値の散布図。外周・内側、象限、Slot の偶奇、質的変数で色分けできる。", "色分け",
                  "散布図と相関", "plot.estimateScatter, scatterSummary"),
                F("残差と説明変数", "座標・半径・方位角・Shot 内の位置と残差の相関（|r| ≥ 0.3 を色付き）。", "説明変数",
                  "散布図と相関の表", "residualFactors, plot.residualVsVariable"),
                F("分布の比較", "Wafer 全面・学習・予測対象・推定値のヒストグラム、代表統計値、JS ダイバージェンス。", "手法、学習パターン",
                  "分布の図と表", "distributionComparison, stats.jsDivergence"),
                F("処理時間の内訳", "学習パターンの作成・異常値の判定・学習・推論などの割合を測る（1〜10 回）。", "回数、「測る」",
                  "積み上げ横棒", "timingBreakdown, plot.timingBars"),
            ]),
            ("補正の比較", [
                F("実測値と推定値の補正", "実測値と推定値で求めた Shot 高次補正を計測値に当てて比べる（図・表）。", "手法、学習パターン、Wafer",
                  "比較の図・表", "estimatedCorrectionComparison"),
                F("補正残差のばらつき分解", "補正前の値と補正した残差のばらつきを Lot 間・Wafer 間・Shot 間・その他に分けて比べる。"
                  "図・表は保存・コピーできる。", "「計算する」、縦軸", "段ごとの 3σ か分散の図・表",
                  "correctionVarianceDecomposition"),
            ]),
        ],
    },
    {
        "key": "4", "title": "4. Waferごとのマップ", "file": "MapTab.m",
        "summary": "1つの条件（Wafer・学習パターン・手法）の計測値・推定値・残差を Wafer 上に描き、条件を並べて比べる。",
        "groups": [
            ("マップ", [
                F("マップの表示", "計測値・推定値・残差を矢印か X・Y の色で描く。Shot の枠（Scan 方向の色分け）・同心円・点の大きさ・矢印の倍率。",
                  "Wafer、学習パターン、手法、図の内容、表示", "マップ（PNG 保存・コピー）", "showMap, plot.waferMap"),
                F("Overlay 補正の図", "実測値で補正した残差・推定値で補正した残差・推定による変化を並べ、|平均|+3σ を出す。", "図の内容「Overlay 補正」",
                  "3 つの場のマップ", "overlayCorrection"),
                F("並べて比べる", "右の一覧に条件を足し（最大 6）、同じ値の種類・色の範囲で並べる。", "「条件を足す」、並べて比べる値",
                  "並べたマップ", "addMapCondition, removeMapConditions"),
                F("Shot スタックマップ", "全 Shot を Shot 内の座標で重ね、分け方（Scan 方向など）ごとに並べる。", "Shot スタックマップの分け方",
                  "スタックマップ", "plot.shotStackMap"),
                F("平均の図と楕円", "全 Wafer・LotID・EqpId・Operation・Slot の偶奇の平均と共分散楕円。楕円だけも描ける。",
                  "Wafer の選択（平均）、楕円だけ描く", "平均のマップ", "averageFields, plot.covarianceEllipses"),
                F("Shot 番号と指標", "Shot 中心に shotNo を重ね、図の下に RMSE・ワースト値・95%値・MAE（X・Y）を出す。", "Shot 番号",
                  "図の題名と説明", "plot.shotNumbers"),
                F("推定の分散を並べる（GPR）", "GPR の手法では推定の分散の色の図も並べる。", "推定の分散を並べる（GPR）", "分散の図",
                  "models.gprPredictVariance"),
            ]),
        ],
    },
    {
        "key": "5", "title": "5. 未知の座標の推定", "file": "TargetTab.m",
        "summary": "計測していない座標（新しい Mark の位置・Wafer 上の任意の点）の値を推定し、重ね合わせ補正値を求める。",
        "groups": [
            ("推定する点", [
                F("Excel・CSV から読み込む", "Xmm・Ymm（必須）・markXmm・markYmm・markNo・shotNo・Direction・名前の表を読む。", "「Excel・CSV から読み込む…」",
                  "点の表", "readTargetPoints"),
                F("画面で作る", "行を追加、全 Shot の同じ位置に置く、格子で置く（上限 20,000 点）、選んだ行・すべてを消す。",
                  "「行を追加」「全 Shot に置く」「格子で置く」", "点の表", "targetGrid, addTargetPoints, setTargetPoints"),
            ]),
            ("推定", [
                F("条件を選ぶ", "Wafer と学習データ（計測値のある全 Mark、または評価の学習パターン）を複数選び、組み合わせごとに一括で推定する。",
                  "Wafer、学習データ、手法", "—", "estimateTargets"),
                F("推定する", "評価と同じ計算で、点を計測値の無い Mark として足して推定する。外挿（凸包の外 0.5 mm 超）・Wafer の外（推定値 0）・"
                  "学習に無い Mark 番号を知らせる。", "「推定する」", "メッセージ、図、推定値の表", "predictTargets, estimateWafer"),
                F("図・推定値の表", "推定値の矢印か色、学習点、学習点の範囲（凸包の破線）、外挿の点の ×。任意の半径の円を重ねられる。"
                  "表は外挿・Wafer の外の行を色付き。", "図・補正に出す組み合わせ、重ねる円 [mm]", "図、表", "plot.targetMap, plot.radiusCircles"),
                F("推定値を Excel に書き出す", "「推定値」「説明」シートに書く（「推定値」はそのまま点として読み直せる）。",
                  "「推定値を Excel に書き出す…」", "Excel", "exportTargetEstimates"),
                F("GPR の推定の分散", "GPR の手法では推定の分散を色の図・表・Excel に出す。", "—", "分散の図・列", "models.gprPredictVariance"),
            ]),
            ("重ね合わせ補正", [
                F("重ね合わせ補正値を計算する", "元の実測値・学習しなかった Mark の推定値・未知の座標の推定値をまとめて、このタブの補正のモデルを当てはめる。",
                  "「重ね合わせ補正値を計算する」", "補正前・補正後の |平均|+3σ と補正値（係数）", "targetOverlayCorrection"),
                F("補正のモデル", "このタブの補正の式（「2.」の基準の補正とは別）。Wafer 成分（0〜5 次）・Shot 共通成分（1 次・2 次・ASML・Canon・"
                  "Nikon・カスタム）・Shot ごとの成分を選び、項を表のチェックで選ぶ（0 次・1 次は外せない）。未知の座標の推定値で Shot 内の点が"
                  "増えるので、高次の式で補正できる。", "式のプルダウン、項の「使う」、「すべての項を使う」", "項の表",
                  "targetCorrectionChoice, targetCorrectionTerms, overlayTermKeys"),
                F("補正値の書き出し", "「補正値」「補正の残差」「補正に使った点」シートと、点ごとの補正量・補正後の残差の列を足す。",
                  "「補正値を Excel に書き出す…」", "Excel", "exportTargetEstimates"),
                F("補正残差のマップ", "補正後の残差・補正量・補正前の値を矢印か色で描く。補正前・補正量・残差を並べる（矢印の倍率をそろえる）、"
                  "Shot スタックマップ（全 Shot を Shot 内の座標で重ねる）、任意の半径の円を重ねる。点の種類で絞れる。",
                  "値、点、表示、並べ方、図、重ねる円 [mm]", "マップ（PNG 保存・コピー）",
                  "plot.correctionMap, plot.shotStackMap, drawTargetCorrectionMap"),
                F("補正の比較（全計測と比べる）", "① 全計測・② 一部計測＋面内推定を基準の補正（2. の条件）で、③ 全計測・④ 一部計測＋面内推定に"
                  "未知の座標の推定値を足してこのタブの補正で補正し、計測値のある Mark の補正後の |平均|+3σ を表・棒・残差の図で比べる。",
                  "「全計測と比べる」、図の補正", "比較の表・棒・図（PNG 保存・コピー）", "targetCorrectionComparison, compareTargetCorrection"),
            ]),
        ],
    },
    {
        "key": "6", "title": "6. Shot高次補正", "file": "HighOrderTab.m ほか 4 ファイル",
        "summary": "計測値・推定値・Excel の値で Shot 高次補正の k パラメータを求め、補正の効果を評価・比較する。右の中のタブは 入力と項／結果／比べる の3つのまとまり。",
        "groups": [
            ("① 入力のデータ", [
                F("入力のデータ", "1. の計測データ・3. の評価の推定値（手法・学習パターン。学習した Mark は計測値）・5. の推定値（実測値も使う）・"
                  "Excel・CSV（列の名前は自由、読んだ後で列を選ぶ）から選び、Wafer を選ぶ。",
                  "入力、手法・学習、「Excel・CSV から読み込む…」、Excel・CSV の列、Wafer", "Wafer ごとのデータ",
                  "readHighOrderFile, prepareHighOrderData, highOrderColumns"),
            ]),
            ("② 補正の式と k パラメータ", [
                F("補正の式", "ASML（k1〜k19）・Canon・Nikon（ルールの式のまま）・カスタム（k1〜k38）・1 次（k1〜k6）・2 次（k1〜k12）。",
                  "補正の式", "使う項の表", "highOrderTerms"),
                F("補正のくくり", "k の組を Wafer 内で共通・選択 Wafer で共通・Scan 方向ごと・行の偶奇ごと・Shot ごとに求める。", "補正のくくり",
                  "k の組", "shotHighOrder"),
                F("外周の半径・外周の式", "Shot 中心の半径が外周の半径（初期 120 mm）以上の Shot だけ別の式で補正する。", "外周の半径、外周の式",
                  "内周・外周の k", "highOrderTerms, shotHighOrder"),
                F("Wafer 補正", "Wafer 成分（Shot 中心の 1〜5 次）と Wafer RT（すべての Shot・外周だけ、次数 1〜5）を先に引く。",
                  "Wafer 成分、Wafer RT、RT の次数", "Wafer 高次補正の残差", "shotHighOrder, basis.rtDesign"),
                F("Shot 共通補正", "なし・計算する・値を入力。Shot 共通の k を先に引き、残りを組ごとに求める（Shot 共通の式・Shot ごとの次数も選ぶ）。",
                  "Shot 共通補正、補正の式、Shot ごとの次数、共通の値", "Shot 共通の k", "highOrderSequential, highOrderSharedFormula"),
                F("使う項と VIF", "項ごとに「使う」を選ぶ（k1〜k6 は外せない）。VIF（全項・使う項）を出し、VIF で選ぶ・すべての項を使う。",
                  "使う項と VIF の表、「VIF で選ぶ」「すべての項を使う」", "VIF の表", "highOrderVif, varianceInflation"),
                F("点が足りない Shot", "全体の項を減らす（初期値）・その Shot だけ項を減らす・その Shot は補正しない。計算の前に決まらない項を知らせる。",
                  "点が足りない Shot", "⚠ のメッセージ", "shotHighOrder（checkOnly）"),
                F("項の組み合わせの保存", "補正の式と使う項に名前を付けて保存・呼び出し・削除する（次に開いたときも使える）。", "名前、「保存」「呼び出す」「削除」",
                  "保存した組み合わせ", "saveHighOrderTermSet, applyHighOrderTermSet"),
            ]),
            ("③ 回帰と計算", [
                F("回帰", "損失関数（最小二乗・Huber・LAD）と、選んだ次数の項だけの正則化（なし・L2・L1、λ）を X・Y 別に選ぶ。",
                  "損失関数、c、正則化、かける次数、λ", "—", "robustRidgeFit"),
                F("補正を計算する", "選んだ Wafer で k パラメータを求め、決定係数 R²・自由度調整済 R² も出す。", "「補正を計算する」",
                  "結果のタブ", "computeHighOrder, shotHighOrder, highOrderRSquared"),
            ]),
            ("結果", [
                F("補正の評価", "補正前・Wafer 高次補正だけ・＋Shot 共通補正・Shot ごとの 1 次・高次補正の残差の |平均|+3σ、|残差| の 95% 点・中央値（内周・外周も）。",
                  "内周・外周に分けて出す", "評価の表", "shotHighOrder（summary）"),
                F("外れ値を除いた |平均|+3σ", "Wafer ごと・軸ごとに、高次補正の残差の中央値から n × 1.4826 × MAD より離れた点を外れ値として除いた "
                  "|平均|+3σ と、除いた点の数を出す（n は初期値 3。変えても計算し直さない）。", "外れ値の判定 n", "評価の表・Excel の列",
                  "highOrderTrimmedSummary"),
                F("マップ", "Wafer 上・Shot を重ねる・1 つの Shot で、矢印・色・グリッド（変形した Shot の枠）を描く。並べる・Wafer を重ねる。",
                  "値、図の種類、表示、グリッドの刻み・倍率", "マップ（PNG 保存・コピー）",
                  "drawHighOrderMap, plot.correctionMap, plot.shotStackMap, plot.shotGridMap"),
                F("ヒストグラム", "補正前・段階ごとの残差（または補正の比較の条件）を X・Y × すべて・内周・外周の 3 段に重ねる。", "Wafer、値",
                  "ヒストグラム", "drawHighOrderHistogram, plot.residualHistogram"),
                F("補正値テーブル", "行（Wafer・k の組・Shot）ごとの回帰の残差と使う項の係数（mm の座標での値）。", "式（dx・dy）、Wafer",
                  "補正値の表", "showHighOrderSummary"),
                F("書き出し", "点ごとの値（計測データの形で読み直せる）・Shot ごとの補正値・補正の比較の全条件を CSV・Excel に書く。",
                  "書き出すもの、値、「書き出す…」", "CSV（UTF-8・BOM）・Excel",
                  "writeHighOrderTable, highOrderMeasurementTable, highOrderShotTable"),
                F("結果を Excel に書き出す", "説明・補正の評価・補正の比較・Shot ごとの比較・補正値・Shot ごとの補正値・項と VIF・残差の成分・点ごとの値。",
                  "「結果を Excel に書き出す…」", "Excel", "exportHighOrder, highOrderLevels"),
            ]),
            ("比べる", [
                F("k の選定", "変数重要度（|t 値| の中央値がしきい値未満の項を外す）・ステップワイズ（BIC・AIC・自由度調整済 R²）で項を選び、表に反映する。",
                  "方法、しきい値、指標、「反映する」", "選んだ項", "highOrderTermSelection"),
                F("結果の履歴", "計算するたびに評価と設定を足す（最大 50 件）。選んだ結果を棒で並べ、設定に戻す・消す。",
                  "「選んだ条件を設定に戻す」「選んだ結果を消す」", "履歴の表・図", "restoreHighOrderHistory"),
                F("他の Wafer の補正", "補正元の Wafer で求めた補正値を補正先に当て、補正先で求めた補正と比べる（複数なら補正値の平均か実測値の平均）。",
                  "補正元、補正先、補正元が複数", "比較の表", "transferHighOrder"),
                F("補正の比較", "条件（くくり・損失関数・λ・項の組み合わせ）を足し、まとめて計算して |平均|+3σ などを表と図に並べる。",
                  "足す条件、「条件を足す」「すべて計算して比べる」", "比較の表・図", "compareHighOrderConditions"),
                F("2 つの条件を並べる", "基準と比べる条件の残差を並べ、改善（青）・悪化（橙）した Shot を示す。", "選ぶ元、基準、比べる条件、同じとみなす差",
                  "並べた図、Shot ごとの表", "compareHighOrderShots"),
                F("λ・c のスイープ", "λ・Huber の c を範囲と評価数で変え、当てはめた残差と 1 点抜きの予測の誤差の推移から最もよい値を選ぶ。",
                  "変える値、開始・終了・評価数、「スイープを実行する」「最もよい値を使う」", "推移の図・表", "sweepHighOrder"),
                F("Wafer の比較", "Wafer ごとの k パラメータか、dx・dy の残差（補正の段階ごとの棒）を並べる。", "値、式",
                  "比較の図", "drawHighOrderWaferComparison"),
            ]),
        ],
    },
    {
        "key": "7", "title": "7. Mark配置最適化", "file": "MarkLayoutTab.m",
        "summary": "Shot 高次補正の計測 Mark の配置を Mark の数ごとに I 最適計画で選び、制御残差と I 効率で比べる。",
        "groups": [
            ("入力と条件", [
                F("入力", "画面で入力する座標（格子で置く・行を足す）・1. の計測データ・6. の入力・Excel・CSV（座標だけの表も）。",
                  "入力、「格子で置く」「Excel・CSV を読み込む…」", "候補の Mark", "markCandidates, markLayoutFileData"),
                F("必ず計測・計測しない Mark", "表のチェックか図のクリックで指定する。必ず計測はどの数の配置にも入れ、計測しないは評価だけに使う。",
                  "候補の Mark の表、図のクリック", "—", "setMarkLayoutRequired, setMarkLayoutExcluded"),
                F("補正の式と回帰", "ASML・Canon・Nikon・カスタム・保存した組み合わせ、VIF で選ぶ、6. の式を写す。回帰は 6. と同じ。",
                  "補正の式、「VIF で選ぶ」「6. の式を写す」", "使う項", "highOrderTerms, robustRidgeFit"),
                F("配置の選び方と評価", "Mark の数の最低数・最大数（0 は自動）、探す回数、評価に使う値（実測値・乱数 Shot）。",
                  "最低数、最大数、探す回数、評価に使う値", "—", "markLayoutOptions"),
            ]),
            ("計算と結果", [
                F("乱数 Shot 生成", "次数ごとの大きさ・ばらつき・飛び値で乱数の Shot の形（最大 1000 通り）を作り、代表の形を描く。",
                  "形の数、次数ごとの大きさ、ばらつき、飛び値、「乱数で Shot を生成する」", "代表の形の図", "randomShotShapes"),
                F("配置を最適化する", "Mark の数ごとに I 基準が最小の配置を交換法で選び、配置ごとの制御残差を求める。", "「配置を最適化する」",
                  "制御残差推移・配置・表", "markLayoutStudy, iOptimalMarks, evaluateMarkLayouts"),
                F("制御残差推移", "横軸 I 効率・I 基準・Mark の数・D 効率・D 基準、縦軸 |平均|+3σ・95% 点・中央値・RMS。", "横軸、縦軸、範囲",
                  "推移の図", "drawMarkLayoutChart"),
                F("配置", "選んだ Mark の数の配置（計測 ●・候補 ○・必ず計測 ◇・計測しない ×）と制御残差のスタックマップ。", "Mark の数",
                  "配置の図", "drawMarkLayoutMap"),
                F("表と書き出し", "Mark の数ごとの I 効率・制御残差・入れ替えた Mark の数。全体か選んだ配置だけを Excel に書く。",
                  "「結果を Excel に書き出す…」「この配置を Excel に書き出す…」", "Excel", "exportMarkLayouts, exportMarkSelection"),
            ]),
        ],
    },
    {
        "key": "8", "title": "8. 計測Mapローテ", "file": "RotationTab.m",
        "summary": "Shot・Mark ごとのばらつき（3σ）で計測の優先度を分け、n 枚のローテーションの計測マップを作り、FB の補正値で検証する。",
        "groups": [
            ("① 入力", [
                F("入力と対象", "計測データ・評価の推定値・未知の座標の推定値・6. で読み込んだ Excel・CSV・このタブで読む Excel・CSV から選び、"
                  "Operation・装置で絞る。",
                  "入力、「Excel・CSV を読み込む…」、対象", "—", "setRotationInput, rotationColumns"),
            ]),
            ("② ばらつき", [
                F("ばらつきを求める", "同じ Shot・Mark の Wafer 間の 3σ（X・Y・長さ |v|）。Shot ごとは Mark の最大か平均（ボタンは青緑）。",
                  "単位、Shot ごとの集計、「ばらつきを求める」",
                  "ばらつきの表と図", "markVariability"),
                F("3σ の分布・半径と指標", "3σ の分布か、半径に対する 3σ と累積 [%] の線・累積率の半径を描く。", "図の種類、累積を重ねる、累積率",
                  "ばらつきの図", "radialCumulative"),
            ]),
            ("③ 優先度と計測マップ", [
                F("優先度", "X・Y・|v| の 3σ のしきい値（値か累積 %）で優先度を分ける。外周の半径以上・指定した Shot は優先度 1。",
                  "指標、しきい値、優先度 1 の外周・Shot", "優先度", "rotationMaps"),
                F("計測マップを作る", "優先度 1 は毎回、最も低い優先度は M 枚に 1 回計測するマップを作る（振り分けは I 最適・D 最適・ポアソンディスク・"
                  "ランダム・表の順。ボタンは青）。",
                  "計測マップの数、振り分け、「計測マップを作る」", "計測マップの図と表", "rotationMaps, rotationCriterionExchange"),
                F("振り分けの比較", "5 つの振り分けを、マップ間の KL・全体との KL・最大の空白・I 基準・D 基準で比べる。", "「比べる」",
                  "比較の表と棒", "compareRotationAssignments, rotationMapMetrics"),
                F("重ねる円・shotNo", "図に半径の円と shotNo を重ねる。", "重ねる円、shotNo を重ねる", "図", "plot.radiusCircles, plot.shotNumbers"),
            ]),
            ("④ FB の検証", [
                F("検証する", "Wafer を日時・LotID・読み込みの順に並べて FB 側と検証側に分け、FB 側の補正値（2. の Overlay 補正か 6. の Shot 高次補正）を"
                  "検証側に当てた補正残差を求める。", "並べ方、分け方、Lot 数、補正のモデル、「検証する」", "補正残差", "feedbackSimulation"),
                F("条件の比較", "検証した条件と結果（計測率・補正残差）を表に足し、選んだ条件を並べて描く。全計測とも比べられる。",
                  "全計測とも比べる、条件の選択", "比較の表と図", "compareRotationConditions"),
                F("計測マップを書き出す", "計測マップ・ばらつき・説明のシートを書く（「2.」の Excel 取込で読める）。", "「計測マップを書き出す…」",
                  "Excel", "exportRotationMaps"),
            ]),
        ],
    },
    {
        "key": "C", "title": "共通の機能（メニュー・表示・ヘルプ）", "file": "Display.m・Core.m",
        "summary": "どのタブでも使う表示の設定・図の保存・ヘルプ・起動と終了の機能。",
        "groups": [
            ("メニュー「設定」", [
                F("ライトモード・ダークモード", "画面の欄・表・図の色を切り替える（次に開いたときも同じ。ダークモードでは空の表をしまい、白く浮かせない）。",
                  "設定 → ライトモード・ダークモード", "画面の色", "setTheme, applyTheme, watchTables", "Pro"),
                F("文字の大きさ", "12・14・16（標準）・18・20 pt。図の文字・決まった幅の欄も同じ比で変える。", "設定 → 文字の大きさ",
                  "画面の文字", "setFontSize, scaleFonts"),
                F("凡例の位置", "すべての図、または図を右クリックしてその図だけの凡例の位置を選ぶ。", "設定 → 凡例の位置、図の右クリック",
                  "凡例", "setLegendLocation, resetLegendOverrides", "Pro"),
                F("Scan 方向の向きと色", "Scan 方向 1・2 の向き（▲・▼）と色を選ぶ（推定の結果は変わらない）。", "設定 → Scan 方向の向きと色",
                  "図の印と色", "setScanStyle, resetScanStyle"),
                F("画面の大きさに合わせる", "今の画面の中央に、画面に収まる大きさで合わせ直す（別の画面に移ったときは自動）。", "設定 → 画面の大きさに合わせる",
                  "窓の大きさ", "fitToScreen"),
                F("乱数の種", "計測点の選び方・Mark 配置最適化で共通の乱数の種。同じ種なら同じ結果。", "設定 → 乱数の種…", "—", "setRandomSeed"),
            ]),
            ("図・ヘルプ・起動", [
                F("図を画像で保存・コピー", "凡例・色の目盛りも入れた PNG を保存、または同じ画像をクリップボードにコピーする（図が複数なら横に並べて1枚）。",
                  "「図を画像で保存…」「図をコピー」", "PNG（150 dpi）、クリップボード", "saveFigureImage, copyFigureImage"),
                F("ヘルプ", "別の窓でヘルプを開く。機能編（タブごとの使い方・用語）と技術編（式・計算の方法）を切り替える。", "メニュー「ヘルプ」",
                  "ヘルプの窓", "openHelp, help/help.html"),
                F("タブを初めて開いたときに作る", "3〜8 のタブは初めて開いたときに中身を作る（起動を速くするため）。", "タブのクリック",
                  "「タブを準備しています」", "ensureTab, finishBuiltTab"),
                F("タブの色分け", "業務でつながるタブを見出しの文字の色で分ける：2〜5（面内推定の設定・結果一覧・マップ・未知の座標）は青、"
                  "6・7（Shot 高次補正・Mark 配置）は橙。", "—", "タブの見出し", "startApp（ESTIMATION_TAB_COLOR・CORRECTION_TAB_COLOR）"),
                F("通常版と Pro 版", "通常版は RT モデル・計測点の選び方（D 最適・Sobol 列・ポアソンディスク・Excel 取込・Mark 単位）・Overlay の式・"
                  "ダークモード・凡例の位置・一部の指標と横軸を使わない。Pro 版の設定を読むと使える設定に直して知らせる。",
                  "runAlignmentEstimationAppStandard・runAlignmentEstimationApp", "窓の名前「（通常版）」", "editionSettings"),
            ]),
        ],
    },
]


def numbered_sections():
    """機能に ID（F1-01 など）を付けた SECTIONS を返す"""
    result = []
    for section in SECTIONS:
        count = 0
        groups = []
        for title, items in section["groups"]:
            rows = []
            for item in items:
                count += 1
                row = dict(item)
                row["id"] = f"F{section['key']}-{count:02d}"
                rows.append(row)
            groups.append((title, rows))
        result.append({**section, "groups": groups, "count": count})
    return result


def feature_count():
    return sum(section["count"] for section in numbered_sections())
