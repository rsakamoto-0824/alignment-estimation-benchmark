classdef (Abstract) Core < handle
    %CORE 面内推定評価ツールの画面の共通部分：プロパティ・定数、起動の手順（startApp）、閉じるときの後始末、タブをまたいで使う処理（図の画像の保存・コピー、知らせの窓など）。
    %   AlignmentEstimationApp（画面の本体）の一部。画面の部品は Controls、データ・結果は Core のプロパティに持つ。
    %   タブごとのクラス（DataTab など）はこのクラスを受け継ぎ、AlignmentEstimationApp がすべてをまとめる。
    %   ほかのタブの関数も同じように呼べる（どれも AlignmentEstimationApp の関数になる）。

    properties (Constant, Access = {?appui.Core})
        APP_TITLE = "面内推定評価ツール"
        PREF_GROUP = "AlignmentEstimationApp"   % 表示の設定（画面の色・文字の大きさ・凡例の位置）を次に開いたときも使うための保存先（getpref）
        FONT_SIZE = 16                  % 画面の文字の標準の大きさ。下の文字の大きさ・決まった幅 [px] は、この大きさのときの値
        FONT_SIZE_CHOICES = [12, 14, 16, 18, 20]   % 「表示」→「文字の大きさ」の選択肢 [pt]
        FONT_SIZE_LIMITS = [10, 24]     % setFontSize で指定できる文字の大きさの範囲 [pt]
        AXES_FONT_SIZE = 13
        SMALL_AXES_FONT_SIZE = 10       % 図を並べるとき（計測マップ・マップの比較）の文字の大きさ
        LEGEND_CHOICES = ["auto", "northeast", "northwest", "southeast", "southwest", "best", ...
            "eastoutside", "westoutside", "northoutside", "southoutside", "none"]   % 凡例の位置（"auto" は図ごとの既定）
        LEGEND_LABELS = ["図ごとの既定", "図の中・右上", "図の中・左上", "図の中・右下", "図の中・左下", ...
            "図の中・線や点と重なりにくい所", "図の外・右", "図の外・左", "図の外・上", "図の外・下", "出さない"]
        LEGEND_MAX_COLUMNS = 4          % 凡例を図の上・下に移したときの列の数の上限
        FIGURE_SIZE = [1440, 900]          % 画面がこれより小さいときは画面に合わせて縮める
        SCREEN_MARGIN = 40
        MIN_FIGURE_SIZE = [800, 600]       % 窓の大きさの下限（画面がこれより小さいときは画面の大きさ）
        SCREEN_CHECK_SECONDS = 1           % 窓が別の画面（モニター）に移ったかを調べる間隔 [秒]
        MIN_CONTENT_SIZE = [1200, 700]     % 窓がこれより小さいときは、中身をこの大きさに保ってスクロールで見る（欄が詰まって崩れないように）
        PRIMARY_COLOR = [0.0, 0.36, 0.67]
        ARROW_COLORS = [0.0, 0.33, 0.62; 0.0, 0.33, 0.62; 0.75, 0.25, 0.10]  % 楕円と重ねるときの矢印（計測値・推定値・残差）
        NONE_LABEL = "（なし）"
        MAX_CURVES = 8
        METHOD_COLUMN_WIDTH = 440        % 結果の表の手法の列の幅 [px]（最も長い名前が収まる幅）
        VALUE_COLUMN_WIDTH = 90          % 結果の表の数値の列の幅 [px]
        PROGRESS_INTERVAL_SECONDS = 0.2
        ANALYSIS_METHOD_LIST_HEIGHT = 66   % 「推定値と誤差の分布」の手法の一覧の高さ [px]（3行ほど見える）
        RESIDUAL_CORRELATION_NOTICE = 0.3  % 「残差と説明変数」で、残差との相関 |r| がこれ以上の説明変数を色付きにする
        INTERACTION_TREND_ORDER = 3     % 「質的変数の交互作用」で Wafer ごとに除く面内の傾向（XY 多項式）の次数の初期値
        MAX_STACK_PANELS_NOTICE = 6     % Shot スタックマップの図がこれより多いときは、分け方を減らすよう知らせる
        DEFAULT_MARKER_SIZE = 30        % 色で描く Wafer マップの点の大きさの初期値（scatter の面積 [ポイント²]）
        MARKER_SIZE_LIMITS = [1, 400]
        UNIT_CHOICES = {'mm', 'µm', 'nm', 'm'}  % 座標の入力単位の選択肢（µm は内部では um として扱う）
        TABLE_FONT_SIZE = 13            % 列の多い表（座標の単位・検定の結果）の文字の大きさ
        LIST_PREVIEW_COUNT = 12         % 学習 Shot 数の並びを画面に出す数（多いときは途中を省く）
        EXCEL_MAX_DATA_ROWS = 1048575   % Excel の最大行数から見出しの1行を除いた数
        MAX_MATERN_NU = 50              % Matérn の ν の上限（alignest.models.maternNuCheck と同じ）
        FORMULA_CHOICE = -1             % Wafer 成分の選択肢「式を入力」の値（次数 0〜5 と区別する）
        MAX_ZERNIKE_ORDER = 7           % Fringe Zernike の次数の上限（Z1〜Z64）
        WORST_PERCENT = 95              % マップに出す「95%値」の百分位（結果一覧の集計と同じ）
        IMAGE_RESOLUTION = 150          % 「図を画像で保存…」の解像度 [dpi]
        IMAGE_GAP_PIXELS = 20           % 図を横に並べて1枚の画像にするときの間 [px]
        COPY_NOTICE_SECONDS = 2         % 「図をコピー」の後、ボタンに「コピーしました」と出しておく時間 [秒]
        COPY_TOOLTIP = 'PowerPoint・Teams・メールなどに貼り付けられるように、保存と同じ画像をクリップボードにコピーします。'
        MAX_MEASURE_PANELS = 6          % 計測マップを並べる数の上限（Wafer × 学習パターン）
        MAX_COMPARE_PANELS = 6          % Wafer ごとのマップで並べて比べる条件の数の上限
        TIMING_REPEAT_LIMITS = [1, 10]  % 処理時間の内訳を測る回数の範囲
        TARGET_GRID_PITCH_MM = 10       % 「格子で置く」の間隔の初期値 [mm]
        TARGET_GRID_RADIUS_MM = 140     % 「格子で置く」の半径の初期値 [mm]（有効半径 150 mm の少し内側）
        TARGET_ALL_TRAINING = "all"     % 学習データの選択肢「計測値のある全 Mark」の値（評価の学習パターンの名前と区別する）
        TARGET_LIST_HEIGHT = 72         % 「6. 未知の座標の推定」の Wafer・学習データの一覧の高さ [px]（3行ほど見える）
        TARGET_MESSAGE_HEIGHT = 76      % 同じく、メッセージの欄の高さ [px]（長いときは欄の中でスクロール）
        TARGET_COLUMNS = {'名前', 'Xmm', 'Ymm', 'markXmm', 'markYmm', 'markNo', 'shotNo', 'Direction'}  % 推定する点の表の列
    end

    properties (SetAccess = {?appui.Core})
        Figure
        RootGrid        % タブを入れる一番外の枠（窓が MIN_CONTENT_SIZE より小さいときにスクロールする）
        TabGroup
        Tabs = struct()
        Controls = struct()
        RawTable = table()
        FilePath = ""
        SheetName = ""
        Data = []
        AppliedMapping = struct()
        Settings
        Results = []
        MapCache
        Analysis = []   % 「推定値と誤差の分布」で最後に分析した結果（推定値の表と検定の結果）
        MeasurementCache = []   % 計測マップの学習パターン（設定・データが変わったら作り直す）
        Distribution = []       % 「分布の比較」で最後に比べた結果（alignest.distributionComparison）
        ImportedEstimates = []  % Excel から読み込んだ推定値（alignest.importEstimates。読み込んだ評価結果と組で使う）
        DefaultsSource = ""     % 初期設定に重ねた既定の設定ファイル（alignest.siteDefaults。無ければ ""）
        BaseResults = []        % 絞り込む前の評価の結果（Results は絞り込みの条件で指標を計算し直したもの）
        ResultFilter            % 評価点の絞り込みの条件（alignest.defaultPointFilter と同じ形）
        MapConditions = struct("option", {}, "plan", {}, "method", {}, "label", {})  % マップで並べて比べる条件
        Timing = []             % 「処理時間の内訳」で最後に測った結果（alignest.timingBreakdown）
        Theme = "light"         % 画面の色：light（ライトモード）・dark（ダークモード）。setTheme で変える
        TargetRun = []          % 「6. 未知の座標の推定」で最後に推定した結果（estimateTargets）
        Interactions = []       % 「質的変数の交互作用」で最後に調べた結果（alignest.factorInteractions）
        ScreenTimer = []        % 窓が別の画面（モニター）に移ったかを調べるタイマー（画面を出すときだけ）
        CurrentMonitor = 0      % 窓の中心がある画面の番号（get(groot, 'MonitorPositions') の行）
        ResponsiveColumns = struct("grid", {}, "column", {}, "width", {})  % 窓の幅に合わせて狭める欄（registerResponsiveColumn）
        TargetSelection = zeros(0, 1)  % 推定する点の表で選んでいる行（「選んだ行を削除」で使う）
        FontSize = 16           % 画面の文字の大きさ [pt]。setFontSize で変える（FONT_SIZE との比を図・表・決まった幅の欄にも掛ける）
        LegendLocation = "auto" % すべての図の凡例の位置（LEGEND_CHOICES の1つ）。setLegendLocation で変える
        LegendOverrides = struct()  % 図ごとに選んだ凡例の位置（名前は図の Controls の名前。setLegendLocation の第3引数）
        LegendMenus = struct()      % 図を右クリックしたときの凡例の位置のメニュー（図ごとに1つ）
        FixedSizes = struct("grid", {}, "property", {}, "index", {}, "size", {})  % 文字の大きさに合わせる決まった大きさ [px] の行・列
        FontVersion = 0         % 文字の大きさを変えた回数（見えていなかったタブを開いたときに、文字を付け直すかの目印）
        HighOrderFile = []      % 「7. Shot高次補正」で読み込んだ Excel・CSV（raw：読んだ表、info：alignest.readHighOrderFile、
                                %  data：選んだ列で整理した Wafer ごとのデータ（alignest.prepareHighOrderData。まだなら []）、mapping）
        HighOrderRun = []       % 「7. Shot高次補正」で最後に計算した結果（computeHighOrder。alignest.shotHighOrder の結果と入力）
        HighOrderConditions = struct("label", {}, "highOrder", {})  % 「7. Shot高次補正」の補正の比較の条件（名前と settings.highOrder）
        HighOrderComparison = []  % 「7. Shot高次補正」の補正の比較の結果（compareHighOrderConditionsNow。表・条件ごとの結果と、比べた条件・入力）
    end

    properties (Dependent)
        Palette                 % 今の画面の色の組（themePalette。文字・背景・エラー・表の最良の色など）
        FontScale               % 文字の大きさの比（FontSize / FONT_SIZE）
    end

    methods
        function palette = get.Palette(app)
            palette = themePalette(app.Theme);
        end

        function scale = get.FontScale(app)
            scale = app.FontSize / app.FONT_SIZE;
        end

        function delete(app)
            if ~isempty(app.ScreenTimer) && isvalid(app.ScreenTimer)
                stop(app.ScreenTimer);
                delete(app.ScreenTimer);
            end
            if ~isempty(app.Figure) && isvalid(app.Figure)
                delete(app.Figure);
            end
        end
    end

    methods (Access = {?appui.Core})
        function startApp(app, visible)
            %STARTAPP 画面を作って開く（AlignmentEstimationApp のコンストラクターから呼ぶ）。visible = false なら
            %   画面を出さずに作る（自動テスト用）。
            % 初期設定：管理者が今のフォルダに既定の設定ファイルを置いていれば、それを重ねる（alignest.siteDefaults）。
            % 読めないときは初期設定で開き、画面を作った後に理由を出す（起動できなくならないように）
            defaultsError = "";
            try
                [app.Settings, app.DefaultsSource] = alignest.siteDefaults();
            catch err
                app.Settings = alignest.defaultSettings();
                defaultsError = string(err.message);
            end
            app.ResultFilter = alignest.defaultPointFilter();
            app.MapCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
            app.Figure = uifigure('Name', app.APP_TITLE, 'Position', figurePosition(app), ...
                'Visible', matlab.lang.OnOffSwitchState(visible), 'CloseRequestFcn', @(~, ~) delete(app));
            root = uigridlayout(app.Figure, [1, 1], 'Padding', 8, 'Scrollable', 'on');
            app.RootGrid = root;
            app.TabGroup = uitabgroup(root);
            app.Tabs.data = uitab(app.TabGroup, 'Title', '1. データの読み込み');
            app.Tabs.settings = uitab(app.TabGroup, 'Title', '2. 評価の設定');
            app.Tabs.run = uitab(app.TabGroup, 'Title', '3. 実行');
            app.Tabs.results = uitab(app.TabGroup, 'Title', '4. 結果一覧');
            app.Tabs.map = uitab(app.TabGroup, 'Title', '5. Waferごとのマップ');
            app.Tabs.target = uitab(app.TabGroup, 'Title', '6. 未知の座標の推定');
            app.Tabs.highOrder = uitab(app.TabGroup, 'Title', '7. Shot高次補正');
            app.Tabs.help = uitab(app.TabGroup, 'Title', '8. ヘルプ');
            app.TabGroup.SelectionChangedFcn = @(~, event) app.onTabChanged(event);
            buildDataTab(app);
            buildSettingsTab(app);
            buildRunTab(app);
            buildResultsTab(app);
            buildMapTab(app);
            buildTargetTab(app);
            buildHighOrderTab(app);
            buildHelpTab(app);
            % 表示のメニュー：ライトモード・ダークモードの切り替え、文字の大きさ、凡例の位置と、ヘルプを開く
            viewMenu = uimenu(app.Figure, 'Text', '表示');
            app.Controls.themeLight = uimenu(viewMenu, 'Text', 'ライトモード', 'Checked', 'on', ...
                'MenuSelectedFcn', @(~, ~) app.setTheme("light"));
            app.Controls.themeDark = uimenu(viewMenu, 'Text', 'ダークモード', ...
                'MenuSelectedFcn', @(~, ~) app.setTheme("dark"));
            fontMenu = uimenu(viewMenu, 'Text', '文字の大きさ', 'Separator', 'on');
            app.Controls.fontSizeItems = gobjects(1, 0);
            for size_ = app.FONT_SIZE_CHOICES
                label = sprintf('%d pt', size_);
                if size_ == app.FONT_SIZE
                    label = [label, '（標準）']; %#ok<AGROW>
                end
                app.Controls.fontSizeItems(end + 1) = uimenu(fontMenu, 'Text', label, 'UserData', size_, ...
                    'Checked', onOff(size_ == app.FONT_SIZE), 'MenuSelectedFcn', @(~, ~) app.setFontSize(size_));
            end
            legendMenu = uimenu(viewMenu, 'Text', '凡例の位置');
            app.Controls.legendItems = gobjects(1, 0);
            for k = 1:numel(app.LEGEND_CHOICES)
                choice = app.LEGEND_CHOICES(k);
                app.Controls.legendItems(end + 1) = uimenu(legendMenu, 'Text', app.LEGEND_LABELS(k), 'UserData', choice, ...
                    'Checked', onOff(choice == app.LegendLocation), 'MenuSelectedFcn', @(~, ~) app.setLegendLocation(choice));
            end
            uimenu(legendMenu, 'Text', '図ごとに選んだ位置をすべて戻す', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~, ~) app.resetLegendOverrides());
            uimenu(legendMenu, 'Text', '（図を右クリックすると、その図だけの位置を選べます）', 'Enable', 'off');
            % Scan 方向 1・2 の向き（▲・▼）と色（図の印と色だけ。推定の結果は変わらない。設定 display に入る）
            scanMenu = uimenu(viewMenu, 'Text', 'Scan 方向の向きと色');
            app.Controls.scanUpItems = [ ...
                uimenu(scanMenu, 'Text', '1 = 上向き（▲）、2 = 下向き（▼）', 'MenuSelectedFcn', ...
                @(~, ~) app.setScanStyle(scan1Up=true)), ...
                uimenu(scanMenu, 'Text', '1 = 下向き（▼）、2 = 上向き（▲）', 'MenuSelectedFcn', ...
                @(~, ~) app.setScanStyle(scan1Up=false))];
            app.Controls.scanColorItems = [ ...
                uimenu(scanMenu, 'Text', 'Scan 方向 1 の色…', 'Separator', 'on', 'MenuSelectedFcn', ...
                @(~, ~) app.onPickScanColor(1)), ...
                uimenu(scanMenu, 'Text', 'Scan 方向 2 の色…', 'MenuSelectedFcn', @(~, ~) app.onPickScanColor(2))];
            uimenu(scanMenu, 'Text', '既定の向きと色に戻す', 'Separator', 'on', 'MenuSelectedFcn', ...
                @(~, ~) app.resetScanStyle());
            uimenu(scanMenu, 'Text', '（図の印と色だけ。推定の結果は変わりません）', 'Enable', 'off');
            uimenu(viewMenu, 'Text', '画面の大きさに合わせる', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~, ~) app.fitToScreen(true));
            uimenu(viewMenu, 'Text', 'ヘルプ（用語・補正の式・カーネル）を開く', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~, ~) set(app.TabGroup, 'SelectedTab', app.Tabs.help));
            set(findall(app.Figure, '-property', 'FontSize'), 'FontSize', app.FONT_SIZE);
            set(findall(app.Figure, 'Type', 'axes'), 'FontSize', app.AXES_FONT_SIZE);
            set(fontTables(app), 'FontSize', app.TABLE_FONT_SIZE);
            collectFixedSizes(app);
            % 見えていないタブの部品は、文字の大きさを変えても表示が古いままのことがあるので、タブを開いたときに付け直す
            for tabGroup = reshape(findall(app.Figure, 'Type', 'uitabgroup'), 1, [])
                addlistener(tabGroup, 'SelectedTab', 'PostSet', @(~, event) app.refreshTabFonts(event.AffectedObject.SelectedTab));
            end
            settingsToControls(app);
            refreshRunSummary(app);
            if app.DefaultsSource ~= ""
                app.Controls.log.Value = {char("既定の設定ファイルを読み込みました（初期設定に使います）：" + app.DefaultsSource)};
            elseif defaultsError ~= ""
                app.Controls.log.Value = {char("⚠ " + defaultsError + " アプリの初期設定で開きました。")};
                if visible
                    uialert(app.Figure, char(defaultsError + " アプリの初期設定で開きました。"), '既定の設定ファイル', ...
                        'Icon', 'warning');
                end
            end
            if visible
                % 前回選んだ表示の設定を使う（自動テストなど画面を出さないときは標準のまま）。読めない値は使わない
                if string(loadPreference(app, 'theme', 'light')) == "dark"
                    setTheme(app, "dark");
                end
                savedSize = loadPreference(app, 'fontSize', app.FONT_SIZE);
                if isnumeric(savedSize) && isscalar(savedSize) && savedSize ~= app.FONT_SIZE && ...
                        savedSize >= app.FONT_SIZE_LIMITS(1) && savedSize <= app.FONT_SIZE_LIMITS(2)
                    setFontSize(app, savedSize);
                end
                savedLocation = string(loadPreference(app, 'legendLocation', 'auto'));
                if isscalar(savedLocation) && any(savedLocation == app.LEGEND_CHOICES)
                    app.LegendLocation = savedLocation;
                end
                app.LegendOverrides = validLegendOverrides(loadPreference(app, 'legendOverrides', struct()), ...
                    app.LEGEND_CHOICES);
                markLegendItems(app);
                % 「7. Shot高次補正」で保存した項の組み合わせ（同じ名前なら、既定の設定ファイルより前回保存したものを使う）
                savedSets = loadPreference(app, 'highOrderTermSets', {});
                if iscellstr(savedSets) || isstring(savedSets)
                    app.Settings.highOrder.termSets = mergeTermSets(savedSets, app.Settings.highOrder.termSets);
                    refreshHighOrderTermSets(app);
                end
            end
            % 画面（モニター）の大きさ・解像度に合わせる：窓の幅に合わせて決まった幅の欄を狭め、別の画面に移したら
            % 窓をその画面に収まる大きさにする（画面の大きさが違う画面の間で動かしても、つり合いが崩れないように）
            app.Figure.AutoResizeChildren = 'off';   % 中は uigridlayout が合わせる（on のままだと SizeChangedFcn が動かない）
            app.Figure.SizeChangedFcn = @(~, ~) app.applyResponsiveLayout();
            applyResponsiveLayout(app);
            app.CurrentMonitor = monitorIndexOf(app.Figure.Position);
            if visible
                app.ScreenTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', app.SCREEN_CHECK_SECONDS, ...
                    'BusyMode', 'drop', 'Name', 'AlignmentEstimationApp:screen', 'TimerFcn', @(~, ~) app.onScreenCheck());
                start(app.ScreenTimer);
            end
        end

        % ================= 共通 =================
        function requireEstimates(app)
            % 推定値を計算し直す機能（分析・散布図・分布の比較・推定値の書き出し）を使える結果か確かめる
            if isempty(app.Results)
                error('alignest:noResults', '先に「3. 実行」で評価してください。');
            end
            if isImportedResults(app.Results) && isempty(app.ImportedEstimates)
                error('alignest:importedResults', ['Excel から読み込んだ結果では推定値を計算できません。' ...
                    '「推定値の Excel を読み込む…」で推定値の Excel も読み込むか、計測ファイルを読み込んで' ...
                    '「3. 実行」で評価し直してください。']);
            end
        end

        function [estimates, messages, overlayPoints] = importedEstimates(app, selection, includeTraining)
            % 読み込んだ推定値の Excel から、選んだ手法・学習パターンの列・Wafer の行を取り出す（評価点。includeTraining なら
            % 学習データの行も）。Excel に無い組み合わせは messages に書く
            results = app.Results;
            imported = app.ImportedEstimates;
            ids = string({results.methods(selection.methodIndex).id});
            wafers = results.unitLabels(selection.unitIndex);
            pick = @(points) ismember(points.methodId, ids) & ismember(points.group, string(selection.groups)) & ...
                ismember(points.Wafer, wafers);
            estimates = imported.estimates(pick(imported.estimates), :);
            if ~includeTraining
                estimates = estimates(estimates.role == "評価", :);
            end
            overlayPoints = table();
            if height(imported.overlayPoints) > 0
                overlayPoints = imported.overlayPoints(pick(imported.overlayPoints), :);
            end
            messages = strings(0, 1);
            if height(estimates) == 0
                messages = "選んだ手法・学習パターン・Wafer の推定値は、読み込んだ推定値の Excel にありません" + ...
                    "（書き出した範囲の外）。";
            end
        end

        function clearResults(app)
            app.Results = [];
            app.BaseResults = [];
            app.ImportedEstimates = [];
            app.Analysis = [];
            app.Timing = [];
            app.ResultFilter = alignest.defaultPointFilter();
            app.MapConditions = app.MapConditions([]);
            app.MapCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
            c = app.Controls;
            if ~isfield(c, 'summaryTable')
                return
            end
            c.summaryTable.Data = {};
            c.comparisonTable.Data = {};
            c.normalityTable.Data = {};
            c.anovaTable.Data = {};
            for ax = [c.chartAxes, c.chartAxes2, c.histogramAxes, c.mapAxes, c.scatterAxes]
                cla(ax);
                legend(ax, 'off');
            end
            for ax = [c.boxAxes, c.timingAxes]
                cla(ax, 'reset');
                legend(ax, 'off');
                ax.Visible = 'off';
            end
            delete(c.comparePanel.Children);
            app.Controls.compareAxes = gobjects(1, 0);
            c.mapStack.RowHeight = {'1x', 0};
            c.mapView.Value = 'single';
            refreshMapConditions(app);
            c.boxFactor.Items = {'—'};
            c.boxInfo.Text = '';
            cla(c.compareLayoutAxes, 'reset');
            legend(c.compareLayoutAxes, 'off');
            c.compareLayoutTable.Data = {};
            c.compareLayoutInfo.Text = c.compareLayoutInfo.UserData;
            c.timingTable.Data = {};
            c.timingInfo.Text = c.timingInfo.UserData;
            c.chartAxes2.Visible = 'off';
            set([c.export, c.saveChart, c.copyChart, c.mapWafer, c.mapPlan, c.mapMethod, c.mapContent, c.mapMode, c.mapScale, ...
                c.mapMarkerSize, c.mapMarkerShape, c.mapEllipse, c.mapEllipseOnly, c.mapShotFrames, c.saveMap, c.copyMap, c.analysisMethod, ...
                c.analysisGroup, ...
                c.analysisWafer, c.analyze, ...
                c.estimateScope, c.exportEstimates, c.scatterMethod, c.scatterGroup, c.scatterWafer, c.scatterColor, ...
                c.drawScatterButton, c.distributionMethod, c.distributionGroup, c.distributionWafer, c.distributionAxis, ...
                c.compareDistributionsButton, c.resumeRun, c.extendRun, c.mapScanFrames, c.mapRings, c.mapView, ...
                c.mapCompareValue, c.mapConditions, c.mapAddCondition, c.mapRemoveCondition, c.mapClearConditions, ...
                c.mapStackBy, c.mapStackAll, c.residualVariableMethod, c.residualVariableGroup, c.residualVariableWafer, ...
                c.residualVariableName, c.drawResidualVariableButton, c.boxFactor, c.timingWafer, c.timingPlan, c.timingMethods, c.timingRepeats, c.measureTimingButton, ...
                c.compareLayoutMethod, c.compareLayoutXAxis, c.compareLayoutErrorBar, ...
                c.filterResults.apply, c.filterMap.apply], 'Enable', 'off');
            showFilter(app);
            app.Distribution = [];
            c.distributionTable.Data = {};
            c.jsTable.Data = {};
            for ax = [c.distributionAxes, c.residualVariableAxes]
                cla(ax, 'reset');
                legend(ax, 'off');
                ax.Visible = 'off';
            end
            c.residualVariableTable.Data = {};
            c.runStatus.Text = "";
            c.mapInfo.Text = "「3. 実行」で評価すると、ここに Wafer ごとの図が出ます。";
            c.resultSource.Text = '';
            c.resultControls.RowHeight{3} = 0;
            c.importEstimates.Enable = 'off';
            c.analysisNote.Text = c.analysisNote.UserData;
        end

        function onResultTabChanged(app, event)
            % 結果一覧の中のタブを開いたら、そのタブの図を描き直す（見えていないタブに描いた図は、開いたときに一部しか
            % 描かれない・前の図のままになることがあるため）
            c = app.Controls;
            try
                if ~isempty(app.Analysis) && event.NewValue == c.histogramGrid.Parent.Parent
                    showAnalysis(app);
                elseif ~isempty(app.Analysis) && event.NewValue == c.boxTab && c.boxFactor.Enable == "on"
                    drawResidualBoxplot(app);
                elseif ~isempty(app.Distribution) && event.NewValue == c.distributionTab
                    drawDistributionHistograms(app);
                end
            catch
                % 描き直せなくても、前に描いた図のままにする（表示を変えるだけなので止めない）
            end
        end

        function onScreenCheck(app)
            % タイマー：窓の中心が別の画面（モニター）に移ったら、その画面に合わせる（最大化・全画面のときはしない）
            if ~isvalid(app) || isempty(app.Figure) || ~isvalid(app.Figure) || app.Figure.Visible == "off" || ...
                    app.Figure.WindowState ~= "normal"
                return
            end
            try
                index = monitorIndexOf(app.Figure.Position);
                if index ~= app.CurrentMonitor
                    app.CurrentMonitor = index;
                    fitToScreen(app, false);
                end
            catch
                % タイマーの中のエラーでタイマーが止まらないように、この回は見送る（次の回に確かめ直す）
            end
        end

        function registerResponsiveColumn(app, grid, column)
            % 決まった幅（[px]）の欄を、窓の幅に合わせて狭める欄として覚える（今の幅を FIGURE_SIZE の幅のときの幅とする）
            app.ResponsiveColumns(end + 1) = struct("grid", grid, "column", column, "width", grid.ColumnWidth{column});
        end

        function applyResponsiveLayout(app)
            % 窓が FIGURE_SIZE より狭いときは、決まった幅の欄（左の条件・右の一覧など）を中身の幅の比で狭める
            % （小さい画面に移しても、図や表の場所が決まった幅の欄に取られすぎないように）。窓が MIN_CONTENT_SIZE より
            % 小さい向きは、中身をその大きさに保ってスクロールする（それより詰めると、幅を決めない欄が無くなり、
            % 見出しが縦に長く折り返して図や表が隠れるため）。文字の大きさを変えたときは、決まった幅の欄と中身の最小の
            % 大きさにも文字の大きさの比を掛ける（大きな文字が欄からはみ出さないように）
            if isempty(app.Figure) || ~isvalid(app.Figure)
                return
            end
            figureSize = app.Figure.Position(3:4);
            minContentSize = scaledPixels(app, app.MIN_CONTENT_SIZE);
            contentSize = max(figureSize, minContentSize);
            padding = 2 * app.RootGrid.Padding(1);
            sizes = {{'1x'}, {'1x'}};
            for k = find(figureSize < minContentSize)
                sizes{k} = {minContentSize(k) - padding};
            end
            set(app.RootGrid, 'ColumnWidth', sizes{1}, 'RowHeight', sizes{2});
            scale = min(1, contentSize(1) / app.FIGURE_SIZE(1)) * app.FontScale;
            for item = app.ResponsiveColumns
                if ~isvalid(item.grid)
                    continue
                end
                widths = item.grid.ColumnWidth;
                widths{item.column} = round(item.width * scale);
                item.grid.ColumnWidth = widths;
            end
        end

        function position = figurePosition(app)
            % 画面の中央に、画面からはみ出さない大きさで置く
            screen = get(groot, 'ScreenSize');
            size_ = min(app.FIGURE_SIZE, screen(3:4) - 2 * app.SCREEN_MARGIN);
            size_ = max(size_, [800, 600]);
            corner = max(screen(1:2) + (screen(3:4) - size_) / 2, screen(1:2));
            position = [corner, size_];
        end

        function button = primaryButton(app, parent, text, callback)
            % 画面ごとに1つだけの主な操作（塗りつぶしのボタン）
            button = uibutton(parent, 'Text', text, 'ButtonPushedFcn', callback, ...
                'BackgroundColor', app.PRIMARY_COLOR, 'FontColor', [1, 1, 1], 'FontWeight', 'bold', 'Tag', 'primary');
        end

        function spinner = markerSizeSpinner(app, parent, callback)
            spinner = uispinner(parent, 'Limits', app.MARKER_SIZE_LIMITS, 'Value', app.DEFAULT_MARKER_SIZE, 'Step', 5, ...
                'Tooltip', '色で描く点の大きさ（面積）。点が重なるときは小さく、まばらなときは大きくします。', ...
                'ValueChangedFcn', callback);
        end

        function item = errorLabel(app, parent, row, column)
            item = uilabel(parent, 'Text', '', 'FontColor', app.Palette.error, 'WordWrap', 'on');
            place(item, row, column);
        end

        function pixels = figureImage(app, figureName)
            % 保存・コピーする図の画像（高さ × 幅 × 3）。図が2つ以上なら横に並べて1枚にする（saveFigureImage の説明）
            items = figureItems(app, string(figureName));
            if app.Figure.Visible == "off"
                error('alignest:hiddenFigure', '図の画像は、画面を出しているときに保存・コピーできます。');
            end
            drawnow;   % 並べ方を変えた直後は、図の大きさが決まってから書き出す（大きさ 0 の図は書き出せない）
            % 描いてある図だけ（軸を消して描く図は Visible が off なので、中身があるかで決める。使わない図は中身を消してある。
            % 色の点は凡例に出さないよう HandleVisibility を off にして描くので、Children ではなく allchild で数える）
            items = items(arrayfun(@(item) isvalid(item) && ~isempty(allchild(item)), items));
            if isempty(items)
                error('alignest:noFigure', '図がありません。先に図を描いてください。');
            end
            images = cell(1, numel(items));
            for k = 1:numel(items)
                file = [tempname, '.png'];
                exportgraphics(items(k), file, 'Resolution', app.IMAGE_RESOLUTION);
                images{k} = imread(file);
                delete(file);
            end
            pixels = joinImages(images, app.IMAGE_GAP_PIXELS);
        end

        function onCopyFigure(app, figureName, button)
            % 「図をコピー」のボタン：図をクリップボードにコピーし、少しの間ボタンに「コピーしました」と出す
            if figureName == "chart"
                app.Controls.resultTabs.SelectedTab = app.Controls.chartTab;   % コピーするグラフを見せる
            end
            if runWithAlert(app, @() app.copyFigureImage(figureName), "図をコピーできませんでした", ...
                    "図を描いてから、もう一度試してください。")
                flashButtonText(button, "コピーしました", app.COPY_NOTICE_SECONDS);
            end
        end

        function items = figureItems(app, figureName)
            % 保存する図（saveFigureImage）：axes か、並べた図の tiledlayout
            c = app.Controls;
            switch figureName
                case "measure"
                    items = findobj(c.measurePanel.Children, 'flat', 'Type', 'tiledlayout');
                case "chart"
                    items = [c.chartAxes, c.chartAxes2];
                case "map"
                    if string(c.mapView.Value) == "single"
                        items = c.mapAxes;
                    else
                        items = findobj(c.comparePanel.Children, 'flat', 'Type', 'tiledlayout');   % 並べて比べる・スタック
                    end
                case "target"
                    items = c.targetAxes;
                case "targetResidual"
                    items = c.targetResidualAxes;
                case "highOrder"
                    items = [c.highOrderAxes, c.highOrderAxes2, c.highOrderAxes3];   % 並べたときは3つ（使わない図は中身が無い）
                case "highOrderPair"
                    items = [c.highOrderPairAxes, c.highOrderPairAxes2];   % 基準（左）と比べる条件（右）
                case "highOrderHistogram"
                    items = c.highOrderHistogramAxes;
                case "highOrderDecomposition"
                    items = c.highOrderDecompositionAxes;
                otherwise
                    error('alignest:figureName', '保存する図の名前が違います: %s', figureName);
            end
        end

        function saveFigureWithDialog(app, figureName, defaultName)
            % 「図を画像で保存…」のボタン：保存先を選んで saveFigureImage で保存する
            [fileName, folder] = uiputfile({'*.png', 'PNG 画像 (*.png)'}, '図を保存', defaultName);
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            if runWithAlert(app, @() app.saveFigureImage(figureName, target), "図を保存できませんでした", ...
                    "図を描いてから、もう一度試してください。描いてあるときは、保存先のフォルダを変えてください。")
                uialert(app.Figure, sprintf('保存しました：%s', target), '保存しました', 'Icon', 'success');
            end
        end

        function ok = runWithAlert(app, action, titleText, nextStep)
            % 失敗したら「何が起きたか・なぜか・次にどうするか」を出す
            ok = false;
            app.Figure.Pointer = 'watch';
            drawnow;
            try
                action();
                ok = true;
                app.Figure.Pointer = 'arrow';
            catch err
                app.Figure.Pointer = 'arrow';
                message = sprintf('%s。\n\n理由：%s\n\n次にすること：%s', titleText, err.message, nextStep);
                uialert(app.Figure, message, titleText, 'Icon', 'error');
            end
        end
    end
end

% ================= このファイルだけで使う小さな関数 =================
function flashButtonText(button, text, seconds)
% ボタンの文字を seconds 秒だけ text にして、元に戻す（知らせの窓を出さずに、終わったことを伝える）
original = button.Text;
button.Text = text;
notice = timer('StartDelay', seconds, 'ExecutionMode', 'singleShot', ...
    'TimerFcn', @(~, ~) restoreButtonText(button, original), 'StopFcn', @(timerObject, ~) delete(timerObject));
start(notice);
end

function restoreButtonText(button, text)
if isvalid(button)
    button.Text = text;
end
end

function joined = joinImages(images, gap)
% 画像（高さ × 幅 × 3）を横に並べて1枚にする。高さは一番高い画像に合わせ、足りない所と間は1枚目の左上の色で埋める
height = max(cellfun(@(image) size(image, 1), images));
background = images{1}(1, 1, :);
parts = cell(1, 0);
for k = 1:numel(images)
    image = images{k};
    if size(image, 3) == 1
        image = repmat(image, 1, 1, 3);
    end
    parts{end + 1} = [image; repmat(background, height - size(image, 1), size(image, 2))]; %#ok<AGROW>
    if k < numel(images)
        parts{end + 1} = repmat(background, height, gap); %#ok<AGROW>
    end
end
joined = [parts{:}];
end

function overrides = validLegendOverrides(saved, choices)
% 保存してあった図ごとの凡例の位置のうち、使えるものだけ（名前・位置が正しいもの）
overrides = struct();
if ~isstruct(saved) || ~isscalar(saved)
    return
end
for name = reshape(string(fieldnames(saved)), 1, [])
    value = saved.(name);
    if (ischar(value) || isstring(value)) && isscalar(string(value)) && any(string(value) == choices)
        overrides.(name) = string(value);
    end
end
end
