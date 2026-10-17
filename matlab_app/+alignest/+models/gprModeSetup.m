function [gp, basisTrain, basisTest, factorTrain, factorTest] = gprModeSetup(trainFeatures, testFeatures, groups, kernelName, factorMode, factors, maxIterations)
%GPRMODESETUP 質的変数の扱い方 factorMode に合わせて、GPR の前計算と平均の基底関数を作る。
%   factors は質的変数の水準（列ベクトル。使えない変数は空）：scanTrain, scanTest（Scan方向）、markTrain, markTest（Mark番号）
%   basisTrain / basisTest は平均の基底関数（定数と、固定効果にする質的変数の効果コード）。
%   factorTrain / factorTest は Scan方向・Mark番号の効果コード（Backfitting で使う）。
%   水準が学習点に1つしかない質的変数は推定できないので使わない（その扱い方は「使わない」と同じ式になる）。
if nargin < 7
    maxIterations = 300;
end
factorMode = string(factorMode);
if ~any(factorMode == alignest.models.gprFactorModes())
    error('alignest:factorMode', '質的変数の扱い方が正しくありません: %s', factorMode);
end
nTrain = size(trainFeatures, 1);
nTest = size(testFeatures, 1);
onesTrain = ones(nTrain, 1);
onesTest = ones(nTest, 1);
design = factorDesigns(factors, nTrain, nTest);
switch factorMode
    case {"none", "backfit"}
        [basisTrain, basisTest, categorical] = deal(onesTrain, onesTest, design.noComponents);
    case "basis"
        [basisTrain, basisTest] = withIntercept([design.scanTrain, design.markTrain], [design.scanTest, design.markTest]);
        categorical = design.noComponents;
    case "basis_int"
        [basisTrain, basisTest] = withIntercept([design.scanTrain, design.markTrain, design.interactionTrain], ...
            [design.scanTest, design.markTest, design.interactionTest]);
        categorical = design.noComponents;
    case "additive"
        [basisTrain, basisTest] = deal(onesTrain, onesTest);
        categorical = [design.scanComponent; design.markComponent];
    case "additive_int"
        [basisTrain, basisTest] = deal(onesTrain, onesTest);
        categorical = [design.scanComponent; design.markComponent; design.interactionComponent];
    case "mixed"
        [basisTrain, basisTest] = withIntercept(design.scanTrain, design.scanTest);
        categorical = design.markComponent;
    case "mixed_int"
        [basisTrain, basisTest] = withIntercept(design.scanTrain, design.scanTest);
        categorical = [design.markComponent; design.interactionComponent];
end
factorTrain = [design.scanTrain, design.markTrain];
factorTest = [design.scanTest, design.markTest];
gp = alignest.models.gprSetup(trainFeatures, testFeatures, groups, kernelName, categorical, maxIterations);
end

function [basisTrain, basisTest] = withIntercept(columnsTrain, columnsTest)
% 定数列を先頭に加え、学習点で一次従属な列（質的変数どうしが重なる場合）を除く
basisTrain = [ones(size(columnsTrain, 1), 1), columnsTrain];
basisTest = [ones(size(columnsTest, 1), 1), columnsTest];
keep = false(1, size(basisTrain, 2));
for column = 1:size(basisTrain, 2)
    keep(column) = true;
    if rank(basisTrain(:, keep)) < nnz(keep)
        keep(column) = false;
    end
end
basisTrain = basisTrain(:, keep);
basisTest = basisTest(:, keep);
end

function design = factorDesigns(factors, nTrain, nTest)
% 効果コードの列と、加法カーネルの項（水準が同じなら1の行列）を作る
empty = struct("name", {}, "trainSame", {}, "crossSame", {});
design.noComponents = empty;
[scanTrain, scanTest] = levelsOrEmpty(factors, "scan", nTrain, nTest);
[markTrain, markTest] = levelsOrEmpty(factors, "mark", nTrain, nTest);
[design.scanTrain, design.scanTest] = alignest.basis.effectCoding(scanTrain, scanTest);
[design.markTrain, design.markTest] = alignest.basis.effectCoding(markTrain, markTest);
% 交互作用の列：Scan方向と Mark番号の効果コードの積
design.interactionTrain = zeros(nTrain, 0);
design.interactionTest = zeros(nTest, 0);
for scanColumn = 1:size(design.scanTrain, 2)
    design.interactionTrain = [design.interactionTrain, design.scanTrain(:, scanColumn) .* design.markTrain];
    design.interactionTest = [design.interactionTest, design.scanTest(:, scanColumn) .* design.markTest];
end
design.scanComponent = component("scan", scanTrain, scanTest);
design.markComponent = component("mark", markTrain, markTest);
if isempty(design.scanComponent) || isempty(design.markComponent)
    design.interactionComponent = empty;
else
    design.interactionComponent = component("scan_mark", scanTrain * 1000 + markTrain, scanTest * 1000 + markTest);
end
end

function [levelsTrain, levelsTest] = levelsOrEmpty(factors, name, nTrain, nTest)
fieldTrain = char(name + "Train");
fieldTest = char(name + "Test");
if isfield(factors, fieldTrain) && ~isempty(factors.(fieldTrain)) && all(~isnan(factors.(fieldTrain)))
    levelsTrain = factors.(fieldTrain)(:);
    levelsTest = factors.(fieldTest)(:);
else
    levelsTrain = nan(nTrain, 1);
    levelsTest = nan(nTest, 1);
end
end

function item = component(name, levelsTrain, levelsTest)
if numel(unique(levelsTrain(~isnan(levelsTrain)))) < 2
    item = struct("name", {}, "trainSame", {}, "crossSame", {});
    return
end
item = struct("name", name, ...
    "trainSame", double(levelsTrain == levelsTrain.'), ...
    "crossSame", double(levelsTest == levelsTrain.'));
end
