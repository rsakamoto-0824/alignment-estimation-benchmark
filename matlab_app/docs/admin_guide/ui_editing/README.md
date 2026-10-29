# 管理者向け画面編集手順書

入口は `ui-editing-guide.html`。画像・CSS・JavaScriptを内包した、添付用の単独HTMLです。13章、画面画像7枚。画像をクリックすると原寸で拡大し、Escで閉じられます。PCのブラウザで閲覧します。

対象は2026-10-29の最新版です。画面のソースはタブごとのファイル（`+appui/DataTab.m` など）に分けてあり、`AlignmentEstimationApp.m` はそれらをまとめる入口です（最初の版は2026-10-26の `a8eb43a`、1つのファイルの版が対象でした）。以前の管理者仕様書の固定版84ca419とは異なります。

主な内容は、ソースを開く手順、画面とタブごとのファイル・build関数の対応、ボタン・タブの文字、グリッド配置、説明文の追加、Items/ItemsData、設定の往復、コールバック、テーマ、保存・再起動・確認、Windows版の再ビルド、復元です。会社の作業にデスクトップ型AIを必要としません。

## 画像・検証の範囲

- アプリ画像は、ローカルMacのMATLAB R2022b Update 1で実際の最新版を生成し、公開 `captureTab` / `exportapp` APIで保存。
- 説明用コピー（画面と計算のファイル一式のコピー）で、`+appui/DataTab.m` のファイルボタン名・列幅・説明用の7行目を変更し、実画面とassertで確認。
- エディターの画像は載せず、該当するコードを本文に抜き出して示す（以前の版のCotEditorの画像は、ファイルを分けて場所が変わったため外した）。Windowsのエディター画面は実機未撮影。
- 同梱の合成CSV、手動10 Shot、XY1次多項式の小規模評価は5件・エラー0。全テスト再実行とWindowsビルドは未実施。
- ソースと画像のSHA-256は `_src/source-evidence.json`、表示・操作確認は `_src/validation.json`。

## 保守・再生成

共通のHTML操作手順書テンプレートを基にしています。`procedure-guide.html` は画像・CSS・JavaScriptを相対参照する版で、保守用です。`base.css`、`procedure-guide.css`、`procedure-guide.js` は共通テンプレートのコピーです。

リポジトリ直下で、既存の `.venv` を使います。

```sh
.venv/bin/python matlab_app/docs/admin_guide/ui_editing/_src/prepare_example.py
```

MATLABで次を実行します。2回の撮影はクラスの取り違えを避けるため、別々のMATLABセッションで実行してください。

```matlab
addpath('matlab_app/docs/admin_guide/ui_editing/_src');
capture_ui_guide('original');
% 別のセッションで：capture_ui_guide('example');
```

本文に抜き出すコードは、生成スクリプトが検索語でソースから取り出します（行番号はその時点の目印）。ソースの場所や検索語が変わったら、`_src/build_guide.py` の `source(...)` を合わせます。

```sh
.venv/bin/python matlab_app/docs/admin_guide/ui_editing/_src/build_guide.py
```

出力先は生成スクリプトを基準に決定します。アプリの場所を変更した場合も、リポジトリ内の同じ相対構成なら動作します。画像取得の実行ログは `.cache/ui-editing-guide/` に保存し、Gmailの下書きIDやメールアドレスは公開用の資料へ含めません。
