classdef TestTransferSelectionCorrection < matlab.unittest.TestCase
    %TESTTRANSFERSELECTIONCORRECTION Shot 高次補正の追加：ほかの Wafer の補正値を当てる評価、補正の段階の残差の列、Shot 共通を
    %   先に引くくくり（Scan 方向ごと・行の偶奇ごと）、保存した組み合わせからの Shot 共通の項、k パラメータの選定（変数重要度・
    %   ステップワイズ）、結果の履歴、マップの Wafer の重ね描き、補正値テーブルのタブの位置。データ読込の異常値の除外とタブの名前、
    %   Mark 配置の最適化の制御残差推移の縦軸、結果一覧の実測値と推定値の補正の比較。

    properties
        Root
        Centers   % 合成の Wafer の Shot 中心 [mm]
    end

    methods (TestClassSetup)
        function addPath(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.Root);
            centers = zeros(0, 2);
            for cx = -130:26:130
                for cy = -132:33:132
                    if hypot(cx, cy) < 145
                        centers(end + 1, :) = [cx, cy]; %#ok<AGROW>
                    end
                end
            end
            testCase.Centers = centers;
        end
    end

    methods (Test)
        function dataOutliersAndTabName(testCase)
            % データ読込：Wafer ごとに平均 ± nσ の外の Mark を X・Y とも除く（重複を平均した後に1回だけ）
            raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            plain = alignest.prepareData(raw, mapping);
            cleaned = alignest.prepareData(raw, mapping, excludeOutliers=true, outlierSigma=2.5);
            testCase.verifyEqual(plain.summary.nOutliersExcluded, 0);
            for u = 1:numel(plain.units)
                expected = alignest.trainingOutliers(plain.units(u).marks, true(numel(plain.units(u).marks.x), 1), 2.5);
                marks = cleaned.units(u).marks;
                testCase.verifyEqual(cleaned.summary.outlierCounts(u), nnz(expected));
                testCase.verifyFalse(any(marks.validX(expected) | marks.validY(expected)), "X・Y の両方で除く");
                testCase.verifyEqual(cleaned.units(u).shots.nValidX, accumarray(marks.shotIndex, marks.validX, ...
                    [numel(cleaned.units(u).shots.Xmm), 1]), "Shot の有効な点の数も除いた後");
            end
            testCase.verifyGreaterThan(cleaned.summary.nOutliersExcluded, 0);
            testCase.verifyTrue(any(contains(cleaned.summary.messages, "異常値の除外")));
            % 画面：タブの名前と、欄から設定・前処理へ
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual(app.Tabs.data.Title, '1. データ読込');
            testCase.verifyEqual(string(c.dataOutlierSigma.Enable), "off");
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            c.dataExcludeOutliers.Value = true;
            c.dataOutlierSigma.Value = 2.5;
            c.dataExcludeOutliers.ValueChangedFcn([], []);
            testCase.verifyTrue(app.Settings.data.excludeOutliers);
            testCase.verifyEqual(string(c.dataOutlierSigma.Enable), "on");
            app.applyMapping();
            testCase.verifyEqual(app.Data.summary.nOutliersExcluded, cleaned.summary.nOutliersExcluded);
            testCase.verifyTrue(any(contains(string(c.summary.Value), "異常値の除外")));
        end

        function transferReproducesOwnAndAverages(testCase)
            % 自分の補正値を当てると、自分で求めた補正と同じ（Wafer 成分・Shot ごと・Wafer RT も）。2枚の平均を当てる
            wafers = [struct("label", "W1", "points", syntheticPoints(testCase, 1)), ...
                struct("label", "W2", "points", syntheticPoints(testCase, 2)), ...
                struct("label", "W3", "points", syntheticPoints(testCase, 3))];
            for unit = ["common", "shot"]
                settings = baseSettings(unit);
                settings.highOrder.waferRtRange = "outer";
                settings.highOrder.outerRadiusMm = 110;
                result = alignest.shotHighOrder(wafers, settings);
                own = alignest.transferHighOrder(result, "W1", "W1");
                testCase.verifyEqual(own.points.transferResidualX, own.points.residualX, 'AbsTol', 1e-8, unit);
                testCase.verifyEqual(own.points.transferResidualY, own.points.residualY, 'AbsTol', 1e-8, unit);
                testCase.verifyEqual(own.summary.difference, zeros(4, 1), 'AbsTol', 1e-8);
            end
            result = alignest.shotHighOrder(wafers, baseSettings("common"));
            averaged = alignest.transferHighOrder(result, ["W1", "W2"], "W3");
            rows = result.coefficients;
            pick = @(w) rows(rows.wafer == w & rows.axis == "dx" & rows.component == "Shot 高次補正", :);
            applied = averaged.coefficients(averaged.coefficients.axis == "dx" & ...
                averaged.coefficients.component == "Shot 高次補正", :);
            testCase.verifyEqual(applied.value, (pick("W1").value + pick("W2").value) / 2, 'AbsTol', 1e-12, "項ごとの平均");
            testCase.verifyTrue(contains(averaged.description, "平均（2 枚）"));
            testCase.verifyEqual(averaged.summary.wafer.', ["W3", "すべての補正先", "W3", "すべての補正先"]);
            testCase.verifyGreaterThan(averaged.summary.transferred(1), averaged.summary.own(1), ...
                "Wafer ごとに違う形なので、ほかの Wafer の補正値では残差が大きい");
            % 実測値を平均してから補正値を求める：最小二乗・正則化なし・同じ点に値があれば、補正値の平均と同じ
            for unit = ["common", "shot"]
                unitResult = alignest.shotHighOrder(wafers, baseSettings(unit));
                byCoefficients = alignest.transferHighOrder(unitResult, ["W1", "W2"], "W3", method="coefficients");
                byValues = alignest.transferHighOrder(unitResult, ["W1", "W2"], "W3", method="values");
                testCase.verifyEqual(byValues.points.transferResidualX, byCoefficients.points.transferResidualX, ...
                    'AbsTol', 1e-8, unit);
                testCase.verifyEqual(byValues.points.transferResidualY, byCoefficients.points.transferResidualY, ...
                    'AbsTol', 1e-8, unit);
                testCase.verifyTrue(contains(byValues.description, "実測値の平均から求めた補正値（2 枚）"));
                testCase.verifyEqual(byValues.method, "values");
            end
            robustSettings = baseSettings("common");
            robustSettings.highOrder.loss = "huber";
            robustResult = alignest.shotHighOrder(wafers, robustSettings);
            robustValues = alignest.transferHighOrder(robustResult, ["W1", "W2"], "W3", method="values");
            single = alignest.transferHighOrder(robustResult, "W1", "W3", method="values");
            testCase.verifyTrue(all(isfinite(robustValues.summary.transferred)));
            testCase.verifyEqual(single.points.transferResidualX, ...
                alignest.transferHighOrder(robustResult, "W1", "W3").points.transferResidualX, 'AbsTol', 1e-12, ...
                "補正元が1枚なら、どちらの求め方も同じ");
            % Shot ごとのくくりで、補正元に無い Shot は補正しない
            shotWafers = wafers;
            shotWafers(1).points = shotWafers(1).points(shotWafers(1).points.shotNo ~= 5, :);
            shotResult = alignest.shotHighOrder(shotWafers, baseSettings("shot"));
            missing = alignest.transferHighOrder(shotResult, "W1", "W2");
            testCase.verifyTrue(all(isnan(missing.points.transferResidualX(missing.points.shotNo == 5))));
            testCase.verifyTrue(any(contains(missing.messages, "Shot 5")));
            testCase.verifyError(@() alignest.transferHighOrder(shotResult, "W9", "W2"), 'alignest:highOrderTransfer');
        end

        function stageColumnsAndSequentialGroups(testCase)
            % 補正の評価に段階（Wafer 高次補正だけ・＋Shot 共通補正）の列。Scan 方向ごと・行の偶奇ごとでも Shot 共通を先に引ける
            points = syntheticPoints(testCase, 1);
            points.direction = 1 + mod(points.shotNo, 2);
            wafer = struct("label", "W1", "points", points);
            common = alignest.shotHighOrder(wafer, baseSettings("common"));
            testCase.verifyEqual(common.summary.commonStage, common.summary.highOrder, 'AbsTol', 1e-12, ...
                "Wafer 内で共通なら Shot 共通補正が高次補正そのもの");
            testCase.verifyTrue(all(common.summary.waferStage >= common.summary.highOrder));
            for unit = ["scan", "row"]
                % Wafer 成分なし：Shot 共通と組ごとの k が同じ項の空間なので、引いても引かなくても最小二乗の補正量は同じ
                % （Wafer 成分があると、先に引く段階の順で Wafer 成分が決まるので同じにはならない）
                settings = baseSettings(unit);
                settings.highOrder.waferOrder = 0;
                plain = alignest.shotHighOrder(wafer, settings);
                settings.highOrder.shotCommon = "fit";
                sequential = alignest.shotHighOrder(wafer, settings);
                testCase.verifyTrue(alignest.highOrderSequential(sequential.options));
                testCase.verifyEqual(sequential.points.correctionX, plain.points.correctionX, 'AbsTol', 1e-8, ...
                    unit + "：組ごとに使う項をすべて求めて正則化なしなら、引かないときと同じ補正量");
                testCase.verifyTrue(contains(sequential.description, "ごとに求める"));
                settings.highOrder.shotEachOrder = 1;
                limited = alignest.shotHighOrder(wafer, settings);
                testCase.verifyGreaterThan(height(limited.commonCoefficients), 0, "引いた Shot 共通の k");
            end
            testCase.verifyFalse(alignest.highOrderSequential(struct("unit", "common", "shotCommon", "fit")));
            testCase.verifyFalse(alignest.highOrderSequential(struct("unit", "scan", "shotCommon", "none")));
        end

        function termSelectionByImportanceAndStepwise(testCase)
            % 変数重要度：効く項は残し、効かない項は外す。ステップワイズ：始めの項から BIC が下がる項を足す
            wafers = [struct("label", "W1", "points", syntheticPoints(testCase, 1)), ...
                struct("label", "W2", "points", syntheticPoints(testCase, 2)), ...
                struct("label", "W3", "points", syntheticPoints(testCase, 3))];
            settings = baseSettings("common");
            selection = alignest.highOrderTermSelection(wafers, settings, "importance", threshold=2);
            t = selection.importance;
            testCase.verifyTrue(all(t.keep(ismember(t.k, [7, 11, 8, 12]))), "形に入れた2次の項は残す");
            testCase.verifyTrue(all(t.keep(t.protected)), "k1〜k6 は外さない");
            testCase.verifyEqual(t.keep, t.protected | t.importance >= 2);
            testCase.verifyEqual(sort(selection.excludedTerms), sort(t.k(~t.keep).'));
            testCase.verifyGreaterThan(nnz(~t.keep), 0, "効かない項は外す");
            settings.highOrder.excludedTerms = 7:60;   % k1〜k6 だけから始める
            stepwise = alignest.highOrderTermSelection(wafers, settings, "stepwise");
            steps = stepwise.steps;
            testCase.verifyTrue(all(ismember([7, 11], stepwise.used{1})), "dx の2次の形の項を足す");
            testCase.verifyTrue(all(ismember([8, 12], stepwise.used{2})), "dy の2次の形の項を足す");
            testCase.verifyTrue(all(steps.change(steps.step > 0) < 0), "足すたびに BIC が下がる");
            testCase.verifyEqual(steps.step(1), 0);
        end

        function highOrderScreensForNewFeatures(testCase)
            % 画面：結果の履歴・他の Wafer の補正・k の選定・保存した組み合わせからの Shot 共通の項・マップの重ね描き・
            % 補正値テーブルのタブの位置、Mark 配置の最適化の制御残差推移の縦軸
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            titles = string({c.highOrderOutputs.Children.Title});
            testCase.verifyEqual(find(titles == "補正値テーブル") + 1, find(titles == "書き出し"), "書き出しの左");
            testCase.verifyFalse(any(titles == "補正値"));
            testCase.verifyTrue(all(ismember(["k の選定", "結果の履歴", "他の Wafer の補正"], titles)));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            app.setHighOrderSource("data");
            app.computeHighOrder(0);
            app.setHighOrderSettings(unit="scan", shotCommon="fit", shotEachOrder=1);
            testCase.verifyEqual(string(c.highOrderShotCommon.Enable), "on", "Scan 方向ごとでも Shot 共通を先に引ける");
            app.computeHighOrder(0);
            testCase.verifyEqual([app.HighOrderHistory.number], [1, 2]);
            testCase.verifyEqual(size(c.highOrderHistoryTable.Data, 1), 2);
            data = app.compareHighOrderHistory([], "highOrder");
            testCase.verifyEqual(data.number.', [1, 2]);
            testCase.verifyEqual(numel(findobj(c.highOrderHistoryAxes, 'Type', 'bar')), 2, "X・Y の棒");
            app.restoreHighOrderHistory(1);
            testCase.verifyEqual(app.Settings.highOrder.unit, "common");
            testCase.verifyEqual(string(c.highOrderUnit.Value), "common");
            app.removeHighOrderHistory(1);
            testCase.verifyEqual([app.HighOrderHistory.number], 2);
            % 他の Wafer の補正
            transfer = app.transferHighOrderCorrection([1, 2], 3);
            testCase.verifyEqual(transfer.targets, string(app.HighOrderRun.wafers(3).label));
            testCase.verifyEqual(height(c.highOrderTransferTable.Data), 4);
            testCase.verifyEqual(transfer.method, "coefficients");
            transfer = app.transferHighOrderCorrection([1, 2], 3, "values");
            testCase.verifyTrue(contains(string(c.highOrderTransferInfo.Text), "実測値の平均から求めた補正値"));
            testCase.verifyEqual(transfer.method, "values");
            % k の選定と、使う項にする
            selection = app.selectHighOrderTerms("importance", 2);
            testCase.verifyEqual(c.highOrderSelectMethod.Items{1}, '変数重要度');
            testCase.verifyTrue(any(string(c.highOrderSelectTable.Data.Properties.VariableNames) == "変数重要度"));
            app.applyHighOrderTermSelection();
            testCase.verifyEqual(app.Settings.highOrder.excludedTerms, selection.excludedTerms);
            testCase.verifyTrue(startsWith(string(c.highOrderSelectInfo.Text), "使う項を"));
            app.selectHighOrderTerms("stepwise");
            testCase.verifyTrue(any(string(c.highOrderSelectTable.Data.Properties.VariableNames) == "BIC"));
            % 保存した組み合わせから Shot 共通の項
            app.setHighOrderSettings(unit="shot", shotCommon="fit");
            app.saveHighOrderTermSet("共通の組");
            testCase.verifyEqual(string(c.highOrderCommonTermSet.Enable), "on");
            app.applyHighOrderCommonTermSet("共通の組");
            testCase.verifyTrue(all(ismember(1:6, app.Settings.highOrder.shotCommonTerms)));
            testCase.verifyError(@() app.applyHighOrderCommonTermSet("無い組"), 'alignest:highOrderTermSet');
            % マップ：選んだ Wafer を重ねる
            app.computeHighOrder(0);
            summary = app.setHighOrderMapOverlay([1, 2, 3]);
            testCase.verifyEqual(height(summary), 3);
            testCase.verifyEqual(numel(findobj(c.highOrderAxes, 'Type', 'quiver')), 3, "Wafer ごとの色の矢印");
            app.drawHighOrderMap(1, "stack", "residual", "vector", "", "single");
            testCase.verifyEqual(numel(findobj(c.highOrderAxes, 'Type', 'quiver')), 3, "Shot を重ねる図でも重ねる");
            app.drawHighOrderMap(1, "wafer", "residual", "X", "", "single");
            testCase.verifyTrue(contains(string(c.highOrderMapInfo.Text), "ベクトル"), "色の図では重ねない");
            app.setHighOrderMapOverlay([]);
            testCase.verifyFalse(c.highOrderMapOverlay.Value);
            % Mark 配置の最適化：制御残差推移の縦軸の範囲
            testCase.verifyEqual(c.markOptChartTab.Title, '制御残差推移');
            app.makeMarkLayoutGrid([24, 30], [5, 7]);
            app.setMarkLayoutSettings(maker="canon", loss="ols", regularization="none", maxMarks=10, shapes=10);
            app.generateMarkLayoutShapes();
            app.optimizeMarkLayout();
            c.markOptChartYManual.Value = true;
            c.markOptChartYMin.Value = 0;
            c.markOptChartYMax.Value = 50;
            c.markOptChartYManual.ValueChangedFcn([], []);
            testCase.verifyEqual(c.markOptChartAxes.YLim, [0, 50]);
            c.markOptChartYMin.Value = 60;
            c.markOptChartYMin.ValueChangedFcn([], []);
            testCase.verifyTrue(startsWith(string(c.markOptChartInfo.Text), "⚠"));
        end

        function measuredAndEstimatedCorrection(testCase)
            % 結果一覧：実測値で求めた補正と推定値で求めた補正を、実測値に当てて比べる（補正のモデルは「7. Shot高次補正」の設定）
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.sampling.nShots = 30;
            settings.sampling.exchangeStarts = 2;
            app.setSettings(settings);
            app.runEvaluationNow(false);
            testCase.verifyEqual(string(c.compareEstimatedCorrectionButton.Enable), "on");
            comparison = app.compareEstimatedCorrection(1, c.estimatedCorrectionGroup.Items{1}, 0);
            t = comparison.table;
            testCase.verifyEqual(height(t), 2 * (numel(app.Data.units) + 1), "Wafer（とすべて）× X・Y");
            testCase.verifyEqual(t.difference, t.estimated - t.measured, 'AbsTol', 1e-12);
            testCase.verifyTrue(all(t.measured <= t.before), "補正すると残差が小さい");
            testCase.verifyTrue(all(t.correctionDifference > 0));
            % 実測値で補正した残差は、同じ設定で計測値から求めた Shot 高次補正と同じ
            wafers = arrayfun(@(unit) struct("label", string(unit.label), "points", alignest.highOrderUnitPoints(unit)), ...
                app.Data.units);
            direct = alignest.shotHighOrder(wafers, app.Settings);
            first = t(t.wafer == string(app.Data.units(1).label) & t.axis == "X", :);
            residual = direct.points.residualX(direct.points.wafer == string(app.Data.units(1).label));
            testCase.verifyEqual(first.measured, meanPlus3Sigma(residual), 'RelTol', 0.05);
            testCase.verifyEqual(height(c.estimatedCorrectionTable.Data), height(t));
            testCase.verifyEqual(numel(findobj(c.estimatedCorrectionAxes, 'Type', 'bar')), 4);
            testCase.verifyTrue(contains(string(c.estimatedCorrectionModel.Text), "Nikon"));
        end
    end
end

function settings = baseSettings(unit)
% 合成の Wafer の補正の設定：Nikon の式・最小二乗・正則化なし・Wafer 成分 1次
settings = alignest.defaultSettings();
settings.highOrder.maker = "nikon";
settings.highOrder.excludedTerms = zeros(1, 0);
settings.highOrder.unit = unit;
settings.highOrder.waferOrder = 1;
settings.highOrder.loss = "ols";
settings.highOrder.regularization = "none";
settings.highOrder.shotCommon = "none";
settings.highOrder.shotEachOrder = 0;
end

function points = syntheticPoints(testCase, seed)
% 合成の Wafer：Shot ごとに 7 × 11 の格子の点。Nikon の式の2次の項（dx：k7・k11、dy：k8・k12）の Shot 共通の形（Wafer ごとに
% 少し違う）＋ Wafer の1次（dx に 0.01 × Xc）＋ 点ごとのばらつき（乱数の種 seed）
rng(seed);
centers = testCase.Centers;
nShots = size(centers, 1);
[lx, ly] = meshgrid(linspace(-12, 12, 7), linspace(-15, 15, 11));
shotNo = repelem((1:nShots).', numel(lx), 1);
local = repmat([lx(:), ly(:)], nShots, 1);
n = numel(shotNo);
Xc = centers(shotNo, 1);
Yc = centers(shotNo, 2);
scale = 1 + 0.3 * seed;
valueX = scale * (0.02 * local(:, 1) .^ 2 - 0.015 * local(:, 2) .^ 2) + 0.01 * Xc + 0.3 * randn(n, 1);
valueY = scale * (0.018 * local(:, 2) .^ 2 + 0.012 * local(:, 1) .^ 2) + 0.3 * randn(n, 1);
points = table(repmat("mark", n, 1), "M" + string((1:n).'), shotNo, Xc, Yc, local(:, 1), local(:, 2), Xc + local(:, 1), ...
    Yc + local(:, 2), valueX, valueY, 'VariableNames', ["source", "name", "shotNo", "Xc", "Yc", "localX", "localY", "x", ...
    "y", "valueX", "valueY"]);
end

function value = meanPlus3Sigma(values)
values = values(isfinite(values));
value = abs(mean(values)) + 3 * std(values);
end
