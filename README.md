# alignment-estimation-benchmark

アライメント計測値の面内推定で、**どの手法と説明変数を選ぶか**を、乱数で作った模擬 Wafer 1,000枚で比べる評価です（Python）。
制約付き I 最適計画で選んだ 10〜40 Shot を学習データとし、未計測 Shot の全 Mark を推定して、
決定係数・自由度調整済み決定係数・RMSE・MAE で評価します。

- 結果の説明資料（PowerPoint、30枚・ノートつき）：[docs/アライメント計測値の面内推定_手法比較_説明資料.pptx](docs/アライメント計測値の面内推定_手法比較_説明資料.pptx)（生成元は [docs/results-briefing_src/](docs/results-briefing_src/README.md)）
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

ユニットテスト（33件、数秒）：

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
src/backfit_order_study.py 補足検証
results/tables/            要約表（per_wafer_metrics.csv.gz は大きいので Git に入れない）
results/figures/           図
```

## 注意事項

- 模擬データの成分の大きさ（係数の減衰、Mark Offset、Scan 差、ノイズの広がり方）は仮定値です（[design.md](design.md)）。
- Overlay 計測ルール（Wafer 中心原点、mm・nm、解析座標 x = Xmm + markXmm）に従っています。
