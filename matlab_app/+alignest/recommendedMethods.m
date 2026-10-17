function methods = recommendedMethods(selection)
%RECOMMENDEDMETHODS 比べる手法の選び方。selection = "recommended"（既定）・"all"・"none"。
%   recommended：前回の模擬データ1000枚の評価で各系統の代表になった設定と、GPR の質的変数の主な扱い方
%     GPR matern52（X,Y,半径）× 質的変数（使わない・同時推定・加法カーネル・混合）、TPS、Kriging exponential、
%     GAM、XY5次多項式、RT モデル K=5。説明変数は X,Y,半径。
if nargin < 1
    selection = "recommended";
end
methods.featureSets = "XYR";
methods.gpr.enabled = true;
methods.gpr.kernels = "matern52";
methods.gpr.factorModes = ["none", "basis", "additive", "mixed"];
methods.tps.enabled = true;
methods.kriging.ordinary = true;
methods.kriging.universal = false;
methods.kriging.variograms = "exponential";
methods.gam.enabled = true;
methods.polynomial.enabled = true;
methods.polynomial.order = 5;
methods.rt.enabled = true;
methods.rt.orders = 5;
% 手法の細かい設定（Python 版と同じ値）
methods.options.gprMaxIterations = 300;
methods.options.backfitMaxIterations = 20;
methods.options.backfitToleranceNm = 1e-3;
methods.options.krigingLags = 6;
methods.options.tpsLog10Lambda = [-8, 3, 45];  % 最小・最大・点数
methods.options.gamBasisAxis = 8;
methods.options.gamBasisRadius = 8;
methods.options.gamBasisAngle = 8;
switch selection
    case "recommended"
    case "all"
        methods.featureSets = ["XY", "XYR", "XYRT"];
        methods.gpr.kernels = alignest.models.gprKernelNames();
        methods.gpr.factorModes = alignest.models.gprFactorModes();
        methods.kriging.universal = true;
        methods.kriging.variograms = ["linear", "gaussian", "power", "exponential"];
        methods.rt.orders = [4, 5];
    case "none"
        methods.gpr.enabled = false;
        methods.tps.enabled = false;
        methods.kriging.ordinary = false;
        methods.kriging.universal = false;
        methods.gam.enabled = false;
        methods.polynomial.enabled = false;
        methods.rt.enabled = false;
    otherwise
        error('alignest:selection', '選び方は recommended・all・none のいずれかです: %s', selection);
end
end
