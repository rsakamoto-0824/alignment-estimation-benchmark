function [sizeMm, estimated] = shotSize(shotXmm, shotYmm, markXmm, markYmm)
%SHOTSIZE Shot の大きさ [幅, 高さ]（mm）を、Shot 中心の間隔から推定する（Wafer マップに Shot の枠を描くため）。
%   同じ行（Y が同じ）の隣り合う Shot の X の間隔、同じ列の Y の間隔のうち、最も小さい値を使う
%   （Shot は格子状に並ぶので、間の Shot が抜けた所の間隔は Shot の大きさの整数倍になる）。
%   1 mm 未満の間隔は座標の書き方の揺れとみなして使わない。
%   隣り合う Shot が無い向きは、Mark の広がりの 1.2 倍を仮の大きさにする（estimated はその向きが false）。
DIGITS = 3;               % 座標を丸める桁（1 µm）
MARK_SPREAD_FACTOR = 1.2; % 間隔が分からないとき、Mark の広がりに足す余白の倍率
MIN_SIZE_MM = 1;          % Mark が1点だけのときなどの最小の大きさ
x = round(shotXmm(:), DIGITS);
y = round(shotYmm(:), DIGITS);
sizeMm = [commonSpacing(x, y), commonSpacing(y, x)];
estimated = isfinite(sizeMm);
spread = [max(markXmm) - min(markXmm), max(markYmm) - min(markYmm)];
for k = find(~estimated)
    sizeMm(k) = max(MARK_SPREAD_FACTOR * spread(k), MIN_SIZE_MM);
end
end

function spacing = commonSpacing(along, across)
% across が同じ Shot どうしで along の隣との差を集め、最も小さい差を返す（無ければ NaN）
MIN_GAP_MM = 1;
gaps = zeros(0, 1);
for level = unique(across).'
    values = unique(along(across == level));
    gaps = [gaps; diff(values)]; %#ok<AGROW>
end
gaps = gaps(gaps >= MIN_GAP_MM);
if isempty(gaps)
    spacing = NaN;
else
    spacing = min(gaps);
end
end
