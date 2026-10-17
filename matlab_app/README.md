# 実データ検証ツール（MATLAB アプリ）

アライメント計測値の面内推定の手法比較を、**実データ（Excel）** で確かめるための画面つきアプリです。
Excel の計測データを読み込み、画面で比べ方を決めて実行し、結果の表・グラフ・Wafer ごとの図を画面で確認します。
推定の計算は、模擬データで評価した Python 版（リポジトリの `src/`）を MATLAB に移したもので、同じ計算結果になることを照合しています（下の「動作確認」）。

- 計算部分は **MATLAB 本体だけ** で動きます（Toolbox は不要。依存解析で確認）。
- **スタンドアローン版（Windows の .exe）** は、MATLAB Compiler の入った PC で `build/buildStandaloneApp.m` を実行して作ります。

## 必要な環境

| 用途 | 必要なもの |
| --- | --- |
| MATLAB の中で使う | MATLAB R2022b で動作確認（R2021a 以上を想定）。Toolbox は不要 |
| スタンドアローン版を作る | MATLAB と **MATLAB Compiler**（同じ PC に入っていること） |
| スタンドアローン版を使う | 作ったときと **同じ版の MATLAB Runtime**（無料。インストーラー版を使うと一緒に入る）。MATLAB 本体は不要 |

Excel 本体は不要です（MATLAB の読み込み・書き出し機能を使います）。環境変数・認証情報・外部サービスは使いません。

## 使い方（MATLAB の中で）

1. MATLAB で `matlab_app` フォルダを開く（現在のフォルダにする）。
2. コマンドウィンドウで次を入力する。

   ```matlab
   runAlignmentEstimationApp
   ```

3. 画面のタブを左から順に進める。

| タブ | すること |
| --- | --- |
| 1. データの読み込み | 「ファイルを選ぶ…」で Excel（または CSV）を選ぶ。列の対応を確かめて「この対応で読み込む」 |
| 2. 評価の設定 | 学習に使う Shot の選び方と Shot 数、比べる手法を選ぶ（初期設定は「推奨の組み合わせ」） |
| 3. 実行 | 「評価を始める」。進み具合と残り時間が出る。「止める」で途中までの結果を残して止められる |
| 4. 結果一覧 | 手法 × 学習 Shot 数 の表（各列の最良に ★）、指標のグラフ、基準の手法との比較。「結果を Excel に書き出す…」 |
| 5. Wafer ごとのマップ | Wafer・学習パターン・手法を選び、計測値・推定値・残差を矢印または色で表示 |

動作確認用のサンプルデータ（模擬データ5枚）：[sample_data/sample_alignment.xlsx](sample_data/sample_alignment.xlsx)

## スタンドアローン版の作り方（Windows）

MATLAB Compiler の入った Windows PC で行います（Mac では Windows 用の .exe は作れません）。

1. `matlab_app` フォルダごと Windows PC にコピーする。
2. MATLAB で `matlab_app` フォルダを開き、次を入力する（数分かかる）。

   ```matlab
   addpath build
   buildStandaloneApp                       % .exe だけ作る
   buildStandaloneApp(makeInstaller=true)   % インストーラーも作る（MATLAB Runtime をネットから入れる形）
   ```

3. `build/output/win64/` に `AlignmentEstimationApp.exe` ができる。使う PC に同じ版の MATLAB Runtime を入れてから起動する
   （インストーラー版なら Runtime も一緒に入る）。

スタンドアローン版は画面だけのアプリとして作ります（コマンド画面は出ません）。設定・結果の保存先は、画面のダイアログで選んだ場所です。

## 読み込むデータの形

1行目が項目名、2行目からデータの表です（Excel のシートを選べます）。項目名は Overlay 計測ルールの
アライメント計測テーブルの標準に合わせます。名前が違う場合は、画面の「列の対応」で選び直せます。

| 項目名 | 意味 | 必須 | 無いとき |
| --- | --- | :---: | --- |
| Wafer | ウェハ ID | 任意 | 全行を1枚とみなす |
| DateTime | 測定日時 | 任意 | 空。同じ Wafer でも日時が違えば別の計測として扱う |
| shotNo | ショット番号 | 任意 | 座標から番号を付ける（上の行から左→右） |
| Direction | Scan 方向（1 または 2） | 任意 | Scan 方向を質的変数・制約に使わない |
| Xmm, Ymm | ショット中心の座標 [mm] | 必須 | |
| Radius | ショット中心の半径 [mm] | 任意 | あれば Xmm・Ymm からの計算値と合うか確かめる |
| markNo | ショット内のマーク番号 | 任意 | マーク座標の組ごとに番号を付ける |
| markXmm, markYmm | ショット中心から見たマーク座標 [mm] | 必須 | |
| measX, measY | マークの測定値 [nm] | 必須 | |
| StsX, StsY | ステータス（0 = 有効、−1 = 未測定） | 任意 | 測定値が空でなければ有効 |

前処理（Overlay 計測ルールのとおり）

- 解析座標は x = Xmm + markXmm、y = Ymm + markYmm。半径 150 mm 以上の点は除く（画面で変えられる）。
- X には StsX = 0 の measX、Y には StsY = 0 の measY だけを使う。未測定を 0 として扱わない。
- Wafer・DateTime・Xmm・Ymm・markXmm・markYmm が同じ行は重複とみなし、測定値を X・Y それぞれ平均する。
- 除いた行・まとめた行の数は「読み込み結果」と書き出した Excel の「説明」シートに出る。

## 評価の考え方

- **学習と評価**：学習 Shot の計測値で推定し、学習しなかった Shot の **計測値** と比べる
  （実データには真の値が無いため。計測ノイズを含むので、模擬データの評価より誤差は少し大きく出る）。
- **学習 Shot の選び方**
  - 制約付き I 最適（前回の評価と同じ）：XY 5次多項式の平均予測分散が小さくなる Shot の組を交換法で探す。
    同心円（Wafer 半径比 0.45・0.7）・4象限・Scan 方向ごとの Shot 数を、全体の割合 ± 1 にそろえる。
  - 制約つきランダム：同じ制約を満たす組をランダムに選び、指定回数くり返す（乱数の種を固定すれば同じ組になる）。
  - 手動で指定：shotNo を並べた行を1パターンとして、何パターンでも比べられる。
  - 候補 Shot と計測できた Mark が同じ Wafer では、同じ学習 Shot を使う（同じ条件で比べるため）。
- **指標**：R²・自由度調整済み R²・RMSE・MAE（X・Y・X と Y の合計）。外周（半径比 0.8 以上）と内側の RMSE も出す。
- **集計**：Wafer ごとの値（ランダムのくり返しは平均）を、Wafer 間で平均または中央値にする。
  基準の手法との比較は、同じ Wafer・同じ学習パターンどうしの差の平均・95% 区間・基準より良かった Wafer の割合。

比べられる手法（前回の評価と同じ）

| 系統 | 選べるもの |
| --- | --- |
| GPR | fitrgp と同じ10カーネル × 説明変数（X,Y／X,Y,半径／X,Y,半径,T）× 質的変数（Scan 方向・Mark 番号）の8通りの扱い（使わない・同時推定・Backfitting・同時推定＋交互作用・加法カーネル・加法カーネル＋交互作用・混合・混合＋交互作用） |
| TPS | 平滑化つき薄板スプライン（λ は GCV） |
| Kriging | 通常 Kriging・Universal Kriging × バリオグラム（linear・gaussian・power・exponential） |
| GAM | P-spline（λ は REML）＋ Scan 方向・Mark 番号 |
| XY 多項式・RT モデル | 次数を指定 |

前処理として「XY 1次（並進・倍率・回転・直交度）を学習点で除いてから推定する」も選べます（実データで1次成分が大きいとき用。初期設定は使わない）。

## 書き出す Excel

| シート | 内容 |
| --- | --- |
| 説明 | 作成日時、読み込んだファイル、学習パターン、データの確認・計算の注意 |
| 集計_RMSE_XY ほか | 手法 × 学習パターン の平均（RMSE・MAE・R²・調整済み R² は X・Y 合計、RMSE は X・Y 別も） |
| Waferごと | 全 Wafer × 学習パターン × 手法 の指標、有効自由度、GPR の超パラメータ、推定できなかった理由 |
| 学習Shot | Wafer ごと・学習パターンごとに選んだ shotNo |
| 設定 | 使った設定（JSON）。「設定を読み込む…」で同じ設定に戻せる |

## 計算時間の目安

M1 Mac（MATLAB R2022b、Intel 版を Rosetta で実行）で、約150 Shot・600 Mark の Wafer の場合：

- 1回の推定（X・Y）：GPR・GAM 約0.08 秒、Kriging 0.03 秒、TPS 0.02 秒、XY 多項式・RT 0.01 秒
- I 最適の計画：Shot 数1つあたり約5〜10 秒（同じ配置の Wafer では1回だけ）
- 推奨の組み合わせ（9手法）× 7つの Shot 数 × 25枚：約2〜3分
- 「すべて選ぶ」（273手法）× 7つの Shot 数 × 25枚：数時間（目安は画面の「2. 評価の設定」の下に出る）

## 動作確認

```matlab
cd tests
runAllTests
```

29件（Python 版との照合 8件、読み込みと前処理 9件、評価・集計・書き出し・設定 9件、画面の流れ 3件）。

Python 版との照合（[tests/TestPythonReference.m](tests/TestPythonReference.m)）は、模擬データ3枚・10/20 Shot で行う。

| 照合の対象 | 結果 |
| --- | --- |
| GPR（超パラメータ固定）の目的関数・勾配・推定値 | 丸め誤差の範囲で一致（13通りの カーネル × 説明変数 × 質的変数） |
| GPR（最適化まで含む） | 対数周辺尤度の差の中央値 3e−11、真値に対する RMSE の差は最大 0.04%（84件） |
| TPS・XY5・RT4/RT5・指標 | 丸め誤差の範囲で一致 |
| Kriging | 経験バリオグラムと、同じバリオグラムでの推定値が一致。当てはめは96件すべてで Python と同じかより良い |
| GAM | λ を固定した REML 基準・推定値が一致。λ の選び方の違いによる推定値の差は最大 0.004 nm |
| 制約付き I 最適 | 基準値 tr(M⁻¹) は Python の 0.9996〜1.0016 倍 |

照合用の基準値は、リポジトリの直下で `.venv/bin/python matlab_app/tests/reference/make_python_reference.py` を実行すると作り直せる。
サンプルデータは `.venv/bin/python matlab_app/sample_data/make_sample_data.py` で CSV を作り、MATLAB の `writetable` で Excel にした。

## 注意事項

- **実データ・社内データはリポジトリに入れない**（`matlab_app` 内の .xlsx・.csv はサンプルだけを登録し、それ以外は .gitignore で除外）。
- 結果を書き出すとき、同じ名前の Excel ファイルを開いていると書き出せない（閉じてからやり直す）。
- CSV は UTF-8 で保存したものを読む。Shift_JIS の CSV で Wafer ID に日本語があると文字化けすることがあるので、Excel（.xlsx）のまま読むのがよい。
- この Mac（MATLAB Compiler なし）では、スタンドアローン版の作成と .exe での動作は確認していない。MATLAB の中での画面の動作・計算・テストは確認済み。

## フォルダ構成

```
runAlignmentEstimationApp.m   起動（スタンドアローン版の入口）
AlignmentEstimationApp.m      画面（5つのタブ）
+alignest/                    計算（読み込み・前処理・学習 Shot の選び方・推定・指標・集計・書き出し）
  +models/                    GPR・TPS・Kriging・GAM・XY 多項式・RT モデル
  +basis/                     説明変数・効果コード・多項式・Zernike・B スプライン
  +optim/                     上下限つき最適化（Optimization Toolbox の代わり）
  +plot/                      Wafer の図
build/buildStandaloneApp.m    スタンドアローン版を作る（MATLAB Compiler が必要）
sample_data/                  サンプルデータ（模擬データ）と作り方
tests/                        自動テストと Python 版の基準値
```
