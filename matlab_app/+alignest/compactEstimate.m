function compact = compactEstimate(out)
%COMPACTESTIMATE 推定の結果（alignest.estimateWafer）のうち、評価点の推定値と点の番号だけを残す。
%   compact = alignest.compactEstimate(out)
%   compact.testIndex.X / Y・estimate.X / Y・trainIndex.X / Y・outlierIndex を、評価の結果（results.pointEstimates）に
%   行ごとに持つ。指標の計算し直し（alignest.filterResults）、マップ・散布図・推定値の表（alignest.collectEstimates）で、
%   推定をやり直さずに estimateWafer の結果の代わりに使える。
compact = struct("testIndex", out.testIndex, "estimate", out.estimate, "trainIndex", out.trainIndex, ...
    "outlierIndex", out.outlierIndex);
end
