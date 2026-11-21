function showRows(grid, rows, visible, heights)
% 格子（uigridlayout）の行 rows を出す・しまう。しまう行は高さ 0 にし、その行にある部品も見えなくする
% （使わない欄を灰色で並べず、画面を短くするため）。heights：出すときの行の高さ（cell。省略時はすべて 'fit'）
if nargin < 4
    heights = repmat({'fit'}, 1, numel(rows));
end
rowHeights = grid.RowHeight;
for k = 1:numel(rows)
    if visible
        rowHeights{rows(k)} = heights{min(k, numel(heights))};
    else
        rowHeights{rows(k)} = 0;
    end
end
grid.RowHeight = rowHeights;
for child = reshape(grid.Children, 1, [])
    if isprop(child, 'Layout') && isprop(child.Layout, 'Row') && any(ismember(child.Layout.Row, rows))
        child.Visible = matlab.lang.OnOffSwitchState(visible);
    end
end
end
