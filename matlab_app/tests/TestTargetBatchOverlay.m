classdef TestTargetBatchOverlay < matlab.unittest.TestCase
    %TESTTARGETBATCHOVERLAY 未知の座標の推定：Wafer の外の点（推定値 0・図から除く）、Wafer × 学習データの一括推定、
    %   推定した後の重ね合わせ補正値（補正モデルの当てはめ・係数・Excel の書き出し）を確かめる。

    properties
        Data
        Settings
        Method
        Root
    end

    methods (TestClassSetup)
        function loadSample(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.Root);
            raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            testCase.Data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            settings = alignest.defaultSettings();
            settings.overlay.waferOrder = 1;
            settings.overlay.shotCommon = "linear";
            settings.overlay.perShot = "translation";
            testCase.Settings = settings;
            methods = alignest.buildMethodList(alignest.recommendedMethods('all'));
            testCase.Method = methods(string({methods.id}) == "XY5");
        end
    end

    methods (Test)
        function pointsOutsideTheWaferAreZero(testCase)
            % 半径 150 mm 以上（境界の上も）の点は推定の対象外で、推定値は X・Y とも 0。外挿にも数えない
            unit = testCase.Data.units(1);
            targets = alignest.targetTemplate(3);
            targets.name = ["中"; "境界"; "外"];
            targets.Xmm = [10; 150; 120];
            targets.Ymm = [0; 0; 120];
            result = alignest.predictTargets(unit, 1:numel(unit.shots.shotNo), testCase.Method, testCase.Settings, targets);
            testCase.verifyEqual(result.table.outsideWafer, [false; true; true]);
            testCase.verifyEqual(result.table{2:3, ["estimateX", "estimateY"]}, zeros(2, 2));
            testCase.verifyTrue(all(isfinite(result.table{1, ["estimateX", "estimateY"]})));
            testCase.verifyNotEqual(result.table.estimateX(1), 0);
            testCase.verifyFalse(any(result.table.extrapolated(2:3)), "Wafer の外の点は外挿に数えない");
            testCase.verifyEqual(result.nOutsideWafer, 2);
            testCase.verifyTrue(any(contains(result.messages, "Wafer の外")));
            % 推定値は、Wafer の外の点を除いて推定したときと同じ
            inside = alignest.predictTargets(unit, 1:numel(unit.shots.shotNo), testCase.Method, testCase.Settings, ...
                targets(1, :));
            testCase.verifyEqual(result.table.estimateX(1), inside.table.estimateX(1), 'AbsTol', 1e-12);
            % 図には Wafer の外の点を描かない（Wafer の中の点だけの結果と同じ図になる）
            figureHandle = figure('Visible', 'off');
            closeFigure = onCleanup(@() close(figureHandle));
            ax = axes(figureHandle);
            alignest.plot.targetMap(ax, result, unit, mode="X");
            drawn = drawnCoordinates(ax);
            alignest.plot.targetMap(ax, inside, unit, mode="X");
            testCase.verifyEqual(drawn, drawnCoordinates(ax));
            testCase.verifyError(@() alignest.predictTargets(unit, 1:5, testCase.Method, testCase.Settings, ...
                targets(3, :)), 'alignest:targetsOutsideWafer');
        end

        function overlayCorrectionMatchesTheProjector(testCase)
            % 未知の座標が無ければ、補正量は評価の Overlay 補正の射影（実測値の当てはめ）と同じ。係数で補正量を作り直せる
            unit = testCase.Data.units(1);
            allShots = 1:numel(unit.shots.shotNo);
            empty = alignest.predictTargets(unit, allShots, testCase.Method, testCase.Settings, ...
                alignest.targetsAtShots(unit, 0, 0)).table([], :);
            correction = alignest.targetOverlayCorrection(unit, allShots, testCase.Method, testCase.Settings, empty);
            choice = alignest.overlayChoice(testCase.Settings);
            projector = alignest.overlayProjector(unit, choice, testCase.Settings.data.waferRadiusMm);
            index = projector.X.index;
            expected = projector.X.basis * (projector.X.basis.' * unit.marks.measX(index));
            testCase.verifyEqual(correction.points.correctionX, expected, 'AbsTol', 1e-9);
            testCase.verifyEqual(unique(correction.points.source), "実測値（学習点）");
            % 重なる項（Shot 共通の k1・Shot ごとの並進の一部）は 0 にしてメモを書く
            coefficients = correction.coefficients;
            dropped = coefficients(coefficients.note ~= "", :);
            testCase.verifyNotEmpty(dropped);
            testCase.verifyTrue(all(dropped.value == 0));
            testCase.verifyTrue(any(coefficients.term == "k1" & coefficients.component == "shotCommon" & ...
                coefficients.note ~= ""));
            % 係数（mm の単位）から X の補正量を作り直す：Wafer 成分の 1・x・y（Shot 中心）と Shot 共通の k3・k5（Shot 内）
            % と Shot ごとの k1
            marks = unit.marks;
            rows = coefficients.axis == "X";
            part = coefficients(rows, :);
            rebuilt = zeros(numel(index), 1);
            for k = 1:height(part)
                term = part(k, :);
                switch term.component
                    case "wafer"
                        powers = sscanfPowers(term.term);
                        rebuilt = rebuilt + term.value * marks.Xmm(index) .^ powers(1) .* marks.Ymm(index) .^ powers(2);
                    case "shotCommon"
                        inner = extractBetween(term.term + "（1）", "（", "）");   % "k3（x）" → "x"、"k1" → "1"
                        powers = sscanfPowers(inner(1));
                        rebuilt = rebuilt + term.value * marks.markXmm(index) .^ powers(1) .* marks.markYmm(index) .^ powers(2);
                    otherwise
                        rebuilt = rebuilt + term.value * (marks.shotNo(index) == term.shotNo);
                end
            end
            testCase.verifyEqual(rebuilt, expected, 'AbsTol', 1e-6, "係数で補正量を作り直せる");
        end

        function overlayUsesEstimatesAndTargets(testCase)
            % 学習パターンでは、学習点は実測値、学習しなかった Mark は推定値、未知の座標は推定値を使う
            unit = testCase.Data.units(1);
            train = 1:3:numel(unit.shots.shotNo);
            targets = alignest.targetsAtShots(unit, 2, -3, 9);
            result = alignest.predictTargets(unit, train, testCase.Method, testCase.Settings, targets);
            correction = alignest.targetOverlayCorrection(unit, train, testCase.Method, testCase.Settings, result.table);
            counts = arrayfun(@(name) nnz(correction.points.source == name), ["実測値（学習点）", ...
                "推定値（学習しなかった Mark）", "推定値（未知の座標）"]);
            reference = alignest.estimateWafer(unit, train, testCase.Method, testCase.Settings);
            testCase.verifyEqual(counts(1), numel(union(reference.trainIndex.X, reference.trainIndex.Y)));
            testCase.verifyEqual(counts(2), numel(union(reference.testIndex.X, reference.testIndex.Y)));
            testCase.verifyEqual(counts(3), height(targets));
            targetRows = correction.points.source == "推定値（未知の座標）";
            testCase.verifyEqual(correction.points.valueX(targetRows), result.table.estimateX, 'AbsTol', 1e-12);
            testCase.verifyEqual(correction.points.residualX, correction.points.valueX - correction.points.correctionX, ...
                'AbsTol', 1e-12);
            summary = correction.summary;
            testCase.verifyEqual(summary.n(summary.axis == "X" & summary.source == "全体"), ...
                nnz(isfinite(correction.points.valueX)));
            noModel = testCase.Settings;
            noModel.overlay.waferOrder = 0;
            noModel.overlay.shotCommon = "none";
            noModel.overlay.perShot = "none";
            testCase.verifyError(@() alignest.targetOverlayCorrection(unit, train, testCase.Method, noModel, ...
                result.table), 'alignest:overlayModel');
        end

        function appBatchEstimateAndOverlay(testCase)
            % 画面：Wafer 2枚 × 学習データ 2つを一括で推定し、組み合わせごとの図・重ね合わせ補正・Excel の書き出し
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.xlsx'));
            app.applyMapping();
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods('none');
            settings.methods.polynomial.enabled = true;
            settings.sampling.method = "random";
            settings.sampling.randomRepeats = 1;
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(20, 20, 10);
            settings.overlay = testCase.Settings.overlay;
            app.setSettings(settings);
            app.runEvaluationNow(false);
            app.setTargetPoints(alignest.targetGrid(50, 160));   % 半径 150 mm 以上の点も入る
            label = app.Results.plans(1).label;
            run = app.estimateTargets([1, 2], ["all", label], 1);
            testCase.verifyEqual(numel(run.results), 4);
            testCase.verifyEqual(run.labels(2), app.Data.units(1).label + "｜学習パターン：" + label);
            nTargets = size(app.Controls.targetTable.Data, 1);
            testCase.verifyEqual(height(run.estimates), 4 * nTargets);
            outside = run.estimates.outsideWafer;
            testCase.verifyTrue(any(outside));
            testCase.verifyEqual(run.estimates{outside, ["estimateX", "estimateY"]}, zeros(nnz(outside), 2));
            testCase.verifyTrue(any(contains(app.Controls.targetMessage.Value, "Wafer の外")));
            testCase.verifyEqual(numel(app.Controls.targetCombination.Items), 4);
            app.Controls.targetCombination.Value = 3;
            app.Controls.targetCombination.ValueChangedFcn([], []);
            testCase.verifyTrue(any(contains(string(app.Controls.targetAxes.Title.String), app.Data.units(2).label)), ...
                "題名（2行）に Wafer の名前");
            overlay = app.computeTargetOverlay();
            testCase.verifyEqual(numel(overlay), 4);
            testCase.verifyGreaterThan(height(app.Controls.targetOverlayTable.Data), 0);
            testCase.verifyTrue(contains(app.Controls.targetOverlayInfo.Text, app.Data.units(2).label));
            file = [tempname, '.xlsx'];
            removeFile = onCleanup(@() delete(file));
            app.exportTargetsTo(file);
            testCase.verifyEqual(string(sheetnames(file)).', ["説明", "推定値", "補正値", "補正の残差", "補正に使った点"]);
            coefficients = readtable(file, 'Sheet', '補正値', 'VariableNamingRule', 'preserve', 'TextType', 'string');
            testCase.verifyEqual(numel(unique(coefficients.("組み合わせ"))), 4);
            again = alignest.readTargetPoints(file);
            testCase.verifyEqual(height(again), height(run.estimates), "書き出した推定値をそのまま読める");
        end
    end
end

function coordinates = drawnCoordinates(ax)
% 図に描いたもの（線・点）の座標を、種類ごとに並べる（同じ図かを比べるため）
items = findobj(ax, '-property', 'XData');
coordinates = sort(arrayfun(@(item) string(class(item)) + ":" + strjoin(compose("%.6f", [item.XData(:); ...
    item.YData(:)]), ","), items));
end

function powers = sscanfPowers(term)
% 項の名前（"1"・"x"・"y"・"x^2·y" など）から x・y のべき
term = string(term);
powers = [0, 0];
if term == "1" || term == "定数"
    return
end
for factor = split(term, "·").'
    parts = split(factor, "^");
    exponent = 1;
    if numel(parts) > 1
        exponent = str2double(parts(2));
    end
    powers(1 + (parts(1) == "y")) = exponent;
end
end
