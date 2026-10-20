function features = distanceFeatures(xMm, yMm, featureSet, waferRadiusMm)
%DISTANCEFEATURES 距離で類似度を測る手法（GPR・TPS・RBF・Kriging）に渡す説明変数の行列（点数 × 次元）。
%   座標は Wafer 半径で割って単位をそろえる。
%   XY   : (x, y)
%   XYR  : (x, y, r)
%   XYRT : (x, y, r, cos θ, sin θ)。T は ASML R&T の接線方向の位置＝方位角 θ = atan2(y, x)。
%          ±180° の境目で値が飛ばないよう cos・sin の2列に展開する。
x = xMm(:) / waferRadiusMm;
y = yMm(:) / waferRadiusMm;
switch featureSet
    case 'XY'
        features = [x, y];
    case 'XYR'
        features = [x, y, hypot(x, y)];
    case 'XYRT'
        theta = atan2(y, x);
        features = [x, y, hypot(x, y), cos(theta), sin(theta)];
    otherwise
        error('alignest:featureSet', '説明変数の組は XY・XYR・XYRT のいずれかです: %s', featureSet);
end
end
