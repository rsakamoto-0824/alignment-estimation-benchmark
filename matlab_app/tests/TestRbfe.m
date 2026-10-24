classdef TestRbfe < matlab.unittest.TestCase
    %TESTRBFE RBFe（仮）：面内を領域に分け、領域ごとの TPS をつなぎ合わせる形状関数の GAM と、
    %   「ハイパーパラメータ」の表記（Excel の見出し、以前の版の見出しの読み込み）を確かめる。

    properties
        Data
        Settings
        Root
    end

    methods (TestClassSetup)
        function loadSample(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.Root);
            raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            testCase.Data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames), ...
                directionRule="serpentine");
            testCase.Settings = alignest.defaultSettings();
        end
    end

    methods (Test)
        function oneRegionIsTheTps(testCase)
            % 領域の数 1 は、全体で1つの TPS と同じ推定値・有効自由度（質的変数の Backfitting も同じ）
            unit = testCase.Data.units(1);
            shots = 1:2:numel(unit.shots.shotNo);
            [methods, ids] = methodList(1, ["none", "backfit"]);
            for mode = ["", "_backfit"]
                tps = alignest.estimateWafer(unit, shots, methods(ids == "TPS_XYR" + mode), testCase.Settings);
                rbfe = alignest.estimateWafer(unit, shots, methods(ids == "RBFe_k1_XYR" + mode), testCase.Settings);
                testCase.verifyEqual(rbfe.estimate.X, tps.estimate.X, 'AbsTol', 1e-8, mode);
                testCase.verifyEqual(rbfe.estimate.Y, tps.estimate.Y, 'AbsTol', 1e-8, mode);
                testCase.verifyEqual(rbfe.edf, tps.edf, 'AbsTol', 1e-6, mode);
            end
        end

        function regionsCoverThePlaneSmoothly(testCase)
            % 領域の重みは1の分割（和が 1）、各領域に最小数以上の学習点、学習点が少なければ領域を減らす。
            % 同じ学習点なら毎回同じ領域。つなぎ目でも推定値は滑らか（近い2点の差が小さい）
            unit = testCase.Data.units(1);
            train = find(ismember(unit.marks.shotIndex, 1:2:numel(unit.shots.shotNo)) & unit.marks.validX);
            trainXY = [unit.marks.x(train), unit.marks.y(train)];
            features = alignest.basis.distanceFeatures(unit.marks.x(train), unit.marks.y(train), "XY", 150);
            [gx, gy] = meshgrid(-140:1:140, 0);
            testXY = [gx(:), gy(:)];
            testFeatures = alignest.basis.distanceFeatures(testXY(:, 1), testXY(:, 2), "XY", 150);
            grid = linspace(-8, 3, 45);
            model = alignest.models.rbfeSetup(trainXY, testXY, features, testFeatures, 9, grid);
            testCase.verifyEqual(model.nRegions, 9);
            testCase.verifyEqual(sum(model.weightTrain, 2), ones(numel(train), 1), 'AbsTol', 1e-12);
            testCase.verifyEqual(sum(model.weightTest, 2), ones(size(testXY, 1), 1), 'AbsTol', 1e-12);
            testCase.verifyGreaterThanOrEqual(min(arrayfun(@(r) numel(r.train), model.regions)), 10);
            again = alignest.models.rbfeSetup(trainXY, testXY, features, testFeatures, 9, grid);
            testCase.verifyEqual(again.centers, model.centers, "決まった初期値なので毎回同じ領域");
            result = alignest.models.rbfeFitPredict(model, unit.marks.measX(train));
            testCase.verifyLessThan(max(abs(diff(result.prediction))), 1.0, "1 mm 隣の推定値が跳ばない");
            testCase.verifyEqual(numel(result.log10Lambdas), 9, "λ は領域ごとに GCV で選ぶ");
            few = alignest.models.rbfeSetup(trainXY(1:30, :), testXY, features(1:30, :), testFeatures, 9, grid);
            testCase.verifyEqual(few.nRegions, 3, "30 点では 10 点ずつ 3 領域まで");
        end

        function rbfeEvaluatesWithFactors(testCase)
            % 評価の流れで推定でき、Backfitting では質的変数の効果を足す（GAM）。使った領域の数がハイパーパラメータに残る
            settings = testCase.Settings;
            settings.methods = alignest.recommendedMethods('none');
            settings.methods.rbfe.enabled = true;
            settings.methods.rbfe.regions = [1, 4];
            settings.methods.rbfe.factorModes = ["none", "backfit"];
            settings.sampling.nShots = 30;
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(30, 30, 10);
            data = testCase.Data;
            data.units = data.units(1:2);
            results = alignest.runEvaluation(data, settings);
            ids = string({results.methods.id});
            testCase.verifyEqual(ids, ["RBFe_k1_XYR", "RBFe_k1_XYR_backfit", "RBFe_k4_XYR", "RBFe_k4_XYR_backfit"]);
            table_ = results.table;
            testCase.verifyTrue(all(isfinite(table_.RMSE_XY)));
            testCase.verifyTrue(all(contains(table_.hyperparameters(table_.methodId == "RBFe_k4_XYR"), "rbfeRegions_X=4")));
            plain = table_.RMSE_XY(table_.methodId == "RBFe_k4_XYR");
            withFactors = table_.RMSE_XY(table_.methodId == "RBFe_k4_XYR_backfit");
            testCase.verifyNotEqual(plain, withFactors, "Backfitting は質的変数（Scan 方向・Mark 番号）の効果を足す");
            testCase.verifyLessThan(mean(withFactors), mean(plain));
        end

        function settingsAreValidated(testCase)
            config = alignest.recommendedMethods('none');
            config.rbfe.enabled = true;
            config.rbfe.regions = [4, 4, 9];
            ids = string({alignest.buildMethodList(config).id});
            testCase.verifyEqual(ids, ["RBFe_k4_XYR_backfit", "RBFe_k9_XYR_backfit"], "初期値は Backfitting、重なりは1つ");
            config.rbfe.regions = 0;
            testCase.verifyError(@() alignest.buildMethodList(config), 'alignest:rbfeRegions');
            config.rbfe.regions = 2.5;
            testCase.verifyError(@() alignest.buildMethodList(config), 'alignest:rbfeRegions');
            legacy = rmfield(alignest.recommendedMethods(), 'rbfe');
            completed = alignest.completeMethodSettings(legacy);
            testCase.verifyFalse(completed.rbfe.enabled, "以前の設定では使わない");
            testCase.verifyEqual(completed.rbfe.regions, 4);
            testCase.verifyFalse(alignest.recommendedMethods().rbfe.enabled, "推奨の組み合わせには入れない（仮の手法）");
        end

        function hyperparameterColumnKeepsOldFilesReadable(testCase)
            % Excel の見出しは「ハイパーパラメータ」。以前の版の「超パラメータ」の見出しのファイルも読める
            [names, headers] = alignest.resultColumnNames(false);
            testCase.verifyEqual(headers(names == "hyperparameters"), "ハイパーパラメータ");
            testCase.verifyFalse(any(contains(headers, "超パラメータ")));
            settings = testCase.Settings;
            settings.methods = alignest.recommendedMethods('none');
            settings.methods.gpr.enabled = true;
            settings.methods.gpr.factorModes = "none";
            settings.sampling.nShots = 20;
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(20, 20, 10);
            data = testCase.Data;
            data.units = data.units(1);
            results = alignest.runEvaluation(data, settings);
            file = [tempname, '.xlsx'];
            cleanup = onCleanup(@() delete(file));
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

        function appRowSetsTheRegions(testCase)
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            settings = app.Settings;
            settings.methods.rbfe.enabled = true;
            settings.methods.rbfe.regions = [4, 9];
            settings.methods.rbfe.factorModes = ["none", "backfit"];
            app.setSettings(settings);
            testCase.verifyTrue(c.rbfe.Value);
            testCase.verifyEqual(string(c.rbfeRegions.Value), "4 9");
            testCase.verifyEqual(string(c.rbfeFactors.Value), "both");
            c.rbfeRegions.Value = '６';
            c.rbfeRegions.ValueChangedFcn([], []);
            testCase.verifyEqual(app.Settings.methods.rbfe.regions, 6, "全角の数字も読む");
            testCase.verifyEmpty(c.rbfeError.Text);
            c.rbfeRegions.Value = '0 4';
            c.rbfeRegions.ValueChangedFcn([], []);
            testCase.verifyTrue(contains(string(c.rbfeError.Text), "領域の数"));
            c.rbfe.Value = false;
            c.rbfe.ValueChangedFcn([], []);
            testCase.verifyEqual(string(c.rbfeRegions.Enable), "off");
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

function [methods, ids] = methodList(regions, modes)
config = alignest.recommendedMethods('none');
config.tps.enabled = true;
config.tps.factorModes = modes;
config.rbfe.enabled = true;
config.rbfe.regions = regions;
config.rbfe.factorModes = modes;
methods = alignest.buildMethodList(config);
ids = string({methods.id});
end
