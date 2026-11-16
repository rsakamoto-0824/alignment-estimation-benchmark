classdef TestPlanModelAndDefaults < matlab.unittest.TestCase
    %TESTPLANMODELANDDEFAULTS 初期設定の変更、I 最適の基準モデル（X・Y・半径の多項式）、Mark 単位の制約つきランダム、
    %   データ読込の異常値の除外（MAD）、推定誤差・計測数に対する重ね合わせ補正の悪化（alignest.overlayDegradation）。

    properties
        Data
        Root
    end

    methods (TestClassSetup)
        function loadSample(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.Root);
            raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            testCase.Data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
        end
    end

    methods (Test)
        function defaultsChanged(testCase)
            % 初期設定：Overlay 補正の評価は Shot 共通なし・Shot ごと 1次、GPR の質的変数は加法カーネルだけ、
            % Shot 高次補正はカスタムの式・最小二乗・正則化なし・λ = 1e-5（Mark 配置の最適化の回帰も同じ）
            settings = alignest.defaultSettings();
            testCase.verifyEqual(settings.overlay.shotCommon, "none");
            testCase.verifyEqual(settings.overlay.perShot, "linear");
            testCase.verifyEqual(settings.methods.gpr.factorModes, "additive");
            testCase.verifyEqual(alignest.recommendedMethods("recommended").gpr.factorModes, ["none", "basis", "additive"], ...
                "推奨の組み合わせは変えない");
            testCase.verifyEqual(settings.highOrder.maker, "custom");
            testCase.verifyEqual([settings.highOrder.loss, settings.highOrder.regularization], ["ols", "none"]);
            testCase.verifyEqual(settings.highOrder.lambda, 1e-5);
            testCase.verifyEqual([settings.markLayout.loss, settings.markLayout.regularization], ["ols", "none"]);
            testCase.verifyEqual(settings.markLayout.lambda, 1e-5);
            testCase.verifyEqual(settings.sampling.designFeatures, "XYR");
            testCase.verifyEqual(settings.data.outlierMethod, "sigma");
        end

        function radialDesignModel(testCase)
            % X・Y・半径の多項式：r² は X・Y の多項式で表せるので、X・Y の多項式と r × X・Y の多項式（5次で 21 + 15 = 36 列）。
            % 列はどれも独立で、X・Y だけなら以前の多項式と同じ
            rng(3);
            xy = rand(400, 2) * 2 - 1;
            xy = xy(hypot(xy(:, 1), xy(:, 2)) < 1, :);
            radial = alignest.basis.designPolynomial(xy(:, 1), xy(:, 2), 5, "XYR");
            testCase.verifyEqual(size(radial, 2), 36);
            testCase.verifyEqual(rank(radial), 36, "重なる列が無い");
            testCase.verifyEqual(radial(:, 22), hypot(xy(:, 1), xy(:, 2)), 'AbsTol', 1e-12, "22 列目が r");
            testCase.verifyEqual(alignest.basis.designPolynomial(xy(:, 1), xy(:, 2), 5, "XY"), ...
                alignest.basis.polynomialDesign(xy(:, 1), xy(:, 2), 5));
            % I 最適の計画：基準モデルを X・Y にすると以前と同じ。I 基準は基準モデルの項で決まる
            sampling = alignest.defaultSettings().sampling;
            sampling.exchangeStarts = 2;
            spec = alignest.buildPlanSpecs(setfield(sampling, "nShots", 20)); %#ok<SFLD>
            sampling.designFeatures = "XY";
            planXY = alignest.planTrainingShots(testCase.Data.units(1), spec(1), sampling, 150);
            sampling.designFeatures = "XYR";
            planXYR = alignest.planTrainingShots(testCase.Data.units(1), spec(1), sampling, 150);
            testCase.verifyTrue(planXY.ok && planXYR.ok);
            testCase.verifyEqual(planXYR.nShots, 20);
            testCase.verifyGreaterThan(planXYR.criterionI, planXY.criterionI, "項が多いほど I 基準は大きい");
        end

        function markRandomPlans(testCase)
            % Mark 単位の制約つきランダム：繰り返しの数だけ学習パターンを作り、各 Shot で1点以上・Mark 番号の割合・同心円の
            % 区画の制約を満たす。乱数の種と繰り返しの番号で決まる
            sampling = alignest.defaultSettings().sampling;
            sampling.method = "markrandom";
            sampling.randomRepeats = 3;
            specs = alignest.buildPlanSpecs(sampling);
            testCase.verifyEqual(string({specs.label}), "Markランダム 1 点/Shot #" + string(1:3));
            testCase.verifyEqual(unique(string({specs.group})), "1 点/Shot", "繰り返しは同じ列");
            unit = testCase.Data.units(1);
            plans = arrayfun(@(spec) alignest.planTrainingShots(unit, spec, sampling, 150), specs);
            testCase.verifyTrue(all([plans.ok]));
            testCase.verifyEqual([plans.violation], [0, 0, 0], "制約を満たす");
            candidateShots = unique(unit.marks.shotIndex(unit.marks.validX | unit.marks.validY));
            for plan = plans
                testCase.verifyEqual(sort(unique(unit.marks.shotIndex(plan.markIndex))), sort(candidateShots), ...
                    "どの Shot も1点以上を計測する");
            end
            testCase.verifyFalse(isequal(plans(1).markIndex, plans(2).markIndex), "繰り返しごとに違う組");
            again = alignest.planTrainingShots(unit, specs(1), sampling, 150);
            testCase.verifyEqual(again.markIndex, plans(1).markIndex, "同じ種なら同じ組");
            testCase.verifyTrue(all(isfinite([plans.criterionI])));
            % Mark 単位の I 最適は、同じ数のランダムより I 基準が小さい
            sampling.method = "mark";
            optimal = alignest.planTrainingShots(unit, alignest.buildPlanSpecs(sampling), sampling, 150);
            testCase.verifyLessThan(optimal.criterionI, min([plans.criterionI]));
            testCase.verifyTrue(ismember("markrandom", alignest.markPlanTypes()));
        end

        function importOutliersByMad(testCase)
            % データ読込の異常値の除外：MAD は学習データの異常値の判定（trainingOutliers の "mad"）と同じ
            raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            byMad = alignest.prepareData(raw, mapping, excludeOutliers=true, outlierSigma=2, outlierMethod="mad");
            plain = alignest.prepareData(raw, mapping);
            marks = plain.units(1).marks;
            expected = alignest.trainingOutliers(marks, true(numel(marks.x), 1), 2, "mad");
            testCase.verifyEqual(byMad.summary.outlierCounts(1), nnz(expected));
            testCase.verifyEqual(byMad.outlierMethod, "mad");
            testCase.verifyTrue(any(contains(byMad.summary.messages, "中央値 ± 2 × 1.4826 MAD")));
            bySigma = alignest.prepareData(raw, mapping, excludeOutliers=true, outlierSigma=2);
            testCase.verifyNotEqual(bySigma.summary.nOutliersExcluded, byMad.summary.nOutliersExcluded);
        end

        function degradationTable(testCase)
            % 補正の悪化：推定誤差（Wafer の集計）・計測数（Wafer の平均）に対する推定による増加。Wafer ごとの点も
            settings = alignest.defaultSettings();
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.sampling.nShots = [10, 20];
            settings.sampling.nShotsStart = 10;
            settings.sampling.nShotsEnd = 20;
            settings.sampling.nShotsStep = 10;
            settings.sampling.exchangeStarts = 2;
            results = alignest.runEvaluation(testCase.Data, settings);
            degradation = alignest.overlayDegradation(results, "error", "overlayIncrease", "mean");
            points = degradation.points;
            testCase.verifyEqual(height(points), 2, "手法 1 × 列 2");
            rmse = alignest.summarizeResults(results, "RMSE_XY", "mean");
            increase = alignest.summarizeResults(results, "overlayIncrease_X", "mean");
            testCase.verifyEqual(points.x.', rmse.values(1, :), 'AbsTol', 1e-12);
            testCase.verifyEqual(points.valueX.', increase.values(1, :), 'AbsTol', 1e-12);
            testCase.verifyEqual(height(degradation.wafers), 2 * numel(results.unitLabels));
            first = degradation.wafers(degradation.wafers.group == points.group(1), :);
            testCase.verifyEqual(points.sdX(1), std(first.valueX), 'AbsTol', 1e-12, "エラーバーの標準偏差");
            testCase.verifyEqual([points.minY(1), points.maxY(1)], [min(first.valueY), max(first.valueY)]);
            byShots = alignest.overlayDegradation(results, "shots", "overlayChange", "median");
            testCase.verifyEqual(byShots.points.x.', [10, 20]);
            byMarks = alignest.overlayDegradation(results, "marks", "overlayIncrease", "mean");
            testCase.verifyTrue(all(byMarks.points.x > byShots.points.x), "Mark の数は Shot 数より多い");
            % Overlay 補正を評価しない結果では空
            results.overlayEvaluated = false;
            testCase.verifyEmpty(alignest.overlayDegradation(results).points);
        end
    end
end
