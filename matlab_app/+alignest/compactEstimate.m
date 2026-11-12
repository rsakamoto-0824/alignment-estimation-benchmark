function compact = compactEstimate(out)
%COMPACTESTIMATE 推定の結果（alignest.estimateWafer）のうち、評価点の推定値と点の番号だけを残す。
%   compact = alignest.compactEstimate(out)
%   compact.testIndex.X / Y・estimate.X / Y・trainIndex.X / Y・outlierIndex・variance.X / Y（GPR の推定の分散。ほかの手法は空）を、
%   評価の結果（results.pointEstimates）に
%   行ごとに持つ。指標の計算し直し（alignest.filterResults）、マップ・散布図・推定値の表（alignest.collectEstimates）で、
%   推定をやり直さずに estimateWafer の結果の代わりに使える。
variance = struct("X", zeros(0, 1), "Y", zeros(0, 1));
if isfield(out, "variance")
    variance = out.variance;   % GPR の評価点の推定の分散（ほかの手法は空）
end
compact = struct("testIndex", out.testIndex, "estimate", out.estimate, "trainIndex", out.trainIndex, ...
    "outlierIndex", out.outlierIndex, "variance", variance);
end
