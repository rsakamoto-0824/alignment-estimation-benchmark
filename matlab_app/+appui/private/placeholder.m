function item = placeholder(app, parent, text)
% 結果がまだ無い枠（uipanel・uitab）に出す案内：枠の中央に灰色の文字（何を押すとここに出るか）。
% 枠に図や表を描くときは、先に枠の子（この案内）を消す
grid = uigridlayout(parent, [1, 1], 'Padding', 20);
item = uilabel(grid, 'Text', text, 'WordWrap', 'on', 'HorizontalAlignment', 'center', ...
    'FontColor', app.Palette.muted, 'UserData', "muted");
end
