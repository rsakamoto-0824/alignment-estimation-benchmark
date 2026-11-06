function handles = referenceArrow(ax, position, scaleMmPerNm, targetMm, color)
%REFERENCEARROW 図の中に矢印の長さの目安（凡例のベクトル）を描く（例：→ 5 nm）。
%   handles = alignest.plot.referenceArrow(ax, position, scaleMmPerNm, targetMm, color)
%   position：矢印の始点 [mm]、scaleMmPerNm：矢印の倍率 [mm/nm]、targetMm：矢印の長さの目安 [mm]（これ以下で、1・2・5 × 10^n nm の
%   きりのよい長さにする）、color：色。handles は矢印と文字。
if scaleMmPerNm <= 0 || ~isfinite(scaleMmPerNm)
    handles = gobjects(0);
    return
end
wanted = targetMm / scaleMmPerNm;
magnitude = 10 ^ floor(log10(wanted));
steps = [1, 2, 5, 10] * magnitude;
lengthNm = max(steps(steps <= wanted * (1 + 1e-9)));
handles = gobjects(1, 2);
handles(1) = quiver(ax, position(1), position(2), lengthNm * scaleMmPerNm, 0, 0, 'Color', color, 'LineWidth', 2, ...
    'MaxHeadSize', 0.8, 'HandleVisibility', 'off');
handles(2) = text(ax, position(1) + lengthNm * scaleMmPerNm / 2, position(2), sprintf('%g nm', lengthNm), ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontSize', 9, 'Color', color, 'Interpreter', 'none');
end
