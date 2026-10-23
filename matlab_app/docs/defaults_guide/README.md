# デフォルト設定の編集ガイド（PowerPoint・管理者向け）

`デフォルト設定の編集ガイド.pptx` は、検証ツールの初期設定（評価の条件・比べる手法・画面の初期値）を管理者が変えるときの 18 ページの手順書です（2026年10月）。

- 構成：設定の仕組み（初期値 → 既定の設定ファイル → 画面 → 設定ファイル → Excel の「設定」シート）→ 3つの変え方と手順（A 設定ファイルを配る、B 既定の設定ファイル `alignment_estimation_defaults.json` を置く、C コードの初期値を変える）→ 設定の項目と初期値の一覧 → 編集の例・注意・確かめ方・まとめ。
- 初期値の表は `+alignest/defaultSettings.m`・`+alignest/recommendedMethods.m`・`AlignmentEstimationApp.m` の定数に合わせています。初期値を変えたときは `_src/build_deck.py` の表も直して作り直してください。
- 見た目は「技術レポートPowerPoint」テンプレート（参照デッキ）のスライドマスター・テーマ・色・文字の大きさ・配置に合わせています。各ページにノートがあります。

## 作り直す場合

Python（`python-pptx`・`lxml`）で作ります。参照デッキは「技術レポートPowerPoint」の `reference.pptx`（省略すると `~/.claude/skills/artifact-template-powerpoint-2/assets/reference.pptx`）。

```bash
python3 _src/build_deck.py デフォルト設定の編集ガイド.pptx <reference.pptx>
```

出力は別名（`.building.pptx`）に書いてから置き換えます。PowerPoint で開いている（`~$` のロックファイルがある）ときは止まるので、閉じてから実行してください。

| ファイル | 中身 |
| --- | --- |
| `_src/build_deck.py` | スライドの中身（文章・表・コードの例の配置） |
| `../kernel_guide/_src/pptkit.py` | 参照デッキの見た目の部品（解説資料と共通） |
