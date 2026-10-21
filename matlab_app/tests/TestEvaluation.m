classdef TestEvaluation < matlab.unittest.TestCase
    %TESTEVALUATION 学習 Shot の選び方、評価の実行、集計・書き出し・設定ファイルを確かめる（サンプルデータを使う）。

    properties
        Data
    end

    methods (TestClassSetup)
        function loadSample(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            addpath(root);
            raw = alignest.readMeasurementFile(fullfile(root, 'sample_data', 'sample_alignment.xlsx'));
            testCase.Data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
        end
    end

    methods (Test)
        function rowParityRunsInEveryFactorModeAndGam(testCase)
            settings = alignest.defaultSettings();
            settings.factors.shotRowParity = true;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.gpr.enabled = true;
            settings.methods.gpr.factorModes = alignest.models.gprFactorModes();
            settings.methods.gam.enabled = true;
            unit = testCase.Data.units(1);
            unit.hasDirection = false;
            shots = 1:3:numel(unit.shots.shotNo);
            for method = alignest.buildMethodList(settings.methods)
                out = alignest.estimateWafer(unit, shots, method, settings);
                testCase.verifyTrue(all(isfinite([out.estimate.X; out.estimate.Y])), method.id);
                if startsWith(method.factorMode, "additive")
                    testCase.verifyTrue(isfield(out.extra, "tau_row_X"));
                end
            end
            % Scan と行の奇偶が同じでも固定効果・Backfitting・GAMを推定できる
            unit.hasDirection = true;
            unit.marks.direction = unit.marks.shotRowParity;
            settings.methods.gpr.factorModes = ["basis_int", "backfit"];
            for method = alignest.buildMethodList(settings.methods)
                out = alignest.estimateWafer(unit, shots, method, settings);
                testCase.verifyTrue(all(isfinite([out.estimate.X; out.estimate.Y])), method.id);
            end
        end

        function parityEffectChangesPredictionAndNoneIgnoresIt(testCase)
            settings = alignest.defaultSettings();
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.gpr.enabled = true;
            settings.methods.gpr.factorModes = ["none", "basis"];
            settings.methods.gam.enabled = true;
            unit = testCase.Data.units(1);
            unit.hasDirection = false;
            unit.marks.measX = 20 * (unit.marks.shotRowParity == 1);
            unit.marks.measY = -unit.marks.measX;
            shots = 1:3:numel(unit.shots.shotNo);
            for method = alignest.buildMethodList(settings.methods)
                settings.factors.shotRowParity = false;
                without = alignest.estimateWafer(unit, shots, method, settings);
                settings.factors.shotRowParity = true;
                with = alignest.estimateWafer(unit, shots, method, settings);
                if method.factorMode == "none" && method.family == "GPR"
                    testCase.verifyEqual(with.estimate.X, without.estimate.X, 'AbsTol', 1e-10);
                else
                    actual = unit.marks.measX(with.testIndex.X);
                    testCase.verifyLessThan(sqrt(mean((with.estimate.X - actual).^2)), 1e-3);
                    testCase.verifyGreaterThan(norm(with.estimate.X - without.estimate.X), 1);
                end
            end
        end

        function planSpecsFollowTheMethod(testCase)
            sampling = alignest.defaultSettings().sampling;
            sampling.nShots = [20, 10];
            specs = alignest.buildPlanSpecs(sampling);
            testCase.verifyEqual(string({specs.label}), ["I最適 10 Shot", "I最適 20 Shot"]);
            sampling.method = "random";
            sampling.randomRepeats = 3;
            testCase.verifyEqual(numel(alignest.buildPlanSpecs(sampling)), 6);
            sampling.method = "manual";
            sampling.manualPlans = ["1, 5 9", "", "2 4 6 8"];
            specs = alignest.buildPlanSpecs(sampling);
            testCase.verifyEqual([specs.nShots], [3, 4]);
            sampling.manualPlans = "1 x 3";
            testCase.verifyError(@() alignest.buildPlanSpecs(sampling), 'alignest:manualPlan');
        end

        function randomPlansAreReproducibleAndMeetConstraints(testCase)
            sampling = alignest.defaultSettings().sampling;
            unit = testCase.Data.units(1);
            spec = struct("type", "random", "nShots", 15, "repeat", 2, "label", "", "group", "", "shotNos", []);
            first = alignest.planTrainingShots(unit, spec, sampling, 150);
            second = alignest.planTrainingShots(unit, spec, sampling, 150);
            testCase.verifyEqual(first.shotIndex, second.shotIndex);
            testCase.verifyEqual(first.violation, 0);
            testCase.verifyEqual(first.nShots, 15);
            spec.repeat = 3;
            third = alignest.planTrainingShots(unit, spec, sampling, 150);
            testCase.verifyNotEqual(third.shotIndex, first.shotIndex);
        end

        function manualPlanReportsMissingShots(testCase)
            sampling = alignest.defaultSettings().sampling;
            spec = struct("type", "manual", "nShots", 3, "repeat", 1, "label", "手動1", "group", "手動1", ...
                "shotNos", [1, 50, 999]);
            plan = alignest.planTrainingShots(testCase.Data.units(1), spec, sampling, 150);
            testCase.verifyTrue(plan.ok);
            testCase.verifyEqual(plan.shotNos(:).', [1, 50]);
            testCase.verifyTrue(contains(plan.message, "999"));
        end

        function tooManyTrainingShotsIsRecorded(testCase)
            settings = alignest.defaultSettings();
            settings.sampling.nShots = 99;
            settings.methods = onlyPolynomial();
            data = testCase.Data;
            data.units = data.units(1);
            results = alignest.runEvaluation(data, settings);
            testCase.verifyTrue(all(results.table.note ~= ""));
            testCase.verifyTrue(all(isnan(results.table.RMSE_XY)));
        end

        function everyFamilyRunsWithoutError(testCase)
            settings = alignest.defaultSettings();
            settings.sampling.nShots = 12;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.featureSets = ["XY", "XYR"];
            settings.methods.gpr.enabled = true;
            settings.methods.gpr.kernels = ["ardrationalquadratic", "exponential"];
            settings.methods.gpr.factorModes = alignest.models.gprFactorModes();
            settings.methods.tps.enabled = true;
            settings.methods.kriging.ordinary = true;
            settings.methods.kriging.universal = true;
            settings.methods.kriging.variograms = ["linear", "gaussian", "power", "exponential"];
            settings.methods.gam.enabled = true;
            settings.methods.polynomial.enabled = true;
            settings.methods.rt.enabled = true;
            settings.methods.rt.orders = [4, 5];
            data = testCase.Data;
            data.units = data.units(1);
            results = alignest.runEvaluation(data, settings);
            testCase.verifyEqual(height(results.table), 2 * (2 * 8 + 1 + 8 + 1) + 3);
            failed = results.table(results.table.note ~= "", ["methodId", "note"]);
            testCase.verifyEmpty(failed, "推定できなかった手法がある");
            testCase.verifyTrue(all(isfinite(results.table.RMSE_XY)));
            testCase.verifyTrue(all(results.table.RMSE_XY < 20), "誤差が大きすぎる手法がある");
        end

        function removingLinearDoesNotChangeModelsWithLinearTerms(testCase)
            % XY 多項式と RT モデルは1次の項を含むので、前処理で1次を除いても推定値は同じ
            settings = alignest.defaultSettings();
            unit = testCase.Data.units(2);
            spec = struct("type", "ioptimal", "nShots", 20, "repeat", 1, "label", "", "group", "", "shotNos", []);
            plan = alignest.planTrainingShots(unit, spec, settings.sampling, 150);
            for method = alignest.buildMethodList(onlyPolynomial())
                plain = alignest.estimateWafer(unit, plan.shotIndex, method, settings);
                settings.evaluation.removeLinear = true;
                shifted = alignest.estimateWafer(unit, plan.shotIndex, method, settings);
                settings.evaluation.removeLinear = false;
                testCase.verifyEqual(shifted.estimate.X, plain.estimate.X, 'AbsTol', 1e-8, method.id);
                testCase.verifyEqual(shifted.estimate.Y, plain.estimate.Y, 'AbsTol', 1e-8, method.id);
            end
        end

        function dataWithoutDirectionStillRuns(testCase)
            data = testCase.Data;
            data.units = data.units(1);
            data.units.hasDirection = false;
            settings = alignest.defaultSettings();
            settings.sampling.nShots = 15;
            results = alignest.runEvaluation(data, settings);
            testCase.verifyTrue(all(results.table.note == ""));
            additive = results.table(results.table.methodId == "GPR_matern52_XYR_additive", :);
            testCase.verifyFalse(contains(additive.hyperparameters, "tau_scan"), "Scan 方向が無いのに τ_scan がある");
            testCase.verifyTrue(contains(additive.hyperparameters, "tau_mark"));
        end

        function cancelKeepsPartialResults(testCase)
            settings = alignest.defaultSettings();
            settings.sampling.nShots = 10;
            results = alignest.runEvaluation(testCase.Data, settings, @(done, ~, ~) done < 3);
            testCase.verifyTrue(results.cancelled);
            testCase.verifyEqual(height(results.table), 3);
        end

        function summaryExportAndSettingsRoundTrip(testCase)
            settings = alignest.defaultSettings();
            settings.sampling.nShots = [10, 20];
            data = testCase.Data;
            data.units = data.units(1:3);
            results = alignest.runEvaluation(data, settings);
            summary = alignest.summarizeResults(results, "RMSE_XY", "mean");
            testCase.verifyEqual(size(summary.values), [9, 2]);
            manual = mean(results.table.RMSE_XY(results.table.methodIndex == 1 & results.table.group == "20 Shot"));
            testCase.verifyEqual(summary.values(1, 2), manual, 'AbsTol', 1e-12);
            comparison = alignest.pairedComparison(results, "GPR_matern52_XYR_basis", "RMSE_XY");
            testCase.verifyEqual(height(comparison), 8 * 2);
            testCase.verifyFalse(any(contains(comparison.method, "同時推定")));
            file = [tempname, '.xlsx'];
            cleanup = onCleanup(@() deleteIfExists(file));
            alignest.exportResults(results, file, "sample.xlsx");
            sheets = sheetnames(file);
            testCase.verifyTrue(all(ismember(["説明", "集計_RMSE_XY", "Waferごと", "学習Shot", "設定"], sheets)));
            exported = readtable(file, 'Sheet', '集計_RMSE_XY', 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(exported.("20 Shot"), summary.values(:, 2), 'AbsTol', 1e-9);
            settingsFile = [tempname, '.json'];
            cleanup2 = onCleanup(@() deleteIfExists(settingsFile));
            settings.sampling = alignest.syncShotCounts(settings.sampling);  % 開始・終了・刻みを並びに合わせる
            testCase.verifyEqual([settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep], ...
                [10, 20, 10]);
            settings.sampling.manualPlans = ["1 2 3"; "4 5 6"];
            settings.methods.featureSets = ["XY", "XYR"];
            settings.data.coordinateUnits.Xmm = "um";
            settings.factors.shotRowParity = true;
            alignest.saveSettings(settings, settingsFile);
            loaded = alignest.loadSettings(settingsFile);
            testCase.verifyEqual(loaded, settings);
            legacy = rmfield(settings, "factors");
            legacy.data = rmfield(legacy.data, "coordinateUnits");
            alignest.saveSettings(legacy, settingsFile);
            loaded = alignest.loadSettings(settingsFile);
            testCase.verifyEqual(loaded.data.coordinateUnits, alignest.coordinateUnits());
            testCase.verifyFalse(loaded.factors.shotRowParity);
            % 開始・終了・刻みの無い以前の設定は、Shot 数の並びから決める（等間隔でなければ間が加わる）
            legacy.sampling = rmfield(legacy.sampling, ["nShotsStart", "nShotsEnd", "nShotsStep"]);
            legacy.sampling.nShots = [10, 20, 50];
            legacy.data = rmfield(legacy.data, ["directionRule", "invertDirection"]);
            legacy.evaluation = rmfield(legacy.evaluation, "recordTiming");
            alignest.saveSettings(legacy, settingsFile);
            loaded = alignest.loadSettings(settingsFile);
            testCase.verifyEqual(loaded.sampling.nShots, 10:10:50);
            testCase.verifyEqual([loaded.sampling.nShotsStart, loaded.sampling.nShotsEnd, loaded.sampling.nShotsStep], ...
                [10, 50, 10]);
            testCase.verifyEqual(loaded.data.directionRule, "none");
            testCase.verifyFalse(loaded.evaluation.recordTiming);
        end

        function shotCountSweepBuildsTheList(testCase)
            testCase.verifyEqual(alignest.shotCountList(10, 40, 5), 10:5:40);
            testCase.verifyEqual(alignest.shotCountList(10, 42, 5), 10:5:40, "終了が刻みに乗らなければ手前まで");
            testCase.verifyEqual(alignest.shotCountList(12, 12, 3), 12);
            testCase.verifyError(@() alignest.shotCountList(20, 10, 5), 'alignest:nShots');
            testCase.verifyError(@() alignest.shotCountList(10, 20, 0), 'alignest:nShots');
            testCase.verifyError(@() alignest.shotCountList(10.5, 20, 1), 'alignest:nShots');
            testCase.verifyError(@() alignest.shotCountList(1, 1000, 1), 'alignest:nShots');
            settings = alignest.defaultSettings();
            testCase.verifyEqual(settings.sampling.nShots, [10, 15, 20, 25, 30, 35, 40]);
            sampling = settings.sampling;
            sampling.nShots = 30;
            sampling = alignest.syncShotCounts(sampling);
            testCase.verifyEqual([sampling.nShotsStart, sampling.nShotsEnd, sampling.nShotsStep], [30, 30, 1]);
        end

        function designCriteriaFollowTheDefinitions(testCase)
            % 正規直交な基底をすべて使うと I 基準 = 項数、D 基準 = 1
            [basis, ~] = qr(linspace(-1, 1, 40).' .^ (0:5), 0);
            blocks = mat2cell(basis, repmat(4, 10, 1), 6);
            [iValue, dValue] = alignest.designCriteria(blocks);
            testCase.verifyEqual([iValue, dValue], [6, 1], 'AbsTol', 1e-9);
            [iValue, dValue] = alignest.designCriteria(blocks(1:5));
            information = vertcat(blocks{1:5}).' * vertcat(blocks{1:5});
            testCase.verifyEqual(iValue, trace(inv(information)), 'RelTol', 1e-9);
            testCase.verifyEqual(dValue, det(information) ^ (-1 / 6), 'RelTol', 1e-9);
            [iValue, dValue] = alignest.designCriteria(blocks(1));  % 4 点で 6 項は求められない
            testCase.verifyTrue(isnan(iValue) && isnan(dValue));
            % I 最適の計画では、交換法で求めた tr(M⁻¹) と同じ。ランダム・手動の計画でも求める
            sampling = alignest.defaultSettings().sampling;
            unit = testCase.Data.units(1);
            spec = struct("type", "ioptimal", "nShots", 15, "repeat", 1, "label", "", "group", "", "shotNos", []);
            plan = alignest.planTrainingShots(unit, spec, sampling, 150);
            testCase.verifyEqual(plan.criterionI, plan.criterion, 'RelTol', 1e-6);
            spec.type = "random";
            random = alignest.planTrainingShots(unit, spec, sampling, 150);
            testCase.verifyGreaterThan(random.criterionI, plan.criterionI, "I 最適の方が I 基準が小さい");
            testCase.verifyTrue(isfinite(random.criterionD) && random.criterionD > 1);
            spec = struct("type", "manual", "nShots", 3, "repeat", 1, "label", "手動1", "group", "手動1", "shotNos", 1:3);
            manual = alignest.planTrainingShots(unit, spec, sampling, 150);
            testCase.verifyTrue(manual.ok);
            testCase.verifyTrue(isnan(manual.criterionI), "12 点では 21 項の基準モデルを決められない");
        end

        function worstAndP95AreTakenOnTheBadSide(testCase)
            settings = alignest.defaultSettings();
            settings.sampling.method = "random";
            settings.sampling.nShots = 15;
            settings.sampling.randomRepeats = 2;
            settings.methods = onlyPolynomial();
            settings.evaluation.recordTiming = true;
            results = alignest.runEvaluation(testCase.Data, settings);
            testCase.verifyTrue(results.timingRecorded);
            for metric = ["RMSE_XY", "R2_XY", "seconds"]
                perUnit = alignest.perUnitValues(results, metric);
                values = perUnit{1, 1};
                lowerIsBetter = metric ~= "R2_XY";
                worst = alignest.summarizeResults(results, metric, "worst");
                p95 = alignest.summarizeResults(results, metric, "p95");
                if lowerIsBetter
                    testCase.verifyEqual(worst.values(1, 1), max(values), metric);
                    testCase.verifyEqual(p95.values(1, 1), alignest.stats.percentile(values, 95), metric);
                else
                    testCase.verifyEqual(worst.values(1, 1), min(values), metric);
                    testCase.verifyEqual(p95.values(1, 1), alignest.stats.percentile(values, 5), metric);
                end
                testCase.verifyLessThanOrEqual(abs(p95.values(1, 1) - median(values)), abs(worst.values(1, 1) - median(values)));
            end
            testCase.verifyError(@() alignest.summarizeResults(results, "RMSE_XY", "max"), 'alignest:statistic');
            file = [tempname, '.xlsx'];
            cleanup = onCleanup(@() deleteIfExists(file));
            alignest.exportResults(results, file, "sample.xlsx");
            timing = readtable(file, 'Sheet', '処理時間', 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(height(timing), numel(results.methods));
            testCase.verifyEqual(timing.("回数"), repmat(numel(testCase.Data.units) * 2, height(timing), 1));
            plans = readtable(file, 'Sheet', '学習Shot', 'VariableNamingRule', 'preserve');
            testCase.verifyTrue(all(isfinite(plans.("D基準det(M)^(-1/p)"))));
        end

        function estimatesMatchTheMetricsAndReuseTheCache(testCase)
            settings = alignest.defaultSettings();
            settings.sampling.nShots = [10, 20];
            settings.methods = onlyPolynomial();
            data = testCase.Data;
            data.units = data.units(1:2);
            results = alignest.runEvaluation(data, settings);
            cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
            selection = struct("methodIndex", 1:numel(results.methods), "groups", results.groups, "unitIndex", 1:2);
            estimates = alignest.collectEstimates(data, results, selection, cache=cache);
            testCase.verifyEqual(cache.Count, uint64(height(results.table)));
            for k = 1:height(results.table)
                row = results.table(k, :);
                points = estimates(estimates.Wafer == row.Wafer & estimates.group == row.group & ...
                    estimates.methodId == row.methodId, :);
                residuals = [points.residualX(isfinite(points.residualX)); points.residualY(isfinite(points.residualY))];
                testCase.verifyEqual(sqrt(mean(residuals .^ 2)), row.RMSE_XY, 'AbsTol', 1e-10);
                testCase.verifyEqual(nnz(isfinite(points.residualX)), row.nTest_X);
            end
            again = alignest.collectEstimates(data, results, selection, cache=cache);
            testCase.verifyEqual(again, estimates);
            testCase.verifyError(@() alignest.collectEstimates(data, results, selection, maxRows=100), 'alignest:tooManyRows');
            analysis = alignest.residualAnalysis(estimates);
            testCase.verifyEqual(height(analysis.normality), numel(results.methods) * numel(results.groups) * 2);
            testCase.verifyTrue(all(ismember(["Scan 方向", "Mark 番号", "Shot 行の奇偶"], analysis.anova.factor)));
        end
    end
end

function methods = onlyPolynomial()
methods = alignest.recommendedMethods("none");
methods.polynomial.enabled = true;
methods.rt.enabled = true;
methods.rt.orders = [4, 5];
end

function deleteIfExists(file)
if isfile(file)
    delete(file);
end
end
