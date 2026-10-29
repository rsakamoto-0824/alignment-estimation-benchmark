"""画面だけを変更した説明用コピーをGit管理外に作る。

画面はタブごとのファイル（+appui）に分けてあるので、アプリの画面と計算のファイル一式をコピーし、
「1. データの読み込み」のファイル（+appui/DataTab.m）だけを書き換える。
"""
from pathlib import Path
import shutil

GUIDE = Path(__file__).resolve().parent.parent
APP = GUIDE.parents[2]
EXAMPLE = APP.parent / '.cache' / 'ui-editing-guide' / 'example'
if EXAMPLE.exists():
    shutil.rmtree(EXAMPLE)
EXAMPLE.mkdir(parents=True)
shutil.copy2(APP / 'AlignmentEstimationApp.m', EXAMPLE / 'AlignmentEstimationApp.m')
for folder in ('+appui', '+alignest', 'help'):
    shutil.copytree(APP / folder, EXAMPLE / folder)
target = EXAMPLE / '+appui' / 'DataTab.m'
original = target.read_text()
changed = original.replace("'Text', 'ファイルを選ぶ…', 'ButtonPushedFcn'", "'Text', '計測ファイルを選ぶ…', 'ButtonPushedFcn'", 1)
before = "fileGrid = uigridlayout(filePanel, [6, 4], 'ColumnWidth', {'fit', '1x', 260, 300}, ...\n                'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit', 'fit'}, 'Padding', 10);"
after = "fileGrid = uigridlayout(filePanel, [7, 4], 'ColumnWidth', {300, '1x', 280, 320}, ...\n                'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit'}, 'Padding', 10);\n            adminNote = uilabel(fileGrid, 'Text', '管理者向け注意：読み込み前に列と単位を確認してください。', ...\n                'WordWrap', 'on', 'FontColor', app.Palette.muted);\n            place(adminNote, 7, [1, 4]);"
assert changed != original, 'ボタンの文字が見つかりません。対象版と置換箇所を確認してください。'
assert before in changed, '元コードが変わっています。対象版と置換箇所を確認してください。'
changed = changed.replace(before, after, 1)
target.write_text(changed)
print('Prepared:', EXAMPLE)
