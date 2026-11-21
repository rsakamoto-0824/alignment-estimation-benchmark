classdef TestAppConsistency < matlab.unittest.TestCase
    %TESTAPPCONSISTENCY アプリ全体の点検で直したところ：図の画像の保存・コピー（できないときの知らせ）、データを変えたときに
    %   前のデータの交互作用の結果を残さないこと、Wafer ごとのマップの上の欄の並び、計算中の進み具合の窓（文が見切れない高さ）。

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
        function savingFigureExplainsWhyItCannot(testCase)
            % 図の保存・コピー：画面を出していないとき・図の名前が違うときは、MATLAB を止めずにエラーで知らせる
            % （画面を出したときの保存・コピーは、見えない画面では書き出せないので自動テストでは確かめない）。
            % 「図をコピー」のボタンは保存のボタンの隣にあり、結果が無いうちは保存と同じく使えない
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            file = [tempname, '.png'];
            testCase.verifyError(@() app.saveFigureImage("chart", file), 'alignest:hiddenFigure');
            testCase.verifyError(@() app.saveFigureImage("noSuchFigure", file), 'alignest:figureName');
            testCase.verifyError(@() app.copyFigureImage("map"), 'alignest:hiddenFigure');
            testCase.verifyFalse(isfile(file));
            pairs = [c.saveMeasure, c.copyMeasure; c.saveChart, c.copyChart; c.saveMap, c.copyMap; ...
                c.targetSaveFigure, c.targetCopyFigure; c.targetResidualSave, c.targetResidualCopy];
            for k = 1:size(pairs, 1)
                testCase.verifyEqual(pairs(k, 2).Parent, pairs(k, 1).Parent, "保存のボタンの隣");
                testCase.verifyEqual(string(pairs(k, 2).Enable), string(pairs(k, 1).Enable), "保存と同じく使える・使えない");
            end
        end

        function changingDataClearsInteractions(testCase)
            % 読み込むと交互作用を調べ、読み込みの条件を変えたら前のデータの結果を消す（読み込み直すと調べ直す）
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            c = app.Controls;
            testCase.verifyNotEmpty(app.Interactions);
            testCase.verifyNotEmpty(c.interactionMainTable.Data);
            testCase.verifyEqual(string(c.interactionRun.Enable), "on");
            c.excludeZeroMeasurements.Value = ~c.excludeZeroMeasurements.Value;
            c.excludeZeroMeasurements.ValueChangedFcn(c.excludeZeroMeasurements, []);
            testCase.verifyEmpty(app.Data);
            testCase.verifyEmpty(app.Interactions);
            testCase.verifyEmpty(c.interactionMainTable.Data);
            testCase.verifyEmpty(c.interactionTable.Data);
            testCase.verifyEqual(string(c.interactionRun.Enable), "off");
            testCase.verifyEqual(string(c.interactionAxes.Visible), "off");
            app.applyMapping();
            testCase.verifyNotEmpty(app.Interactions);
        end

        function screenLayoutRules(testCase)
            % 画面の配置：「2. 面内推定の設定」は評価の設定と実行・計測マップを1つにまとめる（上の帯は評価のボタンと設定の
            % 保存、中のタブは計測設定・比べる手法・評価と Overlay 補正）。押せないボタン・使わない欄はしまう。
            % 結果一覧・Shot 高次補正の中のタブはまとまりに分ける。絞り込みの半径の上限は空欄で上限なし
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual(string({app.TabGroup.Children.Title}), ["1. データ読込", "2. 面内推定の設定", ...
                "3. 結果一覧", "4. Waferごとのマップ", "5. 未知の座標の推定", "6. Shot高次補正", "7. Mark配置の最適化", ...
                "8. 計測Mapローテ"]);
            testCase.verifyEqual(app.Tabs.run, app.Tabs.settings);
            testCase.verifyEqual(string({c.settingsTabs.Children.Title}), ["計測設定", "比べる手法", "評価・Overlay 補正"]);
            testCase.verifyEqual(c.run.Parent, c.runBar);
            testCase.verifyEqual(ancestor(c.measurePanel, 'uitab'), c.pointsTab, "計測マップは計測点の右");
            testCase.verifyEqual(string({c.resumeRun.Visible, c.extendRun.Visible}), ["off", "off"], "押せないときは出さない");
            testCase.verifyEqual(c.runBar.ColumnWidth(2:3), {0, 0});
            testCase.verifyNotEmpty(findobj(c.measurePanel, 'Type', 'uilabel'), "空の計測マップの案内");
            % I 最適だけなら、繰り返し回数・Excel 取込の行と Mark 単位の制約の段はしまう
            grid = c.samplingGrid;
            testCase.verifyEqual(grid.RowHeight([9, 10, 11, 12, 13, 25, 26]), repmat({0}, 1, 7));
            testCase.verifyEqual(string(c.loadLayouts.Visible), "off");
            c.samplingMethod.Value = {'ioptimal', 'excel', 'poisson'};
            c.samplingMethod.ValueChangedFcn([], []);
            testCase.verifyEqual(grid.RowHeight{12}, 90, "Excel 取込を選ぶと出す");
            testCase.verifyEqual(string(c.randomRepeats.Visible), "on");
            % データ読込：③ この対応で読み込む は ② のタブの下（どのタブでも押せる）
            testCase.verifyEqual(c.applyMapping.Parent.Parent, c.dataTabs.Parent);
            testCase.verifyEqual(c.applyMapping.Parent.Layout.Row, 3);
            testCase.verifyEqual(string(c.sheet.Visible), "off", "CSV・読む前はシートの欄を出さない");
            % 結果一覧と Shot 高次補正の中のタブのまとまり
            testCase.verifyEqual(string({c.resultTabs.Children.Title}), ["表・グラフ", "計測配置", "誤差の分析", "補正の比較"]);
            testCase.verifyEqual(string(c.chartTab.Parent.Parent.Parent.Title), "表・グラフ");
            testCase.verifyEqual(c.saveChart.Parent, c.chartXAxis.Parent, "グラフの保存はグラフのタブの右上");
            testCase.verifyEqual(string({c.highOrderOutputs.Children.Title}), ["入力と項", "結果", "比べる"]);
            % Shot 高次補正：段の見出しで閉じると、その段の欄をしまう
            button = c.highOrderSectionButtons(1);
            button.ButtonPushedFcn(button, []);
            testCase.verifyEqual(c.highOrderModelGrid.RowHeight{4}, 0);
            testCase.verifyTrue(startsWith(string(button.Text), "▶"));
            button.ButtonPushedFcn(button, []);
            testCase.verifyEqual(c.highOrderModelGrid.RowHeight{4}, 'fit');
            % 絞り込みの半径の上限：空欄なら上限なし。マップの矢印の倍率：空欄なら自動
            testCase.verifyEqual(string(c.filterResults.radiusMax.Value), "");
            testCase.verifyEqual(string(c.filterResults.radiusMax.Placeholder), "上限なし");
            testCase.verifyEqual(string(c.mapScale.Placeholder), "自動");
            % 空の図の案内（未知の座標・ローテーション）
            testCase.verifyEqual(string(c.targetAxes.Visible), "off");
            testCase.verifyNotEmpty(findobj(c.targetAxes, 'Tag', 'placeholder'));
            testCase.verifyNotEmpty(findobj(c.rotationSpreadAxes(1), 'Tag', 'placeholder'));
            % ローテーション：段のボタンは見出しの右（見出しと同じ小さな格子の2列目）
            for button = [c.rotationComputeVariability, c.rotationMakeMaps, c.rotationRunButton]
                testCase.verifyEqual(button.Layout.Column, 2);
                testCase.verifyEqual(button.Parent.ColumnWidth, {'1x', 'fit'});
            end
        end

        function mapHeaderKeepsMethodWide(testCase)
            % 「Shot の枠」は2行目、「図を画像で保存…」は2行目の右端（手法・図の内容の欄を広く取り、ほかのタブと同じく図の右上）
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual(c.mapShotFrames.Parent, c.mapScanFrames.Parent);
            testCase.verifyEqual(c.saveMap.Parent, c.mapShotFrames.Parent);
            testCase.verifyNotEqual(c.saveMap.Parent, c.mapMethod.Parent);
            testCase.verifyEqual(numel(c.mapMethod.Parent.ColumnWidth), 9);
        end

        function progressWindowGrowsWithMessage(testCase)
            % 計算中の進み具合の窓：文の行数に合わせて高くなる（低くはしない）。棒と割合、止めるボタン（窓の × も同じ）、
            % 閉じると消える。止めるボタンの無い窓は × で止めない。アプリの画面が見えていなければ窓も出さない
            owner = uifigure('Visible', 'off', 'Position', [100, 100, 1200, 700]);
            closeOwner = onCleanup(@() delete(owner));
            palette = struct("background", [1, 1, 1], "text", [0, 0, 0], "muted", [0.4, 0.4, 0.4], "accent", [0, 0.4, 0.7], ...
                "field", [1, 1, 1], "button", [0.95, 0.95, 0.95]);
            window = appui.ProgressWindow(owner, "評価中", "学習パターンを作っています…", palette, 16, "一時中断");
            testCase.verifyEqual(string(window.Window.Visible), "off");
            short = window.Window.Position(4);
            longName = join(repmat("GAM｜X,Y,半径（質的変数あり）｜ガウス過程 xy+r", 1, 4), "｜");
            window.Message = sprintf("12 / 480 件（残り 約 3 分）\n%s", longName);
            tall = window.Window.Position(4);
            testCase.verifyGreaterThan(tall, short, "長い文なら高くする");
            testCase.verifyEqual(window.Message, sprintf("12 / 480 件（残り 約 3 分）\n%s", longName));
            window.Message = "短い文";
            testCase.verifyEqual(window.Window.Position(4), tall, "短くしても低くしない");
            window.Value = 0.25;
            labels = findall(window.Window, 'Type', 'uilabel');
            testCase.verifyTrue(any(string({labels.Text}) == "25%"));
            testCase.verifyEqual(window.Value, 0.25);
            testCase.verifyFalse(window.CancelRequested);
            button = findall(window.Window, 'Type', 'uibutton');
            button.ButtonPushedFcn(button, []);
            testCase.verifyTrue(window.CancelRequested);
            testCase.verifyEqual(string(button.Enable), "off");
            close(window);
            testCase.verifyFalse(isvalid(window));
            fixed = appui.ProgressWindow(owner, "計測マップ", "", palette, 16, "");
            closeFixed = onCleanup(@() delete(fixed));
            testCase.verifyEmpty(findall(fixed.Window, 'Type', 'uibutton'));
            fixed.Window.CloseRequestFcn(fixed.Window, []);
            testCase.verifyFalse(fixed.CancelRequested, "止めるボタンの無い窓は止めない");
        end
    end
end
