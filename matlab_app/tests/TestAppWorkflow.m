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
