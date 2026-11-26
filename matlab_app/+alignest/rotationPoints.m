function points = rotationPoints(points, markNo)
%ROTATIONPOINTS 点の表（alignest.highOrderUnitPoints・highOrderTargetPoints の形）に、計測マップのローテーションで使う列を足す。
%   points = alignest.rotationPoints(points)
%   points = alignest.rotationPoints(points, markNo)
%   足す列：markNo（Mark の番号。分からなければ NaN）・key（Shot と Shot 内の位置の
%   名前。"shotNo|x|y"。x・y は Shot 内の座標を 0.001 mm で丸めた値。Wafer をまたいで同じ Shot・Mark を対応させる）。
arguments
    points table
    markNo double = []
end
POSITION_FORMAT = "%.3f";   % Shot 内の位置を丸める桁（1 µm。alignest.prepareData の重複の判定と同じ）
n = height(points);
if isempty(markNo)
    markNo = nan(n, 1);
end
points.markNo = double(markNo(:));
localX = round(points.localX, 3);
localY = round(points.localY, 3);
localX(localX == 0) = 0;   % −0 と 0 を同じ名前にする
localY(localY == 0) = 0;
points.key = string(points.shotNo) + "|" + compose(POSITION_FORMAT, localX) + "|" + compose(POSITION_FORMAT, localY);
end
