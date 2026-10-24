classdef TestLayoutDesignZernike < matlab.unittest.TestCase
    %TESTLAYOUTDESIGNZERNIKE 計測配置の選び方の比較（D 最適・人の選択・Mark 単位の I 最適）、Fringe Zernike、
    %   異常値の MAD、Slot の偶奇、Shot ごとの成分の式、Matérn の ν の時間の目安、全角の数字を確かめる。

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
        function selectionMethodsBuildComparablePlans(testCase)
            sampling = alignest.defaultSettings().sampling;
            sampling.nShots = [10, 20];
            % 選び方が1つなら、以前と同じ列の名前
            testCase.verifyEqual(string({alignest.buildPlanSpecs(sampling).group}), ["10 Shot", "20 Shot"]);
            % 複数選ぶと、選んだ順によらず I 最適 → D 最適 → 手動 → Mark 単位 の順で、列に選び方の名前が付く
            sampling.method = ["mark", "manual", "doptimal", "ioptimal"];
            sampling.manualPlans = ["担当者A: 1 5 9", "2，4，６"];
            sampling.markPerShot = [1, 1.5];
            specs = alignest.buildPlanSpecs(sampling);
            testCase.verifyEqual(string({specs.label}), ["I最適 10 Shot", "I最適 20 Shot", "D最適 10 Shot", ...
                "D最適 20 Shot", "担当者A（3 Shot）", "手動2（3 Shot）", "Mark最適 1 点/Shot", "Mark最適 1.5 点/Shot"]);
            testCase.verifyEqual(string({specs.group}), ["I最適 10 Shot", "I最適 20 Shot", "D最適 10 Shot", ...
                "D最適 20 Shot", "担当者A", "手動2", "Mark最適 1 点/Shot", "Mark最適 1.5 点/Shot"]);
            testCase.verifyEqual(specs(6).shotNos, [2, 4, 6], "全角の数字・カンマも読む");
            testCase.verifyEqual([specs(7:8).markPerShot], [1, 1.5]);
            sampling.manualPlans = ["A: 1 2", "A: 3 4"];
            testCase.verifyError(@() alignest.buildPlanSpecs(sampling), 'alignest:manualPlan', "名前が重なる");
            sampling.method = "unknown";
            testCase.verifyError(@() alignest.buildPlanSpecs(sampling), 'alignest:samplingMethod');
            sampling.method = "mark";
            sampling.markPerShot = 0.5;
            testCase.verifyError(@() alignest.buildPlanSpecs(sampling), 'alignest:markPerShot');
        end

        function dOptimalImprovesTheDCriterion(testCase)
            sampling = alignest.defaultSettings().sampling;
            sampling.exchangeStarts = 3;
            sampling.requiredShots = [1, 50];
            unit = testCase.Data.units(1);
            planI = alignest.planTrainingShots(unit, spec("ioptimal", 20), sampling, 150);
            planD = alignest.planTrainingShots(unit, spec("doptimal", 20), sampling, 150);
            testCase.verifyTrue(planD.ok);
            testCase.verifyEqual(planD.nShots, 20);
            testCase.verifyTrue(all(ismember([1, 50], planD.shotNos)), "必ず計測する Shot を外さない");
            testCase.verifyEqual(planD.violation, 0, "制約を満たす");
            testCase.verifyLessThanOrEqual(planD.criterionD, planI.criterionD * (1 + 1e-9), ...
                "D 最適は I 最適より D 基準が大きくならない");
            testCase.verifyEqual(planD.criterion, planD.criterionD, 'RelTol', 1e-6, "交換法の基準 = D 基準");
            testCase.verifyEqual(planD.nMarks, nnz(ismember(unit.marks.shotIndex, planD.shotIndex) & ...
                (unit.marks.validX | unit.marks.validY)));
        end

        function markLevelPlanMeasuresEveryShot(testCase)
            sampling = alignest.defaultSettings().sampling;
            sampling.exchangeStarts = 2;
            unit = testCase.Data.units(1);
            item = spec("mark", NaN);
            item.markPerShot = 1.5;
            plan = alignest.planTrainingShots(unit, item, sampling, 150);
            marks = unit.marks;
            candidates = find(unit.shots.nValidX + unit.shots.nValidY > 0);
            testCase.verifyTrue(plan.ok);
            testCase.verifyEqual(numel(plan.markIndex), round(1.5 * numel(candidates)));
            testCase.verifyEqual(plan.nMarks, numel(plan.markIndex));
            testCase.verifyTrue(all(ismember(candidates, marks.shotIndex(plan.markIndex))), "全 Shot で1点以上");
            % Mark 番号ごとの数は、全計測の割合 × 数 ± 許容幅（1）
            usable = ismember(marks.shotIndex, candidates) & (marks.validX | marks.validY);
            for level = unique(marks.markNo(usable)).'
                share = nnz(marks.markNo(usable) == level) / nnz(usable);
                count = nnz(marks.markNo(plan.markIndex) == level);
                testCase.verifyLessThanOrEqual(abs(count - share * numel(plan.markIndex)), 1 + 1);
            end
            testCase.verifyEqual(plan.violation, 0);
            testCase.verifyTrue(isfinite(plan.criterionI) && isfinite(plan.criterionD));
            % 推定は計測した Mark だけを学習に使い、同じ Shot の残りの Mark を評価する
            settings = alignest.defaultSettings();
            method = struct("id", "XY3", "family", "XY", "featureSet", "-", "variant", "order3", "factorMode", "none", ...
                "label", "XY3次多項式");
            out = alignest.estimateWafer(unit, plan, method, settings);
            testCase.verifyEmpty(intersect(out.testIndex.X, plan.markIndex));
            testCase.verifyEqual(sort([out.trainIndex.X; out.testIndex.X]), find(usable & marks.validX));
            % 同じ配置の Wafer では、計画を使い回しても同じ Mark（座標）になる
            cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
            first = alignest.cachedTrainingPlan(testCase.Data.units(1), item, struct("sampling", sampling, ...
                "data", struct("waferRadiusMm", 150)), cache);
            second = alignest.cachedTrainingPlan(testCase.Data.units(2), item, struct("sampling", sampling, ...
                "data", struct("waferRadiusMm", 150)), cache);
            testCase.verifyTrue(second.reused);
            other = testCase.Data.units(2).marks;
            testCase.verifyEqual([other.x(second.markIndex), other.y(second.markIndex)], ...
                [marks.x(first.markIndex), marks.y(first.markIndex)], 'AbsTol', 1e-9);
        end

        function humanLayoutsAreReadFromExcel(testCase)
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's'));
            file = fullfile(folder, 'layouts.xlsx');
            sheet = table((1:6).', [1; 0; 1; 0; 1; 0], [0; 1; 1; 0; 0; 1], [1; 1; 1; 1; 1; 1], ["a"; "b"; "c"; "d"; "e"; "f"], ...
                [0; 0; 1; 1; 0; 0], 'VariableNames', ["shotNo", "担当者A", "担当者B", "全部", "メモ", "最外周"]);
            writetable(sheet, file, 'Sheet', '計測マップ');
            layouts = alignest.readLayoutPlans(file);
            testCase.verifyEqual(layouts.names, ["担当者A"; "担当者B"], "全部 1 の列・文字の列・情報の列は読まない");
            testCase.verifyEqual(layouts.shotNos{1}, [1, 3, 5]);
            testCase.verifyEqual(layouts.lines, ["担当者A: 1 3 5"; "担当者B: 2 3 6"]);
            sampling = alignest.defaultSettings().sampling;
            sampling.method = "manual";
            sampling.manualPlans = layouts.lines;
            testCase.verifyEqual(string({alignest.buildPlanSpecs(sampling).group}), ["担当者A", "担当者B"]);
            writetable(table((1:3).', 'VariableNames', "番号"), fullfile(folder, 'bad.xlsx'));
            testCase.verifyError(@() alignest.readLayoutPlans(fullfile(folder, 'bad.xlsx')), 'alignest:readLayoutPlans');
        end

        function layoutComparisonGroupsBySelectionMethod(testCase)
            settings = alignest.defaultSettings();
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.methods.polynomial.order = 3;
            settings.sampling.method = ["ioptimal", "doptimal", "manual", "mark"];
            settings.sampling.nShots = [15, 25];
            settings.sampling.exchangeStarts = 2;
            settings.sampling.manualPlans = "担当者A: 1 7 13 19 25 31 37 43 49 55 61 67 73 79 85 91 97 4 22 58";
            data = testCase.Data;
            data.units = data.units(1:2);
            results = alignest.runEvaluation(data, settings);
            testCase.verifyTrue(all(results.table.note == ""));
            comparison = alignest.layoutComparison(results, 1, "RMSE_XY", "mean");
            testCase.verifyEqual(comparison.type.', ["ioptimal", "ioptimal", "doptimal", "doptimal", "manual", "mark"]);
            testCase.verifyEqual(comparison.Properties.UserData.nTypes, 4);
            testCase.verifyEqual(comparison.nShots(1:2), [15; 25]);
            testCase.verifyEqual(comparison.nMarks(6), 99, "Mark 単位（1 点/Shot）は候補 Shot 数と同じ数の Mark");
            summary = alignest.summarizeResults(results, "RMSE_XY", "mean");
            testCase.verifyEqual(comparison.value.', summary.values(1, :), 'AbsTol', 1e-12);
            % 選び方が1つの結果（列の名前に選び方が無い）でも、設定から選び方を決める
            single = settings;
            single.sampling.method = "ioptimal";
            plain = alignest.runEvaluation(data, single);
            testCase.verifyEqual(alignest.layoutComparison(plain, 1, "RMSE_XY", "mean").type.', ["ioptimal", "ioptimal"]);
        end

        function fringeZernikeFitsTheFringeTerms(testCase)
            testCase.verifyEqual(alignest.basis.fringeZernikeModes(1), [0, 0; 1, 1; 1, -1; 2, 0]);
            testCase.verifyEqual(size(alignest.basis.fringeZernikeModes(5), 1), 36, "k = 5 は Z1〜Z36");
            modes9 = alignest.basis.fringeZernikeModes(2);
            testCase.verifyEqual(modes9(9, :), [4, 0], "Z9 は球面収差（4, 0）");
            testCase.verifyError(@() alignest.basis.fringeZernikeModes(1.5), 'alignest:zernikeOrder');
            % Z1〜Z16 の組み合わせは、次数 3 でそのまま再現できる
            stream = RandStream('mt19937ar', 'Seed', 3);
            angle = 2 * pi * rand(stream, 80, 1);
            radius = sqrt(rand(stream, 80, 1));
            points = [radius .* cos(angle), radius .* sin(angle)];
            modes = alignest.basis.fringeZernikeModes(3);
            truth = randn(stream, size(modes, 1), 1);
            values = alignest.basis.zernikeMatrix(points(:, 1), points(:, 2), modes) * truth;
            result = alignest.models.zernikeFitPredict(points(1:60, :), points(61:80, :), values(1:60), 3);
            testCase.verifyEqual(result.prediction, values(61:80), 'AbsTol', 1e-9);
            testCase.verifyEqual(result.nCoef, 16);
            % 手法の一覧と推定（X・Y 別）
            config = alignest.recommendedMethods("none");
            config.zernike.enabled = true;
            config.zernike.orders = [4, 3];
            methods = alignest.buildMethodList(config);
            testCase.verifyEqual(string({methods.id}), ["FringeZ_k3", "FringeZ_k4"]);
            testCase.verifyEqual(methods(2).label, "Fringe Zernike Z1〜Z25（次数 4）");
            unit = testCase.Data.units(1);
            out = alignest.estimateWafer(unit, 1:2:99, methods(1), alignest.defaultSettings());
            testCase.verifyTrue(all(isfinite(out.estimate.X)) && all(isfinite(out.estimate.Y)));
            testCase.verifyEqual(out.edf, [16, 16], 'AbsTol', 1e-9);
            testCase.verifyTrue(alignest.completeMethodSettings(rmfield(alignest.recommendedMethods(), "zernike")).zernike.enabled == false, ...
                "以前の設定には Fringe Zernike の項目を足す（使わない）");
        end

        function madIsRobustToOutliers(testCase)
            values = [linspace(-1, 1, 18).'; 0.5; 30];   % 1点だけ大きく外れる
            marks = struct("measX", values, "measY", zeros(20, 1), "validX", true(20, 1), "validY", true(20, 1));
            inTrain = true(20, 1);
            [sigmaOutlier, sigmaStats] = alignest.trainingOutliers(marks, inTrain, 3);
            [madOutlier, madStats] = alignest.trainingOutliers(marks, inTrain, 3, "mad");
            testCase.verifyEqual(find(madOutlier).', 20, "MAD は外れた1点を見つける");
            testCase.verifyEqual(madStats.center(1), median(values));
            testCase.verifyEqual(madStats.spread(1), 1.4826 * median(abs(values - median(values))), 'AbsTol', 1e-12);
            testCase.verifyEqual(sigmaStats.center(1), mean(values), 'AbsTol', 1e-12);
            testCase.verifyEqual(sigmaStats.mean, sigmaStats.center, "以前の名前も使える");
            testCase.verifyLessThanOrEqual(nnz(sigmaOutlier), nnz(madOutlier));
            settings = alignest.defaultSettings();
            testCase.verifyEqual(alignest.outlierMethod(settings), "sigma");
            settings.evaluation = rmfield(settings.evaluation, "outlierMethod");
            testCase.verifyEqual(alignest.outlierMethod(settings), "sigma", "以前の設定は平均と σ");
        end

        function slotParityComesFromTheWaferId(testCase)
            [slot, parity] = alignest.waferSlot(["LOT123-05", "AB-12-04 (EXP01)", "SIM01", "X-", "Y-07a"]);
            testCase.verifyEqual(slot, [5, 4, NaN, NaN, 7]);
            testCase.verifyEqual(parity, ["奇数", "偶数", "", "", "奇数"]);
            units = struct("label", {"L-01", "L-02", "L-03"}, "wafer", {"L-01", "L-02", "L-03"}, "lotId", "", ...
                "eqpId", "", "operation", "");
            options = alignest.groupOptions(units, "slotParity");
            testCase.verifyEqual([options.label], ["L-01", "L-02", "L-03", "平均：Slot 奇数（2 枚）", "平均：Slot 偶数（1 枚）"]);
            testCase.verifyEqual(options(4).unitIndex, [1, 3]);
            defaults = alignest.groupOptions(units);
            testCase.verifyTrue(any([defaults.label] == "平均：Slot 偶数（1 枚）"), "既定の選択肢にも入る");
            % 残差の質的変数（ANOVA・箱ひげ図）にも入る（Slot が読めない Wafer だけなら入れない）
            points = table(["L-01"; "L-02"; "L-03"; "L-04"], [1; 1; 2; 2], [1; 2; 3; 4], [1; 2; 1; 2], ...
                strings(4, 1), strings(4, 1), strings(4, 1), 'VariableNames', ["Wafer", "direction", "markNo", ...
                "shotRowParity", "Operation", "EqpId", "LotID"]);
            factors = alignest.residualFactors(points);
            slotFactor = factors(string({factors.name}) == "Slot の偶奇");
            testCase.verifyEqual(slotFactor.levels, ["奇数"; "偶数"; "奇数"; "偶数"]);
            points.Wafer = ["A"; "B"; "C"; "D"];
            testCase.verifyFalse(any(string({alignest.residualFactors(points).name}) == "Slot の偶奇"));
        end

        function perShotFormulaMatchesTheBuiltInModel(testCase)
            unit = testCase.Data.units(1);
            settings = alignest.defaultSettings();
            settings.overlay.waferOrder = 1;
            settings.overlay.shotCommon = "none";
            settings.overlay.perShot = "linear";
            builtIn = alignest.overlayChoice(settings);
            settings.overlay.perShot = "formula";
            settings.overlay.perShotFormula = struct("dx", "c1 + c3*x + c5*y", "dy", "c2 + c4*y + c6*x");
            formula = alignest.overlayChoice(settings);
            testCase.verifyTrue(contains(formula.description, "Shot ごとの成分 入力した式（dx = c1 + c3*x + c5*y"));
            first = alignest.overlayProjector(unit, builtIn, 150);
            second = alignest.overlayProjector(unit, formula, 150);
            values = unit.marks.measX(first.X.index);
            testCase.verifyEqual(second.X.basis * (second.X.basis.' * values), first.X.basis * (first.X.basis.' * values), ...
                'AbsTol', 1e-8, "1次の式を入れると、組み込みの1次と同じ補正量");
            settings.overlay.perShotFormula.dx = "k1 + (x)";
            testCase.verifyError(@() alignest.overlayChoice(settings), 'alignest:overlayFormula');
        end

        function maternNuIsWeightedInTheTimeEstimate(testCase)
            units = testCase.Data.units;
            settings = alignest.defaultSettings();
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.methods.gpr.enabled = true;
            settings.methods.gpr.kernels = ["matern52", "matern"];
            settings.methods.gpr.maternNu = [0.75, 1, 2];
            settings.methods.gpr.factorModes = "none";
            settings.sampling.nShots = [10, 20];
            [seconds, detail] = alignest.estimateRunSeconds(units, settings);
            testCase.verifyEqual(detail.nRuns, numel(units) * 2 * 5, "XY・matern52・ν 3つ = 5 手法");
            testCase.verifyEqual(detail.nMaternNuMethods, 3);
            testCase.verifyEqual(seconds, 2 * numel(units) * 2 * (2 + 3 * 3), "ν を指定した Matérn は 1条件 6 秒");
            testCase.verifyEqual(alignest.normalizeNumberText("０．７５　２，３"), "0.75 2,3");
        end

        function siteDefaultsOverrideOnlyWrittenItems(testCase)
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's'));
            [settings, source] = alignest.siteDefaults(folder);
            testCase.verifyEqual(settings, alignest.defaultSettings(), "ファイルが無ければ初期設定のまま");
            testCase.verifyEqual(source, "");
            % 変えたい項目だけを書いた既定の設定ファイル
            file = fullfile(folder, 'alignment_estimation_defaults.json');
            fileId = fopen(file, 'w', 'n', 'UTF-8');
            fprintf(fileId, '%s', ['{"evaluation": {"outerRadiusMm": 130, "outlierMethod": "mad"}, ' ...
                '"sampling": {"method": ["ioptimal", "doptimal"], "exchangeStarts": 20, "nShotsEnd": 50, "nShotsStep": 10}}']);
            fclose(fileId);
            [settings, source] = alignest.siteDefaults(folder);
            testCase.verifyEqual(source, string(file));
            testCase.verifyEqual(settings.evaluation.outerRadiusMm, 130);
            testCase.verifyEqual(settings.evaluation.outlierMethod, "mad");
            testCase.verifyEqual(settings.sampling.method, ["ioptimal", "doptimal"]);
            testCase.verifyEqual(settings.sampling.exchangeStarts, 20);
            testCase.verifyEqual(settings.sampling.nShots, [10, 20, 30, 40, 50], "開始・終了・刻みだけ書けば並びもそれに合わせる");
            defaults = alignest.defaultSettings();
            testCase.verifyEqual(settings.methods, defaults.methods, "書いていない項目は初期設定");
            testCase.verifyEqual(settings.data, defaults.data);
            fileId = fopen(file, 'w', 'n', 'UTF-8');
            fprintf(fileId, '%s', '{"evaluation": ');
            fclose(fileId);
            testCase.verifyError(@() alignest.siteDefaults(folder), 'alignest:siteDefaults', "読めないファイルは止める");
        end

        function helpCoversKernelsAndFormulas(testCase)
            text = fileread(fullfile(testCase.Root, 'help', 'help.html'));
            for name = [alignest.models.gprKernelNames(), "matern（ν を指定）", "ardmatern（ν を指定）", ...
                    "linear", "power", "gaussian", "exponential", "spherical", "加法カーネル＋交互作用", "ASML", "Canon", ...
                    "Nikon", "k1 + k3·x + k5·y", "Fringe Zernike", "MAD", "D 最適計画", "Mark 単位の I 最適計画", ...
                    "凸包", "外挿の判定", "学習に無い Mark 番号", "RBFe（仮）", "1 の分割"]
                testCase.verifyTrue(contains(text, name), name + " の説明がヘルプにない");
            end
        end
    end
end

function item = spec(type, nShots)
item = struct("type", type, "nShots", nShots, "rate", NaN, "repeat", 1, "label", type, "group", type, ...
    "shotNos", [], "markPerShot", NaN);
end
