classdef TestMarkBalanceAndComponents < matlab.unittest.TestCase
    %TESTMARKBALANCEANDCOMPONENTS Mark 単位の最適計画の「Mark 番号ごとの計測数を均等にする」制約と、計測マップの
    %   「全計測との成分の差」（計測配置の点だけで求めた Overlay 補正の Wafer 線形・高次、Shot 共通 低次・高次の成分と、
    %   全計測で求めた成分の差）。

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
        function equalTargetsFillShortGroupsFirst(testCase)
            % 均等の数：候補の少ない区分はその数まで、残りを均等に。区分の数の下限・上限は割り切れないときの1つの差だけ
            testCase.verifyEqual(alignest.equalTargets([30; 30; 30; 10], 100), [30; 30; 30; 10]);
            testCase.verifyEqual(alignest.equalTargets([30; 30; 30; 10], 60), [50 / 3; 50 / 3; 50 / 3; 10], 'AbsTol', 1e-12);
            testCase.verifyEqual(alignest.equalTargets([5; 5], 20), [5; 5], "候補より多くは選ばない");
            labels = repelem((1:4).', 25);
            bounds = alignest.shotGroupBounds(labels, 99, 1, true);
            testCase.verifyEqual([bounds.lower, bounds.upper], repmat([24, 25], 4, 1), "均等には許容幅を使わない");
            ratio = alignest.shotGroupBounds(labels, 99, 1);
            testCase.verifyEqual([ratio.lower, ratio.upper], repmat([23, 25], 4, 1), "割合は ±許容幅");
            labels = [repelem((1:3).', 30); repmat(4, 10, 1)];
            bounds = alignest.shotGroupBounds(labels, 60, 1, true);
            testCase.verifyEqual([bounds.lower, bounds.upper], [16, 17; 16, 17; 16, 17; 10, 10]);
        end

        function markPlanCountsAreEqualPerMarkNumber(testCase)
            % 均等にする：Mark 番号ごとの計測数の差は1以下（I 最適・D 最適、1 Shot あたりの数・計測率）。全計測の割合のときより
            % そろう
            unit = testCase.Data.units(1);
            sampling = alignest.defaultSettings().sampling;
            sampling.method = ["mark", "markd"];
            sampling.markPerShot = [1, 1.5];
            sampling.exchangeStarts = 2;
            sampling.constraints.markEqual = true;
            specs = alignest.buildPlanSpecs(sampling);
            for k = 1:numel(specs)
                plan = alignest.planTrainingShots(unit, specs(k), sampling, 150);
                counts = markCounts(unit, plan);
                testCase.verifyLessThanOrEqual(max(counts) - min(counts), 1, specs(k).label);
                testCase.verifyEqual(plan.violation, 0, specs(k).label);
            end
            sampling.countBy = "rate";
            [sampling.rateStart, sampling.rateEnd, sampling.rateStep] = deal(30, 30, 10);
            sampling.method = "mark";
            spec = alignest.buildPlanSpecs(sampling);
            plan = alignest.planTrainingShots(unit, spec, sampling, 150);
            counts = markCounts(unit, plan);
            testCase.verifyLessThanOrEqual(max(counts) - min(counts), 1, "計測率でも均等");
            sampling.constraints.markEqual = false;   % 全計測の割合 ± 許容幅（初期設定）
            plan = alignest.planTrainingShots(unit, spec, sampling, 150);
            testCase.verifyEqual(sum(markCounts(unit, plan)), sum(counts));
        end

        function shortMarkNumbersAreMeasuredFully(testCase)
            % 候補の少ない Mark 番号はその数まで計測し、残りをほかの Mark 番号で均等にする（メモで知らせる）
            unit = testCase.Data.units(1);
            levels = unique(unit.marks.markNo);
            rare = unit.marks.markNo == levels(end) & mod(unit.marks.shotIndex, 4) ~= 0;   % 最後の番号を4分の1の Shot だけに
            unit.marks.validX(rare) = false;
            unit.marks.validY(rare) = false;
            sampling = alignest.defaultSettings().sampling;
            sampling.method = "mark";
            sampling.exchangeStarts = 2;
            sampling.markRequirePerShot = false;
            sampling.constraints.markEqual = true;
            plan = alignest.planTrainingShots(unit, alignest.buildPlanSpecs(sampling), sampling, 150);
            counts = markCounts(unit, plan);
            available = nnz(unit.marks.markNo == levels(end) & (unit.marks.validX | unit.marks.validY));
            testCase.verifyEqual(counts(end), available, "少ない番号は全部");
            testCase.verifyLessThanOrEqual(max(counts(1:end - 1)) - min(counts(1:end - 1)), 1, "残りは均等");
            testCase.verifyTrue(contains(plan.message, "候補の少ない Mark 番号（M" + levels(end) + "）"));
        end

        function exactFieldGivesNoDifference(testCase)
            % 雑音の無い Wafer 2次 + Shot 共通（1次と x·y）の値：計測配置の点で決まるなら差は 0、係数は真の値。全計測と同じ点
            % なら差は 0
            [unit, settings, truth] = exactUnit(testCase);
            plan = struct("markIndex", find(mod(unit.marks.shotIndex, 2) == 0 | unit.marks.markNo == 1), ...
                "shotIndex", zeros(0, 1), "ok", true);
            difference = alignest.planComponentDifference(unit, plan, settings);
            summary = difference.summary;
            testCase.verifyEqual(summary.component.', ["Wafer 線形", "Wafer 高次", "Shot 共通 低次", "Shot 共通 高次", "合計"]);
            testCase.verifyLessThan(max(abs([summary.differenceX; summary.differenceY; summary.maxX; summary.maxY])), 1e-8);
            testCase.verifyTrue(all(summary.sizeX > 0));
            coefficients = difference.coefficients;
            xx = coefficients(coefficients.axis == "X" & coefficients.term == "x^2", :);
            testCase.verifyEqual(xx.full, truth.waferXX, 'RelTol', 1e-8, "Wafer の x^2 [nm/mm^2]");
            xy = coefficients(coefficients.axis == "X" & coefficients.level == "Shot 共通 高次", :);
            testCase.verifyEqual(xy.full, truth.shotXY, 'RelTol', 1e-8, "Shot 共通の x·y [nm/mm^2]");
            testCase.verifyEqual(coefficients.full, coefficients.plan, 'AbsTol', 1e-9);
            testCase.verifyEmpty(difference.messages);
            all_ = struct("markIndex", (1:numel(unit.marks.x)).', "shotIndex", zeros(0, 1), "ok", true);
            same = alignest.planComponentDifference(unit, all_, settings);
            testCase.verifyEqual(same.summary.differenceX, zeros(5, 1), 'AbsTol', 1e-9);
        end

        function undeterminedTermsAreReported(testCase)
            % 計測配置の点の Shot 内の位置が1か所なら Shot 共通の項は決まらない：0 にしてメモと知らせ、差は全計測の成分の大きさ
            [unit, settings] = exactUnit(testCase);
            plan = struct("markIndex", find(unit.marks.markNo == 1), "shotIndex", zeros(0, 1), "ok", true);
            difference = alignest.planComponentDifference(unit, plan, settings);
            testCase.verifyTrue(any(contains(difference.messages, "計測配置の点では決まらない項")));
            rows = difference.coefficients(difference.coefficients.level == "Shot 共通 高次", :);
            testCase.verifyEqual(rows.plan, zeros(height(rows), 1));
            testCase.verifyTrue(all(contains(rows.note, "計測配置の点では")));
            high = difference.summary(difference.summary.component == "Shot 共通 高次", :);
            testCase.verifyEqual(high.differenceX, high.sizeX, 'RelTol', 1e-9, "求めない成分の差 = 全計測の成分の大きさ");
            testCase.verifyEqual(difference.nPoints(2, 1), nnz(unit.marks.markNo == 1 & unit.marks.validX));
        end

        function perShotComponentIsNotUsedAndEmptyModelIsReported(testCase)
            % Shot ごとの成分は使わない（選んでいても同じ結果）。Wafer 成分・Shot 共通成分が無ければ出さない
            [unit, settings] = exactUnit(testCase);
            plan = struct("markIndex", find(unit.marks.markNo <= 2), "shotIndex", zeros(0, 1), "ok", true);
            base = alignest.planComponentDifference(unit, plan, settings);
            settings.overlay.perShot = "translation";
            withPerShot = alignest.planComponentDifference(unit, plan, settings);
            testCase.verifyEqual(withPerShot.summary, base.summary);
            testCase.verifyTrue(contains(base.description, "Shot ごとの成分は使わない"));
            settings.overlay.waferOrder = 0;
            settings.overlay.shotCommon = "none";
            none = alignest.planComponentDifference(unit, plan, settings);
            testCase.verifyTrue(all(isnan(none.summary.sizeX)));
            testCase.verifyTrue(contains(none.messages, "成分の差は出しません"));
            testCase.verifyEmpty(none.coefficients);
        end

        function screenSetsBalanceAndShowsComponentDifferences(testCase)
            % 画面：Mark 番号ごとの計測数の欄と設定、計測マップの成分の差の表・知らせ・書き出し、Overlay 補正を変えたら表を空にする
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual(string(c.markBalance.Value), "ratio", "初期設定は全計測の割合");
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            settings.sampling.method = "mark";
            settings.sampling.exchangeStarts = 2;
            settings.overlay.waferOrder = 2;
            app.setSettings(settings);
            c.markBalance.Value = 'equal';
            c.markBalance.ValueChangedFcn([], []);
            testCase.verifyEqual([app.Settings.sampling.constraints.markRatio, app.Settings.sampling.constraints.markEqual], ...
                [true, true]);
            [plans, components] = app.drawMeasurementMap(1);
            counts = markCounts(app.Data.units(1), plans(1));
            testCase.verifyLessThanOrEqual(max(counts) - min(counts), 1);
            data = string(c.measureComponents.Data);
            testCase.verifyEqual(data(:, 2).', ["Wafer 線形", "Wafer 高次", "Shot 共通 低次", "合計"], "項の無い成分は出さない");
            testCase.verifyEqual(str2double(data(4, 5)), components(1).summary.differenceX(5), 'RelTol', 1e-2);
            filePath = [tempname, '.xlsx'];
            fileCleanup = onCleanup(@() delete(filePath));
            app.exportMeasurementMap(filePath);
            testCase.verifyTrue(all(ismember(["成分の差", "成分の係数"], sheetnames(filePath))));
            sheet = readtable(filePath, 'Sheet', '成分の差', 'VariableNamingRule', 'preserve', 'TextType', 'string');
            testCase.verifyTrue(any(sheet.("成分") == "Wafer 高次"));
            c.overlayWafer.Value = 1;
            c.overlayWafer.ValueChangedFcn([], []);   % 設定を変えると計測マップの欄を確かめ直す
            testCase.verifyEmpty(c.measureComponents.Data, "Overlay 補正を変えたら作り直す");
            c.markBalance.Value = 'none';
            c.markBalance.ValueChangedFcn([], []);
            testCase.verifyEqual([app.Settings.sampling.constraints.markRatio, app.Settings.sampling.constraints.markEqual], ...
                [false, false]);
        end
    end
end

function counts = markCounts(unit, plan)
% Mark 番号ごとの計測する Mark の数（unit の Mark 番号の小さい順）
levels = unique(unit.marks.markNo);
measured = unit.marks.markNo(plan.markIndex);
counts = arrayfun(@(level) nnz(measured == level), levels);
end

function [unit, settings, truth] = exactUnit(testCase)
% 見本の Wafer の Mark の位置に、雑音の無い Wafer 2次 + Shot 共通（1次と x·y）の値を入れる。Overlay 補正は Wafer 2次・
% Shot 共通は式（k1〜k6 と x·y）・Shot ごとはなし
unit = testCase.Data.units(1);
marks = unit.marks;
truth = struct("waferXX", 2e-4, "shotXY", 3e-3);
marks.measX = 1.5 + 0.01 * marks.Xmm - 0.004 * marks.Ymm + truth.waferXX * marks.Xmm .^ 2 + ...
    0.02 * marks.markXmm + 0.01 * marks.markYmm + truth.shotXY * marks.markXmm .* marks.markYmm;
marks.measY = -0.7 + 0.003 * marks.Xmm + 0.008 * marks.Ymm - 1e-4 * marks.Ymm .^ 2 + ...
    0.015 * marks.markYmm - 0.01 * marks.markXmm + 2e-3 * marks.markXmm .* marks.markYmm;
unit.marks = marks;
settings = alignest.defaultSettings();
settings.overlay.waferOrder = 2;
settings.overlay.shotCommon = "formula";
settings.overlay.shotFormula = struct("dx", "k1 + k3*x + k5*y + k7*x*y", "dy", "k2 + k4*y + k6*x + k8*x*y");
settings.overlay.perShot = "none";
end
