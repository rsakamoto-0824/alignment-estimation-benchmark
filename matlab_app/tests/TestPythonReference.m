classdef TestPythonReference < matlab.unittest.TestCase
    %TESTPYTHONREFERENCE Python 版（前回の評価に使った src/）と同じ計算結果になるかを確かめる。
    %   基準値は reference/make_python_reference.py が書き出した python_reference.json
    %   （模擬データ3枚、10 Shot・20 Shot の I 最適計画）。
    %   - ハイパーパラメータ・平滑化パラメータを固定した計算（決まった計算）：丸め誤差の範囲で一致
    %   - 最適化を含む計算：最適化の方法が違う（Python は SciPy の L-BFGS-B）ので、
    %     到達した目的関数の値が Python と同じかより良いこと、推定値の差が小さいことを確かめる
    %   説明変数 XYRT（方位角 T）はツールから削除したので、基準値のうち XYRT の組は照合しない。

    properties
        Reference
        Marks
    end

    methods (TestClassSetup)
        function loadReference(testCase)
            here = fileparts(mfilename('fullpath'));
            addpath(fileparts(here));
            fileId = fopen(fullfile(here, 'reference', 'python_reference.json'), 'r', 'n', 'UTF-8');
            text = fread(fileId, '*char').';
            fclose(fileId);
            testCase.Reference = jsondecode(text);
            layout = testCase.Reference.layout;
            testCase.Marks = struct("x", layout.Xmm + layout.markXmm, "y", layout.Ymm + layout.markYmm, ...
                "markNo", layout.markNo, "direction", layout.Direction, "shotIndex", layout.shot_index, ...
                "Xmm", layout.Xmm, "Ymm", layout.Ymm);
        end
    end

    methods (Test)
        function fixedGprMatchesPython(testCase)
            for level = levelNames(testCase)
                [train, test] = split(testCase, level);
                y = testCase.Reference.wafers(1).measured(train, 1);
                for item = withoutT(testCase.Reference.levels.(level).fixed_gpr).'
                    [gp, basisTrain, basisTest] = gprCase(testCase, item.kernel, item.feature_set, item.mode, train, test);
                    label = sprintf("%s %s %s %s", level, item.kernel, item.feature_set, item.mode);
                    start = alignest.models.gprInitialParams(gp, y);
                    testCase.verifyEqual(start, item.start, 'AbsTol', 1e-12, label + " 初期値");
                    [value, gradient] = alignest.models.gprObjective(gp, item.log_params, y, basisTrain);
                    testCase.verifyEqual(value, item.value, 'RelTol', 1e-9, label + " 目的関数");
                    testCase.verifyEqual(gradient, item.gradient, 'AbsTol', 1e-7 * max(1, max(abs(item.gradient))), label + " 勾配");
                    fit = alignest.models.gprCondition(gp, item.log_params, y, basisTrain);
                    prediction = alignest.models.gprPredict(gp, fit, basisTest);
                    testCase.verifyEqual(prediction, item.prediction, 'AbsTol', 1e-7, label + " 推定値");
                    testCase.verifyEqual(fit.edf, item.edf, 'AbsTol', 1e-7, label + " 有効自由度");
                end
            end
        end

        function fittedGprReachesPythonLikelihood(testCase)
            nllGap = [];
            rmseGap = [];
            labels = strings(0, 1);
            for level = levelNames(testCase)
                [train, test] = split(testCase, level);
                for item = withoutT(testCase.Reference.levels.(level).fitted_gpr).'
                    wafer = testCase.Reference.wafers(item.wafer + 1);
                    y = wafer.measured(train, item.axis + 1);
                    truth = wafer.truth(test, item.axis + 1);
                    features = alignest.basis.distanceFeatures(testCase.Marks.x, testCase.Marks.y, item.feature_set, 150);
                    factors = factorsFor(testCase, train, test);
                    result = alignest.models.gprFitPredict(features(train, :), features(test, :), ...
                        alignest.basis.featureGroups(item.feature_set), y, item.kernel, item.mode, factors);
                    [gp, basisTrain, ~, factorTrain] = gprCase(testCase, item.kernel, item.feature_set, item.mode, train, test);
                    if item.mode == "backfit"
                        basisTrain = [ones(nnz(train), 1), factorTrain - mean(factorTrain, 1)];
                    end
                    nll = alignest.models.gprObjective(gp, result.logParams, y, basisTrain);
                    nllGap(end + 1, 1) = nll - item.nll; %#ok<AGROW>
                    rmse = sqrt(mean((result.prediction - truth) .^ 2));
                    rmseGap(end + 1, 1) = (rmse - item.rmse_truth) / item.rmse_truth; %#ok<AGROW>
                    labels(end + 1, 1) = sprintf("%s %s %s %s wafer%d axis%d", level, item.kernel, item.feature_set, ...
                        item.mode, item.wafer, item.axis); %#ok<AGROW>
                end
            end
            fprintf('GPR（最適化あり）%d 件：対数周辺尤度の差（MATLAB − Python、負なら MATLAB が良い）中央値 %.2e、最大 %.3f\n', ...
                numel(nllGap), median(nllGap), max(nllGap));
            fprintf('  真値に対する RMSE の相対差：平均 %+.3f%%、絶対値の最大 %.2f%%\n', 100 * mean(rmseGap), 100 * max(abs(rmseGap)));
            [~, worst] = max(nllGap);
            fprintf('  尤度の差が最大の例：%s\n', labels(worst));
            testCase.verifyLessThan(median(nllGap), 1e-3, "最適化で到達した尤度が Python より悪い");
            testCase.verifyLessThan(mean(nllGap > 0.05), 0.1, "Python より尤度が明らかに悪い例が多い");
            testCase.verifyLessThan(abs(mean(rmseGap)), 0.01, "推定精度の平均が Python と1%以上違う");
        end

        function tpsMatchesPython(testCase)
            grid = linspace(-8, 3, 45);
            for level = levelNames(testCase)
                [train, test] = split(testCase, level);
                for item = withoutT(testCase.Reference.levels.(level).tps).'
                    features = alignest.basis.distanceFeatures(testCase.Marks.x, testCase.Marks.y, item.feature_set, 150);
                    y = testCase.Reference.wafers(item.wafer + 1).measured(train, item.axis + 1);
                    model = alignest.models.tpsSetup(features(train, :), features(test, :), grid);
                    result = alignest.models.tpsFitPredict(model, y);
                    label = sprintf("%s TPS %s wafer%d axis%d", level, item.feature_set, item.wafer, item.axis);
                    testCase.verifyEqual(result.log10Lambda, item.log10_lambda, 'AbsTol', 1e-9, label + " λ");
                    testCase.verifyEqual(result.prediction, item.prediction, 'AbsTol', 1e-6, label + " 推定値");
                    testCase.verifyEqual(result.edf, item.edf, 'AbsTol', 1e-6, label + " 有効自由度");
                end
            end
        end

        function krigingMatchesPython(testCase)
            costGap = [];
            for level = levelNames(testCase)
                [train, test] = split(testCase, level);
                features = alignest.basis.distanceFeatures(testCase.Marks.x, testCase.Marks.y, "XYR", 150);
                for item = testCase.Reference.levels.(level).kriging.'
                    kinds = struct("OK", "ordinary", "UK", "universal");
                    model = alignest.models.krigingSetup(features(train, :), features(test, :), kinds.(item.family), item.variogram, 6);
                    y = testCase.Reference.wafers(item.wafer + 1).measured(train, item.axis + 1);
                    if model.krigingType == "universal"
                        residual = y - model.driftBasis * (model.driftBasis.' * y);
                    else
                        residual = y;
                    end
                    label = sprintf("%s %s %s wafer%d axis%d", level, item.family, item.variogram, item.wafer, item.axis);
                    [lags, semivariance] = alignest.models.krigingEmpiricalVariogram(model, residual);
                    testCase.verifyEqual(lags, item.lags, 'RelTol', 1e-10, label + " 経験バリオグラムの距離");
                    testCase.verifyEqual(semivariance, item.semivariance, 'RelTol', 1e-10, label + " 経験バリオグラム");
                    fixed = alignest.models.krigingFitPredict(model, y, fixedParams=item.params);
                    testCase.verifyEqual(fixed.prediction, item.prediction, 'AbsTol', 1e-6, label + " 推定値");
                    testCase.verifyEqual(fixed.edf, item.edf, 'AbsTol', 1e-6, label + " 有効自由度");
                    [~, cost] = alignest.models.krigingFitVariogram(item.variogram, lags, semivariance);
                    pythonCost = sum(sqrt(1 + (alignest.models.krigingVariogram(item.variogram, item.params, lags) - semivariance) .^ 2) - 1);
                    costGap(end + 1, 1) = (cost - pythonCost) / max(pythonCost, 1e-12); %#ok<AGROW>
                end
            end
            fprintf('Kriging のバリオグラムの当てはめ %d 件：損失の相対差（MATLAB − Python）最大 %.2e\n', numel(costGap), max(costGap));
            testCase.verifyLessThan(max(costGap), 1e-6, "バリオグラムの当てはめが Python より悪い");
        end

        function gamMatchesPython(testCase)
            criterionGap = [];
            predictionGap = [];
            for level = levelNames(testCase)
                [train, test] = split(testCase, level);
                factors = factorsFor(testCase, train, test);
                [scanTrain, scanTest] = alignest.basis.effectCoding(factors.scanTrain, factors.scanTest);
                [markTrain, markTest] = alignest.basis.effectCoding(factors.markTrain, factors.markTest);
                points = struct("x", testCase.Marks.x / 150, "y", testCase.Marks.y / 150, ...
                    "r", hypot(testCase.Marks.x, testCase.Marks.y) / 150);
                pick = @(index) structfun(@(v) v(index), points, 'UniformOutput', false);
                nBasis = struct("axis", 8, "radius", 8);
                for item = withoutT(testCase.Reference.levels.(level).gam).'
                    model = alignest.models.gamSetup(pick(train), pick(test), string(item.feature_set), ...
                        [scanTrain, markTrain], [scanTest, markTest], nBasis);
                    y = testCase.Reference.wafers(item.wafer + 1).measured(train, item.axis + 1);
                    label = sprintf("%s GAM %s wafer%d axis%d", level, item.feature_set, item.wafer, item.axis);
                    fixed = alignest.models.gamFitPredict(model, y, fixedLog10Lambda=item.fixed_log10_lambda);
                    testCase.verifyEqual(fixed.criterion, item.fixed_criterion, 'RelTol', 1e-8, label + " REML 基準");
                    testCase.verifyEqual(fixed.prediction, item.fixed_prediction, 'AbsTol', 1e-6, label + " 推定値（λ 固定）");
                    atPython = alignest.models.gamFitPredict(model, y, fixedLog10Lambda=item.log10_lambda);
                    % λ が探索範囲の上端（10^8）に近いと連立方程式の条件が悪く、丸め誤差が 1e-4 nm 程度になる
                    testCase.verifyEqual(atPython.prediction, item.prediction, 'AbsTol', 1e-3, label + " 推定値（Python の λ）");
                    fitted = alignest.models.gamFitPredict(model, y);
                    criterionGap(end + 1, 1) = fitted.criterion - item.criterion; %#ok<AGROW>
                    predictionGap(end + 1, 1) = max(abs(fitted.prediction - item.prediction)); %#ok<AGROW>
                end
            end
            fprintf('GAM（λ を REML で選ぶ）%d 件：基準の差（MATLAB − Python）最大 %.2e、推定値の差の最大 %.3f nm\n', ...
                numel(criterionGap), max(criterionGap), max(predictionGap));
            % 基準は数百の大きさで、λ の勾配は差分近似なので止まる位置が少し違う（推定値の差は 0.01 nm 未満）
            testCase.verifyLessThan(max(criterionGap), 1e-3, "REML 基準の最小化が Python より悪い");
            testCase.verifyLessThan(max(predictionGap), 0.01, "GAM の推定値が Python と 0.01 nm 以上違う");
        end

        function linearModelsMatchPython(testCase)
            for level = levelNames(testCase)
                [train, test] = split(testCase, level);
                xy = [testCase.Marks.x, testCase.Marks.y] / 150;
                for item = testCase.Reference.levels.(level).linear.'
                    measured = testCase.Reference.wafers(item.wafer + 1).measured(train, :);
                    order = sscanf(item.name(3:end), '%d');
                    if startsWith(item.name, "XY")
                        estimate = zeros(nnz(test), 2);
                        edf = zeros(1, 2);
                        for k = 1:2
                            result = alignest.models.polynomialFitPredict(xy(train, :), xy(test, :), measured(:, k), order);
                            estimate(:, k) = result.prediction;
                            edf(k) = result.edf;
                        end
                    else
                        result = alignest.models.rtFitPredict(xy(train, :), xy(train, :), xy(test, :), xy(test, :), ...
                            measured(:, 1), measured(:, 2), order);
                        estimate = [result.predictionU, result.predictionV];
                        edf = [result.edfU, result.edfV];
                    end
                    label = sprintf("%s %s wafer%d", level, item.name, item.wafer);
                    testCase.verifyEqual(estimate, item.prediction, 'AbsTol', 1e-6, label + " 推定値");
                    testCase.verifyEqual(edf(:), item.edf(:), 'AbsTol', 1e-8, label + " 有効自由度");
                end
            end
        end

        function metricsMatchPython(testCase)
            for level = levelNames(testCase)
                [~, test] = split(testCase, level);
                reference = testCase.Reference.levels.(level).metrics;
                truth = testCase.Reference.wafers(1).truth(test, :);
                outer = hypot(testCase.Marks.x(test), testCase.Marks.y(test)) / 150 >= 0.8;
                metrics = alignest.computeMetrics(truth(:, 1), reference.estimate(:, 1), reference.edf(1), ...
                    truth(:, 2), reference.estimate(:, 2), reference.edf(2), outer, outer);
                for name = string(fieldnames(reference.values)).'
                    if startsWith(name, "adjR2")
                        continue   % 調整済み R² は使わなくなったので比べない
                    end
                    testCase.verifyEqual(metrics.(name), reference.values.(name), 'AbsTol', 1e-12, level + " " + name);
                end
            end
        end

        function iOptimalIsAsGoodAsPython(testCase)
            sampling = alignest.defaultSettings().sampling;
            for level = levelNames(testCase)
                nShots = str2double(extractAfter(level, 1));
                unit = layoutUnit(testCase);
                spec = struct("type", "ioptimal", "nShots", nShots, "repeat", 1, "label", "", "group", "", "shotNos", []);
                plan = alignest.planTrainingShots(unit, spec, sampling, 150);
                testCase.verifyTrue(plan.ok, level + " 計画が作れない");
                testCase.verifyEqual(plan.violation, 0, level + " 制約を満たさない");
                pythonValue = testCase.Reference.levels.(level).criterion_trace;
                fprintf('I 最適 %d Shot：tr(M⁻¹) MATLAB %.4f、Python %.4f（比 %.4f）\n', nShots, plan.criterion, pythonValue, ...
                    plan.criterion / pythonValue);
                testCase.verifyLessThan(plan.criterion, 1.02 * pythonValue, level + " I 基準が Python より2%以上悪い");
            end
        end
    end

    methods
        function names = levelNames(testCase)
            names = string(fieldnames(testCase.Reference.levels)).';
        end

        function [train, test] = split(testCase, level)
            shots = testCase.Reference.levels.(level).shot_indices;
            train = ismember(testCase.Marks.shotIndex, shots);
            test = ~train;
        end

        function factors = factorsFor(testCase, train, test)
            factors = struct("scanTrain", testCase.Marks.direction(train), "scanTest", testCase.Marks.direction(test), ...
                "markTrain", testCase.Marks.markNo(train), "markTest", testCase.Marks.markNo(test));
        end

        function [gp, basisTrain, basisTest, factorTrain] = gprCase(testCase, kernel, featureSet, mode, train, test)
            features = alignest.basis.distanceFeatures(testCase.Marks.x, testCase.Marks.y, featureSet, 150);
            [gp, basisTrain, basisTest, factorTrain] = alignest.models.gprModeSetup(features(train, :), features(test, :), ...
                alignest.basis.featureGroups(featureSet), kernel, mode, factorsFor(testCase, train, test));
        end

        function unit = layoutUnit(testCase)
            % 模擬データの配置を、アプリのデータ形式（prepareData の出力と同じ形）にする
            marks = testCase.Marks;
            n = numel(marks.x);
            table_ = table(repmat("W1", n, 1), marks.shotIndex + 1, marks.direction, marks.Xmm, marks.Ymm, marks.markNo, ...
                marks.x - marks.Xmm, marks.y - marks.Ymm, zeros(n, 1), zeros(n, 1), ...
                'VariableNames', ["Wafer", "shotNo", "Direction", "Xmm", "Ymm", "markNo", "markXmm", "markYmm", "measX", "measY"]);
            data = alignest.prepareData(table_, alignest.guessColumnMapping(table_.Properties.VariableNames));
            unit = data.units(1);
        end
    end
end

function items = withoutT(items)
% 削除した説明変数の組 XYRT（方位角 T）の基準値を除く
items = items(string({items.feature_set}) ~= "XYRT");
end
