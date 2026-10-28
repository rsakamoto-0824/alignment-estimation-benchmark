classdef TestFactorsResidualsExport < matlab.unittest.TestCase
    %TESTFACTORSRESIDUALSEXPORT 質的変数を変えた条件の追加、残差と説明変数の相関、データの読み込みでの質的変数の
    %   交互作用、未知の座標の重ね合わせ補正値の Excel、Shot スタックマップの3つの値の並べ描きを確かめる。

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
        function extendWithChangedFactors(testCase)
            % 質的変数を変えて条件を足すと、質的変数を使う手法に組を付けて足す。推定はその組だけを選んだ評価と同じ
            data = testCase.Data;
            data.units = data.units(1:2);
            settings = alignest.defaultSettings();
            settings.sampling.nShots = 20;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.tps.enabled = true;
            settings.methods.tps.factorModes = "backfit";
            settings.methods.polynomial.enabled = true;
            first = alignest.runEvaluation(data, settings);
            changed = settings;
            changed.factors.mark = false;
            testCase.verifyEmpty(alignest.extensionConflicts(settings, changed), "質的変数は変えて足してよい");
            extended = alignest.runEvaluation(data, changed, [], first, "extend");
            testCase.verifyEqual(string({extended.methods.id}), ["TPS_XYR_backfit", "XY5", "TPS_XYR_backfit_fs-scan"], ...
                "質的変数を使わない XY 多項式は足さない");
            testCase.verifyTrue(endsWith(extended.methods(3).label, "質的変数：Scan 方向"));
            testCase.verifyEqual(alignest.factorSetKey(extended.settings), "scan+mark", "結果の設定は最初の組のまま");
            testCase.verifyTrue(contains(extended.additions(end), "質的変数を「Scan 方向」にして足した"));
            direct = alignest.runEvaluation(data, changed);
            added = extended.table(extended.table.methodId == "TPS_XYR_backfit_fs-scan", :);
            testCase.verifyEqual(added.RMSE_XY, direct.table.RMSE_XY(direct.table.methodId == "TPS_XYR_backfit"), ...
                'AbsTol', 1e-9);
            old = extended.table(extended.table.methodId == "TPS_XYR_backfit", :);
            testCase.verifyEqual(old.RMSE_XY, first.table.RMSE_XY(first.table.methodId == "TPS_XYR_backfit"), ...
                'AbsTol', 1e-12, "評価済みの行は前の組のまま");
            % 組の書き方：X・Y で違う組、なし、その他の列
            separate = settings;
            separate.factors.separateY = true;
            separate.factors.y.scan = true;
            separate.factors.y.mark = false;
            [key, label] = alignest.factorSetKey(separate);
            testCase.verifyEqual(key, "scan+mark~scan");
            testCase.verifyEqual(label, "X：Scan 方向・Mark 番号／Y：Scan 方向");
            method = struct("id", "GAM_XYR_fs-" + key, "family", "GAM");
            restored = alignest.singleFactorSettings(alignest.defaultSettings(), method);
            testCase.verifyEqual(alignest.factorSetKey(restored), key, "id の組から同じ質的変数に戻せる");
            method.id = "GAM_XYR_fs-none";
            testCase.verifyEqual(alignest.factorSetKey(alignest.singleFactorSettings(settings, method)), "none");
        end

        function correlationAndInteractionStatistics(testCase)
            % 相関の p 値を t 分布の密度の積分と比べる。二元配置の交互作用の平方和を、均等な 2 × 2 の式と比べる
            x = (1:10).';
            y = sin(x) + 0.3 * x;
            result = alignest.stats.correlationTest(x, y);
            r = corrcoef(x, y);
            testCase.verifyEqual(result.r, r(1, 2), 'AbsTol', 1e-12);
            df = 8;
            t = abs(result.r) * sqrt(df / (1 - result.r ^ 2));
            density = @(s) gamma((df + 1) / 2) / (sqrt(df * pi) * gamma(df / 2)) * (1 + s .^ 2 / df) .^ (-(df + 1) / 2);
            testCase.verifyEqual(result.p, 2 * integral(density, t, Inf), 'AbsTol', 1e-8);
            testCase.verifyTrue(isnan(alignest.stats.correlationTest([1; 2], [3; 4]).r), "3点未満は求めない");
            % 均等な 2 × 2（くり返し r 回）：SS_AB = r Σ (ȳij − ȳi. − ȳ.j + ȳ..)²
            replicates = 5;
            [a, b] = ndgrid(1:2, 1:2);
            a = repmat(a(:), replicates, 1);
            b = repmat(b(:), replicates, 1);
            noise = sin(37 * (1:numel(a)).');
            values = 2 * (a == 2) - (b == 2) + 1.5 * (a == 2 & b == 2) + 0.3 * noise;
            factors = struct("name", {"A", "B"}, "levels", {string(a), string(b)});
            [tests, cells] = alignest.stats.interactionTests(values, factors);
            means = accumarray([a, b], values) / replicates;
            effect = means - mean(means, 2) - mean(means, 1) + mean(means, 'all');
            ssInteraction = replicates * sum(effect .^ 2, 'all');
            residual = values - means(sub2ind([2, 2], a, b));
            ssResidual = sum(residual .^ 2);
            testCase.verifyEqual(tests.F, ssInteraction / (ssResidual / (numel(values) - 4)), 'RelTol', 1e-9);
            testCase.verifyEqual(tests.partialEta2, ssInteraction / (ssInteraction + ssResidual), 'RelTol', 1e-9);
            testCase.verifyLessThan(tests.p, 0.05);
            testCase.verifyEqual(height(cells), 4);
            % 同じ分け方の変数どうしは調べられない
            same = struct("name", {"A", "A2"}, "levels", {string(a), string(a)});
            confounded = alignest.stats.interactionTests(values, same);
            testCase.verifyTrue(isnan(confounded.p));
            testCase.verifyNotEqual(confounded.note, "");
        end

        function factorInteractionsFindInjectedInteraction(testCase)
            % 読み込んだ計測値に Scan 方向 × Mark 番号 の交互作用を足すと、「交互作用あり」と判定し、目安に書く
            data = testCase.Data;
            plain = alignest.factorInteractions(data);
            testCase.verifyEqual(height(plain.tests), 3 * 2, "3つの変数の組 × X・Y");
            testCase.verifyEqual(plain.axes, ["X", "Y"]);
            testCase.verifyFalse(any(plain.tests.verdict == "交互作用あり"));
            testCase.verifyTrue(any(contains(plain.advice, "交互作用はみられません")));
            for u = 1:numel(data.units)
                marks = data.units(u).marks;
                data.units(u).marks.measX = marks.measX + 4 * (marks.direction == 1 & marks.markNo == 1);
            end
            injected = alignest.factorInteractions(data, trendOrder=2);
            row = injected.tests(injected.tests.axis == "X" & injected.tests.factorA == "Scan 方向" & ...
                injected.tests.factorB == "Mark 番号", :);
            testCase.verifyEqual(row.verdict, "交互作用あり");
            testCase.verifyTrue(any(contains(injected.advice, "Scan 方向 × Mark 番号")));
            testCase.verifyEqual(injected.trendOrder, 2);
            yRow = injected.tests(injected.tests.axis == "Y" & injected.tests.factorA == "Scan 方向" & ...
                injected.tests.factorB == "Mark 番号", :);
            testCase.verifyNotEqual(yRow.verdict, "交互作用あり", "Y には足していない");
            testCase.verifyError(@() alignest.factorInteractions(data, trendOrder=6), 'alignest:trendOrder');
        end

        function appResidualsInteractionsStackAndExport(testCase)
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.xlsx'));
            app.applyMapping();
            c = app.Controls;
            % 読み込むと交互作用を一度調べる
            testCase.verifyNotEmpty(app.Interactions);
            testCase.verifyEqual(size(c.interactionTable.Data, 1), 6);
            testCase.verifyEqual(string(c.interactionAxes.Visible), "on");
            analysis = app.analyzeFactorInteractions(1, 0, strings(1, 0));
            testCase.verifyEqual(analysis.nUnits, 1);
            % 評価して、残差と説明変数の散布図
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.sampling.nShots = 20;
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(20, 20, 10);
            app.setSettings(settings);
            app.runEvaluationNow(false);
            summary = app.drawResidualVariables(1, app.Results.groups(1), 1, "markX");
            testCase.verifyEqual(height(summary.table), 8);
            estimates = alignest.collectEstimates(app.Data, app.Results, struct("methodIndex", 1, "groups", ...
                app.Results.groups(1), "unitIndex", 1));
            marks = app.Data.units(1).marks;
            expected = alignest.stats.correlationTest(marks.markXmm(estimates.markIndex), estimates.residualX);
            testCase.verifyEqual(summary.X.r, expected.r, 'AbsTol', 1e-12);
            testCase.verifyEqual(string(c.residualVariableAxes(1).XLabel.String), "Shot 内の X [mm]（markXmm）");
            % Shot スタックマップ：計測値・推定値・残差を Scan 方向ごとに並べる（2 段 × 3 列）
            c.mapView.Value = 'stack';
            c.mapStackBy.Value = 'scan';
            c.mapStackAll.Value = true;
            c.mapStackAll.ValueChangedFcn([], []);
            axesList = app.Controls.compareAxes;
            testCase.verifyEqual(numel(axesList), 6);
            titles = string(arrayfun(@(axis_) string(axis_.Title.String), axesList));
            testCase.verifyTrue(endsWith(titles(3), "残差（計測値 − 推定値）") || contains(titles(3), "残差"));
            % 未知の座標：補正値を計算していなくても、書き出すときに計算して補正量・補正後の残差の列も書く
            app.setTargetPoints(alignest.targetGrid(50, 140));
            run = app.estimateTargets(1, "all", 1);
            testCase.verifyTrue(all(cellfun(@isempty, run.overlay)));
            testCase.verifyEqual(c.targetOverlayExport.Enable, matlab.lang.OnOffSwitchState('on'));
            file = [tempname, '.xlsx'];
            removeFile = onCleanup(@() delete(file));
            app.exportTargetsTo(file);
            testCase.verifyFalse(isempty(app.TargetRun.overlay{1}), "書き出すときに計算した");
            sheet = readtable(file, 'Sheet', '推定値', 'VariableNamingRule', 'preserve');
            names = string(sheet.Properties.VariableNames);
            testCase.verifyTrue(all(ismember(["補正量X[nm]", "補正量Y[nm]", "補正後の残差X[nm]", "補正後の残差Y[nm]"], names)));
            points = app.TargetRun.overlay{1}.points;
            targets = points(points.source == "推定値（未知の座標）", :);
            testCase.verifyEqual(sheet{:, "補正後の残差X[nm]"}, targets.residualX, 'AbsTol', 1e-9);
            notes = readtable(file, 'Sheet', '説明', 'VariableNamingRule', 'preserve', 'TextType', 'string');
            testCase.verifyTrue(contains(notes{notes{:, 1} == "重ね合わせ補正", 2}, "書き出すときに計算した"));
        end
    end
end
