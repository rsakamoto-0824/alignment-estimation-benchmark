classdef TestGprVariance < matlab.unittest.TestCase
    %TESTGPRVARIANCE GPR の推定の分散（予測分散）：式どおりの値、学習点の近くで小さく遠くで大きいこと、評価の結果に残ること、
    %   「5. Waferごとのマップ」の「推定の分散を並べる（GPR）」と「6. 未知の座標の推定」の分散の図・表・書き出し。

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
        function varianceMatchesFormula(testCase)
            % ハイパーパラメータを固定し、平均の基底（定数）も推定する GPR の予測分散の式と比べる
            rng(5);
            train = rand(25, 2) * 2 - 1;
            test = [rand(8, 2) * 2 - 1; 0.5, 0.5; 3, 3];
            y = sin(3 * train(:, 1)) + 0.05 * randn(25, 1);
            lengthScale = 0.4;
            signalStd = 0.8;
            noiseStd = 0.05;
            logParams = log([lengthScale; signalStd; noiseStd]);
            result = alignest.models.gprFitPredict(train, test, [1, 1], y, "squaredexponential", "none", struct(), ...
                fixedLogParams=logParams);
            kernel = @(a, b) signalStd ^ 2 * exp(-0.5 * ((a(:, 1) - b(:, 1).') .^ 2 + (a(:, 2) - b(:, 2).') .^ 2) / ...
                lengthScale ^ 2);
            covariance = kernel(train, train) + noiseStd ^ 2 * eye(25);
            cross = kernel(test, train);
            H = ones(25, 1);
            inverse = inv(covariance);   % 教科書の式のまま（アプリとは別の求め方で確かめる）
            r = ones(1, size(test, 1)) - H.' * inverse * cross.'; %#ok<MINV>
            expected = signalStd ^ 2 - sum((cross * inverse) .* cross, 2) + (r .^ 2).' / (H.' * inverse * H); %#ok<MINV>
            testCase.verifyEqual(result.predictionVariance, expected, 'RelTol', 1e-6, 'AbsTol', 1e-10);
            testCase.verifyTrue(all(result.predictionVariance >= 0));
            testCase.verifyGreaterThan(result.predictionVariance(end), max(result.predictionVariance(1:end - 1)), ...
                "学習点から遠い点ほど大きい");
            testCase.verifyGreaterThan(result.predictionVariance(end), 0.9 * signalStd ^ 2, "遠い点は事前分散の程度");
            % 学習点と同じ位置では、計測のばらつき程度まで小さい
            atTrain = alignest.models.gprFitPredict(train, train(1:3, :), [1, 1], y, "squaredexponential", "none", ...
                struct(), fixedLogParams=logParams);
            testCase.verifyLessThan(max(atTrain.predictionVariance), noiseStd ^ 2);
        end

        function estimatesKeepVariance(testCase)
            % 評価の結果（estimateWafer・compactEstimate）に GPR の推定の分散が評価点の数だけ残る。ほかの手法は空
            raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            unit = data.units(1);
            settings = alignest.defaultSettings();
            methods = alignest.recommendedMethods("none");
            methods.gpr.enabled = true;
            methods.gpr.kernels = "matern52";
            methods.gpr.factorModes = "none";
            methods.polynomial.enabled = true;
            settings.methods = methods;
            list = alignest.buildMethodList(methods);
            training = 1:3:numel(unit.shots.shotNo);
            gpr = alignest.estimateWafer(unit, training, list(string({list.family}) == "GPR"), settings);
            testCase.verifyEqual(numel(gpr.variance.X), numel(gpr.testIndex.X));
            testCase.verifyEqual(numel(gpr.variance.Y), numel(gpr.testIndex.Y));
            testCase.verifyTrue(all(gpr.variance.X >= 0 & isfinite(gpr.variance.X)));
            compact = alignest.compactEstimate(gpr);
            testCase.verifyEqual(compact.variance.X, gpr.variance.X);
            polynomial = alignest.estimateWafer(unit, training, list(string({list.family}) == "XY"), settings);
            testCase.verifyEmpty(polynomial.variance.X);
            testCase.verifyEmpty(alignest.compactEstimate(polynomial).variance.Y);
        end

        function screensShowVariance(testCase)
            % 「5. Waferごとのマップ」：GPR なら4つ目の図に推定の分散。GPR 以外は描かずに知らせる。
            % 「6. 未知の座標の推定」：分散の色の図・表の列・Excel の列
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.gpr.enabled = true;
            settings.methods.gpr.kernels = "matern52";
            settings.methods.gpr.factorModes = "none";
            settings.methods.polynomial.enabled = true;
            settings.sampling.nShots = 30;
            settings.sampling.exchangeStarts = 2;
            app.setSettings(settings);
            results = app.runEvaluationNow(false);
            gprIndex = find(string({results.methods.family}) == "GPR", 1);
            polynomialIndex = find(string({results.methods.family}) == "XY", 1);
            plan = results.plans(1).label;
            app.showMap(1, plan, gprIndex, "X");
            testCase.verifyEqual(string(app.Controls.mapVarianceAxes.Visible), "off", "はじめは並べない");
            c.mapVariance.Value = true;
            c.mapVariance.ValueChangedFcn([], []);
            testCase.verifyEqual(string(app.Controls.mapVarianceAxes.Visible), "on");
            testCase.verifyTrue(startsWith(string(app.Controls.mapVarianceAxes.Title.String), "推定の分散 X（GPR）"));
            testCase.verifyTrue(contains(string(c.mapInfo.Text), "推定の分散（GPR）"));
            testCase.verifyEqual(app.Controls.mapVarianceAxes.CLim(1), 0, "分散は 0 から");
            app.showMap(1, plan, gprIndex, "vector");
            testCase.verifyTrue(startsWith(string(app.Controls.mapVarianceAxes.Title.String), "推定の分散 X＋Y"));
            app.showMap(1, plan, polynomialIndex, "X");
            testCase.verifyEqual(string(app.Controls.mapVarianceAxes.Visible), "off");
            testCase.verifyTrue(contains(string(c.mapInfo.Text), "GPR の手法だけ"));
            % 未知の座標の推定
            app.addTargetPoints("grid", 30, 140);
            run = app.estimateTargets(1, "all", gprIndex);
            testCase.verifyTrue(all(isfinite(run.estimates.varianceX(~run.estimates.outsideWafer))));
            c.targetMode.Value = 'varianceY';
            c.targetMode.ValueChangedFcn([], []);
            testCase.verifyTrue(contains(strjoin(string(c.targetAxes.Title.String), " "), "推定の分散 Y（GPR）"));
            names = string(c.targetResultTable.Data.Properties.VariableNames);
            testCase.verifyTrue(all(ismember(["分散 X [nm²]", "分散 Y [nm²]"], names)));
            file = [tempname, '.xlsx'];
            fileCleanup = onCleanup(@() delete(file));
            app.exportTargetsTo(file);
            sheet = readtable(file, 'Sheet', '推定値', 'VariableNamingRule', 'preserve');
            testCase.verifyTrue(all(ismember(["推定の分散X[nm2]", "推定の分散Y[nm2]"], string(sheet.Properties.VariableNames))));
            polynomialRun = app.estimateTargets(1, "all", polynomialIndex);
            testCase.verifyTrue(all(isnan(polynomialRun.estimates.varianceX)));
            testCase.verifyFalse(any(string(c.targetResultTable.Data.Properties.VariableNames) == "分散 X [nm²]"));
            testCase.verifyTrue(contains(strjoin(string(c.targetAxes.Title.String), " "), "GPR の手法だけ"));
        end
    end
end
