function scaleMmPerNm = vectorScale(values)
%VECTORSCALE 矢印の長さの倍率 [mm/nm]。値の大きさの95%点が約12 mm の矢印になるようにする。
TARGET_ARROW_MM = 12;
magnitude = hypot(values(:, 1), values(:, 2));
magnitude = sort(magnitude(isfinite(magnitude)));
if isempty(magnitude) || magnitude(end) <= 0
    scaleMmPerNm = 1;
    return
end
reference = magnitude(max(1, ceil(0.95 * numel(magnitude))));
scaleMmPerNm = TARGET_ARROW_MM / max(reference, eps);
end
