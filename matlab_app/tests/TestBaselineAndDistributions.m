classdef TestBaselineAndDistributions < matlab.unittest.TestCase
    %TESTBASELINEANDDISTRIBUTIONS 平均値・中央値をそのまま推定値にした場合との改善量・改善率と、
    %   分布の比較（代表統計値・JS ダイバージェンス）を確かめる。1 Mark の最大誤差・最小誤差（ワースト・ベストの Mark）も。

    properties
        Data
        Results
    end

    methods (TestClassSetup)
        function evaluateSample(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            addpath(root);
            raw = alignest.readMeasurementFile(fullfile(root, 'sample_data', 'sample_alignment.csv'));
            testCase.Data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            settings = alignest.defaultSettings();
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.methods.tps.enabled = true;
            settings.sampling.nShots = [15, 30];
            settings.sampling.nShotsStart = 15;
            settings.sampling.nShotsEnd = 30;
            settings.sampling.nShotsStep = 15;
            testCase.Results = alignest.runEvaluation(testCase.Data, settings);
        end
    end

    methods (Test)
        function baselineUsesTrainingMeanOrMedian(testCase)
            truthX = [1; 2; 3];
            truthY = [0; 4];
            trainX = [0; 2; 10];   % 平均 4、中央値 2
            trainY = [1; 3];       % 平均 2、中央値 2
            baseline = alignest.baselineImprovement(truthX, truthY, trainX, trainY, "mean", 1);
            expected = sqrt(mean([truthX - 4; truthY - 2] .^ 2));
            testCase.verifyEqual(baseline.rmse, expected, 'AbsTol', 1e-12);
            testCase.verifyEqual(baseline.improvement, expected - 1, 'AbsTol', 1e-12);
            testCase.verifyEqual(baseline.percent, 100 * (expected - 1) / expected, 'AbsTol', 1e-12);
            median_ = alignest.baselineImprovement(truthX, truthY, trainX, trainY, "median", 1);
            testCase.verifyEqual(median_.rmse, sqrt(mean([truthX - 2; truthY - 2] .^ 2)), 'AbsTol', 1e-12);
            testCase.verifyTrue(isnan(alignest.baselineImprovement(truthX, truthY, NaN, trainY, "mean", 1).rmse));
            % 指標の名前と良い向き（改善量・改善率は大きいほど良い）
            names = alignest.metricNames();
            testCase.verifyTrue(all(ismember(["RMSE_XY_baseMean", "improveMean_XY", "improveMeanPct_XY", ...
                "RMSE_XY_baseMedian", "improveMedian_XY", "improveMedianPct_XY"], names)));
            testCase.verifyTrue(alignest.metricHigherIsBetter("improveMeanPct_XY"));
            testCase.verifyTrue(alignest.metricHigherIsBetter("R2_XY"));
            testCase.verifyFalse(alignest.metricHigherIsBetter("RMSE_XY_baseMean"));
        end

        function evaluationRecordsImprovementOverMeanAndMedian(testCase)
            table_ = testCase.Results.table;
            testCase.verifyTrue(all(isfinite(table_.improveMeanPct_XY)));
            testCase.verifyEqual(table_.improveMean_XY, table_.RMSE_XY_baseMean - table_.RMSE_XY, 'AbsTol', 1e-12);
            testCase.verifyEqual(table_.improveMedianPct_XY, ...
                100 * (table_.RMSE_XY_baseMedian - table_.RMSE_XY) ./ table_.RMSE_XY_baseMedian, 'AbsTol', 1e-9);
            % 1行を学習点から直接計算して確かめる
            row = table_(1, :);
            plan = testCase.Results.plans(row.planIndex);
            unit = testCase.Data.units(row.unitIndex);
            out = alignest.estimateWafer(unit, plan.shotIndex, testCase.Results.methods(row.methodIndex), ...
                testCase.Results.settings);
            marks = unit.marks;
            errors = [marks.measX(out.testIndex.X) - mean(marks.measX(out.trainIndex.X)); ...
                marks.measY(out.testIndex.Y) - mean(marks.measY(out.trainIndex.Y))];
            testCase.verifyEqual(row.RMSE_XY_baseMean, sqrt(mean(errors .^ 2)), 'AbsTol', 1e-10);
            % 推定は平均値より良い（模擬データには場の形があるので）。集計の最良は改善率が大きいほう
            testCase.verifyGreaterThan(mean(table_.improveMeanPct_XY), 0);
            summary = alignest.summarizeResults(testCase.Results, "improveMeanPct_XY", "worst");
            testCase.verifyFalse(summary.lowerIsBetter);
            perUnit = alignest.perUnitValues(testCase.Results, "improveMeanPct_XY");
            testCase.verifyEqual(summary.values(1, 1), min(perUnit{1, 1}), 'AbsTol', 1e-12, "ワーストは最も小さい改善率");
        end

        function perMarkWorstAndBestErrors(testCase)
            % 1 Mark の最大誤差・最小誤差：|計測値 − 推定値| の最大と最小。XY は X と Y の誤差をまとめた中の最大・最小
            metrics = alignest.computeMetrics([1; 2; 3], [1.5; 2; 1], NaN, [0; 0], [1; -3], NaN, false(3, 1), false(2, 1));
            testCase.verifyEqual([metrics.MaxAE_X, metrics.MinAE_X], [2, 0], 'AbsTol', 1e-12);
            testCase.verifyEqual([metrics.MaxAE_Y, metrics.MinAE_Y], [3, 1], 'AbsTol', 1e-12);
            testCase.verifyEqual([metrics.MaxAE_XY, metrics.MinAE_XY], [3, 0], 'AbsTol', 1e-12);
            empty = alignest.computeMetrics(zeros(0, 1), zeros(0, 1), NaN, zeros(0, 1), zeros(0, 1), NaN, false(0, 1), ...
                false(0, 1));
            testCase.verifyTrue(isnan(empty.MaxAE_XY) && isnan(empty.MinAE_X), "評価点が無ければ NaN");
            % 指標の名前（小さいほど良い）。1変数では X・Y 合計の列だけを値の名前で出す
            [names, labels] = alignest.metricNames();
            testCase.verifyTrue(all(ismember(["MaxAE_X", "MaxAE_Y", "MaxAE_XY", "MinAE_X", "MinAE_Y", "MinAE_XY"], names)));
            testCase.verifyEqual(labels(names == "MaxAE_XY"), "1 Mark の最大誤差 [nm]（X・Y 合計）");
            testCase.verifyFalse(any(alignest.metricHigherIsBetter(["MaxAE_XY", "MinAE_XY"])));
            scalarSpec = alignest.valueSpec(struct("valueColumn", "Thickness_nm", "valueUnit", "nm"));
            [scalarNames, scalarLabels] = alignest.metricNames(false, false, scalarSpec);
            testCase.verifyTrue(any(scalarNames == "MinAE_XY") && ~any(scalarNames == "MinAE_X"));
            testCase.verifyEqual(scalarLabels(scalarNames == "MinAE_XY"), "1 Mark の最小誤差 [nm]（Thickness_nm）");
            % 評価の結果：1行を評価点から直接計算して確かめる
            table_ = testCase.Results.table;
            testCase.verifyTrue(all(table_.MaxAE_XY >= table_.RMSE_XY - 1e-12 & table_.RMSE_XY >= table_.MinAE_XY - 1e-12));
            row = table_(1, :);
            plan = testCase.Results.plans(row.planIndex);
            unit = testCase.Data.units(row.unitIndex);
            out = alignest.estimateWafer(unit, plan.shotIndex, testCase.Results.methods(row.methodIndex), ...
                testCase.Results.settings);
            marks = unit.marks;
            errorX = abs(marks.measX(out.testIndex.X) - out.estimate.X);
            errorY = abs(marks.measY(out.testIndex.Y) - out.estimate.Y);
            testCase.verifyEqual([row.MaxAE_X, row.MinAE_X], [max(errorX), min(errorX)], 'AbsTol', 1e-10);
            testCase.verifyEqual([row.MaxAE_XY, row.MinAE_XY], [max([errorX; errorY]), min([errorX; errorY])], ...
                'AbsTol', 1e-10);
            % Wafer のベスト・ワーストの指標に入る
            ranking = alignest.waferRanking(testCase.Results);
            testCase.verifyTrue(all(ismember(["MaxAE_XY", "MinAE_XY", "MaxAE_X", "MinAE_Y"], ranking.metrics)));
            worstRow = ranking.table(ranking.table.metric == "MaxAE_XY", :);
            perUnit = alignest.perUnitValues(testCase.Results, "MaxAE_XY");
            testCase.verifyEqual(worstRow.worstValue(1), max(perUnit{1, 1}), 'AbsTol', 1e-12, ...
                "ワーストの Wafer は最大誤差が最も大きい Wafer");
            testCase.verifyEqual(worstRow.bestValue(1), min(perUnit{1, 1}), 'AbsTol', 1e-12);
        end

        function jsDivergenceMeasuresOverlap(testCase)
            edges = [0, 1, 2];
            testCase.verifyEqual(alignest.stats.jsDivergence([0.5; 1.5], [0.2; 1.2], edges), 0, 'AbsTol', 1e-12);
            testCase.verifyEqual(alignest.stats.jsDivergence([0.5; 0.5], [1.5; 1.5], edges), 1, 'AbsTol', 1e-12);
            % P = [1, 0]、Q = [0.5, 0.5] → M = [0.75, 0.25]
            expected = (log2(1 / 0.75) + 0.5 * log2(0.5 / 0.75) + 0.5 * log2(0.5 / 0.25)) / 2;
            testCase.verifyEqual(alignest.stats.jsDivergence([0.5; 0.6], [0.5; 1.5], edges), expected, 'AbsTol', 1e-12);
            testCase.verifyTrue(isnan(alignest.stats.jsDivergence([], [0.5], edges)));
            summary = alignest.stats.distributionSummary([1; 2; 3; 10; NaN]);
            testCase.verifyEqual([summary.n, summary.mean, summary.median, summary.min, summary.max], [4, 4, 2.5, 1, 10]);
            testCase.verifyEqual(summary.meanPlus3Sigma, 4 + 3 * std([1, 2, 3, 10]), 'AbsTol', 1e-12);
        end

        function distributionsOfWholeTrainingTargetAndEstimate(testCase)
            results = testCase.Results;
            selection = struct("methodIndex", 1, "groups", "15 Shot", "unitIndex", [1, 2]);
            estimates = alignest.collectEstimates(testCase.Data, results, selection);
            comparison = alignest.distributionComparison(testCase.Data, results, selection, estimates);
            x = comparison.X;
            testCase.verifyEqual(x.names, ["全面", "学習", "予測対象（実測）", "推定値"]);
            wholeCount = sum(arrayfun(@(u) nnz(testCase.Data.units(u).marks.validX), [1, 2]));
            testCase.verifyEqual(x.stats.n(1), wholeCount);
            testCase.verifyEqual(x.stats.n(3), nnz(isfinite(estimates.measX)));
            testCase.verifyEqual(x.stats.n(2) + x.stats.n(3), wholeCount, "学習と予測対象で全面になる");
            testCase.verifyEqual(x.stats.mean(4), mean(estimates.estimateX, 'omitnan'), 'AbsTol', 1e-12);
            testCase.verifyEqual(height(x.js), 4);
            testCase.verifyEqual(x.js.js(4), alignest.stats.jsDivergence(x.samples{3}, x.samples{4}, x.edges), ...
                'AbsTol', 1e-12);
            testCase.verifyTrue(all(x.js.js >= 0 & x.js.js <= 1));
            testCase.verifyEqual(comparison.nWafers, 2);
            % 学習データの異常値を除く設定なら、学習の分布からも除く
            results.settings.evaluation.excludeOutliers = true;
            results.settings.evaluation.outlierSigma = 2;
            cleaned = alignest.distributionComparison(testCase.Data, results, selection, estimates);
            testCase.verifyLessThan(cleaned.X.stats.n(2), x.stats.n(2));
        end
    end
end
