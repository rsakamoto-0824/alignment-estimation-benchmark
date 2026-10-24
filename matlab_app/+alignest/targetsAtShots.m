function targets = targetsAtShots(unit, markXmm, markYmm, markNo)
%TARGETSATSHOTS すべての Shot の同じ位置（Shot 中心から markXmm・markYmm [mm]）に点を置く。
%   targets = alignest.targetsAtShots(unit, markXmm, markYmm, markNo)
%   新しい Mark の位置の値を全 Shot で推定するときに使う。Shot 中心・shotNo・Scan 方向は unit.shots から取る。
%   markNo は NaN でもよい（Mark 番号の効果は平均で推定）。名前は "S<shotNo>-M<markNo>"（Mark 番号が無ければ
%   "S<shotNo>"）。targets は alignest.targetTemplate の形。
arguments
    unit struct
    markXmm (1, 1) double {mustBeFinite}
    markYmm (1, 1) double {mustBeFinite}
    markNo (1, 1) double = NaN
end
shots = unit.shots;
n = numel(shots.Xmm);
targets = alignest.targetTemplate(n);
targets.Xmm = shots.Xmm(:);
targets.Ymm = shots.Ymm(:);
targets.markXmm(:) = markXmm;
targets.markYmm(:) = markYmm;
targets.markNo(:) = markNo;
targets.shotNo = shots.shotNo(:);
targets.direction = shots.direction(:);
targets.name = "S" + string(targets.shotNo);
if ~isnan(markNo)
    targets.name = targets.name + "-M" + string(markNo);
end
end
