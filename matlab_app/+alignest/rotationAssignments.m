function [names, labels] = rotationAssignments()
%ROTATIONASSIGNMENTS 計測マップの振り分け方の名前（alignest.rotationMaps の assignment）と画面の名前（「8. 計測Mapローテ」）。
%   [names, labels] = alignest.rotationAssignments()
%   並びは画面の並び（I 最適・D 最適・ポアソンディスク・ランダム・表の順。「2. 面内推定の設定」の計測点の選び方と同じ順）。
names = ["ioptimal", "doptimal", "poisson", "random", "order"];
labels = ["I 最適", "D 最適", "ポアソンディスク", "ランダム", "表の順"];
end
