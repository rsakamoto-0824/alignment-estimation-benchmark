function out = estimateWafer(unit, trainShots, method, settings)
%ESTIMATEWAFER 1つの Wafer（評価の単位）で、学習 Shot の計測値から評価 Shot の全 Mark を推定する。
%   trainShots は学習に使う Shot の番号（unit.shots の何番目か）。
%   X・Y は別々に当てはめる（RT モデルだけは X・Y を同時に当てはめる）。
%   学習点は学習 Shot の有効な Mark、評価点は学習しなかった Shot の有効な Mark（軸ごとに有効な点が違ってもよい）。
%   settings.evaluation.removeLinear が true なら、学習点で XY 1次（[1, x, y]、軸ごと）を除いてから推定し、
%   推定値に戻す（有効自由度は軸ごとに3を足す）。
%   out.testIndex.X / Y は評価点の Mark 番号（unit.marks の何番目か）、out.estimate.X / Y はその推定値。
timer = tic;
marks = unit.marks;
radius = settings.data.waferRadiusMm;
inTrain = ismember(marks.shotIndex, trainShots);
axisNames = ["X", "Y"];
for axisName = axisNames
    valid = marks.("valid" + axisName);
    trainIndex.(axisName) = find(inTrain & valid);
    testIndex.(axisName) = find(~inTrain & valid);
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
                    factors = factorLevels(unit, marks, train, test, settings);
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
                    result = fitWithFactors(fitSpatial, unit, train, test, y, method, settings);
                    out.aux(k) = result.log10Lambda;
                    out.extra.("log10Lambda_" + axisNames(k)) = result.log10Lambda;
                case "RBF"
                    grid = linspace(options.rbfLog10Lambda(1), options.rbfLog10Lambda(2), options.rbfLog10Lambda(3));
                    model = alignest.models.rbfSetup(features(train, :), features(test, :), options.rbfLengthScales, grid);
                    result = alignest.models.rbfFitPredict(model, y);
                    out.aux(k) = result.log10Lambda;
                    out.extra.("rbfLengthScale_" + axisNames(k)) = result.lengthScale;
                    out.extra.("log10Lambda_" + axisNames(k)) = result.log10Lambda;
                case {"OK", "UK"}
                    kinds = struct("OK", "ordinary", "UK", "universal");
                    model = alignest.models.krigingSetup(features(train, :), features(test, :), ...
                        kinds.(method.family), method.variant, options.krigingLags);
                    fitSpatial = @(values) alignest.models.krigingFitPredict(model, values, returnSmoother=method.factorMode == "backfit");
                    result = fitWithFactors(fitSpatial, unit, train, test, y, method, settings);
                    out.aux(k) = result.nugget;
                case "GAM"
                    points = gamPoints(marks, radius);
                    factors = factorLevels(unit, marks, train, test, settings);
                    [factorTrain, factorTest] = factorCodes(factors);
                    nBasis = struct("axis", options.gamBasisAxis, "radius", options.gamBasisRadius, ...
                        "angle", options.gamBasisAngle);
                    model = alignest.models.gamSetup(subsetPoints(points, train), subsetPoints(points, test), ...
                        method.featureSet, factorTrain, factorTest, nBasis);
                    result = alignest.models.gamFitPredict(model, y);
                    out.aux(k) = mean(result.log10Lambda);
                otherwise
                    error('alignest:family', '未知の手法です: %s', method.id);
            end
            if any(method.family == ["TPS", "OK", "UK"]) && method.factorMode == "backfit"
                out.converged = out.converged && result.backfitConverged;
                out.extra.("backfitIterations_" + axisNames(k)) = result.nBackfitIterations;
            end
            estimate.(axisNames(k)) = result.prediction;
            out.edf(k) = result.edf;
        end
end
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
out.seconds = toc(timer);
end

function result = fitWithFactors(fitSpatial, unit, train, test, y, method, settings)
if method.factorMode == "none"
    result = fitSpatial(y);
elseif method.factorMode == "backfit"
    factors = factorLevels(unit, unit.marks, train, test, settings);
    [codes, codesTest] = factorCodes(factors);
    result = alignest.models.spatialBackfit(fitSpatial, y, codes, codesTest, ...
        maxIterations=settings.methods.options.backfitMaxIterations, ...
        tolerance=settings.methods.options.backfitToleranceNm);
else
    error('alignest:spatialFactorMode', '質的変数の扱いは none または backfit を選んでください。');
end
end

function [train, test] = factorCodes(factors)
[scanTrain, scanTest] = alignest.basis.effectCoding(factors.scanTrain, factors.scanTest);
[markTrain, markTest] = alignest.basis.effectCoding(factors.markTrain, factors.markTest);
[rowTrain, rowTest] = alignest.basis.effectCoding(factors.rowTrain, factors.rowTest);
[train, test] = alignest.basis.independentColumns( ...
    [ones(numel(factors.markTrain), 1), scanTrain, markTrain, rowTrain], ...
    [ones(numel(factors.markTest), 1), scanTest, markTest, rowTest]);
train = train(:, 2:end);
test = test(:, 2:end);
end

function factors = factorLevels(unit, marks, train, test, settings)
% 質的変数の水準（Scan方向が使えない Wafer では空にする）
factors.markTrain = marks.markNo(train);
factors.markTest = marks.markNo(test);
if unit.hasDirection
    factors.scanTrain = marks.direction(train);
    factors.scanTest = marks.direction(test);
else
    factors.scanTrain = nan(numel(train), 1);
    factors.scanTest = nan(numel(test), 1);
end
factors.rowTrain = nan(numel(train), 1);
factors.rowTest = nan(numel(test), 1);
if isfield(settings, "factors") && settings.factors.shotRowParity
    factors.rowTrain = marks.shotRowParity(train);
    factors.rowTest = marks.shotRowParity(test);
end
end

function points = gamPoints(marks, radius)
points.x = marks.x / radius;
points.y = marks.y / radius;
points.r = marks.r / radius;
points.theta = marks.theta;
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
