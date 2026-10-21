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
            testCase.verifyEqual(string(app.Controls.previewWafer.Items(1:5)), string({app.Data.units.label}));
            testCase.verifyEqual(numel(app.Controls.previewWafer.Items), 5 + 3, "全 Wafer と EqpId ごとの平均も選べる");
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

        function factorColumnsAndLotIdFlowToResults(testCase)
            app = testCase.App;
            raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            raw.LotID = "LOT" + extractAfter(raw.Wafer, "SIM");
            raw.Chuck = "C" + string(mod(raw.shotNo, 2));
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's'));
            file = fullfile(folder, 'with_lot.csv');
            writetable(raw, file);
            app.loadFile(file);
            app.applyMapping();
            testCase.verifyTrue(any(contains(string(app.Controls.summary.Value), "LOT01、LOT02")));
            testCase.verifyEqual(string(app.Controls.factorColumns.ItemsData), "Chuck", "LotID は標準の項目なので選択肢に出ない");
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.rbf.enabled = true;
            settings.methods.rbf.factorModes = "backfit";
            settings.sampling.nShots = 15;
            app.setSettings(settings);
            testCase.verifyEqual(app.Controls.rbfFactors.Value, 'backfit');
            app.Controls.factorScan.Value = false;
            app.Controls.factorColumns.Value = {'Chuck'};
            app.Controls.factorColumns.ValueChangedFcn([], []);
            testCase.verifyEqual(app.Settings.factors.columns, "Chuck");
            testCase.verifyFalse(app.Settings.factors.scan);
            results = app.runEvaluationNow(false);
            testCase.verifyEqual(results.table.methodId(1), "RBF_gaussian_XYR_backfit");
            testCase.verifyTrue(all(results.table.note == ""));
            testCase.verifyEqual(unique(results.table.LotID).', "LOT0" + (1:5));
            analysis = app.analyzeResiduals(1, "15 Shot", 0);
            testCase.verifyTrue(all(ismember(["Chuck", "ロット（LotID）"], analysis.anova.factor)));
            estimatesFile = fullfile(folder, 'estimates.xlsx');
            app.exportEstimatesTo(estimatesFile, "selected");
            points = readtable(estimatesFile, 'Sheet', '推定値', 'VariableNamingRule', 'preserve');
            testCase.verifyTrue(all(ismember(["LotID", "質的変数:Chuck"], string(points.Properties.VariableNames))));
            resultsFile = fullfile(folder, 'results.xlsx');
            app.exportResultsTo(resultsFile);
            perWafer = readtable(resultsFile, 'Sheet', 'Waferごと', 'VariableNamingRule', 'preserve');
            testCase.verifyTrue(any(string(perWafer.Properties.VariableNames) == "LotID"));
            explanation = readcell(resultsFile, 'Sheet', '説明');
            testCase.verifyTrue(any(contains(string(explanation(:, 2)), "Mark 番号、列 Chuck")));
            % 設定の列がデータに無いときは、選択肢に「データに無い」と出て、評価を始めない
            settings = app.Settings;
            settings.factors.columns = ["Chuck", "Nozzle"];
            app.setSettings(settings);
            testCase.verifyTrue(any(contains(string(app.Controls.factorColumns.Items), "Nozzle（データに無い）")));
            testCase.verifyTrue(contains(app.Controls.factorColumnsError.Text, "Nozzle"));
            testCase.verifyError(@() app.runEvaluationNow(false), 'alignest:settings');
        end

        function overlayCorrectionFromControlsMapAndExport(testCase)
            app = testCase.App;
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.xlsx'));
            app.applyMapping();
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.tps.enabled = true;
            settings.sampling.nShots = 15;
            app.setSettings(settings);
            % 補正モデルを画面で選ぶ
            app.Controls.overlayWafer.Value = 2;
            app.Controls.overlayShotCommon.Value = 'asml';
            app.Controls.overlayPerShot.Value = 'translation';
            app.Controls.overlayPerShot.ValueChangedFcn([], []);
            testCase.verifyEqual(app.Settings.overlay, struct("waferOrder", 2, "shotCommon", "asml", "perShot", "translation"));
            results = app.runEvaluationNow(false);
            testCase.verifyTrue(results.overlayEvaluated);
            testCase.verifyTrue(contains(results.overlayDescription, "ASML"));
            testCase.verifyTrue(any(string(app.Controls.metric.ItemsData) == "overlayIncrease_X"));
            testCase.verifyEqual(string(app.Controls.mapContent.Enable), "on");
            % Wafer ごとのマップ：実測値で補正・推定値で補正・推定による変化
            app.showMap(1, results.plans(1).label, 1, "vector", "overlay");
            testCase.verifyEqual(string(app.Controls.mapAxes(3).Title.String), "推定による変化（推定値で補正 − 実測値で補正）");
            testCase.verifyTrue(contains(app.Controls.mapInfo.Text, "補正モデル"));
            row = results.table(1, :);
            testCase.verifyTrue(contains(app.Controls.mapInfo.Text, sprintf("推定値で補正 X %.3f", row.overlayEstimated_X)));
            app.showMap(1, results.plans(1).label, 1, "X", "estimate");
            testCase.verifyEqual(string(app.Controls.mapAxes(1).Title.String), "計測値（評価した Shot）");
            % 推定値の Excel に、全 Mark の補正残差のシート
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's'));
            file = fullfile(folder, 'estimates.xlsx');
            app.Controls.analysisWafer.Value = 1;
            app.Controls.analysisGroup.Value = '15 Shot';
            app.exportEstimatesTo(file, "selected");
            overlay = readtable(file, 'Sheet', 'Overlay残差', 'VariableNamingRule', 'preserve');
            marks = app.Data.units(1).marks;
            testCase.verifyEqual(height(overlay), nnz(marks.validX | marks.validY));
            testCase.verifyEqual(sort(unique(string(overlay.("Shotの区分")))), ["学習"; "評価"]);
            testCase.verifyEqual(overlay.("推定による変化X[nm]"), overlay.("推定値で補正した残差X[nm]") - ...
                overlay.("実測値で補正した残差X[nm]"), 'AbsTol', 1e-9);
            % すべて「なし」にすると評価せず、マップの切り替えも使えない
            app.Controls.overlayWafer.Value = 0;
            app.Controls.overlayShotCommon.Value = 'none';
            app.Controls.overlayPerShot.Value = 'none';
            app.Controls.overlayPerShot.ValueChangedFcn([], []);
            results = app.runEvaluationNow(false);
            testCase.verifyFalse(results.overlayEvaluated);
            testCase.verifyEqual(string(app.Controls.mapContent.Enable), "off");
            testCase.verifyFalse(any(string(app.Controls.metric.ItemsData) == "overlayIncrease_X"));
        end

        function measurementRateRequiredShotsAndMap(testCase)
            app = testCase.App;
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.xlsx'));
            app.applyMapping();
            % 計測率で学習 Shot 数を決め、指定した shotNo と最外周の Shot を必ず計測する
            app.Controls.countBy.Value = 'rate';
            app.Controls.rateStart.Value = 10;
            app.Controls.rateEnd.Value = 40;
            app.Controls.rateStep.Value = 30;
            app.Controls.requiredShots.Value = '50, 37';
            app.Controls.requireOuter.Value = true;
            app.Controls.requireOuter.ValueChangedFcn([], []);
            sampling = app.Settings.sampling;
            testCase.verifyEqual(sampling.countBy, "rate");
            testCase.verifyEqual([sampling.rateStart, sampling.rateEnd, sampling.rateStep], [10, 40, 30]);
            testCase.verifyEqual(sampling.requiredShots, [37, 50]);
            testCase.verifyTrue(sampling.requireOuterShots);
            testCase.verifyTrue(contains(app.Controls.nShotsList.Text, "計測率：10, 40 %"));
            testCase.verifyTrue(contains(app.Controls.requiredInfo.Text, "30 Shot を必ず計測（指定 2・最外周 28"));
            testCase.verifyEqual(string(app.Controls.measurePlan.Items), ["I最適 計測率 10%", "I最適 計測率 40%"]);
            % 計測マップ（評価の前に、学習に使う Shot を Wafer 上で確かめる）
            plan = app.drawMeasurementMap(2, "I最適 計測率 40%");
            testCase.verifyEqual(plan.nShots, 40);
            testCase.verifyTrue(all(ismember([37, 50], plan.shotNos)));
            testCase.verifyEqual(numel(plan.requiredShotIndex), 30);
            names = string(get(findobj(app.Controls.measureAxes, 'Type', 'patch'), 'DisplayName'));
            testCase.verifyTrue(any(names == "必ず計測する Shot（指定・最外周など）（30）"));
            testCase.verifyTrue(any(names == "選んで計測する Shot（10）"));
            testCase.verifyTrue(startsWith(string(app.Controls.measureInfo.Value{1}), ...
                "SIM02｜I最適 計測率 40%｜計測 40 / 候補 99 Shot"));
            % 設定を変えると、古い計測マップは消える
            app.Controls.requireOuter.Value = false;
            app.Controls.requireOuter.ValueChangedFcn([], []);
            testCase.verifyEqual(string(app.Controls.measureAxes.Visible), "off");
            % すべての学習パターンの計測マップを Excel に書き出す
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's'));
            file = fullfile(folder, 'measurement_map.xlsx');
            sheet = app.exportMeasurementMap(file);
            testCase.verifyEqual(sum(sheet.("I最適 計測率 10%")), 10);
            testCase.verifyEqual(sum(sheet.("I最適 計測率 40%")), 40);
            testCase.verifyEqual(sum(sheet.("指定で必ず計測")), 2);
            testCase.verifyEqual(sum(sheet.("最外周")), 28);
            plans = readtable(file, 'Sheet', '学習パターン', 'VariableNamingRule', 'preserve', 'TextType', 'string');
            testCase.verifyEqual(plans.("学習パターン"), ["I最適 計測率 10%"; "I最適 計測率 40%"]);
            testCase.verifyEqual(plans.("学習Shot数"), [10; 40]);
            % 評価の結果も計測率ごとにまとまり、グラフの横軸は計測率
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            app.setSettings(settings);
            results = app.runEvaluationNow(false);
            testCase.verifyEqual(results.groups, ["計測率 10%", "計測率 40%"]);
            testCase.verifyEqual(unique(results.table.nShots(results.table.group == "計測率 10%")), 10);
            app.Controls.resultTabs.SelectedTab = app.Controls.chartTab;
            app.Controls.chartXAxis.Value = 'plan';
            app.Controls.chartXAxis.ValueChangedFcn([], []);
            testCase.verifyEqual(string(app.Controls.chartAxes.XLabel.String), "計測率 [%]");
            testCase.verifyEqual(app.Controls.chartAxes.XTick, [10, 40]);
            testCase.verifyTrue(all(isnan(results.table.nOutliers)), "異常値を除かない設定では NaN");
            % 学習データの異常値を除いて推定する（n は任意の正の値）
            app.Controls.excludeOutliers.Value = true;
            app.Controls.outlierSigma.Value = 2.5;
            app.Controls.outlierSigma.ValueChangedFcn([], []);
            testCase.verifyTrue(app.Settings.evaluation.excludeOutliers);
            testCase.verifyEqual(app.Settings.evaluation.outlierSigma, 2.5);
            results = app.runEvaluationNow(false);
            testCase.verifyTrue(all(isfinite(results.table.nOutliers)));
            testCase.verifyGreaterThan(sum(results.table.nOutliers), 0);
            app.showMap(1, "I最適 計測率 40%", 1, 'vector', 'estimate');
            testCase.verifyTrue(contains(app.Controls.mapInfo.Text, "学習から除いた異常値"));
            testCase.verifyNotEmpty(findobj(app.Controls.mapAxes(1), 'Type', 'line', 'DisplayName', '学習から除いた異常値'));
        end

        function groupMapsErrorBarsScatterAndPriorityFile(testCase)
            app = testCase.App;
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.xlsx'));
            app.applyMapping();
            % 読み込んだデータの平均の図（EqpId ごと）と共分散楕円
            option = find(string(app.Controls.previewWafer.Items) == "平均：EqpId = EXP01（3 枚）");
            testCase.verifyNotEmpty(option);
            app.Controls.previewWafer.Value = option;
            app.Controls.previewWafer.ValueChangedFcn([], []);
            testCase.verifyEqual(numel(findall(app.Controls.previewAxes(1), 'Type', 'patch', 'DisplayName', ...
                'Wafer 間のばらつき（1σ 楕円）')), 1);
            testCase.verifyEqual(string(app.Controls.previewAxes(1).Colorbar.Title.String), "|r|");
            testCase.verifyTrue(contains(app.Controls.previewInfo.Text, "色は X・Y の相関係数の絶対値 |r|"));
            testCase.verifyTrue(contains(app.Controls.previewInfo.Text, "EqpId = EXP01"));
            % 選んだ Wafer の全 Shot を重ね合わせたベクトル場と共分散楕円
            testCase.verifyEqual(cell2mat(app.Controls.shotOverlayWafers.Value), 1:5, "読み込むと全 Wafer を選ぶ");
            overlay = app.drawShotOverlay([1, 3]);
            testCase.verifyEqual(overlay.nWafers, 2);
            overlayAxes = app.Controls.shotOverlayAxes;
            testCase.verifyTrue(startsWith(string(overlayAxes(1).Title.String), "Wafer 2 枚"));
            ellipses = findall(overlayAxes(1), 'Type', 'patch', 'DisplayName', 'Shot・Wafer 間のばらつき（1σ 楕円）');
            testCase.verifyNotEmpty(ellipses);
            % 楕円の色は X・Y の相関係数の絶対値（楕円ごとに同じ値の頂点が並ぶ）
            covariance = overlay.average.covariance;
            expected = abs(covariance(:, 3)) ./ sqrt(covariance(:, 1) .* covariance(:, 2));
            colors = reshape(ellipses.FaceVertexCData, [], size(ellipses.Faces, 1));
            testCase.verifyEqual(colors(1, :).', expected, 'AbsTol', 1e-12);
            testCase.verifyEqual(overlayAxes(1).CLim, [0, 1]);
            testCase.verifyEqual(numel(findobj(overlayAxes(1), 'Type', 'quiver')), 2, "個々の Shot と平均");
            testCase.verifyEqual(numel(app.Controls.shotOverlayInfo.Value), 1 + 4);
            testCase.verifyEqual(app.Controls.shotOverlayAxesGrid.ColumnWidth, {'1x', 0, 0});
            app.Controls.shotOverlayWaferOrder.Value = 1;
            app.Controls.shotOverlayIndividual.Value = false;
            app.Controls.shotOverlayIndividual.ValueChangedFcn([], []);
            testCase.verifyTrue(contains(string(overlayAxes(1).Title.String), "Wafer 成分 1次を除く"));
            testCase.verifyEqual(numel(findobj(overlayAxes(1), 'Type', 'quiver')), 1);
            % Scan 方向で分けた図も並べる（同じ矢印の倍率で、すべての Shot・Scan 方向 1・2）
            overlay = app.drawShotOverlay(1:5, true);
            testCase.verifyEqual(numel(overlay), 3);
            testCase.verifyEqual([overlay(2:3).direction], [1, 2]);
            testCase.verifyEqual(overlay(2).nShots + overlay(3).nShots, overlay(1).nShots, "Shot はどちらかの Scan 方向");
            testCase.verifyEqual(app.Controls.shotOverlayAxesGrid.ColumnWidth, {'1x', '1x', '1x'});
            % 並べた図の題名は2行（Scan 方向と、除いた Wafer 成分）
            testCase.verifyEqual(string(overlayAxes(2).Title.String(1)), "Scan 方向 1（" + overlay(2).nShots + " Shot）");
            testCase.verifyEqual(string(overlayAxes(3).Title.String(2)), "Wafer 成分 1次を除く");
            testCase.verifyEqual(overlayAxes(2).XLim, overlayAxes(1).XLim);
            testCase.verifyEqual(numel(app.Controls.shotOverlayInfo.Value), 3 * (1 + 4));
            app.Controls.shotOverlayByScan.Value = false;
            app.Controls.shotOverlayByScan.ValueChangedFcn([], []);
            testCase.verifyEqual(app.Controls.shotOverlayAxesGrid.ColumnWidth, {'1x', 0, 0});
            testCase.verifyEqual(string(overlayAxes(2).Visible), "off");
            % 計測する Shot の優先順のファイル
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's'));
            file = fullfile(folder, 'priority.xlsx');
            writetable(table([50; 1; 99; (2:2:40).'], [1; 0; 1; nan(20, 1)], 'VariableNames', ["shotNo", "優先度"]), file);
            app.loadShotPriority(file);
            testCase.verifyEqual(string(app.Controls.samplingMethod.Value), "file");
            testCase.verifyTrue(contains(app.Controls.priorityInfo.Text, "必ず計測 2、計測しない 1"));
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.methods.tps.enabled = true;
            settings.sampling.nShots = [10, 20];
            app.setSettings(settings);
            results = app.runEvaluationNow(false);
            testCase.verifyEqual(unique(string({results.plans.label})), ["優先順 10 Shot", "優先順 20 Shot"]);
            plan = results.plans(1);
            testCase.verifyTrue(all(ismember([50, 99, 2, 4], plan.shotNos)) && ~any(plan.shotNos == 1));
            % グラフのエラーバー
            app.Controls.resultTabs.SelectedTab = app.Controls.chartTab;
            app.Controls.chartErrorBars.Value = 'sd';
            app.Controls.chartErrorBars.ValueChangedFcn([], []);
            testCase.verifyEqual(numel(findobj(app.Controls.chartAxes, 'Type', 'errorbar')), numel(app.Controls.chartMethods.Value));
            app.Controls.chartXAxis.Value = 'criteria';
            app.Controls.chartXAxis.ValueChangedFcn([], []);
            testCase.verifyNotEmpty(findobj(app.Controls.chartAxes2, 'Type', 'errorbar'));
            % 評価結果の平均の図（全 Wafer、Overlay 補正も）
            group = find(string(app.Controls.mapWafer.Items) == "平均：全 Wafer（5 枚）");
            app.Controls.mapWafer.Value = group;
            app.showMap(group, "優先順 20 Shot", 1, "vector", "estimate");
            testCase.verifyTrue(startsWith(app.Controls.mapInfo.Text, "平均：全 Wafer"));
            testCase.verifyEqual(string(app.Controls.mapAxes(3).Title.String), "残差（計測値 − 推定値）の平均");
            app.showMap(group, "優先順 20 Shot", 1, "vector", "overlay");
            testCase.verifyEqual(string(app.Controls.mapAxes(2).Title.String), "推定値で補正した残差の平均");
            testCase.verifyNotEmpty(findall(app.Controls.mapAxes(1), 'Type', 'patch', 'DisplayName', 'Wafer 間のばらつき（1σ 楕円）'));
            % 推定値と実測値の散布図（Mark 番号で色分け）
            summary = app.drawScatter(1, "20 Shot", 0, "mark");
            testCase.verifyEqual(numel(summary), 2);
            testCase.verifyGreaterThan(summary(1).r, 0.5);
            testCase.verifyEqual(numel(findobj(app.Controls.scatterAxes(1), 'Type', 'scatter')), 4);
            testCase.verifyTrue(contains(app.Controls.scatterInfo.Text, "Mark 番号"));
            summary = app.drawScatter(2, "10 Shot", 1, "eqp");
            testCase.verifyEqual(numel(findobj(app.Controls.scatterAxes(2), 'Type', 'scatter')), 1);
            testCase.verifyEqual(summary(1).n, nnz(results.table.unitIndex == 1 & results.table.methodIndex == 2) * 0 + ...
                results.table.nTest_X(results.table.unitIndex == 1 & results.table.methodIndex == 2 & ...
                results.table.group == "10 Shot"));
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
