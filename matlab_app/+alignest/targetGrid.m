function targets = targetGrid(pitchMm, radiusMm)
%TARGETGRID Wafer 上に間隔 pitchMm [mm] の格子の点を、中心からの半径 radiusMm [mm] 以下に置く。
%   targets = alignest.targetGrid(pitchMm, radiusMm)
%   Wafer 全面の推定値を見るときに使う。格子は原点を通る。点は上の行から左→右の順で、名前は G1, G2, …。
%   Shot 内の座標は 0（Xmm・Ymm が点そのものの座標）、Mark 番号・shotNo・Scan 方向は無し（推定のとき、
%   点を含む Shot から Scan 方向を補う。alignest.predictTargets）。点が MAX_POINTS を超える指定は止める。
arguments
    pitchMm (1, 1) double {mustBeFinite, mustBePositive}
    radiusMm (1, 1) double {mustBeFinite, mustBePositive}
end
MAX_POINTS = 20000;   % 画面の表と推定の時間が長くなりすぎない点の数
steps = floor(radiusMm / pitchMm);
if (2 * steps + 1)^2 > 2 * MAX_POINTS   % 円の中は正方形の格子の約 8 割なので、これより多い格子は作る前に止める
    error('alignest:targetGrid', '点が多すぎます（約 %d 点）。間隔を広げるか半径を小さくしてください（上限 %d 点）。', ...
        round(pi * (radiusMm / pitchMm)^2), MAX_POINTS);
end
coordinates = (-steps:steps) * pitchMm;
[x, y] = meshgrid(coordinates, flip(coordinates));   % 上の行（Y が大きい）から
x = reshape(x.', [], 1);
y = reshape(y.', [], 1);
inside = hypot(x, y) <= radiusMm + 1e-9;
x = x(inside);
y = y(inside);
if numel(x) > MAX_POINTS
    error('alignest:targetGrid', '点が多すぎます（%d 点）。間隔を広げるか半径を小さくしてください（上限 %d 点）。', ...
        numel(x), MAX_POINTS);
end
targets = alignest.targetTemplate(numel(x));
targets.Xmm = x;
targets.Ymm = y;
targets.name = "G" + string((1:numel(x)).');
end
