classdef TestCorrectionModelsAndInputs < matlab.unittest.TestCase
    %TESTCORRECTIONMODELSANDINPUTS 「5. 未知の座標の推定」の補正のモデル（項の選択）と補正の比較、Shot 高次補正の外れ値を
    %   除いた |平均|+3σ、学習パターンの使い回し（Shot が同じで Mark の欠けが違う Wafer）、「6. Shot高次補正」「8. 計測Mapローテ」
    %   の入力（評価の推定値・6. で読み込んだデータ）、ダークモードの空の表、業務でつながるタブの色を確かめる。

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
        function targetCorrectionChoiceAndTerms(testCase)
            % 補正のモデルの初期値は Wafer 1次＋Shot ごとの1次。項の一覧の 0次・1次は外せない、外した項は使わない
            settings = alignest.defaultSettings();
            choice = alignest.targetCorrectionChoice(settings);
            testCase.verifyEqual([choice.waferOrder, string(choice.shotCommon), string(choice.perShot)], ...
                ["1", "none", "linear"]);
            testCase.verifyTrue(choice.enabled);
            terms = alignest.targetCorrectionTerms(settings);
            testCase.verifyTrue(all(terms.required) && all(terms.used), "1次までの式は外せる項が無い");
            settings.targetCorrection.shotCommon = "quadratic";
            terms = alignest.targetCorrectionTerms(settings);
            quadratic = terms(terms.component == "shotCommon" & terms.order == 2, :);
            testCase.verifyEqual(height(quadratic), 6, "2次の項は X・Y で3つずつ");
            testCase.verifyFalse(any(quadratic.required));
            settings.targetCorrection.excludedTerms = quadratic.key(1);
            terms = alignest.targetCorrectionTerms(settings);
            testCase.verifyEqual(nnz(~terms.used), 1);
            testCase.verifyEqual(terms.key(~terms.used), quadratic.key(1));
            % 0次・1次の項は外したことにしても使う
            settings.targetCorrection.excludedTerms = terms.key(find(terms.required, 1));
            testCase.verifyTrue(all(alignest.targetCorrectionTerms(settings).used));
            % 読めない値は知らせる
            bad = settings;
            bad.targetCorrection.shotCommon = "formula";
            testCase.verifyError(@() alignest.targetCorrectionChoice(bad), 'alignest:targetCorrection');
            bad = settings;
            bad.targetCorrection.waferOrder = 6;
            testCase.verifyError(@() alignest.targetCorrectionChoice(bad), 'alignest:targetCorrection');
            % 設定が無い（以前の設定ファイル）ときは初期値
            old = rmfield(alignest.defaultSettings(), "targetCorrection");
            testCase.verifyEqual(alignest.targetCorrectionChoice(old).perShot, "linear");
        end

        function comparisonMatchesBaselineWithoutTargets(testCase)
            % このタブの補正が基準と同じ式で、未知の座標の点が無ければ、③ は ① と同じ。一部計測の行は ② ④ の2つが増える
            [data, settings] = sampleData(testCase);
            unit = data.units(1);
            [settings.overlay.waferOrder, settings.overlay.shotCommon, settings.overlay.perShot] = deal(1, "linear", "none");
            settings.targetCorrection = struct("waferOrder", 1, "shotCommon", "linear", "perShot", "none", ...
                "excludedTerms", strings(1, 0));
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            method = alignest.activeMethods(settings);
            method = method(1);
            allShots = 1:numel(unit.shots.shotNo);
            targets = alignest.predictTargets(unit, allShots, method, settings, alignest.targetGrid(40, 140)).table;
            none = targets([], :);
            comparison = alignest.targetCorrectionComparison(unit, [], method, settings, none, none);
            t = comparison.table;
            testCase.verifyEqual(height(t), 4, "全計測の2つ × X・Y");
            testCase.verifyEqual(t.residual(3:4), t.residual(1:2), 'AbsTol', 1e-9);
            testCase.verifyTrue(all(t.residual < t.before));
            % 高次の式と未知の座標の点：③ は計測値のある Mark の補正後の値で比べる（点の数は同じ）
            settings.targetCorrection.shotCommon = "quadratic";
            comparison = alignest.targetCorrectionComparison(unit, [], method, settings, targets, targets);
            t = comparison.table;
            testCase.verifyEqual(t.n(3:4), t.n(1:2));
            testCase.verifyEqual(t.targets(3), nnz(~targets.outsideWafer));
            testCase.verifyTrue(contains(comparison.model, "2次"));
            % 一部計測：学習しなかった Mark は推定値。4 つの補正
            spec = ioptimalSpec(settings);
            plan = alignest.planTrainingShots(unit, spec, settings.sampling, settings.data.waferRadiusMm);
            comparison = alignest.targetCorrectionComparison(unit, plan, method, settings, targets, targets);
            testCase.verifyEqual(extractBefore(unique(comparison.table.scenario, 'stable'), 2), ["①"; "②"; "③"; "④"]);
            testCase.verifyNumElements(comparison.maps, 4);
        end

        function trimmedMeanPlus3Sigma(testCase)
            % 外れ値（中央値 ± n × 1.4826 × MAD の外）を除いた |平均|+3σ。外れ値の無い軸は同じ値
            nPoints = 40;
            noise = 0.5 * sin(1:nPoints).';
            points = table(repmat("W1", nPoints, 1), repmat(["内周"; "外周"], nPoints / 2, 1), noise, noise, ...
                ones(nPoints, 1), ones(nPoints, 1), 'VariableNames', ["wafer", "zone", "residualX", "residualY", ...
                "linearResidualX", "linearResidualY"]);
            points.residualX(5) = 100;   % 外れ値（内周）
            trimmed = alignest.highOrderTrimmedSummary(points);
            row = trimmed(trimmed.wafer == "W1" & trimmed.axis == "X" & trimmed.region == "すべて", :);
            kept = points.residualX([1:4, 6:end]);
            testCase.verifyEqual(row.highOrderTrimmed, abs(mean(kept)) + 3 * std(kept), 'AbsTol', 1e-12);
            testCase.verifyEqual(row.trimmedOutliers, 1);
            inner = trimmed(trimmed.wafer == "W1" & trimmed.axis == "X" & trimmed.region == "内周", :);
            testCase.verifyEqual(inner.trimmedOutliers, 1);
            outer = trimmed(trimmed.wafer == "W1" & trimmed.axis == "X" & trimmed.region == "外周", :);
            testCase.verifyEqual(outer.trimmedOutliers, 0);
            rowY = trimmed(trimmed.wafer == "W1" & trimmed.axis == "Y" & trimmed.region == "すべて", :);
            testCase.verifyEqual(rowY.highOrderTrimmed, abs(mean(noise)) + 3 * std(noise), 'AbsTol', 1e-12);
            testCase.verifyEqual(rowY.trimmedOutliers, 0);
            testCase.verifyTrue(any(trimmed.wafer == "すべての Wafer"));
            % 幅 n を大きくすると外れ値にしない
            wide = alignest.highOrderTrimmedSummary(points, 1000);
            testCase.verifyEqual(sum(wide.trimmedOutliers), 0);
            % 1次の残差が無い点は比べない
            points.linearResidualX(5) = NaN;
            noLinear = alignest.highOrderTrimmedSummary(points);
            testCase.verifyEqual(noLinear.trimmedOutliers(noLinear.wafer == "W1" & noLinear.axis == "X" & ...
                noLinear.region == "すべて"), 0);
        end

        function shotPlanIsReusedWhenMarksDiffer(testCase)
            % 候補の Shot が同じ Wafer：Mark の欠けが違っても学習パターン（選ぶ Shot）を使い回し、学習に使う Mark の数と
            % I 基準・D 基準だけをその Wafer の Mark で求め直す（作り直したときと同じ値）
            [data, settings] = sampleData(testCase);
            first = data.units(1);
            second = first;
            shotOfMark = second.marks.shotIndex;
            counts = accumarray(shotOfMark(:), 1);
            mark = find(counts(shotOfMark) > 1, 1);   % ほかの Mark が残る Shot の Mark
            [second.marks.validX(mark), second.marks.validY(mark)] = deal(false);
            second.shots = refreshValidCounts(second);
            testCase.verifyEqual(alignest.planLayoutKey(first, "shot"), alignest.planLayoutKey(second, "shot"));
            testCase.verifyNotEqual(alignest.planLayoutKey(first), alignest.planLayoutKey(second));
            spec = ioptimalSpec(settings);
            cache = containers.Map();
            plan1 = alignest.cachedTrainingPlan(first, spec, settings, cache);
            plan2 = alignest.cachedTrainingPlan(second, spec, settings, cache);
            testCase.verifyFalse(plan1.reused);
            testCase.verifyTrue(plan2.reused, "作り直さない");
            testCase.verifyEqual(plan2.shotIndex, plan1.shotIndex);
            fresh = alignest.planTrainingShots(second, spec, settings.sampling, settings.data.waferRadiusMm, plan1.shotIndex);
            testCase.verifyEqual(plan2.nMarks, fresh.nMarks);
            testCase.verifyEqual([plan2.criterionI, plan2.criterionD], [fresh.criterionI, fresh.criterionD], ...
                'RelTol', 1e-12);
            if any(plan1.shotIndex == second.marks.shotIndex(mark))
                testCase.verifyEqual(plan2.nMarks, plan1.nMarks - 1, "欠けた Mark の分だけ少ない");
            end
            % 評価にかかる時間の目安も、Shot 単位の計画は1回と数える
            testCase.verifyEqual(numel(unique(string({alignest.planLayoutKey(first, "shot"), ...
                alignest.planLayoutKey(second, "shot")}))), 1);
        end

        function highOrderAndRotationInputs(testCase)
            % 「6. Shot高次補正」は評価の推定値（学習した Mark は計測値、ほかは推定値）を、「8. 計測Mapローテ」は 6. で読み込んだ
            % Excel・CSV を入力にできる
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.sampling.method = "random";
            [settings.sampling.nShots, settings.sampling.nShotsStart, settings.sampling.nShotsEnd] = deal(20, 20, 20);
            app.setSettings(settings);
            results = app.runEvaluationNow(false);
            app.setHighOrderSource("estimate");
            c = app.Controls;
            testCase.verifyEqual(string(c.highOrderEstimatePlan.Enable), "on");
            testCase.verifyTrue(any(string(c.highOrderEstimatePlan.ItemsData) == results.plans(1).label));
            result = app.computeHighOrder(1);
            testCase.verifyNotEmpty(result.summary);
            testCase.verifyEqual(app.HighOrderRun.source, "estimate");
            % 計測値の入力とは値が違う（学習しなかった Mark は推定値）
            app.setHighOrderSource("data");
            measured = app.computeHighOrder(1);
            testCase.verifyNotEqual(result.points.residualX, measured.points.residualX);
            % 6. で読み込んだ Excel・CSV を 8. の入力にする
            file = [tempname, '.csv'];
            copyfile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'), file);
            cleanupFile = onCleanup(@() delete(file));
            data = app.loadHighOrderFile(file);
            testCase.verifyNotEmpty(data, "見出しから列を推定して読み込む");
            app.setRotationInput("highOrderFile");
            c = app.Controls;
            testCase.verifyEqual(string(c.rotationComputeVariability.Enable), "on");
            testCase.verifyTrue(contains(string(c.rotationInputInfo.Text), "6. Shot高次補正"));
            variability = app.computeRotationVariability("mark", "max");
            testCase.verifyEqual(variability.nWafers, numel(data.units));
            testCase.verifyTrue(contains(variability.description, "6. Shot高次補正"));
            % 「ばらつきを求める」と「計測マップを作る」は色が違う
            testCase.verifyNotEqual(c.rotationComputeVariability.BackgroundColor, c.rotationMakeMaps.BackgroundColor);
        end

        function darkModeHidesEmptyTablesAndTabsHaveColors(testCase)
            % ダークモードでは中身が空の表をしまう（空の部分が白く目立つため）。中身が入れば出し、ライトモードで戻す。
            % 業務でつながるタブ（2〜5・6〜7）は見出しの色で分ける
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            table_ = c.varianceTable;
            testCase.verifyEmpty(table_.Data);
            app.setTheme("dark");
            testCase.verifyEqual(string(table_.Visible), "off", "空の表はしまう");
            table_.Data = table(1, 'VariableNames', "値");
            testCase.verifyEqual(string(table_.Visible), "on", "中身が入ったら出す");
            table_.Data = table();
            testCase.verifyEqual(string(table_.Visible), "off");
            app.setTheme("light");
            testCase.verifyEqual(string(table_.Visible), "on", "ライトモードではすべて出す");
            tabs = app.Tabs;
            estimation = tabs.settings.ForegroundColor;
            correction = tabs.highOrder.ForegroundColor;
            for name = ["results", "map", "target"]
                testCase.verifyEqual(tabs.(name).ForegroundColor, estimation, 'AbsTol', 1e-9, "2〜5 は同じ色：" + name);
            end
            testCase.verifyEqual(tabs.markLayout.ForegroundColor, correction, 'AbsTol', 1e-9, "6・7 は同じ色");
            testCase.verifyGreaterThan(norm(estimation - correction), 0.1, "2〜5 と 6・7 は違う色");
            testCase.verifyGreaterThan(norm(tabs.data.ForegroundColor - estimation), 0.1, "ほかのタブは色を付けない");
            testCase.verifyEqual(tabs.data.ForegroundColor, tabs.rotation.ForegroundColor, 'AbsTol', 1e-9);
        end
    end
end

function [data, settings] = sampleData(testCase)
% サンプルの計測データ（Wafer ごと）と初期設定
raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
settings = alignest.defaultSettings();
end

function spec = ioptimalSpec(settings)
% Shot 単位の I 最適・20 Shot の学習パターンの仕様
sampling = settings.sampling;
sampling.method = "ioptimal";
sampling.countBy = "shots";
[sampling.nShotsStart, sampling.nShotsEnd, sampling.nShotsStep] = deal(20, 20, 5);
spec = alignest.buildPlanSpecs(sampling);
spec = spec(1);
end

function shots = refreshValidCounts(unit)
% Mark の有効・無効を変えたあとの、Shot ごとの有効な点の数
shots = unit.shots;
nShots = numel(shots.shotNo);
shots.nValidX = accumarray(unit.marks.shotIndex(:), double(unit.marks.validX(:)), [nShots, 1]);
shots.nValidY = accumarray(unit.marks.shotIndex(:), double(unit.marks.validY(:)), [nShots, 1]);
end
