classdef TestShotHighOrderSweep < matlab.unittest.TestCase
    %TESTSHOTHIGHORDERSWEEP Shot 高次補正（「7. Shot高次補正」）の λ・c のスイープ：1点抜きの予測の誤差（最小二乗では
    %   求め直した値と同じ）、当てはめた残差と 1点抜きの誤差の推移、範囲と刻み、途中で止める、画面（図・表・最もよい値を使う）。

    properties
        Root
        Grid      % 合成の Wafer の Shot 中心と Shot 内の点
    end

    methods (TestClassSetup)
        function addPath(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.Root);
            centers = zeros(0, 2);
            for cx = -130:26:130
                for cy = -132:33:132
                    if hypot(cx, cy) < 125
                        centers(end + 1, :) = [cx, cy]; %#ok<AGROW>
                    end
                end
            end
            [lx, ly] = meshgrid(linspace(-12, 12, 7), linspace(-15, 15, 11));   % 1 Shot 7 × 11 点
            testCase.Grid = struct("centers", centers, "local", [lx(:), ly(:)]);
        end
    end

    methods (Test)
        function leaveOneOutMatchesRefitForLeastSquares(testCase)
            % 最小二乗では、1点抜きの予測の誤差は、その点を除いて当てはめ直したときの誤差と同じ
            points = noisyWafer(testCase, 3);
            settings = alignest.defaultSettings();
            settings.highOrder = struct("maker", "custom", "excludedTerms", 13:38, "unit", "shot", "waferOrder", 0, ...
                "loss", "ols", "regularization", "none");
            result = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            terms = alignest.highOrderTerms("custom", 13:38);
            terms = terms(terms.axis == "dx" & terms.used, :);
            rows = find(points.shotNo == 4);
            design = points.localX(rows) .^ (terms.xPower.') .* points.localY(rows) .^ (terms.yPower.');
            for i = [1, 30, 77]
                others = setdiff(1:numel(rows), i);
                coefficients = design(others, :) \ points.valueX(rows(others));
                expected = points.valueX(rows(i)) - design(i, :) * coefficients;
                testCase.verifyEqual(result.points.looResidualX(rows(i)), expected, 'AbsTol', 1e-9);
            end
        end

        function sweepShowsFitAndLeaveOneOutTrend(testCase)
            % λ を大きくすると当てはめた残差は増える。1点抜きの誤差は当てはめた残差より大きい。強すぎる λ は
            % 1点抜きの誤差も大きくする（本当にある高次の項まで小さくするため）。正則化なしの設定なら L2 にする
            points = noisyWafer(testCase, 5);
            settings = alignest.defaultSettings();
            settings.highOrder = struct("maker", "custom", "excludedTerms", 13:38, "unit", "common", "waferOrder", 0, ...
                "loss", "ols", "regularization", "none");
            wafer = struct("label", "W1", "points", points);
            lambdas = [0, 0.1, 1, 10, 100];
            sweep = alignest.sweepHighOrder(wafer, settings, lambda=lambdas);
            testCase.verifyEqual([sweep.parameter, sweep.regularization, sweep.loss], ["lambda", "l2", "ols"]);
            testCase.verifyEqual(height(sweep.table), 2 * numel(lambdas));
            x = sweep.table(sweep.table.axis == "X", :);
            testCase.verifyEqual(x.lambda, lambdas.');
            testCase.verifyGreaterThanOrEqual(diff(x.fitRms), -1e-9, "当てはめた残差は λ とともに増える");
            testCase.verifyGreaterThanOrEqual(x.looRms - x.fitRms, -1e-12, "1点抜きの誤差は当てはめた残差以上");
            testCase.verifyGreaterThan(x.looMeanPlus3Sigma(end), x.looMeanPlus3Sigma(1), "強すぎる λ は予測も悪くする");
            testCase.verifyEqual(x.n, repmat(height(points), numel(lambdas), 1));
            % Huber の c：損失関数を Huber にする。λ と c の組み合わせはすべての組
            tuning = alignest.sweepHighOrder(wafer, settings, huberTuning=[0.5, 1, 2]);
            testCase.verifyEqual([tuning.parameter, tuning.loss], ["huberTuning", "huber"]);
            testCase.verifyEqual(unique(tuning.table.huberTuning).', [0.5, 1, 2]);
            both = alignest.sweepHighOrder(wafer, settings, lambda=[0, 1], huberTuning=[1, 2]);
            testCase.verifyEqual(both.parameter, "both");
            testCase.verifyEqual(height(both.table), 2 * 4);
            % 途中で止める
            stopped = alignest.sweepHighOrder(wafer, settings, lambda=lambdas, progressFcn=@(done, ~, ~) done < 2);
            testCase.verifyTrue(stopped.cancelled);
            testCase.verifyEqual(stopped.nRuns, 2);
            testCase.verifyEqual(height(stopped.table), 2 * 2);
            % 誤り
            testCase.verifyError(@() alignest.sweepHighOrder(wafer, settings), 'alignest:highOrderSweep');
            testCase.verifyError(@() alignest.sweepHighOrder(wafer, settings, lambda=-1), 'alignest:highOrderSweep');
            testCase.verifyError(@() alignest.sweepHighOrder(wafer, settings, lambda=1:21, huberTuning=1:20), ...
                'alignest:highOrderSweep', "値の組が多すぎる");
        end

        function screenSweepsAndAppliesBest(testCase)
            % 画面：範囲と刻み（対数・等間隔）、計算する数、スイープの図と表、最もよい値を使う、設定を変えた後の知らせ
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual([c.highOrderTuneLambdaStart.Value, c.highOrderTuneLambdaEnd.Value, ...
                c.highOrderTuneLambdaStep.Value], [0.001, 10, 0.25]);
            testCase.verifyTrue(startsWith(string(c.highOrderTuneCount.Text), "λ 17 通り（0.001〜10）"));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            app.setHighOrderSource("data");
            app.setHighOrderSettings(unit="common", lambda=0.1);
            c.highOrderWafer.Value = {1, 2};
            sweep = app.sweepHighOrderParameters("lambda", lambdaRange=[0.01, 1, 1], lambdaScale="log");
            testCase.verifyEqual(sweep.lambda, [0.01, 0.1, 1]);
            testCase.verifyEqual(height(c.highOrderTuneTable.Data), 3);
            testCase.verifyEqual(c.highOrderTuneTable.Data.("λ"), [0.01; 0.1; 1]);
            testCase.verifyEqual(numel(findobj(c.highOrderTuneAxes(1), 'Type', 'line')), 3, "当てはめ・1点抜き・最小");
            testCase.verifyEqual(string(c.highOrderTuneAxes(1).XScale), "log");
            testCase.verifyTrue(contains(string(c.highOrderTuneInfo.Text), "1点抜きの予測の誤差の |平均|+3σ が最小"));
            best = app.applyHighOrderSweepBest();
            testCase.verifyTrue(ismember(best.lambda, sweep.lambda));
            testCase.verifyEqual(app.Settings.highOrder.lambda, best.lambda);
            % 等間隔の刻みは終了も入れる。対数で 0 から始めると知らせる
            app.sweepHighOrderParameters("huberTuning", tuningRange=[1, 2, 0.4]);
            testCase.verifyEqual(app.HighOrderSweep.huberTuning, [1, 1.4, 1.8, 2]);
            testCase.verifyEqual(app.Settings.highOrder.loss, "huber");
            c.highOrderTuneParameter.Value = 'lambda';
            c.highOrderTuneLambdaStart.Value = 0;
            c.highOrderTuneLambdaStart.ValueChangedFcn(c.highOrderTuneLambdaStart, []);
            testCase.verifyTrue(startsWith(string(c.highOrderTuneCount.Text), "⚠"));
            testCase.verifyError(@() app.sweepHighOrderParameters("lambda"), 'alignest:highOrderSweep');
            % λ と c の組み合わせは色の図
            app.sweepHighOrderParameters("both", lambdaRange=[0, 1, 1], lambdaScale="linear", tuningRange=[1, 2, 1]);
            testCase.verifyNotEmpty(findobj(c.highOrderTuneAxes(2), 'Type', 'image'));
            testCase.verifyEqual(height(c.highOrderTuneTable.Data), 4);
            % 入力・設定を変えた後は、スイープし直す知らせ
            app.setHighOrderSettings(unit="shot");
            app.drawHighOrderSweep();
            testCase.verifyTrue(startsWith(string(c.highOrderTuneInfo.Text), "⚠ スイープの後に"));
        end
    end
end

function points = noisyWafer(testCase, seed)
% 合成の Wafer（1 Shot 77 点）：Shot 内の 1次・2次の項（dx は x^2 と x·y、dy は y^2）＋ Shot ごとに同じ雑音の大きさ
centers = testCase.Grid.centers;
local = testCase.Grid.local;
nShots = size(centers, 1);
nMarks = size(local, 1);
L = repmat(local, nShots, 1);
rng(seed);
valueX = 0.5 + 0.02 * L(:, 1) - 0.01 * L(:, 2) + 0.004 * L(:, 1) .^ 2 + 0.002 * L(:, 1) .* L(:, 2) + ...
    0.3 * randn(nShots * nMarks, 1);
valueY = -0.3 + 0.01 * L(:, 2) + 0.015 * L(:, 1) - 0.003 * L(:, 2) .^ 2 + 0.3 * randn(nShots * nMarks, 1);
Xc = repelem(centers(:, 1), nMarks, 1);
Yc = repelem(centers(:, 2), nMarks, 1);
points = table(repmat("計測値", nShots * nMarks, 1), strings(nShots * nMarks, 1), repelem((1:nShots).', nMarks, 1), Xc, ...
    Yc, L(:, 1), L(:, 2), Xc + L(:, 1), Yc + L(:, 2), valueX, valueY, 'VariableNames', ["source", "name", "shotNo", ...
    "Xc", "Yc", "localX", "localY", "x", "y", "valueX", "valueY"]);
end
