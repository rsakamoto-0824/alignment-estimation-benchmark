classdef TestAppWorkflow < matlab.unittest.TestCase
    %TESTAPPWORKFLOW 画面を出さずにアプリを作り、読み込み → 設定 → 実行 → 結果 → マップ → 書き出し の流れを確かめる。

    properties
        App
        Root
    end

    methods (TestMethodSetup)
        function createApp(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.Root);
            testCase.App = AlignmentEstimationApp(false);
            testCase.addTeardown(@() delete(testCase.App));
        end
    end

    methods (Test)
        function recordFiltersPersistInvalidateAndExport(testCase)
            app = testCase.App;
            raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            raw.StsX(:) = 0;
            raw.StsY(:) = 0;
            raw.measX(1) = 0;
            raw.measY(1) = 0;
            raw.StsX(2) = -1;
            raw.StsY(3) = -1;
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's'));
            file = fullfile(folder, 'input.csv');
            writetable(raw, file);
            app.loadFile(file);
            app.applyMapping();
            testCase.verifyEqual(app.Data.summary.nRecordsExcluded, 0);
            app.Controls.excludeZeroMeasurements.Value = true;
            app.Controls.excludeZeroMeasurements.ValueChangedFcn([], []);
            testCase.verifyEmpty(app.Data);
            testCase.verifyTrue(app.Settings.data.excludeZeroMeasurements);
            app.applyMapping();
            testCase.verifyEqual(app.Data.summary.nRecordsExcluded, 1);
            app.Controls.excludeUnmeasuredRecords.Value = true;
            % コールバックを経ない変更でも、以前のデータでは評価できない
            testCase.verifyError(@() app.runEvaluationNow(false), 'alignest:noData');
            app.applyMapping();
            testCase.verifyEqual(app.Data.summary.nRecordsExcluded, 3);
            testCase.verifyTrue(any(contains(string(app.Controls.summary.Value), "合計 3 行")));
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods('none');
            settings.methods.polynomial.enabled = true;
            settings.methods.polynomial.order = 1;
            settings.sampling.method = "manual";
            settings.sampling.manualPlans = "1 4 7 10 13 16 19 22 25 28";
            file = fullfile(folder, 'settings.json');
            alignest.saveSettings(settings, file);
            restored = alignest.loadSettings(file);
            testCase.verifyEqual(restored, settings);
            app.setSettings(restored);
            testCase.verifyNotEmpty(app.Data);
            result = app.runEvaluationNow(false);
            testCase.verifyTrue(all(result.table.note == ""));
            file = fullfile(folder, 'result.xlsx');
            app.exportResultsTo(file);
            explanation = readcell(file, 'Sheet', '説明');
            testCase.verifyTrue(any(contains(string(explanation(:)), "合計 3 行")));
            restored.data.excludeUnmeasuredRecords = false;
            app.setSettings(restored);
            testCase.verifyEmpty(app.Data);
            testCase.verifyEmpty(app.Results);
            testCase.verifyFalse(app.Controls.excludeUnmeasuredRecords.Value);
            % 追加項目を持たない従来の設定も、除外なしとして読み込める
            legacy = settings;
            legacy.data = rmfield(legacy.data, {'excludeZeroMeasurements', 'excludeUnmeasuredRecords'});
            app.setSettings(legacy);
            testCase.verifyFalse(app.Controls.excludeZeroMeasurements.Value);
            testCase.verifyFalse(app.Controls.excludeUnmeasuredRecords.Value);
            file = fullfile(folder, 'legacy.json');
            alignest.saveSettings(legacy, file);
            loaded = alignest.loadSettings(file);
            testCase.verifyFalse(loaded.data.excludeZeroMeasurements);
            testCase.verifyFalse(loaded.data.excludeUnmeasuredRecords);
        end

        function spatialMethodsRunFromControlsAndExport(testCase)
            app = testCase.App;
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods('none');
            settings.sampling.method = "manual";
            settings.sampling.manualPlans = "1 4 7 10 13 16 19 22 25 28 31 34 37 40 43";
            settings.factors.shotRowParity = true;
            app.setSettings(settings);
            app.Controls.rbf.Value = true;
            app.Controls.tps.Value = true;
            app.Controls.ordinaryKriging.Value = true;
            app.Controls.universalKriging.Value = true;
            app.Controls.tpsFactors.Value = 'both';
            app.Controls.ordinaryFactors.Value = 'backfit';
            app.Controls.universalFactors.Value = 'backfit';
            app.Controls.rbf.ValueChangedFcn([], []);
            testCase.verifyEqual(app.Settings.methods.tps.factorModes, ["none", "backfit"]);
            testCase.verifyEqual(string(app.Controls.universalFactors.Enable), "on");
            result = app.runEvaluationNow(false);
            testCase.verifyEqual(height(result.table), 25);
            testCase.verifyTrue(all(result.table.note == ""));
            testCase.verifyTrue(all(isfinite(result.table.RMSE_XY)));
            rbfIndex = find(string({result.methods.family}) == "RBF");
            app.showMap(1, result.plans(1).label, rbfIndex, "Y");
            testCase.verifyTrue(contains(app.Controls.mapInfo.Text, "RBF"));
            file = [tempname, '.xlsx'];
            cleanup = onCleanup(@() delete(file));
            app.exportResultsTo(file);
            exported = readtable(file, 'Sheet', 'Waferごと', 'VariableNamingRule', 'preserve');
            testCase.verifyTrue(any(contains(string(exported.("手法の識別子")), "RBF_gaussian")));
            testCase.verifyTrue(any(contains(string(exported.("手法の識別子")), "UK_exponential_XYR_backfit")));
            app.setSettings(result.settings);
            testCase.verifyTrue(app.Controls.rbf.Value);
            testCase.verifyEqual(string(app.Controls.tpsFactors.Value), "both");
        end

        function inputUnitsAndParityPersistAndRequireReimport(testCase)
            app = testCase.App;
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            settings.data.coordinateUnits.markXmm = "um";
            settings.factors.shotRowParity = true;
            app.setSettings(settings);
            testCase.verifyEmpty(app.Data);
            testCase.verifyTrue(app.Controls.shotRowParity.Value);
            row = find(string(app.Controls.mapping.Data(:, 1)) == "markXmm");
            testCase.verifyEqual(string(app.Controls.mapping.Data{row, 5}), "um");
            app.applyMapping();
            testCase.verifyEqual(app.Data.coordinateUnits.markXmm, "um");
            testCase.verifyEqual(max(abs(app.Data.units(1).marks.markXmm)), ...
                max(abs(app.RawTable.markXmm)) / 1000, 'AbsTol', 1e-12);
            % コールバックを通さない変更でも、古い解析データで実行しない
            app.Controls.mapping.Data{row, 5} = 'nm';
            testCase.verifyError(@() app.runEvaluationNow(false), 'alignest:noData');
            testCase.verifyEmpty(app.Data);
            event = struct("Indices", [row, 5], "NewData", 'nm', "PreviousData", 'um');
            app.Controls.mapping.CellEditCallback([], event);
            testCase.verifyEqual(app.Settings.data.coordinateUnits.markXmm, "nm");
            app.applyMapping();
            app.applyMapping(); % 元の入力から変換するため、二重に倍率を掛けない
            testCase.verifyEqual(max(abs(app.Data.units(1).marks.markXmm)), ...
                max(abs(app.RawTable.markXmm)) / 1e6, 'AbsTol', 1e-12);
        end

        function fullWorkflow(testCase)
            app = testCase.App;
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.xlsx'));
            testCase.verifyEqual(height(app.RawTable), 1995);
            testCase.verifyEqual(string(app.Controls.mapping.Data(:, 4)).', string(app.Controls.mapping.Data(:, 1)).');
            app.applyMapping();
            testCase.verifyEqual(numel(app.Data.units), 5);
            testCase.verifyEqual(numel(app.Controls.previewWafer.Items), 5);
            settings = app.Settings;
            settings.sampling.nShots = [10, 20];
            app.setSettings(settings);
            testCase.verifyEqual(app.Controls.nShots.Value, '10 20');
            testCase.verifyTrue(contains(app.Controls.countLabel.Text, "90 回"));
            results = app.runEvaluationNow(false);
            testCase.verifyEqual(height(results.table), 5 * 2 * 9);
            testCase.verifyEqual(size(app.Controls.summaryTable.Data), [9, 3]);
            testCase.verifyEqual(size(app.Controls.comparisonTable.Data, 1), 8 * 2);
            testCase.verifyTrue(any(contains(string(app.Controls.summaryTable.Data(:)), "★")));
            app.showMap(2, "I最適 20 Shot", 3, "vector");
            testCase.verifyTrue(contains(app.Controls.mapInfo.Text, "RMSE"));
            app.showMap(1, "I最適 10 Shot", 5, "Y");
            testCase.verifyTrue(contains(app.Controls.mapInfo.Text, "TPS"));
            file = [tempname, '.xlsx'];
            cleanup = onCleanup(@() delete(file));
            app.exportResultsTo(file);
            testCase.verifyTrue(isfile(file));
        end

        function reloadingDataClearsResults(testCase)
            app = testCase.App;
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            settings.sampling.nShots = 10;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            app.setSettings(settings);
            app.runEvaluationNow(false);
            testCase.verifyNotEmpty(app.Results);
            app.applyMapping();
            testCase.verifyEmpty(app.Results);
            testCase.verifyEqual(string(app.Controls.export.Enable), "off");
        end

        function runWithoutDataIsAnError(testCase)
            testCase.verifyError(@() testCase.App.runEvaluationNow(false), 'alignest:noData');
        end
    end
end
