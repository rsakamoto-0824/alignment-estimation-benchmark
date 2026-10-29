function [nRows, nColumns] = tileShape(panel, nPanels)
% 図を並べる段と列の数：枠の幅・高さに合わせ、1枚（Wafer の正方形の図）が最も大きくなる並べ方にする
% （枠の大きさがまだ決まっていないときは、3枚までは横に、4枚以上は2段に並べる）
MIN_PANEL_SIZE = 50;
position = panel.Position;
nRows = 1 + (nPanels > 3);
nColumns = ceil(nPanels / nRows);
if numel(position) < 4 || position(3) < MIN_PANEL_SIZE || position(4) < MIN_PANEL_SIZE
    return
end
best = 0;
for rows = 1:nPanels
    columns = ceil(nPanels / rows);
    side = min(position(3) / columns, position(4) / rows);
    if side > best
        best = side;
        nRows = rows;
        nColumns = columns;
    end
end
end
