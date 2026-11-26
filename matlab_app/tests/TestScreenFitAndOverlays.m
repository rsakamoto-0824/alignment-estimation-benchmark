classdef TestScreenFitAndOverlays < matlab.unittest.TestCase
    %TESTSCREENFITANDOVERLAYS 分布を重ねた図（同じ値の手法の見分け・タブを開いたときの描き直し）と、画面（モニター）の
    %   大きさに合わせる窓・決まった幅の欄を確かめる。

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
        function overlaidHistogramsShowEverySeries(testCase)
            % 手法が3つ以上でもすべての線を描き、前の手法と同じ値の手法は破線と「＝ 〇〇と同じ」で見分けられる
            figureHandle = figure('Visible', 'off');
            closeFigure = onCleanup(@() close(figureHandle));
            ax = axes(figureHandle);
            values = {[1; 2; 3; 4], [1; 2; 3; 4], [2; 3; 5; 6], [0; 1; 1; 2]};
            alignest.plot.residualHistogram(ax, values, "X の残差", "nm", ["A", "B", "C", "D"]);
            lines_ = flipud(findobj(ax, 'Type', 'histogram'));
            testCase.verifyEqual(numel(lines_), 4);
            testCase.verifyEqual(string({lines_.LineStyle}), ["-", "--", "-", "-"]);
            testCase.verifyTrue(endsWith(lines_(2).DisplayName, "＝A と同じ"));
            colors = vertcat(lines_.EdgeColor);
            testCase.verifyEqual(size(unique(colors, 'rows'), 1), 4, "手法ごとに違う色");
            testCase.verifyEqual(numel(ax.Legend.String), 4);
        end

        function tabsRedrawWhenOpened(testCase)
            % 「推定値と誤差の分布」「残差の箱ひげ図」のタブを開くと、最後に分析した手法の数だけ描き直す
            raw = fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv');
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(raw);
            app.applyMapping();
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.methods.tps.enabled = true;
            settings.methods.tps.factorModes = ["none", "backfit"];
            settings.sampling.nShots = 20;
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(20, 20, 10);
            app.setSettings(settings);
            app.runEvaluationNow(false);
            c = app.Controls;
            app.analyzeResiduals([1, 2, 3], app.Results.groups(1), 0);
            for k = 1:2
                cla(c.histogramAxes(k));   % 描かれていない状態にしてから、タブを開く
            end
            analysisTab = c.histogramGrid.Parent.Parent;
            analysisTab.Parent.SelectedTab = analysisTab;   % 結果一覧の「誤差の分析」の中のタブ
            analysisTab.Parent.SelectionChangedFcn(analysisTab.Parent, struct("NewValue", analysisTab));
            testCase.verifyEqual(numel(findobj(c.histogramAxes(1), 'Type', 'histogram')), 3, "X も3つ");
            testCase.verifyEqual(numel(findobj(c.histogramAxes(2), 'Type', 'histogram')), 3);
            cla(c.boxAxes(1));
            c.boxTab.Parent.SelectedTab = c.boxTab;
            c.boxTab.Parent.SelectionChangedFcn(c.boxTab.Parent, struct("NewValue", c.boxTab));
            testCase.verifyEqual(numel(findobj(c.boxAxes(1), 'Type', 'BoxChart')), 3);
            testCase.verifyEqual(c.distributionTab.Children(1).RowHeight{3}, '1x', "分布の比較の表は決まった高さにしない");
        end

        function chartsRedrawAfterResize(testCase)
            % 窓の大きさを変え終えたら、見えている図（Wafer マップ）をすぐに描き直し、見えていない図はタブを開いたときに描き直す
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            c = app.Controls;
            c.dataTabs.SelectedTab = c.previewTab;
            app.TabGroup.SelectedTab = app.Tabs.data;
            previewBefore = c.previewAxes(1).Children;
            layoutBefore = c.layoutAxes(1).Children;
            app.refreshChartsAfterResize();
            testCase.verifyFalse(any(isvalid(previewBefore)), "見えている Wafer マップは描き直す");
            testCase.verifyTrue(all(isvalid(layoutBefore)), "見えていない図はまだ描き直さない");
            testCase.verifyEqual(app.ResizedCharts, ["layout", "overlay", "variance", "map", "target", "highOrder"]);
            c.dataTabs.SelectedTab = c.layoutTab;
            c.dataTabs.SelectionChangedFcn(c.dataTabs, struct("NewValue", c.layoutTab));
            testCase.verifyFalse(any(isvalid(layoutBefore)), "Shot レイアウトはタブを開いたときに描き直す");
            testCase.verifyEqual(app.ResizedCharts, ["overlay", "variance", "map", "target", "highOrder"]);
            app.TabGroup.SelectedTab = app.Tabs.map;
            app.TabGroup.SelectionChangedFcn(app.TabGroup, struct("NewValue", app.Tabs.map));
            testCase.verifyEqual(app.ResizedCharts, ["overlay", "variance", "target", "highOrder"], "結果が無いマップは描かずに済ませる");
            % ばらつき分解のタブを開くと、そのタブの図を描き直す
            app.TabGroup.SelectedTab = app.Tabs.data;
            c.dataTabs.SelectedTab = c.varianceTab;
            varianceBefore = c.varianceAxes(1).Children;
            c.dataTabs.SelectionChangedFcn(c.dataTabs, struct("NewValue", c.varianceTab));
            testCase.verifyFalse(any(isvalid(varianceBefore)));
            testCase.verifyEqual(app.ResizedCharts, ["overlay", "target", "highOrder"]);
            testCase.verifyNotEmpty(c.previewAxes(1).Children);
        end

        function laterTabsAreBuiltWhenOpened(testCase)
            % 「3. 結果一覧」から後のタブは、初めて開いたとき（またはそのタブの操作を呼んだとき）に作り、作る前のデータ・
            % 結果・文字の大きさ・画面の色を、すべてを起動のときに作ったときと同じに出す
            raw = fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv');
            lazy = AlignmentEstimationApp(false, true);
            cleanupLazy = onCleanup(@() delete(lazy));
            testCase.verifyEmpty(lazy.BuiltTabs);
            testCase.verifyFalse(any(isfield(lazy.Controls, ["summaryTable", "mapAxes", "targetWafer", ...
                "highOrderWafer", "markOptWafer", "rotationSource"])), "起動のときは作らない");
            eager = AlignmentEstimationApp(false);
            cleanupEager = onCleanup(@() delete(eager));
            laterTabs = ["results", "target", "highOrder", "markLayout", "rotation"];
            testCase.verifyEqual(eager.BuiltTabs, laterTabs, "画面を出さないときの既定は、すべて作る");
            settings = lazy.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.sampling.method = "random";
            settings.sampling.nShots = 20;
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(20, 20, 5);
            for app = [lazy, eager]
                app.loadFile(raw);
                app.applyMapping();
                app.setSettings(settings);
                app.setTheme("dark");
                app.setFontSize(18);
            end
            testCase.verifyEmpty(lazy.BuiltTabs, "読み込み・設定・表示の設定では作らない");
            lazy.runEvaluationNow(false);
            eager.runEvaluationNow(false);
            testCase.verifyEqual(lazy.BuiltTabs, "results", "評価すると結果一覧とマップを作る");
            testCase.verifyEqual(lazy.Controls.summaryTable.Data, eager.Controls.summaryTable.Data);
            testCase.verifyEqual(lazy.Controls.mapWafer.Items, eager.Controls.mapWafer.Items);
            for name = ["target", "highOrder", "markLayout", "rotation"]
                lazy.openTab(name);
                eager.openTab(name);
            end
            testCase.verifyEqual(sort(lazy.BuiltTabs), sort(laterTabs));
            l = lazy.Controls;
            e = eager.Controls;
            testCase.verifyEqual(l.targetWafer.Items, e.targetWafer.Items);
            testCase.verifyEqual(l.highOrderWafer.Items, e.highOrderWafer.Items);
            testCase.verifyEqual(l.highOrderMaker.Value, e.highOrderMaker.Value);
            testCase.verifyEqual(l.markOptMaker.Items, e.markOptMaker.Items);
            testCase.verifyEqual(l.rotationMethod.Items, e.rotationMethod.Items);
            % 後から作ったタブも、今の文字の大きさ・画面の色（補足の文字の色を含む）
            testCase.verifyEqual(l.targetRun.FontSize, e.targetRun.FontSize);
            testCase.verifyEqual(l.highOrderTermTable.FontSize, e.highOrderTermTable.FontSize);
            testCase.verifyEqual(l.targetInfo.FontColor, e.targetInfo.FontColor, 'AbsTol', 1e-9);
            testCase.verifyEqual(l.targetInfo.FontColor, lazy.Palette.muted, 'AbsTol', 1e-9);
            testCase.verifyEqual(l.rotationSource.BackgroundColor, e.rotationSource.BackgroundColor, 'AbsTol', 1e-9);
            testCase.verifyEqual(sort(cellfun(@(size_) size_, {lazy.FixedSizes.size})), ...
                sort(cellfun(@(size_) size_, {eager.FixedSizes.size})), "決まった大きさの行・列も同じだけ覚える");
            % まだ作っていないタブの操作を呼ぶと、そのタブを作ってから動く
            other = AlignmentEstimationApp(false, true);
            cleanupOther = onCleanup(@() delete(other));
            other.loadFile(raw);
            other.applyMapping();
            variability = other.computeRotationVariability("shot", "max");
            testCase.verifyNotEmpty(variability.table);
            testCase.verifyEqual(other.BuiltTabs, "rotation");
            % 図を保存するときもタブを作る（画面を出していないので、保存はできないと知らせる）
            testCase.verifyError(@() other.saveFigureImage("markLayoutShape", tempname + ".png"), 'alignest:hiddenFigure');
            testCase.verifyEqual(other.BuiltTabs, ["rotation", "markLayout"]);
        end

        function windowFitsTheScreen(testCase)
            % 画面に合わせる：窓は画面（モニター）の中に収まり、決まった幅の欄は中身の幅の比で狭める
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            testCase.verifyEqual(numel(app.ResponsiveColumns), 31, ['「2. 面内推定の設定」の「計測設定」の左の欄。' ...
                '絞り込みの欄は結果一覧とマップの2か所。「6. Shot高次補正」' ...
                '「7. Mark配置最適化」「8. 計測Mapローテ」の左の欄、結果一覧の「Wafer のベスト・ワースト」の総合に' ...
                '使う指標の欄・「補正の悪化」の描く手法の欄も']);
            app.Figure.Position = [-5000, -5000, 9000, 8000];
            app.fitToScreen(false);
            monitors = get(groot, 'MonitorPositions');
            position = app.Figure.Position;
            center = position(1:2) + position(3:4) / 2;
            inside = any(center(1) >= monitors(:, 1) & center(1) <= monitors(:, 1) + monitors(:, 3) & ...
                center(2) >= monitors(:, 2) & center(2) <= monitors(:, 2) + monitors(:, 4));
            testCase.verifyTrue(inside, "窓の中心が画面の中");
            testCase.verifyLessThanOrEqual(position(3:4), max(monitors(:, 3:4), [], 1) + 1, "画面より大きくしない");
            figureSize = [1440, 900];   % アプリの FIGURE_SIZE・MIN_CONTENT_SIZE と同じ値
            minContentSize = [1200, 700];
            testCase.verifyLessThanOrEqual(position(3:4), figureSize);
            scale = min(1, max(minContentSize(1), position(3)) / figureSize(1));
            for item = app.ResponsiveColumns
                testCase.verifyEqual(item.grid.ColumnWidth{item.column}, round(item.width * scale));
            end
            % 窓が中身の最小の大きさより小さいときは、中身をその大きさに保ってスクロールする
            % 見えない窓では大きさを変えても SizeChangedFcn が呼ばれないことがあるので、呼び出して確かめる
            app.Figure.Position(3:4) = [1000, 650];
            app.Figure.SizeChangedFcn(app.Figure, []);
            root = app.RootGrid;
            testCase.verifyEqual(root.Scrollable, matlab.lang.OnOffSwitchState('on'));
            testCase.verifyEqual(root.ColumnWidth{1}, minContentSize(1) - 2 * root.Padding(1));
            testCase.verifyEqual(root.RowHeight{1}, minContentSize(2) - 2 * root.Padding(1));
            for item = app.ResponsiveColumns
                testCase.verifyEqual(item.grid.ColumnWidth{item.column}, round(item.width * minContentSize(1) / figureSize(1)));
            end
            app.Figure.Position(3:4) = [1300, 800];
            app.Figure.SizeChangedFcn(app.Figure, []);
            testCase.verifyEqual(root.ColumnWidth{1}, '1x');
            testCase.verifyEqual(root.RowHeight{1}, '1x');
            % 中央に置く：窓の中心が、その画面の中心にくる
            app.fitToScreen(true);
            position = app.Figure.Position;
            center = position(1:2) + position(3:4) / 2;
            centers = monitors(:, 1:2) + monitors(:, 3:4) / 2;
            testCase.verifyLessThanOrEqual(min(hypot(centers(:, 1) - center(1), centers(:, 2) - center(2))), 1.5);
        end
    end
end
