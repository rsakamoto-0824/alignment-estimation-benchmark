classdef (Abstract) Core < handle
    %CORE 面内推定評価ツールの画面の共通部分：プロパティ・定数、起動の手順（startApp）、閉じるときの後始末、タブをまたいで使う処理（図の画像の保存・コピー、知らせの窓など）。
    %   AlignmentEstimationApp（画面の本体）の一部。画面の部品は Controls、データ・結果は Core のプロパティに持つ。
    %   タブごとのクラス（DataTab など）はこのクラスを受け継ぎ、AlignmentEstimationApp がすべてをまとめる。
    %   ほかのタブの関数も同じように呼べる（どれも AlignmentEstimationApp の関数になる）。

    properties (Constant, Access = {?appui.Core})
        APP_TITLE = "面内推定評価ツール"
        PREF_GROUP = "AlignmentEstimationApp"   % 表示の設定（画面の色・文字の大きさ・凡例の位置）を次に開いたときも使うための保存先（getpref）
        FONT_SIZE = 16                  % 画面の文字の標準の大きさ。下の文字の大きさ・決まった幅 [px] は、この大きさのときの値
        FONT_SIZE_CHOICES = [12, 14, 16, 18, 20]   % 「設定」→「文字の大きさ」の選択肢 [pt]
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
        RESIZE_SETTLE_SECONDS = 0.5        % 窓の大きさがこの間変わらなければ、変え終えたとみなして図を描き直す [秒]
        CORRECTION_VARIANCE_NOTE = ['「計算する」で、「実測値と推定値の補正」の手法・学習パターン・Wafer の補正前の値と補正した残差を' ...
            '求め、ばらつきを Lot 間・Wafer 間・Shot 間・その他に分けて並べます（Wafer が複数のとき、補正で Wafer 間の' ...
            'ばらつきがどう変わるかが分かります）。']
        RESIZE_CHARTS = ["preview", "layout", "overlay", "variance", "map", "target", "highOrder"]   % 窓の大きさを変えたあと描き直す図
        LAZY_TABS = ["results", "target", "highOrder", "markLayout", "rotation"]   % 初めて開いたときに中身を作るタブ（ensureTab。
                                        % "results" は「3. 結果一覧」と「4. Waferごとのマップ」。部品が多いと起動・文字の大きさ・
                                        % 画面の色の切り替えがどれも遅くなるので、開くまで作らない）
        MIN_CONTENT_SIZE = [1200, 700]     % 窓がこれより小さいときは、中身をこの大きさに保ってスクロールで見る（欄が詰まって崩れないように）
        PRIMARY_COLOR = [0.0, 0.36, 0.67]
        ESTIMATION_TAB_COLOR = [0.0, 0.36, 0.67]   % 業務でつながるタブの見出しの文字の色：2〜5（面内推定の設定・結果一覧・
        CORRECTION_TAB_COLOR = [0.72, 0.36, 0.0]   % マップ・未知の座標）は青、6・7（Shot 高次補正・Mark 配置）は橙
        ROTATION_SPREAD_COLOR = [0.0, 0.48, 0.45]   % 「8. 計測Mapローテ」の「ばらつきを求める」の色（青緑）
        ROTATION_MAP_COLOR = [0.0, 0.36, 0.67]      % 同じく「計測マップを作る」の色（青）
        TARGET_COMPARE_TABLE_HEIGHT = 160   % 「5. 未知の座標の推定」の補正の比較の表の高さ [px]（補正 4 行が見える）
        VARIANCE_LEGEND_WIDTH = 150     % ばらつき分解の図の右の、凡例だけの列の幅 [px]（4つの図の大きさをそろえる）
        ARROW_COLORS = [0.0, 0.33, 0.62; 0.0, 0.33, 0.62; 0.75, 0.25, 0.10]  % 楕円と重ねるときの矢印（計測値・推定値・残差）
        NONE_LABEL = "（なし）"
        MAX_CURVES = 8
        METHOD_COLUMN_WIDTH = 440        % 結果の表の手法の列の幅 [px]（最も長い名前が収まる幅）
        APPLY_BUTTON_WIDTH = 320         % 「1. データ読込」の「③ この対応で読み込む」の幅 [px]
        FILL_TABLE_MAX_GROUPS = 6        % 結果の表の列（学習パターン）がこの数以下なら、手法の列を広げて表を画面の幅いっぱいにする
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
        MAX_COUNT_LIST = 100            % 学習 Shot 数・計測する Mark の数の並びの上限（alignest.shotCountList と同じ）
        HIGH_ORDER_WAFER_LIST_HEIGHT = 48   % 「6. Shot高次補正」の Wafer の一覧の高さ [px]（以前の約 1/4。2行ほど見える）
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
        TARGET_LIST_HEIGHT = 72         % 「5. 未知の座標の推定」の Wafer・学習データの一覧の高さ [px]（3行ほど見える）
        TARGET_MESSAGE_HEIGHT = 76      % 同じく、メッセージの欄の高さ [px]（長いときは欄の中でスクロール）
        TARGET_COLUMNS = {'名前', 'Xmm', 'Ymm', 'markXmm', 'markYmm', 'markNo', 'shotNo', 'Direction'}  % 推定する点の表の列
        TARGET_COLUMN_WIDTHS = {76, 62, 62, 86, 86, 70, 66, 84}   % その表の列の幅 [px]（見出しが切れない幅）
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
        RunLog = strings(0, 1)  % 評価の記録（データの確認・学習パターン・推定できなかった組み合わせなど。「記録を見る…」）
        LogWindow = []          % 記録を見る窓
        Distribution = []       % 「分布の比較」で最後に比べた結果（alignest.distributionComparison）
        ImportedEstimates = []  % Excel から読み込んだ推定値（alignest.importEstimates。読み込んだ評価結果と組で使う）
        DefaultsSource = ""     % 初期設定に重ねた既定の設定ファイル（alignest.siteDefaults。無ければ ""）
        BaseResults = []        % 絞り込む前の評価の結果（Results は絞り込みの条件で指標を計算し直したもの）
        ResultFilter            % 評価点の絞り込みの条件（alignest.defaultPointFilter と同じ形）
        MapConditions = struct("option", {}, "plan", {}, "method", {}, "label", {})  % マップで並べて比べる条件
        Timing = []             % 「処理時間の内訳」で最後に測った結果（alignest.timingBreakdown）
        Theme = "light"         % 画面の色：light（ライトモード）・dark（ダークモード）。setTheme で変える
        TargetRun = []          % 「5. 未知の座標の推定」で最後に推定した結果（estimateTargets）
        Interactions = []       % 「質的変数の交互作用」で最後に調べた結果（alignest.factorInteractions）
        ScreenTimer = []        % 窓が別の画面（モニター）に移ったかを調べるタイマー（画面を出すときだけ）
        ResizeTimer = []        % 窓の大きさを変え終えたかを待つタイマー（画面を出すときだけ。scheduleChartRefresh）
        ResizedCharts = strings(1, 0)  % まだ描き直していない図（RESIZE_CHARTS の名前。開いたときに描き直す）：窓の大きさを変えたあとの図と、
                                       % 画面を出しているときにデータを読み込んだ直後の、見えていない「1. データ読込」の図
        BuiltTabs = strings(1, 0)      % 中身を作った LAZY_TABS のタブ（ensureTab）
        TableListeners = event.listener.empty   % 表の中身が変わったことを知る見張り（ダークモードで空の表をしまう。watchTables）
        ThemeHiddenTables = gobjects(1, 0)      % ダークモードで中身が空なのでしまった表（中身が入るか、ライトモードで戻す）
        Edition = "pro"                % 版："pro"（Pro 版。すべての設定）・"standard"（通常版。RT モデル・計測点の選び方・
                                       % Overlay の式・表示・指標を絞る。alignest.editionSettings）
        CurrentMonitor = 0      % 窓の中心がある画面の番号（get(groot, 'MonitorPositions') の行）
        ResponsiveColumns = struct("grid", {}, "column", {}, "width", {})  % 窓の幅に合わせて狭める欄（registerResponsiveColumn）
        TargetSelection = zeros(0, 1)  % 推定する点の表で選んでいる行（「選んだ行を削除」で使う）
        FontSize = 16           % 画面の文字の大きさ [pt]。setFontSize で変える（FONT_SIZE との比を図・表・決まった幅の欄にも掛ける）
        LegendLocation = "auto" % すべての図の凡例の位置（LEGEND_CHOICES の1つ）。setLegendLocation で変える
        LegendOverrides = struct()  % 図ごとに選んだ凡例の位置（名前は図の Controls の名前。setLegendLocation の第3引数）
        LegendMenus = struct()      % 図を右クリックしたときの凡例の位置のメニュー（図ごとに1つ）
        FixedSizes = struct("grid", {}, "property", {}, "index", {}, "size", {})  % 文字の大きさに合わせる決まった大きさ [px] の行・列
        FontVersion = 0         % 文字の大きさを変えた回数（見えていなかったタブを開いたときに、文字を付け直すかの目印）
        HighOrderFile = []      % 「6. Shot高次補正」で読み込んだ Excel・CSV（raw：読んだ表、info：alignest.readHighOrderFile、
                                %  data：選んだ列で整理した Wafer ごとのデータ（alignest.prepareHighOrderData。まだなら []）、mapping）
        HighOrderRun = []       % 「6. Shot高次補正」で最後に計算した結果（computeHighOrder。alignest.shotHighOrder の結果と入力）
        HighOrderSweep = []     % 「6. Shot高次補正」の λ・c のスイープの結果（sweepHighOrderParameters。alignest.sweepHighOrder の
                                %  結果と、スイープしたときの入力・設定）
        HighOrderCheck = []     % 「6. Shot高次補正」の計算の前の確かめ（今の設定・入力で点が足りない k の組。alignest.shotHighOrder の
                                %  checkOnly。入力が無ければ []）
        HighOrderConditions = struct("label", {}, "highOrder", {})  % 「6. Shot高次補正」の補正の比較の条件（名前と settings.highOrder）
        HighOrderConditionSelection = zeros(1, 0)  % 「補正の比較」の条件の表で選んでいる行
        HighOrderComparison = []  % 「6. Shot高次補正」の補正の比較の結果（compareHighOrderConditionsNow。表・条件ごとの結果と、比べた条件・入力）
        HighOrderHistory = struct("number", {}, "time", {}, "description", {}, "nWafers", {}, "summary", {}, "settings", {}, ...
            "points", {}, "options", {}, "wafers", {}, "source", {})
                                % 「6. Shot高次補正」の結果の履歴（計算するたびに足す。番号・時刻・説明・Wafer の数・すべての Wafer の評価・設定と、
                                %  「2つの条件を並べる」に使う点の残差（必要な列だけ）・計算の設定・Wafer（名前と Shot の配置）・入力のデータの種類）
        HighOrderHistorySelection = zeros(1, 0)  % 「結果の履歴」の表で選んでいる行
        HighOrderTransfer = []  % 「6. Shot高次補正」の「他の Wafer の補正」の結果（alignest.transferHighOrder）
        HighOrderTermSelection = []  % 「6. Shot高次補正」の「k の選定」の結果（alignest.highOrderTermSelection）
        EstimatedCorrection = []     % 「3. 結果一覧」の「実測値と推定値の補正」の結果（alignest.estimatedCorrectionComparison）
        DataVariance = []            % 「1. データ読込」の「ばらつき分解」の結果（alignest.dataVarianceDecomposition）
        CorrectionVariance = []      % 「3. 結果一覧」の「補正残差のばらつき分解」の結果（alignest.correctionVarianceDecomposition）
        RotationWafers = []          % 「8. 計測Mapローテ」の入力の Wafer（label・points・lot・dateTime・operation・eqpId）
        RotationVariability = []     % 「8.」の Shot・Mark ごとのばらつき（alignest.markVariability）
        RotationMaps = []            % 「8.」の計測マップ（alignest.rotationMaps）
        RotationRun = []             % 「8.」の直近の FB の検証（alignest.feedbackSimulation）
        RotationAssignmentComparison = []   % 「8.」の振り分けの比較（alignest.compareRotationAssignments）
        RotationHistory = []         % 「8.」の検証の結果の履歴（条件の比較）
        RotationHistorySelection = zeros(1, 0)   % 「8.」の条件の比較で選んでいる履歴の番号
        RotationFile = []            % 「8.」で読み込んだ Excel・CSV（raw・info：alignest.readHighOrderFile、data：選んだ列で整理した
                                     %  Wafer ごとのデータ（alignest.prepareHighOrderData。まだなら []）、mapping・directionRule）
        WaferRanking = []       % 「3. 結果一覧」の「Waferベスト/ワースト」の結果（alignest.waferRanking。結果が変わると求め直す）
        MeasureRangeStart = []  % 「2. 面内推定の設定」の計測マップで「範囲で選ぶ」の1点目（Wafer・図の種類・角の座標・図・印。無ければ []）
        MeasurementCandidates = []  % 「3. 結果一覧」の「計測を足す場所」で最後に出した候補（alignest.measurementCandidates の表と条件）
        MarkLayoutFile = []     % 「7. Mark配置最適化」で読み込んだ Excel・CSV（raw・info：alignest.readHighOrderFile、mapping、
                                %  wafers・coordinates・dataInfo：選んだ列で整理した入力（alignest.markLayoutFileData。まだなら dataInfo は []））
        MarkLayoutInput = []    % 「7. Mark配置最適化」の今の入力の候補の Mark と Shot ごとの値（alignest.markCandidates。入力が無ければ []）
        MarkLayoutStudy = []    % 「7. Mark配置最適化」で最後に計算した結果（alignest.markLayoutStudy と、計算したときの入力・設定）
        MarkLayoutSelection = zeros(0, 1)  % 「候補の Mark」の表で選んでいる行（「選んだ行を消す」で使う）
        MarkLayoutShapes = []   % 「乱数で Shot を生成する」で作った形（shapes：alignest.randomShotShapes、key：作ったときの条件）
        HelpWindow = []         % ヘルプの窓（メニュー「ヘルプ」で開く。閉じていれば []）
        MarkLayoutValuesAuto = false       % 座標だけの入力のため「評価に使う値」を自動で乱数にした（値のある入力で実測値に戻す）
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
            for watcher = {app.ScreenTimer, app.ResizeTimer}
                if ~isempty(watcher{1}) && isvalid(watcher{1})
                    stop(watcher{1});
                    delete(watcher{1});
                end
            end
            if ~isempty(app.HelpWindow) && isvalid(app.HelpWindow)
                delete(app.HelpWindow);
            end
            if ~isempty(app.LogWindow) && isvalid(app.LogWindow)
                delete(app.LogWindow);
            end
            if ~isempty(app.Figure) && isvalid(app.Figure)
                delete(app.Figure);
            end
        end

        function openTab(app, name)
            %OPENTAB タブ name（app.Tabs の名前："data"・"settings"・"results"・"map"・"target"・"highOrder"・"markLayout"・
            %   "rotation"）を開く（タブをクリックしたときと同じ。まだ作っていないタブは作る）。
            tab = app.Tabs.(name);
            app.TabGroup.SelectedTab = tab;
            onTabChanged(app, struct("NewValue", tab));
        end

        function refreshChartsAfterResize(app)
            %REFRESHCHARTSAFTERRESIZE 窓の大きさを変え終えたときの処理（タイマーから呼ぶ。動作確認でも呼べる）：
            %   欄の幅を最後の大きさに合わせ直し、Wafer マップなどの図（RESIZE_CHARTS）を描き直す。今見えている図は
            %   すぐに、見えていない図はそのタブを開いたときに描き直す（見えていない図は大きさが決まらないため）。
            applyResponsiveLayout(app);
            app.ResizedCharts = app.RESIZE_CHARTS;
            redrawShownResizedCharts(app);
        end
    end

    methods (Access = {?appui.Core})
        function startApp(app, visible, lazyTabs, edition)
            %STARTAPP 画面を作って開く（AlignmentEstimationApp のコンストラクターから呼ぶ）。visible = false なら
            %   画面を出さずに作る（自動テスト用）。lazyTabs = true なら、LAZY_TABS のタブは初めて開いたとき（またはその
            %   タブの操作を呼んだとき）に作る（ensureTab）。false なら起動のときにすべて作る。edition："pro"・"standard"
            %   （通常版。alignest.editionSettings）。
            % 初期設定：管理者が今のフォルダに既定の設定ファイルを置いていれば、それを重ねる（alignest.siteDefaults）。
            % 読めないときは初期設定で開き、画面を作った後に理由を出す（起動できなくならないように）
            app.Edition = edition;
            defaultsError = "";
            try
                [app.Settings, app.DefaultsSource] = alignest.siteDefaults();
            catch err
                app.Settings = alignest.defaultSettings();
                defaultsError = string(err.message);
            end
            app.Settings = alignest.editionSettings(app.Settings, app.Edition);   % 通常版で使えない既定の設定は直す
            app.ResultFilter = alignest.defaultPointFilter();
            app.MapCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
            app.Figure = uifigure('Name', app.APP_TITLE + ternary(isPro(app), "", "（通常版）"), 'Position', figurePosition(app), ...
                'Visible', matlab.lang.OnOffSwitchState(visible), 'CloseRequestFcn', @(~, ~) delete(app));
            root = uigridlayout(app.Figure, [1, 1], 'Padding', 8, 'Scrollable', 'on');
            app.RootGrid = root;
            app.TabGroup = uitabgroup(root);
            app.Tabs.data = uitab(app.TabGroup, 'Title', '1. データ読込');
            app.Tabs.settings = uitab(app.TabGroup, 'Title', '2. 面内推定の設定');
            app.Tabs.run = app.Tabs.settings;   % 評価の実行と計測マップも同じタブ（以前の「2. 面内推定の設定」）
            app.Tabs.results = uitab(app.TabGroup, 'Title', '3. 結果一覧');
            app.Tabs.map = uitab(app.TabGroup, 'Title', '4. Waferごとのマップ');
            app.Tabs.target = uitab(app.TabGroup, 'Title', '5. 未知の座標の推定');
            app.Tabs.highOrder = uitab(app.TabGroup, 'Title', '6. Shot高次補正');
            app.Tabs.markLayout = uitab(app.TabGroup, 'Title', '7. Mark配置最適化');
            app.Tabs.rotation = uitab(app.TabGroup, 'Title', '8. 計測Mapローテ');
            app.TabGroup.SelectionChangedFcn = @(~, event) app.onTabChanged(event);
            % 業務でつながるタブを見出しの文字の色で分ける（タブの見出しの地はどちらの画面の色でも明るい）
            set([app.Tabs.settings, app.Tabs.results, app.Tabs.map, app.Tabs.target], 'ForegroundColor', ...
                app.ESTIMATION_TAB_COLOR);
            set([app.Tabs.highOrder, app.Tabs.markLayout], 'ForegroundColor', app.CORRECTION_TAB_COLOR);
            buildDataTab(app);
            buildSettingsTab(app);
            buildRunTab(app);   % 「3. 結果一覧」から後のタブは ensureTab で作る（下の lazyTabs）
            % 設定のメニュー：ライトモード・ダークモードの切り替え、文字の大きさ、凡例の位置、Scan 方向の向きと色、乱数の種
            viewMenu = uimenu(app.Figure, 'Text', '設定');
            app.Controls.settingsMenu = viewMenu;
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
            app.Controls.legendMenu = legendMenu;
            app.Controls.legendItems = gobjects(1, 0);
            for k = 1:numel(app.LEGEND_CHOICES)
                choice = app.LEGEND_CHOICES(k);
                app.Controls.legendItems(end + 1) = uimenu(legendMenu, 'Text', app.LEGEND_LABELS(k), 'UserData', choice, ...
                    'Checked', onOff(choice == app.LegendLocation), 'MenuSelectedFcn', @(~, ~) app.setLegendLocation(choice));
            end
            uimenu(legendMenu, 'Text', '図ごとに選んだ位置をすべて戻す', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~, ~) app.resetLegendOverrides());
            uimenu(legendMenu, 'Text', '（図を右クリックすると、その図だけの位置を選べます）', 'Enable', 'off');
            if ~isPro(app)
                % 通常版：ダークモードと凡例の位置の変更は Pro 版だけ（メニューに出さない）
                set([app.Controls.themeLight, app.Controls.themeDark, legendMenu], 'Visible', 'off');
                fontMenu.Separator = 'off';
            end
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
            % 乱数の種（計測点の選び方と Mark 配置の最適化で共通。設定 sampling.seed。結果が変わる設定）
            app.Controls.randomSeedItem = uimenu(viewMenu, 'Text', '乱数の種…', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~, ~) app.onPickRandomSeed());
            % ヘルプは「設定」の右隣のメニューから別の窓で開く（機能編・技術編）
            app.Controls.helpMenu = uimenu(app.Figure, 'Text', 'ヘルプ', 'MenuSelectedFcn', @(~, ~) app.openHelp());
            prepareFonts(app, app.Figure);
            watchTables(app, app.Figure);   % ダークモードで空の表が白く浮かないように（Display.watchTables）
            settingsToControls(app);
            refreshRunSummary(app);
            if app.DefaultsSource ~= ""
                app.RunLog = "既定の設定ファイルを読み込みました（初期設定に使います）：" + app.DefaultsSource;
                app.Controls.runStatus.Text = char(app.RunLog);
            elseif defaultsError ~= ""
                app.RunLog = "⚠ " + defaultsError + " アプリの初期設定で開きました。";
                app.Controls.runStatus.Text = char(app.RunLog);
                if visible
                    uialert(app.Figure, char(defaultsError + " アプリの初期設定で開きました。"), '既定の設定ファイル', ...
                        'Icon', 'warning');
                end
            end
            if visible
                % 前回選んだ表示の設定を使う（自動テストなど画面を出さないときは標準のまま）。読めない値は使わない。
                % 画面の色・凡例の位置は Pro 版だけ（通常版はライトモード・図ごとの既定の位置）
                if isPro(app) && string(loadPreference(app, 'theme', 'light')) == "dark"
                    setTheme(app, "dark");
                end
                savedSize = loadPreference(app, 'fontSize', app.FONT_SIZE);
                if isnumeric(savedSize) && isscalar(savedSize) && savedSize ~= app.FONT_SIZE && ...
                        savedSize >= app.FONT_SIZE_LIMITS(1) && savedSize <= app.FONT_SIZE_LIMITS(2)
                    setFontSize(app, savedSize);
                end
                savedLocation = string(loadPreference(app, 'legendLocation', 'auto'));
                if isPro(app) && isscalar(savedLocation) && any(savedLocation == app.LEGEND_CHOICES)
                    app.LegendLocation = savedLocation;
                end
                if isPro(app)
                    app.LegendOverrides = validLegendOverrides(loadPreference(app, 'legendOverrides', struct()), ...
                        app.LEGEND_CHOICES);
                end
                markLegendItems(app);
                % 「6. Shot高次補正」で保存した項の組み合わせ（同じ名前なら、既定の設定ファイルより前回保存したものを使う）
                savedSets = loadPreference(app, 'highOrderTermSets', {});
                if iscellstr(savedSets) || isstring(savedSets)
                    app.Settings.highOrder.termSets = mergeTermSets(savedSets, app.Settings.highOrder.termSets);
                    refreshHighOrderTermSets(app);
                end
            end
            if ~lazyTabs
                for name = app.LAZY_TABS
                    ensureTab(app, name);
                end
            end
            % 画面（モニター）の大きさ・解像度に合わせる：窓の幅に合わせて決まった幅の欄を狭め、別の画面に移したら
            % 窓をその画面に収まる大きさにする（画面の大きさが違う画面の間で動かしても、つり合いが崩れないように）
            app.Figure.AutoResizeChildren = 'off';   % 中は uigridlayout が合わせる（on のままだと SizeChangedFcn が動かない）
            app.Figure.SizeChangedFcn = @(~, ~) app.onFigureResized();
            applyResponsiveLayout(app);
            app.CurrentMonitor = monitorIndexOf(app.Figure.Position);
            if visible
                app.ScreenTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', app.SCREEN_CHECK_SECONDS, ...
                    'BusyMode', 'drop', 'Name', 'AlignmentEstimationApp:screen', 'TimerFcn', @(~, ~) app.onScreenCheck());
                start(app.ScreenTimer);
            end
        end

        function built = ensureTab(app, name)
            %ENSURETAB タブ name（app.Tabs の名前）の中身を、まだ作っていなければ作る（LAZY_TABS のタブ。開いたとき・
            %   そのタブの操作を呼んだとき・ほかのタブからそのタブの欄を使うとき）。「4. Waferごとのマップ」は「3. 結果一覧」と
            %   一緒に作る（結果の選択肢を両方のタブに出すため）。作ったタブには、今の文字の大きさ・画面の色を合わせ、今の
            %   データ・結果を出す。built：いま作ったら true。
            name = string(name);
            if name == "map"
                name = "results";
            end
            built = false;
            if ~any(name == app.LAZY_TABS) || any(name == app.BuiltTabs) || isempty(app.Figure) || ~isvalid(app.Figure)
                return
            end
            app.BuiltTabs(end + 1) = name;   % 先に印を付ける（作る途中でこのタブの関数を呼んでも、作り直さない）
            dialog = [];
            if app.Figure.Visible == "on"
                dialog = uiprogressdlg(app.Figure, 'Title', '準備中', 'Indeterminate', 'on', ...
                    'Message', 'タブを準備しています（初めて開くときだけ）…');
            end
            cleanup = onCleanup(@() closeDialog(dialog));
            roots = app.Tabs.(name);
            if name == "results"
                roots = [roots, app.Tabs.map];
            end
            try
                switch name
                    case "results"
                        buildResultsTab(app);
                        buildMapTab(app);
                    case "target"
                        buildTargetTab(app);
                    case "highOrder"
                        buildHighOrderTab(app);
                    case "markLayout"
                        buildMarkLayoutTab(app);
                    otherwise
                        buildRotationTab(app);
                end
            catch err
                % 作りかけの部品を消し、次に開いたときに作り直せるようにする
                app.BuiltTabs(app.BuiltTabs == name) = [];
                for root = roots
                    delete(root.Children);
                end
                rethrow(err);
            end
            for root = roots
                finishBuiltTab(app, root);
            end
            % 作る前にあったデータ・結果を出す（設定・入力の選択肢は、それぞれのタブを作る関数の最後で合わせている）
            switch name
                case "results"
                    if ~isempty(app.Results)
                        refreshResultControls(app);
                    end
                case "highOrder"
                    refreshHighOrderTermSets(app);   % 前回保存した項の組み合わせ（起動のときに設定へ重ねたもの）
            end
            applyResponsiveLayout(app);
            built = true;
        end

        function yes = isPro(app)
            % Pro 版か（通常版は、比べる手法・計測点の選び方・Overlay の式を絞る。alignest.editionSettings）
            yes = app.Edition == "pro";
        end

        function yes = isTabBuilt(app, name)
            % タブ name の中身を作ってあるか（LAZY_TABS 以外のタブは起動のときに作るので、いつも true）
            name = string(name);
            if name == "map"
                name = "results";
            end
            yes = ~any(name == app.LAZY_TABS) || any(name == app.BuiltTabs);
        end

        function name = tabName(app, tab)
            % app.Tabs の部品から名前（"results" など）を引く（見つからなければ ""）
            name = "";
            for candidate = string(fieldnames(app.Tabs)).'
                if app.Tabs.(candidate) == tab
                    name = candidate;
                    return
                end
            end
        end

        % ================= 共通 =================
        function requireEstimates(app)
            % 推定値を計算し直す機能（分析・散布図・分布の比較・推定値の書き出し）を使える結果か確かめる
            if isempty(app.Results)
                error('alignest:noResults', '先に「2. 面内推定の設定」で評価してください。');
            end
            if isImportedResults(app.Results) && isempty(app.ImportedEstimates)
                error('alignest:importedResults', ['Excel から読み込んだ結果では推定値を計算できません。' ...
                    '「推定値の Excel を読み込む…」で推定値の Excel も読み込むか、計測ファイルを読み込んで' ...
                    '「2. 面内推定の設定」で評価し直してください。']);
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
            app.WaferRanking = [];
            app.MeasurementCandidates = [];
            app.Distribution = [];
            app.EstimatedCorrection = [];
            app.CorrectionVariance = [];
            c = app.Controls;
            % 「2. 面内推定の設定」の評価の知らせとボタン（結果のタブを作る前でも消す）
            c.runStatus.Text = "";
            set([c.resumeRun, c.extendRun], 'Enable', 'off', 'Visible', 'off');   % 押せないときは出さない（showRunButtons）
            if ~isTabBuilt(app, "results")
                return   % 結果のタブをまだ作っていない（作るときは空の状態で作る）
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
            c.compareLayoutInfo.Text = '';
            c.timingTable.Data = {};
            c.timingInfo.Text = '';
            c.chartAxes2.Visible = 'off';
            set([c.export, c.saveChart, c.copyChart, c.mapWafer, c.mapPlan, c.mapMethod, c.mapContent, c.mapMode, c.mapScale, ...
                c.mapMarkerSize, c.mapMarkerShape, c.mapEllipse, c.mapEllipseOnly, c.mapShotFrames, c.saveMap, c.copyMap, c.mapVariance, ...
                c.analysisMethod, ...
                c.analysisGroup, ...
                c.analysisWafer, c.analyze, ...
                c.estimateScope, c.exportEstimates, c.scatterMethod, c.scatterGroup, c.scatterWafer, c.scatterColor, ...
                c.drawScatterButton, c.distributionMethod, c.distributionGroup, c.distributionWafer, c.distributionAxis, ...
                c.compareDistributionsButton, c.mapScanFrames, c.mapRings, c.mapView, ...
                c.mapCompareValue, c.mapConditions, c.mapAddCondition, c.mapRemoveCondition, c.mapClearConditions, ...
                c.mapStackBy, c.mapStackAll, c.residualVariableMethod, c.residualVariableGroup, c.residualVariableWafer, ...
                c.residualVariableName, c.drawResidualVariableButton, c.boxFactor, c.timingWafer, c.timingPlan, c.timingMethods, c.timingRepeats, c.measureTimingButton, ...
                c.estimatedCorrectionMethods, c.estimatedCorrectionGroup, c.estimatedCorrectionWafer, c.compareEstimatedCorrectionButton, ...
                c.correctionVarianceButton, c.correctionVarianceMethodPlan, c.correctionVarianceScope, ...
                c.compareLayoutMethod, c.compareLayoutXAxis, c.compareLayoutErrorBar, ...
                c.rankingMethod, c.rankingGroup, c.rankingOverallMetrics, ...
                c.degradationXAxis, c.degradationYAxis, c.degradationErrorBar, c.degradationWafers, c.degradationMethods, ...
                c.degradationTypes, ...
                c.candidateMethod, c.candidateGroup, c.candidateWafer, c.candidateCriterion, c.candidateAxis, ...
                c.candidateStatistic, c.candidateLevel, c.candidateMode, c.candidateCount, c.candidateThreshold, ...
                c.findCandidatesButton, c.addCandidatesButton, c.addCandidateShotsButton, c.selectAllCandidatesButton, c.clearCandidatesButton, ...
                c.filterResults.apply, c.filterMap.apply], 'Enable', 'off');
            showFilter(app);
            showWaferRanking(app);
            drawOverlayDegradation(app);
            showMeasurementCandidates(app);
            c.estimatedCorrectionTable.Data = table();
            showVarianceDecomposition(app, [], "correction");
            c.correctionVarianceInfo.Text = app.CORRECTION_VARIANCE_NOTE;
            c.distributionTable.Data = {};
            c.jsTable.Data = {};
            for ax = [c.distributionAxes, c.residualVariableAxes]
                cla(ax, 'reset');
                legend(ax, 'off');
                ax.Visible = 'off';
            end
            c.residualVariableTable.Data = {};
            c.mapInfo.Text = "「2. 面内推定の設定」で評価すると、ここに Wafer ごとの図が出ます。";
            c.resultSource.Text = '';
            c.resultControls.RowHeight{3} = 0;
            c.importEstimates.Enable = 'off';
            c.analysisNote.Text = '';
        end

        function showResultTab(app, tab)
            % 結果一覧の中のタブ tab を開く（まとまりのタブ・中のタブの両方を選ぶ）
            group = tab.Parent;
            group.SelectedTab = tab;
            app.Controls.resultTabs.SelectedTab = ancestor(group, 'uitab');
        end

        function onResultCategoryChanged(app)
            % 結果一覧のまとまりを変えたとき：そのまとまりで選んであるタブを開いたときと同じく、図を描き直す
            category = app.Controls.resultTabs.SelectedTab;
            group = findobj(category, 'Type', 'uitabgroup', '-depth', 2);
            if ~isempty(group)
                onResultTabChanged(app, struct("NewValue", group(1).SelectedTab));
            end
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
            % 変わったときだけ入れる（窓をドラッグしている間に、同じ値で中身の配置を何度もやり直さないように）
            if ~isequal(app.RootGrid.ColumnWidth, sizes{1}) || ~isequal(app.RootGrid.RowHeight, sizes{2})
                set(app.RootGrid, 'ColumnWidth', sizes{1}, 'RowHeight', sizes{2});
            end
            scale = min(1, contentSize(1) / app.FIGURE_SIZE(1)) * app.FontScale;
            for item = app.ResponsiveColumns
                if ~isvalid(item.grid)
                    continue
                end
                widths = item.grid.ColumnWidth;
                width = round(item.width * scale);
                if ~isequal(widths{item.column}, width)
                    widths{item.column} = width;
                    item.grid.ColumnWidth = widths;
                end
            end
        end

        function onFigureResized(app)
            % 窓の大きさが変わった：欄の幅を合わせ、変え終えたら図を描き直す
            applyResponsiveLayout(app);
            scheduleChartRefresh(app);
        end

        function scheduleChartRefresh(app)
            % 窓の大きさを変え終えたら（RESIZE_SETTLE_SECONDS の間変わらなければ）図を描き直す。ドラッグしている間の
            % 途中の大きさで配置した図（軸・色の目盛り・凡例）が、窓を戻しても崩れたまま残ることがあるため
            if isempty(app.Figure) || ~isvalid(app.Figure) || app.Figure.Visible == "off"
                return
            end
            if isempty(app.ResizeTimer) || ~isvalid(app.ResizeTimer)
                app.ResizeTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', app.RESIZE_SETTLE_SECONDS, ...
                    'Name', 'AlignmentEstimationApp:resize', 'TimerFcn', @(~, ~) app.onResizeSettled());
            end
            stop(app.ResizeTimer);   % まだ変えている途中：待ち直す
            start(app.ResizeTimer);
        end

        function onResizeSettled(app)
            % タイマー：窓の大きさを変え終えた
            if ~isvalid(app) || isempty(app.Figure) || ~isvalid(app.Figure)
                return
            end
            try
                refreshChartsAfterResize(app);
            catch
                % 描き直せなくても画面は使える（次に図を描くときに直る）
            end
        end

        function redrawShownResizedCharts(app)
            % 窓の大きさを変えたあと、まだ描き直していない図のうち、今見えている図を描き直す（タブを開いたときにも呼ぶ）
            if isempty(app.ResizedCharts)
                return
            end
            c = app.Controls;
            shown = strings(1, 0);
            switch app.TabGroup.SelectedTab
                case app.Tabs.data
                    subTabs = struct("preview", c.previewTab, "layout", c.layoutTab, "overlay", c.shotOverlayTab, ...
                        "variance", c.varianceTab);
                    for name = ["preview", "layout", "overlay", "variance"]
                        if c.dataTabs.SelectedTab == subTabs.(name)
                            shown = name;
                        end
                    end
                case app.Tabs.map
                    shown = "map";
                case app.Tabs.target
                    shown = "target";
                case app.Tabs.highOrder
                    shown = "highOrder";
            end
            shown = shown(ismember(shown, app.ResizedCharts));
            app.ResizedCharts = setdiff(app.ResizedCharts, shown, 'stable');
            for name = shown
                try
                    redrawChart(app, name);
                catch
                    % 描けない状態の図（データ・結果が無い）はそのまま
                end
            end
        end

        function redrawChart(app, name)
            % 図を今の選択で描き直す（name は RESIZE_CHARTS の名前。描くものが無ければ何もしない）
            switch name
                case "preview"
                    if ~isempty(app.Data)
                        drawPreview(app);
                    end
                case "layout"
                    if ~isempty(app.Data)
                        drawLayout(app);
                    end
                case "overlay"
                    if ~isempty(app.Data)
                        drawShotOverlay(app);
                    end
                case "variance"
                    if ~isempty(app.DataVariance)
                        showVarianceDecomposition(app, app.DataVariance, "data");
                    end
                case "map"
                    if ~isempty(app.Results)
                        drawMap(app);
                    end
                case "target"
                    if ~isempty(app.TargetRun)
                        drawTargetMap(app);
                    end
                case "highOrder"
                    if ~isempty(app.HighOrderRun)
                        drawHighOrderMap(app);
                    end
            end
        end


        function showVarianceDecomposition(app, result, target)
            % ばらつき分解の図（上：3σ の配分（全体の 3σ を ◆）か分散の積み上げ（「縦軸」の選択）、下：分散の割合。左が X、右が Y）と表を出す。
            % target："data"（「1. データ読込」の「ばらつき分解」）・"correction"（「3. 結果一覧」の「補正残差のばらつき分解」）。
            % result が空なら消す
            c = app.Controls;
            if target == "data"
                [axesList, axesGrid, table_, quantityControl, legendAxes] = deal(c.varianceAxes, c.varianceAxesGrid, ...
                    c.varianceTable, c.varianceQuantity, c.varianceLegendAxes);
            else
                [axesList, axesGrid, table_, quantityControl, legendAxes] = deal(c.correctionVarianceAxes, ...
                    c.correctionVarianceAxesGrid, c.correctionVarianceTable, c.correctionVarianceQuantity, ...
                    c.correctionVarianceLegendAxes);
            end
            cla(legendAxes, 'reset');
            legend(legendAxes, 'off');
            legendAxes.Visible = 'off';
            quantity = string(quantityControl.Value);
            % 図・表の保存とコピーのボタンは、分けた結果があるときだけ押せる
            set(c.(ternary(target == "data", "varianceOutputs", "correctionVarianceOutputs")), 'Enable', onOff(~isempty(result)));
            for ax = axesList
                cla(ax, 'reset');
                legend(ax, 'off');
            end
            if target == "data"
                % 分け方「成分」は回帰係数の図（3σ・分散の「縦軸」は使わない）。図はどちらかの格子だけを見せる
                coefficients = ~isempty(result) && result.kind == "components";
                for ax = c.coefficientAxes
                    cla(ax, 'reset');
                    legend(ax, 'off');
                end
                set(c.coefficientAxes, 'Visible', 'off');
                c.varianceChartGrid.RowHeight = ternary(coefficients, {0, '1x'}, {'1x', 0});
                quantityControl.Enable = onOff(~coefficients);
                if coefficients
                    set(axesList, 'Visible', 'off');
                    showComponentCoefficients(app, result);
                    return
                end
            end
            if isempty(result)
                set(axesList, 'Visible', 'off');
                table_.Data = table();
                return
            end
            nAxes = numel(result.axes);
            widths = axesGrid.ColumnWidth;   % 3列目は凡例だけの図（決まった幅のまま）
            widths(1:2) = [repmat({'1x'}, 1, nAxes), repmat({0}, 1, 2 - nAxes)];   % 1変数なら左の列だけ
            axesGrid.ColumnWidth = widths;
            set(axesList, 'Visible', 'off');
            labels = result.categories;
            names = labels;
            if isfield(result, "categoryNames")
                names = result.categoryNames;   % 表には長い名前
            end
            for a = 1:nAxes
                % 凡例は右の列の図にまとめて出す（X・Y の図の大きさを同じにする）
                alignest.plot.varianceBars(axesList(a), axesList(a + 2), result, result.axes(a), quantity=quantity, ...
                    unitLabel=result.unitLabel, showLegend=false, categoryLabels=labels, legendAxes=legendAxes);
            end
            styleAxes(app, axesList(ismember(1:4, [1:nAxes, 3:2 + nAxes])), app.AXES_FONT_SIZE);
            % 表：棒・軸ごとに、段の 3σ（縦軸が分散なら分散）・割合と全体
            t = result.table;
            totals = result.totals;
            totalPercent = repmat(100, height(totals), 1);
            totalPercent(~(totals.variance > 0)) = NaN;   % ばらつきが無い（点が無い）ときは割合を出さない
            totalRows = table(totals.category, totals.axis, repmat("全体", height(totals), 1), totals.variance, ...
                totals.sigma3, totals.sigma3, totalPercent, totals.n, 'VariableNames', ["category", "axis", "component", ...
                "variance", "sigma3", "sigma3Share", "percent", "n"]);
            t = t(:, ["category", "axis", "component", "variance", "sigma3", "sigma3Share", "percent", "n"]);
            rows = [t; totalRows];
            [~, categoryOrder] = ismember(rows.category, result.categories);
            [~, axisOrder] = ismember(rows.axis, result.axes);
            [~, componentOrder] = ismember(rows.component, [result.components, "全体"]);
            [~, order] = sortrows([categoryOrder, axisOrder, componentOrder]);
            rows = rows(order, :);
            [~, nameIndex] = ismember(rows.category, result.categories);
            unitText = result.unitLabel;
            front = table(reshape(names(nameIndex), [], 1), rows.axis, rows.component, 'VariableNames', ["棒", "軸", "ばらつき"]);
            if quantity == "sigma3"
                % 3σ の配分（全体の 3σ × 分散の割合。足すと全体の 3σ）と、その段・成分だけの 3σ（3√分散）
                share = rows.sigma3;   % 全体の行は全体の 3σ
                share(rows.component ~= "全体") = rows.sigma3Share(rows.component ~= "全体");
                values = table(round(share, 4), round(rows.sigma3, 4), 'VariableNames', ...
                    ["3σ の配分 [" + unitText + "]", "単独の 3σ [" + unitText + "]"]);
            else
                values = table(round(rows.variance, 4), 'VariableNames', "分散 [" + unitText + "²]");
            end
            table_.Data = [front, values, table(round(rows.percent, 1), rows.n, 'VariableNames', ["分散の割合 [%]", "点の数"])];
            removeStyle(table_);
            totalIndex = find(rows.component == "全体");
            if ~isempty(totalIndex)
                addStyle(table_, uistyle('FontWeight', 'bold'), 'row', totalIndex);
            end
        end

        function showComponentCoefficients(app, result)
            % 「1. データ読込」の「ばらつき分解」の分け方「成分」：成分ごとの図（Wafer ごとの回帰係数。横軸は表の No.、軸ごとの
            % 線）と、Wafer × 軸 の行に成分の回帰係数を並べた表（alignest.componentCoefficients）
            COEFFICIENT_DIGITS = 4;   % 表の係数の有効数字
            c = app.Controls;
            t = result.table;
            nWafers = numel(result.wafers);
            nAxes = numel(result.axes);
            nComponents = numel(result.components);
            % 単位：全体 Shift と残留（回帰残差の 3σ）は値の単位、倍率・回転は 値の単位/mm（座標は mm）
            units = repmat(result.unitLabel + "/mm", 1, nComponents);
            units(result.components == "全体 Shift" | contains(result.components, "残留")) = result.unitLabel;
            values = nan(nWafers, nComponents, nAxes);
            counts = zeros(nWafers, nAxes);
            for a = 1:nAxes
                for k = 1:nComponents
                    rows = t(t.axis == result.axes(a) & t.component == result.components(k), :);
                    values(rows.waferIndex, k, a) = rows.coefficient;
                    counts(rows.waferIndex, a) = rows.n;
                end
            end
            for k = 1:nComponents
                alignest.plot.coefficientSeries(c.coefficientAxes(k), reshape(values(:, k, :), nWafers, nAxes), result.axes, ...
                    result.components(k) + " [" + units(k) + "]", categories=result.waferCategories, ...
                    showLegend=k == nComponents);
            end
            set(c.coefficientAxes(1:nComponents), 'Visible', 'on');
            styleAxes(app, c.coefficientAxes(1:nComponents), app.AXES_FONT_SIZE);
            % 表：Wafer ごとに軸の行を並べ、列に成分の回帰係数
            [axisIndex, waferIndex] = ndgrid(1:nAxes, 1:nWafers);
            front = table(waferIndex(:), reshape(result.wafers(waferIndex(:)), [], 1), ...
                reshape(result.axes(axisIndex(:)), [], 1), 'VariableNames', ["No.", "Wafer", "軸"]);
            if isfield(result, "hasOperation") && result.hasOperation
                front = addvars(front, reshape(result.waferCategories(waferIndex(:)), [], 1), 'Before', "Wafer", ...
                    'NewVariableNames', "Operation");
            end
            columns = cell(1, nComponents);
            for k = 1:nComponents
                picked = values(sub2ind(size(values), waferIndex(:), repmat(k, numel(waferIndex), 1), axisIndex(:)));
                columns{k} = round(reshape(picked, [], 1), COEFFICIENT_DIGITS, 'significant');   % Wafer が1枚でも列にする
            end
            coefficients = table(columns{:}, 'VariableNames', result.components + " [" + units + "]");
            c.varianceTable.Data = [front, coefficients, ...
                table(reshape(counts(sub2ind(size(counts), waferIndex(:), axisIndex(:))), [], 1), 'VariableNames', "点の数")];
            removeStyle(c.varianceTable);
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
            % Shot 高次補正のヒストグラム（3段 × X・Y）：画面と同じ3段に並べ、凡例（画面では上の行の文字）は下に足す
            histogramRows = string(figureName) == "highOrderHistogram" && numel(items) == 6;
            % ばらつき分解（Lot・Wafer・Shot 間）：画面と同じ2段（上：3σ の配分か分散、下：分散の割合）に並べ、凡例だけの図を
            % 右に足す。成分は画面と同じ2段（上：Wafer の成分 4 つ、下：Shot 共通の成分 3 つ）
            legendHandles = gobjects(1, 0);   % 凡例だけの図（cla(ax, 'reset') で Tag が消えるので、部品で見分ける）
            for name = ["varianceLegendAxes", "correctionVarianceLegendAxes"]
                if isfield(app.Controls, name)
                    legendHandles(end + 1) = app.Controls.(name); %#ok<AGROW>
                end
            end
            isLegend = arrayfun(@(item) any(item == legendHandles), items);
            legendItems = items(isLegend);
            items = items(~isLegend);
            isVariance = any(string(figureName) == ["variance", "correctionVariance"]);
            componentRows = isVariance && isVarianceComponents(app, figureName) && numel(items) == 7;
            varianceRows = isVariance && ~isVarianceComponents(app, figureName) && mod(numel(items), 2) == 0;
            images = cell(1, numel(items));
            for k = 1:numel(items)
                file = [tempname, '.png'];
                exportgraphics(items(k), file, 'Resolution', app.IMAGE_RESOLUTION);
                images{k} = imread(file);
                delete(file);
            end
            if histogramRows
                rows = {joinImages(images(1:2), app.IMAGE_GAP_PIXELS), joinImages(images(3:4), app.IMAGE_GAP_PIXELS), ...
                    joinImages(images(5:6), app.IMAGE_GAP_PIXELS), legendImage(items(1), app.IMAGE_RESOLUTION)};
                pixels = stackImages(rows, app.IMAGE_GAP_PIXELS);
                return
            end
            if componentRows
                pixels = stackImages({joinImages(images(1:4), app.IMAGE_GAP_PIXELS), ...
                    joinImages(images(5:7), app.IMAGE_GAP_PIXELS)}, app.IMAGE_GAP_PIXELS);
                return
            end
            if varianceRows
                half = numel(images) / 2;
                pixels = stackImages({joinImages(images(1:half), app.IMAGE_GAP_PIXELS), ...
                    joinImages(images(half + 1:end), app.IMAGE_GAP_PIXELS)}, app.IMAGE_GAP_PIXELS);
                if ~isempty(legendItems)
                    pixels = joinImages({pixels, axesLegendImage(legendItems(1), app.IMAGE_RESOLUTION)}, ...
                        app.IMAGE_GAP_PIXELS);
                end
                return
            end
            pixels = joinImages(images, app.IMAGE_GAP_PIXELS);
        end

        function onCopyFigure(app, figureName, button)
            % 「図をコピー」のボタン：図をクリップボードにコピーし、少しの間ボタンに「コピーしました」と出す
            if figureName == "chart"
                showResultTab(app, app.Controls.chartTab);   % コピーするグラフを見せる
            end
            if runWithAlert(app, @() app.copyFigureImage(figureName), "図をコピーできませんでした", ...
                    "図を描いてから、もう一度試してください。")
                flashButtonText(button, "コピーしました", app.COPY_NOTICE_SECONDS);
            end
        end

        function items = figureItems(app, figureName)
            % 保存する図（saveFigureImage）：axes か、並べた図の tiledlayout
            owners = struct("chart", "results", "map", "results", "correctionVariance", "results", "target", "target", ...
                "targetResidual", "target", "targetCompare", "target", ...
                "highOrder", "highOrder", "highOrderPair", "highOrder", "highOrderHistogram", "highOrder", ...
                "markLayoutChart", "markLayout", "markLayoutMap", "markLayout", "markLayoutShape", "markLayout");
            if isfield(owners, figureName)
                ensureTab(app, owners.(figureName));   % まだ作っていないタブには描いた図が無い（下で知らせる）
            end
            c = app.Controls;
            switch figureName
                case "measure"
                    items = findobj(c.measurePanel.Children, 'flat', 'Type', 'tiledlayout');
                case "chart"
                    items = [c.chartAxes, c.chartAxes2];
                case "variance"
                    % ばらつき分解（1. データ読込）：Lot・Wafer・Shot 間は 2 × 2 の図、成分は回帰係数の図。「表」のタブを
                    % 見ていても書き出せるように、「図」のタブを開く（見えていない図は大きさが決まらない）
                    c.varianceViews.SelectedTab = c.varianceChartTab;
                    items = ternary(isVarianceComponents(app, figureName), c.coefficientAxes, ...
                        [c.varianceAxes, c.varianceLegendAxes]);
                case "correctionVariance"
                    c.correctionVarianceViews.SelectedTab = c.correctionVarianceChartTab;   % 補正残差のばらつき分解（3. 結果一覧）
                    items = [c.correctionVarianceAxes, c.correctionVarianceLegendAxes];
                case "map"
                    if string(c.mapView.Value) == "single"
                        items = c.mapAxes;
                        if isfield(c, 'mapVarianceAxes') && strcmp(c.mapVarianceAxes.Visible, 'on')
                            items = [items, c.mapVarianceAxes];   % 推定の分散（GPR）の図も並べてある
                        end
                    else
                        items = findobj(c.comparePanel.Children, 'flat', 'Type', 'tiledlayout');   % 並べて比べる・スタック
                    end
                case "target"
                    items = c.targetAxes;
                case "targetResidual"
                    items = c.targetResidualAxesList;   % 並べたときは3つ（使わない図は中身が無い）
                case "targetCompare"
                    items = [c.targetCompareBarAxes, c.targetCompareMapAxes];
                case "highOrder"
                    items = [c.highOrderAxes, c.highOrderAxes2, c.highOrderAxes3];   % 並べたときは3つ（使わない図は中身が無い）
                case "highOrderPair"
                    items = [c.highOrderPairAxes, c.highOrderPairAxes2];   % 基準（左）と比べる条件（右）
                case "highOrderHistogram"
                    items = c.highOrderHistogramAxes;
                case "markLayoutChart"
                    items = c.markOptChartAxes;
                case "markLayoutMap"
                    items = [c.markOptMapAxes, c.markOptStackAxes];
                case "markLayoutShape"
                    items = c.markOptShapeAxes;
                otherwise
                    error('alignest:figureName', '保存する図の名前が違います: %s', figureName);
            end
        end

        function [grid, axesList, legendAxes] = varianceAxesLayout(app, parent)
            % ばらつき分解（Lot・Wafer・Shot 間）の図の並び：2 × 2（上：3σ の配分か分散、下：分散の割合。左：X、右：Y）と、
            % 右の列に凡例だけの図（凡例を図の外に出すと、凡例のある図だけ狭くなるので、4つの図の大きさをそろえるため）
            grid = uigridlayout(parent, [2, 3], 'ColumnWidth', {'1x', '1x', app.VARIANCE_LEGEND_WIDTH}, 'Padding', 4, ...
                'RowSpacing', 6, 'ColumnSpacing', 8);
            axesList = gobjects(1, 4);
            positions = [1, 1; 1, 2; 2, 1; 2, 2];
            for k = 1:4
                axesList(k) = uiaxes(grid);
                axesList(k).Layout.Row = positions(k, 1);
                axesList(k).Layout.Column = positions(k, 2);
            end
            legendAxes = uiaxes(grid);
            legendAxes.Layout.Row = [1, 2];
            legendAxes.Layout.Column = 3;
            set([axesList, legendAxes], 'Visible', 'off');
        end

        function [grid, buttons] = varianceOutputButtons(app, parent, target)
            % ばらつき分解の図・表の保存とコピーのボタン（target："data"（1. データ読込）・"correction"（3. 結果一覧の
            % 補正残差のばらつき分解））。分けた結果があるときだけ押せる（showVarianceDecomposition）
            figureName = ternary(target == "data", "variance", "correctionVariance");
            fileName = ternary(target == "data", "ばらつき分解", "補正残差のばらつき分解");
            grid = uigridlayout(parent, [1, 4], 'ColumnWidth', {'fit', 'fit', 'fit', 'fit'}, 'Padding', 0, ...
                'ColumnSpacing', 6);
            buttons = [ ...
                uibutton(grid, 'Text', '図を保存…', 'Tooltip', '図（凡例・色の目盛りも入れる）を PNG 画像で保存します。', ...
                'ButtonPushedFcn', @(~, ~) app.saveFigureWithDialog(figureName, fileName + ".png")), ...
                uibutton(grid, 'Text', '図をコピー', 'Tooltip', app.COPY_TOOLTIP, ...
                'ButtonPushedFcn', @(source, ~) app.onCopyFigure(figureName, source)), ...
                uibutton(grid, 'Text', '表を保存…', 'Tooltip', '表を Excel（.xlsx）か CSV（.csv）に保存します。', ...
                'ButtonPushedFcn', @(~, ~) app.onSaveVarianceTable(target, fileName)), ...
                uibutton(grid, 'Text', '表をコピー', 'Tooltip', ['Excel・PowerPoint の表に、そのまま貼り付けられる形で' ...
                'コピーします（1行目が列名）。'], 'ButtonPushedFcn', @(source, ~) app.onCopyVarianceTable(target, source))];
            set(buttons, 'Enable', 'off');
        end

        function onSaveVarianceTable(app, target, fileName)
            % 「表を保存…」：保存先を選んで exportVarianceTable で書き出す
            [chosen, folder] = uiputfile({'*.xlsx', 'Excel (*.xlsx)'; '*.csv', 'CSV（UTF-8） (*.csv)'}, '表を保存', ...
                fileName + ".xlsx");
            figure(app.Figure);
            if isequal(chosen, 0)
                return
            end
            target_ = fullfile(folder, chosen);
            if runWithAlert(app, @() app.exportVarianceTable(target, target_), "表を保存できませんでした", ...
                    "保存先のフォルダを変えるか、同じ名前のファイルを Excel で開いていれば閉じてください。")
                uialert(app.Figure, sprintf('保存しました：%s', target_), '保存しました', 'Icon', 'success');
            end
        end

        function onCopyVarianceTable(app, target, button)
            % 「表をコピー」：表をクリップボードにコピーし、少しの間ボタンに「コピーしました」と出す
            if runWithAlert(app, @() app.copyVarianceTable(target), "表をコピーできませんでした", ...
                    "先にばらつきを分けてから、もう一度試してください。")
                flashButtonText(button, "コピーしました", app.COPY_NOTICE_SECONDS);
            end
        end

        function [data, info] = varianceTableData(app, target)
            % ばらつき分解の表（画面の表と同じ）と、図の下の説明の文。表が無ければエラー
            switch string(target)
                case "data"
                    [table_, infoLabel] = deal(app.Controls.varianceTable, app.Controls.varianceInfo);
                case "correction"
                    ensureTab(app, "results");
                    [table_, infoLabel] = deal(app.Controls.correctionVarianceTable, app.Controls.correctionVarianceInfo);
                otherwise
                    error('alignest:varianceTarget', 'ばらつき分解の場所は "data" か "correction" です: %s', target);
            end
            data = table_.Data;
            if ~istable(data) || height(data) == 0
                error('alignest:noVarianceTable', '表がありません。先にばらつきを分けてください。');
            end
            info = string(infoLabel.Text);
        end

        function yes = isVarianceComponents(app, figureName)
            % ばらつき分解の図が、分け方「成分」（回帰係数）で描いてあるか（補正残差のばらつき分解は、いつも Lot・Wafer・Shot 間）
            yes = string(figureName) == "variance" && ~isempty(app.DataVariance) && isfield(app.DataVariance, "kind") && ...
                app.DataVariance.kind == "components";
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

function pixels = legendImage(ax, resolution)
% 図 ax の凡例だけの画像（同じ色・線種の線と名前。見えない図に描いて書き出す）。ヒストグラムを画像にするときに使う
LEGEND_COLUMNS = 3;
LEGEND_FONT_SIZE = 12;
helper = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0, 0, 1000, 200]);
cleanup = onCleanup(@() delete(helper));
target = axes(helper, 'Visible', 'off');
hold(target, 'on');
items = flipud(findobj(ax, 'Type', 'histogram'));
for k = 1:numel(items)
    plot(target, NaN, NaN, 'Color', items(k).EdgeColor, 'LineStyle', items(k).LineStyle, 'LineWidth', 2, ...
        'DisplayName', items(k).DisplayName);
end
legend(target, 'Location', 'north', 'Orientation', 'horizontal', 'Box', 'off', ...
    'NumColumns', min(LEGEND_COLUMNS, max(numel(items), 1)), 'FontSize', LEGEND_FONT_SIZE, 'Interpreter', 'none');
file = [tempname, '.png'];
exportgraphics(helper, file, 'Resolution', resolution);
pixels = imread(file);
delete(file);
end

function pixels = axesLegendImage(ax, resolution)
% 凡例だけの図 ax（ばらつき分解の右の列）の凡例の画像：凡例の項目（色の四角・印）を見えない図に描き直して書き出す
LEGEND_FONT_SIZE = 12;
helper = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0, 0, 260, 320]);
cleanup = onCleanup(@() delete(helper));
target = axes(helper, 'Visible', 'off');
hold(target, 'on');
items = gobjects(1, 0);
for source = reshape(ax.Legend.PlotChildren, 1, [])
    if isa(source, 'matlab.graphics.primitive.Patch')
        items(end + 1) = patch(target, NaN, NaN, source.FaceColor, 'EdgeColor', 'none', ...
            'DisplayName', source.DisplayName); %#ok<AGROW>
    else
        items(end + 1) = plot(target, NaN, NaN, 'LineStyle', 'none', 'Marker', source.Marker, ...
            'MarkerSize', source.MarkerSize, 'MarkerFaceColor', source.MarkerFaceColor, ...
            'MarkerEdgeColor', source.MarkerEdgeColor, 'DisplayName', source.DisplayName); %#ok<AGROW>
    end
end
legend(target, items, 'Location', 'west', 'Box', 'off', 'FontSize', LEGEND_FONT_SIZE, 'Interpreter', 'none', ...
    'TextColor', [0, 0, 0]);
file = [tempname, '.png'];
exportgraphics(helper, file, 'Resolution', resolution);
pixels = imread(file);
delete(file);
end

function stacked = stackImages(rows, gap)
% 画像を縦に並べて1枚にする（行と列を入れ替えて横に並べ、元に戻す）
turned = cellfun(@(image) permute(image, [2, 1, 3]), rows, 'UniformOutput', false);
stacked = permute(joinImages(turned, gap), [2, 1, 3]);
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
