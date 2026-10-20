function [gp, basisTrain, basisTest, factorTrain, factorTest] = gprModeSetup(trainFeatures, testFeatures, groups, kernelName, factorMode, factors, maxIterations)
%GPRMODESETUP 質的変数の扱い方 factorMode に合わせて、GPR の前計算と平均の基底関数を作る。
%   factors は質的変数の水準：scanTrain/Test、markTrain/Test、任意の rowTrain/Test（Shot行の奇偶）。
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
names = ["scan", "mark", "row"];
codesTrain = cell(1, numel(names));
codesTest = cell(1, numel(names));
components = cell(1, numel(names));
for k = 1:numel(names)
    [train, test] = levelsOrEmpty(factors, names(k), nTrain, nTest);
    [codesTrain{k}, codesTest{k}] = alignest.basis.effectCoding(train, test);
    components{k} = component(names(k), train, test);
end
design.mainTrain = [codesTrain{:}];
design.mainTest = [codesTest{:}];
design.mainComponents = vertcat(components{:});
% 混合モデルでは Scan と行の奇偶を固定効果、Mark を変量効果にする。
design.fixedTrain = [codesTrain{1}, codesTrain{3}];
design.fixedTest = [codesTest{1}, codesTest{3}];
design.markComponent = components{2};
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
