classdef TestFilterExtendTiming < matlab.unittest.TestCase
    %TESTFILTEREXTENDTIMING 半径の mm 指定、評価済みの結果への条件の追加、評価点の絞り込みによる指標の計算し直し、
    %   処理時間の内訳、残差の質的変数、交換法の時間の目安を確かめる。

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
        function radiusSettingsAreAbsoluteMillimetres(testCase)
            settings = alignest.defaultSettings();
            testCase.verifyEqual(settings.sampling.constraints.radialZoneEdgesMm, [67.5, 105]);
            testCase.verifyEqual(settings.evaluation.outerRadiusMm, 120);
            testCase.verifyFalse(isfield(settings.sampling.constraints, "radialZoneEdges"));
            testCase.verifyFalse(isfield(settings.evaluation, "outerRadiusRatio"));
            % 以前の設定（Wafer 半径に対する比）は、比 × Wafer 半径 [mm] に直して読む
            legacy = jsonencode(struct("sampling", struct("constraints", struct("radialZoneEdges", [0.4, 0.8])), ...
                "evaluation", struct("outerRadiusRatio", 0.9)));
            loaded = alignest.loadSettings(legacy, "text");
            testCase.verifyEqual(loaded.sampling.constraints.radialZoneEdgesMm, [60, 120], 'AbsTol', 1e-12);
            testCase.verifyEqual(loaded.evaluation.outerRadiusMm, 135, 'AbsTol', 1e-12);
            testCase.verifyFalse(isfield(loaded.sampling.constraints, "radialZoneEdges"));
            % 区切りは 0 より大きく Wafer 半径より小さい値だけを小さい順に使う
            sampling.constraints.radialZoneEdgesMm = [105, 0, 67.5, 150, 200];
            testCase.verifyEqual(alignest.zoneEdgesMm(sampling, 150), [67.5, 105]);
            % mm の区切り [67.5, 105] は、以前の比 [0.45, 0.7] と同じ区画になる（同じ学習 Shot を選ぶ）
            unit = testCase.Data.units(1);
            spec = struct("type", "ioptimal", "nShots", 15, "rate", NaN, "repeat", 1, "label", "I最適 15 Shot", ...
                "group", "15 Shot", "shotNos", []);
            millimetres = alignest.defaultSettings().sampling;
            millimetres.exchangeStarts = 2;
            ratio = rmfield(millimetres, "constraints");
            ratio.constraints = rmfield(millimetres.constraints, "radialZoneEdgesMm");
            ratio.constraints.radialZoneEdges = [0.45, 0.7];
            planMm = alignest.planTrainingShots(unit, spec, millimetres, 150);
            planRatio = alignest.planTrainingShots(unit, spec, ratio, 150);
            testCase.verifyEqual(planMm.shotNos, planRatio.shotNos);
            testCase.verifyEqual(planMm.violation, 0);
        end

        function addingConditionsMatchesAFullEvaluation(testCase)
            settings = smallSettings();
            first = alignest.runEvaluation(testCase.Data, settings);
            % 評価の後に手法（RT）と学習 Shot 数（15）を足す。済んだ 20 件は計算しない
            more = settings;
            more.methods.rt.enabled = true;
            more.sampling.nShots = [10, 15, 20];
            extended = alignest.runEvaluation(testCase.Data, more, [], first, "extend");
            full = alignest.runEvaluation(testCase.Data, more);
            testCase.verifyEqual(height(extended.table), height(full.table));
            testCase.verifyEqual(extended.groups, ["10 Shot", "15 Shot", "20 Shot"], "学習 Shot 数の順に並べ直す");
            testCase.verifyEqual(string({extended.methods.id}), ["TPS_XYR", "XY5", "RT5"]);
            key = @(results) results.table.Wafer + "|" + results.table.plan + "|" + results.table.methodId;
            testCase.verifyEqual(key(extended), key(full), "Wafer × 学習パターン × 手法 の並びも同じ");
            testCase.verifyEqual(extended.table.RMSE_XY, full.table.RMSE_XY, 'AbsTol', 1e-12);
            testCase.verifyEqual(extended.table.planIndex, full.table.planIndex);
            testCase.verifyEqual(extended.table.methodIndex, full.table.methodIndex);
            testCase.verifyTrue(isequal({extended.plans.shotNos}, {full.plans.shotNos}));
            old = ismember(key(extended), key(first));
            testCase.verifyEqual(nnz(old), height(first.table));
            testCase.verifyEqual(extended.table.seconds(old), first.table.seconds, "済んだ行はそのまま使う");
            testCase.verifyEqual(numel(extended.additions), 1);
            testCase.verifyTrue(contains(extended.additions, "手法 1（RT5）・学習パターン 1（I最適 15 Shot）"));
            testCase.verifyTrue(extended.settings.methods.tps.enabled && extended.settings.methods.rt.enabled);
            testCase.verifyEqual(extended.runSettings, more);
            % 足すものが無い・推定の結果を変える設定を変えたときは追加できない
            testCase.verifyError(@() alignest.runEvaluation(testCase.Data, more, [], extended, "extend"), 'alignest:extend');
            changed = more;
            changed.sampling.nShots = [10, 15, 20, 25];
            changed.sampling.constraints.radialZoneEdgesMm = 80;
            changed.evaluation.outerRadiusMm = 100;
            try
                alignest.runEvaluation(testCase.Data, changed, [], extended, "extend");
                testCase.verifyFail("設定を変えたのに追加できてしまった");
            catch err
                testCase.verifyEqual(err.identifier, 'alignest:extend');
                testCase.verifyTrue(contains(err.message, "学習 Shot の選び方・制約") && contains(err.message, "評価の条件"));
            end
            testCase.verifyEmpty(alignest.extensionConflicts(settings, more), "手法と学習 Shot 数は足してよい");
        end

        function pausedAdditionResumesToTheSameResults(testCase)
            settings = smallSettings();
            first = alignest.runEvaluation(testCase.Data, settings);
            more = settings;
            more.methods.rt.enabled = true;
            more.sampling.nShots = [10, 15, 20];
            % 追加の評価を 3 件計算したところで止めても、評価済みの行は残る
            paused = alignest.runEvaluation(testCase.Data, more, @(done, ~, ~) done < height(first.table) + 3, first, ...
                "extend");
            testCase.verifyTrue(paused.cancelled);
            testCase.verifyEqual(height(paused.table), height(first.table) + 3);
            resumed = alignest.runEvaluation(testCase.Data, more, [], paused);
            full = alignest.runEvaluation(testCase.Data, more);
            testCase.verifyEqual(resumed.table.RMSE_XY, full.table.RMSE_XY, 'AbsTol', 1e-12);
            testCase.verifyFalse(resumed.cancelled);
        end

        function filterRecomputesMetricsFromStoredEstimates(testCase)
            settings = smallSettings();
            settings.overlay.waferOrder = 1;
            results = alignest.runEvaluation(testCase.Data, settings);
            testCase.verifyEqual(numel(results.pointEstimates), height(results.table));
            % すべての点を残す条件では、評価のときと同じ指標になる（計算し直しが評価と同じ式であること）
            keepAll = alignest.defaultPointFilter();
            keepAll.radiusMaxMm = 1000;
            same = alignest.filterResults(results, testCase.Data, keepAll);
            names = ["RMSE_XY", "RMSE_X", "R2_XY", "MAE_XY", "RMSE_XY_outer", "RMSE_XY_inner", "improveMeanPct_XY", ...
                "improveMedian_XY", "overlayEstimated_X", "overlayIncrease_Y", "nTest_X"];
            for name = names
                testCase.verifyEqual(same.table.(name), results.table.(name), 'AbsTol', 1e-10, name);
            end
            % 半径 100 mm 未満・Scan 方向 1 に絞った RMSE は、推定値の表を同じ条件で絞って求めた値と同じ
            filter = alignest.defaultPointFilter();
            filter.radiusMaxMm = 100;
            filter.scan = 1;
            filtered = alignest.filterResults(results, testCase.Data, filter);
            testCase.verifyEqual(filtered.filterText, "半径 0〜100 mm・Scan 方向 1");
            testCase.verifyLessThan(sum(filtered.table.nTest_X), sum(results.table.nTest_X));
            selection = struct("methodIndex", 1, "groups", "10 Shot", "unitIndex", 2);
            estimates = alignest.collectEstimates(testCase.Data, results, selection);
            keep = estimates.r < 100 & estimates.direction == 1;
            residual = [estimates.residualX(keep); estimates.residualY(keep)];
            residual = residual(isfinite(residual));
            row = filtered.table.unitIndex == 2 & filtered.table.group == "10 Shot" & filtered.table.methodIndex == 1;
            testCase.verifyEqual(filtered.table.RMSE_XY(row), sqrt(mean(residual .^ 2)), 'AbsTol', 1e-10);
            testCase.verifyEqual(filtered.table.seconds, results.table.seconds, "処理時間は変わらない");
            % 絞り込まない条件なら、そのまま返す
            testCase.verifyEqual(alignest.filterResults(results, testCase.Data, alignest.defaultPointFilter()).table, ...
                results.table);
        end

        function pointFilterConditions(testCase)
            points = struct("r", [10; 50; 90; 140], "shotNo", [1; 2; 3; 4], "direction", [1; 2; 1; NaN], ...
                "outer", [false; false; true; true]);
            filter = alignest.defaultPointFilter();
            [mask, text, active] = alignest.pointFilterMask(filter, points);
            testCase.verifyEqual(mask, true(4, 1));
            testCase.verifyEqual(text, "絞り込みなし");
            testCase.verifyFalse(active);
            filter.radiusMinMm = 20;
            filter.radiusMaxMm = 100;
            testCase.verifyEqual(alignest.pointFilterMask(filter, points), [false; true; true; false]);
            filter = alignest.defaultPointFilter();
            filter.shotMode = "exclude";
            filter.shotNos = [2, 4];
            testCase.verifyEqual(alignest.pointFilterMask(filter, points), [true; false; true; false]);
            filter.shotMode = "include";
            filter.scan = 2;
            [mask, text] = alignest.pointFilterMask(filter, points);
            testCase.verifyEqual(mask, [false; true; false; false]);
            testCase.verifyEqual(text, "shotNo 2 4 だけ・Scan 方向 2");
            filter = alignest.defaultPointFilter();
            filter.outer = "exclude";
            testCase.verifyEqual(alignest.pointFilterMask(filter, points), [true; true; false; false]);
            noOuter = rmfield(points, "outer");
            testCase.verifyError(@() alignest.pointFilterMask(filter, noOuter), 'alignest:pointFilter', ...
                "最外周が分からない点では最外周で絞り込めない");
            % Wafer の Mark では、最外周を Shot の配置から決める
            unit = testCase.Data.units(1);
            filter.outer = "only";
            mask = alignest.unitPointFilter(unit, filter);
            outerShots = alignest.outerShots(unit.shots);
            testCase.verifyEqual(mask, outerShots(unit.marks.shotIndex));
        end

        function timingBreakdownSplitsTheStages(testCase)
            settings = smallSettings();
            settings.evaluation.excludeOutliers = true;
            settings.overlay.waferOrder = 0;
            settings.overlay.shotCommon = "none";
            settings.overlay.perShot = "none";
            methods = alignest.buildMethodList(settings.methods);
            specs = alignest.buildPlanSpecs(settings.sampling);
            breakdown = alignest.timingBreakdown(testCase.Data.units(1), specs(1), methods, settings, 2);
            testCase.verifyEqual(breakdown.stages, ["plan", "outliers", "prepare", "fit", "predict", "metrics", "overlay"]);
            testCase.verifyEqual(height(breakdown.table), numel(methods));
            values = breakdown.table{:, cellstr(breakdown.stages)};
            testCase.verifyTrue(all(values(:) >= 0));
            testCase.verifyEqual(breakdown.table.total, sum(values, 2), 'AbsTol', 1e-12);
            testCase.verifyGreaterThan(breakdown.table.plan(1), 0, "I 最適の交換法の時間");
            testCase.verifyEqual(breakdown.table.plan(1), breakdown.table.plan(2), "学習パターンは手法によらない");
            testCase.verifyEqual(breakdown.table.overlay, zeros(numel(methods), 1), "Overlay 補正を評価しないなら 0");
            testCase.verifyTrue(breakdown.plan.ok);
            testCase.verifyEqual(breakdown.nTrain(1) + breakdown.nTest(1) <= numel(testCase.Data.units(1).marks.x), true);
            % 推定の時間の内訳（estimateWafer）は合計が処理時間になる
            out = alignest.estimateWafer(testCase.Data.units(1), breakdown.plan.shotIndex, methods(1), settings);
            timing = out.timing;
            testCase.verifyEqual(timing.outliers + timing.model + timing.prepare, out.seconds, 'AbsTol', 1e-9);
            % 評価点を1点にすると、推定する点だけが減る（学習点は同じ）
            marks = testCase.Data.units(1).marks;
            mask = false(numel(marks.x), 1);
            mask(find(~ismember(marks.shotIndex, breakdown.plan.shotIndex) & marks.validX & marks.validY, 1)) = true;
            single = alignest.estimateWafer(testCase.Data.units(1), breakdown.plan.shotIndex, methods(1), settings, mask);
            testCase.verifyEqual(single.trainIndex, out.trainIndex);
            testCase.verifyEqual([numel(single.testIndex.X), numel(single.testIndex.Y)], [1, 1]);
        end

        function residualFactorsMatchTheAnova(testCase)
            settings = smallSettings();
            results = alignest.runEvaluation(testCase.Data, settings);
            selection = struct("methodIndex", 1, "groups", "20 Shot", "unitIndex", 1:3);
            estimates = alignest.collectEstimates(testCase.Data, results, selection);
            factors = alignest.residualFactors(estimates);
            analysis = alignest.residualAnalysis(estimates);
            testCase.verifyEqual(string({factors.name}), unique(analysis.anova.factor, 'stable').');
            scan = factors(string({factors.name}) == "Scan 方向");
            testCase.verifyEqual(sort(unique(scan.levels)).', ["1", "2"]);
            ax = axes(figure('Visible', 'off'));
            cleanup = onCleanup(@() close(ax.Parent));
            summary = alignest.plot.residualBoxplot(ax, scan.levels, estimates.residualX, "X");
            testCase.verifyEqual(summary.level, ["1"; "2"]);
            testCase.verifyEqual(summary.mean(1), mean(estimates.residualX(scan.levels == "1"), 'omitnan'), 'AbsTol', 1e-12);
            testCase.verifyNotEmpty(findobj(ax, 'Type', 'boxchart'));
        end

        function exchangeTimeGuideIsProportional(testCase)
            testCase.verifyEqual(alignest.exchangeSecondsGuide(20, 10, 99), 2, 'AbsTol', 1e-12);
            testCase.verifyEqual(alignest.exchangeSecondsGuide([10, 40], 20, 99), [2, 8], 'AbsTol', 1e-12);
            testCase.verifyEqual(alignest.exchangeSecondsGuide(20, 10, 198), 4, 'AbsTol', 1e-12, "候補 Shot 数に比例");
        end
    end
end

function settings = smallSettings()
% 速く終わる評価の設定（TPS と XY 5次多項式、学習 Shot 10・20）
settings = alignest.defaultSettings();
settings.methods = alignest.recommendedMethods("none");
settings.methods.polynomial.enabled = true;
settings.methods.tps.enabled = true;
settings.sampling.nShots = [10, 20];
settings.sampling.nShotsStart = 10;
settings.sampling.nShotsEnd = 20;
settings.sampling.nShotsStep = 10;
settings.sampling.exchangeStarts = 2;
end
