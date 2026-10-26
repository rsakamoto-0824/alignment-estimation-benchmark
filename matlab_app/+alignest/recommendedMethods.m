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
methods.gpr.maternNu = 2;  % カーネル matern・ardmatern（ν を指定）を選んだときの ν（複数なら ν ごとに比べる）
methods.tps.enabled = true;
methods.tps.factorModes = "none";
methods.rbf.enabled = false;
methods.rbf.factorModes = "none";   % none（質的変数なし）・backfit（Backfitting）、両方なら比べる
methods.rbfe.enabled = false;        % RBFe（仮）：面内を領域に分けた TPS をつなぐ形状関数の GAM（alignest.models.rbfeSetup）
methods.rbfe.regions = 4;            % 領域の数（ハイパーパラメータ。空白区切りで複数なら、領域の数ごとに比べる）
methods.rbfe.factorModes = "backfit";  % 質的変数：backfit（Backfitting で効果を足す GAM）・none、両方なら比べる
methods.kriging.ordinary = true;
methods.kriging.universal = false;
methods.kriging.variograms = "exponential";
methods.kriging.ordinaryFactorModes = "none";
methods.kriging.universalFactorModes = "none";
methods.gam.enabled = true;
methods.gam.shapes = struct("xy", "spline", "r", "spline");  % 形状関数：spline・gp（項ごと）
methods.gam.gpKernels = "matern52";  % ガウス過程の形状関数のカーネル（alignest.models.gamKernelChoices。複数ならカーネルごとに比べる）
methods.gam.gpMaternNu = 2;          % カーネル matern（ν を指定）を選んだときの ν（複数なら ν ごとに比べる）
methods.polynomial.enabled = true;
methods.polynomial.order = 5;
methods.rt.enabled = true;
methods.rt.orders = 5;
methods.zernike.enabled = false;   % Fringe Zernike 多項式の近似（次数 k：Z1〜Z(k+1)²。複数なら次数ごとに比べる）
methods.zernike.orders = 4;
methods.zernike.factorModes = "none";   % 質的変数：none（使わない）・backfit（Backfitting で効果を足す）、両方なら比べる
% 手法の細かい設定（Python 版と同じ値）
methods.options.gprMaxIterations = 300;
methods.options.backfitMaxIterations = 20;
methods.options.backfitToleranceNm = 1e-3;
methods.options.krigingLags = 6;
methods.options.tpsLog10Lambda = [-8, 3, 45];  % 最小・最大・点数
methods.options.rbfLengthScales = [0.05, 0.1, 0.2, 0.4, 0.8, 1.6];
methods.options.rbfLog10Lambda = [-8, 3, 45];
methods.options.gamBasisAxis = 8;
methods.options.gamBasisRadius = 8;
methods.options.gamGpLengthScales = [0.15, 0.3, 0.6];  % GAM のガウス過程の長さスケールの候補（Wafer 半径で割った単位）
methods.options.gamGpKnots = 10;      % GAM のガウス過程の節点の数（半径）
methods.options.gamGpGridKnots = 7;   % GAM のガウス過程の節点の格子（X・Y、各軸）
methods.options.rbfeOverlap = 1.5;    % RBFe の領域の半径の倍率（まとまりの点の中心からの最大距離 × これ。1 より大きく、隣と重ねる）
methods.options.rbfeMinPoints = 10;   % RBFe の領域ごとの学習点の最小数（足りなければ半径を広げ、領域の数を減らす）
switch selection
    case "recommended"
    case "all"
        methods.rbf.enabled = true;
        methods.rbf.factorModes = ["none", "backfit"];
        methods.tps.factorModes = ["none", "backfit"];
        methods.kriging.ordinaryFactorModes = ["none", "backfit"];
        methods.kriging.universalFactorModes = ["none", "backfit"];
        methods.featureSets = ["XY", "XYR"];
        methods.gpr.kernels = alignest.models.gprKernelChoices();
        methods.gpr.factorModes = alignest.models.gprFactorModes();
        methods.kriging.universal = true;
        methods.kriging.variograms = ["linear", "gaussian", "power", "exponential", "spherical"];
        methods.rt.orders = [4, 5];
        methods.zernike.enabled = true;
        methods.zernike.orders = [3, 4, 5];
        methods.zernike.factorModes = ["none", "backfit"];
        methods.rbfe.enabled = true;
        methods.rbfe.regions = [4, 9];
        methods.rbfe.factorModes = ["none", "backfit"];
    case "none"
        methods.gpr.enabled = false;
        methods.tps.enabled = false;
        methods.kriging.ordinary = false;
        methods.kriging.universal = false;
        methods.gam.enabled = false;
        methods.polynomial.enabled = false;
        methods.rt.enabled = false;
        methods.zernike.enabled = false;
        methods.rbfe.enabled = false;
    otherwise
        error('alignest:selection', '選び方は recommended・all・none のいずれかです: %s', selection);
end
end
