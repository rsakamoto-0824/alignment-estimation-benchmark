function item = label(parent, text, row, column)
item = uilabel(parent, 'Text', text, 'WordWrap', 'on');
if nargin >= 3
    place(item, row, column);
end
end
