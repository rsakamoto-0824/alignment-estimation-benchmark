function outer = outerShots(shots)
%OUTERSHOTS 最外周の Shot（上下左右の隣のどれかに Shot が無い Shot）を論理ベクトルで返す。
%   outer = alignest.outerShots(unit.shots)
%   隣は Shot の行・列の番号（shots.row・shots.column。Shot 中心の座標から数えた格子の位置）で調べる。
%   半径の外などで Shot が無くなった所の内側の Shot も最外周になる（計測できる Shot の外周）。
NEIGHBORS = [-1, 0; 1, 0; 0, -1; 0, 1];
position = [shots.row(:), shots.column(:)];
outer = false(size(position, 1), 1);
for k = 1:size(NEIGHBORS, 1)
    outer = outer | ~ismember(position + NEIGHBORS(k, :), position, 'rows');
end
end
