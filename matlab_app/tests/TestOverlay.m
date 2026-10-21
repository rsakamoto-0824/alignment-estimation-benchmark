classdef TestOverlay < matlab.unittest.TestCase
    %TESTOVERLAY 推定誤差による Overlay 補正の残差の変化（実測値で補正・推定値で補正・推定による変化）を確かめる。

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
        function makerFormulasAreTheRuleFormulas(testCase)
            % Overlay 計測ルールの Shot 高次補正の式（項・係数番号・変数・符号）そのもの
            expected = struct( ...
                "asml", ["k1 + k3*x + k5*y + k7*x^2 + k11*y^2 + k13*x^3 + k19*y^3", ...
                "k2 + k4*y + k6*x + k8*y^2 + k10*x*y + k12*x^2 + k14*y^3 + k16*x*y^2"], ...
                "canon", ["k1 + k3*x + k5*y + k9*x*y + k11*y^2 + k17*x*y^2 + k19*y^3 + k27*x*y^3", ...
                "k2 + k4*y + k6*x + k8*y^2 + k10*x*y + k14*y^3 + k16*x*y^2 + k24*x*y^3"], ...
                "nikon", ["k1 + k3*x + k5*y + k7*x^2 + k9*x*y + k11*y^2 + k13*x^3 + k17*x*y^2 + k19*y^3 + k29*y^4 + k41*y^5 + k55*y^6", ...
                "k2 + k4*y + k6*x + k8*y^2 + k10*x*y + k12*x^2 + k14*y^3 + k16*x*y^2 + k18*x^2*y + k22*y^4 + k24*x*y^3 + k32*y^5 + k34*x*y^4 + k44*y^6 + k46*x*y^5"], ...
                "linear", ["k1 + k3*x + k5*y", "k2 + k4*y + k6*x"]);
            for model = string(fieldnames(expected)).'
                terms = alignest.overlayTerms(model);
                testCase.verifyEqual([formula(terms.dx), formula(terms.dy)], expected.(model), model);
            end
            testCase.verifyError(@() alignest.overlayTerms("zeiss"), 'alignest:overlayModel');
        end

        function correctionResidualsFollowTheDefinitions(testCase)
            unit = testCase.Data.units(1);
            marks = unit.marks;
            % 補正モデル（Wafer 1次 + Shot 共通 1次 + Shot ごとの並進）でちょうど表せる場は、実測値で補正すると残差 0
            shotOffset = 0.3 * sin(marks.shotIndex);
            unit.marks.measX = 2 + 5 * marks.Xmm / 150 - 3 * marks.Ymm / 150 + 0.4 * marks.markXmm + shotOffset;
            unit.marks.measY = -1 + 2 * marks.Xmm / 150 + 0.2 * marks.markYmm - 0.1 * marks.markXmm - shotOffset;
            settings = alignest.defaultSettings();
            settings.overlay.perShot = "translation";
            choice = alignest.overlayChoice(settings);
            projector = alignest.overlayProjector(unit, choice, 150);
            trainShots = 1:3:numel(unit.shots.shotNo);
            method = alignest.buildMethodList(polynomialOnly()).';
            out = alignest.estimateWafer(unit, trainShots, method(1), settings);
            result = alignest.overlayCorrection(unit, out, projector);
            fields = result.fields;
            testCase.verifyLessThan(max(abs(fields.residualActual), [], 'all'), 1e-9);
            % 推定による変化 = 推定値で補正した残差 − 実測値で補正した残差
            testCase.verifyEqual(fields.change, fields.residualEstimated - fields.residualActual, 'AbsTol', 1e-10);
            testCase.verifyEqual(result.metrics.overlayIncrease_X, ...
                result.metrics.overlayEstimated_X - result.metrics.overlayActual_X, 'AbsTol', 1e-12);
            % 推定が完全なら、推定値で補正しても残差は同じ
            perfect = out;
            perfect.estimate.X = unit.marks.measX(out.testIndex.X);
            perfect.estimate.Y = unit.marks.measY(out.testIndex.Y);
            same = alignest.overlayCorrection(unit, perfect, projector);
            testCase.verifyLessThan(max(abs(same.fields.change), [], 'all'), 1e-9);
            testCase.verifyEqual(same.metrics.overlayIncrease_Y, 0, 'AbsTol', 1e-9);
        end

        function perShotTranslationChangesOnlyEstimatedShots(testCase)
            unit = testCase.Data.units(2);
            settings = alignest.defaultSettings();
            settings.overlay = struct("waferOrder", 0, "shotCommon", "none", "perShot", "translation");
            projector = alignest.overlayProjector(unit, alignest.overlayChoice(settings), 150);
            trainShots = 1:4:numel(unit.shots.shotNo);
            methods = alignest.buildMethodList(polynomialOnly());
            out = alignest.estimateWafer(unit, trainShots, methods(1), settings);
            result = alignest.overlayCorrection(unit, out, projector);
            marks = unit.marks;
            inTrain = ismember(marks.shotIndex, trainShots);
            change = result.fields.change(:, 1);
            testCase.verifyLessThan(max(abs(change(inTrain & marks.validX))), 1e-9, "学習 Shot の Shot ごとの補正は実測値と同じ");
            % 評価 Shot では、Shot ごとの並進 = その Shot の (計測値 − 推定値) の平均
            difference = nan(numel(marks.x), 1);
            difference(out.testIndex.X) = marks.measX(out.testIndex.X) - out.estimate.X;
            shot = marks.shotIndex(out.testIndex.X(1));
            members = marks.shotIndex == shot & marks.validX;
            testCase.verifyEqual(change(members), repmat(mean(difference(members)), nnz(members), 1), 'AbsTol', 1e-9);
        end

        function largerModelsLeaveSmallerResiduals(testCase)
            unit = testCase.Data.units(3);
            settings = alignest.defaultSettings();
            methods = alignest.buildMethodList(polynomialOnly());
            out = alignest.estimateWafer(unit, 1:3:numel(unit.shots.shotNo), methods(1), settings);
            previous = Inf;
            % 項を増やす順（Wafer 1次 → Shot 共通 1次 → Nikon 高次 → Shot ごとの 1次）では残差が増えない
            models = {struct("waferOrder", 1, "shotCommon", "none", "perShot", "none"), ...
                struct("waferOrder", 1, "shotCommon", "linear", "perShot", "none"), ...
                struct("waferOrder", 3, "shotCommon", "nikon", "perShot", "none"), ...
                struct("waferOrder", 3, "shotCommon", "nikon", "perShot", "linear")};
            for k = 1:numel(models)
                settings.overlay = models{k};
                choice = alignest.overlayChoice(settings);
                result = alignest.overlayCorrection(unit, out, alignest.overlayProjector(unit, choice, 150));
                testCase.verifyLessThanOrEqual(result.metrics.overlayActual_X, previous + 1e-9, choice.description);
                previous = result.metrics.overlayActual_X;
            end
            for model = ["asml", "canon"]
                settings.overlay = struct("waferOrder", 1, "shotCommon", model, "perShot", "none");
                result = alignest.overlayCorrection(unit, out, ...
                    alignest.overlayProjector(unit, alignest.overlayChoice(settings), 150));
                testCase.verifyTrue(all(isfinite(cell2mat(struct2cell(result.metrics)))), model);
            end
        end

        function choiceIsValidatedAndLegacyMeansDisabled(testCase)
            settings = alignest.defaultSettings();
            choice = alignest.overlayChoice(settings);
            testCase.verifyTrue(choice.enabled);
            testCase.verifyTrue(contains(choice.description, "Wafer 成分 1次"));
            testCase.verifyFalse(alignest.overlayChoice(rmfield(settings, "overlay")).enabled);
            settings.overlay = struct("waferOrder", 0, "shotCommon", "none", "perShot", "none");
            testCase.verifyFalse(alignest.overlayChoice(settings).enabled);
            settings.overlay.waferOrder = 7;
            testCase.verifyError(@() alignest.overlayChoice(settings), 'alignest:overlayModel');
            settings.overlay.waferOrder = 1;
            settings.overlay.perShot = "quadratic";
            testCase.verifyError(@() alignest.overlayChoice(settings), 'alignest:overlayModel');
        end

        function evaluationRecordsOverlayMetricsAndExports(testCase)
            data = testCase.Data;
            data.units = data.units(1:2);
            settings = alignest.defaultSettings();
            settings.sampling.nShots = [10, 20];
            settings.methods = polynomialOnly();
            results = alignest.runEvaluation(data, settings);
            testCase.verifyTrue(results.overlayEvaluated);
            overlayNames = alignest.overlayMetricNames();
            values = results.table{:, overlayNames};
            testCase.verifyTrue(all(isfinite(values), 'all'));
            % 実測値で補正した残差は Wafer で決まり、学習パターン・手法によらない
            first = results.table(results.table.unitIndex == 1, :);
            testCase.verifyEqual(first.overlayActual_X, repmat(first.overlayActual_X(1), height(first), 1), 'AbsTol', 1e-12);
            % 集計もできる（推定による変化の大きさは 0 以上）
            summary = alignest.summarizeResults(results, "overlayChange_X", "mean");
            testCase.verifyGreaterThanOrEqual(summary.values, 0);
            file = [tempname, '.xlsx'];
            cleanup = onCleanup(@() delete(file));
            alignest.exportResults(results, file, "sample.xlsx");
            perWafer = readtable(file, 'Sheet', 'Waferごと', 'VariableNamingRule', 'preserve');
            [~, labels] = alignest.overlayMetricNames();
            testCase.verifyTrue(all(ismember(labels, string(perWafer.Properties.VariableNames))));
            statistics = readtable(file, 'Sheet', '集計_統計量', 'VariableNamingRule', 'preserve');
            testCase.verifyTrue(any(contains(string(statistics.("指標")), "OVL 推定による増加")));
            % 補正モデルがすべて「なし」なら評価しない
            settings.overlay = struct("waferOrder", 0, "shotCommon", "none", "perShot", "none");
            results = alignest.runEvaluation(data, settings);
            testCase.verifyFalse(results.overlayEvaluated);
            testCase.verifyTrue(all(isnan(results.table{:, overlayNames}), 'all'));
        end
    end
end

function text = formula(terms)
% 項の表 [k, x のべき, y のべき] を「k3*x + k5*y」の形の文字にする
parts = strings(1, size(terms, 1));
for row = 1:size(terms, 1)
    factors = "k" + terms(row, 1);
    for variable = 1:2
        power = terms(row, 1 + variable);
        letter = ["x", "y"];
        if power == 1
            factors = factors + "*" + letter(variable);
        elseif power > 1
            factors = factors + "*" + letter(variable) + "^" + power;
        end
    end
    parts(row) = factors;
end
text = strjoin(parts, " + ");
end

function methods = polynomialOnly()
methods = alignest.recommendedMethods("none");
methods.polynomial.enabled = true;
methods.polynomial.order = 3;
end
