# 実データ検証ツール（MATLAB アプリ）

アライメント計測値の面内推定の手法比較を、**実データ（Excel）** で確かめるための画面つきアプリです。
Excel の計測データを読み込み、画面で比べ方を決めて実行し、結果の表・グラフ・Wafer ごとの図を画面で確認します。
推定の計算は、模擬データで評価した Python 版（リポジトリの `src/`）を MATLAB に移したもので、同じ計算結果になることを照合しています（下の「動作確認」）。

- **Windows での使い方・exe の作り方の手順書（HTML）**：[docs/windows_guide/windows_guide.html](docs/windows_guide/windows_guide.html)（ブラウザで開く。画像・CSS が同じフォルダにあるので、フォルダごと扱う）
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
| 1. データの読み込み | 「ファイルを選ぶ…」で Excel（または CSV）を選ぶ。列の対応と座標の入力単位を確かめて「この対応で読み込む」 |
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
   buildStandaloneApp(makeInstaller=true, runtimeDelivery="installer")  % Runtime 入りのインストーラー（ネットに出られない PC 用）
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

- 「列の対応」の **座標の入力単位** で、`Xmm`・`Ymm`・`markXmm`・`markYmm`・`Radius` ごとに **m／mm／um（µm）／nm** を選べる。初期値は mm。列名が `Xmm` でも実際の入力が µm なら um を選ぶ。
- 読み込み時に mm に変換する（m は ×1000、um は ×0.001、nm は ×0.000001）。半径の照合・除外、重複・Shot の判定、マップ、推定には変換後の値を使う。`measX`・`measY` は nm のまま。
- 列の対応・入力単位・有効半径を変更したら、もう一度「この対応で読み込む」を押す。設定ファイルの読み込みで単位・有効半径が変わった場合も再読み込みが必要。入力ファイル自体は変更しない。
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

比べられる手法

| 系統 | 選べるもの |
| --- | --- |
| GPR | fitrgp と同じ10カーネル × 説明変数（X,Y／X,Y,半径／X,Y,半径,T）× 質的変数（Scan 方向・Mark 番号）の8通りの扱い（使わない・同時推定・Backfitting・同時推定＋交互作用・加法カーネル・加法カーネル＋交互作用・混合・混合＋交互作用） |
| TPS | 平滑化つき薄板スプライン（λ は GCV）× 質的変数なし／Backfitting |
| RBF | ガウス型の動径基底関数＋1次多項式。広がりと平滑化は GCV で選択 |
| Kriging | 通常 Kriging・Universal Kriging × バリオグラム（linear・gaussian・power・exponential）× 質的変数なし／Backfitting |
| GAM | P-spline（λ は REML）＋ Scan 方向・Mark 番号 |
| XY 多項式・RT モデル | 次数を指定 |

前処理として「XY 1次（並進・倍率・回転・直交度）を学習点で除いてから推定する」も選べます（実データで1次成分が大きいとき用。初期設定は使わない）。

### RBF と TPS・Kriging の Backfitting

「2. 評価の設定」で **RBF（ガウス型・平滑化つき）** を選ぶと、RBF を手法比較に追加できます。説明変数は既存手法と同じ XY／XYR／XYRT です。RBF 自体には質的変数を追加しません。

TPS・Kriging（通常）・Universal Kriging の右側では、それぞれ **質的変数なし／Backfitting／なし・Backfitting を比較** を選べます。両方を選ぶと、同じ学習 Shot でそれぞれの結果が出ます。

- Backfitting は Scan 方向・Mark 番号と、チェックした場合は Shot 行奇偶を固定効果として扱う。質的変数の効果を除いた残差から空間成分を推定し、質的変数の効果を更新する。
- TPS は平滑化を、Kriging はバリオグラムを残差から選び直す。学習点で平滑化を固定した内側の交互反復は収束値を直接計算し、外側を最大20回、変化が 0.001 nm 未満になるまで繰り返す。評価点の計測値は当てはめにも設定選択にも使わない。
- 収束しなかった場合は「3. 実行」の記録と Excel の「説明」に通知し、最終反復の結果を残す。「Waferごと」の「最適化の収束」は false になる。有効自由度には質的変数と空間成分の両方を含める（最終パラメータ固定時の値）。
- RBF の基底は `exp(-r² / (2ℓ²))`。Wafer 半径で正規化した説明変数の距離で、ℓ の初期候補は 0.05・0.1・0.2・0.4・0.8・1.6。平滑化と合わせて学習データの GCV（一般化交差検証）が最小の候補を使う。選択した値は Excel の「超パラメータ」に残る。
- 詳細設定は JSON の `methods.options.rbfLengthScales`、`rbfLog10Lambda`（最小・最大・候補数）、`backfitMaxIterations`、`backfitToleranceNm` で指定する。RBF の候補や Backfitting の反復が増えると計算時間も増える。
- 従来の設定と結果を再現できるよう、「推奨の組み合わせ」は従来の9手法を維持する。RBF と追加の Backfitting は個別に選ぶか「すべて選ぶ」で追加する。古い設定JSONでは RBF はオフ、TPS・Kriging の質的変数は「なし」になる。

### Shot 配列の行の奇数・偶数を使う

「2. 評価の設定」の「比べる手法」にある **Shot 行の奇数・偶数を質的変数に追加** を選びます。GPR・GAM と、Backfitting を選んだ TPS・Kriging に適用します。初期値はオフです。

- 各 Wafer・測定日時について、Shot 中心の `Ymm` を大きい順（上から）に並べ、1行目を奇数行、2行目を偶数行として扱う。同じ Y 座標の Shot とその Mark は同じ分類になる。座標は変換後の mm を小数点以下3桁に丸めて判定する。
- Excel の行番号や `shotNo` の奇偶ではない。半径で点を除く前の入力座標を使うため、有効半径を変えても分類は変わらない。ただし、入力に一切含まれない Shot 行は数えられない。欠落行を含む装置側の行番号を再現する機能ではない。
- Scan 方向・Mark 番号に追加される。GPR の「使わない」ではこの分類も使わない。同時推定・Backfitting・GAMでは固定効果、加法カーネルでは変量効果、混合ではScan方向と行奇偶が固定効果、Mark番号が変量効果になる。
- 「交互作用あり」は、Scan×Mark、Scan×行奇偶、Mark×行奇偶の各ペアを含む。学習点の水準が1種類しかない変数は効果を推定しない。Scan方向と行奇偶が一致する場合など、固定効果の重複する列は除く。
- 入力単位と行奇偶の使用設定は設定JSONと結果Excelに保存される。既存の設定JSONにこの項目が無ければ、座標はmm、行奇偶はオフになる。

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
- 「すべて選ぶ」は追加機能込みで303手法。Backfitting の反復を含むため、所要時間は従来の273手法より長くなる（画面の目安では追加 Backfitting に反復上限を掛けている）。

## 動作確認

```matlab
cd tests
runAllTests
```

46件（Python 版との照合 8件、読み込みと前処理 12件、評価・集計・書き出し・設定 11件、質的変数の設計 2件、RBF・空間モデルの Backfitting 8件、画面の流れ 5件）。単位変換、Shot 行奇偶、既存手法との互換性、新手法の数値照合、評価点の計測値を学習に使わないこと、画面操作から Excel 出力までを含め、MATLAB R2022b で全件成功を確認（2026-10-21）。

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
  +models/                    GPR・TPS・RBF・Kriging・GAM・XY 多項式・RT モデル
  +basis/                     説明変数・効果コード・多項式・Zernike・B スプライン
  +optim/                     上下限つき最適化（Optimization Toolbox の代わり）
  +plot/                      Wafer の図
build/buildStandaloneApp.m    スタンドアローン版を作る（MATLAB Compiler が必要）
docs/windows_guide/           Windows 手順書（HTML。画面の画像つき）
sample_data/                  サンプルデータ（模擬データ）と作り方
tests/                        自動テストと Python 版の基準値
```
