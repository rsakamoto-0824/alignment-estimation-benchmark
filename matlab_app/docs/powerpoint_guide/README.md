# アライメント計測ツールのPowerPoint手順書

`アライメント計測ツール_ユーザー手順書.pptx` は、2026年10月21日時点のローカルアプリを対象にした26ページの操作手順書です。起動、入力項目、取り込み、単位変換、行の除外、Scan方向、評価条件、質的変数、Backfitting、Overlay補正、結果の確認、保存を説明します。

画面は同梱の `sample_alignment.xlsx` を実際のMATLABアプリで読み込んで撮影しました。顧客・会社の実測データは使っていません。画面画像以外の説明、番号、表はPowerPointで編集できます。使用フォントは参照テンプレートと同じ BIZ UDGothic です。

## 更新する場合

- `_src/content.json`: 本文、画面上の番号位置、切り出し範囲
- `_src/build_guide.mjs`: テンプレートへの配置と下書き生成
- `_src/finalize_guide.mjs`: 構造・レイアウト検証と最終ファイルの配置
- `_src/capture_screens.m`: 模擬データを用いた画面の再撮影
- `images/`: 撮影した画面と撮影記録

MATLABで `_src/capture_screens.m` を実行すると画面を更新できます。アプリの公開メソッドとコントロール名に依存するため、画面構成を変更した際は撮影スクリプトも確認してください。

PowerPointはCodex同梱のNode.jsと `@oai/artifact-tool`・`sharp` で生成します。依存ライブラリの場所は `load_workspace_dependencies` の結果を使います。生成前に対象のPowerPointファイルを閉じてください。

1. `NODE_PATH` と `RUNTIME_NODE_MODULES` に同梱Node.jsライブラリのディレクトリを設定。
2. `GUIDE_TEMPLATE` に「技術レポートPowerPoint」の `assets/reference.pptx` を指定。
3. 同梱Node.jsで `_src/build_guide.mjs` を実行。
4. `PRESENTATIONS_SKILL` にPresentationsスキルのディレクトリ、`RUNTIME_PYTHON` に同梱Pythonの実行ファイルを指定し、同梱Node.jsで `_src/finalize_guide.mjs` を実行。
5. OOXML検証、全ページの表示確認、Microsoft PowerPointでの再オープンを実施。

下書き・画像確認用の出力・検証結果はリポジトリの `.cache/powerpoint-guide/` に保存します。PowerPoint編集中を示すロックファイルがあれば、生成・配置を中止します。

## 作成時の確認

- 模擬データ: 9手法 × 2学習Shot数 × 5 Wafer、90評価行、推定失敗なし。
- PowerPoint: 26ページ、編集可能な表3個、ノート26ページ。
- 構造検証、ZIP整合性、Artifact Toolでの再読み込み、全ページの画像確認、LibreOfficeでのPDF変換を実施。
- Microsoft PowerPointでの最終再オープンは、端末がロック中のため未確認。

アプリ本体にあった変更はそのまま使用しています。手順書の作成によるアプリ本体の変更はありません。
