classdef TestPlanSelectionAndScreens < matlab.unittest.TestCase
    %TESTPLANSELECTIONANDSCREENS 手法と学習パターンの追加・変更（GAM の質的変数あり・なし、Mark 単位の計測する Mark の数の
    %   スイープ、Wafer 中心に最も近い Mark、計測しない Shot・Mark と必ず計測する Mark、全計測との統計量の差、計測率の横軸）と、
    %   画面（計測マップでの指定・記録の窓、結果一覧の効率の横軸・凡例、Wafer ごとのマップの Shot 番号・MAE、Shot 高次補正の
    %   ②の並び・Shot 共通の項の列・マップの重ねる物・Scan 方向ごとの図・2つの条件を並べる・補正の比較の条件のタブ、
    %   Mark 配置の候補の表の幅）、初期設定（X・Y の質的変数を別に選ぶ・Huber の c = 3・グリッドの線の数）。

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
        function defaultsChanged(testCase)
            % 初期設定：X・Y の質的変数を別に選ぶ（はじめは同じ選択）、Huber の c = 3、GAM は質的変数あり、Mark の数は1 Shot あたり
            defaults = alignest.defaultSettings();
            testCase.verifyTrue(defaults.factors.separateY);
            testCase.verifyEqual(alignest.factorChoice(defaults, "Y"), alignest.factorChoice(defaults, "X"));
            testCase.verifyEqual([defaults.highOrder.huberTuning, defaults.markLayout.huberTuning], [3, 3]);
            testCase.verifyEqual(alignest.recommendedMethods().gam.factorModes, "factor");
            testCase.verifyEqual(defaults.sampling.markCountBy, "perShot");
            testCase.verifyEmpty(defaults.sampling.excludedShots);
        end

        function gamCanRunWithoutFactors(testCase)
            % GAM の質的変数：あり（以前と同じ id）・なし（_nofactor）・両方。なしは質的変数を使わない（usesFactors）
            methods = alignest.recommendedMethods("none");
            methods.gam.enabled = true;
            methods.gam.factorModes = ["none", "factor"];
            list = alignest.buildMethodList(methods);
            testCase.verifyEqual(string({list.id}), ["GAM_XYR", "GAM_XYR_nofactor"]);
            testCase.verifyEqual(string({list.label}), ["GAM｜X,Y,半径（質的変数あり）", "GAM｜X,Y,半径（質的変数なし）"]);
            testCase.verifyEqual([alignest.usesFactors(list(1)), alignest.usesFactors(list(2))], [true, false]);
            unit = testCase.Data.units(1);
            settings = alignest.defaultSettings();
            train = 1:2:numel(unit.shots.shotNo);
            with = alignest.estimateWafer(unit, train, list(1), settings);
            without = alignest.estimateWafer(unit, train, list(2), settings);
            testCase.verifyTrue(all(isfinite(without.estimate.X)));
            testCase.verifyGreaterThan(max(abs(with.estimate.X - without.estimate.X)), 1e-6, "質的変数の項の分だけ違う");
            methods.gam.factorModes = "bad";
            testCase.verifyError(@() alignest.buildMethodList(methods), 'alignest:gamFactorMode');
        end

        function markCountSweepAndCenterMark(testCase)
            % 計測する Mark の数のスイープ：開始・終了・刻みごとの学習パターン（"Mark最適 120 点"）。Wafer 中心に最も近い
            % Mark は必ず計測する
            unit = testCase.Data.units(1);
            sampling = alignest.defaultSettings().sampling;
            sampling.method = ["mark", "markd"];
            sampling.markCountBy = "total";
            [sampling.markCountStart, sampling.markCountEnd, sampling.markCountStep] = deal(110, 150, 20);
            sampling.exchangeStarts = 2;
            specs = alignest.buildPlanSpecs(sampling);
            testCase.verifyEqual(string({specs.label}), ["Mark最適 110 点", "Mark最適 130 点", "Mark最適 150 点", ...
                "MarkD最適 110 点", "MarkD最適 130 点", "MarkD最適 150 点"]);
            [~, center] = min(hypot(unit.marks.x, unit.marks.y));
            for k = [1, 6]
                plan = alignest.planTrainingShots(unit, specs(k), sampling, 150);
                testCase.verifyEqual(plan.nMarks, specs(k).markCount);
                testCase.verifyTrue(ismember(center, plan.markIndex), "Wafer 中心に最も近い Mark");
            end
            sampling.markCountEnd = 100;
            testCase.verifyError(@() alignest.buildPlanSpecs(sampling), 'alignest:markCount');
            sampling.countBy = "rate";   % 計測率で決めるときは計測率を使う
            [sampling.rateStart, sampling.rateEnd, sampling.rateStep] = deal(30, 30, 10);
            testCase.verifyEqual(string({alignest.buildPlanSpecs(sampling).label}), ["Mark最適 計測率 30%", "MarkD最適 計測率 30%"]);
            conflicts = alignest.extensionConflicts(alignest.defaultSettings(), setfield(alignest.defaultSettings(), ...
                "sampling", setfield(alignest.defaultSettings().sampling, "markCountBy", "total"))); %#ok<SFLD>
            testCase.verifyEmpty(conflicts, "Mark の数の決め方は条件の追加で変えてよい");
        end

        function excludedAndRequiredSelections(testCase)
            % 計測しない Shot・Mark は学習に選ばず（評価には使う）、必ず計測する Mark は選ぶ。指定の文字の確かめ
            unit = testCase.Data.units(1);
            sampling = alignest.defaultSettings().sampling;
            sampling.exchangeStarts = 2;
            sampling.method = "ioptimal";
            sampling.nShots = 20;
            sampling.excludedShots = [10, 11, 12];
            sampling.requiredShots = [10, 40];   % 10 は計測しないが優先（必ず計測から外す）
            spec = alignest.buildPlanSpecs(sampling);
            plan = alignest.planTrainingShots(unit, spec, sampling, 150);
            testCase.verifyFalse(any(ismember(plan.shotNos, [10, 11, 12])));
            testCase.verifyTrue(ismember(40, plan.shotNos));
            testCase.verifyEqual(plan.nShots, 20);
            sampling.method = "mark";
            sampling.excludedMarks = ["60-1", "61-2"];
            sampling.requiredMarks = "50-2";
            spec = alignest.buildPlanSpecs(sampling);
            plan = alignest.planTrainingShots(unit, spec, sampling, 150);
            keys = compose("%d-%d", unit.marks.shotNo(plan.markIndex), unit.marks.markNo(plan.markIndex));
            testCase.verifyTrue(ismember("50-2", keys));
            testCase.verifyFalse(any(ismember(keys, ["60-1", "61-2"])));
            testCase.verifyFalse(any(ismember(unit.marks.shotNo(plan.markIndex), [10, 11, 12])));
            selection = alignest.measurementSelections(unit, sampling);
            testCase.verifyEqual(numel(selection.excludedShots), 3);
            testCase.verifyEqual(alignest.parseMarkKeys(["12-3", " 12-3", "4-1"]), [12, 3; 4, 1]);
            testCase.verifyError(@() alignest.parseMarkKeys("12_3"), 'alignest:markKeys');
            sampling.excludedMarks = "999-9";
            testCase.verifyEqual(alignest.measurementSelections(unit, sampling).missing, "999-9");
        end

        function statisticsDifferenceAndRate(testCase)
            % 全計測との統計量の差：全 Mark なら差は 0、平均・中央値・分散・最大・最小。計測配置の比較の計測率
            unit = testCase.Data.units(1);
            everything = struct("markIndex", (1:numel(unit.marks.x)).', "shotIndex", zeros(0, 1), "ok", true);
            same = alignest.planStatisticsDifference(unit, everything);
            testCase.verifyEqual(same.table.statistic.', ["平均", "中央値", "分散", "最大", "最小"]);
            testCase.verifyEqual([same.table.differenceX; same.table.differenceY], zeros(10, 1), 'AbsTol', 1e-12);
            half = struct("markIndex", (1:2:numel(unit.marks.x)).', "shotIndex", zeros(0, 1), "ok", true);
            difference = alignest.planStatisticsDifference(unit, half);
            valid = unit.marks.validX;
            chosen = false(size(valid));
            chosen(1:2:end) = true;
            testCase.verifyEqual(difference.table.planX(1), mean(unit.marks.measX(valid & chosen)), 'AbsTol', 1e-12);
            testCase.verifyEqual(difference.table.fullX(3), var(unit.marks.measX(valid)), 'AbsTol', 1e-9);
            testCase.verifyEqual(difference.table.differenceX(4), max(unit.marks.measX(valid & chosen)) - ...
                max(unit.marks.measX(valid)), 'AbsTol', 1e-12);
            data = testCase.Data;
            data.units = data.units(1:2);
            settings = alignest.defaultSettings();
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.sampling.method = "mark";
            settings.sampling.markPerShot = 1;
            settings.sampling.exchangeStarts = 2;
            results = alignest.runEvaluation(data, settings);
            comparison = alignest.layoutComparison(results, 1, "RMSE_XY", "mean", data);
            plans = results.plans;
            candidates = nnz(data.units(1).marks.validX | data.units(1).marks.validY);
            testCase.verifyEqual(comparison.rate(1), mean(100 * [plans.nMarks] ./ candidates), 'RelTol', 0.05);
            testCase.verifyTrue(isnan(alignest.layoutComparison(results, 1, "RMSE_XY", "mean").rate(1)), "データが無ければ NaN");
        end

        function shotCommonTermsAreChosenSeparately(testCase)
            % Shot 共通を「計算する」：Shot 共通の k に使う項を選べる（k1〜k6 は必ず）。Shot ごとは「使う」と次数の上限
            unit = testCase.Data.units(1);
            wafer = struct("label", unit.label, "points", alignest.highOrderUnitPoints(unit));
            settings = alignest.defaultSettings();
            settings.highOrder = struct("maker", "custom", "excludedTerms", 21:38, "unit", "shot", "waferOrder", 1, ...
                "loss", "ols", "regularization", "none", "shotCommon", "fit", "shotEachOrder", 1, "shotCommonTerms", [9, 10]);
            result = alignest.shotHighOrder(wafer, settings);
            common = unique(result.commonCoefficients.k).';
            testCase.verifyEqual(common, [1:6, 9, 10], "選んだ項と k1〜k6");
            testCase.verifyTrue(all(ismember(result.terms.k(result.terms.used).', 1:20)));
            settings.highOrder.shotCommonTerms = 0;
            testCase.verifyError(@() alignest.highOrderOptions(settings), 'alignest:highOrderShotCommon');
        end

        function runTabSelectsMarksAndShowsLog(testCase)
            % 実行タブ：記録の欄の代わりに計測の指定。クリックで Shot・Mark を必ず計測・計測しないにし、計測マップを作り直す。
            % 統計量の差の表、記録の窓。設定タブの Mark の数の決め方・計測しない shotNo
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyFalse(isfield(c, 'log'), "記録の欄は無い");
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            settings.sampling.method = ["ioptimal", "mark"];
            settings.sampling.nShots = 20;
            settings.sampling.exchangeStarts = 2;
            app.setSettings(settings);
            testCase.verifyEqual(string(c.markCountNote.Text), "Wafer 中心に最も近い Mark は必ず計測します。");
            c.markCountBy.Value = 'total';
            c.markCountBy.ValueChangedFcn([], []);
            testCase.verifyEqual(string({c.markPerShot.Enable, c.markCountStart.Enable}), ["off", "on"]);
            testCase.verifyEqual(app.Settings.sampling.markCountBy, "total");
            c.markCountBy.Value = 'perShot';
            c.markCountBy.ValueChangedFcn([], []);
            c.measurePlan.Value = c.measurePlan.Items(1);
            app.drawMeasurementMap(1);
            testCase.verifyEqual(size(c.measureStatistics.Data, 2), 8);
            testCase.verifyEqual(string(c.measureStatistics.Data(:, 2)).', ["平均", "中央値", "分散", "最大", "最小"]);
            app.setMeasurementSelection("shot", 50, "required");
            app.setMeasurementSelection("shot", 10, "excluded");
            testCase.verifyEqual([app.Settings.sampling.requiredShots, app.Settings.sampling.excludedShots], [50, 10]);
            testCase.verifyEqual(string(c.excludedShots.Value), "10", "設定タブの欄も直す");
            testCase.verifyNotEmpty(app.Controls.measureAxes, "計測マップを作り直す");
            app.setMeasurementSelection("shot", 10, "required");
            testCase.verifyEqual(app.Settings.sampling.requiredShots, [10, 50], "計測しないから必ず計測へ移す");
            testCase.verifyEmpty(app.Settings.sampling.excludedShots);
            c.measurePlan.Value = c.measurePlan.Items(end);
            app.drawMeasurementMap(1);
            c.measureClickMode.Value = 'excluded';
            marks = app.Data.units(1).marks;
            ax = app.Controls.measureAxes(1);
            ax.ButtonDownFcn(ax, struct('IntersectionPoint', [marks.x(5), marks.y(5), 0]));
            testCase.verifyEqual(app.Settings.sampling.excludedMarks, compose("%d-%d", marks.shotNo(5), marks.markNo(5)));
            testCase.verifyTrue(any(contains(string(c.measureSelectionInfo.Value), "計測しない Mark（1）")));
            c.clearMeasureSelections.ButtonPushedFcn([], []);
            testCase.verifyEmpty([app.Settings.sampling.requiredShots, app.Settings.sampling.excludedShots]);
            testCase.verifyEmpty(app.Settings.sampling.excludedMarks);
            testCase.verifyError(@() app.setMeasurementSelection("mark", "x", "required"), 'alignest:markKeys');
            app.showRunLog();
            testCase.verifyTrue(isvalid(app.LogWindow));
            delete(app.LogWindow);
        end

        function resultsAndWaferMapOptions(testCase)
            % 結果一覧：グラフの横軸に全計測に対する I 効率・D 効率（2つの図は同じ大きさ、凡例は図の中の右上）、計測配置の
            % 比較の横軸に計測率。Wafer ごとのマップ：Shot 番号と X・Y の MAE
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.sampling.method = ["ioptimal", "mark"];
            settings.sampling.nShots = [15, 25];
            settings.sampling.exchangeStarts = 2;
            app.setSettings(settings);
            app.runEvaluationNow(false);
            testCase.verifyNotEmpty(app.RunLog);
            testCase.verifyTrue(contains(string(c.runStatus.Text), "完了"));
            c.chartMethods.Value = c.chartMethods.ItemsData(1);
            c.chartXAxis.Value = 'efficiency';
            c.chartXAxis.ValueChangedFcn([], []);   % 画面で横軸を選ぶのと同じ
            testCase.verifyEqual(string(c.chartAxes.XLabel.String), "I 効率 [%]（全計測に対する。大きいほど良い計画）");
            testCase.verifyEqual(string(c.chartAxes.XScale), "linear");
            testCase.verifyEqual(c.chartAxesGrid.ColumnWidth, {'1x', '1x'});
            testCase.verifyEqual(string(c.chartAxes.Legend.Location), "northeast");
            c.chartXAxis.Value = 'plan';
            c.chartXAxis.ValueChangedFcn([], []);
            testCase.verifyEqual(string(c.chartAxes.Legend.Location), "northeast");
            comparison = app.drawLayoutComparison(1, "rate");
            testCase.verifyTrue(all(isfinite(comparison.rate)));
            testCase.verifyTrue(contains(string(c.compareLayoutAxes.XLabel.String), "計測率 [%]"));
            c.mapShotNumbers.Value = true;
            app.showMap(1, string(c.mapPlan.Items{1}), 1, "vector");
            labels = findall(c.mapAxes(1), 'Type', 'text', 'Tag', 'keepColor');   % 凡例に出さない文字は findall で探す
            testCase.verifyGreaterThan(numel(labels), 50, "Shot 番号を重ねる");
            testCase.verifyTrue(contains(string(c.mapInfo.Text), "MAE（X・Y）"));
        end

        function highOrderTabLayoutAndMapOptions(testCase)
            % Shot 高次補正：②の並び（Wafer 補正 → Shot 共通補正 → Shot ごとの補正）、Wafer の一覧の高さ、Shot 共通の項の列、
            % マップの Shot 番号・外れ値の ○・Scan 方向ごとの図、Wafer 上のグリッド（補正前の値）、2つの条件を並べるの ○、
            % 補正の比較の条件のタブ。Mark 配置の候補の表の幅
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            sections = string({c.highOrderShotCommon.Parent.Children(arrayfun(@(item) isa(item, ...
                'matlab.ui.control.Label') && item.FontWeight == "bold", c.highOrderShotCommon.Parent.Children)).Text});
            testCase.verifyTrue(all(ismember(["Wafer 補正", "Shot 共通補正", "Shot ごとの補正"], sections)));
            testCase.verifyLessThan(c.highOrderWaferOrder.Layout.Row, c.highOrderShotCommon.Layout.Row);
            testCase.verifyLessThan(c.highOrderShotCommon.Layout.Row, c.highOrderUnit.Layout.Row);
            testCase.verifyEqual(c.highOrderWafer.Parent.RowHeight{c.highOrderWafer.Layout.Row}, 48);
            testCase.verifyEqual([c.markOptCandidateTable.ColumnWidth{:}], [68, 116, 116, 132, 100, 100]);
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            app.setHighOrderSource("data");
            app.setHighOrderSettings(unit="shot", shotCommon="fit", shotEachOrder=1);
            names = reshape(string(c.highOrderTermTable.ColumnName), 1, []);
            testCase.verifyEqual(names(6), "共通");
            row = find(string(c.highOrderTermTable.Data(:, 3)) == "k9", 1);
            c.highOrderTermTable.CellEditCallback(c.highOrderTermTable, struct("Indices", [row, 6], "NewData", false));
            testCase.verifyFalse(ismember(9, app.Settings.highOrder.shotCommonTerms));
            testCase.verifyTrue(all(ismember(1:6, app.Settings.highOrder.shotCommonTerms)));
            row = find(string(c.highOrderTermTable.Data(:, 3)) == "k1", 1);
            c.highOrderTermTable.CellEditCallback(c.highOrderTermTable, struct("Indices", [row, 6], "NewData", false));
            testCase.verifyEqual(string(c.highOrderTermInfo.Text), "k1〜k6 は外せません");
            c.highOrderAllTerms.ButtonPushedFcn([], []);
            testCase.verifyEmpty(app.Settings.highOrder.shotCommonTerms, "すべての項を使うで戻す");
            app.setHighOrderSettings(unit="row");
            app.computeHighOrder(1);
            c.highOrderMapShotNumbers.Value = true;
            c.highOrderMapOutliers.Value = true;
            app.drawHighOrderMap(1, "wafer", "value", "grid");
            testCase.verifyGreaterThan(numel(findall(c.highOrderAxes, 'Type', 'text', 'Tag', 'keepColor')), 50);
            testCase.verifyFalse(contains(string(c.highOrderMapInfo.Text), "Wafer 上のグリッドは補正量だけ"));
            c.highOrderMapByScan.Value = true;
            app.drawHighOrderMap(1, "stack", "residual", "vector");
            testCase.verifyEqual(c.highOrderAxesGrid.ColumnWidth(1:2), {'1x', '1x'});
            testCase.verifyTrue(contains(string(c.highOrderAxes2.Title.String), "Scan 方向 2"));
            testCase.verifyEqual(string(c.highOrderMapLayout.Enable), "off");
            app.addHighOrderConditions("loss");
            testCase.verifyEqual(c.highOrderCompareResults.SelectedTab, c.highOrderConditionTab, "条件は下のタブ");
            app.compareHighOrderConditionsNow(1);
            testCase.verifyEqual(c.highOrderCompareResults.SelectedTab, c.highOrderCompareTableTab);
            pairAxes = [c.highOrderPairAxes, c.highOrderPairAxes2];
            app.drawHighOrderPair(1, 3, 1, "xy");   % 最小二乗と LAD（LAD は外れ値とみなす点がある）
            shown = numel(findall(pairAxes, 'Type', 'line', 'Marker', 'o'));
            c.highOrderPairOutliers.Value = false;
            app.drawHighOrderPair(1, 3, 1, "xy");
            hidden = numel(findall(pairAxes, 'Type', 'line', 'Marker', 'o'));
            testCase.verifyLessThan(hidden, shown, "外れ値の ○ を描かない");
            settings = app.Settings;
            testCase.verifyEqual(settings.highOrder.huberTuning, 3);
        end
    end
end
