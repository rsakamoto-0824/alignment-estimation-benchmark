classdef TestComparisonPlansDisplay < matlab.unittest.TestCase
    %TESTCOMPARISONPLANSDISPLAY 結果一覧の比べ方（計測配置の比較の横軸・エラーバー、手法を並べた分布・箱ひげ図、
    %   Shapiro–Wilk を計算しない理由）、残り時間の計算、Mark 単位の計画（D 最適・計測率・Shot ごとの n 点）、
    %   質的変数を1つずつ使う手法、Fringe Zernike の Backfitting、Scan 方向の表示、Shot スタックマップ、アプリの名前。

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
        function progressCountIsDouble(testCase)
            % 続きから・条件を足して計算するとき、済んだ数は double（uint64 のままだと残り時間の割り算が丸められた）
            data = testCase.Data;
            data.units = data.units(1);
            settings = alignest.defaultSettings();
            settings.sampling.nShots = 10;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            first = alignest.runEvaluation(data, settings);
            settings.sampling.nShots = [10, 20];
            classes = strings(0, 1);
            function ok = record(done, ~, ~)
                classes(end + 1, 1) = string(class(done));
                ok = true;
            end
            alignest.runEvaluation(data, settings, @record, first, "extend");
            testCase.verifyNotEmpty(classes);
            testCase.verifyTrue(all(classes == "double"));
        end

        function layoutComparisonEfficiencyAndErrorBars(testCase)
            results = smallResults(testCase, ["ioptimal", "random"]);
            comparison = alignest.layoutComparison(results, 1, "RMSE_XY", "mean");
            testCase.verifyTrue(all(ismember(["efficiencyI", "efficiencyD", "sd", "se", "minValue", "maxValue", ...
                "nWafers"], string(comparison.Properties.VariableNames))));
            testCase.verifyTrue(all(comparison.efficiencyD > 0 & comparison.efficiencyD < 1));
            perUnit = alignest.perUnitValues(results, "RMSE_XY");
            [~, g] = ismember(comparison.group(1), results.groups);
            values = perUnit{1, g};
            testCase.verifyEqual(comparison.sd(1), std(values), 'AbsTol', 1e-12);
            testCase.verifyEqual(comparison.se(1), std(values) / sqrt(numel(values)), 'AbsTol', 1e-12);
            [lower, upper] = alignest.layoutErrorBars(comparison, "ci95");
            testCase.verifyEqual(lower, 1.96 * comparison.se, 'AbsTol', 1e-12);
            testCase.verifyEqual(upper, lower);
            [lower, upper] = alignest.layoutErrorBars(comparison, "range");
            testCase.verifyEqual(comparison.value - lower, comparison.minValue, 'AbsTol', 1e-12);
            testCase.verifyEqual(comparison.value + upper, comparison.maxValue, 'AbsTol', 1e-12);
            testCase.verifyError(@() alignest.layoutErrorBars(comparison, "iqr"), 'alignest:errorBar');
        end

        function shapiroWilkReason(testCase)
            many = alignest.stats.normalityTests(sin((1:6000).'));
            testCase.verifyTrue(isnan(many.swW));
            testCase.verifyEqual(many.swNote, "6000 点（5000 点超）");
            testCase.verifyTrue(isfinite(many.adP));
            few = alignest.stats.normalityTests([1; 2]);
            testCase.verifyEqual(few.swNote, "2 点（3 点未満）");
            testCase.verifyEqual(few.adNote, "2 点（8 点未満）");
            same = alignest.stats.normalityTests(ones(10, 1));
            testCase.verifyEqual(same.swNote, "値がすべて同じ");
            fine = alignest.stats.normalityTests(sin((1:50).'));
            testCase.verifyEqual([fine.swNote, fine.adNote], ["", ""]);
        end

        function appComparesMethodsAndLayouts(testCase)
            % 画面：計測配置の比較（D・I 効率の横軸、エラーバー）、手法を複数選んだ分布・検定の表・箱ひげ図
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.methods.tps.enabled = true;
            settings.sampling.method = ["ioptimal", "doptimal"];
            settings.sampling.nShots = [10, 20];
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(10, 20, 10);
            app.setSettings(settings);
            app.runEvaluationNow(false);
            c = app.Controls;
            app.drawLayoutComparison(1, "efficiencyD", "sd");
            testCase.verifyTrue(startsWith(string(c.compareLayoutAxes.XLabel.String), "D 効率"));
            testCase.verifyEqual(numel(findobj(c.compareLayoutAxes, 'Type', 'errorbar')), 2);
            testCase.verifyEqual(size(c.compareLayoutTable.Data, 2), 10);
            app.drawLayoutComparison(1, "efficiencyI", "none");
            testCase.verifyEmpty(findobj(c.compareLayoutAxes, 'Type', 'errorbar'));
            testCase.verifyTrue(startsWith(string(c.compareLayoutAxes.XLabel.String), "I 効率"));
            analysis = app.analyzeResiduals([1, 2], app.Results.groups(end), 0);
            testCase.verifyEqual(height(analysis.normality), 4, "手法 2 × X・Y");
            testCase.verifyEqual(size(c.normalityTable.Data, 2), 14);
            testCase.verifyEqual(numel(unique(string(c.normalityTable.Data(:, 1)))), 2);
            testCase.verifyEqual(numel(findobj(c.histogramAxes(1), 'Type', 'histogram')), 2, "手法ごとの輪郭");
            testCase.verifyEqual(numel(findobj(c.boxAxes(1), 'Type', 'BoxChart')), 2, "手法ごとに色分け");
            summary = app.drawResidualBoxplot("Mark 番号");
            testCase.verifyTrue(any(string(summary(1).levels.Properties.VariableNames) == "method"));
            testCase.verifyTrue(contains(c.boxInfo.Text, app.Results.methods(2).label));
            oneMethod = app.analyzeResiduals(1, app.Results.groups(end), 0);
            testCase.verifyEqual(height(oneMethod.normality), 2);
            testCase.verifyEqual(numel(findobj(c.boxAxes(1), 'Type', 'BoxChart')), 1);
            c.analysisMethod.Value = {};
            testCase.verifyError(@() app.analyzeResiduals(), 'alignest:analysisMethod');
        end

        function markPlansDOptimalRateAndPerShot(testCase)
            unit = testCase.Data.units(1);
            sampling = alignest.defaultSettings().sampling;
            sampling.method = ["mark", "markd"];
            sampling.countBy = "rate";
            [sampling.rateStart, sampling.rateEnd, sampling.rateStep] = deal(30, 40, 10);
            specs = alignest.buildPlanSpecs(sampling);
            testCase.verifyEqual(string({specs.label}), ["Mark最適 計測率 30%", "Mark最適 計測率 40%", ...
                "MarkD最適 計測率 30%", "MarkD最適 計測率 40%"]);
            candidates = nnz(unit.marks.validX | unit.marks.validY);
            planI = alignest.planTrainingShots(unit, specs(1), sampling, 150);
            planD = alignest.planTrainingShots(unit, specs(3), sampling, 150);
            testCase.verifyEqual(planI.nMarks, round(0.3 * candidates));
            testCase.verifyEqual(planD.nMarks, planI.nMarks);
            testCase.verifyNotEqual(sort(planD.markIndex), sort(planI.markIndex), "D 最適は I 最適と違う組");
            counts = accumarray(unit.marks.shotIndex(planD.markIndex), 1, [numel(unit.shots.shotNo), 1]);
            testCase.verifyGreaterThanOrEqual(min(counts), 1, "既定では各 Shot 1 点以上");
            % Shot ごとの n 点を必須にしない：計測しない Shot がある
            free = sampling;
            free.markRequirePerShot = false;
            free.rateStart = 10;
            freeSpecs = alignest.buildPlanSpecs(free);
            plan = alignest.planTrainingShots(unit, freeSpecs(1), free, 150);
            testCase.verifyEqual(plan.nMarks, round(0.1 * candidates));
            testCase.verifyLessThan(plan.nShots, numel(unit.shots.shotNo));
            % 各 Shot 2 点：足りない Mark の数は増やしてメモに書く
            two = alignest.defaultSettings().sampling;
            two.method = "mark";
            two.markMinPerShot = 2;
            plan = alignest.planTrainingShots(unit, alignest.buildPlanSpecs(two), two, 150);
            counts = accumarray(unit.marks.shotIndex(plan.markIndex), 1, [numel(unit.shots.shotNo), 1]);
            usable = unit.marks.validX | unit.marks.validY;
            available = accumarray(unit.marks.shotIndex(usable), 1, [numel(unit.shots.shotNo), 1]);
            measured = available > 0;
            testCase.verifyTrue(all(counts(measured) >= min(2, available(measured))), "各 Shot 2 点（少ない Shot は全 Mark）");
            testCase.verifyTrue(contains(plan.message, "各 Shot 2 点"));
            % 計測率を使わないときは 1 Shot あたりの数（1 未満も、Shot ごとの必須をやめれば使える）
            half = free;
            half.countBy = "shots";
            half.markPerShot = 0.5;
            spec = alignest.buildPlanSpecs(half);
            testCase.verifyEqual(spec(1).label, "Mark最適 0.5 点/Shot");
            testCase.verifyError(@() alignest.buildPlanSpecs(setfield(half, "markPerShot", 0)), 'alignest:markPerShot'); %#ok<SFLD>
        end

        function singleFactorMethodsUseOneFactor(testCase)
            settings = alignest.defaultSettings();
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.tps.enabled = true;
            settings.methods.tps.factorModes = "backfit";
            settings.methods.polynomial.enabled = true;
            settings.factors.scan = true;
            settings.factors.mark = true;
            testCase.verifyEqual(string({alignest.activeMethods(settings).id}), ["TPS_XYR_backfit", "XY5"]);
            settings.factors.evaluateSingles = true;
            methods = alignest.activeMethods(settings);
            testCase.verifyEqual(string({methods.id}), ["TPS_XYR_backfit", "TPS_XYR_backfit_1f-scan", ...
                "TPS_XYR_backfit_1f-mark", "XY5"], "質的変数を使わない手法には足さない");
            testCase.verifyTrue(endsWith(methods(3).label, "質的変数：Mark 番号だけ"));
            % 1つだけの手法は、その変数だけを選んだ設定の推定と同じ
            unit = testCase.Data.units(1);
            train = 1:2:numel(unit.shots.shotNo);
            onlyMark = settings;
            onlyMark.factors.scan = false;
            onlyMark.factors.evaluateSingles = false;
            expected = alignest.estimateWafer(unit, train, methods(1), onlyMark);
            actual = alignest.estimateWafer(unit, train, methods(3), settings);
            testCase.verifyEqual(actual.estimate.X, expected.estimate.X, 'AbsTol', 1e-9);
            [restricted, key] = alignest.singleFactorSettings(settings, methods(2));
            testCase.verifyEqual(key, "scan");
            testCase.verifyEqual([restricted.factors.scan, restricted.factors.mark], [true, false]);
            % 条件の追加では、1つずつの手法を足すのは「手法を足す」だけ
            before = settings;
            before.factors.evaluateSingles = false;
            testCase.verifyEmpty(alignest.extensionConflicts(before, settings));
            % 変数が1つだけなら足さない
            settings.factors.mark = false;
            testCase.verifyEqual(numel(alignest.activeMethods(settings)), 2);
        end

        function zernikeBackfitting(testCase)
            config = alignest.recommendedMethods("none");
            config.zernike.enabled = true;
            config.zernike.orders = 3;
            config.zernike.factorModes = ["none", "backfit"];
            methods = alignest.buildMethodList(config);
            testCase.verifyEqual(string({methods.id}), ["FringeZ_k3", "FringeZ_k3_backfit"]);
            testCase.verifyTrue(alignest.usesFactors(methods(2)));
            testCase.verifyFalse(alignest.usesFactors(methods(1)));
            unit = testCase.Data.units(1);
            train = 1:2:numel(unit.shots.shotNo);
            settings = alignest.defaultSettings();
            plain = alignest.estimateWafer(unit, train, methods(1), settings);
            backfit = alignest.estimateWafer(unit, train, methods(2), settings);
            testCase.verifyGreaterThan(max(abs(backfit.estimate.X - plain.estimate.X)), 1e-6, "質的変数の効果を足す");
            testCase.verifyGreaterThan(backfit.edf(1), plain.edf(1));
            testCase.verifyTrue(isfield(backfit.extra, "backfitIterations_X"));
            noFactors = settings;
            [noFactors.factors.scan, noFactors.factors.mark] = deal(false);
            same = alignest.estimateWafer(unit, train, methods(2), noFactors);
            testCase.verifyEqual(same.estimate.X, plain.estimate.X, 'AbsTol', 1e-9, "質的変数が無ければ Zernike だけと同じ");
            testCase.verifyEqual(alignest.completeMethodSettings(rmfield(config, "zernike")).zernike.factorModes, "none");
        end

        function scanStyleAndSettings(testCase)
            style = alignest.plot.scanStyle();
            testCase.verifyEqual(style.markers, ['^', 'v']);
            testCase.verifyEqual(style.names, ["Scan 1（▲ 上）", "Scan 2（▼ 下）"]);
            display = struct("scan1Up", false, "scan1Color", [1, 0, 0], "scan2Color", [0, 0, 1]);
            style = alignest.plot.scanStyle(display);
            testCase.verifyEqual(style.markers, ['v', '^']);
            testCase.verifyEqual(style.names, ["Scan 1（▼ 下）", "Scan 2（▲ 上）"]);
            testCase.verifyEqual(style.colors, [1, 0, 0; 0, 0, 1]);
            testCase.verifyError(@() alignest.plot.scanStyle(struct("scan1Color", [2, 0, 0])), 'alignest:scanColor');
            % 設定ファイルに保存して読み戻せる。色を変えても一時中断の再開は止めない（推定の結果は変わらない）
            settings = alignest.defaultSettings();
            settings.display = display;
            file = [tempname, '.json'];
            cleanup = onCleanup(@() delete(file));
            alignest.saveSettings(settings, file);
            loaded = alignest.loadSettings(file);
            testCase.verifyEqual(loaded.display.scan1Color, [1, 0, 0]);
            testCase.verifyFalse(loaded.display.scan1Up);
            testCase.verifyTrue(alignest.sameRunSettings(alignest.defaultSettings(), settings));
            testCase.verifyEmpty(alignest.extensionConflicts(alignest.defaultSettings(), settings));
            % 画面：メニューの「表示」→「Scan 方向の向きと色」と、Wafer マップの凡例
            app = AlignmentEstimationApp(false);
            appCleanup = onCleanup(@() delete(app));
            app.setSettings(settings);
            testCase.verifyEqual(string([app.Controls.scanUpItems.Checked]), ["off", "on"], "1 = 下向きに ✓");
            testCase.verifyTrue(contains(app.Controls.scanColorItems(1).Text, "#FF0000"));
            testCase.verifyFalse(isfield(app.Controls, 'scan1Up'), "「2. 評価の設定」には欄を出さない");
            app.setScanStyle(scan2Color=[0, 1, 128 / 255]);
            testCase.verifyEqual(app.Settings.display.scan2Color, [0, 1, 128 / 255], 'AbsTol', 1e-12);
            testCase.verifyTrue(contains(app.Controls.scanColorItems(2).Text, "#00FF80"));
            testCase.verifyError(@() app.setScanStyle(scan2Color=[2, 0, 0]), 'alignest:scanColor');
            testCase.verifyEqual(app.Settings.display.scan2Color, [0, 1, 128 / 255], 'AbsTol', 1e-12, "読めない値は前の色");
            app.Controls.scanUpItems(1).MenuSelectedFcn([], []);
            testCase.verifyTrue(app.Settings.display.scan1Up);
            testCase.verifyEqual(string([app.Controls.scanUpItems.Checked]), ["on", "off"]);
            app.resetScanStyle();
            testCase.verifyEqual(app.Settings.display, alignest.defaultSettings().display);
            app.setScanStyle(scan1Up=false, scan1Color=[1, 0, 0], scan2Color=[0, 0, 1]);
            figureHandle = figure('Visible', 'off');
            closeFigure = onCleanup(@() close(figureHandle));
            ax = axes(figureHandle);
            unit = testCase.Data.units(1);
            handles = alignest.plot.scanFrames(ax, [unit.shots.Xmm, unit.shots.Ymm], unit.shotSizeMm, ...
                unit.shots.direction, 0, style);
            testCase.verifyEqual(string({handles.DisplayName}), style.names);
            testCase.verifyEqual(handles(1).Marker, 'v');
        end

        function shotStackMap(testCase)
            figureHandle = figure('Visible', 'off');
            closeFigure = onCleanup(@() close(figureHandle));
            ax = axes(figureHandle);
            local = [-5, 5; -5, 5; 5, -5];
            values = [1, 2; 3, 4; -1, 0];
            summary = alignest.plot.shotStackMap(ax, local, values, shotSizeMm=[20, 30]);
            testCase.verifyEqual(summary.n, [2; 1]);
            testCase.verifyEqual(summary{summary.localX == -5, ["meanX", "meanY"]}, [2, 3]);
            testCase.verifyEqual(numel(findobj(ax, 'Type', 'quiver')), 2);
            alignest.plot.shotStackMap(ax, local, values, mode="Y", shotSizeMm=[20, 30]);
            testCase.verifyEqual(numel(findobj(ax, 'Type', 'scatter')), 2);
            % 画面：Scan 方向 × 行の偶奇ごとの Shot スタックマップ
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            testCase.verifyEqual(app.Figure.Name, '面内推定評価ツール');
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.sampling.nShots = 20;
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(20, 20, 10);
            app.setSettings(settings);
            app.runEvaluationNow(false);
            c = app.Controls;
            c.mapView.Value = 'stack';
            c.mapStackBy.Value = 'scanRow';
            c.mapView.ValueChangedFcn([], []);
            testCase.verifyEqual(numel(app.Controls.compareAxes), 4);
            testCase.verifyTrue(startsWith(c.mapInfo.Text, "Shot スタックマップ"));
            c.mapStackBy.Value = 'scan';
            c.mapStackBy.ValueChangedFcn([], []);
            testCase.verifyEqual(numel(app.Controls.compareAxes), 2);
            titles = string(arrayfun(@(axis_) string(axis_.Title.String), app.Controls.compareAxes));
            testCase.verifyTrue(all(startsWith(titles, "Scan ")));
        end
    end
end

function results = smallResults(testCase, methods)
% 2 枚の Wafer・XY 5次・学習 Shot 数 10・20 の評価（選び方を比べる）
data = testCase.Data;
data.units = data.units(1:3);
settings = alignest.defaultSettings();
settings.sampling.method = methods;
settings.sampling.randomRepeats = 1;
settings.sampling.nShots = [10, 20];
settings.methods = alignest.recommendedMethods("none");
settings.methods.polynomial.enabled = true;
results = alignest.runEvaluation(data, settings);
end
