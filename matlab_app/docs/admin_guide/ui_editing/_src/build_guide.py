"""アプリ固有の画面編集手順書を共通HTML手順書のスタイルで生成する。"""
from pathlib import Path
import base64
import hashlib
import html
import json
import re
import subprocess

HERE = Path(__file__).resolve().parent
GUIDE = HERE.parent
APP = GUIDE.parents[2]
REPO = APP.parent
SOURCE = APP / 'AlignmentEstimationApp.m'          # 画面の入口（タブごとのクラスをまとめるだけ）
UI_FOLDER = APP / '+appui'                         # 画面の中身（タブごとのファイル）
DATE = '2026-10-30'
SECTIONS = [
    ('overview', '目的と対象'), ('prerequisites', '作業前の確認'),
    ('workflow', '全体の流れ・編集箇所'), ('open', 'ファイルを開き、変更箇所を探す'),
    ('wording', 'ボタン・タブの文字を変える'), ('layout', '幅・高さ・配置を変える'),
    ('add-label', '説明文を1行追加する'), ('settings', '選択肢・初期値・設定をつなぐ'),
    ('events', 'ボタンを押した後の処理を確認する'), ('appearance', '文字・色・表示を調整する'),
    ('verification', '保存・再起動・動作確認'), ('release', 'Windows版を作り直す・元に戻す'),
    ('troubleshooting', '困ったとき・根拠ファイル'),
]


def code(text, language='MATLAB'):
    return f'<div class="code-block" data-language="{language}"><button class="copy-button" type="button">コピー</button><pre><code>{html.escape(text.strip())}</code></pre></div>'


def source(relative, search, count):
    """relative（matlab_app からの場所）の、search を含む行から count 行を抜き出す（行番号はその時点の目印）"""
    lines = (APP / relative).read_text().splitlines()
    start = next(i for i, line in enumerate(lines, 1) if search in line)
    excerpt = '\n'.join(lines[start-1:start-1+count])
    return f'<p class="source-note">根拠：{html.escape(relative)} の {start}〜{start+count-1}行（対象版）。行番号より検索語（<code>{html.escape(search.strip())}</code>）を優先してください。</p>' + code(excerpt)


def figure(file, title, caption, pins=()):
    markers = ''.join(f'<span class="screen-pin" style="left:{x}%;top:{y}%" aria-label="説明番号{n}">{n}</span>' for n,x,y in pins)
    return f'<figure class="screen"><div class="screen-heading">{html.escape(title)}<span>画像をクリックすると拡大</span></div><div class="screen-surface"><button class="screen-zoom" type="button" aria-label="{html.escape(title)}を拡大"><img src="images/{file}" alt="{html.escape(caption)}" loading="lazy"></button>{markers}</div><figcaption>{caption}</figcaption></figure>'


def steps(items):
    return '<ol class="numbered-steps">' + ''.join(f'<li><div>{x}</div></li>' for x in items) + '</ol>'


def table(head, rows):
    return '<div class="table-wrap"><table><thead><tr>' + ''.join(f'<th>{x}</th>' for x in head) + '</tr></thead><tbody>' + ''.join('<tr>'+''.join(f'<td>{v}</td>' for v in r)+'</tr>' for r in rows) + '</tbody></table></div>'


def note(title, text, kind='info'):
    return f'<div class="callout {kind}"><div class="callout-icon" aria-hidden="true">i</div><div><h3>{title}</h3><p>{text}</p></div></div>'


def section(id, body):
    index = next(i for i,s in enumerate(SECTIONS, 1) if s[0] == id)
    title = SECTIONS[index-1][1]
    return f'<section id="{id}" class="content-section"><div class="section-heading"><span class="section-number">{index:02}</span><div><p class="section-kicker">Administrator procedure</p><h2>{index}. {title}</h2></div></div>{body}</section>'


parts = []
parts.append(section('overview', '''
<p>「面内推定評価ツール」の画面を管理者が変更するときに、<strong>どのファイルを開き、どの文字・設定を編集し、何を確認して配布するか</strong>を説明します。対象はローカルの最新版ソースです。過去の管理者仕様書の固定版（84ca419）とは対象版が異なります。</p>
<div class="card-grid three-columns"><article class="feature-card"><h3>編集するもの</h3><p>MATLABの <code>+appui</code> フォルダにある、タブごとのファイル（例：「1. データの読み込み」は <code>+appui/DataTab.m</code>）。画面の名前、ボタン、入力欄、配置とイベント処理をコードで定義しています。<code>AlignmentEstimationApp.m</code> はそれらをまとめる入口です。</p></article><article class="feature-card"><h3>編集できる環境</h3><p>ソース一式とMATLABを持つ管理者のPC。配布済みexeとMATLAB Runtimeだけでは、元の画面コードを編集できません。</p></article><article class="feature-card"><h3>完了した状態</h3><p>変更した画面を再起動して確認し、読み込み・設定・小規模評価が通ることを確認。exe利用者へは作り直した実行ファイルを配布します。</p></article></div>
'''+note('App Designerの「Design View」で部品を動かすアプリではありません', 'このリポジトリの画面は <code>classdef</code> と <code>uifigure</code> / <code>uigridlayout</code> で作るプログラム型UIです。<code>.mlapp</code> のデザイン画面へ変換して編集する手順は使いません。タブごとのファイルは、共通部分の <code>+appui/Core.m</code> を受け継ぎ、<code>AlignmentEstimationApp</code> が1つの画面にまとめます。')+
figure('01_original.png','最新版の起動直後：画面とコードを対応させる','① タブ名は +appui/Core.m の startApp、② ファイル選択ボタンは +appui/DataTab.m の buildDataTab、③ 列対応・単位の領域も buildDataTab で作成。画面画像は合成データ以外の入力を含みません。',[(1,1,4),(2,2,21),(3,1,38)])))

parts.append(section('prerequisites', '''
<ul class="check-list"><li>編集用フォルダとして、アプリのソース一式をコピーします。既存の変更がある場合は残し、変更前のファイルも別名で保管します。</li><li>ソースの <code>matlab_app</code> に、<code>AlignmentEstimationApp.m</code>、<code>+appui</code>（画面のタブごとのファイル）、<code>runAlignmentEstimationApp.m</code>、<code>+alignest</code>、<code>help</code>、<code>sample_data</code>、<code>tests</code> があることを確認します。</li><li>MATLAB本体で編集・起動します。この資料の描画確認はR2022b Update 1。Windows用exe作成にはWindows PC上のMATLAB Compilerが必要です。</li><li>動作確認には同梱の <code>sample_data/sample_alignment.csv</code> を使います。実運用の計測ファイルを変更例へ混ぜません。</li></ul>
'''+table(['確認項目','この資料の条件'],[
('ソース基準','2026-10-29の最新版（画面をタブごとのファイル <code>+appui</code> に分けた版）。それより前の版は1つのファイル <code>AlignmentEstimationApp.m</code> に画面のすべてがあります。'),
('資料作成日',DATE),('通常の運用先','Windows 11を想定。会社の手順はMATLABと既存のファイル管理だけで実施でき、デスクトップ型AIを必要としません。'),
('スクリーンショット','Mac上のR2022bで、アプリの公開captureTab機能から実際のUIを描画・保存。OSの外枠・フォントはWindowsと異なります。'),
('コード編集画面','エディターの画像は載せず、該当するコードをそのまま抜き出して示します（以前の版にあったエディターの画像は、ファイルを分けて場所が変わったため外しました）。Windowsのエディター操作は実機未撮影です。'),
('変更例','説明用コピーでボタン名・列幅・説明行を変更。アプリ本体と計算ロジックはこの資料作成では変更していません。'),
]) + note('最初の変更は文字だけに絞る', '画面の文字を変える場合と、計算へ渡す値を変える場合では確認範囲が違います。まず第5章のボタン名変更で、保存→閉じる→再起動の流れを確かめてください。')))

parts.append(section('workflow', '''
<div class="workflow"><div class="workflow-step"><span>1</span><strong>退避</strong><small>変更前を保存</small></div><div class="workflow-arrow">→</div><div class="workflow-step"><span>2</span><strong>特定</strong><small>タブと関数を対応</small></div><div class="workflow-arrow">→</div><div class="workflow-step"><span>3</span><strong>編集</strong><small>1種類ずつ変更</small></div><div class="workflow-arrow">→</div><div class="workflow-step"><span>4</span><strong>確認</strong><small>再起動と小規模評価</small></div><div class="workflow-arrow">→</div><div class="workflow-step"><span>5</span><strong>配布</strong><small>Windows版を再作成</small></div></div>
<h3>画面のどこを直すか</h3>
'''+table(['画面・目的','開くファイル','検索する関数・名前','主な役割'],[
('ウィンドウ名・タブ名・メニュー','+appui/Core.m','APP_TITLE / function startApp','起動時のタイトル、8つのタブ、メニュー「表示」を作る。'),
('1. データの読み込み','+appui/DataTab.m','function buildDataTab','ファイル、列対応、座標単位、入力プレビュー。'),
('2. 評価の設定','+appui/SettingsTab.m','function buildSettingsTab','選び方、計測数、質的変数、手法、補正条件。'),
('3. 実行','+appui/RunTab.m','function buildRunTab','開始・再開・条件追加、計測マップ、ログ。'),
('4. 結果一覧','+appui/ResultsTab.m','function buildResultsTab','表、グラフ、分析・比較タブ。表示更新はrefreshResults等。'),
('5. Waferごとのマップ','+appui/MapTab.m','function buildMapTab','選択欄と描画用の領域。描画内容はdrawMap等。'),
('6. 未知の座標の推定','+appui/TargetTab.m','function buildTargetTab','入力表、条件、推定・補正・書き出しボタン。'),
('7. Shot高次補正','+appui/HighOrderTab.m','function buildHighOrderTab','入力のデータ、補正の式・くくり・回帰の欄、結果（Excel・CSVの列・使う項とVIF・評価・補正値・マップ）のタブ。'),
('7. Shot高次補正の比較','+appui/HighOrderCompareTab.m','function buildHighOrderCompareTab / buildHighOrderPairTab / buildHighOrderWaferTab','補正の比較（条件の一覧・λのスイープ・3つの回帰）、2つの条件を並べる、Waferの比較、項の組み合わせの保存の欄。'),
('7. Shot高次補正の残差の分析と書き出し','+appui/HighOrderAnalysisTab.m','function buildHighOrderHistogramTab / buildHighOrderDecompositionTab / buildHighOrderOutputTab','ヒストグラム（重ねる値・軸・Wafer・範囲）、残差の成分分解（分析の項・Shot成分の項）、書き出し（書き出すもの・値・書き出すボタンと表）の欄。'),
('8. ヘルプ・表示の設定','+appui/Display.m','function buildHelpTab / setTheme / setFontSize','help/help.htmlの表示、画面の色・文字の大きさ・凡例の位置。'),
('画面と設定を相互に渡す','+appui/SettingsTab.m','settingsToControls / controlsToSettings','設定→画面、画面→設定。片側だけ直すと値が戻る・反映されない。'),
('いくつかのタブで使う小さな関数','+appui/private/','label / place / onOff など','部品を作る・置く、値を文字にする。1つの関数が1つのファイル。'),
('計算そのもの','+alignest 以下','—','データ整理、手法、評価、書き出し。見た目だけなら通常ここを直さない。'),
]) + figure('03_target.png','第6タブは +appui/TargetTab.m で作られる','① 入力する点の表、② Wafer・学習データ・手法、③ 推定後の結果領域。編集場所は +appui/TargetTab.m の buildTargetTab です。',[(1,2,7),(2,51,7),(3,51,41)])))

parts.append(section('open', steps([
    '<strong>MATLABで編集用のmatlab_appフォルダを選びます。</strong><p>現在のフォルダーから移動するか、次のコードをコマンドウィンドウで実行します。「matlab_app」そのものを選びます。</p>',
    '<strong>どのコピーが読み込まれるかを確認します。</strong><p><code>which AlignmentEstimationApp -all</code> の先頭が編集用コピーを指すことを確認。別フォルダが先頭なら、そのコピーを閉じてパスを整理します。</p>',
    '<strong>直すタブのファイルを開きます。</strong><p>第3章の表でファイルを選び、<code>edit appui.DataTab</code>（「1. データの読み込み」の場合）で開きます。検索（WindowsはCtrl+F、MacはCmd+F）へ <code>function buildDataTab</code> と入力し、呼び出し箇所ではなく関数定義へ移動します。</p>',
    '<strong>変更前を退避します。</strong><p>下のバックアップ例を実行し、バックアップファイルの存在を確認。バックアップは拡張子を <code>.m</code> 以外にします（<code>+appui</code> の中に <code>.m</code> のコピーを置くと、クラス名とファイル名が合わないファイルになり、<code>checkcode</code> や、<code>+appui</code> をフォルダごと入れるexeの作成で問題になるため）。<code>classdef DataTab</code> とファイル名の組はそのままにします。</p>',
]) + code('''appFolder = uigetdir(pwd, '編集用コピーの matlab_app を選ぶ');
if isequal(appFolder, 0), return; end
cd(appFolder)
addpath(appFolder)
which AlignmentEstimationApp -all
edit appui.DataTab''') + code('''target = fullfile('+appui', 'DataTab.m');
backupName = [target '.before_' datestr(now,'yyyymmdd_HHMMSS')];   % 拡張子を .m 以外にする
copyfile(target, backupName)
isfile(backupName)  % 1なら存在します''') +
'<h3>検索で関数の定義へ移動した例</h3><p><code>function buildDataTab</code> を検索すると、次の場所へ移動します（「1. データの読み込み」の画面を作る関数の始まり）。</p>' +
source('+appui/DataTab.m', 'function buildDataTab', 5)+
note('行番号は目印です', '機能追加で行番号はずれます。画面に出ている日本語→部品名（例：c.chooseFile）→所属するbuild関数→コールバック、の順に追うと対象を見つけやすくなります。')))

parts.append(section('wording', '''<p>最初に、ファイル選択ボタンの名前だけを変えます。計算やファイル選択の動作は変えません。</p>'''+steps([
    '<strong><code>c.chooseFile = uibutton</code> を検索します。</strong><p>buildDataTab内にあることを確認してください。</p>',
    '<strong><code>Text</code> の文字列だけを変更します。</strong><p>「ファイルを選ぶ…」を「計測ファイルを選ぶ…」に変更。<code>c.chooseFile</code> と <code>ButtonPushedFcn</code> は変えません。</p>',
    '<strong>保存し、現在のアプリ画面を閉じて開き直します。</strong><p>MATLABのクラスファイルのRunボタンに頼らず、コマンドウィンドウで <code>app = AlignmentEstimationApp();</code> を実行します。実行中の画面は、ソースを保存しただけでは作り直されません。</p>',
    '<strong>新しい名前のボタンを押し、ファイル選択画面が開くことを確認します。</strong><p>キャンセルで元の画面へ戻れることも確認します。</p>',
]) + '<h3>変更前</h3>' + code("c.chooseFile = uibutton(fileGrid, 'Text', 'ファイルを選ぶ…', ...\n    'ButtonPushedFcn', @(~, ~) app.onChooseFile());") + '<h3>変更後</h3>' + code("c.chooseFile = uibutton(fileGrid, 'Text', '計測ファイルを選ぶ…', ...\n    'ButtonPushedFcn', @(~, ~) app.onChooseFile());")+
table(['変えたい文字','プロパティ','残すもの'],[
('ボタン・ラベル・チェックボックスの文字','Text','部品名・コールバック・内部の値。'),('タブ・パネルの見出し','Title','app.Tabsのdata/settings等のキー。'),('ウィンドウの名前','APP_TITLE','クラス名、起動関数名、exeの内部名は別に扱う。'),('カーソルを置くと出る説明','Tooltip','入力値の意味・単位と説明を一致させる。'),
]) + note('検索と置換は、最初は1件ずつ', '日本語が同じでも別の画面やエラーメッセージで使う場合があります。「すべて置換」で内部名まで変えると、動作やテストを壊すことがあります。')))

parts.append(section('layout', '''<p>このアプリでは、部品をマウスでドラッグする代わりに、<strong>親のグリッドの列幅・行高と、その部品の行・列番号</strong>を変更します。</p>'''+table(['指定','意味','今回の具体例'],[
('uigridlayout(parent, [行数, 列数])','部品を並べる区画数','fileGridは変更前が6行×4列。'),('ColumnWidth','各列の幅','数値はpx。fitは内容に合わせる。1xは残りを配分し、2xなら1xの2倍。'),('RowHeight','各行の高さ','fitで文字量に追従。行を追加したら要素数も確認。'),('Layout.Row / Layout.Column','部品を置く区画','Row=3、Column=1なら3行1列。Column=[1,4]なら4列をまたぐ。'),('Padding / RowSpacing / ColumnSpacing','外側の余白・区画の間隔','詰めすぎると文字が接触し、広げすぎると入力欄が狭くなる。'),
]) + source('+appui/DataTab.m', 'grid = uigridlayout(app.Tabs.data', 4) + steps([
    '<strong>対象の部品の親を確認します。</strong><p><code>c.chooseFile</code> の親は <code>fileGrid</code>。画面全体のrootや別のタブのgridを変更しないよう注意します。</p>',
    '<strong>fileGridのColumnWidthを変更します。</strong><p>この例は <code>{300, \'1x\', 280, 320}</code>。1列目を300px、2列目を残り、3列目を280px、4列目を320pxにします。4列なので値は4個です。</p>',
    '<strong>部品の位置を変更するときは行・列を指定します。</strong><p><code>place(c.chooseFile, 3, 1)</code> は既存の2行のLayout指定と同じ働きです。親グリッドの範囲を超えず、他部品と重ねないようにします。</p>',
    '<strong>再起動し、幅を変えて確認します。</strong><p>最大化した画面だけでなく、会社PCで使う通常のウィンドウ幅で、ファイル名・説明・長い手法名が読めるか確認します。固定幅が多い場合は狭い領域が残らないかを見ます。</p>',
]) + code("% 表示領域を4列で配分する例\n'ColumnWidth', {300, '1x', 280, 320}\n\n% 部品をグリッド内へ配置する共通関数\nplace(c.chooseFile, 3, 1);\n% 内部では Layout.Row = 3; Layout.Column = 1; を指定") +
note('親の幅を変えると、その列を共有する部品も動きます', 'ファイル選択ボタンだけでなく、ファイル名・Scan方向・座標定義なども同じグリッドを使います。変更箇所だけを見ず、上段の入力領域全体を確認します。')))

parts.append(section('add-label', '''<p>説明文だけを追加する例です。画面に表示するだけなので、Settingsへの項目追加や計算の修正は不要です。第5・6章と合わせた変更例を、実際に描画して確認しました。</p>'''+steps([
    '<strong>fileGridを7行へ増やします。</strong><p><code>[6, 4]</code> を <code>[7, 4]</code> にし、<code>RowHeight</code> に7個目の <code>\'fit\'</code> を追加します。</p>',
    '<strong>fileGrid生成の直後へ、説明用ラベルを追加します。</strong><p>以下のコードを入力します。<code>adminNote</code> はこの関数内だけの部品名で、配置は7行目・1〜4列をまとめて使用します。</p>',
    '<strong>保存して再起動します。</strong><p>新しい注意文が座標定義の下に表示され、既存の6行が押しつぶされないことを確認します。</p>',
    '<strong>ライト・ダーク両方で確認します。</strong><p>補足の文字色には固定の黒ではなく <code>app.Palette.muted</code> を使います。</p>',
]) + code("fileGrid = uigridlayout(filePanel, [7, 4], ...\n    'ColumnWidth', {300, '1x', 280, 320}, ...\n    'RowHeight', {'fit','fit','fit','fit','fit','fit','fit'}, ...\n    'Padding', 10);\nadminNote = uilabel(fileGrid, ...\n    'Text', '管理者向け注意：読み込み前に列と単位を確認してください。', ...\n    'WordWrap', 'on', 'FontColor', app.Palette.muted);\nplace(adminNote, 7, [1, 4]);") +
figure('07_after.png','作業用コピーでの変更後：ボタン名・列幅・説明行','① 「計測ファイルを選ぶ…」へ変更し、1列目を300pxに設定。② 7行目に注意文を追加。これは説明用コピーの変更結果で、配布中アプリを変更した画像ではありません。',[(1,2,21),(2,2,36)]) +
note('後から書き換える部品はControlsへ登録する', '表示だけならローカル変数で足ります。別の関数から文字やEnableを変更する場合は <code>c.adminNote</code> として作り、build関数末尾の <code>app.Controls = mergeStruct(app.Controls, c)</code> に含めて参照します。名前を他の部品と重複させないでください。')))

parts.append(section('settings', '''<h3>選択肢の「表示名」と「内部値」を区別する</h3><p>例として、学習Shotの選び方は表示を <code>Items</code>、処理へ渡すキーを <code>ItemsData</code> で定義しています。以下は既存7項目のうち、先頭2項目の対応です。元の7項目を2項目に置き換える手順ではありません。</p>'''+table(['Itemsの表示名','同じ位置のItemsData'],[('制約付き I 最適（前回の評価と同じ）','ioptimal'),('制約付き D 最適','doptimal')]) +
steps([
    '<strong>表示名だけを変える場合</strong><p>該当する <code>Items</code> の文字だけを変えます。並び順・要素数と、対応する <code>ItemsData</code> をそろえます。内部値 <code>ioptimal</code> などを日本語へ変えないでください。</p>',
    '<strong>新しい選択肢を増やす場合</strong><p>画面へ選択肢を足すだけでは計算できません。ItemsData、controlsToSettings、設定の既定値、検証、+alignestの分岐・手法一覧・書き出し・テストまで対応させます。</p>',
    '<strong>起動時の値だけ変える場合</strong><p>先に「設定を保存…」でJSONを作り、必要な値を変更します。共通の初期設定は、起動時の現在のフォルダに <code>alignment_estimation_defaults.json</code> を置く方法もあります。画面の文言・配置はJSONでは変更できません。</p>',
]) + figure('02_settings.png','評価設定の画面：見た目の変更と意味の変更を分ける','① 選び方はItems/ItemsDataの対応、② 数値欄はSettingsとの同期、③ 手法選択は+alignestの手法定義にも関係します。',[(1,1,14),(2,1,31),(3,43,7)]) +
'<h3>既存の有効半径を例にした、画面と設定の往復</h3>' + table(['段階','コード内の場所','確認する内容'],[
('部品を作る','buildDataTab','c.validRadiusのValue・Limits・ValueChangedFcn。'),
('設定→画面','settingsToControls','c.validRadius.Value = s.data.validRadiusMm。'),
('画面→設定','controlsToSettings','s.data.validRadiusMm = c.validRadius.Value。'),
('既定値・型','+alignest/defaultSettings.m','設定項目を定義。新規項目はここに存在しないとloadSettingsで無視される。'),
('保存・読込','+alignest/saveSettings.m / loadSettings.m','保存はJSON化、読込は既定項目に重ねる。古い設定ファイルでも動くか確認。'),
('実行・再描画','コールバック / +alignest / refresh関数','変更した条件が古い結果と混ざらず、必要な再計算が行われること。'),
]) + code('''{
  "data": {
    "validRadiusMm": 149
  }
}''','JSON') + note('初期値が戻るときに見る順番', '<code>defaultSettings → 現在のフォルダの既定JSON → 個別に読み込んだ設定 → settingsToControls</code> を確認します。UI作成時のValueだけ変えても、後の同期でSettingsの値へ戻ることがあります。<code>Controls</code> 自体をJSONへ保存しないでください。')))

parts.append(section('events', '''<p>コールバックは「クリックしたとき・値を変えたときに呼ぶ処理」です。文字や配置だけの変更では、この接続を保ちます。</p>'''+figure('06_run.png','実行画面：ボタンの処理と表示更新の接続','開始・再開・条件追加は別の処理です。ボタンを増やす場合は、処理内容だけでなく、実行前後のEnable、ログ、結果の更新も確認します。')+code("'ButtonPushedFcn', @(~, ~) app.onChooseFile()") +
'<p>上の <code>@(~, ~)</code> は、MATLABから渡される発生元とイベントをこの処理では使わない指定です。ボタン名を変えても、呼び出し先 <code>onChooseFile</code> を変える必要はありません。呼び出し先は、別のタブのファイルにあっても同じように呼べます（どれも <code>AlignmentEstimationApp</code> の関数になるため）。</p>' + source('+appui/DataTab.m', 'function onChooseFile', 10) +
table(['部品・操作','主な接続先','変更後に確認すること'],[
('ファイル選択','onChooseFile → loadFile','ダイアログ、キャンセル、読込エラーの表示。'),
('列対応の確定','onApplyMapping → applyMapping','選んだ列・単位でデータを作り直す。'),
('入力データ条件を変える','onDataOptionsChanged / invalidatePreparedData','以前に整理したデータをそのまま使わない。'),
('評価設定を変える','onSettingsChanged','検証→controlsToSettings→有効/無効の更新→実行概要の更新。'),
('評価を始める','onRun → runEvaluationNow等','進行状況、エラー、結果表示。重い処理をbuild関数へ入れない。'),
]) + note('Valueを代入しただけではイベントが発火しない場合がある', '動作確認コードから <code>app.Controls.xxx.Value = ...</code> と設定する操作は、利用者が画面で値を変える操作と同じとは限りません。公開APIの <code>app.setSettings(s)</code> を使うか、対象のValueChangedFcnが何を更新するか確認します。') +
'<h3>新しい「計算へ渡す入力」を追加するときの順番</h3>' + steps([
    '<strong>設定項目を決める。</strong><p>defaultSettingsへ名前・型・単位・初期値を追加。数値の範囲とエラー時の扱いを決めます。</p>',
    '<strong>UIを作ってControlsへ登録する。</strong><p>親グリッドの行数と配置も合わせて直します。</p>',
    '<strong>設定の往復と検証を追加する。</strong><p>settingsToControls、controlsToSettings、validateSettings等の該当処理へつなぎます。入力条件が変わればデータや結果の作り直しも必要です。</p>',
    '<strong>計算と保存へ渡っているか確認する。</strong><p>+alignestの該当関数が新しい値を実際に使い、設定の保存・再読込で値が残り、旧JSONでも起動することを確認します。</p>',
]) ))

parts.append(section('appearance', '''<h3>文字の大きさ</h3><p><code>+appui/Core.m</code> の冒頭の定数 <code>FONT_SIZE=16</code>、<code>AXES_FONT_SIZE=13</code>、<code>TABLE_FONT_SIZE=13</code> などを確認します。<code>startApp</code> でFontSizeをまとめて適用し、表などは例外のサイズを上書きしています。利用者がメニュー「表示」→「文字の大きさ」で選ぶと、<code>setFontSize</code>（<code>+appui/Display.m</code>）が <code>FONT_SIZE</code> との比を画面・表・図と決まった幅の欄に掛けます。部品を作った行だけでFontSizeを指定しても、後で変わる場合があります。図を描く関数の最後では <code>styleAxes</code> を呼び、文字の大きさと凡例の位置をそろえます。</p>
<h3>色・テーマ</h3><p><code>themePalette</code>（<code>+appui/private/themePalette.m</code>）がライト・ダークの背景、文字、補足、エラー、入力欄、ボタンの色をまとめています。切替処理は <code>setTheme → applyTheme</code>（<code>+appui/Display.m</code>）です。新しい部品も <code>app.Palette.text / muted / error</code> など役割で色を指定します。</p>
'''+figure('04_dark.png','ダークモードの実画面','メニュー「表示」からテーマを切り替えます。追加した説明文、入力欄、表、無効状態の文字が背景に埋もれないか確認します。')+
table(['調整したいもの','主な場所','注意'],[
('画面全体の基準文字','FONT_SIZE（Core.m）とstartApp','部品ごとの例外サイズを確認。利用者は「表示」→「文字の大きさ」で変えられる。'),
('表の列幅','ColumnWidth / METHOD_COLUMN_WIDTH等','長い手法名と数値の両方が読める幅。'),
('図の文字・凡例の位置','AXES_FONT_SIZE / SMALL_AXES_FONT_SIZE / styleAxes','グラフ再描画後にも適用されるか。凡例の位置は利用者が「表示」→「凡例の位置」と図の右クリックで選ぶ。'),
('ウィンドウの初期サイズ','FIGURE_SIZE / figurePosition / fitToScreen','本PCの確認画像は1600×1000指定。既定は1440×900で、小さい画面に合わせて調整される。'),
('ヘルプ本文','help/help.html / buildHelpTab','UIの名称を変えたらヘルプ内の説明も合わせる。'),
]) + note('色の設定を変えると利用者全体の見た目が変わります', 'themePaletteの共通色はアプリ全体に使われます。1個のエラー文だけのつもりで共通色を変更しないようにし、ライト・ダークの両方で表・図・警告を見直します。')))

parts.append(section('verification', steps([
    '<strong>ファイルを保存します。</strong><p>WindowsはCtrl+S、MacはCmd+S。ファイル名とclassdefの名前（例：<code>DataTab.m</code> と <code>classdef (Abstract) DataTab</code>）を変えていないことを確認します。</p>',
    '<strong>MATLABで構文を確認します。</strong><p><code>checkcode</code> のメッセージは該当行を開いて確認。表示された警告のすべてを無条件に消すのではなく、変更箇所との関係を確かめます。</p>',
    '<strong>アプリを閉じて新しいインスタンスを起動します。</strong><p>app変数で起動した画面は下のdelete/clearの例を使用。ほかの作業中の変数を消す <code>clear all</code> は使いません。</p>',
    '<strong>見た目・操作・設定の保存を確認します。</strong><p>下のチェックリストを実施。入力値を変える修正では設定をJSONに保存し、再読込して同じ値に戻ることも確認します。</p>',
    '<strong>サンプルで小規模評価します。</strong><p>同梱CSVを読み込み、短時間で終わる条件で実行。変更前と同じ入力・設定で比較し、見た目だけの変更なら評価値が変わらないことを確認します。</p>',
]) + code('''checkcode(fullfile('+appui', 'DataTab.m'), '-id')   % 直したファイル

% app変数で起動した画面がある場合
if exist('app','var') && isa(app,'AlignmentEstimationApp') && isvalid(app)
    delete(app)
end
clear app
clear AlignmentEstimationApp
app = AlignmentEstimationApp();''') +
figure('05_results.png','保存・再起動後に確認する結果一覧の例','同梱の合成CSV、手動10 Shot、XY1次多項式での小規模評価を今回実行しました。これは見た目と起動経路の確認用で、推定手法の性能比較ではありません。')+
'''<div class="checklist-grid"><article><h3>表示・操作</h3><label><input type="checkbox">タイトル・タブ・ボタンの文字が意図どおり</label><label><input type="checkbox">文字切れ、重なり、不要な空欄がない</label><label><input type="checkbox">全タブを開け、必要なスクロールができる</label><label><input type="checkbox">クリック・キャンセル・入力エラーが動く</label><label><input type="checkbox">ライト・ダークで文字・表・図が読める</label></article><article><h3>設定・計算</h3><label><input type="checkbox">変更した入力値が設定と計算へ渡る</label><label><input type="checkbox">JSONへ保存し、読み直して値が残る</label><label><input type="checkbox">古い設定ファイルでも起動できる</label><label><input type="checkbox">サンプルの小規模評価と書き出しが動く</label><label><input type="checkbox">見た目だけなら変更前後の評価値が一致</label></article></div>
<h3>既存の画面フローテストを実行する場合</h3><p>次はアプリの操作経路をまとめて検証する既存テストです。全件の再実行には時間がかかるため、まず小規模確認を済ませ、機能や設定へ関わる修正後に使用します。今回の資料作成では全テストの再実行はしていません。</p>'''+code("results = runtests(fullfile('tests','TestAppWorkflow.m'));\nassert(all([results.Passed]), '画面フローテストに失敗があります');") +
note('今回実施した確認の範囲', '元の最新版で8タブを生成し、合成CSVの小規模評価と画面描画を確認。説明用コピーではボタン名・グリッド7行・追加注意文の存在をassertで確認しています。Windowsのexe作成と実行はこのMacでは実施していません。')))

parts.append(section('release', '''<h3>MATLABで直接使う利用者へ配る場合</h3><p>変更したソースと必要なパッケージ（<code>+appui</code>・<code>+alignest</code>）を配布し、起動元が新しいコピーになっているか <code>which AlignmentEstimationApp -all</code> で確認します。ソースファイルだけ置き換えたまま、古い画面を開き続けないでください。</p>
<h3>Windowsのexeを使う利用者へ配る場合</h3>'''+steps([
    '<strong>確認したソース一式をWindowsのビルド用PCへ移します。</strong><p>MATLAB Compilerを利用できるPCで実行します。MacでWindows用exeは作れません。</p>',
    '<strong>matlab_appを現在のフォルダにしてビルドします。</strong><p>最初は実行ファイルのみを作ります。必要な場合だけインストーラーを作成します。</p>',
    '<strong>build/output/win64を確認します。</strong><p>新しいAlignmentEstimationApp.exeを別の確認フォルダで起動。対応するMATLAB Runtimeを使用して、MATLAB本体から起動したときと同じ画面になるか確認します。</p>',
    '<strong>配布版の名前・日時・ソース版を記録します。</strong><p>配布先の古いショートカットが旧exeを指していないか、既定JSONの作業フォルダーが変わっていないかも確認します。</p>',
]) + code("addpath build\nbuildStandaloneApp\n\n% 必要な場合のみ、Runtimeを内包したインストーラーも作成\nbuildStandaloneApp(makeInstaller=true, runtimeDelivery=\"installer\")") +
'<h3>変更を戻す手順</h3>' + steps([
    '<strong>変更したアプリ画面を閉じます。</strong><p>利用中の画面を終了し、編集用ソースとバックアップを見比べます。</p>',
    '<strong>対象ファイルだけを変更前へ戻します。</strong><p>今回の例は <code>+appui/DataTab.m</code> だけ。ほかの人の変更や別の作業をまとめて取り消さず、変更したファイル・行だけを戻します。バックアップから戻すときは、拡張子を元の <code>.m</code> に戻した名前で上書きします。</p>',
    '<strong>再起動して確認します。</strong><p>exeで配布済みの場合は、旧版exeを戻すか、復元したソースから再ビルドします。ソースを戻しただけでは、既に作成したexeの中身は変わりません。</p>',
]) ))

faq = [
('保存したのに文字が変わらない','古いアプリ画面が残っていないか、whichで編集用コピーが先頭かを確認。画面を閉じ、クラスをクリアして再起動します。配布exeは再ビルドが必要です。'),
('部品が重なる・文字が切れる','親グリッド、ColumnWidth、RowHeight、Layout.Row/Columnを確認します。行を足した場合は行数とRowHeightをそろえ、WordWrapや固定幅の合計を確認します。'),
('初期値を変えたのに元へ戻る','部品のValueだけでなくSettingsの既定値・既定JSON・settingsToControlsを確認します。loadSettingsはdefaultSettingsにない項目を無視します。'),
('選択肢は表示されるが計算できない','ItemsDataのキーと+alignest側の対応処理が一致しているか確認。表示名の追加だけでは新しい手法は実装されません。'),
('ボタンを押すと入力引数やメソッドのエラーになる','ButtonPushedFcn/ValueChangedFcnの呼び出し先、引数、appのスコープを確認。別の部品からコピーしたコールバックのままになっていないかを見ます。'),
('ダークモードで追加した文字だけ見えない','固定色ではなくPaletteの役割色を使い、applyThemeが扱える部品か確認。新しい種類の部品を追加する場合はテーマ切替の対応も確認します。'),
('画面作成時にclassdefやendのエラーが出る','引用符、括弧、...、カンマ、endの数を変更前と比較。まず1つ前の動く状態へ戻し、変更を1種類ずつ適用します。'),
('「クラス名とファイル名が一致しなければなりません」と出る','<code>+appui</code> の中に、バックアップのつもりの <code>.m</code> のコピー（例：<code>DataTab_old.m</code>）を置いていないか確認します。アプリは起動できても、<code>checkcode</code> やexeの作成でこのエラーになります。バックアップは拡張子を <code>.m</code> 以外にするか、別のフォルダへ移します。'),
('Compilerがない・MacでWindows版が作れない','ソース編集とMATLAB内での起動は実施できます。Windows用exeの再作成は、WindowsとMATLAB Compilerを利用できるビルド担当PCで行います。'),
]
parts.append(section('troubleshooting','<div class="faq-list">'+''.join(f'<details><summary>{q}</summary><div><p>{a}</p></div></details>' for q,a in faq)+'</div><h3>この資料の根拠</h3>'+table(['ファイル','役割'],[
('AlignmentEstimationApp.m','画面の入口。+appui のタブごとのクラスをまとめる。'),('+appui/*.m・+appui/private/','画面生成、イベント、設定同期、テーマ・表示の設定、公開captureTab API（タブごとのファイル）。'),('runAlignmentEstimationApp.m','MATLAB・スタンドアローン版の起動入口。'),('+alignest/defaultSettings.m / siteDefaults.m / loadSettings.m / saveSettings.m','設定項目・既定JSONの探索・読込・保存。'),('build/buildStandaloneApp.m','OS別のビルドと追加ファイル。'),('tests/TestAppWorkflow.m','画面操作経路の既存テスト。'),('_src/source-evidence.json / validation.json','対象版、ソースと画像のハッシュ、確認結果。ローカル保守用ファイル。'),
]) + '<p class="note">この手順書の画像は2026-10-29に取得しました（最初の版は2026-10-27）。変更後の画面例を除き最新版ソースを使用しています。画像・CSS・JavaScriptを内包する <code>ui-editing-guide.html</code> が添付・持ち運び用です。外部のサイトやAIサービスへ接続せず閲覧できます。</p>'))

toc = ''.join(f'<li><a href="#{id}">{i}. {title}</a></li>' for i,(id,title) in enumerate(SECTIONS,1))
custom_css = (HERE/'guide.css').read_text()
custom_js = (HERE/'guide.js').read_text()
doc = f'''<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="description" content="面内推定評価ツールの管理者向け画面編集手順書。実画面、コード、変更前後の確認、再ビルドまで。"><title>面内推定評価ツール｜管理者向け画面編集手順書</title><link rel="icon" href="data:,"><link rel="stylesheet" href="procedure-guide.css"><style>{custom_css}</style><script src="procedure-guide.js" defer></script></head><body id="top"><a class="skip-link" href="#main-content">本文へ移動</a><button id="toc-toggle" class="toc-toggle" type="button" aria-controls="sidebar" aria-expanded="false">☰ 目次</button><aside id="sidebar" class="sidebar" aria-label="目次"><div class="sidebar-header"><p class="eyebrow">Administrator Guide</p><p class="sidebar-title">面内推定評価ツール</p><p class="sidebar-subtitle">画面編集手順書</p></div><nav><ol class="toc-list">{toc}</ol></nav><div class="sidebar-footer">管理・保守用 · {DATE}</div></aside><div id="sidebar-overlay" class="sidebar-overlay" aria-hidden="true"></div><main id="main-content" class="main-content"><header class="hero"><div class="hero-content"><p class="eyebrow">MATLAB UI Maintenance</p><h1>面内推定評価ツール<br><span>管理者向け 画面編集手順書</span></h1><p class="hero-lead">文字の修正から配置・設定との接続、再起動確認、Windows版の作り直しまで。実画面と変更例を対応づけて説明します。</p><div class="hero-badges"><span>対象：ソースを保守する管理者</span><span>PCブラウザ向け</span><span>作成：{DATE}</span><span>アプリ基準：2026-10-30版（+appui）</span></div></div></header>{''.join(parts)}<footer class="page-footer"><p>面内推定評価ツール · 管理者向け画面編集手順書</p><p>{DATE} · v1.1</p></footer></main><button id="back-to-top" class="back-to-top" type="button" aria-label="ページ上部へ戻る">↑ トップへ戻る</button><dialog id="image-dialog" aria-labelledby="image-title"><header><h2 id="image-title">画面の拡大</h2><button id="image-close" type="button">閉じる（Esc）</button></header><p>画像内はスクロールして確認できます。</p><div><img id="expanded-image" alt=""></div></dialog><script>{custom_js}</script></body></html>'''
(GUIDE/'procedure-guide.html').write_text(doc)
css = (GUIDE/'base.css').read_text()+'\n'+(GUIDE/'procedure-guide.css').read_text().replace('@import url("base.css");','')
offline = doc.replace('<link rel="stylesheet" href="procedure-guide.css">',f'<style>{css}</style>')
offline = offline.replace('<script src="procedure-guide.js" defer></script>','')
offline = offline.replace('</body>', '<script>'+ (GUIDE/'procedure-guide.js').read_text()+'</script></body>')
image_paths = sorted(p for p in (GUIDE/'images').iterdir() if p.suffix in ('.png', '.jpg'))
for path in image_paths:
    mime = 'image/jpeg' if path.suffix == '.jpg' else 'image/png'
    data='data:'+mime+';base64,'+base64.b64encode(path.read_bytes()).decode()
    offline=offline.replace('images/'+path.name,data)
(GUIDE/'ui-editing-guide.html').write_text(offline)

files = [SOURCE,*sorted(UI_FOLDER.glob('*.m')),APP/'runAlignmentEstimationApp.m',APP/'build/buildStandaloneApp.m',APP/'+alignest/defaultSettings.m',APP/'+alignest/loadSettings.m',APP/'+alignest/siteDefaults.m',APP/'+alignest/saveSettings.m',APP/'tests/TestAppWorkflow.m']
evidence={'date':DATE,'baseCommit':subprocess.check_output(['git','rev-parse','main'],cwd=REPO,text=True).strip(),
 'note':'作業中のソース（main に、画面をタブごとのファイルに分けた変更を加えたもの）から作成',
 'sourceSha256':{str(p.relative_to(APP)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
 'imageSha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in image_paths},
 'screenSource':'R2022b captureTab/exportapp; source excerpts are quoted as text (no editor screenshot)',
 'exampleChanges':['button Text','fileGrid column widths','fileGrid seventh row and explanatory label'],
 'productionApplicationEdited':False,'windowsEditorCaptured':False,'windowsBuildExecuted':False}
(HERE/'source-evidence.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n')
assert not re.search(r'［[^］]+］',doc)
assert len(re.findall(r'<section id=',doc))==13
assert 'src="images/' not in offline
assert 'data-image="images/' not in offline
print(json.dumps({'html':str(GUIDE/'ui-editing-guide.html'),'bytes':len(offline.encode()),'sections':13,'images':len(evidence['imageSha256'])},ensure_ascii=False))
