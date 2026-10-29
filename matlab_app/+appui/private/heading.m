function heading(parent, text, row)
item = uilabel(parent, 'Text', text, 'FontWeight', 'bold', 'WordWrap', 'on');   % 欄が狭くても切れないように折り返す
place(item, row, [1, 2]);
end
