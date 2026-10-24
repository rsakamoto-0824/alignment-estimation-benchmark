classdef TestSpatialModels < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addAppPath(~)
            addpath(fileparts(fileparts(mfilename('fullpath'))));
        end
    end

    methods (Test)
        function rbfMatchesDirectAugmentedSystem(testCase)
            [train, test, y] = points();
            ell = 0.4;
            model = alignest.models.rbfSetup(train, test, ell, -2);
            out = alignest.models.rbfFitPredict(model, y);
            kernel = exp(-alignest.basis.pairwiseSquaredDiff(train, train) / (2*ell^2));
            cross = exp(-alignest.basis.pairwiseSquaredDiff(test, train) / (2*ell^2));
            p = [ones(size(train, 1), 1), train];
            pt = [ones(size(test, 1), 1), test];
            lambda = 10^out.log10Lambda;
            system = [kernel + lambda*eye(numel(y)), p; p.', zeros(size(p, 2))];
            operator = system \ [eye(numel(y)); zeros(size(p, 2), numel(y))];
            testCase.verifyEqual(out.prediction, [cross, pt]*operator*y, 'AbsTol', 1e-9);
            testCase.verifyEqual(out.edf, trace([kernel, p]*operator), 'AbsTol', 1e-9);
            fitted = [kernel, p]*operator*y;
            testCase.verifyEqual(out.gcv, numel(y)*sum((y-fitted).^2)/(numel(y)-out.edf)^2, 'RelTol', 1e-8);
        end

        function rbfSelectsGcvWithoutTestResponses(testCase)
            [train, test, y] = points();
            model = alignest.models.rbfSetup(train, test, [0.1, 0.4, 1], [-4, -2, 0]);
            out = alignest.models.rbfFitPredict(model, y);
            best = Inf;
            for candidate = model.candidates.'
                fitted = alignest.models.radialFitPredict(candidate{1}, y);
                best = min(best, fitted.gcv);
            end
            testCase.verifyEqual(out.gcv, best);
            moved = alignest.models.rbfSetup(train, test+0.2, [0.1, 0.4, 1], [-4, -2, 0]);
            other = alignest.models.rbfFitPredict(moved, y);
            testCase.verifyEqual([out.lengthScale, out.log10Lambda], [other.lengthScale, other.log10Lambda]);
            affine = alignest.models.rbfFitPredict(model, 2 + 3*train(:, 1) - train(:, 2));
            testCase.verifyEqual(affine.prediction, 2 + 3*test(:, 1) - test(:, 2), 'AbsTol', 1e-8);
            testCase.verifyError(@() alignest.models.rbfSetup(train, test, 0, -2), 'alignest:rbfLengthScale');
        end

        function backfitMatchesExplicitAlternationAndConditionalEdf(testCase)
            [train, test, y] = points();
            codes = (-1).^(1:numel(y)).';
            codesTest = (-1).^(1:size(test, 1)).';
            callbacks = fixedSmoothers(train, test);
            for k = 1:numel(callbacks)
                fit = callbacks{k};
                spatial = fit(y);
                out = alignest.models.spatialBackfit(fit, y, codes, codesTest);
                centered = codes-mean(codes);
                centeredTest = codesTest-mean(codes);
                beta = centered \ (y-mean(y));
                for iteration = 1:20000
                    next = centered \ (y-spatial.smoother*(y-centered*beta));
                    if norm(next-beta) < 1e-12
                        beta = next;
                        break
                    end
                    beta = next;
                end
                expected = spatial.predictionMatrix*(y-centered*beta) + centeredTest*beta;
                testCase.verifyEqual(out.prediction, expected, 'AbsTol', 1e-7);
                testCase.verifyTrue(out.backfitConverged);
                testCase.verifyEqual(out.prediction, out.predictionMatrix*y, 'AbsTol', 1e-9);
                testCase.verifyLessThan(norm(centered.'*(y-out.smoother*y)), 1e-8);
                testCase.verifyEqual(out.edf, trace(out.smoother), 'AbsTol', 1e-10);
                testCase.verifyEqual(spatial.prediction, spatial.predictionMatrix*y, 'AbsTol', 1e-9);
                testCase.verifyEqual(spatial.edf, trace(spatial.smoother), 'AbsTol', 1e-9);
            end
        end

        function backfitHandlesMissingAndRedundantFactorsAndLimit(testCase)
            [train, test, y] = points();
            callbacks = fixedSmoothers(train, test);
            fit = callbacks{1};
            plain = fit(y);
            empty = alignest.models.spatialBackfit(fit, y, zeros(numel(y), 0), zeros(size(test, 1), 0));
            testCase.verifyEqual(empty.prediction, plain.prediction);
            testCase.verifyEqual(empty.edf, plain.edf);
            testCase.verifyEqual(empty.nBackfitIterations, 0);
            codes = (-1).^(1:numel(y)).';
            codesTest = (-1).^(1:size(test, 1)).';
            single = alignest.models.spatialBackfit(fit, y, codes, codesTest);
            redundant = alignest.models.spatialBackfit(fit, y, [codes, codes, ones(numel(y), 1)], ...
                [codesTest, codesTest, ones(size(test, 1), 1)]);
            testCase.verifyEqual(redundant.prediction, single.prediction, 'AbsTol', 1e-9);
            limited = alignest.models.spatialBackfit(fit, y, codes, codesTest, maxIterations=1);
            testCase.verifyFalse(limited.backfitConverged);
            testCase.verifyEqual(limited.nBackfitIterations, 1);
        end

        function settingsAndMethodIdsRemainCompatible(testCase)
            settings = alignest.defaultSettings();
            original = alignest.buildMethodList(settings.methods);
            legacy = settings;
            legacy.methods = rmfield(legacy.methods, 'rbf');
            legacy.methods.tps = rmfield(legacy.methods.tps, 'factorModes');
            legacy.methods.kriging = rmfield(legacy.methods.kriging, {'ordinaryFactorModes', 'universalFactorModes'});
            legacy.methods.options = rmfield(legacy.methods.options, {'rbfLengthScales', 'rbfLog10Lambda'});
            testCase.verifyEqual(alignest.buildMethodList(legacy.methods), original);
            file = [tempname, '.json'];
            cleanup = onCleanup(@() delete(file));
            alignest.saveSettings(legacy, file);
            testCase.verifyEqual(alignest.loadSettings(file), settings);
            settings.methods = alignest.recommendedMethods('all');
            methods = alignest.buildMethodList(settings.methods);
            % 説明変数 X,Y・X,Y,半径 の2組 ×（GPR 12カーネル × 8扱い、TPS・RBF・通常 Kriging（5バリオグラム）・
            % Universal Kriging の質的変数なし／Backfitting、RBFe（領域 4・9）の質的変数なし／Backfitting、GAM）
            % ＋ XY5・RT4・RT5 ＋ Fringe Zernike（次数 3・4・5）
            testCase.verifyEqual(numel(methods), 2 * (12 * 8 + 2 + 2 + 10 + 10 + 2 * 2 + 1) + 3 + 3);
            testCase.verifyEqual(numel(unique(string({methods.id}))), numel(methods));
            testCase.verifyTrue(all(ismember(["RBF_gaussian_XY", "TPS_XY_backfit", ...
                "OK_linear_XY_backfit", "UK_linear_XY_backfit", "GPR_matern_nu2_XY_none", "OK_spherical_XYR_backfit", ...
                "RBF_gaussian_XYR_backfit"], ...
                string({methods.id}))));
            alignest.saveSettings(settings, file);
            testCase.verifyEqual(alignest.loadSettings(file), settings);
        end

        function newVariantsEvaluateAllFeaturesWithoutTestLeakage(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            raw = alignest.readMeasurementFile(fullfile(root, 'sample_data', 'sample_alignment.csv'));
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            unit = data.units(1);
            settings = alignest.defaultSettings();
            settings.factors.shotRowParity = true;
            settings.methods = alignest.recommendedMethods('none');
            settings.methods.featureSets = ["XY", "XYR"];
            settings.methods.rbf.enabled = true;
            settings.methods.rbf.factorModes = ["none", "backfit"];
            settings.methods.tps.enabled = true;
            settings.methods.tps.factorModes = "backfit";
            settings.methods.kriging.ordinary = true;
            settings.methods.kriging.universal = true;
            settings.methods.kriging.ordinaryFactorModes = "backfit";
            settings.methods.kriging.universalFactorModes = "backfit";
            settings.methods.kriging.variograms = ["linear", "power", "gaussian", "exponential"];
            shots = 1:3:numel(unit.shots.shotNo);
            changed = unit;
            testMarks = ~ismember(unit.marks.shotIndex, shots);
            changed.marks.measX(testMarks) = 1e6;
            changed.marks.measY(testMarks) = -1e6;
            for method = alignest.buildMethodList(settings.methods)
                out = alignest.estimateWafer(unit, shots, method, settings);
                other = alignest.estimateWafer(changed, shots, method, settings);
                testCase.verifyTrue(all(isfinite([out.estimate.X; out.estimate.Y; out.edf(:)])), method.id);
                testCase.verifyEqual(out.estimate, other.estimate, 'AbsTol', 1e-8, method.id);
                testCase.verifyGreaterThanOrEqual(out.edf, [0, 0], method.id);
                testCase.verifyLessThanOrEqual(out.edf, [numel(out.trainIndex.X), numel(out.trainIndex.Y)]+1e-6, method.id);
            end
        end

        function categoricalSignalIsRecoveredWithoutScanDirection(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            raw = alignest.readMeasurementFile(fullfile(root, 'sample_data', 'sample_alignment.csv'));
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            unit = data.units(1);
            unit.hasDirection = false;
            unit.marks.measX = 20*(unit.marks.shotRowParity == 1) + 4*unit.marks.markNo;
            unit.marks.measY = -unit.marks.measX;
            settings = alignest.defaultSettings();
            settings.factors.shotRowParity = true;
            settings.methods = alignest.recommendedMethods('none');
            settings.methods.tps.enabled = true;
            settings.methods.tps.factorModes = "backfit";
            settings.methods.rbf.enabled = true;
            settings.methods.rbf.factorModes = "backfit";
            settings.methods.kriging.ordinary = true;
            settings.methods.kriging.universal = true;
            settings.methods.kriging.ordinaryFactorModes = "backfit";
            settings.methods.kriging.universalFactorModes = "backfit";
            for method = alignest.buildMethodList(settings.methods)
                out = alignest.estimateWafer(unit, 1:3:numel(unit.shots.shotNo), method, settings);
                testCase.verifyEqual(out.estimate.X, unit.marks.measX(out.testIndex.X), 'AbsTol', 1e-3, method.id);
                testCase.verifyEqual(out.estimate.Y, unit.marks.measY(out.testIndex.Y), 'AbsTol', 1e-3, method.id);
            end
        end

        function selectedFactorsIncludingFileColumnsAreUsed(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            raw = alignest.readMeasurementFile(fullfile(root, 'sample_data', 'sample_alignment.csv'));
            raw.Chuck = "C" + string(mod(raw.shotNo, 2));  % Shot ごとに2水準の、ファイルのその他の列（学習 Shot にも両方ある）
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            unit = data.units(1);
            chuck = unit.marks.attributes(:, unit.attributeNames == "Chuck");
            unit.marks.measX = 12 * (chuck == "C1") + 3 * unit.marks.markNo;
            unit.marks.measY = -unit.marks.measX;
            settings = alignest.defaultSettings();
            settings.factors.scan = false;
            settings.factors.columns = "Chuck";
            settings.methods = alignest.recommendedMethods('none');
            settings.methods.gpr.enabled = true;
            settings.methods.gpr.factorModes = ["basis", "mixed"];
            settings.methods.tps.enabled = true;
            settings.methods.tps.factorModes = "backfit";
            settings.methods.rbf.enabled = true;
            settings.methods.rbf.factorModes = "backfit";
            settings.methods.kriging.ordinary = true;
            settings.methods.kriging.ordinaryFactorModes = "backfit";
            settings.methods.gam.enabled = true;
            shots = 1:3:numel(unit.shots.shotNo);
            for method = alignest.buildMethodList(settings.methods)
                out = alignest.estimateWafer(unit, shots, method, settings);
                testCase.verifyEqual(out.estimate.X, unit.marks.measX(out.testIndex.X), 'AbsTol', 1e-3, method.id);
            end
            % 加法カーネルでは、その他の列の項の τ がハイパーパラメータに残る
            settings.methods.gpr.factorModes = "additive";
            settings.methods.tps.enabled = false;
            settings.methods.rbf.enabled = false;
            settings.methods.kriging.ordinary = false;
            settings.methods.gam.enabled = false;
            out = alignest.estimateWafer(unit, shots, alignest.buildMethodList(settings.methods), settings);
            testCase.verifyTrue(all(isfield(out.extra, ["tau_col_Chuck_X", "tau_mark_X"])));
            testCase.verifyFalse(isfield(out.extra, "tau_scan_X"), "Scan 方向を選ばなければ使わない");
            % 列を選ばなければ、その列の効果は推定できない
            settings.factors.columns = strings(1, 0);
            settings.methods.gpr.factorModes = "basis";
            out = alignest.estimateWafer(unit, shots, alignest.buildMethodList(settings.methods), settings);
            testCase.verifyGreaterThan(sqrt(mean((out.estimate.X - unit.marks.measX(out.testIndex.X)) .^ 2)), 1);
            % データに無い列を選ぶと評価を始めない
            settings.factors.columns = "Nozzle";
            data.units = data.units(1);
            testCase.verifyError(@() alignest.runEvaluation(data, settings), 'alignest:factorColumn');
        end

        function factorsCanDifferBetweenXAndY(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            raw = alignest.readMeasurementFile(fullfile(root, 'sample_data', 'sample_alignment.csv'));
            raw.Chuck = "C" + string(mod(raw.shotNo, 2));
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            unit = data.units(1);
            chuck = unit.marks.attributes(:, unit.attributeNames == "Chuck");
            unit.marks.measX = 12 * (chuck == "C1") + 3 * unit.marks.markNo;
            unit.marks.measY = unit.marks.measX;
            settings = alignest.defaultSettings();
            settings.factors.scan = false;
            settings.factors.columns = "Chuck";
            % 別に選ばなければ Y 成分も X 成分と同じ
            testCase.verifyEqual(alignest.factorChoice(settings, "Y"), alignest.factorChoice(settings, "X"));
            settings.factors.separateY = true;
            settings.factors.y.scan = false;
            settings.factors.y.columns = strings(1, 0);
            testCase.verifyEqual(alignest.factorChoice(settings, "X").columns, "Chuck");
            testCase.verifyEmpty(alignest.factorChoice(settings, "Y").columns);
            settings.methods = alignest.recommendedMethods('none');
            settings.methods.gpr.enabled = true;
            settings.methods.gpr.factorModes = "basis";
            shots = 1:3:numel(unit.shots.shotNo);
            out = alignest.estimateWafer(unit, shots, alignest.buildMethodList(settings.methods), settings);
            testCase.verifyEqual(out.estimate.X, unit.marks.measX(out.testIndex.X), 'AbsTol', 1e-3, "X は Chuck の効果を推定");
            testCase.verifyGreaterThan(sqrt(mean((out.estimate.Y - unit.marks.measY(out.testIndex.Y)) .^ 2)), 1, ...
                "Y は Chuck を使わない");
            % 加法カーネルの質的変数の項も軸ごと
            settings.methods.gpr.factorModes = "additive";
            out = alignest.estimateWafer(unit, shots, alignest.buildMethodList(settings.methods), settings);
            testCase.verifyTrue(isfield(out.extra, "tau_col_Chuck_X"));
            testCase.verifyFalse(isfield(out.extra, "tau_col_Chuck_Y"));
            % Y 成分だけで選んだ列も、データに無ければ評価を始めない
            settings.factors.y.columns = "Nozzle";
            testCase.verifyEqual(alignest.factorColumnsUsed(settings), ["Chuck", "Nozzle"]);
            data.units = data.units(1);
            testCase.verifyError(@() alignest.runEvaluation(data, settings), 'alignest:factorColumn');
        end

        function iterationLimitIsReportedWithUsableResults(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            raw = alignest.readMeasurementFile(fullfile(root, 'sample_data', 'sample_alignment.csv'));
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            data.units = data.units(1);
            settings = alignest.defaultSettings();
            settings.sampling.method = "manual";
            settings.sampling.manualPlans = "1 4 7 10 13 16 19 22 25 28";
            settings.methods = alignest.recommendedMethods('none');
            settings.methods.tps.enabled = true;
            settings.methods.tps.factorModes = "backfit";
            settings.methods.options.backfitMaxIterations = 1;
            result = alignest.runEvaluation(data, settings);
            testCase.verifyFalse(result.table.converged);
            testCase.verifyEqual(result.table.note, "");
            testCase.verifyTrue(isfinite(result.table.RMSE_XY));
            testCase.verifyTrue(any(contains(result.log, "収束しませんでした")));
            testCase.verifyTrue(contains(result.table.hyperparameters, "backfitIterations_X=1"));
        end
    end
end

function [train, test, y] = points()
[x, yCoordinate] = meshgrid(linspace(-0.8, 0.8, 5), linspace(-0.7, 0.7, 4));
train = [x(:), yCoordinate(:)];
test = train(1:3:end, :) + [0.03, -0.04];
y = sin(3*train(:, 1)) + train(:, 2).^2 + 0.4*(-1).^(1:size(train, 1)).';
end

function callbacks = fixedSmoothers(train, test)
tps = alignest.models.tpsSetup(train, test, 0);
ordinary = alignest.models.krigingSetup(train, test, 'ordinary', 'exponential');
universal = alignest.models.krigingSetup(train, test, 'universal', 'exponential');
callbacks = {@(y) alignest.models.tpsFitPredict(tps, y, returnSmoother=true), ...
    @(y) alignest.models.krigingFitPredict(ordinary, y, fixedParams=[1, 2, 0.2], returnSmoother=true), ...
    @(y) alignest.models.krigingFitPredict(universal, y, fixedParams=[1, 2, 0.2], returnSmoother=true)};
end
