function filter = defaultPointFilter()
%DEFAULTPOINTFILTER 評価点の絞り込み（alignest.pointFilterMask）の初期値：絞り込まない。
%   filter.radiusMinMm・radiusMaxMm：Mark の半径 [mm] の範囲（最小以上・最大未満。最大 Inf なら上限なし）
%   filter.shotMode：all（すべて）・include（shotNos の Shot だけ）・exclude（shotNos の Shot を除く）
%   filter.shotNos ：shotNo の並び
%   filter.scan    ：0（すべて）・1・2（その Scan 方向の Shot だけ）
%   filter.outer   ：all（すべて）・only（最外周の Shot だけ）・exclude（最外周の Shot を除く。alignest.outerShots）
filter = struct("radiusMinMm", 0, "radiusMaxMm", Inf, "shotMode", "all", "shotNos", zeros(1, 0), "scan", 0, ...
    "outer", "all");
end
