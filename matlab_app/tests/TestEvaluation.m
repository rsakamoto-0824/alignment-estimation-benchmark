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
            settings.methods.featureSets = ["XY", "XYRT"];
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
            settings.sampling.manualPlans = ["1 2 3"; "4 5 6"];
            settings.methods.featureSets = ["XY", "XYR"];
            alignest.saveSettings(settings, settingsFile);
            loaded = alignest.loadSettings(settingsFile);
            testCase.verifyEqual(loaded, settings);
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
