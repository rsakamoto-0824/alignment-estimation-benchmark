classdef TestRangeVifHistoryScreens < matlab.unittest.TestCase
    %TESTRANGEVIFHISTORYSCREENS 画面：計測マップの範囲で選ぶ・ボタンの幅、Shot ごとの成分の選択肢、データ読込の MAD、結果一覧の
    %   「補正の悪化」、Shot 高次補正（欄の並び・VIF で選ぶを Shot 高次と Shot 共通に別々・1つの Shot の図の Wafer の縁と
    %   実測点・ヒストグラムの3段・結果の履歴から2つの条件を並べる）。

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
        function settingsRunAndResults(testCase)
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            % Shot ごとの成分に「並進」は無い（以前の設定の並進は 1次にする）
            testCase.verifyFalse(any(string(c.overlayPerShot.ItemsData) == "translation"));
            testCase.verifyEqual(c.overlayPerShot.Value, 'linear', "初期値は 1次");
            testCase.verifyEqual(c.overlayShotCommon.Value, 'none', "Shot 共通成分の初期値はなし");
            old = app.Settings;
            old.overlay.perShot = "translation";
            app.setSettings(old);
            testCase.verifyEqual(c.overlayPerShot.Value, 'linear');
            testCase.verifyEqual(c.designFeatures.Value, 'XYR');
            testCase.verifyTrue(any(string(c.samplingMethod.ItemsData) == "markrandom"));
            % 計測マップのボタンは決まった幅（文字が切れないように）
            testCase.verifyTrue(all(cellfun(@isnumeric, c.drawMeasure.Parent.ColumnWidth)));
            % データ読込の異常値の除外：MAD
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            c.dataExcludeOutliers.Value = true;
            c.dataExcludeOutliers.ValueChangedFcn([], []);
            testCase.verifyEqual(string(c.dataOutlierMethod.Enable), "on");
            c.dataOutlierMethod.Value = 'mad';
            c.dataOutlierMethod.ValueChangedFcn([], []);
            testCase.verifyEqual(app.Settings.data.outlierMethod, "mad");
            app.applyMapping();
            testCase.verifyEqual(app.Data.outlierMethod, "mad");
            % 計測マップの範囲で選ぶ：2点の四角に中心が入る Shot をまとめて「計測しない」にする
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.sampling.nShots = [10, 20];
            settings.sampling.nShotsStart = 10;
            settings.sampling.nShotsEnd = 20;
            settings.sampling.nShotsStep = 10;
            settings.sampling.exchangeStarts = 2;
            app.setSettings(settings);
            app.drawMeasurementMap(1);
            c.measureClickMode.Value = 'excluded';
            c.measureRange.Value = true;
            c.measureRange.ValueChangedFcn([], []);
            ax = app.Controls.measureAxes(1);
            ax.ButtonDownFcn(ax, struct("IntersectionPoint", [-160, -160, 0]));
            testCase.verifyEqual(string(c.measureSelectNote.Text), "四角のもう1つの角をクリックしてください。");
            testCase.verifyEmpty(app.Settings.sampling.excludedShots, "1点目では指定しない");
            ax.ButtonDownFcn(ax, struct("IntersectionPoint", [0, 0, 0]));
            shots = app.Data.units(1).shots;
            expected = unique(shots.shotNo(shots.Xmm <= 0 & shots.Ymm <= 0)).';
            testCase.verifyEqual(app.Settings.sampling.excludedShots, expected);
            testCase.verifyTrue(contains(string(c.measureSelectNote.Text), sprintf("%d 個の Shot", numel(expected))));
            app.setMeasurementSelection("shot", expected, "clear");
            testCase.verifyEmpty(app.Settings.sampling.excludedShots, "まとめて外す");
            % 結果一覧の「補正の悪化」：手法の線を X・Y の図に描く
            app.runEvaluationNow(false);
            testCase.verifyEqual(string(c.degradationXAxis.Enable), "on");
            testCase.verifyEqual(numel(findobj(c.degradationAxes(1), 'Type', 'line', 'LineStyle', '-')), ...
                numel(c.degradationMethods.Value));
            testCase.verifyTrue(startsWith(string(c.degradationInfo.Text), "点は手法"));
            c.degradationXAxis.Value = 'marks';
            c.degradationXAxis.ValueChangedFcn([], []);
            testCase.verifyEqual(string(c.degradationAxes(2).XLabel.String), "計測する Mark の数");
            % エラーバー（Wafer 間のばらつき）
            c.degradationErrorBar.Value = 'sd';
            c.degradationErrorBar.ValueChangedFcn([], []);
            testCase.verifyEqual(numel(findobj(c.degradationAxes(1), 'Type', 'errorbar')), numel(c.degradationMethods.Value));
        end

        function highOrderScreens(testCase)
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            % 補正のくくりが上、補正の式が「Shot ごとの補正」の行。初期値はカスタム・最小二乗・正則化なし
            testCase.verifyEqual([c.highOrderUnit.Layout.Row, c.highOrderMaker.Layout.Row], [1, 11]);
            testCase.verifyEqual(c.highOrderMaker.Value, 'custom');
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            app.setHighOrderSource("data");
            % VIF で選ぶ・すべての項を使うのボタンは、Shot 共通補正と Shot ごとの補正の欄に別々に置く
            testCase.verifyEqual([c.highOrderVifSelectCommon.Parent.Layout.Row, c.highOrderAllCommonTerms.Parent.Layout.Row], [9, 9]);
            testCase.verifyEqual([c.highOrderVifSelect.Parent.Layout.Row, c.highOrderAllTerms.Parent.Layout.Row], [13, 13]);
            % VIF で選ぶ：Shot 共通と Shot 高次を別々に
            app.setHighOrderSettings(maker="nikon", unit="shot", shotCommon="fit");
            testCase.verifyEqual(string(c.highOrderVifSelectCommon.Enable), "on");
            app.selectHighOrderTermsByVif(2, "common");
            common = app.Settings.highOrder.shotCommonTerms;
            testCase.verifyNotEmpty(common);
            testCase.verifyEmpty(app.Settings.highOrder.excludedTerms, "Shot 高次の項は変えない");
            app.selectHighOrderTermsByVif(2, "terms");
            testCase.verifyNotEmpty(app.Settings.highOrder.excludedTerms);
            testCase.verifyEqual(app.Settings.highOrder.shotCommonTerms, common, "Shot 共通の項は変えない");
            % Shot 共通の補正の式を別にする（Shot ごとはカスタム、Shot 共通は Nikon）
            app.useAllHighOrderTerms();
            app.setHighOrderSettings(maker="custom", shotCommonMaker="nikon", shotEachOrder=1);
            testCase.verifyEqual(string(c.highOrderCommonMaker.Enable), "on");
            testCase.verifyTrue(contains(string(c.highOrderVifInfo.Text), "Shot 共通は Nikon の式"));
            app.useAllHighOrderTerms("common");
            nikon = alignest.highOrderTerms("nikon");
            testCase.verifyEqual(app.Settings.highOrder.shotCommonTerms, unique(nikon.k.'), "Shot 共通の式のすべての項");
            separate = app.computeHighOrder(1);
            testCase.verifyTrue(contains(separate.description, "Shot 共通は Nikon"));
            testCase.verifyTrue(all(ismember(separate.commonCoefficients.k, nikon.k)), "Shot 共通の k は Nikon の式の項");
            % Wafer の比較：Shot 共通補正をかけたときは「Shot ごとの1次＋Shot 共通補正」も並べる
            residuals = app.drawHighOrderWaferComparison("residual");
            testCase.verifyTrue(any(string(residuals.Properties.VariableNames) == "Shot ごとの1次＋Shot 共通補正"));
            testCase.verifyEqual(numel(findobj(c.highOrderWaferAxes(1), 'Type', 'bar')), 6);
            testCase.verifyTrue(all(isfinite(separate.points.commonLinearResidualX(isfinite(separate.points.residualX)))));
            app.setHighOrderSettings(unit="common", shotCommonMaker="same");
            testCase.verifyEqual(string({c.highOrderVifSelectCommon.Enable, c.highOrderCommonMaker.Enable}), ["on", "on"], ...
                "Wafer 内で共通では、k の組の式・項を Shot 共通補正の欄で選ぶ");
            testCase.verifyEqual(string({c.highOrderVifSelect.Enable, c.highOrderMaker.Enable}), ["off", "off"], ...
                "Shot ごとの補正の欄は使わない");
            % 1つの Shot の図：実測点の位置と、外周の Shot では Wafer の縁
            app.useAllHighOrderTerms();
            app.setHighOrderSettings(loss="ols", regularization="none");
            run = app.computeHighOrder(1);
            points = run.points(run.points.wafer == run.points.wafer(1), :);
            radius = hypot(points.x - points.localX, points.y - points.localY);
            [~, outer] = max(radius);
            [~, inner] = min(radius);
            app.drawHighOrderMap(1, "shot", "residual", "vector", "", "single", points.shotNo(outer));
            testCase.verifyNotEmpty(findobj(c.highOrderAxes, 'DisplayName', '実測点の位置'));
            testCase.verifyNotEmpty(findobj(c.highOrderAxes, 'DisplayName', 'Wafer の縁'), "外周の Shot");
            testCase.verifyTrue(contains(string(c.highOrderMapInfo.Text), "Wafer の縁"));
            app.drawHighOrderMap(1, "shot", "residual", "vector", "", "single", points.shotNo(inner));
            testCase.verifyNotEmpty(findobj(c.highOrderAxes, 'DisplayName', '実測点の位置'));
            testCase.verifyEmpty(findobj(c.highOrderAxes, 'DisplayName', 'Wafer の縁'), "中心の Shot には縁が無い");
            % ヒストグラム：X・Y × すべて・内周・外周
            histogram_ = app.drawHighOrderHistogram("run", 0);
            testCase.verifyEqual(numel(c.highOrderHistogramAxes), 6);
            testCase.verifyTrue(all(arrayfun(@(ax) ~isempty(ax.Children), c.highOrderHistogramAxes)));
            testCase.verifyEqual(unique(histogram_.region, 'stable').', ["すべて", "内周", "外周"]);
            testCase.verifyTrue(contains(string(c.highOrderHistogramLegend.Text), '<font color="#'), "凡例に線の色");
            testCase.verifyFalse(contains(string(c.highOrderHistogramLegend.Text), '#000000'), "黒くしない");
            % 結果の履歴から2つの条件を並べる（同じ Wafer の最小二乗と Huber）
            app.setHighOrderSettings(loss="huber");
            app.computeHighOrder(1);
            app.setHighOrderPairSource("history");
            testCase.verifyEqual(numel(c.highOrderPairReference.Items), numel(app.HighOrderHistory));
            shots = app.drawHighOrderPair(numel(app.HighOrderHistory) - 1, numel(app.HighOrderHistory));
            testCase.verifyGreaterThan(height(shots), 0);
            testCase.verifyTrue(startsWith(string(c.highOrderPairInfo.Text), "左：結果 #"));
            % 違う入力（Wafer）で計算した結果どうしは比べられないと知らせる
            app.computeHighOrder(0);
            shots = app.drawHighOrderPair(numel(app.HighOrderHistory) - 1, numel(app.HighOrderHistory));
            testCase.verifyEmpty(shots);
            testCase.verifyTrue(contains(string(c.highOrderPairInfo.Text), "点が違います"));
            app.setHighOrderPairSource("comparison");
            testCase.verifyEqual(string(c.highOrderPairReference.Enable), "off", "補正の比較をしていなければ選べない");
        end
    end
end
