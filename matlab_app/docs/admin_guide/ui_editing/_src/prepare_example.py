"""画面だけを変更した説明用コピーをGit管理外に作る。"""
from pathlib import Path
import shutil

GUIDE = Path(__file__).resolve().parent.parent
APP = GUIDE.parents[2]
EXAMPLE = APP.parent / '.cache' / 'ui-editing-guide' / 'example'
EXAMPLE.mkdir(parents=True, exist_ok=True)
original = (APP / 'AlignmentEstimationApp.m').read_text()
changed = original.replace("'Text', 'ファイルを選ぶ…', 'ButtonPushedFcn'", "'Text', '計測ファイルを選ぶ…', 'ButtonPushedFcn'", 1)
before = "fileGrid = uigridlayout(filePanel, [6, 4], 'ColumnWidth', {'fit', '1x', 260, 300}, ...\n                'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit', 'fit'}, 'Padding', 10);"
after = "fileGrid = uigridlayout(filePanel, [7, 4], 'ColumnWidth', {300, '1x', 280, 320}, ...\n                'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit'}, 'Padding', 10);\n            adminNote = uilabel(fileGrid, 'Text', '管理者向け注意：読み込み前に列と単位を確認してください。', ...\n                'WordWrap', 'on', 'FontColor', app.Palette.muted);\n            place(adminNote, 7, [1, 4]);"
assert before in changed, '元コードが変わっています。対象版と置換箇所を確認してください。'
changed = changed.replace(before, after, 1)
(EXAMPLE / 'AlignmentEstimationApp.m').write_text(changed)
if not (EXAMPLE / 'help').is_symlink():
    shutil.copytree(APP / 'help', EXAMPLE / 'help', dirs_exist_ok=True)
print('Prepared:', EXAMPLE)
