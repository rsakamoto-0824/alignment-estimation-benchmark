function [dxField, dyField] = formulaFields(parent, row, column, callback, tooltip)
% 補正の式（dx・dy）を入れる欄
grid = uigridlayout(parent, [2, 2], 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', 'fit'}, 'Padding', 0, ...
    'RowSpacing', 4);
place(grid, row, column);
label(grid, 'dx =', 1, 1);
dxField = uieditfield(grid, 'text', 'ValueChangedFcn', callback, 'Tooltip', tooltip);
place(dxField, 1, 2);
label(grid, 'dy =', 2, 1);
dyField = uieditfield(grid, 'text', 'ValueChangedFcn', callback, 'Tooltip', tooltip);
place(dyField, 2, 2);
end
