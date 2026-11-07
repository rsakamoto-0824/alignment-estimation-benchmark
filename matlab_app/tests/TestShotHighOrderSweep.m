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
            testCase.verifyEqual([sweep.parameter, sweep.regularization, sweep.loss], ["lambda", "l2", "l2", "ols", "ols"]);
            testCase.verifyEqual(height(sweep.table), 2 * numel(lambdas));
            x = sweep.table(sweep.table.axis == "X", :);
            testCase.verifyEqual(x.lambda, lambdas.');
            testCase.verifyGreaterThanOrEqual(diff(x.fitRms), -1e-9, "当てはめた残差は λ とともに増える");
            testCase.verifyGreaterThanOrEqual(x.looRms - x.fitRms, -1e-12, "1点抜きの誤差は当てはめた残差以上");
            testCase.verifyGreaterThan(x.looMeanPlus3Sigma(end), x.looMeanPlus3Sigma(1), "強すぎる λ は予測も悪くする");
            testCase.verifyEqual(x.n, repmat(height(points), numel(lambdas), 1));
            % Huber の c：損失関数を Huber にする。λ と c の組み合わせはすべての組
            tuning = alignest.sweepHighOrder(wafer, settings, huberTuning=[0.5, 1, 2]);
            testCase.verifyEqual([tuning.parameter, tuning.loss], ["huberTuning", "huber", "huber"]);
            testCase.verifyEqual(unique(tuning.table.huberTuning).', [0.5, 1, 2]);
            both = alignest.sweepHighOrder(wafer, settings, lambda=[0, 1], huberTuning=[1, 2]);
            testCase.verifyEqual(both.parameter, "both");
            testCase.verifyEqual(height(both.table), 2 * 4);
            % 途中で止めて、続きから再開すると、止めずに計算したときと同じ
            stopped = alignest.sweepHighOrder(wafer, settings, lambda=lambdas, progressFcn=@(done, ~, ~) done < 2);
            testCase.verifyTrue(stopped.cancelled);
            testCase.verifyEqual(stopped.nRuns, 2);
            testCase.verifyEqual(height(stopped.table), 2 * 2);
            resumed = alignest.sweepHighOrder(wafer, settings, lambda=lambdas, resume=stopped.state);
            testCase.verifyFalse(resumed.cancelled);
            testCase.verifyEqual(resumed.table.fitRms, sweep.table.fitRms, 'AbsTol', 1e-12);
            testCase.verifyEqual(resumed.table.looRms, sweep.table.looRms, 'AbsTol', 1e-12);
            testCase.verifyError(@() alignest.sweepHighOrder(wafer, settings, lambda=[0, 1], resume=stopped.state), ...
                'alignest:highOrderSweep', "値の並びが違う");
            % c = 0 は LAD と同じ
            lad = settings;
            lad.highOrder.loss = "lad";
            ladResult = alignest.shotHighOrder(wafer, lad, stages=false);
            zeroTuning = alignest.sweepHighOrder(wafer, settings, huberTuning=[0, 1]);
            ladRows = zeroTuning.table(zeroTuning.table.huberTuning == 0 & zeroTuning.table.axis == "X", :);
            testCase.verifyEqual(ladRows.fitRms, sqrt(mean(ladResult.points.residualX .^ 2)), 'RelTol', 1e-9);
            % 基準（最小二乗・正則化なし）：λ = 0 の最小二乗と同じ。Wafer ごとの値もある
            testCase.verifyEqual(sweep.baseline.fitRms, sweep.table.fitRms(sweep.table.lambda == 0), 'AbsTol', 1e-9);
            testCase.verifyEqual(height(sweep.perWafer), 2 * numel(lambdas));
            % X・Y で別の回帰：dx は最小二乗、dy は Huber
            separate = settings;
            separate.highOrder.loss = ["ols", "huber"];
            separate.highOrder.regularization = ["none", "l2"];
            separate.highOrder.lambda = [0, 0.5];
            separate.highOrder.penaltyOrders = 2;
            separate.highOrder.penaltyOrdersY = 2:3;
            both_ = alignest.shotHighOrder(wafer, separate, stages=false);
            onlyX = settings;
            testCase.verifyEqual(both_.points.residualX, alignest.shotHighOrder(wafer, onlyX, stages=false).points.residualX, ...
                'AbsTol', 1e-9, "X は Y の設定に左右されない");
            onlyY = settings;
            onlyY.highOrder.loss = "huber";
            onlyY.highOrder.regularization = "l2";
            onlyY.highOrder.lambda = 0.5;
            onlyY.highOrder.penaltyOrders = 2:3;
            testCase.verifyEqual(both_.points.residualY, alignest.shotHighOrder(wafer, onlyY, stages=false).points.residualY, ...
                'AbsTol', 1e-9, "Y は Y の設定で求める");
            testCase.verifyTrue(contains(both_.description, "X は") && contains(both_.description, "Y は"));
            % 設定ファイルに X・Y 別の値が残る
            file = [tempname, '.json'];
            alignest.saveSettings(separate, file);
            loaded = alignest.loadSettings(file);
            delete(file);
            testCase.verifyEqual(loaded.highOrder.loss, ["ols", "huber"]);
            testCase.verifyEqual(loaded.highOrder.lambda, [0, 0.5]);
            testCase.verifyEqual(loaded.highOrder.penaltyOrdersY, 2:3);
            % 誤り
            testCase.verifyError(@() alignest.sweepHighOrder(wafer, settings), 'alignest:highOrderSweep');
            testCase.verifyError(@() alignest.sweepHighOrder(wafer, settings, lambda=-1), 'alignest:highOrderSweep');
            testCase.verifyError(@() alignest.sweepHighOrder(wafer, settings, lambda=1:21, huberTuning=1:20), ...
                'alignest:highOrderSweep', "値の組が多すぎる");
        end

        function regressionReportsRSquared(testCase)
            % 決定係数と自由度調整済決定係数：最小二乗は定義どおり（p は項の数）。L2 の自由度は項の数より小さい。Shot ごと・Wafer 成分
            points = noisyWafer(testCase, 7);
            wafer = struct("label", "W1", "points", points);
            settings = alignest.defaultSettings();
            settings.highOrder = struct("maker", "custom", "excludedTerms", 13:38, "unit", "common", "waferOrder", 0, ...
                "loss", "ols", "regularization", "none");
            result = alignest.shotHighOrder(wafer, settings, stages=false);
            terms = result.terms(result.terms.axis == "dx" & result.terms.used, :);
            p = height(terms);
            y = points.valueX;
            n = numel(y);
            design = points.localX .^ (terms.xPower.') .* points.localY .^ (terms.yPower.');
            residual = y - design * (design \ y);
            expected = 1 - sum(residual .^ 2) / sum((y - mean(y)) .^ 2);
            row = result.summary(result.summary.axis == "X" & result.summary.wafer == "W1", :);
            testCase.verifyEqual(row.rSquared, expected, 'AbsTol', 1e-9);
            testCase.verifyEqual(row.adjustedRSquared, 1 - (1 - expected) * (n - 1) / (n - p), 'AbsTol', 1e-9);
            testCase.verifyLessThan(row.adjustedRSquared, row.rSquared);
            testCase.verifyEqual(sum(result.points.leverageX), p, 'AbsTol', 1e-6, "最小二乗の自由度は項の数");
            regularized = settings;
            regularized.highOrder.regularization = "l2";
            regularized.highOrder.lambda = 1;
            regularized.highOrder.penaltyOrders = 2:4;
            shrunk = alignest.shotHighOrder(wafer, regularized, stages=false);
            testCase.verifyLessThan(sum(shrunk.points.leverageX), p, "L2 は有効自由度");
            perShot = settings;
            perShot.highOrder.unit = "shot";
            eachShot = alignest.shotHighOrder(wafer, perShot, stages=false);
            nShots = numel(unique(points.shotNo));
            testCase.verifyEqual(sum(eachShot.points.leverageX), p * nShots, 'AbsTol', 1e-6, "Shot ごとは項の数 × Shot の数");
            perShot.highOrder.waferOrder = 1;
            withWafer = alignest.shotHighOrder(wafer, perShot);
            testCase.verifyEqual(sum(withWafer.points.leverageX), p * nShots + 2, 'AbsTol', 1e-6, "先に引く Wafer 成分の2項も数える");
            testCase.verifyTrue(all(isfinite(result.regionSummary.rSquared)), "内周・外周の行にも出す");
            % 点の数と自由度が同じ・値がすべて同じ
            [first, second] = alignest.highOrderRSquared([1; 2; 4], [0; 0; 0], [1; 1; 1]);
            testCase.verifyEqual(first, 1);
            testCase.verifyTrue(isnan(second));
            [first, second] = alignest.highOrderRSquared([2; 2; 2], [0; 0; 0], [0.5; 0.5; 0.5]);
            testCase.verifyTrue(isnan(first) && isnan(second));
            % 値のある点だけを使う。ロバスト回帰では 0 より小さくなることがある
            [first, ~] = alignest.highOrderRSquared([1; 2; NaN; 3], [0.1; -0.1; 5; NaN], [0.5; 0.5; 0.5; 0.5]);
            testCase.verifyEqual(first, 1 - 0.02 / 0.5, 'AbsTol', 1e-12);
            [first, ~] = alignest.highOrderRSquared([1; 2; 3], [2; -2; 2], [0.5; 0.5; 0.5]);
            testCase.verifyLessThan(first, 0);
            % 表と Excel
            sheet = alignest.highOrderShotTable(eachShot);
            testCase.verifyTrue(all(ismember(["決定係数R2X", "自由度調整済決定係数Y"], string(sheet.Properties.VariableNames))));
            mine = eachShot.points(eachShot.points.shotNo == 3, :);
            testCase.verifyEqual(sheet.("決定係数R2X")(sheet.shotNo == 3), alignest.highOrderRSquared(mine.valueX, ...
                mine.residualX, mine.leverageX), 'AbsTol', 1e-12, "Shot ごとは Shot の回帰");
        end

        function screenSweepsAndAppliesBest(testCase)
            % 画面：範囲と刻み（対数・等間隔）、計算する数、スイープの図と表、最もよい値を使う、設定を変えた後の知らせ
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual([c.highOrderTuneLambdaStart.Value, c.highOrderTuneLambdaEnd.Value, ...
                c.highOrderTuneLambdaPoints.Value], [0, 1, 11]);
            testCase.verifyTrue(startsWith(string(c.highOrderTuneCount.Text), "λ 11 通り（0〜1）"));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            app.setHighOrderSource("data");
            app.setHighOrderSettings(unit="common", lambda=0.1);
            c.highOrderWafer.Value = {1, 2};
            sweep = app.sweepHighOrderParameters("lambda", lambdaRange=[0.01, 1, 3], lambdaScale="log");
            testCase.verifyEqual(sweep.lambda, [0.01, 0.1, 1]);
            testCase.verifyEqual(height(c.highOrderTuneTable.Data), 4, "基準の行＋3つの値");
            testCase.verifyEqual(c.highOrderTuneTable.Data.("λ")(2:end), [0.01; 0.1; 1]);
            testCase.verifyEqual(c.highOrderTuneTable.Data.("メモ")(1), "基準（最小二乗・正則化なし）");
            testCase.verifyEqual(numel(findobj(c.highOrderTuneAxes(1), 'Type', 'line')), 3, "当てはめ・1点抜き・最小");
            testCase.verifyEqual(numel(findobj(c.highOrderTuneAxes(1), 'Type', 'constantline')), 2, "基準の線");
            c.highOrderTuneErrorBar.Value = 'sd';
            app.drawHighOrderSweep();
            testCase.verifyEqual(numel(findobj(c.highOrderTuneAxes(1), 'Type', 'errorbar')), 2, "エラーバー");
            c.highOrderTuneErrorBar.Value = 'none';
            testCase.verifyEqual(string(c.highOrderTuneAxes(1).XScale), "log");
            testCase.verifyTrue(contains(string(c.highOrderTuneInfo.Text), "1点抜きの予測の誤差の |平均|+3σ が最小"));
            best = app.applyHighOrderSweepBest();
            testCase.verifyTrue(all(ismember([best.lambda], sweep.lambda)));
            testCase.verifyEqual([c.highOrderRegression.lambda.Value], [best.lambda], "X・Y それぞれ");
            % 評価数で等しく分ける。c = 0 を含められる（LAD）。対数で 0 から始めると知らせる
            app.sweepHighOrderParameters("huberTuning", tuningRange=[0, 3, 4]);
            testCase.verifyEqual(app.HighOrderSweep.huberTuning, [0, 1, 2, 3]);
            testCase.verifyEqual(app.Settings.highOrder.loss, "huber");
            % 一時中断と続きから再開
            stopped = app.sweepHighOrderParameters("lambda", lambdaRange=[0, 1, 5], lambdaScale="linear", ...
                progressFcn=@(done, ~, ~) done < 2);
            testCase.verifyTrue(stopped.cancelled);
            testCase.verifyEqual(string(c.highOrderTuneResume.Enable), "on");
            finished = app.resumeHighOrderSweep();
            testCase.verifyFalse(finished.cancelled);
            testCase.verifyEqual(finished.nRuns, 5);
            testCase.verifyEqual(string(c.highOrderTuneResume.Enable), "off");
            testCase.verifyError(@() app.resumeHighOrderSweep(), 'alignest:highOrderSweep');
            c.highOrderTuneParameter.Value = 'lambda';
            c.highOrderTuneLambdaScale.Value = 'log';
            c.highOrderTuneLambdaStart.Value = 0;
            c.highOrderTuneLambdaStart.ValueChangedFcn(c.highOrderTuneLambdaStart, []);
            testCase.verifyTrue(startsWith(string(c.highOrderTuneCount.Text), "⚠"));
            testCase.verifyError(@() app.sweepHighOrderParameters("lambda"), 'alignest:highOrderSweep');
            % λ と c の組み合わせは色の図
            app.sweepHighOrderParameters("both", lambdaRange=[0, 1, 2], lambdaScale="linear", tuningRange=[1, 2, 2]);
            testCase.verifyNotEmpty(findobj(c.highOrderTuneAxes(2), 'Type', 'image'));
            testCase.verifyEqual(height(c.highOrderTuneTable.Data), 5);
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
