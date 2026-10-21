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
            row = find(string(app.Controls.unitTable.Data(:, 1)) == "markXmm");
            testCase.verifyEqual(string(app.Controls.unitTable.Data{row, 2}), "µm");
            testCase.verifyTrue(startsWith(string(app.Controls.unitTable.Data{row, 6}), "⚠"), ...
                "mm の値を µm として読むと目安の外になる");
            app.applyMapping();
            testCase.verifyEqual(app.Data.coordinateUnits.markXmm, "um");
            testCase.verifyEqual(max(abs(app.Data.units(1).marks.markXmm)), ...
                max(abs(app.RawTable.markXmm)) / 1000, 'AbsTol', 1e-12);
            % コールバックを通さない変更でも、古い解析データで実行しない
            app.Controls.unitTable.Data{row, 2} = 'nm';
            testCase.verifyError(@() app.runEvaluationNow(false), 'alignest:noData');
            testCase.verifyEmpty(app.Data);
            app.Controls.unitTable.CellEditCallback([], []);
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
            settings.sampling.nShots = [10, 20];   % 並びだけを変えた設定も、開始・終了・刻みに直して表示する
            app.setSettings(settings);
            testCase.verifyEqual([app.Controls.nShotsStart.Value, app.Controls.nShotsEnd.Value, ...
                app.Controls.nShotsStep.Value], [10, 20, 10]);
            testCase.verifyTrue(contains(app.Controls.nShotsList.Text, "10, 20（2 通り）"));
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

        function dataMapsLayoutAndUnitSuggestion(testCase)
            app = testCase.App;
            raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            raw.markXmm = raw.markXmm * 1000;  % 列名は markXmm のまま、中身を µm にする
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's'));
            file = fullfile(folder, 'input_um.csv');
            writetable(raw, file);
            app.loadFile(file);
            row = find(string(app.Controls.unitTable.Data(:, 1)) == "markXmm");
            testCase.verifyTrue(startsWith(string(app.Controls.unitTable.Data{row, 6}), "⚠"));
            testCase.verifyEqual(app.suggestCoordinateUnits(), "markXmm");
            testCase.verifyEqual(string(app.Controls.unitTable.Data{row, 2}), "µm");
            testCase.verifyEqual(string(app.Controls.unitTable.Data(:, 6)).', repmat("OK", 1, 5));
            % 「まとめて選ぶ」は全列を同じ単位にして、選択欄は「列ごとに選ぶ」に戻る
            app.Controls.unitAll.Value = 'nm';
            app.Controls.unitAll.ValueChangedFcn([], []);
            testCase.verifyEqual(string(struct2cell(app.Settings.data.coordinateUnits)).', repmat("nm", 1, 5));
            testCase.verifyEqual(app.Controls.unitAll.Value, '');
            app.suggestCoordinateUnits();
            testCase.verifyEqual(app.Settings.data.coordinateUnits.markXmm, "um");
            testCase.verifyEqual(app.Settings.data.coordinateUnits.Xmm, "mm");
            app.applyMapping();
            testCase.verifyEqual(max(abs(app.Data.units(1).marks.markXmm)), 10, 'AbsTol', 1e-9);
            % 計測値のベクトルと X・Y のヒートマップ、Shot の枠
            testCase.verifyTrue(all(arrayfun(@(ax) ax.Visible == "on", app.Controls.previewAxes)));
            scatterX = findall(app.Controls.previewAxes(2), 'Type', 'scatter');
            testCase.verifyEqual(scatterX.SizeData, 30);
            framed = numel(findall(app.Controls.previewAxes(2), 'Type', 'line'));  % Wafer の縁と Shot の枠
            app.Controls.previewMarkerSize.Value = 80;
            app.Controls.previewShotFrames.Value = false;
            app.Controls.previewShotFrames.ValueChangedFcn([], []);
            scatterX = findall(app.Controls.previewAxes(2), 'Type', 'scatter');
            testCase.verifyEqual(scatterX.SizeData, 80);
            testCase.verifyEqual(numel(findall(app.Controls.previewAxes(2), 'Type', 'line')), framed - 1);
            % Shot レイアウト：Shot ごとに shotNo、Shot 内の Mark の位置ごとに番号
            unit = app.Data.units(1);
            testCase.verifyEqual(unit.shotSizeMm, [22, 26], 'AbsTol', 1e-9);
            texts = findobj(app.Controls.layoutAxes(1), 'Type', 'text');
            testCase.verifyEqual(numel(texts), numel(unit.shots.shotNo));
            markLabels = findobj(app.Controls.layoutAxes(2), 'Type', 'text');
            testCase.verifyEqual(numel(markLabels), 4);
            markTexts = arrayfun(@(item) strjoin(string(item.String), " "), markLabels);
            testCase.verifyTrue(any(contains(markTexts, "M1")));
            testCase.verifyTrue(contains(app.Controls.layoutInfo.Text, "22.000 × 26.000"));
        end

        function directionIsAssignedFromControls(testCase)
            app = testCase.App;
            raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            withColumn = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            raw = removevars(raw, 'Direction');
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's'));
            file = fullfile(folder, 'no_direction.csv');
            writetable(raw, file);
            app.loadFile(file);
            app.applyMapping();
            testCase.verifyFalse(app.Data.units(1).hasDirection);
            testCase.verifyTrue(any(contains(string(app.Controls.summary.Value), "なし")));
            % サンプルの Scan 方向は Shot 列の奇偶と同じ
            app.Controls.directionRule.Value = 'columnParity';
            app.Controls.directionRule.ValueChangedFcn([], []);
            testCase.verifyEmpty(app.Data);
            testCase.verifyEqual(string(app.Controls.invertDirection.Enable), "on");
            app.applyMapping();
            testCase.verifyTrue(app.Data.units(1).hasDirection);
            testCase.verifyEqual(app.Data.units(1).shots.direction, withColumn.units(1).shots.direction);
            testCase.verifyTrue(any(contains(string(app.Controls.summary.Value), "規則による付与")));
            app.Controls.invertDirection.Value = true;
            app.Controls.invertDirection.ValueChangedFcn([], []);
            app.applyMapping();
            testCase.verifyEqual(app.Data.units(1).shots.direction, 3 - withColumn.units(1).shots.direction);
            testCase.verifyEqual(app.Settings.data.directionRule, "columnParity");
            testCase.verifyTrue(app.Settings.data.invertDirection);
            % 設定の読み込みで規則が変われば、読み込み直しが必要
            settings = app.Settings;
            settings.data.directionRule = "none";
            app.setSettings(settings);
            testCase.verifyEmpty(app.Data);
            testCase.verifyEqual(app.Controls.directionRule.Value, 'none');
        end

        function sweepTimingAnalysisAndEstimateExport(testCase)
            app = testCase.App;
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.xlsx'));
            app.applyMapping();
            testCase.verifyTrue(any(contains(string(app.Controls.summary.Value), "EXP01、EXP02")));
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.methods.tps.enabled = true;
            app.setSettings(settings);
            % 学習 Shot 数は 開始・終了・刻み で決める
            app.Controls.nShotsStart.Value = 10;
            app.Controls.nShotsEnd.Value = 22;
            app.Controls.nShotsStep.Value = 6;
            app.Controls.recordTiming.Value = true;
            app.Controls.recordTiming.ValueChangedFcn([], []);
            testCase.verifyEqual(app.Settings.sampling.nShots, [10, 16, 22]);
            testCase.verifyTrue(contains(app.Controls.nShotsList.Text, "10, 16, 22（3 通り）"));
            app.Controls.nShotsEnd.Value = 5;
            app.Controls.nShotsEnd.ValueChangedFcn([], []);
            testCase.verifyTrue(contains(app.Controls.nShotsError.Text, "終了"));
            testCase.verifyEqual(app.Settings.sampling.nShots, [10, 16, 22], "正しくない組み合わせでは前の値のまま");
            testCase.verifyError(@() app.runEvaluationNow(false), 'alignest:settings');
            app.Controls.nShotsEnd.Value = 22;
            app.Controls.nShotsEnd.ValueChangedFcn([], []);
            results = app.runEvaluationNow(false);
            testCase.verifyEqual(results.groups, ["10 Shot", "16 Shot", "22 Shot"]);
            testCase.verifyTrue(results.timingRecorded);
            testCase.verifyTrue(all(results.table.seconds > 0));
            testCase.verifyTrue(any(string(app.Controls.metric.ItemsData) == "seconds"));
            testCase.verifyTrue(all(isfinite([results.plans.criterionI, results.plans.criterionD])));
            % 集計のワースト値は Wafer の最大
            app.Controls.statistic.Value = 'worst';
            app.Controls.statistic.ValueChangedFcn([], []);
            worst = max(results.table.RMSE_XY(results.table.methodIndex == 1 & results.table.group == "10 Shot"));
            testCase.verifyEqual(str2double(extractBefore(string(app.Controls.summaryTable.Data{1, 2}) + " ", " ")), ...
                worst, 'AbsTol', 5e-4);
            % I 基準・D 基準のグラフ（2つの軸に、手法ごとに学習パターンの数だけ点）
            app.Controls.chartXAxis.Value = 'criteria';
            app.Controls.chartXAxis.ValueChangedFcn([], []);
            curves = findobj(app.Controls.chartAxes2, 'Type', 'line');
            testCase.verifyEqual(numel(curves), numel(results.methods));
            testCase.verifyEqual(numel(curves(1).XData), 3);
            testCase.verifyEqual(app.Controls.chartAxes2.XScale, 'log');
            % 推定値と誤差の分布：ヒストグラム・正規性検定・ANOVA（工程は1つなので検定しない、装置は2台）
            analysis = app.analyzeResiduals(1, "22 Shot", 0);
            testCase.verifyEqual(height(analysis.normality), 2);
            testCase.verifyEqual(size(app.Controls.normalityTable.Data, 1), 2);
            testCase.verifyTrue(any(analysis.anova.factor == "装置（EqpId）"));
            testCase.verifyEqual(analysis.anova.note(analysis.anova.factor == "工程（Operation）"), ...
                repmat("水準が1つしかないので検定しません。", 2, 1));
            testCase.verifyNotEmpty(findobj(app.Controls.histogramAxes(1), 'Type', 'histogram'));
            % 推定値の Excel：選んだ範囲（1手法・1列・5枚）と、すべて
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's'));
            file = fullfile(folder, 'estimates.xlsx');
            app.exportEstimatesTo(file, "selected");
            testCase.verifyTrue(all(ismember(["説明", "推定値", "正規性検定", "ANOVA"], sheetnames(file))));
            points = readtable(file, 'Sheet', '推定値', 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(numel(unique(string(points.Wafer))), 5);
            testCase.verifyEqual(unique(string(points.("列"))), "22 Shot");
            testCase.verifyEqual(points.("残差X[nm]"), points.("計測値X[nm]") - points.("推定値X[nm]"), 'AbsTol', 1e-9);
            testCase.verifyTrue(all(ismember(["EXP01", "EXP02"], string(points.EqpId))));
            app.exportEstimatesTo(file, "all");
            points = readtable(file, 'Sheet', '推定値', 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(numel(unique(string(points.("手法の識別子")) + string(points.("列")))), ...
                numel(results.methods) * numel(results.groups));
            % 評価結果の Excel：集計の統計量・処理時間・工程と装置の列
            file = fullfile(folder, 'results.xlsx');
            app.exportResultsTo(file);
            testCase.verifyTrue(all(ismember(["集計_統計量", "処理時間"], sheetnames(file))));
            statistics = readtable(file, 'Sheet', '集計_統計量', 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(sort(unique(string(statistics.("集計")))), sort(["平均"; "中央値"; "ワースト値"; "95%値"]));
            perWafer = readtable(file, 'Sheet', 'Waferごと', 'VariableNamingRule', 'preserve');
            testCase.verifyTrue(all(ismember(["Operation", "EqpId", "I基準tr(M⁻¹)", "D基準det(M)^(-1/p)"], ...
                string(perWafer.Properties.VariableNames))));
        end

        function modelOptionsFromControls(testCase)
            app = testCase.App;
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            app.setSettings(settings);
            app.Controls.gpr.Value = true;
            app.Controls.kernels.Value = {'matern52', 'ardmatern'};
            set(app.Controls.factorModes, 'Value', false);
            app.Controls.factorModes(1).Value = true;
            app.Controls.maternNu.Value = '0.5 1.2';
            app.Controls.ordinaryKriging.Value = true;
            set(app.Controls.variograms, 'Value', false);
            app.Controls.variograms(end).Value = true;
            app.Controls.gam.Value = true;
            app.Controls.gamShapes(1).Value = 'gp';
            app.Controls.gam.ValueChangedFcn([], []);
            settings = app.Settings.methods;
            testCase.verifyEqual(settings.gpr.maternNu, [0.5, 1.2]);
            testCase.verifyEqual(settings.kriging.variograms, "spherical");
            testCase.verifyEqual(settings.gam.shapes.xy, "gp");
            testCase.verifyEqual(string(app.Controls.maternNu.Enable), "on");
            ids = string({alignest.buildMethodList(settings).id});
            testCase.verifyEqual(ids, ["GPR_matern52_XYR_none", "GPR_ardmatern_nu0.5_XYR_none", ...
                "GPR_ardmatern_nu1.2_XYR_none", "OK_spherical_XYR", "GAM_XYR_gp-xy"]);
            testCase.verifyTrue(contains(app.Controls.countLabel.Text, "手法 5 種類"));
            % 正しくない ν は欄の下に理由を出し、前の値のまま
            app.Controls.maternNu.Value = '0 2';
            app.Controls.maternNu.ValueChangedFcn([], []);
            testCase.verifyTrue(startsWith(app.Controls.maternNuError.Text, "⚠"));
            testCase.verifyEqual(app.Settings.methods.gpr.maternNu, [0.5, 1.2]);
            % 設定の保存・読み込みで元に戻る
            file = [tempname, '.json'];
            cleanup = onCleanup(@() delete(file));
            app.Controls.maternNu.Value = '0.5 1.2';
            app.Controls.maternNu.ValueChangedFcn([], []);
            alignest.saveSettings(app.Settings, file);
            app.setSettings(alignest.defaultSettings());
            testCase.verifyEqual(app.Controls.gamShapes(1).Value, 'spline');
            app.setSettings(alignest.loadSettings(file));
            testCase.verifyEqual(app.Controls.gamShapes(1).Value, 'gp');
            testCase.verifyEqual(app.Controls.maternNu.Value, '0.5 1.2');
            testCase.verifyTrue(app.Controls.variograms(end).Value);
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
