classdef TestAbsoluteScalar < matlab.unittest.TestCase
    %TESTABSOLUTESCALAR 絶対座標だけで定義した計測データと、1つの列（膜厚・線幅など）を1変数として推定することを確かめる。

    properties
        Root
        Raw          % 計測データの見本（Shot 中心＋Shot 内の位置、X・Y 成分）
        Mapping
        Thickness    % 膜厚の見本（絶対座標だけ、1変数）
    end

    methods (TestClassSetup)
        function loadSamples(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.Root);
            testCase.Raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            testCase.Mapping = alignest.guessColumnMapping(testCase.Raw.Properties.VariableNames);
            testCase.Thickness = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_thickness.csv'));
        end
    end

    methods (Test)
        function absoluteCoordinatesKeepTheShots(testCase)
            % 絶対座標（Xmm・Ymm の列 = 点の座標）でも、Shot 内の位置か shotNo があれば元と同じ Shot・Mark になる
            reference = alignest.prepareData(testCase.Raw, testCase.Mapping);
            raw = testCase.Raw;
            raw.Xmm = raw.Xmm + raw.markXmm;
            raw.Ymm = raw.Ymm + raw.markYmm;
            withOffsets = alignest.prepareData(raw, testCase.Mapping, coordinateMode="absolute");
            mapping = testCase.Mapping;
            [mapping.markXmm, mapping.markYmm] = deal("");
            withShotNo = alignest.prepareData(raw, mapping, coordinateMode="absolute");
            for data = [withOffsets, withShotNo]
                unit = data.units(1);
                expected = reference.units(1);
                testCase.verifyEqual([unit.marks.x, unit.marks.y], [expected.marks.x, expected.marks.y], 'AbsTol', 1e-9);
                testCase.verifyEqual([unit.shots.Xmm, unit.shots.Ymm], [expected.shots.Xmm, expected.shots.Ymm], 'AbsTol', 1e-9);
                testCase.verifyEqual(unit.marks.shotIndex, expected.marks.shotIndex);
                testCase.verifyEqual(unit.marks.measX, expected.marks.measX);
            end
            testCase.verifyEqual(withShotNo.units(1).marks.markXmm, reference.units(1).marks.markXmm, 'AbsTol', 1e-9, ...
                "shotNo の点の平均が Shot 中心（見本の Mark は Shot 中心に対称）");
            testCase.verifyTrue(any(contains(withShotNo.summary.messages, "同じ Wafer・shotNo の点の平均")));
            testCase.verifyEqual(withShotNo.coordinateMode, "absolute");
            testCase.verifyError(@() alignest.prepareData(raw, mapping), 'alignest:missingColumn', ...
                "Shot 中心＋Shot 内の位置では markXmm・markYmm が必須");
        end

        function pointsWithoutShotsAreSingleShots(testCase)
            % Shot の情報が無い絶対座標の点は、1点ずつの Shot（Mark 番号 1、Scan 方向なし、枠は隣の点と重ならない大きさ）
            mapping = alignest.guessColumnMapping(testCase.Thickness.Properties.VariableNames);
            data = alignest.prepareData(testCase.Thickness, mapping, coordinateMode="absolute", ...
                valueColumn="Thickness_nm", directionRule="serpentine");
            unit = data.units(1);
            testCase.verifyEqual(numel(data.units), 5);
            testCase.verifyEqual(numel(unit.shots.Xmm), 109);
            testCase.verifyEqual(numel(unit.marks.x), 109);
            testCase.verifyEqual(unique(unit.marks.markNo), 1);
            testCase.verifyEqual([unit.marks.markXmm, unit.marks.markYmm], zeros(109, 2));
            testCase.verifyFalse(unit.hasDirection, "点ごとの Shot には Scan 方向の並びが無い");
            nearest = min(hypot(unit.marks.x(2:end) - unit.marks.x(1), unit.marks.y(2:end) - unit.marks.y(1)));
            testCase.verifyLessThan(unit.shotSizeMm(1), 25, "枠は点の間隔より小さい");
            testCase.verifyGreaterThan(unit.shotSizeMm(1), 0.3 * nearest);
            testCase.verifyTrue(any(contains(data.summary.messages, "点を1つずつ Shot として扱います")));
        end

        function valueColumnIsTheOnlyComponent(testCase)
            mapping = alignest.guessColumnMapping(testCase.Thickness.Properties.VariableNames);
            data = alignest.prepareData(testCase.Thickness, mapping, coordinateMode="absolute", valueColumn="Thickness_nm");
            unit = data.units(1);
            rows = testCase.Thickness.Wafer == "THK01-01";
            testCase.verifyEqual(sort(unit.marks.measX), sort(testCase.Thickness.Thickness_nm(rows)));
            testCase.verifyFalse(any(unit.marks.validY), "1変数は Y 成分を使わない");
            testCase.verifyEqual(data.attributeNames, "Chamber", "推定する値の列は質的変数の候補にしない");
            testCase.verifyEqual(data.valueColumn, "Thickness_nm");
            columns = alignest.standardColumns("absolute", "Thickness_nm");
            required = string({columns([columns.required]).name});
            testCase.verifyEqual(required, ["Xmm", "Ymm"]);
            testCase.verifyError(@() alignest.prepareData(testCase.Thickness, mapping, coordinateMode="absolute", ...
                valueColumn="NoSuchColumn"), 'alignest:valueColumn');
            mapping.Wafer = "Thickness_nm";
            testCase.verifyError(@() alignest.prepareData(testCase.Thickness, mapping, coordinateMode="absolute", ...
                valueColumn="Thickness_nm"), 'alignest:valueColumn', "標準の項目にも対応づけた列は使えない");
            spec = alignest.valueSpec(struct("valueColumn", "Thickness_nm", "valueUnit", "Å"));
            testCase.verifyTrue(spec.scalar);
            testCase.verifyEqual([spec.name, spec.unit, spec.components], ["Thickness_nm", "Å", "X"]);
            testCase.verifyFalse(alignest.valueSpec(alignest.defaultSettings().data).scalar);
        end

        function scalarEstimatesMatchTheXComponent(testCase)
            % 1変数として推定した値は、同じ値を X 成分にした2成分の推定の X と同じ（質的変数を使う手法も）
            raw = testCase.Raw;
            raw.Value = raw.measX;
            raw.Value(raw.StsX ~= 0) = NaN;   % 1変数ではステータスの列を使わないので、無効な値を空にしておく
            vector = alignest.prepareData(raw, testCase.Mapping, directionRule="serpentine");
            scalar = alignest.prepareData(raw, testCase.Mapping, directionRule="serpentine", valueColumn="Value");
            settings = alignest.defaultSettings();
            methods = alignest.buildMethodList(alignest.recommendedMethods('all'));
            ids = string({methods.id});
            unitVector = vector.units(1);
            unitScalar = scalar.units(1);
            shots = 1:3:numel(unitVector.shots.shotNo);
            for id = ["XY5", "TPS_XYR_backfit", "GPR_matern52_XYR_additive", "GAM_XYR", "FringeZ_k4"]
                method = methods(ids == id);
                expected = alignest.estimateWafer(unitVector, shots, method, settings);
                actual = alignest.estimateWafer(unitScalar, shots, method, settings);
                testCase.verifyEqual(actual.testIndex.X, expected.testIndex.X, id);
                testCase.verifyEqual(actual.estimate.X, expected.estimate.X, 'AbsTol', 1e-9, id);
                testCase.verifyEmpty(actual.estimate.Y, id);
            end
            testCase.verifyError(@() alignest.estimateWafer(unitScalar, shots, methods(ids == "RT5"), settings), ...
                'alignest:rtNeedsXY');
        end

        function scalarEvaluationUsesOneComponent(testCase)
            mapping = alignest.guessColumnMapping(testCase.Thickness.Properties.VariableNames);
            data = alignest.prepareData(testCase.Thickness, mapping, coordinateMode="absolute", valueColumn="Thickness_nm");
            settings = alignest.defaultSettings();
            settings.data.coordinateMode = "absolute";
            settings.data.valueColumn = "Thickness_nm";
            settings.data.valueUnit = "nm";
            settings.methods = alignest.recommendedMethods('none');
            settings.methods.polynomial.enabled = true;
            settings.methods.tps.enabled = true;
            settings.methods.rt.enabled = true;
            settings.overlay.waferOrder = 1;
            settings.sampling.method = "ioptimal";
            settings.sampling.nShots = [20, 40];
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(20, 40, 20);
            [methods, note] = alignest.activeMethods(settings);
            testCase.verifyEqual(string({methods.id}), ["TPS_XYR", "XY5"]);
            testCase.verifyTrue(contains(note, "RT モデル"));
            testCase.verifyFalse(alignest.overlayChoice(settings).enabled, "1変数では Overlay 補正を評価しない");
            results = alignest.runEvaluation(data, settings);
            table_ = results.table;
            testCase.verifyEqual(height(table_), 5 * 2 * 2);
            testCase.verifyEqual(table_.RMSE_XY, table_.RMSE_X, 'AbsTol', 1e-12);
            testCase.verifyTrue(all(isnan(table_.RMSE_Y)));
            testCase.verifyTrue(all(isfinite(table_.improveMeanPct_XY)), "平均値に対する改善も1変数で求める");
            testCase.verifyLessThan(mean(table_.RMSE_XY(table_.methodId == "TPS_XYR")), 0.3);
            [names, labels] = alignest.metricNames(true, true, alignest.valueSpec(settings.data));
            testCase.verifyFalse(any(endsWith(names, ["_X", "_Y"])));
            testCase.verifyFalse(any(startsWith(names, "ovl")), "Overlay の指標は出さない");
            testCase.verifyEqual(labels(names == "RMSE_XY"), "RMSE [nm]（Thickness_nm）");
            [fullNames, ~] = alignest.metricNames(true, true);
            testCase.verifyTrue(all(ismember(["RMSE_X", "RMSE_Y"], fullNames)), "2成分は今までどおり");
        end

        function appWorkflowWithThickness(testCase)
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_thickness.csv'));
            c = app.Controls;
            testCase.verifyTrue(any(strcmp(c.valueColumn.ItemsData, 'Thickness_nm')));
            c.coordinateMode.Value = 'absolute';
            c.coordinateMode.ValueChangedFcn([], []);
            c.valueColumn.Value = 'Thickness_nm';
            c.valueColumn.ValueChangedFcn([], []);
            requirement = string(c.mapping.Data(:, 3));
            items = string(c.mapping.Data(:, 1));
            testCase.verifyEqual(requirement(ismember(items, ["Xmm", "markXmm", "measX"])), ["必須"; "任意"; "任意"]);
            app.applyMapping();
            testCase.verifyEqual(numel(app.Data.units), 5);
            testCase.verifyEqual(c.previewAxesGrid.ColumnWidth, {'1x', 0, 0}, "1変数は値の色の図を1枚");
            testCase.verifyEqual(string(c.rt.Enable), "off");
            testCase.verifyEqual(string(c.overlayWafer.Enable), "off");
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods('none');
            settings.methods.polynomial.enabled = true;
            settings.sampling.method = "random";
            settings.sampling.randomRepeats = 1;
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(30, 30, 10);
            app.setSettings(settings);
            results = app.runEvaluationNow(false);
            testCase.verifyTrue(any(contains(string(c.metric.Items), "Thickness_nm")));
            testCase.verifyFalse(any(endsWith(string(c.metric.ItemsData), "_Y")));
            app.showMap(1, results.plans(1).label, 1, 'X', 'estimate');
            testCase.verifyEqual(string(c.mapMode.Items), "Thickness_nm（色）");
            testCase.verifyTrue(contains(c.mapInfo.Text, "RMSE（Thickness_nm）"));
            app.addTargetPoints("grid", 50, 100);
            run = app.estimateTargets(1, "all", 1);
            testCase.verifyTrue(all(isfinite(run.estimates.estimateX)));
            testCase.verifyTrue(any(strcmp(c.targetResultTable.Data.Properties.VariableNames, '推定値 Thickness_nm [nm]')));
            % 設定の保存・読み込みで、座標の定義・推定する値も戻る
            file = [tempname, '.json'];
            removeFile = onCleanup(@() delete(file));
            alignest.saveSettings(app.Settings, file);
            loaded = alignest.loadSettings(file);
            testCase.verifyEqual([loaded.data.coordinateMode, loaded.data.valueColumn, loaded.data.valueUnit], ...
                ["absolute", "Thickness_nm", "nm"]);
            app.setSettings(alignest.defaultSettings());
            testCase.verifyEqual(string(c.valueColumn.Value), "", "初期設定は X・Y 成分");
            testCase.verifyEmpty(app.Data, "推定する値が変わったので読み込み直す");
        end
    end
end
