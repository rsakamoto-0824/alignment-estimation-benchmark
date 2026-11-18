classdef TestVarianceDecomposition < matlab.unittest.TestCase
    %TESTVARIANCEDECOMPOSITION ばらつき分解（Lot 間・Wafer 間・Scan 方向間・Shot 間・その他）：手で決めた値での分け方と合計、
    %   「1. データ読込」の「ばらつき分解」（Operation ごとの棒・装置の切り替え）、「4. 結果一覧」の「補正残差のばらつき分解」
    %   （補正で Wafer 間のばらつきが変わること）を確かめる。

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
        function nestedPartsAddUpToTheVariance(testCase)
            % 釣り合った入れ子（Lot 2 × Wafer 2 × Scan 方向 2 × Shot 2 × 点 2）で、段ごとに ± の差を足した値は、段の分散が
            % 差の2乗になり、足すと値の分散（点の数で割る）になる
            effects = [4, 3, 2, 1, 0.5];   % Lot・Wafer・Scan 方向・Shot・点の差（上の段の中で ±）
            [lotIndex, waferIndex, scanIndex, shotIndex, pointIndex] = ndgrid(1:2, 1:2, 1:2, 1:2, 1:2);
            signOf = @(index) 2 * index(:) - 3;   % 1 → −1、2 → +1
            values = 10 + effects(1) * signOf(lotIndex) + effects(2) * signOf(waferIndex) + effects(3) * signOf(scanIndex) + ...
                effects(4) * signOf(shotIndex) + effects(5) * signOf(pointIndex);
            shotNo = 2 * (scanIndex(:) - 1) + shotIndex(:);   % Wafer の中で Shot ごとに違う番号（実際の Shot と同じ）
            points = table(repmat("A", numel(values), 1), "L" + lotIndex(:), "W" + lotIndex(:) + "-" + waferIndex(:), ...
                scanIndex(:), shotNo, values, -2 * values, 'VariableNames', ["category", "lot", "wafer", "scan", ...
                "shot", "valueX", "valueY"]);
            result = alignest.varianceDecomposition(points);
            testCase.verifyEqual(result.components, ["Lot 間", "Wafer 間", "Scan 方向間", "Shot 間", "その他"]);
            x = result.table(result.table.axis == "X", :);
            testCase.verifyEqual(x.variance.', effects .^ 2, 'AbsTol', 1e-12);
            testCase.verifyEqual(sum(x.percent), 100, 'AbsTol', 1e-9);
            testCase.verifyEqual(result.totals.variance, [var(values, 1); var(-2 * values, 1)], 'AbsTol', 1e-9);
            y = result.table(result.table.axis == "Y", :);
            testCase.verifyEqual(y.variance.', 4 * effects .^ 2, 'AbsTol', 1e-9, "値を2倍すると分散は4倍");
            % Lot が1つ・Scan 方向が分からないときは、その段を分けない（その分は下の段に入る）
            points.lot(:) = "L1";
            points.scan(:) = NaN;
            merged = alignest.varianceDecomposition(points);
            testCase.verifyEqual(merged.components, ["Wafer 間", "Shot 間", "その他"]);
            testCase.verifyFalse(merged.useLot);
            testCase.verifyFalse(merged.useScan);
            xm = merged.table(merged.table.axis == "X", :);
            testCase.verifyEqual(xm.variance.', [effects(1) ^ 2 + effects(2) ^ 2, effects(3) ^ 2 + effects(4) ^ 2, ...
                effects(5) ^ 2], 'AbsTol', 1e-12, "Lot の分は Wafer 間、Scan 方向の分は Shot 間に入る");
            % 値の無い点は使わず、棒（category）ごとに分ける。点の無い棒は NaN
            points.valueX(1:4) = NaN;
            points.category(17:end) = "B";
            split = alignest.varianceDecomposition(points, categories=["A", "B", "C"]);
            testCase.verifyEqual(split.totals.n(split.totals.axis == "X").', [12, 16, 0]);
            testCase.verifyTrue(all(isnan(split.table.variance(split.table.category == "C"))));
            testCase.verifyError(@() alignest.varianceDecomposition(points, valueColumns="valueX", axisNames=["X", "Y"]), ...
                'alignest:varianceDecomposition');
        end

        function importedDataIsSplitByOperationAndEqp(testCase)
            % 「1. データ読込」の「ばらつき分解」：Operation ごとの棒、Lot が2つ以上なら Lot 間、Scan 方向があれば Scan 方向間。
            % 装置を選ぶとその装置の計測だけ。段を足すと有効な計測値の分散になる
            raw = readtable(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'), 'TextType', 'string');
            later = ismember(raw.Wafer, ["SIM04", "SIM05"]);
            raw.Operation(later) = "OP-M2-ALIGN";
            raw.LotID(raw.Wafer == "SIM02") = "LOTSIM02";
            file = [tempname, '.csv'];
            writetable(raw, file);
            cleanupFile = onCleanup(@() delete(file));
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(file);
            app.applyMapping();
            c = app.Controls;
            result = app.DataVariance;
            testCase.verifyNotEmpty(result, "読み込むと一度分ける");
            testCase.verifyEqual(result.categories, ["OP-M1-ALIGN", "OP-M2-ALIGN"], "Operation ごとの棒");
            testCase.verifyEqual(result.components, ["Lot 間", "Wafer 間", "Scan 方向間", "Shot 間", "その他"]);
            testCase.verifyEqual(string(c.varianceEqp.Items), ["すべての装置", "装置 EXP01", "装置 EXP02"]);
            testCase.verifyEqual(string(c.varianceEqp.Enable), "on");
            units = app.Data.units;
            first = units(string({units.operation}) == "OP-M1-ALIGN");
            marks = [first.marks];
            values = vertcat(marks.measX);
            valid = logical(vertcat(marks.validX));
            parts = result.table(result.table.category == "OP-M1-ALIGN" & result.table.axis == "X", :);
            testCase.verifyEqual(sum(parts.variance), var(values(valid), 1), 'RelTol', 1e-10, "足すと分散");
            testCase.verifyGreaterThan(parts.variance(parts.component == "Lot 間"), 0);
            testCase.verifyNotEmpty(c.varianceAxes(1).Children);
            testCase.verifyEqual(height(c.varianceTable.Data), 2 * 2 * 6, "棒 × 軸 × （5つの段と全体）");
            one = app.decomposeDataVariance("EXP02");
            testCase.verifyEqual(one.nUnits, nnz(string({units.eqpId}) == "EXP02"));
            testCase.verifyEqual(one.categories, "OP-M2-ALIGN", "EXP02 の計測は2つ目の Operation だけ");
            testCase.verifyFalse(one.useLot, "その装置の計測の Lot は1つ");
            testCase.verifyTrue(contains(string(c.varianceInfo.Text), "装置 EXP02"));
            testCase.verifyError(@() app.decomposeDataVariance("NONE"), 'alignest:varianceDecomposition');
            % 1変数の推定：値の名前の1列だけ
            spec = struct("scalar", true, "name", "Thickness_nm", "unit", "nm");
            scalar = alignest.dataVarianceDecomposition(units, "", spec);
            testCase.verifyEqual(scalar.axes, "Thickness_nm");
        end

        function correctionChangesWaferToWaferVariation(testCase)
            % 「4. 結果一覧」の「補正残差のばらつき分解」：補正前の値と、実測値・推定値で補正した残差（足す成分のある段階）を
            % 並べる。Wafer 成分（定数を含む）で Wafer ごとに補正すると、実測値で補正した残差の Wafer 間はほぼ 0 になる
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            c = app.Controls;
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.sampling.nShots = 20;
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(20, 20, 10);
            app.setSettings(settings);
            app.runEvaluationNow(false);
            testCase.verifyEqual(string(c.correctionVarianceButton.Enable), "on");
            testCase.verifyError(@() app.decomposeCorrectionVariance(), 'alignest:varianceDecomposition', ...
                "比べる前は分けられない");
            comparison = app.compareEstimatedCorrection(1, app.Results.groups(end), 0);
            testCase.verifyEqual(comparison.stageUsed, [true, false, true], "初期の補正モデル：Wafer 成分と Shot ごとの成分");
            testCase.verifyEqual(height(comparison.points), sum(arrayfun(@(unit) numel(unit.marks.x), app.Data.units)));
            result = app.CorrectionVariance;
            testCase.verifyNotEmpty(result, "比べると、ばらつき分解も描く");
            testCase.verifyEqual(result.categories, ["補正前", "実測・Wafer 成分", "推定・Wafer 成分", "実測・全成分", ...
                "推定・全成分"]);
            testCase.verifyEqual(result.nWafers, numel(app.Data.units));
            pick = @(category, component) result.table.variance(result.table.category == category & ...
                result.table.axis == "X" & result.table.component == component);
            total = @(category) result.totals.variance(result.totals.category == category & result.totals.axis == "X");
            testCase.verifyGreaterThan(pick("補正前", "Wafer 間"), 0.01 * total("補正前"));
            testCase.verifyLessThan(pick("実測・Wafer 成分", "Wafer 間"), 1e-9 * total("補正前"), ...
                "Wafer ごとの補正で Wafer 間はほぼ 0");
            testCase.verifyLessThan(pick("実測・全成分", "Shot 間"), 1e-9 * total("補正前"), "Shot ごとの補正で Shot 間はほぼ 0");
            testCase.verifyEqual(result.totals.n(result.totals.axis == "X"), ...
                repmat(comparison.table.n(comparison.table.wafer == "すべての Wafer" & ...
                comparison.table.scope == "すべての点" & comparison.table.axis == "X"), 5, 1), "「実測値と推定値の補正」と同じ点");
            testCase.verifyNotEmpty(c.correctionVarianceAxes(3).Children);
            testCase.verifyTrue(contains(string(c.correctionVarianceInfo.Text), "Wafer 間"));
            target = app.decomposeCorrectionVariance(result.methodPlan, "推定対象の点");
            testCase.verifyLessThan(target.totals.n(1), result.totals.n(1));
            % 1枚だけなら Wafer 間は 0 と知らせる
            app.compareEstimatedCorrection(1, app.Results.groups(end), 1);
            testCase.verifyEqual(app.CorrectionVariance.nWafers, 1);
            testCase.verifyTrue(contains(string(c.correctionVarianceInfo.Text), "Wafer が1枚"));
        end
    end
end
