classdef TestGroupsScatterPriority < matlab.unittest.TestCase
    %TESTGROUPSSCATTERPRIORITY グループ平均の場と共分散、エラーバーのばらつき、散布図の相関、Shot の優先順のファイルを確かめる。

    properties
        Data
    end

    methods (TestClassSetup)
        function loadSample(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            addpath(root);
            raw = alignest.readMeasurementFile(fullfile(root, 'sample_data', 'sample_alignment.csv'));
            testCase.Data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
        end
    end

    methods (Test)
        function groupOptionsFollowLotEquipmentAndOperation(testCase)
            options = alignest.groupOptions(testCase.Data.units);
            labels = [options.label];
            testCase.verifyEqual(labels(1:5), string({testCase.Data.units.label}));
            testCase.verifyEqual(labels(6:end), ["平均：全 Wafer（5 枚）", "平均：EqpId = EXP01（3 枚）", ...
                "平均：EqpId = EXP02（2 枚）"], "LotID・Operation は1種類なので値ごとの平均を出さない");
            testCase.verifyEqual(options(8).unitIndex, [4, 5]);
            units = testCase.Data.units;
            [units(4:5).lotId] = deal("LOT2");
            labels = [alignest.groupOptions(units).label];
            testCase.verifyTrue(any(labels == "平均：LotID = LOT2（2 枚）"));
        end

        function averagesAndCovarianceAreComputedPerPosition(testCase)
            points = {[0, 0; 10, 0; 20, 0], [10, 0; 0, 0; 20, 0]};
            values = {[1, 2; 3, 4; 5, NaN], [5, 6; -1, 0; 7, 8]};
            average = alignest.averageFields(points, values);
            testCase.verifyEqual(average.points, [0, 0; 10, 0; 20, 0]);
            testCase.verifyEqual(average.mean, [0, 1; 4, 5; 6, 8], 'AbsTol', 1e-12);
            testCase.verifyEqual(average.count, [2, 2; 2, 2; 2, 1]);
            % 2枚の共分散：(差)²/2、X と Y の積も同じ
            testCase.verifyEqual(average.covariance(1, :), [2, 2, 2], 'AbsTol', 1e-12);
            testCase.verifyEqual(average.covariance(2, :), [2, 2, 2], 'AbsTol', 1e-12);
            testCase.verifyTrue(all(isnan(average.covariance(3, :))), "X・Y がそろった Wafer が1枚だけ");
        end

        function errorBarSpreadIsTheWaferStandardDeviation(testCase)
            settings = alignest.defaultSettings();
            settings.sampling.nShots = [10, 20];
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.methods.polynomial.order = 3;
            results = alignest.runEvaluation(testCase.Data, settings);
            [deviation, count] = alignest.waferSpread(results, "RMSE_XY");
            values = results.table.RMSE_XY(results.table.group == "20 Shot");
            testCase.verifyEqual(deviation(1, 2), std(values), 'AbsTol', 1e-12);
            testCase.verifyEqual(count, [5, 5]);
        end

        function scatterSummaryMeasuresTheCorrelation(testCase)
            measured = (1:10).';
            summary = alignest.scatterSummary(measured, 2 * measured + 1);
            testCase.verifyEqual([summary.r, summary.r2, summary.slope, summary.intercept], [1, 1, 2, 1], 'AbsTol', 1e-12);
            testCase.verifyEqual(summary.rmse, sqrt(mean((measured + 1) .^ 2)), 'AbsTol', 1e-12);
            summary = alignest.scatterSummary([1; NaN; 3; 2], [-1; 5; -3; -2]);
            testCase.verifyEqual(summary.n, 3);
            testCase.verifyEqual(summary.r, -1, 'AbsTol', 1e-12);
            testCase.verifyTrue(isnan(alignest.scatterSummary(1, 1).r));
        end

        function priorityFileIsReadByColumnNames(testCase)
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's'));
            file = fullfile(folder, 'priority.csv');
            writetable(table([5; 10; 3; 7; 1], [1; 0; NaN; 2; 1], 'VariableNames', ["メモ欄ShotNo", "Priority"]), file);
            priority = alignest.readShotPriority(file);
            testCase.verifyEqual(priority.shotNo, [5, 10, 3, 7, 1]);
            testCase.verifyEqual(priority.level, [1, 0, NaN, 2, 1]);
            testCase.verifyEqual(priority.file, "priority.csv");
            file = fullfile(folder, 'japanese.csv');
            writetable(table(["a"; "b"], [0; 1], [4; 8], 'VariableNames', ["備考", "優先度", "Shot"]), file);
            priority = alignest.readShotPriority(file);
            testCase.verifyEqual([priority.shotNo; priority.level], [4, 8; 0, 1]);
            file = fullfile(folder, 'only.csv');
            writetable(table([3; 1], 'VariableNames', "No"), file);
            priority = alignest.readShotPriority(file);
            testCase.verifyEqual(priority.shotNo, [3, 1]);
            testCase.verifyTrue(all(isnan(priority.level)));
            file = fullfile(folder, 'bad.csv');
            writetable(table([3; 1.5], [0; 1], 'VariableNames', ["Shot", "Priority"]), file);
            testCase.verifyError(@() alignest.readShotPriority(file), 'alignest:shotPriority');
        end

        function priorityOrderSelectsTrainingShots(testCase)
            unit = testCase.Data.units(1);
            sampling = alignest.defaultSettings().sampling;
            sampling.method = "file";
            sampling.priorityShots = [5, 10, 3, 999, 7, 1, 20, 10, 3];
            sampling.priorityLevels = [1, 0, NaN, NaN, 2, 1, NaN, NaN, NaN];
            sampling.nShots = [1, 4, 6];
            specs = alignest.buildPlanSpecs(sampling);
            testCase.verifyEqual(string({specs.label}), ["優先順 1 Shot", "優先順 4 Shot", "優先順 6 Shot"]);
            plans = arrayfun(@(spec) alignest.planTrainingShots(unit, spec, sampling, 150), specs);
            % 必ず計測（5・1）＋ 行の順（3、999 は無いので飛ばす、7、20）。10 は計測しない（0）が優先
            testCase.verifyEqual(sort(plans(2).shotNos(:)).', [1, 3, 5, 7]);
            testCase.verifyTrue(contains(plans(2).message, "999"));
            testCase.verifyEqual(sort(plans(1).shotNos(:)).', [1, 5], "必ず計測する Shot は学習 Shot 数より多くても使う");
            testCase.verifyTrue(contains(plans(1).message, "必ず計測する Shot が 2 個"));
            testCase.verifyEqual(sort(plans(3).shotNos(:)).', [1, 3, 5, 7, 20]);
            testCase.verifyTrue(contains(plans(3).message, "足りません"));
            testCase.verifyFalse(any(plans(3).shotNos == 10));
            testCase.verifyTrue(all([plans.ok]));
            sampling.priorityShots = zeros(1, 0);
            testCase.verifyError(@() alignest.buildPlanSpecs(sampling), 'alignest:shotPriority');
        end
    end
end
