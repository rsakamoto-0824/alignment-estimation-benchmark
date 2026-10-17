# alignment-estimation-benchmark

アライメント計測値の面内推定で、**どの手法と説明変数を選ぶか**を、乱数で作った模擬 Wafer 1,000枚で比べる評価です（Python）。
制約付き I 最適計画で選んだ 10〜40 Shot を学習データとし、未計測 Shot の全 Mark を推定して、
決定係数・自由度調整済み決定係数・RMSE・MAE で評価します。

- 結果の説明資料（PowerPoint、30枚・ノートつき）：[docs/アライメント計測値の面内推定_手法比較_説明資料.pptx](docs/アライメント計測値の面内推定_手法比較_説明資料.pptx)（生成元は [docs/results-briefing_src/](docs/results-briefing_src/README.md)）
- **実データ検証ツール（MATLAB アプリ、画面つき・スタンドアローン版を作れる）**：[matlab_app/](matlab_app/README.md)
- 設計メモ（指定と、確認して決めたこと・仮定）：[design.md](design.md)
- 課題・確認事項：[issues.md](issues.md)

数値はすべて乱数で生成した模擬データによります。実データ・社内データは使っていません。

## 比べたもの

| 区分 | 内容 |
| --- | --- |
| 手法（7系統・123設定） | GPR（MATLAB fitrgp の10カーネル）、TPS、Kriging、Universal Kriging（バリオグラム linear・gaussian・power・exponential）、GAM、XY5次多項式、RT モデル |
| 説明変数 | X, Y ／ X, Y, 半径 ／ X, Y, 半径, T（T は ASML R&T の接線方向の位置＝方位角 θ） |
| 質的変数（Scan 方向・Mark 番号） | GPR：使わない／基底関数で同時推定／Backfitting。GAM：説明変数に追加 |
| 計測 Shot 数 | 10, 15, 20, 25, 30, 35, 40（制約付き I 最適計画） |

模擬データは「Zernike（動径次数10以下の66項から10〜30項）の面内傾向 ＋ Mark 番号ごとの Offset ＋ Scan 方向の差 ＋ 一様ノイズ（中心 ±1 → 最外周 ±3 nm）」です。

## 結果の要点（1,000枚の平均、未計測 Shot の全 Mark の RMSE（X・Y）[nm]）

系統ごとに、全 Shot 数の平均 RMSE が最小の設定を1つ選んだ値です（GPR は同時推定から選択）。

| 系統（代表の設定） | 10 Shot | 20 Shot | 40 Shot | R²（40 Shot） |
| :--- | ---: | ---: | ---: | ---: |
| GPR matern52｜X, Y, 半径｜質的変数を同時推定 | 3.91 | **1.65** | **0.77** | 0.986 |
| TPS｜X, Y, 半径 | **3.73** | 2.86 | 2.44 | 0.856 |
| Kriging exponential｜X, Y, 半径 | 4.32 | 3.09 | 2.74 | 0.819 |
| Universal Kriging exponential｜X, Y, 半径 | 4.61 | 3.23 | 2.71 | 0.823 |
| GAM｜X, Y, 半径, T（質的変数あり） | 4.90 | 2.55 | 1.25 | 0.960 |
| XY5次多項式 | 4.75 | 3.66 | 3.25 | 0.753 |
| RT モデル（K = 5） | 4.94 | 3.73 | 3.31 | 0.745 |

- **手法**：15 Shot 以上は GPR（matern52 または rationalquadratic、X, Y, 半径、質的変数あり）が最良。10 Shot では TPS（X, Y, 半径）が最良で、質的変数なしの GPR（matern32、3.78 nm）が続く。
- **質的変数（Scan 方向・Mark 番号）**：GPR に入れると 40 Shot で RMSE が平均 −64%。15 Shot で −11%。10 Shot では +6% と逆効果（点が少なく Mark ごとの Offset を誤って推定する）。
- **Backfitting**：同時推定（基底関数）と RMSE の差が 0.01 nm 未満の場合が 91%。同じ尤度の座標上昇法なので同じ解に収束する。教科書どおり（1回ずつ交互）に当てはめると、10〜20 Shot では収束が遅く精度も悪化した（補足検証 50枚）。
- **説明変数**：半径を足すと GPR で 1.5〜5% 改善。T（方位角）を足すと GPR・TPS・Kriging では悪化し、ARD カーネルでは T の長さスケールが 59〜80% で上限に張り付く（T を無視）。GAM だけは T を足しても悪化しない。
- **カーネル**：X, Y, 半径 では等方の matern52 が最良、exponential が最も悪い。ARD 版は T を入れても崩れない。
- **Kriging**：PyKrige 既定の経験バリオグラム（6区間）ではナゲットを過大に推定し、GPR に大きく劣る。ガウス型はナゲットが 0 になると不安定（RMSE > 20 nm が 211 件、すべてガウス型）。
- **指標**：R²・調整済み R²・RMSE・MAE の順位相関は 0.97 以上。調整済み R² は有効自由度の大きいモデル（指数カーネル・指数バリオグラム）に厳しい。

### 追加検証：GPR の質的変数を加法カーネルで扱う（2026-10-14）

「GPR の同時推定は加法カーネルか？」（答え：いいえ。質的変数は平均の基底関数＝固定効果）を受けて、
質的変数を加法カーネル（変量効果）で扱う方法などを同じ1000枚・同じ計画で比べました。
資料：[docs/GPRの質的変数を加法カーネルで扱う_追加検証.pptx](docs/GPRの質的変数を加法カーネルで扱う_追加検証.pptx)（17枚、生成元は [docs/additive-kernel-briefing_src/](docs/additive-kernel-briefing_src/README.md)）

| GPR matern52・X, Y, 半径 | 10 Shot | 15 Shot | 20 Shot | 30 Shot | 40 Shot |
| :--- | ---: | ---: | ---: | ---: | ---: |
| 質的変数なし | 3.80 | 3.14 | 2.75 | 2.46 | 2.36 |
| 基底関数で同時推定（前回） | 3.91 | 2.55 | 1.65 | 1.03 | 0.77 |
| 加法カーネル（Scan・Mark とも変量効果） | **3.51** | **2.43** | 1.71 | 1.04 | 0.77 |
| 混合（Scan 固定効果・Mark 変量効果） | 3.98 | 2.59 | 1.67 | **1.03** | **0.77** |

- 加法カーネルは 10 Shot で同時推定より 8.2%（同じ Wafer どうしの比の平均）良く、少ない Shot の逆効果が消える。ただし 20〜30 Shot では最大 5.4% 悪い。
- 原因は2水準しかない Scan 方向の分散 τ が 0 に縮むこと（10 Shot で 92%、20 Shot で 73% の Wafer）。少ない Shot では縮める方が良く、20 Shot 前後では縮みすぎる。
- 混合は 25 Shot 以上で同時推定よりわずかに良い（0.3〜0.9%）が、10〜20 Shot では劣る。
- 使い分け（15 Shot 以下：加法カーネル、20 Shot 以上：混合または同時推定）なら最良との差は 1.3% 以内。1つに決めるなら加法カーネル（最大の損 5.4%）。
- 交互作用の項は、不要なとき同時推定では +4.5〜11.5% の損、変量効果では約 +1%。交互作用のあるデータ（σ = 1 nm）では 20 Shot 以上で混合＋交互作用が最良。
- τ → ∞ で加法カーネルが同時推定と一致することをテストで確認（tests/test_gpr_additive.py）。

### 実データ検証ツール（MATLAB アプリ、2026-10-17）

模擬データでの比較を実データで確かめるための画面つきアプリです（[matlab_app/README.md](matlab_app/README.md)）。
Excel のアライメント計測データ（Overlay 計測ルールの標準の項目）を読み込み、学習 Shot の選び方・Shot 数・比べる手法を画面で選んで実行し、
結果の表・グラフ・Wafer ごとの図を画面で確認し、Excel に書き出します。実データには真の値が無いので、学習しなかった Shot の計測値と比べます。

- 計算は Python 版（`src/`）を MATLAB 本体だけで動くように移したもの（Toolbox 不要）。Python 版と同じ計算結果になることを29件の自動テストで確認。
- Windows の .exe は MATLAB Compiler の入った PC で `matlab_app/build/buildStandaloneApp.m` を実行して作る（この Mac には MATLAB Compiler が無く、.exe は未確認）。

## 必要な環境

- Python 3.14.5 以上（動作確認は Python 3.14.6）
- ライブラリ（版は [requirements.txt](requirements.txt) で固定）：NumPy 2.5.4、SciPy 1.18.1、pandas 3.0.6、Matplotlib 3.11.2、pytest 9.1.1
- 説明資料を作り直す場合：Pillow、Node.js と pptxgenjs 4.0.1、LibreOffice（表示確認）
- 環境変数・認証情報・外部 API は使いません。

## 実行方法

```bash
python3.14 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

ユニットテスト（46件、数秒）：

```bash
.venv/bin/python -m pytest
```

本計算（1,000枚 × 7 Shot 数 × 123設定。M1・メモリ 8 GB の6並列で約3時間）。途中で止めても、再実行すると続きから計算します：

```bash
.venv/bin/python -m src.simulation --config config/default.json --workers 6
```

表と図の作成：

```bash
.venv/bin/python -m src.summarize --results results
.venv/bin/python -m src.plotting --results results
```

追加検証（加法カーネル・混合・交互作用。本計算と同じ Wafer・計画で新しい扱い方だけを計算。合計約2時間）と集計・図：

```bash
.venv/bin/python -m src.simulation --config config/additive_kernel.json --workers 6
.venv/bin/python -m src.simulation --config config/mixed_kernel.json --workers 6
.venv/bin/python -m src.simulation --config config/interaction_scenario.json --workers 6
.venv/bin/python -m src.additive_study
```

補足検証（Backfitting の始め方の比較、50枚）：

```bash
.venv/bin/python -m src.backfit_order_study --n-wafers 50 --workers 1
```

少ない枚数での動作確認（3枚、約1分。サンプリング計画は初回だけ約4分）：

```bash
.venv/bin/python -m src.simulation --n-wafers 3 --results-dir results_smoke --workers 3
```

## フォルダ構成

```
config/default.json        設定（配置・模擬データ・サンプリング・手法・並列数）
src/geometry.py            Wafer・Shot・Mark の配置、Scan 方向
src/wafer_generator.py     模擬データ（Zernike＋Mark Offset＋Scan 差＋ノイズ）
src/sampling.py            制約付き I 最適計画（交換法）
src/basis.py               説明変数・質的変数（効果コード）・多項式
src/models/                GPR・TPS・Kriging・GAM・XY5・RT
src/methods.py             手法の一覧と Shot 数ごとの前計算
src/metrics.py             R²・調整済み R²・RMSE・MAE
src/simulation.py          本計算（並列・途中再開）
src/summarize.py           要約表
src/plotting.py            図
src/backfit_order_study.py 補足検証（Backfitting の始め方）
src/additive_study.py      追加検証（加法カーネル・混合・交互作用）の集計と図
docs/deck_common/          2つの説明資料で共有する部品（スライドの部品・数式画像・後処理）
matlab_app/                実データ検証ツール（MATLAB アプリ、画面・計算・テスト・スタンドアローン版の作成）
results/tables/            要約表（per_wafer_metrics.csv.gz は大きいので Git に入れない）
results/figures/           図
```

## 注意事項

- 模擬データの成分の大きさ（係数の減衰、Mark Offset、Scan 差、ノイズの広がり方）は仮定値です（[design.md](design.md)）。
- Overlay 計測ルール（Wafer 中心原点、mm・nm、解析座標 x = Xmm + markXmm）に従っています。
