function scale = stackArrowScale(values, sizeMm)
% Shot を重ねる図の矢印の倍率 [mm/nm]：大きさの95%点の矢印が Shot の短い辺の ARROW_RATIO 倍
% （alignest.plot.shotStackMap の自動の倍率と同じ。図を並べるとき、3つの図の値をまとめて決める。
% 「6. Shot高次補正」と「5. 未知の座標の推定」の補正残差のマップで使う）
ARROW_RATIO = 0.18;
magnitude = sort(hypot(values(:, 1), values(:, 2)));
magnitude = magnitude(isfinite(magnitude));
scale = 0;   % 0 なら shotStackMap が決める（値が無い・Shot の大きさが分からない）
if isempty(magnitude) || magnitude(end) <= 0 || any(~isfinite(sizeMm))
    return
end
reference = magnitude(max(1, ceil(0.95 * numel(magnitude))));
scale = min(sizeMm) * ARROW_RATIO / max(reference, eps);
end
