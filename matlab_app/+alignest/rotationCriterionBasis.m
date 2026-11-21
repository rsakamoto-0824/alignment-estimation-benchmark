function basis = rotationCriterionBasis(pointsMm, waferRadiusMm, designOrder, designFeatures)
%ROTATIONCRITERIONBASIS 計測マップの I 基準・D 基準に使う、点ごとの基底の行（「8. 計測Mapローテ」）。
%   basis = alignest.rotationCriterionBasis(pointsMm, waferRadiusMm, designOrder, designFeatures)
%   pointsMm：点の位置 [x, y] [mm]（Mark ごとは Mark、Shot ごとは Shot 中心）。I 最適の基準モデル（designOrder 次の
%   多項式。designFeatures："XYR"（X・Y・半径）・"XY"。座標は waferRadiusMm で割る。alignest.basis.designPolynomial）を、
%   全点で正規直交化する（QR 分解。「2. 面内推定の設定」の I 基準・D 基準と同じ。全点を計測すると情報行列が単位行列）。
%   basis：点 × 項。点が項の数より少ないときは止める。
design = alignest.basis.designPolynomial(pointsMm(:, 1) / waferRadiusMm, pointsMm(:, 2) / waferRadiusMm, ...
    designOrder, designFeatures);
if size(design, 1) < size(design, 2)
    error('alignest:rotationCriterion', ['I 最適の基準モデル（%d 次、%d 項）より点（%d 点）が少ないので、I 基準・D 基準を' ...
        '求められません。「2. 面内推定の設定」の基準モデルの次数を下げてください。'], designOrder, size(design, 2), ...
        size(design, 1));
end
[basis, ~] = qr(design, 0);
end
