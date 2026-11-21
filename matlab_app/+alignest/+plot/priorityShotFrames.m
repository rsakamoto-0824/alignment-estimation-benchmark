function handle = priorityShotFrames(ax, rows, shotNos, shotSizeMm)
%PRIORITYSHOTFRAMES 優先度 1 に指定した Shot（「8. 計測Mapローテ」）を、今の図に太い赤紫の枠で重ねて描く。
%   handle = alignest.plot.priorityShotFrames(ax, rows, shotNos, shotSizeMm)
%   rows：shotNo・Xc・Yc（Shot 中心 [mm]）の列のある表（alignest.markVariability・rotationMaps の table）。
%   shotNos：指定した shotNo。shotSizeMm：Shot の [幅, 高さ] [mm]。
%   handle：描いた線（凡例の名前は「優先度 1 に指定（n）」。n は描いた Shot の数）。表に無い shotNo は描かず、
%   描く Shot が無い・Shot の大きさが分からないときは空。線はクリックを図に渡し（HitTest = off）、点の下に描く
%   （Shot の角の Mark を隠さないように）。
FRAME_COLOR = [0.75, 0.00, 0.55];   % 優先度の色（赤・橙・青・緑・紫・灰）と見分けられる色
FRAME_LINE_WIDTH = 2;
handle = gobjects(0);
columns = string(rows.Properties.VariableNames);
if isempty(shotNos) || ~all(ismember(["shotNo", "Xc", "Yc"], columns))
    return
end
chosen = ismember(rows.shotNo, shotNos);
[~, first] = unique(rows.shotNo(chosen), 'stable');
centers = [rows.Xc(chosen), rows.Yc(chosen)];
centers = centers(first, :);
if isempty(centers)
    return
end
held = ishold(ax);
hold(ax, 'on');
handle = alignest.plot.shotFrames(ax, centers, shotSizeMm, FRAME_COLOR);
if ~held
    hold(ax, 'off');
end
if ~isempty(handle)
    set(handle, 'LineWidth', FRAME_LINE_WIDTH, 'HandleVisibility', 'on', 'HitTest', 'off', ...
        'DisplayName', sprintf("優先度 1 に指定（%d）", size(centers, 1)));
    uistack(handle, 'bottom');   % 点（Mark・Shot の印）の下にする
end
end
