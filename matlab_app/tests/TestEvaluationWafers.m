classdef TestEvaluationWafers < matlab.unittest.TestCase
    %TESTEVALUATIONWAFERS 評価に使う Wafer（すべて・枚数・割合、先頭から・ランダム）と、条件の追加で Wafer を足すこと。

    properties
        Data
        Root
    end

    methods (TestClassSetup)
        function loadSample(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.Root);
            raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            testCase.Data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
        end
    end

    methods (Test)
        function selectsWafersByCountOrRate(testCase)
            % 枚数・割合で決める。ランダムは乱数の種で決まり、枚数を増やしても前の Wafer を含む
            evaluation = struct("waferSelection", "all");
            testCase.verifyEqual(alignest.evaluationUnitIndex(5, evaluation), 1:5);
            evaluation = struct("waferSelection", "count", "waferCount", 3, "waferOrder", "first");
            [index, text] = alignest.evaluationUnitIndex(5, evaluation);
            testCase.verifyEqual(index, 1:3);
            testCase.verifyEqual(text, "5 枚中 3 枚（先頭から）");
            evaluation.waferCount = 10;
            testCase.verifyEqual(alignest.evaluationUnitIndex(5, evaluation), 1:5, "読み込んだ枚数より多ければすべて");
            evaluation = struct("waferSelection", "rate", "waferRate", 40, "waferOrder", "first");
            testCase.verifyEqual(alignest.evaluationUnitIndex(5, evaluation), 1:2, "5 × 40% = 2 枚");
            evaluation.waferRate = 1;
            testCase.verifyEqual(alignest.evaluationUnitIndex(5, evaluation), 1, "1 枚以上");
            random = struct("waferSelection", "count", "waferCount", 4, "waferOrder", "random");
            four = alignest.evaluationUnitIndex(20, random, 7);
            random.waferCount = 8;
            eight = alignest.evaluationUnitIndex(20, random, 7);
            testCase.verifyEqual(numel(four), 4);
            testCase.verifyTrue(all(ismember(four, eight)), "枚数を増やしても前の Wafer を含む");
            testCase.verifyEqual(alignest.evaluationUnitIndex(20, random, 7), eight, "同じ種なら同じ Wafer");
            testCase.verifyTrue(issorted(eight));
            testCase.verifyError(@() alignest.evaluationUnitIndex(5, struct("waferSelection", "count", "waferCount", 0)), ...
                'alignest:waferSelection');
            testCase.verifyError(@() alignest.evaluationUnitIndex(5, struct("waferSelection", "rate", "waferRate", 120)), ...
                'alignest:waferSelection');
        end

        function evaluatesOnlySelectedWafersAndAddsMore(testCase)
            % 2 枚だけ評価し、条件の追加で 4 枚に増やす（足した Wafer だけ計算し、最初から 4 枚で評価したのと同じ）
            settings = smallSettings();
            settings.evaluation.waferSelection = "count";
            settings.evaluation.waferCount = 2;
            first = alignest.runEvaluation(testCase.Data, settings);
            testCase.verifyEqual(unique(first.table.unitIndex).', [1, 2]);
            testCase.verifyEqual(first.evaluatedUnits, [1, 2]);
            testCase.verifyEqual(alignest.evaluatedUnits(first), [1, 2]);
            testCase.verifyEqual(first.waferSelectionText, "5 枚中 2 枚（先頭から）");
            testCase.verifyEqual(numel(first.unitLabels), 5, "Wafer の名前はすべて（行の unitIndex の番号）");
            [~, detail] = alignest.estimateRunSeconds(testCase.Data.units, settings);
            testCase.verifyEqual(detail.nRuns, height(first.table), "時間の目安も評価する Wafer だけ");
            more = settings;
            more.evaluation.waferCount = 4;
            testCase.verifyEmpty(alignest.extensionConflicts(settings, more), "Wafer の枚数は足してよい");
            extended = alignest.runEvaluation(testCase.Data, more, [], first, "extend");
            full = alignest.runEvaluation(testCase.Data, more);
            key = @(results) results.table.Wafer + "|" + results.table.plan + "|" + results.table.methodId;
            testCase.verifyEqual(key(extended), key(full));
            testCase.verifyEqual(extended.table.RMSE_XY, full.table.RMSE_XY, 'AbsTol', 1e-12);
            testCase.verifyEqual(extended.evaluatedUnits, 1:4);
            old = ismember(key(extended), key(first));
            testCase.verifyEqual(extended.table.seconds(old), first.table.seconds, "評価済みの行はそのまま使う");
            testCase.verifyTrue(contains(extended.additions(end), "Wafer 2（"));
            summary = alignest.summarizeResults(extended, "RMSE_XY", "mean");
            testCase.verifyEqual(summary.counts(1, 1), 4, "4 枚で集計");
            % 減らす・足すものが無いときは追加できない
            fewer = more;
            fewer.evaluation.waferCount = 3;
            testCase.verifyError(@() alignest.runEvaluation(testCase.Data, fewer, [], extended, "extend"), 'alignest:extend');
            testCase.verifyError(@() alignest.runEvaluation(testCase.Data, more, [], extended, "extend"), 'alignest:extend');
        end

        function screenSelectsWafers(testCase)
            % 画面：「評価に使う Wafer」の欄、時間の目安、結果一覧・マップの Wafer の選択肢、条件の追加で Wafer を足す
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual(string({c.waferCount.Enable, c.waferRate.Enable, c.waferOrder.Enable}), ...
                ["off", "off", "off"], "すべてのときは使わない");
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.sampling.nShots = 20;
            settings.sampling.exchangeStarts = 2;
            app.setSettings(settings);
            c.waferSelection.Value = 'rate';
            c.waferSelection.ValueChangedFcn([], []);
            c.waferRate.Value = 40;
            c.waferRate.ValueChangedFcn([], []);
            testCase.verifyEqual(app.Settings.evaluation.waferSelection, "rate");
            testCase.verifyEqual(string({c.waferCount.Enable, c.waferRate.Enable, c.waferOrder.Enable}), ["off", "on", "on"]);
            testCase.verifyTrue(contains(string(c.waferSelectionInfo.Text), "5 枚中 2 枚（先頭から）"));
            testCase.verifyTrue(contains(string(c.countLabel.Text), "Wafer 2 枚（5 枚中 2 枚（先頭から））"));
            results = app.runEvaluationNow(false);
            testCase.verifyEqual(results.evaluatedUnits, [1, 2]);
            testCase.verifyEqual(c.analysisWafer.ItemsData, [0, 1, 2], "評価した Wafer だけを選べる");
            options = c.mapWafer.UserData;
            testCase.verifyEqual([options(1:2).unitIndex], [1, 2]);
            testCase.verifyTrue(contains(options(3).label, "全 Wafer（2 枚）"));
            % 条件の追加で Wafer を足す
            c.waferRate.Value = 80;
            c.waferRate.ValueChangedFcn([], []);
            extended = app.extendEvaluation(false);
            testCase.verifyEqual(extended.evaluatedUnits, 1:4);
            testCase.verifyEqual(numel(unique(extended.table.unitIndex)), 4);
            testCase.verifyEqual(c.analysisWafer.ItemsData, 0:4);
        end
    end
end

function settings = smallSettings()
% 速く終わる評価の設定（XY 5次多項式、学習 Shot 10・20）
settings = alignest.defaultSettings();
settings.methods = alignest.recommendedMethods("none");
settings.methods.polynomial.enabled = true;
settings.sampling.nShots = [10, 20];
settings.sampling.nShotsStart = 10;
settings.sampling.nShotsEnd = 20;
settings.sampling.nShotsStep = 10;
settings.sampling.exchangeStarts = 2;
end
