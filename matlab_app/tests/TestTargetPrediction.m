classdef TestTargetPrediction < matlab.unittest.TestCase
    %TESTTARGETPREDICTION 未知の座標の推定（「6. 未知の座標の推定」）：点の読み込み・作り方、評価と同じ推定値になること、
    %   学習に無い Mark 番号・外挿の判定、Excel の書き出し、画面の流れを確かめる。

    properties
        Data
        Settings
        Methods
        Root
    end

    methods (TestClassSetup)
        function loadSample(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.Root);
            raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            testCase.Data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            testCase.Settings = alignest.defaultSettings();
            testCase.Methods = alignest.buildMethodList(alignest.recommendedMethods('all'));
        end
    end

    methods (Test)
        function targetsAtKnownMarksMatchTheEvaluation(testCase)
            % 学習しなかった Shot の Mark と同じ点を未知の座標として渡すと、評価の推定値と同じになる（質的変数も含む）
            unit = testCase.Data.units(1);
            trainShots = 1:2:numel(unit.shots.shotNo);
            marks = unit.marks;
            rows = find(~ismember(marks.shotIndex, trainShots) & marks.validX & marks.validY);
            targets = alignest.targetTemplate(numel(rows));
            targets.Xmm = marks.Xmm(rows);
            targets.Ymm = marks.Ymm(rows);
            targets.markXmm = marks.markXmm(rows);
            targets.markYmm = marks.markYmm(rows);
            targets.markNo = marks.markNo(rows);
            targets.shotNo = marks.shotNo(rows);   % Scan 方向・行の奇偶は Shot から補う
            for id = ["XY5", "TPS_XYR_backfit", "GPR_matern52_XYR_additive", "GAM_XYR", "RT5"]
                method = testCase.Methods(string({testCase.Methods.id}) == id);
                reference = alignest.estimateWafer(unit, trainShots, method, testCase.Settings);
                result = alignest.predictTargets(unit, trainShots, method, testCase.Settings, targets);
                [~, positionX] = ismember(rows, reference.testIndex.X);
                [~, positionY] = ismember(rows, reference.testIndex.Y);
                testCase.verifyEqual(result.table.estimateX, reference.estimate.X(positionX), 'AbsTol', 1e-9, id);
                testCase.verifyEqual(result.table.estimateY, reference.estimate.Y(positionY), 'AbsTol', 1e-9, id);
            end
            testCase.verifyEqual(result.table.direction, marks.direction(rows), "Scan 方向は点の Shot から補う");
            testCase.verifyFalse(any(result.table.unseenMark));
        end

        function unseenMarkUsesTheAverageEffect(testCase)
            % 学習に無い Mark 番号は、Mark 番号が空欄の点と同じ推定値（Mark 番号の効果は全 Mark の平均）
            unit = testCase.Data.units(1);
            allShots = 1:numel(unit.shots.shotNo);
            method = testCase.Methods(string({testCase.Methods.id}) == "GPR_matern52_XYR_additive");
            unseen = alignest.targetsAtShots(unit, 0, 0, 9);
            blank = alignest.targetsAtShots(unit, 0, 0);
            testCase.verifyEqual(height(unseen), numel(unit.shots.shotNo));
            testCase.verifyEqual(unseen.name(1), "S" + unit.shots.shotNo(1) + "-M9");
            first = alignest.predictTargets(unit, allShots, method, testCase.Settings, unseen);
            second = alignest.predictTargets(unit, allShots, method, testCase.Settings, blank);
            testCase.verifyEqual(first.table.estimateX, second.table.estimateX, 'AbsTol', 1e-12);
            testCase.verifyEqual(first.nUnseenMark, height(unseen));
            testCase.verifyTrue(any(contains(first.messages, "学習データに無い Mark 番号：M9")));
            testCase.verifyTrue(any(contains(first.messages, "全 Mark の平均の効果")), "Mark 番号を使う手法");
            known = alignest.targetsAtShots(unit, 0, 0, 1);
            third = alignest.predictTargets(unit, allShots, method, testCase.Settings, known);
            testCase.verifyGreaterThan(max(abs(third.table.estimateX - first.table.estimateX)), 0, ...
                "学習にある Mark 番号ならその効果を使う");
            plain = testCase.Methods(string({testCase.Methods.id}) == "XY5");
            fourth = alignest.predictTargets(unit, allShots, plain, testCase.Settings, unseen);
            testCase.verifyTrue(any(contains(fourth.messages, "Mark 番号を使わないので")));
        end

        function extrapolationIsFlagged(testCase)
            % 学習点を囲む凸包の外（0.5 mm を超える）を外挿とし、外への距離を出す（学習は内側の Shot だけ。
            % 300 mm Wafer の外の点は推定の対象外なので、Wafer の中の点で確かめる）
            unit = testCase.Data.units(1);
            method = testCase.Methods(string({testCase.Methods.id}) == "TPS_XYR");
            targets = alignest.targetTemplate(3);
            targets.name = ["中心"; "外"; "遠く"];
            targets.Xmm = [0; 0; 130];
            targets.Ymm = [0; 120; 0];
            innerShots = find(unit.shots.radius < 60);
            result = alignest.predictTargets(unit, innerShots, method, testCase.Settings, targets);
            testCase.verifyEqual(result.table.extrapolated, [false; true; true]);
            testCase.verifyEqual(result.table.outsideMm(1), 0);
            trained = ismember(unit.marks.shotIndex, innerShots) & unit.marks.validX;
            radius = max(hypot(unit.marks.x(trained), unit.marks.y(trained)));
            testCase.verifyGreaterThanOrEqual(result.table.outsideMm(3), 130 - radius - 1e-9, "凸包は学習点の円の内側");
            testCase.verifyGreaterThanOrEqual(result.table.nearestMm, result.table.outsideMm - 1e-9, ...
                "最も近い学習点は凸包より近くない");
            testCase.verifyTrue(all(isfinite([result.table.estimateX; result.table.estimateY])), "外挿でも推定値は出す");
            testCase.verifyTrue(startsWith(result.messages(1), "⚠ 外挿：2 / 3 点"));
            testCase.verifyTrue(contains(result.table.note(3), "外挿"));
            % 学習点を内側の Shot に限ると、外側の Mark の位置は外挿になる
            inner = find(unit.shots.radius < 60);
            outer = alignest.targetsAtShots(unit, 0, 0, 1);
            limited = alignest.predictTargets(unit, inner, method, testCase.Settings, outer);
            testCase.verifyFalse(any(limited.table.extrapolated(unit.shots.radius < 30)), "学習した Shot の近くは範囲内");
            testCase.verifyTrue(all(limited.table.extrapolated(unit.shots.radius > 100)), "外側の Shot は外挿");
            inside = alignest.predictTargets(unit, 1:numel(unit.shots.shotNo), method, testCase.Settings, ...
                alignest.targetGrid(20, 100));
            testCase.verifyEqual(inside.nExtrapolated, 0);
            testCase.verifyTrue(startsWith(inside.messages(1), "外挿なし"));
        end

        function pointsAreReadAndMade(testCase)
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's'));
            [targets, info] = alignest.readTargetPoints(fullfile(testCase.Root, 'sample_data', 'sample_targets.xlsx'));
            testCase.verifyEqual(info.sheet, "未知の座標");
            testCase.verifyEqual(height(targets), 10);
            testCase.verifyEqual(targets.markXmm(5:end), zeros(6, 1), "Shot 内の座標の空欄は 0");
            testCase.verifyEqual(targets.markNo(1), 5);
            % 見出しの大文字・小文字、全角の数字、名前の空欄、空の行、Direction の別名
            file = fullfile(folder, 'points.csv');
            writecell({'XMM', 'ymm', 'MarkNo', 'Scan方向'; '１０', '-5', '', '2'; '', '', '', ''; '3', '4', '7', ''}, file);
            [points, info] = alignest.readTargetPoints(file);
            testCase.verifyEqual(info.sheet, "");
            testCase.verifyEqual([points.Xmm, points.Ymm], [10, -5; 3, 4]);
            testCase.verifyEqual(points.name, ["P1"; "P2"]);
            testCase.verifyEqual(points.direction, [2; NaN]);
            testCase.verifyEqual(points.markNo, [NaN; 7]);
            bad = fullfile(folder, 'bad.csv');
            writecell({'Xmm', 'Ymm'; 'a', '1'}, bad);
            testCase.verifyError(@() alignest.readTargetPoints(bad), 'alignest:readTargetPoints');
            writecell({'X', 'Y'; '1', '1'}, bad);
            testCase.verifyError(@() alignest.readTargetPoints(bad), 'alignest:readTargetPoints', "Xmm・Ymm の列が無い");
            % 格子：半径の中だけ、上の行から
            grid = alignest.targetGrid(50, 100);
            testCase.verifyEqual(height(grid), 13);
            testCase.verifyEqual([grid.Xmm(1), grid.Ymm(1)], [0, 100]);
            testCase.verifyLessThanOrEqual(max(hypot(grid.Xmm, grid.Ymm)), 100);
            testCase.verifyError(@() alignest.targetGrid(0.1, 150), 'alignest:targetGrid', "点が多すぎる");
        end

        function estimatesAreExported(testCase)
            unit = testCase.Data.units(1);
            method = testCase.Methods(string({testCase.Methods.id}) == "XY5");
            targets = alignest.targetsAtShots(unit, 0, 0, 5);
            result = alignest.predictTargets(unit, 1:numel(unit.shots.shotNo), method, testCase.Settings, targets);
            estimates = addvars(result.table, repmat(unit.label, height(result.table), 1), 'Before', 1, ...
                'NewVariableNames', "wafer");
            file = [tempname, '.xlsx'];
            cleanup = onCleanup(@() delete(file));
            alignest.exportTargetEstimates(file, estimates, ["手法", method.label]);
            testCase.verifyEqual(string(sheetnames(file)).', ["説明", "推定値"]);
            sheet = readtable(file, 'Sheet', '推定値', 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(sheet{:, "推定値X[nm]"}, result.table.estimateX, 'AbsTol', 1e-9);
            again = alignest.readTargetPoints(file);
            testCase.verifyEqual([again.Xmm, again.Ymm, again.markNo], [targets.Xmm, targets.Ymm, targets.markNo], ...
                "書き出した推定値の Excel を、推定する点としてそのまま読める");
            testCase.verifyError(@() alignest.exportTargetEstimates([tempname, '.csv'], estimates), 'alignest:exportType');
        end

        function appWorkflow(testCase)
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            testCase.verifyEqual(app.Tabs.target.Title, '6. 未知の座標の推定');
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.xlsx'));
            app.applyMapping();
            targets = app.loadTargetPoints(fullfile(testCase.Root, 'sample_data', 'sample_targets.xlsx'));
            testCase.verifyEqual(size(app.Controls.targetTable.Data, 1), height(targets));
            app.addTargetPoints("grid", 50, 100);
            app.addTargetPoints("row");
            data = app.Controls.targetTable.Data;
            testCase.verifyEqual(size(data, 1), 10 + 13 + 1);
            testCase.verifyNotEmpty(app.Controls.targetError.Text, "空の行（Xmm・Ymm が空欄）は誤りとして出す");
            data(end, 2:3) = {'5', '５'};
            app.Controls.targetTable.Data = data;
            run = app.estimateTargets(1, "all", 1);
            testCase.verifyEqual(height(run.estimates), 24);
            testCase.verifyEqual(run.estimates.Xmm(end), 5);
            testCase.verifyEqual(run.estimates.Ymm(end), 5, "全角の数字も読む");
            testCase.verifyEqual(nnz(run.estimates.extrapolated), 2, "外周の2点だけが外挿");
            testCase.verifyTrue(any(contains(app.Controls.targetMessage.Value, "外挿")));
            testCase.verifyTrue(any(contains(app.Controls.targetMessage.Value, "M5")));
            testCase.verifyEqual(height(app.Controls.targetResultTable.Data), 24);
            testCase.verifyNotEmpty(findobj(app.Controls.targetAxes, 'DisplayName', '外挿の点（2 点）'));
            allWafers = app.estimateTargets(0, "all", 1);
            testCase.verifyEqual(height(allWafers.estimates), 24 * numel(app.Data.units));
            file = [tempname, '.xlsx'];
            removeFile = onCleanup(@() delete(file));
            app.exportTargetsTo(file);
            testCase.verifyTrue(isfile(file));
            % 評価の学習パターンを学習データにする（短く終わる設定：XY 5次・ランダム 20 Shot を1回）
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods('none');
            settings.methods.polynomial.enabled = true;
            settings.sampling.method = "random";
            settings.sampling.randomRepeats = 1;
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(20, 20, 10);
            app.setSettings(settings);
            app.runEvaluationNow(false);
            label = app.Results.plans(1).label;
            planned = app.estimateTargets(1, label, 1);
            testCase.verifyEqual(planned.trainingTexts, "学習パターン：" + label);
            testCase.verifyGreaterThanOrEqual(nnz(planned.estimates.extrapolated), nnz(run.estimates.extrapolated), ...
                "学習点が少ないほど範囲は狭い");
            % データを読み込み直すと推定値は消える
            app.applyMapping();
            testCase.verifyEmpty(app.TargetRun);
        end
    end
end
