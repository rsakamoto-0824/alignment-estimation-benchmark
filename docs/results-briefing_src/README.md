# 説明資料（PowerPoint）の生成元

`docs/アライメント計測値の面内推定_手法比較_説明資料.pptx`（30枚、各スライドにノートつき）を作るためのスクリプトです。
スライドに載せる数値は、すべて計算結果の CSV から取り出します（手で書き写さない）。

## 必要な環境

- リポジトリの Python 仮想環境 `.venv`（`requirements.txt` の内容）と Pillow（`pip install pillow`、数式画像の寸法を読むため）
- Node.js と、グローバルに入れた `pptxgenjs`（4.0.1 で確認）
- 計算結果：`results/`（`python -m src.simulation` → `python -m src.summarize` → `python -m src.plotting`）と、
  補足検証 `results_backfit_order/`（`python -m src.backfit_order_study`）

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
| `prepare_data.py` | 計算結果の CSV から、スライドで使う数値を `deck_data.json` に書き出す |
| `render_formulas.py` | 数式を画像（`formulas/`）にする。PowerPoint の数式機能は使わない |
| `build_deck.js` | スライドを作る。図は `results/figures/` から読む。文字・図形・表などの部品は `../deck_common/deck_kit.js`（「技術レポートPowerPoint」テンプレートの見た目） |
| `../deck_common/postprocess.py` | フォント指定（和文 BIZ UDGothic、欧文 Arial）の修正、PowerPoint が修復を求める部品の正規化、再圧縮（wafer_rt_simulation と同じもの） |

`deck.building.pptx` を確認してから、`docs/` の完成版と置き換えます（PowerPoint で開いているときは置き換えない）。
`deck_raw.pptx`、`deck.building.pptx`、`formulas/` は再生成できるので Git に入れていません。

## 注意

- 結果を計算し直したときは、`prepare_data.py` から実行し直します。ノートの文章にも数値が入ります。
- 表示確認には LibreOffice で PDF にした画像を使い、最後に Microsoft PowerPoint で開けることを確かめます。
