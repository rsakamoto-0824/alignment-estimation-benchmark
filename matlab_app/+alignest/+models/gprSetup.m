function gp = gprSetup(trainFeatures, testFeatures, groups, kernelName, categorical, maxIterations)
%GPRSETUP GPR の前計算（学習点・評価点を固定し、目的変数だけを差し替えて使う）。
%   カーネル（r は長さスケールで割った距離。ARD は説明変数ごとに長さスケールを持つ）
%     exponential        : σf² exp(−r)
%     squaredexponential : σf² exp(−r²/2)
%     matern32           : σf² (1 + √3 r) exp(−√3 r)
%     matern52           : σf² (1 + √5 r + 5r²/3) exp(−√5 r)
%     rationalquadratic  : σf² (1 + r²/(2α))^(−α)
%     ard***             : 上の5種類の ARD 版
%   categorical は質的変数のカーネル項 τ²·[水準が同じ] の構造体配列（name, trainSame, crossSame）。
%   加法カーネルでは質的変数の効果を平均0・分散 τ² の確率変数（変量効果）として扱う。
%   パラメータの並び：[log ℓ（1 または説明変数の数）, log σf, (log α), log τ（項ごと）, log σn]
if nargin < 5 || isempty(categorical)
    categorical = struct("name", {}, "trainSame", {}, "crossSame", {});
end
if nargin < 6
    maxIterations = 300;
end
kernelName = string(kernelName);
if ~any(kernelName == alignest.models.gprKernelNames())
    error('alignest:kernel', 'GPR のカーネル名が正しくありません: %s', kernelName);
end
gp.kernelName = kernelName;
gp.ard = startsWith(kernelName, "ard");
baseName = kernelName;
if gp.ard
    baseName = extractAfter(kernelName, 3);
end
familyByName = containers.Map(["exponential", "squaredexponential", "matern32", "matern52", "rationalquadratic"], ...
    ["exp", "se", "m32", "m52", "rq"]);
gp.family = familyByName(char(baseName));
gp.trainSq = alignest.basis.pairwiseSquaredDiff(trainFeatures, trainFeatures, groups);
gp.crossSq = alignest.basis.pairwiseSquaredDiff(testFeatures, trainFeatures, groups);
gp.trainSqTotal = sum(gp.trainSq, 3);
gp.crossSqTotal = sum(gp.crossSq, 3);
nGroups = max(groups);
featureStd = zeros(nGroups, 1);
for group = 1:nGroups
    % 1変数を複数列に展開した場合（cos θ, sin θ）は各列の標準偏差の2乗和の平方根
    featureStd(group) = sqrt(sum(var(trainFeatures(:, groups == group), 1, 1)));
end
gp.featureStd = max(featureStd, 1e-3);
gp.nLength = 1;
if gp.ard
    gp.nLength = nGroups;
end
gp.hasAlpha = gp.family == "rq";
gp.categorical = categorical(:);
gp.nCategorical = numel(categorical);
gp.categoricalOffset = gp.nLength + 1 + gp.hasAlpha + 1;  % log τ が始まる位置（1始まり）
gp.nParams = gp.nLength + 1 + gp.hasAlpha + gp.nCategorical + 1;
gp.nTrain = size(trainFeatures, 1);
gp.maxIterations = maxIterations;
end
