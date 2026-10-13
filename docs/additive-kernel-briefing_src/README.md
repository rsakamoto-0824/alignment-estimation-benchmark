# 追加検証の説明資料（PowerPoint）の生成元

`docs/GPRの質的変数を加法カーネルで扱う_追加検証.pptx`（ノートつき）を作るためのスクリプトです。
スライドに載せる数値は、すべて計算結果の CSV から取り出します（手で書き写さない）。

## 必要な環境

- リポジトリの Python 仮想環境 `.venv`（`requirements.txt` の内容）と Pillow
- Node.js と、グローバルに入れた `pptxgenjs`（4.0.1 で確認）
- 計算結果（リポジトリの直下で実行）：
  1. 本計算 `python -m src.simulation --config config/default.json`（`results/`）
  2. 追加計算 `python -m src.simulation --config config/additive_kernel.json`（`results_additive/`）
  3. 補足検証 `python -m src.simulation --config config/interaction_scenario.json`（`results_interaction/`）
  4. 集計と図 `python -m src.additive_study`（`results_additive/tables`・`figures`）

## 作り方

このフォルダで、上から順に実行します。

```bash
../../.venv/bin/python prepare_data.py
../../.venv/bin/python render_formulas.py
NODE_PATH="$(npm root -g)" node build_deck.js deck_raw.pptx
../../.venv/bin/python ../deck_common/postprocess.py deck_raw.pptx deck.building.pptx
```

| ファイル | 役割 |
| --- | --- |
| `prepare_data.py` | 集計表から、スライドで使う数値を `deck_data.json` に書き出す |
| `render_formulas.py` | 数式を画像（`formulas/`）にする（描き方は `../deck_common/formula_renderer.py`） |
| `build_deck.js` | スライドを作る。部品は `../deck_common/deck_kit.js`（「技術レポートPowerPoint」テンプレートの見た目） |
| `../deck_common/postprocess.py` | フォントの指定の修正、PowerPoint が修復を求める部品の正規化、再圧縮 |

`deck.building.pptx` を確認してから、`docs/` の完成版と置き換えます（PowerPoint で開いているときは置き換えない）。
`deck_raw.pptx`、`deck.building.pptx`、`formulas/` は再生成できるので Git に入れていません。

## 注意

- タイトルや結論の文は数値から組み立てています（例：有意に良い Shot 数の範囲、交互作用ありのデータでの最良）。結果が変わると文も変わるので、作り直したら全スライドを目で確認します。
- 動作確認で別の結果フォルダを使うときは、環境変数 `ADDITIVE_DIR`・`INTERACTION_DIR` を指定します。
