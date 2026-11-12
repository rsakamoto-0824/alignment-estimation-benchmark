classdef TestWaferRanking < matlab.unittest.TestCase
    %TESTWAFERRANKING Wafer のベスト・平均・ワースト（alignest.waferRanking）：指標ごとの Wafer、同じ値・ランダムの繰り返し・
    %   値の無い Wafer の扱い、総合の順位、「4. 結果一覧」の「Wafer のベスト・ワースト」の表と Excel のシート。

    properties
        Root
    end

    methods (TestClassSetup)
        function addPath(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.Root);
        end
    end

    methods (Test)
        function picksWafersPerMetric(testCase)
            % 手で決めた値：RMSE のワーストは W3、OVL のワーストは W1（指標で違う）
            results = syntheticResults();
            ranking = alignest.waferRanking(results, ["RMSE_XY", "R2_XY", "overlayEstimated_X"], ...
                ["RMSE_XY", "overlayEstimated_X"]);
            testCase.verifyEqual(ranking.units, (1:4).', "評価していない W5 は除く");
            rows = ranking.table(ranking.table.methodIndex == 1, :);
            testCase.verifyEqual(rows.metric.', ["RMSE_XY", "R2_XY", "overlayEstimated_X", "overall"]);
            % RMSE：W2 は繰り返しの平均 (2 + 4) / 2 = 3。平均 2.875 に最も近いのは W2
            testCase.verifyEqual([rows.bestWafer(1), rows.averageWafer(1), rows.worstWafer(1)], ["W1", "W2", "W3"]);
            testCase.verifyEqual(rows.mean(1), 2.875, 'AbsTol', 1e-12);
            testCase.verifyEqual(rows.averageValue(1), 3, 'AbsTol', 1e-12);
            % R²：大きいほど良い
            testCase.verifyEqual([rows.bestWafer(2), rows.worstWafer(2)], ["W1", "W2"]);
            % OVL：W4 は値が無い。同じ値（W2・W3 が 4）は先の Wafer
            testCase.verifyEqual(rows.nWafers(3), 3);
            testCase.verifyEqual([rows.bestWafer(3), rows.averageWafer(3), rows.worstWafer(3)], ["W2", "W2", "W1"]);
            testCase.verifyEqual(ranking.ranks{1, 1}(:, 3), [3; 1.5; 1.5; NaN], "同じ値は順位の平均");
            testCase.verifyEqual(ranking.ranks{1, 1}(:, 1), [1; 3; 4; 2]);
            % 総合：RMSE と OVL の順位の平均（W4 は RMSE だけ）= [2, 2.25, 2.75, 2]
            testCase.verifyEqual(ranking.overallRank{1, 1}, [2; 2.25; 2.75; 2], 'AbsTol', 1e-12);
            testCase.verifyEqual([rows.bestWafer(4), rows.averageWafer(4), rows.worstWafer(4)], ["W1", "W2", "W3"]);
            % 別の手法の行は混ざらない
            other = ranking.table(ranking.table.methodIndex == 2 & ranking.table.metric == "RMSE_XY", :);
            testCase.verifyEqual([other.bestWafer, other.worstWafer], ["W4", "W1"]);
            % 総合に使う指標が無いときは、総合の Wafer を出さない
            none = alignest.waferRanking(results, ["RMSE_XY", "R2_XY"], strings(1, 0));
            last = none.table(none.table.methodIndex == 1 & none.table.metric == "overall", :);
            testCase.verifyEqual(last.bestWafer, "");
            testCase.verifyEqual(last.nWafers, 0);
        end

        function matchesPerUnitValues(testCase)
            % 評価の結果で：Wafer ごとの値は alignest.perUnitValues と同じ。ベスト・ワーストは最小・最大の値
            raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            results = alignest.runEvaluation(data, smallSettings(alignest.defaultSettings()));
            ranking = alignest.waferRanking(results);
            testCase.verifyTrue(all(ismember(["RMSE_XY", "overlayEstimated_X", "overlayActual_Y"], ranking.metrics)));
            testCase.verifyFalse(any(ranking.metrics == "seconds"), "処理時間は比べない");
            testCase.verifyEqual(ranking.overallMetrics, ["RMSE_XY", "overlayEstimated_X", "overlayEstimated_Y"]);
            for metric = ["RMSE_XY", "R2_X", "overlayEstimated_Y"]
                perUnit = alignest.perUnitValues(results, metric);
                k = ranking.metrics == metric;
                for g = 1:numel(results.groups)
                    values = ranking.values{1, g}(:, k);
                    testCase.verifyEqual(values, perUnit{1, g}(ranking.units), 'AbsTol', 1e-12);
                    row = ranking.table(ranking.table.methodIndex == 1 & ranking.table.group == results.groups(g) & ...
                        ranking.table.metric == metric, :);
                    if alignest.metricHigherIsBetter(metric)
                        testCase.verifyEqual(row.bestValue, max(values));
                    else
                        testCase.verifyEqual(row.worstValue, max(values));
                    end
                end
            end
            testCase.verifyEqual(height(ranking.table), numel(results.methods) * numel(results.groups) * ...
                (numel(ranking.metrics) + 1));
        end

        function screenShowsRanking(testCase)
            % 画面：指標ごとの表と Wafer ごとの表、総合に使う指標の選択、Excel のシート
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual(string(c.rankingMethod.Enable), "off", "結果が無いときは使わない");
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            app.setSettings(smallSettings(app.Settings));
            results = app.runEvaluationNow(false);
            ranking = app.WaferRanking;
            nMetrics = numel(ranking.metrics);
            testCase.verifyEqual(size(c.rankingTable.Data, 1), nMetrics + 1);
            testCase.verifyEqual(c.rankingTable.Data{1, 1}, '総合（順位の平均）', "総合を先に出す");
            testCase.verifyEqual(size(c.rankingWaferTable.Data), [numel(results.unitLabels), nMetrics + 2]);
            testCase.verifyTrue(contains(string(c.rankingInfo.Text), "ワースト"));
            testCase.verifyEqual(string(c.rankingOverallMetrics.Value), ranking.overallMetrics);
            % 総合を RMSE（X・Y 合計）だけにすると、総合のベストは RMSE のベストと同じ
            c.rankingOverallMetrics.Value = {'RMSE_XY'};
            c.rankingOverallMetrics.ValueChangedFcn([], []);
            rmseRow = find(app.WaferRanking.metrics == "RMSE_XY") + 1;
            testCase.verifyEqual(c.rankingTable.Data{1, 2}, c.rankingTable.Data{rmseRow, 2});
            testCase.verifyEqual(c.rankingTable.Data{1, 6}, c.rankingTable.Data{rmseRow, 6});
            % 手法・学習パターンを変える
            c.rankingGroup.Value = char(results.groups(1));
            c.rankingGroup.ValueChangedFcn([], []);
            expected = app.WaferRanking.table(app.WaferRanking.table.methodIndex == c.rankingMethod.Value & ...
                app.WaferRanking.table.group == results.groups(1) & app.WaferRanking.table.metric == "RMSE_XY", :);
            testCase.verifyEqual(string(c.rankingTable.Data{rmseRow, 2}), expected.bestWafer);
            % Excel：総合は画面で選んだ指標
            file = [tempname, '.xlsx'];
            fileCleanup = onCleanup(@() delete(file));
            app.exportResultsTo(file);
            sheet = readtable(file, 'Sheet', 'Waferのベスト・ワースト', 'VariableNamingRule', 'preserve', 'TextType', 'string');
            testCase.verifyEqual(height(sheet), height(app.WaferRanking.table));
            overall = sheet(startsWith(sheet.("指標"), "総合"), :);
            testCase.verifyEqual(unique(overall.("指標")), "総合（順位の平均：RMSE [nm]（X・Y 合計））");
            testCase.verifyEqual(numel(alignest.importResults(file).unitLabels), numel(results.unitLabels), ...
                "読み込みは変わらない");
            % 何も選ばないと総合は出さない
            c.rankingOverallMetrics.Value = {};
            c.rankingOverallMetrics.ValueChangedFcn([], []);
            testCase.verifyEqual(c.rankingTable.Data{1, 2}, '—');
            testCase.verifyTrue(contains(string(c.rankingInfo.Text), "総合に使う指標"));
        end
    end
end

function results = syntheticResults()
% 2 手法 × 1 列 × Wafer 5 枚（W5 は評価していない）。W2 は手法 1 で2回（ランダムの繰り返し）
unitIndex = [1; 2; 2; 3; 4; 1; 2; 3; 4];
methodIndex = [1; 1; 1; 1; 1; 2; 2; 2; 2];
RMSE_XY = [1; 2; 4; 5; 2.5; 9; 3; 2; 1];
R2_XY = [0.9; 0.4; 0.6; 0.7; 0.8; 0.1; 0.2; 0.3; 0.4];
overlayEstimated_X = [9; 4; 4; 4; NaN; 1; 1; 1; 1];
group = repmat("10 Shot", numel(unitIndex), 1);
results.table = table(unitIndex, methodIndex, group, RMSE_XY, R2_XY, overlayEstimated_X);
results.methods = struct("id", {"A", "B"}, "label", {"手法 A", "手法 B"});
results.groups = "10 Shot";
results.unitLabels = ["W1", "W2", "W3", "W4", "W5"];
results.evaluatedUnits = 1:4;
results.overlayEvaluated = true;
end

function settings = smallSettings(settings)
% 速く終わる評価の設定（XY 5次多項式、学習 Shot 10・20。Overlay 補正の評価は初期設定のまま）
settings.methods = alignest.recommendedMethods("none");
settings.methods.polynomial.enabled = true;
settings.sampling.nShots = [10, 20];
settings.sampling.nShotsStart = 10;
settings.sampling.nShotsEnd = 20;
settings.sampling.nShotsStep = 10;
settings.sampling.exchangeStarts = 2;
end
