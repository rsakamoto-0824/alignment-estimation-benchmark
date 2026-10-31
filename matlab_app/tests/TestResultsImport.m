classdef TestResultsImport < matlab.unittest.TestCase
    %TESTRESULTSIMPORT 評価結果の Excel（alignest.exportResults）を読み込み（alignest.importResults）、
    %   結果の表・学習パターン・手法・設定が書き出す前と同じに戻ることと、「ハイパーパラメータ」の見出し（以前の版の
    %   「超パラメータ」の見出しも読めること）を確かめる。

    properties
        Results
        Folder
    end

    methods (TestClassSetup)
        function evaluateSample(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            addpath(root);
            raw = alignest.readMeasurementFile(fullfile(root, 'sample_data', 'sample_alignment.csv'));
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            settings = alignest.defaultSettings();
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.methods.tps.enabled = true;
            settings.sampling.nShots = [15, 30];
            settings.sampling.nShotsStart = 15;
            settings.sampling.nShotsEnd = 30;
            settings.sampling.nShotsStep = 15;
            settings.factors.separateY = true;
            settings.factors.y.scan = false;
            testCase.Results = alignest.runEvaluation(data, settings);
            testCase.Folder = tempname;
            mkdir(testCase.Folder);
            testCase.addTeardown(@() rmdir(testCase.Folder, 's'));
        end
    end

    methods (Test)
        function roundTripRestoresResults(testCase)
            results = testCase.Results;
            file = fullfile(testCase.Folder, 'results.xlsx');
            alignest.exportResults(results, file, "sample_alignment.csv");
            imported = alignest.importResults(file);
            % 結果の表：書き出した列は同じ値（数値は Excel の桁で丸まる）、番号の列も同じ
            names = alignest.resultColumnNames(results.overlayEvaluated);
            for name = names
                expected = results.table.(name);
                actual = imported.table.(name);
                if isnumeric(expected) || islogical(expected)
                    testCase.verifyEqual(double(actual), double(expected), 'AbsTol', 1e-9, name);
                else
                    testCase.verifyEqual(actual, string(expected), name);
                end
            end
            for name = ["unitIndex", "planIndex", "methodIndex", "family", "featureSet", "variant", "factorMode"]
                testCase.verifyEqual(imported.table.(name), results.table.(name), name);
            end
            testCase.verifyEqual(imported.methods, results.methods);
            testCase.verifyEqual(imported.groups, results.groups);
            testCase.verifyEqual(imported.unitLabels, results.unitLabels);
            testCase.verifyEqual(imported.settings, results.settings, "設定は JSON から戻す（Y 成分の質的変数も）");
            testCase.verifyEqual(imported.createdAt, results.createdAt);
            testCase.verifyEqual(imported.overlayEvaluated, results.overlayEvaluated);
            testCase.verifyEqual(imported.overlayDescription, results.overlayDescription);
            testCase.verifyEqual(imported.elapsedSeconds, round(results.elapsedSeconds, 1), 'AbsTol', 1e-9);
            % 学習パターン：Shot 番号・I 基準・D 基準
            testCase.verifyEqual(numel(imported.plans), numel(results.plans));
            for p = 1:numel(results.plans)
                testCase.verifyEqual(imported.plans(p).shotNos(:), results.plans(p).shotNos(:));
                testCase.verifyEqual([imported.plans(p).criterionI, imported.plans(p).efficiencyD], ...
                    [results.plans(p).criterionI, results.plans(p).efficiencyD], 'AbsTol', 1e-9);
                testCase.verifyEqual(imported.plans(p).group, results.plans(p).group);
            end
            % 集計・比較は書き出す前と同じ
            for metric = ["RMSE_XY", "improveMeanPct_XY", "criterionI"]
                expected = alignest.perUnitValues(results, metric);
                actual = alignest.perUnitValues(imported, metric);
                testCase.verifyEqual(cell2mat(actual), cell2mat(expected), 'AbsTol', 1e-9, metric);
            end
            expected = alignest.pairedComparison(results, results.methods(1).id, "RMSE_XY");
            actual = alignest.pairedComparison(imported, imported.methods(1).id, "RMSE_XY");
            testCase.verifyEqual(actual{:, vartype('numeric')}, expected{:, vartype('numeric')}, 'AbsTol', 1e-9);
            testCase.verifyEqual(actual{:, vartype('string')}, expected{:, vartype('string')});
        end

        function otherFilesAreRejected(testCase)
            file = fullfile(testCase.Folder, 'other.xlsx');
            writetable(table([1; 2], 'VariableNames', "value"), file, 'Sheet', 'Sheet1');
            testCase.verifyError(@() alignest.importResults(file), 'alignest:importResults');
            testCase.verifyError(@() alignest.importResults(fullfile(testCase.Folder, 'missing.xlsx')), ...
                'alignest:importResults');
            % 必要な列が無い「Waferごと」シート
            writetable(table("W1", 'VariableNames', "Wafer"), file, 'Sheet', 'Waferごと');
            testCase.verifyError(@() alignest.importResults(file), 'alignest:importResults');
        end

        function hyperparameterColumnKeepsOldFilesReadable(testCase)
            % Excel の見出しは「ハイパーパラメータ」。以前の版の「超パラメータ」の見出しのファイルも読める
            [names, headers] = alignest.resultColumnNames(false);
            testCase.verifyEqual(headers(names == "hyperparameters"), "ハイパーパラメータ");
            testCase.verifyFalse(any(contains(headers, "超パラメータ")));
            root = fileparts(fileparts(mfilename('fullpath')));
            raw = alignest.readMeasurementFile(fullfile(root, 'sample_data', 'sample_alignment.csv'));
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames), ...
                directionRule="serpentine");
            data.units = data.units(1);
            settings = alignest.defaultSettings();
            settings.methods = alignest.recommendedMethods('none');
            settings.methods.gpr.enabled = true;
            settings.methods.gpr.factorModes = "none";
            settings.sampling.nShots = 20;
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(20, 20, 10);
            results = alignest.runEvaluation(data, settings);
            file = fullfile(testCase.Folder, 'hyperparameters.xlsx');
            alignest.exportResults(results, file, "sample_alignment.csv");
            cells = readcell(file, 'Sheet', 'Waferごと');
            column = find(strcmp(string(cells(1, :)), "ハイパーパラメータ"));
            testCase.verifyNumElements(column, 1);
            writecell({'超パラメータ'}, file, 'Sheet', 'Waferごと', 'Range', excelColumn(column) + "1");
            imported = alignest.importResults(file);
            testCase.verifyEqual(imported.table.hyperparameters, results.table.hyperparameters, ...
                "以前の見出しの列も「ハイパーパラメータ」として読む");
            testCase.verifyTrue(contains(imported.table.hyperparameters(1), "ls1_X"));
        end
    end
end

function letters = excelColumn(index)
% Excel の列の番号を列の文字にする（1 → A、27 → AA）
letters = "";
while index > 0
    remainder = mod(index - 1, 26);
    letters = char('A' + remainder) + letters;
    index = floor((index - 1) / 26);
end
end
