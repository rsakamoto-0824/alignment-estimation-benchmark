function prediction = gprPredict(gp, fit, testBasis)
%GPRPREDICT 評価点の推定値 = Hβ + K(評価点, 学習点) K_y⁻¹(y − Hβ)。
cross = alignest.models.gprKernel(gp, fit.logParams, "cross");
prediction = testBasis * fit.beta + cross * fit.alphaVector;
end
