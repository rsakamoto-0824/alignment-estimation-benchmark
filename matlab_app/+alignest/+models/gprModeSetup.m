function [gp, basisTrain, basisTest, factorTrain, factorTest] = gprModeSetup(trainFeatures, testFeatures, groups, kernelName, factorMode, factors, maxIterations)
%GPRMODESETUP 質的変数の扱い方 factorMode に合わせて、GPR の前計算と平均の基底関数を作る。
%   factors は質的変数の水準：<名前>Train/Test の組（scan：Scan 方向、mark：Mark 番号、row：Shot 行の奇偶、
%   col_<列名>：ファイルのその他の列）。並びは alignest.factorNames の順。
%   basisTrain / basisTest は平均の基底関数（定数と、固定効果にする質的変数の効果コード）。
%   factorTrain / factorTest は全質的変数の効果コード（Backfitting で使う）。
%   混合（mixed）は Mark 番号を変量効果（加法カーネル）、それ以外の質的変数を固定効果（基底関数）にする。
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
        [basisTrain, basisTest] = withIntercept(design.mainTrain, design.mainTest);
        categorical = design.noComponents;
    case "basis_int"
        [basisTrain, basisTest] = withIntercept([design.mainTrain, design.interactionTrain], ...
            [design.mainTest, design.interactionTest]);
        categorical = design.noComponents;
    case "additive"
        [basisTrain, basisTest] = deal(onesTrain, onesTest);
        categorical = design.mainComponents;
    case "additive_int"
        [basisTrain, basisTest] = deal(onesTrain, onesTest);
        categorical = [design.mainComponents; design.interactionComponents];
    case "mixed"
        [basisTrain, basisTest] = withIntercept(design.fixedTrain, design.fixedTest);
        categorical = design.markComponent;
    case "mixed_int"
        [basisTrain, basisTest] = withIntercept(design.fixedTrain, design.fixedTest);
        categorical = [design.markComponent; design.interactionComponents];
end
[factorTrain, factorTest] = withIntercept(design.mainTrain, design.mainTest);
factorTrain = factorTrain(:, 2:end);
factorTest = factorTest(:, 2:end);
gp = alignest.models.gprSetup(trainFeatures, testFeatures, groups, kernelName, categorical, maxIterations);
end

function [basisTrain, basisTest] = withIntercept(columnsTrain, columnsTest)
% 定数列を先頭に加え、学習点で一次従属な列（質的変数どうしが重なる場合）を除く
basisTrain = [ones(size(columnsTrain, 1), 1), columnsTrain];
basisTest = [ones(size(columnsTest, 1), 1), columnsTest];
[basisTrain, basisTest] = alignest.basis.independentColumns(basisTrain, basisTest);
end

function design = factorDesigns(factors, nTrain, nTest)
% 効果コードの列と、加法カーネルの項（水準が同じなら1の行列）を作る
empty = struct("name", {}, "trainSame", {}, "crossSame", {});
design.noComponents = empty;
names = alignest.factorNames(factors);
codesTrain = cell(1, numel(names));
codesTest = cell(1, numel(names));
components = cell(1, numel(names));
for k = 1:numel(names)
    [train, test] = levelsOrEmpty(factors, names(k), nTrain, nTest);
    [codesTrain{k}, codesTest{k}] = alignest.basis.effectCoding(train, test);
    components{k} = component(names(k), train, test);
end
design.mainTrain = [zeros(nTrain, 0), codesTrain{:}];
design.mainTest = [zeros(nTest, 0), codesTest{:}];
design.mainComponents = vertcat(empty, components{:});
% 混合モデルでは Mark を変量効果、それ以外（Scan・行の奇偶・その他の列）を固定効果にする。
isMark = names == "mark";
design.fixedTrain = [zeros(nTrain, 0), codesTrain{~isMark}];
design.fixedTest = [zeros(nTest, 0), codesTest{~isMark}];
design.markComponent = vertcat(empty, components{isMark});
% 交互作用ありの場合は有効な質的変数の全ペアを加える（3変数の積は加えない）。
design.interactionTrain = zeros(nTrain, 0);
design.interactionTest = zeros(nTest, 0);
design.interactionComponents = empty;
for first = 1:numel(names)
    for second = first + 1:numel(names)
        for column = 1:size(codesTrain{first}, 2)
            design.interactionTrain = [design.interactionTrain, codesTrain{first}(:, column) .* codesTrain{second}];
            design.interactionTest = [design.interactionTest, codesTest{first}(:, column) .* codesTest{second}];
        end
        if ~isempty(components{first}) && ~isempty(components{second})
            item = struct("name", names(first) + "_" + names(second), ...
                "trainSame", components{first}.trainSame .* components{second}.trainSame, ...
                "crossSame", components{first}.crossSame .* components{second}.crossSame);
            design.interactionComponents(end + 1, 1) = item;
        end
    end
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
