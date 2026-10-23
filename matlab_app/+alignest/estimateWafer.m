function out = estimateWafer(unit, trainShots, method, settings, testMask)
%ESTIMATEWAFER 1つの Wafer（評価の単位）で、学習 Shot の計測値から評価 Shot の全 Mark を推定する。
%   trainShots は学習に使う Shot の番号（unit.shots の何番目か）。
%   X・Y は別々に当てはめる（RT モデルだけは X・Y を同時に当てはめる）。
%   学習点は学習 Shot の有効な Mark、評価点は学習しなかった Shot の有効な Mark（軸ごとに有効な点が違ってもよい）。
%   settings.evaluation.removeLinear が true なら、学習点で XY 1次（[1, x, y]、軸ごと）を除いてから推定し、
%   推定値に戻す（有効自由度は軸ごとに3を足す）。
%   settings.evaluation.excludeOutliers が true なら、学習点のうち平均から outlierSigma × σ を超えて離れた Mark を
%   X・Y の両方の学習データから除く（平均・σ はこの Wafer・この学習 Shot の組で求める。alignest.trainingOutliers）。
%   除いた Mark は評価にも使わない（学習 Shot の Mark なので）。out.outlierIndex はその Mark 番号。
%   out.testIndex.X / Y は評価点の Mark 番号（unit.marks の何番目か）、out.estimate.X / Y はその推定値。
%   testMask（省略可、Mark ごとの論理ベクトル）を渡すと、評価点をその Mark に限る（処理時間の内訳で、推定する点を
%   減らして当てはめだけの時間を測るため。alignest.timingBreakdown）。
%   out.timing は段階ごとの秒数（outliers：異常値の判定、model：モデルの当てはめと評価点の推定、
%   prepare：それ以外の準備。合計が out.seconds）。
timer = tic;
marks = unit.marks;
radius = settings.data.waferRadiusMm;
if nargin < 5 || isempty(testMask)
    testMask = true(numel(marks.x), 1);
end
inTrain = ismember(marks.shotIndex, trainShots);
outlier = false(size(inTrain));
outlierTimer = tic;
if isfield(settings.evaluation, "excludeOutliers") && settings.evaluation.excludeOutliers
    outlier = alignest.trainingOutliers(marks, inTrain, settings.evaluation.outlierSigma);
end
outlierSeconds = toc(outlierTimer);
axisNames = ["X", "Y"];
for axisName = axisNames
    valid = marks.("valid" + axisName);
    trainIndex.(axisName) = find(inTrain & valid & ~outlier);
    testIndex.(axisName) = find(~inTrain & valid & testMask(:));
    measured.(axisName) = marks.("meas" + axisName)(trainIndex.(axisName));
    if numel(trainIndex.(axisName)) < 3
        error('alignest:fewPoints', '%s の学習点が %d 点しかありません。学習 Shot を増やしてください。', ...
            axisName, numel(trainIndex.(axisName)));
    end
end
xyNorm = [marks.x, marks.y] / radius;
linearPart = struct();
if settings.evaluation.removeLinear
    for axisName = axisNames
        designTrain = [ones(numel(trainIndex.(axisName)), 1), xyNorm(trainIndex.(axisName), :)];
        designTest = [ones(numel(testIndex.(axisName)), 1), xyNorm(testIndex.(axisName), :)];
        coefficients = designTrain \ measured.(axisName);
        linearPart.(axisName) = designTest * coefficients;
        measured.(axisName) = measured.(axisName) - designTrain * coefficients;
    end
end

methodSettings = alignest.completeMethodSettings(settings.methods);
options = methodSettings.options;
out.extra = struct();
out.converged = true;
out.aux = [NaN, NaN];
out.edf = [NaN, NaN];
modelTimer = tic;
switch method.family
    case "XY"
        order = sscanf(char(method.variant), 'order%d');
        for k = 1:2
            result = alignest.models.polynomialFitPredict(xyNorm(trainIndex.(axisNames(k)), :), ...
                xyNorm(testIndex.(axisNames(k)), :), measured.(axisNames(k)), order);
            estimate.(axisNames(k)) = result.prediction;
            out.edf(k) = result.edf;
        end
    case "RT"
        order = sscanf(char(method.variant), 'order%d');
        result = alignest.models.rtFitPredict(xyNorm(trainIndex.X, :), xyNorm(trainIndex.Y, :), ...
            xyNorm(testIndex.X, :), xyNorm(testIndex.Y, :), measured.X, measured.Y, order);
        estimate.X = result.predictionU;
        estimate.Y = result.predictionV;
        out.edf = [result.edfU, result.edfV];
    otherwise
        features = [];
        if any(method.family == ["GPR", "TPS", "RBF", "OK", "UK"])
            features = alignest.basis.distanceFeatures(marks.x, marks.y, method.featureSet, radius);
        end
        for k = 1:2
            train = trainIndex.(axisNames(k));
            test = testIndex.(axisNames(k));
            y = measured.(axisNames(k));
            switch method.family
                case "GPR"
                    factors = factorLevels(unit, marks, train, test, settings, axisNames(k));
                    result = alignest.models.gprFitPredict(features(train, :), features(test, :), ...
                        alignest.basis.featureGroups(method.featureSet), y, method.variant, method.factorMode, factors, ...
                        maxIterations=options.gprMaxIterations, backfitMaxIterations=options.backfitMaxIterations, ...
                        backfitTolerance=options.backfitToleranceNm);
                    out.aux(k) = result.noiseStd;
                    out.converged = out.converged && result.optimizerConverged && result.backfitConverged;
                    out.extra = addGprExtra(out.extra, result, axisNames(k));
                case "TPS"
                    grid = linspace(options.tpsLog10Lambda(1), options.tpsLog10Lambda(2), options.tpsLog10Lambda(3));
                    model = alignest.models.tpsSetup(features(train, :), features(test, :), grid);
                    fitSpatial = @(values) alignest.models.tpsFitPredict(model, values, returnSmoother=method.factorMode == "backfit");
                    result = fitWithFactors(fitSpatial, unit, train, test, y, method, settings, axisNames(k));
                    out.aux(k) = result.log10Lambda;
                    out.extra.("log10Lambda_" + axisNames(k)) = result.log10Lambda;
                case "RBF"
                    grid = linspace(options.rbfLog10Lambda(1), options.rbfLog10Lambda(2), options.rbfLog10Lambda(3));
                    model = alignest.models.rbfSetup(features(train, :), features(test, :), options.rbfLengthScales, grid);
                    fitSpatial = @(values) alignest.models.rbfFitPredict(model, values, returnSmoother=method.factorMode == "backfit");
                    result = fitWithFactors(fitSpatial, unit, train, test, y, method, settings, axisNames(k));
                    out.aux(k) = result.log10Lambda;
                    out.extra.("rbfLengthScale_" + axisNames(k)) = result.lengthScale;
                    out.extra.("log10Lambda_" + axisNames(k)) = result.log10Lambda;
                case {"OK", "UK"}
                    kinds = struct("OK", "ordinary", "UK", "universal");
                    model = alignest.models.krigingSetup(features(train, :), features(test, :), ...
                        kinds.(method.family), method.variant, options.krigingLags);
                    fitSpatial = @(values) alignest.models.krigingFitPredict(model, values, returnSmoother=method.factorMode == "backfit");
                    result = fitWithFactors(fitSpatial, unit, train, test, y, method, settings, axisNames(k));
                    out.aux(k) = result.nugget;
                case "GAM"
                    points = gamPoints(marks, radius);
                    factors = factorLevels(unit, marks, train, test, settings, axisNames(k));
                    [factorTrain, factorTest] = factorCodes(factors, numel(train), numel(test));
                    nBasis = struct("axis", options.gamBasisAxis, "radius", options.gamBasisRadius);
                    [gpTerms, gpKernel] = gamGpTerms(method.variant);
                    shapes = struct();
                    for term = gpTerms
                        shapes.(term) = "gp";
                    end
                    setup = @(scales) alignest.models.gamSetup(subsetPoints(points, train), subsetPoints(points, test), ...
                        method.featureSet, factorTrain, factorTest, nBasis, shapes=shapes, lengthScales=scales, ...
                        gpKnots=options.gamGpKnots, gpGridKnots=options.gamGpGridKnots, gpKernel=gpKernel);
                    result = alignest.models.gamShapeFit(setup, gpTerms, options.gamGpLengthScales, y);
                    out.aux(k) = mean(result.log10Lambda);
                    for term = gpTerms
                        out.extra.("gpLength_" + term + "_" + axisNames(k)) = result.lengthScales.(term);
                    end
                otherwise
                    error('alignest:family', '未知の手法です: %s', method.id);
            end
            if any(method.family == ["TPS", "RBF", "OK", "UK"]) && method.factorMode == "backfit"
                out.converged = out.converged && result.backfitConverged;
                out.extra.("backfitIterations_" + axisNames(k)) = result.nBackfitIterations;
            end
            estimate.(axisNames(k)) = result.prediction;
            out.edf(k) = result.edf;
        end
end
modelSeconds = toc(modelTimer);
for axisName = axisNames
    if settings.evaluation.removeLinear
        estimate.(axisName) = estimate.(axisName) + linearPart.(axisName);
    end
end
if settings.evaluation.removeLinear
    out.edf = out.edf + 3;
end
out.estimate = estimate;
out.testIndex = testIndex;
out.trainIndex = trainIndex;
out.outlierIndex = find(outlier);
out.seconds = toc(timer);
out.timing = struct("outliers", outlierSeconds, "model", modelSeconds, ...
    "prepare", max(out.seconds - outlierSeconds - modelSeconds, 0));
end

function result = fitWithFactors(fitSpatial, unit, train, test, y, method, settings, axisName)
if method.factorMode == "none"
    result = fitSpatial(y);
elseif method.factorMode == "backfit"
    factors = factorLevels(unit, unit.marks, train, test, settings, axisName);
    [codes, codesTest] = factorCodes(factors, numel(train), numel(test));
    result = alignest.models.spatialBackfit(fitSpatial, y, codes, codesTest, ...
        maxIterations=settings.methods.options.backfitMaxIterations, ...
        tolerance=settings.methods.options.backfitToleranceNm);
else
    error('alignest:spatialFactorMode', '質的変数の扱いは none または backfit を選んでください。');
end
end

function [train, test] = factorCodes(factors, nTrain, nTest)
% 選んだ質的変数の効果コードを並べ、学習点で一次従属な列（変数どうしが重なる場合）を除く
blocksTrain = {ones(nTrain, 1)};
blocksTest = {ones(nTest, 1)};
for name = alignest.factorNames(factors)
    [codesTrain, codesTest] = alignest.basis.effectCoding(factors.(name + "Train"), factors.(name + "Test"));
    blocksTrain{end + 1} = codesTrain; %#ok<AGROW>
    blocksTest{end + 1} = codesTest; %#ok<AGROW>
end
[train, test] = alignest.basis.independentColumns([blocksTrain{:}], [blocksTest{:}]);
train = train(:, 2:end);
test = test(:, 2:end);
end

function factors = factorLevels(unit, marks, train, test, settings, axisName)
% 選んだ質的変数（axisName の成分の選択）の水準（数値の符号）。Scan 方向が使えない Wafer・値の欠けがある列は NaN に
% して、推定では使わない。その他の列は Wafer ごとに文字列の水準を番号にする（項目名は col_<列名>）。
choice = alignest.factorChoice(settings, axisName);
factors = struct();
if choice.scan
    direction = nan(numel(marks.x), 1);
    if unit.hasDirection
        direction = marks.direction;
    end
    factors = addFactor(factors, "scan", direction, train, test);
end
if choice.mark
    factors = addFactor(factors, "mark", marks.markNo, train, test);
end
if choice.row
    factors = addFactor(factors, "row", marks.shotRowParity, train, test);
end
for column = choice.columns
    position = find(string(unit.attributeNames) == column, 1);
    if isempty(position)
        error('alignest:factorColumn', '質的変数に選んだ列「%s」が、読み込んだデータにありません。', column);
    end
    [~, ~, codes] = unique(marks.attributes(:, position));
    codes = double(codes);
    codes(marks.attributes(:, position) == "") = NaN;
    factors = addFactor(factors, alignest.factorFieldName(column), codes, train, test);
end
end

function factors = addFactor(factors, name, levels, train, test)
factors.(name + "Train") = levels(train);
factors.(name + "Test") = levels(test);
end

function [terms, kernel] = gamGpTerms(variant)
% GAM の variant（"pspline" または "gp:xy+r:matern32" のような形）から、ガウス過程回帰にする項の名前とカーネルを取り出す
% （カーネルの無い "gp:xy+r" は以前の書き方で、matern52）
terms = strings(1, 0);
kernel = "matern52";
variant = string(variant);
if startsWith(variant, "gp:")
    parts = split(extractAfter(variant, "gp:"), ":");
    terms = split(parts(1), "+").';
    if numel(parts) >= 2
        kernel = parts(2);
    end
end
end

function points = gamPoints(marks, radius)
points.x = marks.x / radius;
points.y = marks.y / radius;
points.r = marks.r / radius;
end

function subset = subsetPoints(points, index)
subset = structfun(@(values) values(index), points, 'UniformOutput', false);
end

function extra = addGprExtra(extra, result, axisName)
for k = 1:numel(result.lengthScales)
    extra.(sprintf("ls%d_%s", k, axisName)) = result.lengthScales(k);
end
extra.("sf_" + axisName) = result.signalStd;
if ~isnan(result.alpha)
    extra.("alpha_" + axisName) = result.alpha;
end
for name = string(fieldnames(result.tau)).'
    extra.("tau_" + name + "_" + axisName) = result.tau.(name);
end
end
