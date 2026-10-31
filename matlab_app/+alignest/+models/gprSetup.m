function gp = gprSetup(trainFeatures, testFeatures, groups, kernelName, categorical, maxIterations)
%GPRSETUP GPR の前計算（学習点・評価点を固定し、目的変数だけを差し替えて使う）。
%   カーネル（r は長さスケールで割った距離。ARD は説明変数ごとに長さスケールを持つ）
%     exponential        : σf² exp(−r)
%     squaredexponential : σf² exp(−r²/2)
%     matern32           : σf² (1 + √3 r) exp(−√3 r)
%     matern52           : σf² (1 + √5 r + 5r²/3) exp(−√5 r)
%     rationalquadratic  : σf² (1 + r²/(2α))^(−α)
%     matern_nu<ν>       : σf² 2^(1−ν)/Γ(ν) (√(2ν) r)^ν K_ν(√(2ν) r)（ν を任意に指定する Matérn。K_ν は第2種変形ベッセル関数。
%                          例：matern_nu1.2。ν = 0.5・1.5・2.5 で exponential・matern32・matern52 と同じ式）
%     periodic           : σf² exp(−2 Σ_j sin²(π d_j / p) / ℓ²)（周期カーネル。d_j は説明変数 j ごとの距離 |x_j − x'_j|、
%                          p は周期（ハイパーパラメータ。説明変数と同じ Wafer 半径で割った単位）。1変数の周期カーネルの
%                          積なので、2変数以上でも正定値になる）
%     ard***             : 上の7種類の ARD 版（例：ardmatern_nu1.2。ardperiodic は ℓ が説明変数ごと）
%   categorical は質的変数のカーネル項 τ²·[水準が同じ] の構造体配列（name, trainSame, crossSame）。
%   加法カーネルでは質的変数の効果を平均0・分散 τ² の確率変数（変量効果）として扱う。
%   パラメータの並び：[log ℓ（1 または説明変数の数）, log σf, (log α または log p), log τ（項ごと）, log σn]
if nargin < 5 || isempty(categorical)
    categorical = struct("name", {}, "trainSame", {}, "crossSame", {});
end
if nargin < 6
    maxIterations = 300;
end
kernelName = string(kernelName);
[baseName, gp.ard, gp.nu] = parseKernelName(kernelName);
gp.kernelName = kernelName;
familyByName = containers.Map(["exponential", "squaredexponential", "matern32", "matern52", "rationalquadratic", ...
    "matern", "periodic"], ["exp", "se", "m32", "m52", "rq", "mnu", "per"]);
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
gp.hasAlpha = any(gp.family == ["rq", "per"]);   % 3つ目のハイパーパラメータ（rationalquadratic の α・periodic の周期 p）
gp.categorical = categorical(:);
gp.nCategorical = numel(categorical);
gp.categoricalOffset = gp.nLength + 1 + gp.hasAlpha + 1;  % log τ が始まる位置（1始まり）
gp.nParams = gp.nLength + 1 + gp.hasAlpha + gp.nCategorical + 1;
gp.nTrain = size(trainFeatures, 1);
gp.maxIterations = maxIterations;
end

function [baseName, ard, nu] = parseKernelName(kernelName)
% fitrgp と同じ10種類、「(ard)matern_nu<ν>」（ν を任意に指定する Matérn）、または「(ard)periodic」（周期カーネル）
nu = NaN;
ard = startsWith(kernelName, "ard");
baseName = kernelName;
if ard
    baseName = extractAfter(kernelName, 3);
end
if any(kernelName == alignest.models.gprKernelNames()) || baseName == "periodic"
    return
end
if startsWith(baseName, "matern_nu")
    nu = str2double(extractAfter(baseName, "matern_nu"));
    alignest.models.maternNuCheck(nu);
    baseName = "matern";
    return
end
error('alignest:kernel', 'GPR のカーネル名が正しくありません: %s', kernelName);
end
