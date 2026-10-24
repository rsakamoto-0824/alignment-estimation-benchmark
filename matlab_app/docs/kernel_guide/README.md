# 加法カーネルと交互作用の解説資料（PowerPoint）

`加法カーネルと交互作用の解説.pptx` は、アプリの GPR で質的変数の扱いを「加法カーネル」「加法カーネル＋交互作用」にしたとき、カーネルがどんな式になっているかを説明する 23 ページの技術解説資料です（2026年10月）。

- 構成：前提（GPR と質的変数、8通りの扱い方）→ 加法カーネル（式・行列・変量効果としての読み方・予測での効き方・固定効果との違い）→ 交互作用（式・全ペアの入れ方・ほかの「＋交互作用」との違い）→ 計算例と使い方（ハイパーパラメータの推定、模擬データでの数値例、アプリでの場所、注意点）→ まとめ・参考文献。
- 式はアプリの実装（`+alignest/+models` の `gprModeSetup`・`gprKernel`・`gprInitialParams`・`gprObjective`・`gprPredict`）に合わせています。
- 計算例は、同梱の模擬データ（`sample_data/sample_alignment.csv`）を MATLAB R2022b で計算した値です。実データ・社内データは使っていません。
- 見た目は「技術レポートPowerPoint」テンプレート（参照デッキ）のスライドマスター・テーマ・色・文字の大きさ・配置に合わせています。各ページにノートがあります。

## 作り直す場合

1. MATLAB で `matlab_app` を開き、計算例を作り直す（`_src/kernel_numbers.json` を書く）。

   ```matlab
   run('docs/kernel_guide/_src/kernel_numbers.m')
   ```

2. Python（`python-pptx`・`lxml`）で資料を作る。参照デッキは「技術レポートPowerPoint」の `reference.pptx`（省略すると `~/.claude/skills/artifact-template-powerpoint-2/assets/reference.pptx`）。

   ```bash
   python3 _src/build_deck.py 加法カーネルと交互作用の解説.pptx <reference.pptx> _src/kernel_numbers.json
   ```

   出力は別名（`.building.pptx`）に書いてから置き換えます。PowerPoint で開いている（`~$` のロックファイルがある）ときは止まるので、閉じてから実行してください。

| ファイル | 中身 |
| --- | --- |
| `_src/build_deck.py` | スライドの中身（文章・表・図の配置） |
| `_src/pptkit.py` | 参照デッキの見た目の部品（文字・角丸の箱・表・行列の升目・グラフ。数式は `$…$`、下付き `_{…}`、上付き `^{…}`） |
| `_src/kernel_numbers.m` | 計算例（模擬データでのハイパーパラメータ・共分散の内訳・予測の内訳・手法の比較）を MATLAB で計算する |
| `_src/kernel_numbers.json` | 上の計算結果（資料の数値はここから入る） |
