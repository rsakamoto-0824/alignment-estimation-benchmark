function features = distanceFeatures(xMm, yMm, featureSet, waferRadiusMm)
%DISTANCEFEATURES 距離で類似度を測る手法（GPR・TPS・RBF・Kriging）に渡す説明変数の行列（点数 × 次元）。
%   座標は Wafer 半径で割って単位をそろえる。
%   XY   : (x, y)
%   XYR  : (x, y, r)
%   （以前の XYRT（方位角 T を加えた組）は使わなくなったので削除した）
x = xMm(:) / waferRadiusMm;
y = yMm(:) / waferRadiusMm;
switch featureSet
    case 'XY'
        features = [x, y];
    case 'XYR'
        features = [x, y, hypot(x, y)];
    otherwise
        error('alignest:featureSet', '説明変数の組は XY・XYR のいずれかです: %s', featureSet);
end
end
