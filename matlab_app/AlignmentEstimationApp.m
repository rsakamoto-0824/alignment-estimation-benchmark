classdef AlignmentEstimationApp < handle
    %ALIGNMENTESTIMATIONAPP アライメント計測値の面内推定を、実データ（Excel）で比べる画面。
    %   app = AlignmentEstimationApp();       画面を開く
    %   app = AlignmentEstimationApp(false);  画面を出さずに作る（自動テスト用）
    %   流れ：1. データの読み込み（列の対応・座標の単位・Wafer マップ・Shot レイアウト） → 2. 評価の設定 → 3. 実行
    %         （評価の後に条件を足して追加の評価もできる）→ 4. 結果一覧（表・グラフ・基準の手法との比較・推定値と誤差の
    %         分布・残差の箱ひげ図・散布図・分布の比較・処理時間の内訳。評価点を半径・Shot の条件で絞り込んで計算し直せる）
    %         → 5. Waferごとのマップ（1つの条件の計測値・推定値・残差、または複数の条件を並べて比べる）
    %   計算は +alignest パッケージ（MATLAB 本体だけで動く）。画面はその呼び出しと表示だけを受け持つ。

    properties (Constant, Access = private)
        APP_TITLE = "アライメント計測値の面内推定 検証ツール"
        PREF_GROUP = "AlignmentEstimationApp"   % 画面の色（ライト・ダーク）を次に開いたときも使うための保存先（getpref）
        FONT_SIZE = 16
        AXES_FONT_SIZE = 13
        SMALL_AXES_FONT_SIZE = 10       % 図を並べるとき（計測マップ・マップの比較）の文字の大きさ
        FIGURE_SIZE = [1440, 900]          % 画面がこれより小さいときは画面に合わせて縮める
        SCREEN_MARGIN = 40
        PRIMARY_COLOR = [0.0, 0.36, 0.67]
        ARROW_COLORS = [0.0, 0.33, 0.62; 0.0, 0.33, 0.62; 0.75, 0.25, 0.10]  % 楕円と重ねるときの矢印（計測値・推定値・残差）
        NONE_LABEL = "（なし）"
        MAX_CURVES = 8
        METHOD_COLUMN_WIDTH = 440        % 結果の表の手法の列の幅 [px]（最も長い名前が収まる幅）
        VALUE_COLUMN_WIDTH = 90          % 結果の表の数値の列の幅 [px]
        PROGRESS_INTERVAL_SECONDS = 0.2
        DEFAULT_MARKER_SIZE = 30        % 色で描く Wafer マップの点の大きさの初期値（scatter の面積 [ポイント²]）
        MARKER_SIZE_LIMITS = [1, 400]
        UNIT_CHOICES = {'mm', 'µm', 'nm', 'm'}  % 座標の入力単位の選択肢（µm は内部では um として扱う）
        TABLE_FONT_SIZE = 13            % 列の多い表（座標の単位・検定の結果）の文字の大きさ
        LIST_PREVIEW_COUNT = 12         % 学習 Shot 数の並びを画面に出す数（多いときは途中を省く）
        EXCEL_MAX_DATA_ROWS = 1048575   % Excel の最大行数から見出しの1行を除いた数
        MAX_MATERN_NU = 50              % Matérn の ν の上限（alignest.models.maternNuCheck と同じ）
        FORMULA_CHOICE = -1             % Wafer 成分の選択肢「式を入力」の値（次数 0〜5 と区別する）
        MAX_ZERNIKE_ORDER = 6           % Fringe Zernike の次数の上限（Z1〜Z49）
        MAX_RBFE_REGIONS = 25           % RBFe の領域の数の上限（alignest.buildMethodList と同じ）
        WORST_PERCENT = 95              % マップに出す「95%値」の百分位（結果一覧の集計と同じ）
        MAX_MEASURE_PANELS = 6          % 計測マップを並べる数の上限（Wafer × 学習パターン）
        MAX_COMPARE_PANELS = 6          % Wafer ごとのマップで並べて比べる条件の数の上限
        TIMING_REPEAT_LIMITS = [1, 10]  % 処理時間の内訳を測る回数の範囲
        TARGET_GRID_PITCH_MM = 10       % 「格子で置く」の間隔の初期値 [mm]
        TARGET_GRID_RADIUS_MM = 140     % 「格子で置く」の半径の初期値 [mm]（有効半径 150 mm の少し内側）
        TARGET_ALL_TRAINING = "all"     % 学習データの選択肢「計測値のある全 Mark」の値（評価の学習パターンの名前と区別する）
        TARGET_COLUMNS = {'名前', 'Xmm', 'Ymm', 'markXmm', 'markYmm', 'markNo', 'shotNo', 'Direction'}  % 推定する点の表の列
    end

    properties (SetAccess = private)
        Figure
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
        TargetSelection = zeros(0, 1)  % 推定する点の表で選んでいる行（「選んだ行を削除」で使う）
    end

    properties (Dependent)
        Palette                 % 今の画面の色の組（themePalette。文字・背景・エラー・表の最良の色など）
    end

    methods
        function palette = get.Palette(app)
            palette = themePalette(app.Theme);
        end

        function app = AlignmentEstimationApp(visible)
            if nargin < 1
                visible = true;
            end
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
            root = uigridlayout(app.Figure, [1, 1], 'Padding', 8);
            app.TabGroup = uitabgroup(root);
            app.Tabs.data = uitab(app.TabGroup, 'Title', '1. データの読み込み');
            app.Tabs.settings = uitab(app.TabGroup, 'Title', '2. 評価の設定');
            app.Tabs.run = uitab(app.TabGroup, 'Title', '3. 実行');
            app.Tabs.results = uitab(app.TabGroup, 'Title', '4. 結果一覧');
            app.Tabs.map = uitab(app.TabGroup, 'Title', '5. Waferごとのマップ');
            app.Tabs.target = uitab(app.TabGroup, 'Title', '6. 未知の座標の推定');
            app.Tabs.help = uitab(app.TabGroup, 'Title', '7. ヘルプ');
            app.TabGroup.SelectionChangedFcn = @(~, event) app.onTabChanged(event);
            buildDataTab(app);
            buildSettingsTab(app);
            buildRunTab(app);
            buildResultsTab(app);
            buildMapTab(app);
            buildTargetTab(app);
            buildHelpTab(app);
            % 表示のメニュー：ライトモード・ダークモードの切り替えと、ヘルプを開く
            viewMenu = uimenu(app.Figure, 'Text', '表示');
            app.Controls.themeLight = uimenu(viewMenu, 'Text', 'ライトモード', 'Checked', 'on', ...
                'MenuSelectedFcn', @(~, ~) app.setTheme("light"));
            app.Controls.themeDark = uimenu(viewMenu, 'Text', 'ダークモード', ...
                'MenuSelectedFcn', @(~, ~) app.setTheme("dark"));
            uimenu(viewMenu, 'Text', 'ヘルプ（用語・補正の式・カーネル）を開く', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~, ~) set(app.TabGroup, 'SelectedTab', app.Tabs.help));
            set(findall(app.Figure, '-property', 'FontSize'), 'FontSize', app.FONT_SIZE);
            set(findall(app.Figure, 'Type', 'axes'), 'FontSize', app.AXES_FONT_SIZE);
            set([app.Controls.unitTable, app.Controls.normalityTable, app.Controls.anovaTable, app.Controls.targetTable, ...
                app.Controls.targetResultTable], 'FontSize', app.TABLE_FONT_SIZE);
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
                % 前回選んだ画面の色を使う（自動テストなど画面を出さないときはライトモードのまま）
                try
                    saved = string(getpref(app.PREF_GROUP, 'theme', 'light'));
                catch
                    saved = "light";
                end
                if saved == "dark"
                    setTheme(app, "dark");
                end
            end
        end

        function setTheme(app, mode)
            %SETTHEME 画面の色を mode = "light"（ライトモード）・"dark"（ダークモード）にする（メニューの「表示」と同じ）。
            %   画面の部品・図（軸・文字・凡例・色の目盛り）・表・ヘルプの色を変え、これから描く図にも同じ色を使う。
            %   画面を出しているときは、次に開いたときも同じ色にする（setpref）。
            mode = string(mode);
            if ~any(mode == ["light", "dark"])
                error('alignest:theme', '画面の色は light（ライトモード）か dark（ダークモード）です: %s', mode);
            end
            previous = themePalette(app.Theme);
            app.Theme = mode;
            applyTheme(app, previous, themePalette(mode));
            app.Controls.themeLight.Checked = onOff(mode == "light");
            app.Controls.themeDark.Checked = onOff(mode == "dark");
            if app.Figure.Visible == "on"
                try
                    setpref(app.PREF_GROUP, 'theme', char(mode));
                catch
                    % 保存できなくても、今の画面の色は変わっている
                end
            end
        end

        function delete(app)
            if ~isempty(app.Figure) && isvalid(app.Figure)
                delete(app.Figure);
            end
        end

        % ---- 画面の操作と同じことをするメソッド（ボタンからも自動テストからも呼ぶ）
        function loadFile(app, filePath, sheetName)
            %LOADFILE ファイルを読み、列の対応を推定して表に出す（まだ解析用には変換しない）。
            if nargin < 3
                sheetName = "";
            end
            [raw, sheets, sheetName] = alignest.readMeasurementFile(filePath, sheetName);
            app.RawTable = raw;
            app.FilePath = string(filePath);
            app.SheetName = sheetName;
            app.Data = [];
            clearResults(app);
            clearDataMaps(app);
            c = app.Controls;
            % 長いパスは切れて読めないので、ファイル名だけを出し、フォルダはマウスを重ねたときに出す
            [~, name, extension] = fileparts(app.FilePath);
            c.filePath.Text = name + extension;
            c.filePath.Tooltip = char(app.FilePath);
            if all(sheets == "")
                c.sheet.Items = {'（CSV にはシートがありません）'};
                c.sheet.Enable = 'off';
            else
                c.sheet.Items = cellstr(sheets);
                c.sheet.Value = char(sheetName);
                c.sheet.Enable = 'on';
            end
            refreshValueColumns(app);
            fillMappingTable(app, alignest.guessColumnMapping(raw.Properties.VariableNames));
            fillUnitTable(app);
            c.mappingStatus.Text = sprintf(['%d 行・%d 列を読みました。「ファイルの列」の対応と、右の「座標の単位」を' ...
                '確かめてから、「この対応で読み込む」を押してください。'], height(raw), width(raw));
            c.mappingStatus.FontColor = app.Palette.text;
            c.applyMapping.Enable = 'on';
            c.summary.Value = {''};
            c.dataTabs.SelectedTab = c.mappingTab;
            refreshRunSummary(app);
        end

        function applyMapping(app)
            %APPLYMAPPING 列の対応・座標の単位・行の除外・Scan 方向の付与に従って前処理し、Wafer ごとのデータにする。
            if isempty(app.RawTable) || width(app.RawTable) == 0
                error('alignest:noFile', '先に「ファイルを選ぶ…」で計測データを読み込んでください。');
            end
            mapping = currentMapping(app);
            options = currentDataOptions(app);
            invalidatePreparedData(app);
            app.Data = alignest.prepareData(app.RawTable, mapping, validRadiusMm=options.validRadiusMm, ...
                coordinateUnits=options.coordinateUnits, excludeZeroMeasurements=options.excludeZeroMeasurements, ...
                excludeUnmeasuredRecords=options.excludeUnmeasuredRecords, directionRule=options.directionRule, ...
                invertDirection=options.invertDirection, directionOverrideShots=options.directionOverrideShots, ...
                directionOverrideValues=options.directionOverrideValues, coordinateMode=options.coordinateMode, ...
                valueColumn=options.valueColumn);
            app.AppliedMapping = mapping;
            app.Settings.data = mergeStruct(app.Settings.data, options);
            summary = app.Data.summary;
            lines = [sprintf("Wafer（評価の単位）：%d 枚", summary.nUnits); ...
                "工程（Operation）：" + listOrNone(summary.operations); ...
                "装置（EqpId）：" + listOrNone(summary.eqpIds); ...
                "ロット（LotID）：" + listOrNone(summary.lotIds); ...
                sprintf("Shot 数：%d〜%d／Wafer、Mark 数：%d〜%d／Wafer", summary.nShotsRange, summary.nMarksRange); ...
                "Shot の大きさ（中心の間隔から推定）：" + shotSizeText(summary.shotSizeRangeMm); ...
                sprintf("Mark 番号の水準：%s", strjoin(string(summary.markLevels), "、")); ...
                "Scan 方向（Direction）：" + directionText(summary); ...
                "質的変数に選べるその他の列：" + listOrNone(summary.attributeNames); ...
                summary.messages(:)];
            app.Controls.summary.Value = cellstr(lines);
            labels = string({app.Data.units.label});
            app.Controls.layoutWafer.Items = cellstr(labels);
            app.Controls.layoutWafer.ItemsData = 1:numel(labels);
            app.Controls.layoutWafer.Value = 1;
            app.MeasurementCache = [];
            refreshMeasurementChoices(app);
            refreshPreviewGroupBy(app);
            app.Controls.mappingStatus.Text = sprintf(['読み込みました（%d 枚）。上の「Wafer マップ」「Shot レイアウト」で' ...
                'データを確かめ、「2. 評価の設定」で比べ方を決めてください。'], summary.nUnits);
            app.Controls.mappingStatus.FontColor = app.Palette.text;
            drawPreview(app);
            drawLayout(app);
            app.Controls.shotOverlayWafers.Items = cellstr(labels);
            app.Controls.shotOverlayWafers.ItemsData = num2cell(1:numel(labels));
            app.Controls.shotOverlayWafers.Value = num2cell(1:numel(labels));
            % Scan 方向があれば、はじめは Scan 方向で分けた図も並べる
            app.Controls.shotOverlayByScan.Value = any(arrayfun(@(unit) any(~isnan(unit.marks.direction)), app.Data.units));
            drawShotOverlay(app);
            refreshFactorColumns(app);
            validateSettings(app);
            refreshRunSummary(app);
            refreshTargetChoices(app);
        end

        function setSettings(app, settings)
            %SETSETTINGS 設定を画面に反映する（設定ファイルの読み込みと同じ）。
            %   以前の設定に無い項目は初期値にする。学習 Shot 数は並び（nShots）と開始・終了・刻みをそろえる。
            %   同心円の区切り・外周の半径が比（以前の設定）なら mm に直す。
            settings = alignest.upgradeRadiusSettings(settings);
            settings.methods = alignest.completeMethodSettings(settings.methods);
            defaults = alignest.defaultSettings();
            for group = ["data", "factors", "sampling", "evaluation", "overlay"]
                if ~isfield(settings, group)
                    settings.(group) = defaults.(group);
                end
                for name = string(fieldnames(defaults.(group))).'
                    if ~isfield(settings.(group), name)
                        settings.(group).(name) = defaults.(group).(name);
                    end
                end
            end
            settings.data.coordinateUnits = alignest.coordinateUnits(settings.data.coordinateUnits);
            settings.data.directionRule = string(settings.data.directionRule);
            settings.sampling = alignest.syncShotCounts(settings.sampling);
            if ~isempty(app.Data) && ~isequal(dataOptions(settings.data), dataOptions(app.Data))
                invalidatePreparedData(app);
            end
            app.Settings = settings;
            settingsToControls(app);
            refreshRunSummary(app);
        end

        function results = runEvaluationNow(app, showProgress, pauseAfter)
            %RUNEVALUATIONNOW 評価を最初から実行して結果の画面を更新する。進み具合の画面の「一時中断」で止められ、
            %   止めたときは途中までの結果を出す（resumeEvaluation で続きから再開できる）。
            %   pauseAfter（省略可）を渡すと、その件数を計算したところで一時中断する（動作確認・説明資料用）。
            if nargin < 2
                showProgress = true;
            end
            if nargin < 3
                pauseAfter = Inf;
            end
            prepareEvaluation(app);
            results = evaluate(app, showProgress, [], pauseAfter);
        end

        function results = resumeEvaluation(app, showProgress)
            %RESUMEEVALUATION 一時中断した評価を、続きから再開する（済んだ組み合わせは計算しない）。
            %   中断した後に設定やデータを変えたときは再開できない（「評価を始める」で最初から計算する）。
            if nargin < 2
                showProgress = true;
            end
            previous = app.BaseResults;
            if isempty(previous) || ~previous.cancelled || ~isfield(previous, "resume") || isempty(previous.resume)
                error('alignest:resume', '続きから再開できる評価がありません。「評価を始める」で計算してください。');
            end
            prepareEvaluation(app);
            runSettings = previous.settings;
            if isfield(previous, "runSettings")
                runSettings = previous.runSettings;   % 条件を足した評価では、合わせた設定ではなく最後に実行した設定と比べる
            end
            if ~isequaln(runSettings, app.Settings)
                error('alignest:resume', ['一時中断した後に評価の設定が変わったので、続きから再開できません。' ...
                    '設定を戻すか、「評価を始める」で最初から計算してください。']);
            end
            results = evaluate(app, showProgress, previous, Inf, "resume");
        end

        function results = extendEvaluation(app, showProgress)
            %EXTENDEVALUATION 評価済みの結果に、「2. 評価の設定」で増やした手法・学習パターン（学習 Shot 数・計測率など）を
            %   足して評価する。済んだ組み合わせ（Wafer × 学習パターン × 手法）は計算せず、無いものだけを計算して結果に
            %   加える（alignest.runEvaluation の "extend"）。推定の結果を変える設定（データ・質的変数・制約・評価の条件・
            %   Overlay 補正など。alignest.extensionConflicts）を変えたときは追加できない（「評価を始める」で計算し直す）。
            if nargin < 2
                showProgress = true;
            end
            prepareEvaluation(app);
            previous = app.BaseResults;
            if isempty(previous) || isImportedResults(previous)
                error('alignest:extend', ['条件を追加できる評価の結果がありません。先に「評価を始める」で評価してください' ...
                    '（Excel から読み込んだ結果には追加できません）。']);
            end
            results = evaluate(app, showProgress, previous, Inf, "extend");
        end

        function results = applyResultFilter(app, filter)
            %APPLYRESULTFILTER 評価点を半径・Shot の条件で絞り込み、結果一覧の表・グラフ・基準の手法との比較と、
            %   Wafer ごとのマップを描き直す（指標は alignest.filterResults で計算し直す。推定はやり直さない）。
            %   filter（alignest.defaultPointFilter と同じ形）を省くと、絞り込みを解除する。推定値と誤差の分布・箱ひげ図・
            %   散布図・分布の比較・推定値の書き出しは、次に計算するときに同じ条件で評価点を絞り込む。
            %   Excel から読み込んだ結果では表・グラフは計算し直せない（読み込んだ推定値を使う図だけを絞り込む）。
            if nargin < 2
                filter = alignest.defaultPointFilter();
            end
            if isempty(app.BaseResults)
                error('alignest:noResults', '先に「3. 実行」で評価してください。');
            end
            validateFilter(filter);
            if isImportedResults(app.BaseResults)
                results = app.BaseResults;
                results.filter = filter;
                [~, results.filterText] = alignest.pointFilterMask(filter);
            else
                results = alignest.filterResults(app.BaseResults, app.Data, filter);
            end
            app.ResultFilter = filter;
            app.Results = results;
            clearPointViews(app);
            showFilter(app);
            refreshResults(app);
            drawMap(app);
        end

        function exportResultsTo(app, filePath)
            %EXPORTRESULTSTO 結果を Excel に書き出す。
            if isempty(app.Results)
                error('alignest:noResults', '先に「3. 実行」で評価してください。');
            end
            if isImportedResults(app.Results)
                error('alignest:importedResults', ['Excel から読み込んだ結果は書き出せません（読み込んだファイル「%s」を' ...
                    'そのまま使ってください）。'], app.Results.imported);
            end
            alignest.exportResults(app.Results, filePath, app.FilePath);
        end

        function results = importResultsFrom(app, filePath)
            %IMPORTRESULTSFROM 「結果を Excel に書き出す」で書き出したファイルを読み込み、結果の画面に出す。
            %   表・グラフ・基準の手法との比較を見られる。推定値は Excel に無いので、Wafer マップ・推定値と誤差の分布・
            %   散布図・分布の比較は使えない（計測ファイルを読み込んで「3. 実行」で評価し直すと使える）。
            results = alignest.importResults(filePath);
            clearResults(app);
            app.Results = results;
            app.BaseResults = results;
            refreshResultControls(app);
            app.TabGroup.SelectedTab = app.Tabs.results;
        end

        function imported = importEstimatesFrom(app, filePath)
            %IMPORTESTIMATESFROM 「推定値を Excel に書き出す」で書き出したファイルを読み込み、Excel から読み込んだ評価結果と
            %   組にする。Wafer マップ・推定値と誤差の分布・散布図・分布の比較を、推定値の Excel にある手法・学習パターン・
            %   Wafer の範囲で描ける（計測ファイルは要らない）。先に importResultsFrom で評価結果を読み込んでおく。
            if ~isImportedResults(app.Results)
                error('alignest:importEstimates', ['先に「結果を読み込む…」で評価結果の Excel を読み込んでください' ...
                    '（推定値の Excel は、同じ評価から書き出した評価結果と組で使います）。']);
            end
            imported = alignest.importEstimates(filePath);
            results = app.Results;
            known = @(points) ismember(points.methodId, string({results.methods.id})) & ...
                ismember(points.group, results.groups) & ismember(points.Wafer, results.unitLabels);
            matched = known(imported.estimates);
            if ~any(matched)
                error('alignest:importEstimates', ['推定値の Excel の手法・学習パターン・Wafer が、読み込んだ評価結果に' ...
                    'ありません。同じ評価から書き出した2つのファイルを選んでください。']);
            end
            imported.estimates = imported.estimates(matched, :);
            imported.nIgnored = nnz(~matched);
            if height(imported.overlayPoints) > 0
                imported.overlayPoints = imported.overlayPoints(known(imported.overlayPoints), :);
            end
            app.ImportedEstimates = imported;
            app.Analysis = [];
            app.Distribution = [];
            refreshResultControls(app);
        end

        function layouts = loadLayoutPlans(app, filePath, sheetName)
            %LOADLAYOUTPLANS 人が選んだ計測配置の Excel（shotNo と、パターンごとの 1・0 の列。計測マップの Excel と同じ形）を
            %   読み、手動・人の選択の欄に1パターン1行（「名前: shotNo…」）で入れる（alignest.readLayoutPlans）。
            %   選び方に「手動・人の選択」を足す（ほかに選んでいた選び方はそのまま。I 最適・D 最適と比べられる）。
            if nargin < 3
                sheetName = "";
            end
            layouts = alignest.readLayoutPlans(filePath, sheetName);
            controlsToSettings(app);
            app.Settings.sampling.manualPlans = layouts.lines;
            app.Settings.sampling.method = unique([reshape(string(app.Settings.sampling.method), 1, []), "manual"], 'stable');
            settingsToControls(app);
            refreshRunSummary(app);
        end

        function priority = loadShotPriority(app, filePath)
            %LOADSHOTPRIORITY 計測する Shot の優先順のファイルを読み、設定に入れる（選び方も「ファイルの優先順」にする）。
            priority = alignest.readShotPriority(filePath);
            app.Settings.sampling.priorityShots = priority.shotNo;
            app.Settings.sampling.priorityLevels = priority.level;
            app.Settings.sampling.priorityFile = priority.file;
            app.Settings.sampling.method = "file";
            settingsToControls(app);
            refreshRunSummary(app);
        end

        function overlay = drawShotOverlay(app, unitIndex, byScan)
            %DRAWSHOTOVERLAY 選んだ Wafer（unitIndex、省略時は画面の選択）のすべての Shot を Shot 内の座標で重ね合わせ、
            %   個々の Shot の矢印・Mark の位置ごとの平均・共分散楕円を「Shot 重ね合わせ」に描く。
            %   byScan（省略時は画面の選択）が true なら、Scan 方向ごとに重ねた図も右に並べる。
            %   overlay は描いた図ごとの alignest.shotOverlay の結果（1つ目がすべての Shot）。
            c = app.Controls;
            overlay = [];
            if isempty(app.Data)
                return
            end
            if alignest.valueSpec(app.Settings.data).scalar
                showOverlayPanels(app, 0);
                c.shotOverlayInfo.Value = {'Shot 重ね合わせは X・Y のベクトル場の図なので、1変数の推定では使いません。'};
                return
            end
            if nargin >= 2
                c.shotOverlayWafers.Value = num2cell(unitIndex);
            end
            if nargin >= 3
                c.shotOverlayByScan.Value = byScan;
            end
            selected = cell2mat(c.shotOverlayWafers.Value);
            if isempty(selected)
                showOverlayPanels(app, 0);
                c.shotOverlayInfo.Value = {'Wafer を1枚以上選んでください。'};
                return
            end
            % 図ごとの Scan 方向（NaN = すべて）。選んだ Wafer に Scan 方向が無ければ分けない
            directions = NaN;
            notes = strings(0, 1);
            if c.shotOverlayByScan.Value
                marks = [app.Data.units(selected).marks];
                levels = unique(vertcat(marks.direction));
                levels = levels(~isnan(levels)).';
                if isempty(levels)
                    notes(end + 1) = "選んだ Wafer に Scan 方向が無いため、Scan 方向で分けた図は描きません。";
                end
                directions = [NaN, levels(1:min(end, numel(c.shotOverlayAxes) - 1))];
            end
            showOverlayPanels(app, numel(directions));
            order = c.shotOverlayWaferOrder.Value;
            orderText = ternary(order > 0, sprintf("Wafer 成分 %d次を除く", order), "");
            scale = c.shotOverlayScale.Value;
            lines = strings(0, 1);
            for k = 1:numel(directions)
                part = alignest.shotOverlay(app.Data.units, selected, order, app.Settings.data.waferRadiusMm, ...
                    directions(k));
                if numel(directions) == 1
                    titleText = sprintf("Wafer %d 枚・%d Shot を重ね合わせ%s", part.nWafers, part.nShots, ...
                        ternary(order > 0, "、" + orderText, ""));
                    heading = "Mark の位置ごと（Shot 内の座標 [mm]）。σ と相関は Shot・Wafer 間。楕円の色は相関の絶対値 |r|。";
                elseif isnan(directions(k))
                    titleText = sprintf("すべての Shot（Wafer %d 枚・%d Shot）", part.nWafers, part.nShots);
                    heading = "【すべての Shot】Mark の位置ごと（Shot 内の座標 [mm]）。σ と相関は Shot・Wafer 間。" + ...
                        "楕円の色は相関の絶対値 |r|。";
                else
                    titleText = sprintf("Scan 方向 %g（%d Shot）", directions(k), part.nShots);
                    heading = sprintf("【Scan 方向 %g】", directions(k));
                end
                if numel(directions) > 1 && order > 0
                    titleText = titleText + newline + orderText;
                end
                % 並べる図は、1つ目（すべての Shot）と同じ矢印の倍率・色の範囲で描く
                if k == 1
                    values = vertcat(part.values{:});
                    magnitudeLimit = max([0; hypot(values(:, 1), values(:, 2))], [], 'omitnan');
                end
                scale = alignest.plot.shotOverlayMap(c.shotOverlayAxes(k), part, scaleMmPerNm=scale, ...
                    ellipseSigma=c.shotOverlayEllipse.Value, showIndividual=c.shotOverlayIndividual.Value, ...
                    titleText=titleText, magnitudeLimit=magnitudeLimit, ...
                    showArrows=~(c.shotOverlayEllipseOnly.Value && c.shotOverlayEllipse.Value > 0));
                c.shotOverlayAxes(k).Visible = 'on';
                c.shotOverlayAxes(k).FontSize = app.AXES_FONT_SIZE;
                lines = [lines; heading; overlayLines(part)]; %#ok<AGROW>
                overlay = [overlay, part]; %#ok<AGROW>
            end
            c.shotOverlayInfo.Value = cellstr([notes; lines]);
        end

        function plans = drawMeasurementMap(app, unitIndex, planLabels)
            %DRAWMEASUREMENTMAP 選んだ Wafer・学習パターン（省略時は画面の選択。どちらも複数可）の計測マップを「3. 実行」に
            %   並べて描く（Wafer × 学習パターン、最大 MAX_MEASURE_PANELS 枚）。学習に使う（計測する）Shot・必ず計測する Shot・
            %   計測しない Shot を塗り分け、選べば Scan 方向（Shot の内側の色の枠と ▲・▼）と同心円の制約の区切りも描く。
            %   評価の前に使える。学習パターンは評価と同じ作り方なので、同じ設定なら評価でも同じ Shot を使う。
            %   plans は描いた学習パターン（Wafer ごとに学習パターンの順）。
            c = app.Controls;
            if isempty(app.Data)
                error('alignest:noData', '先に「1. データの読み込み」でデータを読み込んでください。');
            end
            controlsToSettings(app);
            settingsErrors = validateSettings(app);
            if ~isempty(settingsErrors)
                error('alignest:settings', '%s', strjoin(settingsErrors, newline));
            end
            refreshMeasurementChoices(app);
            if nargin >= 2
                c.measureWafer.Value = num2cell(unitIndex);
            end
            if nargin >= 3
                planLabels = string(planLabels);
                unknown = planLabels(~ismember(planLabels, string(c.measurePlan.Items)));
                if ~isempty(unknown)
                    error('alignest:measurementPlan', '学習パターン「%s」はありません（「2. 評価の設定」を確かめてください）。', ...
                        unknown(1));
                end
                c.measurePlan.Value = cellstr(planLabels);
            end
            specs = alignest.buildPlanSpecs(app.Settings.sampling);
            units = cell2mat(c.measureWafer.Value);
            labels = string(c.measurePlan.Value);
            if isempty(units) || isempty(labels)
                error('alignest:measurementPlan', 'Wafer と学習パターンを1つ以上選んでください。');
            end
            [unitGrid, labelGrid] = ndgrid(1:numel(units), 1:numel(labels));
            pairs = [reshape(units(unitGrid.'), [], 1), reshape(labelGrid.', [], 1)];   % Wafer ごとに学習パターンの順
            nPanels = min(size(pairs, 1), app.MAX_MEASURE_PANELS);
            dialog = [];
            if app.Figure.Visible == "on"
                dialog = uiprogressdlg(app.Figure, 'Title', '計測マップ', 'Indeterminate', 'on', 'Message', '');
            end
            cleanup = onCleanup(@() closeDialog(dialog));
            if app.Figure.Visible == "on" && app.TabGroup.SelectedTab ~= app.Tabs.run
                % 並べ方は枠の大きさで決めるので、枠が画面に出ている状態で描く
                app.TabGroup.SelectedTab = app.Tabs.run;
                drawnow;
            end
            layout = resetMeasurePanel(app, nPanels);
            rings = zeros(1, 0);
            if c.measureRings.Value
                rings = activeZoneEdges(app.Settings);
            end
            plans = repmat(alignest.planTemplate(), 0, 1);
            lines = strings(0, 1);
            axesList = gobjects(1, nPanels);
            for k = 1:nPanels
                unit = app.Data.units(pairs(k, 1));
                spec = specs(string({specs.label}) == labels(pairs(k, 2)));
                plan = measurementPlan(app, pairs(k, 1), spec(1), dialog);
                ax = nexttile(layout);
                alignest.plot.measurementMap(ax, unit, plan, app.Settings.data.waferRadiusMm, ...
                    unit.label + "｜" + plan.label, showScan=c.measureScan.Value, ringRadiiMm=rings, ...
                    showLegend=nPanels == 1, allCategories=k == 1 && nPanels > 1);
                ax.FontSize = ternary(nPanels > 1, app.SMALL_AXES_FONT_SIZE, app.AXES_FONT_SIZE);
                axesList(k) = ax;
                plans(end + 1, 1) = orderfields(plan, alignest.planTemplate()); %#ok<AGROW>
                lines = [lines; measurementLines(app, unit, plan)]; %#ok<AGROW>
            end
            if nPanels > 1
                % 並べるときは凡例を1つだけ右に、短い名前で出す（区分の数は図ごとに違うので、数は下の欄に書く）
                items = flipud(findobj(axesList(1), '-regexp', 'DisplayName', '.+'));
                names = regexprep(string(get(items, 'DisplayName')), '（\d+）$', '');
                names = replace(names, ["必ず計測する Shot（指定・最外周など）", "選んで計測する Shot", ...
                    "計測しない Shot（評価に使う）", "計測値の無い Shot"], ["必ず計測", "選んで計測", "計測しない（評価）", ...
                    "計測値なし"]);
                shown = legend(axesList(1), items, cellstr(names), 'Box', 'off', 'FontSize', app.SMALL_AXES_FONT_SIZE);
                shown.Layout.Tile = 'east';
            end
            app.Controls.measureAxes = axesList;
            if size(pairs, 1) > nPanels
                lines = [sprintf("選んだ %d 通りのうち、はじめの %d 通りを描きました（Wafer・学習パターンを減らしてください）。", ...
                    size(pairs, 1), nPanels); lines];
            end
            c.measureInfo.Value = cellstr(lines);
        end

        function sheet = exportMeasurementMap(app, filePath)
            %EXPORTMEASUREMENTMAP 選んだ Wafer（複数選んだときは1枚目）の計測マップを、すべての学習パターンについて
            %   Excel に書き出す。
            %   「計測マップ」シート：Shot ごとの座標・行・列・最外周・指定の有無と、学習パターンごとの 1（計測する）／0（しない）。
            %   「学習パターン」シート：学習パターンごとの Shot 数・計測率・必ず計測した数・I 基準・D 基準・shotNo・メモ。
            if isempty(app.Data)
                error('alignest:noData', '先に「1. データの読み込み」でデータを読み込んでください。');
            end
            controlsToSettings(app);
            settingsErrors = validateSettings(app);
            if ~isempty(settingsErrors)
                error('alignest:settings', '%s', strjoin(settingsErrors, newline));
            end
            refreshMeasurementChoices(app);
            selected = cell2mat(app.Controls.measureWafer.Value);
            if isempty(selected)
                error('alignest:measurementPlan', '書き出す Wafer を選んでください。');
            end
            unitIndex = selected(1);
            unit = app.Data.units(unitIndex);
            shots = unit.shots;
            specs = alignest.buildPlanSpecs(app.Settings.sampling);
            dialog = [];
            if app.Figure.Visible == "on"
                dialog = uiprogressdlg(app.Figure, 'Title', '計測マップ', 'Message', '', 'ShowPercentage', 'on');
            end
            cleanup = onCleanup(@() closeDialog(dialog));
            candidates = find(shots.nValidX + shots.nValidY > 0);
            [~, required] = alignest.requiredShotIndex(shots, candidates, app.Settings.sampling);
            sheet = table(shots.shotNo, shots.Xmm, shots.Ymm, shots.row, shots.column, shots.direction, ...
                double(ismember((1:numel(shots.shotNo)).', candidates)), double(alignest.outerShots(shots)), ...
                double(ismember((1:numel(shots.shotNo)).', required.specified)), 'VariableNames', ["shotNo", "Xmm", ...
                "Ymm", "行（上から）", "列（左から）", "Scan方向", "計測値あり", "最外周", "指定で必ず計測"]);
            summary = cell(numel(specs), 11);
            marks = unit.marks;
            markSheet = table(marks.shotNo, marks.markNo, marks.x, marks.y, 'VariableNames', ["shotNo", "markNo", "Xmm", "Ymm"]);
            hasMarkPlans = false;
            for k = 1:numel(specs)
                if ~isempty(dialog)
                    dialog.Value = (k - 1) / numel(specs);
                end
                plan = measurementPlan(app, unitIndex, specs(k), dialog);
                sheet.(char(plan.label)) = double(ismember((1:numel(shots.shotNo)).', plan.shotIndex));
                markSheet.(char(plan.label)) = double(alignest.trainingMarks(unit, plan) & plan.ok);
                hasMarkPlans = hasMarkPlans || ~isempty(plan.markIndex);
                summary(k, :) = {plan.label, plan.rate, plan.nShots, numel(plan.requiredShotIndex), plan.criterionI, ...
                    plan.criterionD, plan.efficiencyI, plan.efficiencyD, plan.violation, ...
                    strjoin(string(plan.shotNos(:).'), " "), plan.message};
            end
            planSheet = cell2table(summary, 'VariableNames', ["学習パターン", "計測率[%]", "学習Shot数", ...
                "必ず計測したShot数", "I基準tr(M⁻¹)", "D基準det(M)^(-1/p)", "I効率(全計測に対する)", ...
                "D効率(全計測に対する)", "制約の違反量", "計測するshotNo", "メモ"]);
            if isfile(filePath)
                delete(filePath);
            end
            writetable(sheet, filePath, 'Sheet', '計測マップ');
            if hasMarkPlans
                % Mark 単位の計画があるときは、Mark ごとの 1（計測する）・0（しない）も書く
                writetable(markSheet, filePath, 'Sheet', '計測マップ_Mark');
            end
            writetable(planSheet, filePath, 'Sheet', '学習パターン');
            notes = table(["Wafer"; "学習 Shot の選び方"; "見方"], [unit.label; ...
                strjoin(string(app.Controls.samplingMethod.Items(ismember(app.Controls.samplingMethod.ItemsData, ...
                app.Controls.samplingMethod.Value))), "、"); "学習パターンの列は 1 = 計測する（学習に使う）、0 = 計測しない（評価に使う）。" + ...
                "最外周・指定で必ず計測は 1 = そうである。"], 'VariableNames', ["項目", "内容"]);
            writetable(notes, filePath, 'Sheet', '説明');
        end

        function setScanDirection(app, shotNos, directions)
            %SETSCANDIRECTION shotNo の Scan 方向を directions（1・2。shotNos と同じ数、または1つ）に変える。
            %   すべての Wafer の同じ shotNo に当て、前処理をやり直す（評価の結果は消える）。shotNos が空なら変更をすべて戻す。
            %   変えた Scan 方向は設定（data.directionOverrideShots・directionOverrideValues）に残る。
            if isempty(app.RawTable) || width(app.RawTable) == 0
                error('alignest:noFile', '先に「ファイルを選ぶ…」で計測データを読み込んでください。');
            end
            shots = app.Settings.data.directionOverrideShots;
            values = app.Settings.data.directionOverrideValues;
            if isempty(shotNos)
                shots = zeros(1, 0);
                values = zeros(1, 0);
            else
                shotNos = reshape(double(shotNos), 1, []);
                directions = reshape(double(directions), 1, []);
                if isscalar(directions)
                    directions = repmat(directions, size(shotNos));
                end
                if numel(directions) ~= numel(shotNos) || any(~ismember(directions, [1, 2]))
                    error('alignest:directionOverride', 'Scan 方向は 1 か 2 を、shotNo と同じ数だけ指定してください。');
                end
                keep = ~ismember(shots, shotNos);
                shots = [shots(keep), shotNos];
                values = [values(keep), directions];
            end
            app.Settings.data.directionOverrideShots = shots;
            app.Settings.data.directionOverrideValues = values;
            shownWafer = app.Controls.layoutWafer.Value;
            selectedTab = app.Controls.dataTabs.SelectedTab;
            applyMapping(app);
            if isnumeric(shownWafer) && shownWafer <= numel(app.Data.units)
                app.Controls.layoutWafer.Value = shownWafer;
                drawLayout(app);
            end
            app.Controls.dataTabs.SelectedTab = selectedTab;
        end

        function onLayoutShotClicked(app, point)
            %ONLAYOUTSHOTCLICKED Shot レイアウトの point [x, y]（mm）の Shot の Scan 方向を 1 ↔ 2 で入れ替える
            %   （方向が無ければ 1 にする。すべての Wafer の同じ shotNo。図のクリックから呼ぶ）。
            if isempty(app.Data)
                return
            end
            unit = app.Data.units(app.Controls.layoutWafer.Value);
            half = unit.shotSizeMm / 2;
            inside = find(abs(unit.shots.Xmm - point(1)) <= half(1) & abs(unit.shots.Ymm - point(2)) <= half(2), 1);
            if isempty(inside)
                return
            end
            current = unit.shots.direction(inside);
            next = 1;
            if current == 1
                next = 2;
            end
            runWithAlert(app, @() app.setScanDirection(unit.shots.shotNo(inside), next), ...
                "Scan 方向を変えられませんでした", "「1. データの読み込み」の設定を確かめてください。");
        end

        function changed = suggestCoordinateUnits(app)
            %SUGGESTCOORDINATEUNITS ファイルの値の大きさから、座標の列ごとの入力単位を推定して選ぶ（目安の外の列だけ）。
            checks = alignest.checkCoordinateUnits(app.RawTable, currentMapping(app), app.Settings.data.coordinateUnits);
            change = ~checks.ok & checks.suggested ~= "";
            units = app.Settings.data.coordinateUnits;
            for k = find(change).'
                units.(checks.name(k)) = checks.suggested(k);
            end
            changed = checks.name(change);
            app.Settings.data.coordinateUnits = alignest.coordinateUnits(units);
            fillUnitTable(app);
            status = app.Controls.unitStatus;
            if any(change)
                invalidatePreparedData(app);
                parts = checks.name(change) + "：" + displayUnit(checks.unit(change)) + " → " + ...
                    displayUnit(checks.suggested(change));
                status.Text = "値の大きさから単位を選びました（" + strjoin(parts, "、") + "）。「この対応で読み込む」を押してください。";
                status.FontColor = app.Palette.text;
            elseif all(checks.ok)
                status.Text = "すべての座標の大きさが目安の範囲内なので、単位は変えていません。";
                status.FontColor = app.Palette.text;
            else
                status.Text = "⚠ 目安に合う単位が見つからない列があります。列の対応が正しいか確かめてください。";
                status.FontColor = app.Palette.error;
            end
        end

        function analysis = analyzeResiduals(app, methodIndex, group, unitIndex)
            %ANALYZERESIDUALS 選んだ手法・学習パターンの列・Wafer（0 = すべて）の評価点の残差を、
            %   ヒストグラム・正規性検定・質的変数の ANOVA で調べて「推定値と誤差の分布」に出す。
            requireEstimates(app);
            c = app.Controls;
            if nargin >= 2
                c.analysisMethod.Value = methodIndex;
                c.analysisGroup.Value = char(group);
                c.analysisWafer.Value = unitIndex;
            end
            selection = analysisSelection(app);
            [estimates, messages] = collectWithProgress(app, selection, app.MapCache, Inf, "残差を計算しています");
            if height(estimates) == 0
                error('alignest:noEstimates', '評価点がありません（この組み合わせは推定できませんでした）。%s', ...
                    strjoin(messages, newline));
            end
            analysis = alignest.residualAnalysis(estimates);
            app.Analysis = struct("estimates", estimates, "analysis", analysis, "selection", selection, ...
                "messages", messages);
            showAnalysis(app);
            % 同じ残差の箱ひげ図（質的変数は前の選択があればそのまま、無ければ最初の変数）
            names = string({alignest.residualFactors(estimates).name});
            c.boxFactor.Enable = onOff(~isempty(names));
            if isempty(names)
                c.boxFactor.Items = {'—'};
                c.boxInfo.Text = '質的変数に値が無いため、箱ひげ図は描けません。';
                return
            end
            previous = string(c.boxFactor.Value);
            c.boxFactor.Items = cellstr(names);
            c.boxFactor.Value = char(ternary(any(names == previous), previous, names(1)));
            drawResidualBoxplot(app);
        end

        function summary = drawResidualBoxplot(app, factorName)
            %DRAWRESIDUALBOXPLOT 最後に分析した残差（「推定値と誤差の分布」の「分析する」）を、質的変数の水準ごとの
            %   箱ひげ図で X・Y 別に「残差の箱ひげ図（ANOVA）」に描く。題名に一元配置の ANOVA の F・p 値・η² を書く。
            %   factorName（省略時は画面の選択）は alignest.residualFactors の変数の名前（例："Scan 方向"・"Mark 番号"）。
            %   summary は X・Y の水準ごとの点数・平均・中央値（alignest.plot.residualBoxplot）。
            c = app.Controls;
            if isempty(app.Analysis)
                error('alignest:noAnalysis', '先に「推定値と誤差の分布」で「分析する」を押してください。');
            end
            factors = alignest.residualFactors(app.Analysis.estimates);
            names = string({factors.name});
            if nargin >= 2
                if ~any(names == string(factorName))
                    error('alignest:boxFactor', '質的変数「%s」はこの分析にありません（%s）。', factorName, strjoin(names, "、"));
                end
                c.boxFactor.Items = cellstr(names);
                c.boxFactor.Value = char(factorName);
            end
            factor = factors(names == string(c.boxFactor.Value));
            anova = app.Analysis.analysis.anova;
            notes = strings(1, 2);
            axisNames = ["X", "Y"];
            for k = 1:2
                titleText = axisNames(k) + " の残差：" + factor.name;
                row = table();
                if height(anova) > 0
                    row = anova(anova.axis == axisNames(k) & anova.factor == factor.name, :);
                end
                if height(row) > 0 && isfinite(row.F(1))
                    titleText = titleText + sprintf("（一元配置 F = %.2f、p = %s、η² = %.3f）", row.F(1), ...
                        pValueText(row.p(1)), row.etaSquared(1));
                    notes(k) = axisNames(k) + "：" + judgementWithNote(row.judgement(1), row.note(1));
                else
                    notes(k) = axisNames(k) + "：検定できません（水準が1つ、または点が少ない）";
                end
                part = alignest.plot.residualBoxplot(c.boxAxes(k), factor.levels, ...
                    app.Analysis.estimates.("residual" + axisNames(k)), titleText);
                summary(k) = struct("axis", axisNames(k), "levels", part); %#ok<AGROW>
            end
            set(c.boxAxes, 'Visible', 'on', 'FontSize', app.AXES_FONT_SIZE);
            results = app.Results;
            selection = app.Analysis.selection;
            c.boxInfo.Text = sprintf("%s｜%s｜Wafer %d 枚｜判定（5%%）：%s", results.methods(selection.methodIndex).label, ...
                selection.groups, numel(selection.unitIndex), strjoin(notes, "、")) + filterNote(app);
        end

        function breakdown = measureTiming(app, unitIndex, planLabel, methodIndex, nRepeats)
            %MEASURETIMING 選んだ Wafer・学習パターン・手法（複数可）の処理時間を段階ごとに測り、「処理時間の内訳」に
            %   積み上げ横棒（秒・割合）と表で出す（alignest.timingBreakdown。評価の結果は変えない）。引数を省くと画面の選択。
            c = app.Controls;
            if isempty(app.BaseResults) || isImportedResults(app.BaseResults) || isempty(app.Data)
                error('alignest:noResults', ['処理時間は、計測データを読み込んで評価した結果で測れます' ...
                    '（Excel から読み込んだ結果では測れません）。']);
            end
            if nargin >= 2
                c.timingWafer.Value = unitIndex;
                c.timingPlan.Value = char(planLabel);
                c.timingMethods.Value = num2cell(methodIndex);
            end
            if nargin >= 5
                c.timingRepeats.Value = nRepeats;
            end
            results = app.BaseResults;
            methodIndex = cell2mat(c.timingMethods.Value);
            if isempty(methodIndex)
                error('alignest:timingBreakdown', '手法を1つ以上選んでください。');
            end
            runSettings = results.settings;
            if isfield(results, "runSettings")
                runSettings = results.runSettings;
            end
            if isfield(results, "specs")
                specs = results.specs;
            else
                specs = alignest.buildPlanSpecs(runSettings.sampling);
            end
            spec = specs(string({specs.label}) == string(c.timingPlan.Value));
            if isempty(spec)
                error('alignest:timingBreakdown', '学習パターン「%s」がありません。', c.timingPlan.Value);
            end
            dialog = [];
            if app.Figure.Visible == "on"
                dialog = uiprogressdlg(app.Figure, 'Title', '処理時間の内訳', 'Indeterminate', 'on', ...
                    'Message', '同じ計算をくり返して時間を測っています…');
            end
            cleanup = onCleanup(@() closeDialog(dialog));
            unit = app.Data.units(c.timingWafer.Value);
            breakdown = alignest.timingBreakdown(unit, spec(1), results.methods(methodIndex), runSettings, ...
                c.timingRepeats.Value);
            app.Timing = breakdown;
            alignest.plot.timingBars(c.timingAxes(1), c.timingAxes(2), breakdown);
            set(c.timingAxes, 'Visible', 'on', 'FontSize', app.AXES_FONT_SIZE);
            values = breakdown.table{:, cellstr(breakdown.stages)};
            rows = cell(height(breakdown.table), numel(breakdown.stages) + 2);
            for m = 1:height(breakdown.table)
                total = breakdown.table.total(m);
                rows{m, 1} = char(breakdown.table.methodLabel(m));
                rows{m, 2} = sprintf('%.3f', total);
                for k = 1:numel(breakdown.stages)
                    rows{m, k + 2} = sprintf('%.4f（%.0f%%）', values(m, k), 100 * values(m, k) / max(total, eps));
                end
            end
            c.timingTable.Data = rows;
            c.timingTable.ColumnName = cellstr(["手法", "合計 [秒]", breakdown.labels + " [秒]"]);
            c.timingTable.ColumnWidth = [{app.METHOD_COLUMN_WIDTH, 90}, repmat({'auto'}, 1, numel(breakdown.stages))];
            c.timingInfo.Text = sprintf("%s｜%s｜学習点 X %d・Y %d、評価点 X %d・Y %d｜", unit.label, spec(1).label, ...
                breakdown.nTrain, breakdown.nTest) + c.timingInfo.UserData;
        end

        function summary = drawScatter(app, methodIndex, group, unitIndex, colorBy)
            %DRAWSCATTER 選んだ手法・学習パターンの列・Wafer（0 = すべて）の評価点で、実測値と推定値の散布図を X・Y 別に描く。
            %   colorBy は色分けの項目（none・wafer・lot・eqp・operation・scan・mark・row・col:<列名>）。
            requireEstimates(app);
            c = app.Controls;
            if nargin >= 2
                c.scatterMethod.Value = methodIndex;
                c.scatterGroup.Value = char(group);
                c.scatterWafer.Value = unitIndex;
                c.scatterColor.Value = char(colorBy);
            end
            unitIndex = c.scatterWafer.Value;
            if unitIndex == 0
                unitIndex = 1:numel(app.Results.unitLabels);
            end
            selection = struct("methodIndex", c.scatterMethod.Value, "groups", string(c.scatterGroup.Value), ...
                "unitIndex", unitIndex);
            estimates = collectWithProgress(app, selection, app.MapCache, Inf, "散布図の推定値を計算しています");
            if height(estimates) == 0
                error('alignest:noEstimates', '評価点がありません（この組み合わせは推定できませんでした）。');
            end
            categories = scatterCategories(app, estimates, string(c.scatterColor.Value));
            spec = resultSpec(app);
            summary = alignest.plot.estimateScatter(c.scatterAxes(1), estimates.measX, estimates.estimateX, categories, ...
                spec.labels(1), spec.unit);
            if spec.scalar
                c.scatterAxesGrid.ColumnWidth = {'1x', 0};   % 1変数は Y 成分が無い
                cla(c.scatterAxes(2), 'reset');
                c.scatterAxes(2).Visible = 'off';
            else
                c.scatterAxesGrid.ColumnWidth = {'1x', '1x'};
                c.scatterAxes(2).Visible = 'on';
                summary(2) = alignest.plot.estimateScatter(c.scatterAxes(2), estimates.measY, estimates.estimateY, ...
                    categories, "Y");
            end
            set(c.scatterAxes, 'FontSize', app.AXES_FONT_SIZE);
            c.scatterInfo.Text = sprintf(['%s｜%s｜Wafer %d 枚｜色：%s。破線は y = x、赤い線は回帰直線' ...
                '（推定値 = a + b·実測値）、r は相関係数。'], app.Results.methods(selection.methodIndex).label, ...
                selection.groups, numel(unitIndex), string(c.scatterColor.Items{strcmp(c.scatterColor.ItemsData, ...
                c.scatterColor.Value)})) + filterNote(app);
        end

        function comparison = compareDistributions(app, methodIndex, group, unitIndex)
            %COMPAREDISTRIBUTIONS 選んだ手法・学習パターンの列・Wafer（0 = すべて）で、Wafer 全面・学習データ・予測対象の
            %   計測値の分布と、予測対象の実測値と推定値の分布を、ヒストグラム・代表統計値・JS ダイバージェンスで比べる
            %   （alignest.distributionComparison）。引数を省くと画面の選択を使う。
            requireEstimates(app);
            c = app.Controls;
            if nargin >= 2
                c.distributionMethod.Value = methodIndex;
                c.distributionGroup.Value = char(group);
                c.distributionWafer.Value = unitIndex;
            end
            unitIndex = c.distributionWafer.Value;
            if unitIndex == 0
                unitIndex = 1:numel(app.Results.unitLabels);
            end
            selection = struct("methodIndex", c.distributionMethod.Value, "groups", string(c.distributionGroup.Value), ...
                "unitIndex", unitIndex);
            % 読み込んだ推定値では、Wafer 全面・学習の分布を学習データの行から作る（計測ファイルが無いので）
            imported = isImportedResults(app.Results);
            [estimates, messages] = collectWithProgress(app, selection, app.MapCache, Inf, "分布を比べる推定値を計算しています", ...
                imported);
            if nnz(estimates.role == "評価") == 0
                error('alignest:noEstimates', '評価点がありません（この組み合わせは推定できませんでした）。%s', ...
                    strjoin(messages, newline));
            end
            data = app.Data;
            if imported
                data = [];
            end
            comparison = alignest.distributionComparison(data, app.Results, selection, estimates);
            comparison.title = sprintf("%s｜%s｜Wafer %d 枚", app.Results.methods(selection.methodIndex).label, ...
                selection.groups, comparison.nWafers) + filterNote(app);
            app.Distribution = comparison;
            statsRows = cell(0, 9);
            jsRows = cell(0, 4);
            for axisName = ["X", "Y"]
                stats = comparison.(axisName).stats;
                for k = 1:height(stats)
                    statsRows(end + 1, :) = {char(axisName), char(stats.name(k)), stats.n(k), round4(stats.mean(k)), ...
                        round4(stats.std(k)), round4(stats.median(k)), round4(stats.min(k)), round4(stats.max(k)), ...
                        round4(stats.meanPlus3Sigma(k))}; %#ok<AGROW>
                end
                js = comparison.(axisName).js;
                for k = 1:height(js)
                    jsRows(end + 1, :) = {char(axisName), char(js.pair(k)), round4(js.js(k)), char(js.meaning(k))}; %#ok<AGROW>
                end
            end
            c.distributionTable.Data = statsRows;
            c.jsTable.Data = jsRows;
            drawDistributionHistograms(app);
        end

        function exportEstimatesTo(app, filePath, scope)
            %EXPORTESTIMATESTO 推定値（Mark ごとの計測値・推定値・残差）と残差の検定結果を Excel に書き出す。
            %   学習データの Mark も書き出し、その推定値・残差は空欄にする（「区分」の列で見分ける）。
            %   scope = "selected"：「推定値と誤差の分布」で選んだ手法・学習パターン・Wafer
            %           "all"     ：すべての手法・学習パターン・Wafer（評価で求めた推定値を使う。行が多いと書き出しに時間がかかる）
            requireEstimates(app);
            if isImportedResults(app.Results)
                error('alignest:importedResults', ['Excel から読み込んだ推定値は書き出せません（読み込んだファイル「%s」を' ...
                    'そのまま使ってください）。'], app.ImportedEstimates.file);
            end
            if nargin < 3
                scope = string(app.Controls.estimateScope.Value);
            end
            results = app.Results;
            if scope == "all"
                selection = struct("methodIndex", 1:numel(results.methods), "groups", results.groups, ...
                    "unitIndex", 1:numel(results.unitLabels));
                scopeText = "すべての手法・学習パターン・Wafer";
            else
                selection = analysisSelection(app);
                scopeText = "選んだ手法・学習パターン・Wafer";
            end
            % 評価で求めた推定値は記憶（app.MapCache）にあるので、推定し直さずに使う
            [estimates, messages, overlayPoints] = collectWithProgress(app, selection, app.MapCache, app.EXCEL_MAX_DATA_ROWS, ...
                "推定値を計算しています", true);
            analysis = alignest.residualAnalysis(estimates(estimates.role == "評価", :));
            notes = ["読み込んだファイル", app.FilePath; "書き出した範囲", scopeText; ...
                "手法", strjoin(string({results.methods(selection.methodIndex).label}), "、"); ...
                "学習パターンの列", strjoin(selection.groups, "、"); ...
                "Wafer", strjoin(results.unitLabels(selection.unitIndex), "、")];
            spec = resultSpec(app);
            if spec.scalar
                notes = [notes; "推定した値", "1変数：列「" + spec.name + "」（単位 " + spec.unit + "）。計測値・推定値・" + ...
                    "残差は X の列（Y の列は空欄）"];
            end
            if ~isempty(messages)
                notes = [notes; [repmat("推定できなかった組み合わせ", numel(messages), 1), messages(:)]];
            end
            if isfield(results, "overlayEvaluated") && results.overlayEvaluated
                notes = [notes; "Overlay 補正のモデル", results.overlayDescription];
            end
            [~, filterText, filterActive] = alignest.pointFilterMask(app.ResultFilter);
            if filterActive
                notes = [notes; "評価点の絞り込み", filterText + "（「推定値」シートの評価の行と検定。Overlay 残差のシートは" + ...
                    "絞り込まない）"];
            end
            alignest.exportEstimates(estimates, analysis, filePath, notes, overlayPoints=overlayPoints);
        end

        function showMap(app, unitIndex, planLabel, methodIndex, displayMode, content)
            %SHOWMAP 選んだ Wafer・学習パターン・手法の計測値・推定値・残差（content = "overlay" なら補正残差）を描く。
            c = app.Controls;
            if nargin >= 6
                c.mapContent.Value = char(content);
            end
            if nargin >= 2
                c.mapWafer.Value = unitIndex;
                c.mapPlan.Value = char(planLabel);
                c.mapMethod.Value = methodIndex;
            end
            if nargin >= 5
                c.mapMode.Value = char(displayMode);
            end
            c.mapView.Value = 'single';
            drawMap(app);
        end

        function comparison = drawLayoutComparison(app, methodIndex, xAxis)
            %DRAWLAYOUTCOMPARISON 「計測配置の比較」：1つの手法について、選び方（I 最適・D 最適・ランダム・優先順・
            %   Mark 単位）ごとに、計測する Mark の数（または学習 Shot 数）に対する指標の線を描き、人の選択・手動は点で
            %   描く（alignest.layoutComparison。指標と Wafer の集計は結果一覧の上の選択）。引数を省くと画面の選択。
            c = app.Controls;
            comparison = table();
            if isempty(app.Results)
                return
            end
            if nargin >= 2
                c.compareLayoutMethod.Value = methodIndex;
            end
            if nargin >= 3
                c.compareLayoutXAxis.Value = char(xAxis);
            end
            metric = string(c.metric.Value);
            statistic = string(c.statistic.Value);
            comparison = alignest.layoutComparison(app.Results, c.compareLayoutMethod.Value, metric, statistic);
            useMarks = string(c.compareLayoutXAxis.Value) == "marks" && any(isfinite(comparison.nMarks));
            x = comparison.nShots;
            axisLabel = "学習 Shot 数（Wafer の平均）";
            if useMarks
                x = comparison.nMarks;
                axisLabel = "計測する Mark の数（Wafer の平均）";
            end
            ax = c.compareLayoutAxes;
            cla(ax, 'reset');
            legend(ax, 'off');
            hold(ax, 'on');
            markers = {'o', 's', 'd', '^', 'v', 'p'};
            types = unique(comparison.type, 'stable');
            for k = 1:numel(types)
                rows = find(comparison.type == types(k) & isfinite(x) & isfinite(comparison.value));
                if isempty(rows)
                    continue
                end
                [~, order] = sort(x(rows));
                rows = rows(order);
                name = comparison.typeLabel(rows(1));
                if types(k) == "manual"
                    % 人の選択・手動はパターンごとに点を描き、名前を添える
                    points = plot(ax, x(rows), comparison.value(rows), markers{mod(k - 1, numel(markers)) + 1}, ...
                        'MarkerSize', 9, 'LineWidth', 1.5, 'LineStyle', 'none', 'DisplayName', name);
                    text(ax, x(rows), comparison.value(rows), "  " + comparison.group(rows), 'FontSize', 10, ...
                        'Color', points.Color, 'VerticalAlignment', 'bottom', 'Interpreter', 'none', 'HandleVisibility', 'off');
                else
                    plot(ax, x(rows), comparison.value(rows), ['-', markers{mod(k - 1, numel(markers)) + 1}], ...
                        'MarkerSize', 7, 'LineWidth', 1.5, 'DisplayName', name);
                end
            end
            hold(ax, 'off');
            grid(ax, 'on');
            box(ax, 'on');
            [names, labels] = alignest.metricNames(true, true, resultSpec(app));
            xlabel(ax, axisLabel);
            ylabel(ax, labels(names == metric));
            title(ax, sprintf("選び方の比較：%s（Wafer の%s）", comparison.Properties.UserData.methodLabel, ...
                statisticLabel(statistic)), 'Interpreter', 'none');
            if ~isempty(ax.Children)
                legend(ax, 'Location', 'best', 'Box', 'off', 'FontSize', 10);
            end
            ax.FontSize = app.AXES_FONT_SIZE;
            rows = cell(height(comparison), 7);
            for k = 1:height(comparison)
                rows(k, :) = {char(comparison.typeLabel(k)), char(comparison.group(k)), numberText(comparison.nShots(k), '%.1f'), ...
                    numberText(comparison.nMarks(k), '%.1f'), numberText(comparison.value(k), '%.3f'), ...
                    numberText(comparison.criterionI(k), '%.4g'), numberText(comparison.criterionD(k), '%.4g')};
            end
            c.compareLayoutTable.Data = rows;
            c.compareLayoutTable.ColumnName = cellstr(["選び方", "列", "学習 Shot 数", "計測 Mark 数", labels(names == metric), ...
                "I 基準", "D 基準"]);
            note = string(c.compareLayoutInfo.UserData);
            if comparison.Properties.UserData.nTypes < 2
                note = "⚠ この評価の選び方は1つです。" + note;
            end
            if string(c.compareLayoutXAxis.Value) == "marks" && ~useMarks
                note = note + "（この結果には計測する Mark の数が無いので、学習 Shot 数で描きました）";
            end
            c.compareLayoutInfo.Text = note + filterNote(app);
        end

        function conditions = addMapCondition(app, optionIndex, planLabel, methodIndex)
            %ADDMAPCONDITION 「5. Waferごとのマップ」の並べて比べる一覧に、条件（Wafer・平均 × 学習パターン × 手法）を足して
            %   並べて描く（並べ方を「一覧の条件を並べて比べる」にする）。引数を省くと画面の選択。同じ条件は足さない。
            c = app.Controls;
            if isempty(app.Results)
                error('alignest:noResults', '先に「3. 実行」で評価してください。');
            end
            if nargin >= 2
                c.mapWafer.Value = optionIndex;
                c.mapPlan.Value = char(planLabel);
                c.mapMethod.Value = methodIndex;
            end
            option = c.mapWafer.UserData(c.mapWafer.Value);
            condition = struct("option", c.mapWafer.Value, "plan", string(c.mapPlan.Value), "method", c.mapMethod.Value, ...
                "label", option.label + "｜" + string(c.mapPlan.Value) + "｜" + app.Results.methods(c.mapMethod.Value).label);
            known = arrayfun(@(item) item.option == condition.option && item.plan == condition.plan && ...
                item.method == condition.method, app.MapConditions);
            if ~any(known)
                if numel(app.MapConditions) >= app.MAX_COMPARE_PANELS
                    error('alignest:mapCompare', '並べて比べる条件は %d までです。「選んだ条件を外す」で減らしてから追加してください。', ...
                        app.MAX_COMPARE_PANELS);
                end
                app.MapConditions(end + 1) = condition;
            end
            refreshMapConditions(app);
            c.mapView.Value = 'compare';
            drawMap(app);
            conditions = app.MapConditions;
        end

        function removeMapConditions(app, indices)
            %REMOVEMAPCONDITIONS 並べて比べる一覧から条件（一覧の何番目か）を外して描き直す。
            app.MapConditions(indices) = [];
            refreshMapConditions(app);
            drawMap(app);
        end

        function targets = setTargetPoints(app, targets)
            %SETTARGETPOINTS 「6. 未知の座標の推定」の表を targets（alignest.targetTemplate の形）にする。
            app.Controls.targetTable.Data = targetCells(targets);
            app.TargetSelection = zeros(0, 1);
            onTargetEdited(app);
        end

        function targets = loadTargetPoints(app, filePath, sheetName)
            %LOADTARGETPOINTS 未知の座標の表（Excel・CSV）を読み、推定する点の表を置き換える（alignest.readTargetPoints）。
            if nargin < 3
                sheetName = "";
            end
            [targets, info] = alignest.readTargetPoints(filePath, sheetName);
            setTargetPoints(app, targets);
            sheetText = "";
            if info.sheet ~= ""
                sheetText = "（シート「" + info.sheet + "」）";
            end
            app.Controls.targetInfo.Text = sprintf('%s%s から %d 点を読み込みました。', info.file, sheetText, height(targets)) + ...
                " " + app.Controls.targetInfo.Text;
        end

        function targets = addTargetPoints(app, kind, varargin)
            %ADDTARGETPOINTS 推定する点の表に点を足す。
            %   addTargetPoints(app, "shots", markXmm, markYmm, markNo)  % 全 Shot の同じ位置（Shot は「Wafer」で選んだ
            %                                                           % Wafer、すべてなら最初の Wafer の並び）
            %   addTargetPoints(app, "grid", pitchMm, radiusMm)         % Wafer 上の格子
            %   addTargetPoints(app, "row")                             % 空の1行（画面で書き込む）
            c = app.Controls;
            existing = size(c.targetTable.Data, 1);
            switch string(kind)
                case "shots"
                    if isempty(app.Data)
                        error('alignest:noData', '先に「1. データの読み込み」で計測データを読み込んでください（Shot の並びを使います）。');
                    end
                    added = alignest.targetsAtShots(app.Data.units(max(c.targetWafer.Value, 1)), varargin{:});
                case "grid"
                    added = alignest.targetGrid(varargin{:});
                case "row"
                    added = alignest.targetTemplate(1);
                    added.name = "P" + string(existing + 1);
                otherwise
                    error('alignest:targetKind', '点の足し方は shots・grid・row のどれかです: %s', kind);
            end
            c.targetTable.Data = [c.targetTable.Data; targetCells(added)];
            onTargetEdited(app);
            targets = added;
        end

        function run = estimateTargets(app, unitChoice, trainingChoice, methodIndex)
            %ESTIMATETARGETS 「6. 未知の座標の推定」：表の点の推定値を求め、表・図・メッセージに出す。
            %   unitChoice：Wafer の番号（0 = すべての Wafer）、trainingChoice："all"（計測値のある全 Mark）または評価の
            %   学習パターンの名前、methodIndex：手法の番号（alignest.buildMethodList(app.Settings.methods) の何番目か）。
            %   省略すると画面で選んでいるもの。推定は alignest.predictTargets（評価と同じ推定、条件は今の設定）。
            if isempty(app.Data)
                error('alignest:noData', '先に「1. データの読み込み」で計測データを読み込んでください。');
            end
            refreshTargetChoices(app);
            c = app.Controls;
            if nargin >= 2
                c.targetWafer.Value = unitChoice;
            end
            if nargin >= 3
                c.targetTraining.Value = char(trainingChoice);
            end
            if nargin >= 4
                c.targetMethod.Value = methodIndex;
            end
            targets = currentTargets(app);
            methods = alignest.activeMethods(app.Settings);
            if isempty(methods)
                error('alignest:noMethods', '手法がありません。「2. 評価の設定」で比べる手法を選んでください。');
            end
            method = methods(c.targetMethod.Value);
            units = c.targetWafer.Value;
            if units == 0
                units = 1:numel(app.Data.units);
            end
            training = string(c.targetTraining.Value);
            app.Figure.Pointer = 'watch';
            drawnow;
            restore = onCleanup(@() set(app.Figure, 'Pointer', 'arrow'));
            estimates = table();
            results = cell(1, numel(units));
            for k = 1:numel(units)
                unit = app.Data.units(units(k));
                [plan, trainingText] = targetTraining(app, units(k), training);
                results{k} = alignest.predictTargets(unit, plan, method, app.Settings, targets);
                rows = results{k}.table;
                rows = addvars(rows, repmat(unit.label, height(rows), 1), 'Before', 1, 'NewVariableNames', "wafer");
                estimates = [estimates; rows]; %#ok<AGROW>
            end
            app.TargetRun = struct("estimates", estimates, "results", {results}, "unitIndex", units, "method", method, ...
                "trainingText", trainingText, "messages", targetMessages(results, estimates), "stale", false);
            showTargetRun(app);
            run = app.TargetRun;
        end

        function exportTargetsTo(app, filePath)
            %EXPORTTARGETSTO 最後に推定した未知の座標の推定値を Excel に書き出す（alignest.exportTargetEstimates）。
            if isempty(app.TargetRun)
                error('alignest:noTargets', '書き出す推定値がありません。先に「推定する」を押してください。');
            end
            run = app.TargetRun;
            labels = string({app.Data.units(run.unitIndex).label});
            evaluation = app.Settings.evaluation;
            conditions = sprintf('XY 1次を除く：%s、学習データの異常値の除外：%s', onOffText(evaluation.removeLinear), ...
                onOffText(evaluation.excludeOutliers));
            notes = ["Wafer", strjoin(labels, "・"); "学習データ", run.trainingText; ...
                "手法", run.method.label + "（" + run.method.id + "）"; "推定の条件", conditions; ...
                "画面のメッセージ", strjoin(run.messages, " ")];
            alignest.exportTargetEstimates(filePath, run.estimates, notes, alignest.valueSpec(app.Settings.data));
        end

        function captureTab(app, tabName, filePath)
            %CAPTURETAB タブを表示して画面の画像を保存する（説明資料・動作確認用）。
            % 画面の配置が描き終わるまで少し待ってから保存する（すぐ保存すると古い配置の絵になることがある）
            RENDER_WAIT_SECONDS = 1.5;
            app.TabGroup.SelectedTab = app.Tabs.(tabName);
            drawnow;
            pause(RENDER_WAIT_SECONDS);
            drawnow;
            exportapp(app.Figure, filePath);
        end
    end

    methods (Access = private)
        % ================= 1. データの読み込み =================
        function buildDataTab(app)
            grid = uigridlayout(app.Tabs.data, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 12, 'RowSpacing', 12);
            filePanel = uipanel(grid, 'Title', '計測データのファイル');
            fileGrid = uigridlayout(filePanel, [6, 4], 'ColumnWidth', {'fit', '1x', 260, 300}, ...
                'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit', 'fit'}, 'Padding', 10);
            help = uilabel(fileGrid, 'WordWrap', 'on', 'Text', ['Excel（.xlsx）または CSV。1行目に項目名、2行目からデータ。' ...
                '項目名がアライメント計測テーブルの標準（Operation, EqpId, LotID, Wafer, DateTime, shotNo, Direction, Xmm, Ymm, ' ...
                'Radius, markNo, markXmm, markYmm, measX, measY, StsX, StsY）なら自動で対応づけます。']);
            help.Layout.Row = 1;
            help.Layout.Column = [1, 4];
            label(fileGrid, 'ファイル', 2, [1, 2]);
            label(fileGrid, 'シート', 2, 3);
            label(fileGrid, '有効半径 [mm]（この半径以上の点は除く）', 2, 4);
            c.chooseFile = uibutton(fileGrid, 'Text', 'ファイルを選ぶ…', 'ButtonPushedFcn', @(~, ~) app.onChooseFile());
            c.chooseFile.Layout.Row = 3;
            c.chooseFile.Layout.Column = 1;
            c.filePath = uilabel(fileGrid, 'Text', 'まだ選んでいません', 'Tooltip', '');
            c.filePath.Layout.Row = 3;
            c.filePath.Layout.Column = 2;
            c.sheet = uidropdown(fileGrid, 'Items', {'—'}, 'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.onSheetChanged());
            c.sheet.Layout.Row = 3;
            c.sheet.Layout.Column = 3;
            c.validRadius = uieditfield(fileGrid, 'numeric', 'Value', app.Settings.data.validRadiusMm, 'Limits', [1, 1000], ...
                'ValueDisplayFormat', '%.1f', 'ValueChangedFcn', @(~, ~) app.invalidatePreparedData());
            c.validRadius.Layout.Row = 3;
            c.validRadius.Layout.Column = 4;
            onDataOption = @(~, ~) app.onDataOptionsChanged();
            c.excludeZeroMeasurements = uicheckbox(fileGrid, 'Text', '測定値 X・Y が両方 0 の行を除外', ...
                'Tooltip', 'measX = 0 かつ measY = 0 の入力行を、重複の平均前に除外します。', 'ValueChangedFcn', onDataOption);
            place(c.excludeZeroMeasurements, 4, [1, 2]);
            c.excludeUnmeasuredRecords = uicheckbox(fileGrid, 'Text', 'StsX または StsY が −1 の行を除外', ...
                'Tooltip', 'どちらかが−1なら行全体を除外します。オフの場合も、無効な軸の測定値は解析に使いません。', ...
                'ValueChangedFcn', onDataOption);
            place(c.excludeUnmeasuredRecords, 4, [3, 4]);
            label(fileGrid, 'Scan 方向（Direction）が無い行に付ける値', 5, 1);
            [ruleNames, ruleLabels] = alignest.directionRules();
            c.directionRule = uidropdown(fileGrid, 'Items', cellstr(ruleLabels), 'ItemsData', cellstr(ruleNames), ...
                'Tooltip', ['Direction の列が無いとき（または空の行）に、規則で Scan 方向 1・2 を付けます。' ...
                '行・列は Wafer ごとに Shot 中心の座標から数えます。付けた結果は「Shot レイアウト」で確かめられます。'], ...
                'ValueChangedFcn', onDataOption);
            place(c.directionRule, 5, 2);
            c.invertDirection = uicheckbox(fileGrid, 'Text', '付ける 1 と 2 を入れ替える', 'ValueChangedFcn', onDataOption);
            place(c.invertDirection, 5, 3);
            directionHelp = label(fileGrid, 'Direction の列に値がある行はそのまま使います。', 5, 4);
            directionHelp.FontColor = app.Palette.muted;
            % 座標の定義（Shot 中心＋Shot 内の位置、または絶対座標だけ）と、推定する値（X・Y 成分、または1つの列）
            label(fileGrid, '座標の定義', 6, 1);
            c.coordinateMode = uidropdown(fileGrid, 'Items', {'Shot 中心＋Shot 内の位置（Xmm・Ymm ＋ markXmm・markYmm）', ...
                'Wafer 上の絶対座標だけ（Xmm・Ymm が点の座標）'}, 'ItemsData', {'shotMark', 'absolute'}, ...
                'ValueChangedFcn', onDataOption, 'Tooltip', ['絶対座標だけ：Xmm・Ymm の項目に点の Wafer 上の座標の列を' ...
                '対応づけます。shotNo があれば同じ Shot の点の平均を Shot 中心に、markXmm・markYmm があれば' ...
                '点の座標 − markXmm を Shot 中心にします。どちらも無ければ点を1つずつ Shot として扱います。']);
            place(c.coordinateMode, 6, 2);
            valueGrid = uigridlayout(fileGrid, [1, 4], 'ColumnWidth', {'fit', '1x', 'fit', 70}, 'Padding', 0);
            place(valueGrid, 6, [3, 4]);
            label(valueGrid, '推定する値', 1, 1);
            c.valueColumn = uidropdown(valueGrid, 'Items', {'X・Y 成分（measX・measY）'}, 'ItemsData', {''}, ...
                'ValueChangedFcn', onDataOption, 'Tooltip', ['膜厚・線幅など、ファイルの1つの列を1変数として推定するときは' ...
                'その列を選びます（measX・measY は使いません。Overlay 補正の評価と RT モデルは使えません）。']);
            place(c.valueColumn, 1, 2);
            label(valueGrid, '単位', 1, 3);
            c.valueUnit = uieditfield(valueGrid, 'text', 'Value', char(app.Settings.data.valueUnit), ...
                'ValueChangedFcn', @(~, ~) app.onValueUnitChanged(), 'Tooltip', '1変数の単位（画面と Excel の表示だけ。換算はしません）');
            place(c.valueUnit, 1, 4);

            c.dataTabs = uitabgroup(grid);
            c.mappingTab = uitab(c.dataTabs, 'Title', '列の対応・座標の単位');
            lower = uigridlayout(c.mappingTab, [1, 2], 'ColumnWidth', {'1x', '1.1x'}, 'Padding', 8, 'ColumnSpacing', 12);
            mappingPanel = uipanel(lower, 'Title', '列の対応（標準の項目 ← ファイルの列）');
            mappingGrid = uigridlayout(mappingPanel, [3, 1], 'RowHeight', {'1x', 'fit', 'fit'}, 'Padding', 10);
            c.mapping = uitable(mappingGrid, 'ColumnName', {'標準の項目', '意味（変換後）', '必須', 'ファイルの列'}, ...
                'ColumnEditable', [false, false, false, true], 'RowName', {}, 'ColumnWidth', {100, 'auto', 50, 150}, ...
                'CellEditCallback', @(~, event) app.onMappingEdited(event));
            c.mappingStatus = uilabel(mappingGrid, 'WordWrap', 'on', ...
                'Text', '「ファイルを選ぶ…」で計測データを読み込んでください。');
            c.applyMapping = primaryButton(app, mappingGrid, 'この対応で読み込む', @(~, ~) app.onApplyMapping());
            c.applyMapping.Enable = 'off';

            right = uigridlayout(lower, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 0, 'RowSpacing', 12);
            unitPanel = uipanel(right, 'Title', '座標の単位（読み込むときに mm に変換する）');
            unitGrid = uigridlayout(unitPanel, [4, 3], 'RowHeight', {'fit', 'fit', 150, 'fit'}, ...
                'ColumnWidth', {'fit', 170, '1x'}, 'Padding', 8, 'RowSpacing', 4);
            unitHelp = label(unitGrid, ['mm でない列は「入力の単位」を選び直します（列名が Xmm でも中身が µm なら µm）。' ...
                '測定値 measX・measY は nm のまま変換しません。'], 1, [1, 3]);
            unitHelp.FontColor = app.Palette.muted;
            label(unitGrid, 'まとめて選ぶ', 2, 1);
            c.unitAll = uidropdown(unitGrid, 'Items', {'（列ごとに選ぶ）', 'すべて mm', 'すべて µm', 'すべて nm', 'すべて m'}, ...
                'ItemsData', {'', 'mm', 'um', 'nm', 'm'}, 'Value', '', 'ValueChangedFcn', @(~, ~) app.onUnitAll());
            place(c.unitAll, 2, 2);
            c.suggestUnits = uibutton(unitGrid, 'Text', '値の大きさから単位を推定', ...
                'Tooltip', 'Shot 中心は 10〜300 mm、Mark は 0.05〜50 mm に入る単位を選びます（目安の外の列だけ変えます）。', ...
                'ButtonPushedFcn', @(~, ~) app.onSuggestUnits());
            place(c.suggestUnits, 2, 3);
            c.unitTable = uitable(unitGrid, 'ColumnName', {'項目', '入力の単位', 'mm への倍率', 'ファイルの最大値', ...
                '変換後 [mm]', '確認'}, 'ColumnEditable', [false, true, false, false, false, false], 'RowName', {}, ...
                'ColumnWidth', {85, 95, 100, 120, 100, 'auto'}, 'CellEditCallback', @(~, ~) app.onUnitEdited());
            place(c.unitTable, 3, [1, 3]);
            c.unitStatus = uilabel(unitGrid, 'WordWrap', 'on', 'Text', '');
            place(c.unitStatus, 4, [1, 3]);
            resultPanel = uipanel(right, 'Title', '読み込み結果');
            resultGrid = uigridlayout(resultPanel, [1, 1], 'Padding', 10);
            c.summary = uitextarea(resultGrid, 'Editable', 'off', 'Value', {''});

            c.previewTab = uitab(c.dataTabs, 'Title', 'Wafer マップ（計測値）');
            previewGrid = uigridlayout(c.previewTab, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 8, 'RowSpacing', 8);
            previewControls = uigridlayout(previewGrid, [3, 11], 'ColumnWidth', {'fit', 260, 'fit', 170, 'fit', 80, 60, ...
                'fit', 'fit', 90, '1x'}, 'RowHeight', {'fit', 'fit', 'fit'}, 'Padding', 0);
            label(previewControls, '表示する Wafer・平均', 1, 1);
            c.previewWafer = uidropdown(previewControls, 'Items', {'—'}, 'ValueChangedFcn', @(~, ~) app.drawPreview());
            place(c.previewWafer, 1, 2);
            label(previewControls, '平均・楕円の単位', 1, 3);
            c.previewGroupBy = uidropdown(previewControls, 'Items', {'ALL（全 Wafer）'}, 'ItemsData', {'all'}, ...
                'ValueChangedFcn', @(~, ~) app.onPreviewGroupByChanged(), 'Tooltip', ['平均の図と共分散楕円を、どの単位で' ...
                '求めるか。ALL は全 Wafer、LotID・EqpId・Operation・その他の列は値ごと（その他の列は、その値の Mark だけを使う）。' ...
                '選ぶと「表示する Wafer・平均」に平均の選択肢が出ます。']);
            place(c.previewGroupBy, 1, 4);
            label(previewControls, '色の点', 1, 5);
            c.previewMarkerSize = markerSizeSpinner(app, previewControls, @(~, ~) app.drawPreview());
            place(c.previewMarkerSize, 1, 6);
            c.previewMarkerShape = markerShapeDropdown(previewControls, @(~, ~) app.drawPreview());
            place(c.previewMarkerShape, 1, 7);
            c.previewShotFrames = uicheckbox(previewControls, 'Text', 'Shot の枠', 'Value', true, ...
                'ValueChangedFcn', @(~, ~) app.drawPreview());
            place(c.previewShotFrames, 1, 8);
            label(previewControls, '共分散楕円', 1, 9);
            c.previewEllipse = ellipseDropdown(previewControls, @(~, ~) app.drawPreview());
            place(c.previewEllipse, 1, 10);
            c.previewEllipseOnly = ellipseOnlyCheckbox(previewControls, @(~, ~) app.drawPreview());
            place(c.previewEllipseOnly, 1, 11);
            c.previewScanFrames = uicheckbox(previewControls, 'Text', 'Shot の枠を Scan 方向で色分け（緑 ▲ = 1、紫 ▼ = 2）', ...
                'ValueChangedFcn', @(~, ~) app.drawPreview());
            place(c.previewScanFrames, 2, [1, 2]);
            c.previewRings = uicheckbox(previewControls, 'Text', '同心円の区切り（「2. 評価の設定」の制約）を描く', ...
                'ValueChangedFcn', @(~, ~) app.drawPreview(), 'Tooltip', ['I 最適・ランダムで同心円の制約を使うとき、' ...
                '区切りの半径（Shot 中心の半径 [mm]）を橙の一点鎖線で描きます。']);
            place(c.previewRings, 2, [3, 7]);
            c.previewInfo = uilabel(previewControls, 'WordWrap', 'on', 'Text', '');
            place(c.previewInfo, 3, [1, 11]);
            c.previewPanel = uipanel(previewGrid, 'BorderType', 'none');
            c.previewAxesGrid = uigridlayout(c.previewPanel, [1, 3], 'Padding', 0, 'ColumnSpacing', 8);
            c.previewAxes = [uiaxes(c.previewAxesGrid), uiaxes(c.previewAxesGrid), uiaxes(c.previewAxesGrid)];
            set(c.previewAxes, 'Visible', 'off');  % 読み込むまでは空の枠を出さない

            c.layoutTab = uitab(c.dataTabs, 'Title', 'Shot レイアウト');
            layoutGrid = uigridlayout(c.layoutTab, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 8, 'RowSpacing', 8);
            layoutControls = uigridlayout(layoutGrid, [2, 3], 'ColumnWidth', {'fit', 260, '1x'}, 'RowHeight', {'fit', 'fit'}, ...
                'Padding', 0);
            label(layoutControls, '表示する Wafer', 1, 1);
            c.layoutWafer = uidropdown(layoutControls, 'Items', {'—'}, 'ValueChangedFcn', @(~, ~) app.drawLayout());
            place(c.layoutWafer, 1, 2);
            c.layoutInfo = uilabel(layoutControls, 'WordWrap', 'on', 'Text', '');
            place(c.layoutInfo, 1, 3);
            c.resetScanDirections = uibutton(layoutControls, 'Text', 'Scan 方向の変更を元に戻す', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onResetScanDirections());
            place(c.resetScanDirections, 2, [1, 2]);
            c.scanEditInfo = uilabel(layoutControls, 'WordWrap', 'on', 'Text', ...
                '左の図の Shot をクリックすると、その shotNo の Scan 方向を 1 ↔ 2 で入れ替えます（すべての Wafer の同じ shotNo）。');
            place(c.scanEditInfo, 2, 3);
            c.layoutPanel = uipanel(layoutGrid, 'BorderType', 'none');
            layoutAxesGrid = uigridlayout(c.layoutPanel, [1, 2], 'ColumnWidth', {'1.25x', '1x'}, 'Padding', 0, ...
                'ColumnSpacing', 12);
            c.layoutAxes = [uiaxes(layoutAxesGrid), uiaxes(layoutAxesGrid)];
            set(c.layoutAxes, 'Visible', 'off');

            c.shotOverlayTab = uitab(c.dataTabs, 'Title', 'Shot 重ね合わせ');
            overlayGrid = uigridlayout(c.shotOverlayTab, [1, 2], 'ColumnWidth', {320, '1x'}, 'Padding', 8, 'ColumnSpacing', 12);
            overlayControls = uigridlayout(overlayGrid, [13, 1], 'RowHeight', {'fit', 110, 'fit', 'fit', 'fit', 'fit', ...
                'fit', 'fit', 'fit', 'fit', 'fit', '1x', 0}, 'Padding', 0, 'RowSpacing', 4);
            onOverlay = @(~, ~) app.drawShotOverlay();
            label(overlayControls, 'Wafer（Ctrl・Shift で複数選ぶ）', 1, 1);
            c.shotOverlayWafers = uilistbox(overlayControls, 'Items', {}, 'Multiselect', 'on', 'ValueChangedFcn', onOverlay);
            place(c.shotOverlayWafers, 2, 1);
            label(overlayControls, 'Wafer 成分を除く（Shot 中心の多項式）', 3, 1);
            c.shotOverlayWaferOrder = uidropdown(overlayControls, 'Items', {'除かない', '1次（並進・倍率・回転・直交度）', ...
                '2次', '3次'}, 'ItemsData', {0, 1, 2, 3}, 'ValueChangedFcn', onOverlay, ...
                'Tooltip', 'Wafer ごとに Shot 中心の座標の多項式を最小二乗で当てはめて除き、Shot 内の成分だけを重ねます。');
            place(c.shotOverlayWaferOrder, 4, 1);
            label(overlayControls, '共分散楕円（Shot・Wafer 間のばらつき。色は |相関係数|）', 5, 1);
            c.shotOverlayEllipse = ellipseDropdown(overlayControls, onOverlay);
            place(c.shotOverlayEllipse, 6, 1);
            c.shotOverlayIndividual = uicheckbox(overlayControls, 'Text', '個々の Shot の矢印も描く', 'Value', true, ...
                'ValueChangedFcn', onOverlay);
            place(c.shotOverlayIndividual, 7, 1);
            c.shotOverlayEllipseOnly = ellipseOnlyCheckbox(overlayControls, onOverlay);
            place(c.shotOverlayEllipseOnly, 8, 1);
            c.shotOverlayByScan = uicheckbox(overlayControls, 'Text', 'Scan 方向で分けた図も並べる', 'Value', false, ...
                'ValueChangedFcn', onOverlay, 'Tooltip', ['すべての Shot の図の右に、Scan 方向 1・2 の Shot だけを重ねた図を' ...
                '同じ矢印の倍率で並べます（Scan 方向はデータの Direction、または取り込みで付けた値）。']);
            place(c.shotOverlayByScan, 9, 1);
            label(overlayControls, '矢印の倍率 [mm/nm]（0 = 自動）', 10, 1);
            c.shotOverlayScale = uieditfield(overlayControls, 'numeric', 'Value', 0, 'Limits', [0, Inf], ...
                'ValueChangedFcn', onOverlay);
            place(c.shotOverlayScale, 11, 1);
            c.shotOverlayInfo = uitextarea(overlayControls, 'Editable', 'off', 'Value', {''});
            place(c.shotOverlayInfo, [12, 13], 1);
            % すべての Shot の図と、Scan 方向で分けた図（使わない列は幅 0）
            c.shotOverlayAxesGrid = uigridlayout(overlayGrid, [1, 3], 'ColumnWidth', {'1x', 0, 0}, 'Padding', 0, ...
                'ColumnSpacing', 8);
            c.shotOverlayAxes = [uiaxes(c.shotOverlayAxesGrid), uiaxes(c.shotOverlayAxesGrid), ...
                uiaxes(c.shotOverlayAxesGrid)];
            set(c.shotOverlayAxes, 'Visible', 'off');
            app.Controls = mergeStruct(app.Controls, c);
        end

        function onChooseFile(app)
            [fileName, folder] = uigetfile({'*.xlsx;*.xlsm;*.xls;*.csv', '計測データ (*.xlsx, *.xlsm, *.xls, *.csv)'}, ...
                '計測データのファイルを選ぶ');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.loadFile(fullfile(folder, fileName)), "ファイルを読み込めませんでした", ...
                "ファイルが Excel で開かれていないか、1行目が項目名になっているかを確かめてください。");
        end

        function onSheetChanged(app)
            runWithAlert(app, @() app.loadFile(app.FilePath, string(app.Controls.sheet.Value)), ...
                "シートを読み込めませんでした", "別のシートを選ぶか、ファイルの中身を確かめてください。");
        end

        function onApplyMapping(app)
            ok = runWithAlert(app, @() app.applyMapping(), "データを整理できませんでした", ...
                "「ファイルの列」と「座標の入力単位」を選び直してから、もう一度「この対応で読み込む」を押してください。");
            if ~ok
                app.Controls.mappingStatus.Text = "⚠ 読み込めませんでした。列の対応を確かめてください。";
                app.Controls.mappingStatus.FontColor = app.Palette.error;
            end
        end

        function fillMappingTable(app, mapping)
            % 必須・任意と項目の意味は、座標の定義と推定する値で変わる（alignest.standardColumns）
            columns = alignest.standardColumns(string(fieldOr(app.Settings.data, "coordinateMode", "shotMark")), ...
                string(fieldOr(app.Settings.data, "valueColumn", "")));
            options = [app.NONE_LABEL, string(app.RawTable.Properties.VariableNames)];
            data = cell(numel(columns), 4);
            for k = 1:numel(columns)
                data{k, 1} = columns(k).name;
                data{k, 2} = columns(k).meaning;
                data{k, 3} = char(ternary(columns(k).required, "必須", "任意"));
                value = mapping.(columns(k).name);
                if value == ""
                    value = app.NONE_LABEL;
                end
                data{k, 4} = char(value);
            end
            app.Controls.mapping.Data = data;
            app.Controls.mapping.ColumnFormat = {'char', 'char', 'char', cellstr(options)};
        end

        function fillUnitTable(app)
            % 座標の列ごとの入力単位・倍率・ファイルの値の大きさと、mm に直した値が目安に入るかを表に出す
            checks = alignest.checkCoordinateUnits(app.RawTable, currentMapping(app), app.Settings.data.coordinateUnits);
            data = cell(height(checks), 6);
            for k = 1:height(checks)
                data{k, 1} = char(checks.name(k));
                data{k, 2} = char(displayUnit(checks.unit(k)));
                data{k, 3} = sprintf('× %g', checks.scale(k));
                data{k, 4} = numberText(checks.maxInput(k));
                data{k, 5} = numberText(checks.maxMm(k));
                data{k, 6} = char(checks.message(k));
            end
            unitTable = app.Controls.unitTable;
            unitTable.Data = data;
            unitTable.ColumnFormat = {'char', app.UNIT_CHOICES, 'char', 'char', 'char', 'char'};
            removeStyle(unitTable);
            warnings = find(~checks.ok);
            status = app.Controls.unitStatus;
            if isempty(warnings)
                status.Text = "読み込むときに、選んだ単位から mm に変換します（ファイルは変更しません）。";
                status.FontColor = app.Palette.text;
            else
                addStyle(unitTable, uistyle('FontColor', app.Palette.error, 'FontWeight', 'bold'), 'cell', ...
                    [warnings, repmat(6, numel(warnings), 1)]);
                status.Text = "⚠ 大きさが目安の外の列があります。入力の単位を確かめてください（「値の大きさから単位を推定」で選べます）。";
                status.FontColor = app.Palette.error;
            end
        end

        function units = currentCoordinateUnits(app)
            units = app.Settings.data.coordinateUnits;
            values = app.Controls.unitTable.Data;
            for k = 1:size(values, 1)
                units.(values{k, 1}) = string(values{k, 2});
            end
            units = alignest.coordinateUnits(units);
        end

        function options = currentDataOptions(app)
            % 前処理を決める画面の値（変わったら読み込み直す）
            c = app.Controls;
            options = dataOptions(struct("validRadiusMm", c.validRadius.Value, "coordinateUnits", currentCoordinateUnits(app), ...
                "excludeZeroMeasurements", c.excludeZeroMeasurements.Value, ...
                "excludeUnmeasuredRecords", c.excludeUnmeasuredRecords.Value, ...
                "directionRule", string(c.directionRule.Value), "invertDirection", c.invertDirection.Value, ...
                "directionOverrideShots", app.Settings.data.directionOverrideShots, ...
                "directionOverrideValues", app.Settings.data.directionOverrideValues, ...
                "coordinateMode", string(c.coordinateMode.Value), "valueColumn", string(c.valueColumn.Value)));
        end

        function onMappingEdited(app, ~)
            fillUnitTable(app);  % 対応づける列が変わると、単位の確認に使う値も変わる
            invalidatePreparedData(app);
        end

        function onUnitEdited(app)
            app.Settings.data.coordinateUnits = currentCoordinateUnits(app);
            fillUnitTable(app);
            invalidatePreparedData(app);
        end

        function onUnitAll(app)
            unit = string(app.Controls.unitAll.Value);
            if unit == ""
                return
            end
            units = app.Settings.data.coordinateUnits;
            for name = string(fieldnames(units)).'
                units.(name) = unit;
            end
            app.Settings.data.coordinateUnits = alignest.coordinateUnits(units);
            app.Controls.unitAll.Value = '';  % 選んだ後は「列ごとに選ぶ」に戻す（個別に変えられるように）
            fillUnitTable(app);
            invalidatePreparedData(app);
        end

        function onSuggestUnits(app)
            runWithAlert(app, @() app.suggestCoordinateUnits(), "単位を推定できませんでした", ...
                "先にファイルを選び、列の対応を確かめてください。");
        end

        function invalidatePreparedData(app)
            app.Data = [];
            clearResults(app);
            clearTargetRun(app);
            app.Controls.summary.Value = {''};
            clearDataMaps(app);
            refreshFactorColumns(app);
            validateSettings(app);
            if ~isempty(app.RawTable)
                app.Controls.mappingStatus.Text = ['列の対応・座標の単位・有効半径・行の除外条件・Scan 方向の付与を確認し、' ...
                    '「この対応で読み込む」を押してください。'];
            end
            refreshRunSummary(app);
        end

        function onDataOptionsChanged(app)
            c = app.Controls;
            app.Settings.data.excludeZeroMeasurements = c.excludeZeroMeasurements.Value;
            app.Settings.data.excludeUnmeasuredRecords = c.excludeUnmeasuredRecords.Value;
            app.Settings.data.directionRule = string(c.directionRule.Value);
            app.Settings.data.invertDirection = c.invertDirection.Value;
            c.invertDirection.Enable = onOff(app.Settings.data.directionRule ~= "none");
            app.Settings.data.coordinateMode = string(c.coordinateMode.Value);
            app.Settings.data.valueColumn = string(c.valueColumn.Value);
            c.valueUnit.Enable = onOff(app.Settings.data.valueColumn ~= "");
            if ~isempty(app.RawTable) && width(app.RawTable) > 0
                fillMappingTable(app, currentMapping(app));   % 座標の定義・推定する値で必須の項目が変わる
            end
            invalidatePreparedData(app);
            updateEnabled(app);
        end

        function onValueUnitChanged(app)
            % 1変数の単位（表示だけ）。読み込み直す必要はないので、計測値の図だけ描き直す
            app.Settings.data.valueUnit = string(strtrim(app.Controls.valueUnit.Value));
            if ~isempty(app.Data)
                drawPreview(app);
            end
        end

        function refreshValueColumns(app)
            % 「推定する値」の選択肢：X・Y 成分と、ファイルの列（設定で選んである列がファイルに無くても残す）
            c = app.Controls;
            columns = strings(1, 0);
            if ~isempty(app.RawTable)
                columns = string(app.RawTable.Properties.VariableNames);
            end
            selected = string(fieldOr(app.Settings.data, "valueColumn", ""));
            if selected ~= "" && ~any(columns == selected)
                columns(end + 1) = selected;
            end
            c.valueColumn.Items = cellstr(["X・Y 成分（measX・measY）", "1変数：" + columns]);
            c.valueColumn.ItemsData = cellstr(["", columns]);
            c.valueColumn.Value = char(selected);
            c.valueUnit.Enable = onOff(selected ~= "");
        end

        function mapping = currentMapping(app)
            data = app.Controls.mapping.Data;
            mapping = struct();
            for k = 1:size(data, 1)
                value = string(data{k, 4});
                if value == app.NONE_LABEL
                    value = "";
                end
                mapping.(data{k, 1}) = value;
            end
        end

        function drawPreview(app)
            % 読み込んだ計測値：ベクトル（矢印）と、X・Y 成分ごとのヒートマップ（色）を並べる
            c = app.Controls;
            if isempty(app.Data)
                clearDataMaps(app);
                return
            end
            option = c.previewWafer.UserData(c.previewWafer.Value);
            pointsList = cell(1, numel(option.unitIndex));
            valuesList = cell(1, numel(option.unitIndex));
            for k = 1:numel(option.unitIndex)
                unit = app.Data.units(option.unitIndex(k));
                marks = unit.marks;
                values = [marks.measX, marks.measY];
                values(~marks.validX, 1) = NaN;
                values(~marks.validY, 2) = NaN;
                selected = true(size(marks.x));
                if option.column ~= ""
                    % その他の列の値ごとの平均：その値の Mark だけを使う
                    selected = marks.attributes(:, string(unit.attributeNames) == option.column) == option.level;
                end
                pointsList{k} = [marks.x(selected), marks.y(selected)];
                valuesList{k} = values(selected, :);
            end
            unit = app.Data.units(option.unitIndex(1));
            covariance = zeros(0, 3);
            if option.isGroup
                average = alignest.averageFields(pointsList, valuesList);
                points = average.points;
                values = average.mean;
                covariance = average.covariance;
            else
                points = pointsList{1};
                values = valuesList{1};
            end
            [centers, sizeMm] = shotFrameData(unit, c.previewShotFrames.Value || c.previewScanFrames.Value);
            directions = zeros(0, 1);
            if c.previewScanFrames.Value
                directions = nan(numel(unit.shots.Xmm), 1);
                if unit.hasDirection
                    directions = unit.shots.direction;
                end
            end
            rings = zeros(1, 0);
            if c.previewRings.Value
                rings = activeZoneEdges(app.Settings);
            end
            limit = colorLimitOf(values);
            radius = app.Settings.data.waferRadiusMm;
            ellipseSigma = c.previewEllipse.Value * option.isGroup;
            common = {'waferRadiusMm', radius, 'shotCenters', centers, 'shotSizeMm', sizeMm, 'showLegend', option.isGroup, ...
                'covariance', covariance, 'ellipseSigma', ellipseSigma, 'shotDirections', directions, 'ringRadiiMm', rings};
            spec = alignest.valueSpec(app.Settings.data);
            if spec.scalar
                % 1変数：値の色の図を1枚（色の範囲は値の最小〜最大）。X・Y のベクトル・楕円は描かない
                c.previewAxesGrid.ColumnWidth = {'1x', 0, 0};
                common{find(strcmp(common, 'ellipseSigma')) + 1} = 0;
                alignest.plot.waferMap(c.previewAxes(1), points, values, common{:}, mode="X", ...
                    colorRange=valueRange(values(:, 1)), colorTitle=spec.name + " [" + spec.unit + "]", ...
                    markerSize=c.previewMarkerSize.Value, markerShape=c.previewMarkerShape.Value, ...
                    titleText=ternary(option.isGroup, spec.name + " の平均", spec.name));
                set(c.previewAxes(1), 'Visible', 'on', 'FontSize', app.AXES_FONT_SIZE);
                arrayfun(@(ax) cla(ax, 'reset'), c.previewAxes(2:3));
                set(c.previewAxes(2:3), 'Visible', 'off');
                c.previewInfo.Text = sprintf('%s（1変数）を色で描いています（単位 %s）。', spec.name, spec.unit);
                return
            end
            c.previewAxesGrid.ColumnWidth = {'1x', '1x', '1x'};
            % name=value の書き方は最後に置く決まりなので、共通の指定（common）を先に渡す
            alignest.plot.waferMap(c.previewAxes(1), points, values, common{:}, ...
                scaleMmPerNm=alignest.plot.vectorScale(values), titleText=ternary(option.isGroup, "計測値の平均（ベクトル）", ...
                "計測値（ベクトル）"), showArrows=~(c.previewEllipseOnly.Value && ellipseSigma > 0));
            alignest.plot.waferMap(c.previewAxes(2), points, values, common{:}, mode="X", colorLimit=limit, ...
                markerSize=c.previewMarkerSize.Value, markerShape=c.previewMarkerShape.Value, titleText="X 成分（色）");
            alignest.plot.waferMap(c.previewAxes(3), points, values, common{:}, mode="Y", colorLimit=limit, ...
                markerSize=c.previewMarkerSize.Value, markerShape=c.previewMarkerShape.Value, titleText="Y 成分（色）");
            set(c.previewAxes, 'Visible', 'on', 'FontSize', app.AXES_FONT_SIZE);
            % 楕円と重ねる矢印は単色（色の目盛りは楕円の |r|）、楕円が無ければ矢印の色は長さ
            arrowText = ternary(ellipseSigma > 0, "矢印は単色（右の目盛りは楕円の |r|）", "矢印の色は長さ |v|");
            extras = "";
            if ~isempty(directions)
                extras = extras + "枠の色は Scan 方向（緑 ▲ = 1、紫 ▼ = 2）。";
            end
            if ~isempty(rings)
                extras = extras + "橙の一点鎖線は同心円の区切り（" + strjoin(string(rings), "・") + " mm）。";
            elseif c.previewRings.Value
                extras = extras + "同心円の制約は使っていません（「2. 評価の設定」で I 最適・ランダムと区切りを選ぶと描きます）。";
            end
            c.previewInfo.Text = sprintf("%s：%d 点。点線は半径 %g mm%s。%s。色の図の範囲は X・Y 共通で ±%.2f nm。%s", option.label, ...
                size(points, 1), radius, ternary(c.previewShotFrames.Value, "、灰色の枠は Shot", ""), arrowText, limit, ...
                ternary(option.isGroup, "座標ごとに Wafer 間で平均（楕円は Wafer 間のばらつき、色は X・Y の相関係数の絶対値 |r|）。", "")) + ...
                extras;
        end

        function refreshPreviewGroupBy(app)
            % 平均・楕円の単位の選択肢（ALL・LotID・EqpId・Operation・その他の列）と、表示する Wafer・平均の選択肢
            c = app.Controls;
            columns = string(app.Data.attributeNames);
            keys = ["all", "lotId", "eqpId", "operation", "slotParity", "col:" + columns];
            labels = ["ALL（全 Wafer）", "LotID", "EqpId", "Operation", "Slot の偶奇（Wafer ID のハイフンの後の番号）", ...
                "その他の列：" + columns];
            previous = string(c.previewGroupBy.Value);
            c.previewGroupBy.Items = cellstr(labels);
            c.previewGroupBy.ItemsData = cellstr(keys);
            if any(keys == previous)
                c.previewGroupBy.Value = char(previous);
            end
            setGroupItems(c.previewWafer, alignest.groupOptions(app.Data.units, string(c.previewGroupBy.Value)));
        end

        function onPreviewGroupByChanged(app)
            % 単位を変えたら、その単位の最初の平均を表示する
            if isempty(app.Data)
                return
            end
            refreshPreviewGroupBy(app);
            c = app.Controls;
            firstGroup = find([c.previewWafer.UserData.isGroup], 1);
            if ~isempty(firstGroup)
                c.previewWafer.Value = firstGroup;
            end
            drawPreview(app);
        end

        function drawLayout(app)
            % Shot の配置（枠・shotNo・Scan 方向）と、Shot 内の Mark の位置・番号
            c = app.Controls;
            if isempty(app.Data)
                return
            end
            unit = app.Data.units(c.layoutWafer.Value);
            alignest.plot.shotLayout(c.layoutAxes(1), unit, app.Settings.data.waferRadiusMm);
            alignest.plot.markLayout(c.layoutAxes(2), unit);
            set(c.layoutAxes, 'Visible', 'on', 'FontSize', app.AXES_FONT_SIZE);
            % Shot をクリックして Scan 方向を入れ替える（図の中の線・文字はクリックを図に通す）
            ax = c.layoutAxes(1);
            disableDefaultInteractivity(ax);
            set(ax.Children, 'HitTest', 'off');
            ax.ButtonDownFcn = @(~, event) app.onLayoutShotClicked(event.IntersectionPoint);
            changed = numel(app.Settings.data.directionOverrideShots);
            c.resetScanDirections.Enable = onOff(changed > 0);
            c.scanEditInfo.Text = "左の図の Shot をクリックすると、その shotNo の Scan 方向を 1 ↔ 2 で入れ替えます" + ...
                "（すべての Wafer の同じ shotNo）。" + ternary(changed > 0, sprintf("変えた Shot：%s", ...
                strjoin(compose("%g→S%d", app.Settings.data.directionOverrideShots(:), ...
                app.Settings.data.directionOverrideValues(:)), "、")), "");
            c.layoutInfo.Text = sprintf(['%s：%d Shot・%d Mark、Shot の大きさ %.3f × %.3f mm、Scan 方向 %s。' ...
                '左の数字は shotNo、右は Shot 中心から見た Mark の位置（M の後が markNo）。'], unit.label, ...
                numel(unit.shots.Xmm), numel(unit.marks.x), unit.shotSizeMm, ...
                ternary(unit.hasDirection, "あり（S1・S2 で表示）", "なし"));
        end

        function showOverlayPanels(app, count)
            % Shot 重ね合わせの図を count 枚だけ見せる（残りは消して幅 0 にする）
            c = app.Controls;
            widths = repmat({0}, 1, numel(c.shotOverlayAxes));
            widths(1:count) = {'1x'};
            if count == 0
                widths{1} = '1x';
            end
            c.shotOverlayAxesGrid.ColumnWidth = widths;
            for k = count + 1:numel(c.shotOverlayAxes)
                ax = c.shotOverlayAxes(k);
                cla(ax, 'reset');
                colorbar(ax, 'off');
                legend(ax, 'off');
                ax.Visible = 'off';
            end
        end

        function clearDataMaps(app)
            c = app.Controls;
            if ~isfield(c, 'layoutAxes')
                return
            end
            for ax = [c.previewAxes, c.layoutAxes, c.shotOverlayAxes]
                cla(ax, 'reset');
                colorbar(ax, 'off');
                legend(ax, 'off');
                ax.Visible = 'off';
            end
            c.previewInfo.Text = '';
            c.layoutInfo.Text = '';
            c.shotOverlayInfo.Value = {''};
            if isfield(c, 'measurePanel')
                clearMeasurePanel(app);
            end
        end

        % ================= 2. 評価の設定 =================
        function buildSettingsTab(app)
            grid = uigridlayout(app.Tabs.settings, [2, 2], 'RowHeight', {'1x', 'fit'}, ...
                'ColumnWidth', {'1x', '1.45x'}, 'Padding', 12, 'ColumnSpacing', 12);
            onChange = @(~, ~) app.onSettingsChanged();

            samplingPanel = uipanel(grid, 'Title', '学習に使う Shot（この Shot の計測値で、残りの Shot を推定する）');
            s = uigridlayout(samplingPanel, [43, 2], 'RowHeight', repmat({'fit'}, 1, 43), 'ColumnWidth', {'1x', '1x'}, ...
                'Padding', 10, 'RowSpacing', 6, 'Scrollable', 'on');
            label(s, '選び方（Ctrl・Shift で複数選ぶと、選び方どうしを同じ評価の中で比べる）', 1, [1, 2]);
            c.samplingMethod = uilistbox(s, 'Items', {'制約付き I 最適（前回の評価と同じ）', '制約付き D 最適', ...
                '制約つきランダム', '手動・人の選択（Excel の計測マップから読み込める）', 'ファイルの優先順で指定', ...
                'Mark 単位の I 最適（全 Shot で1点以上を計測）'}, 'ItemsData', {'ioptimal', 'doptimal', 'random', 'manual', ...
                'file', 'mark'}, 'Multiselect', 'on', 'Value', {'ioptimal'}, 'ValueChangedFcn', onChange, ...
                'Tooltip', ['D 最適：I 最適と同じ制約で det(M) を大きくする組。Mark 単位：計測する Shot ではなく Mark を選ぶ' ...
                '（全 Shot を1点以上計測し、Mark 番号の割合を全計測とそろえる）。複数選ぶと、結果一覧の「計測配置の比較」で' ...
                '選び方どうしを比べられます。']);
            place(c.samplingMethod, 2, [1, 2]);
            s.RowHeight{2} = 160;
            label(s, '学習 Shot 数（開始から終了まで、刻みごとに増やして比べる）', 3, 1);
            c.countBy = uidropdown(s, 'Items', {'Shot 数で決める', '計測率 [%] で決める'}, 'ItemsData', {'shots', 'rate'}, ...
                'ValueChangedFcn', onChange, 'Tooltip', ['計測率は、Wafer の計測値のある Shot（候補）に対する学習 Shot の' ...
                '割合です。Wafer ごとに 候補 Shot 数 × 計測率 を四捨五入した数の Shot を学習に使います。']);
            place(c.countBy, 3, 2);
            sweep = uigridlayout(s, [3, 4], 'RowHeight', {'fit', 'fit', 'fit'}, 'ColumnWidth', {'fit', '1x', '1x', '1x'}, ...
                'Padding', 0, 'RowSpacing', 2);
            place(sweep, 4, [1, 2]);
            label(sweep, '開始', 1, 2);
            label(sweep, '終了', 1, 3);
            label(sweep, '刻み（スイープ幅）', 1, 4);
            label(sweep, 'Shot 数', 2, 1);
            c.nShotsStart = shotCountSpinner(sweep, onChange);
            place(c.nShotsStart, 2, 2);
            c.nShotsEnd = shotCountSpinner(sweep, onChange);
            place(c.nShotsEnd, 2, 3);
            c.nShotsStep = shotCountSpinner(sweep, onChange);
            place(c.nShotsStep, 2, 4);
            label(sweep, '計測率 [%]', 3, 1);
            c.rateStart = rateField(sweep, onChange);
            place(c.rateStart, 3, 2);
            c.rateEnd = rateField(sweep, onChange);
            place(c.rateEnd, 3, 3);
            c.rateStep = rateField(sweep, onChange);
            place(c.rateStep, 3, 4);
            c.nShotsList = uilabel(s, 'WordWrap', 'on', 'Text', '');
            place(c.nShotsList, 5, [1, 2]);
            c.nShotsError = errorLabel(app, s, 6, [1, 2]);
            label(s, 'ランダムの繰り返し回数', 7, 1);
            label(s, '乱数の種', 7, 2);
            c.randomRepeats = uispinner(s, 'Limits', [1, 1000], 'RoundFractionalValues', 'on', 'ValueChangedFcn', onChange);
            place(c.randomRepeats, 8, 1);
            c.seed = uieditfield(s, 'numeric', 'Limits', [0, 2^32 - 1], 'RoundFractionalValues', 'on', ...
                'ValueDisplayFormat', '%d', 'ValueChangedFcn', onChange);
            place(c.seed, 8, 2);
            label(s, '手動・人の選択（1行に1パターン。「名前: shotNo…」、shotNo は空白・カンマ区切り）', 9, 1);
            c.loadLayouts = uibutton(s, 'Text', '人の選択を Excel から読み込む…', 'ButtonPushedFcn', @(~, ~) app.onLoadLayouts(), ...
                'Tooltip', ['shotNo の列と、パターンごとの列（1 = 計測する、0 = しない）の Excel（「計測マップを Excel に' ...
                '書き出す…」と同じ形）を読み、下の欄に1パターン1行で入れます。選び方の「手動・人の選択」も選びます。']);
            place(c.loadLayouts, 9, 2);
            c.manualPlans = uitextarea(s, 'ValueChangedFcn', onChange);
            place(c.manualPlans, 10, [1, 2]);
            s.RowHeight{10} = 90;
            c.manualError = errorLabel(app, s, 11, [1, 2]);
            c.loadPriority = uibutton(s, 'Text', '優先順のファイルを読み込む…', 'ButtonPushedFcn', @(~, ~) app.onLoadPriority(), ...
                'Tooltip', ['Shot 番号と優先度の表（Excel・CSV）。行の順に Shot を足して学習 Shot 数にします。' ...
                '優先度 1 = 必ず計測、0 = 計測しない（評価だけに使う）。']);
            place(c.loadPriority, 12, 1);
            c.priorityInfo = uilabel(s, 'WordWrap', 'on', 'Text', 'まだ読み込んでいません');
            place(c.priorityInfo, 12, 2);
            c.priorityError = errorLabel(app, s, 13, [1, 2]);
            heading(s, '必ず計測する Shot（I 最適・ランダム。残りの Shot を選ぶ）', 14);
            label(s, '必ず計測する shotNo（空白またはカンマで区切る）', 15, [1, 2]);
            c.requiredShots = uieditfield(s, 'text', 'ValueChangedFcn', onChange, 'Tooltip', ['ここに書いた Shot を' ...
                '必ず学習に入れ、残りを I 最適（またはランダム）で選びます（拡張 I 最適計画）。']);
            place(c.requiredShots, 16, [1, 2]);
            c.requireOuter = uicheckbox(s, 'Text', '最外周の Shot をすべて必ず計測する（上下左右のどこかに隣の Shot が無い Shot）', ...
                'ValueChangedFcn', onChange);
            place(c.requireOuter, 17, [1, 2]);
            c.requiredInfo = uilabel(s, 'WordWrap', 'on', 'Text', '');
            place(c.requiredInfo, 18, [1, 2]);
            c.requiredError = errorLabel(app, s, 19, [1, 2]);
            heading(s, '制約（I 最適・ランダム）', 20);
            radiusMm = app.Settings.data.waferRadiusMm;
            label(s, sprintf('同心円の区切り：Shot 中心の半径 [mm]（Wafer 半径 %g mm が前提。空白区切り）', radiusMm), 21, [1, 2]);
            c.zoneEdges = uieditfield(s, 'text', 'ValueChangedFcn', onChange, 'Tooltip', sprintf(['Shot 中心の Wafer 中心からの' ...
                '距離 [mm] で区画を分け、区画ごとの Shot 数をそろえます（例：67.5 105 → 0〜67.5・67.5〜105・105 mm 以上の' ...
                '3区画）。0 より大きく %g mm より小さい値。使わないなら空欄。'], radiusMm));
            place(c.zoneEdges, 22, [1, 2]);
            c.zoneError = errorLabel(app, s, 23, [1, 2]);
            c.quadrants = uicheckbox(s, 'Text', '4象限の Shot 数をそろえる', 'ValueChangedFcn', onChange);
            place(c.quadrants, 24, [1, 2]);
            c.scanConstraint = uicheckbox(s, 'Text', 'Scan 方向ごとの Shot 数をそろえる', 'ValueChangedFcn', onChange);
            place(c.scanConstraint, 25, [1, 2]);
            label(s, '許容幅（各区画の Shot 数の ±）', 26, 1);
            label(s, 'I 最適の基準モデル（XY 多項式の次数）', 26, 2);
            c.slack = uispinner(s, 'Limits', [0, 10], 'RoundFractionalValues', 'on', 'ValueChangedFcn', onChange);
            place(c.slack, 27, 1);
            c.designOrder = uispinner(s, 'Limits', [1, 8], 'RoundFractionalValues', 'on', 'ValueChangedFcn', onChange);
            place(c.designOrder, 27, 2);
            label(s, '交換法の初期配置の数（多いほど良い組が見つかるが遅い。時間は数にほぼ比例）', 28, [1, 2]);
            % 入力欄と時間の目安（目安の文が長くても入力欄が縦に伸びないように、小さな格子に入れる）と、Mark 単位の計画
            exchangeGrid = uigridlayout(s, [6, 2], 'ColumnWidth', {'1x', '1x'}, 'RowHeight', repmat({'fit'}, 1, 6), ...
                'Padding', 0, 'RowSpacing', 2);
            place(exchangeGrid, 29, [1, 2]);
            c.exchangeStarts = uispinner(exchangeGrid, 'Limits', [1, 100], 'RoundFractionalValues', 'on', ...
                'ValueChangedFcn', onChange, 'Tooltip', ['初期配置 1 つあたりの時間の目安は 約 0.01 秒 × 学習 Shot 数' ...
                '（候補 99 Shot の模擬データで測った値）。10 → 20 にすると学習パターンを作る時間は約 2 倍。模擬データでは' ...
                ' 10〜20 を超えると I 基準はほとんど良くならなかった。']);
            place(c.exchangeStarts, 1, 1);
            c.exchangeInfo = uilabel(exchangeGrid, 'WordWrap', 'on', 'Text', '');
            place(c.exchangeInfo, 2, [1, 2]);
            markLabel = label(exchangeGrid, ['Mark 単位の I 最適：1 Shot あたりの計測 Mark 数（空白区切りで複数。' ...
                '1 = 全 Shot で1点）'], 3, [1, 2]);
            markLabel.FontWeight = 'bold';
            c.markPerShot = uieditfield(exchangeGrid, 'text', 'ValueChangedFcn', onChange, 'Tooltip', ['計測する Mark の数 = ' ...
                'この値 × 候補 Shot 数（四捨五入）。全 Shot を1点以上計測し、残りの Mark を I 最適で選びます。']);
            place(c.markPerShot, 4, 1);
            c.markRatio = uicheckbox(exchangeGrid, 'Text', 'Mark 番号ごとの計測割合を全計測とそろえる', 'ValueChangedFcn', onChange, ...
                'Tooltip', ['Mark 番号ごとの計測する Mark の数を、候補の全 Mark での割合 × 計測する数 ± 許容幅に収めます' ...
                '（例：4 Mark なら各 25%）。']);
            place(c.markRatio, 5, [1, 2]);
            c.markError = errorLabel(app, exchangeGrid, 6, [1, 2]);
            heading(s, '評価', 30);
            label(s, sprintf('外周とみなす Mark の半径 [mm]（この半径以上を外周。Wafer 半径 %g mm が前提）', radiusMm), 31, [1, 2]);
            c.outerRadius = uieditfield(s, 'numeric', 'Limits', [0, radiusMm], 'ValueDisplayFormat', '%.1f', ...
                'ValueChangedFcn', onChange, 'Tooltip', ['Mark の Wafer 中心からの距離 [mm]。結果一覧の「外周の RMSE」' ...
                '「内側の RMSE」と、散布図の色分け「外周・内側」の境目です。']);
            place(c.outerRadius, 32, 1);
            c.removeLinear = uicheckbox(s, 'ValueChangedFcn', onChange, ...
                'Text', 'XY 1次（並進・倍率・回転・直交度）を除いてから推定する');
            place(c.removeLinear, 33, [1, 2]);
            outlierGrid = uigridlayout(s, [2, 3], 'ColumnWidth', {'1x', 'fit', 70}, 'RowHeight', {'fit', 'fit'}, 'Padding', 0, ...
                'RowSpacing', 2);
            place(outlierGrid, 34, [1, 2]);
            c.excludeOutliers = uicheckbox(outlierGrid, 'ValueChangedFcn', onChange, ...
                'Text', '学習データの異常値を除いて推定する（下の判定のしかたと n）', ...
                'Tooltip', ['Wafer・学習パターンごとに、学習点の中心とばらつきを X・Y 別に求め、|値 − 中心| が n × ばらつき' ...
                'を超える軸が1つでもある Mark を、X・Y の両方の学習データから除きます。']);
            place(c.excludeOutliers, 1, [1, 3]);
            c.outlierMethod = uidropdown(outlierGrid, 'Items', {'平均と σ（nσ）', '中央値と MAD（n × 1.4826 × MAD）'}, ...
                'ItemsData', {'sigma', 'mad'}, 'ValueChangedFcn', onChange, 'Tooltip', ['MAD = 中央値からの差の絶対値の中央値。' ...
                '1.4826 を掛けると正規分布では σ と同じ大きさになり、外れ値に引きずられにくい判定になります。']);
            place(c.outlierMethod, 2, 1);
            label(outlierGrid, 'n =', 2, 2);
            c.outlierSigma = uieditfield(outlierGrid, 'numeric', 'Limits', [0, Inf], 'LowerLimitInclusive', 'off', ...
                'ValueDisplayFormat', '%g', 'ValueChangedFcn', onChange);
            place(c.outlierSigma, 2, 3);
            c.recordTiming = uicheckbox(s, 'ValueChangedFcn', onChange, ...
                'Text', '条件ごとの処理時間を記録する（1 枚あたりの推定時間）', ...
                'Tooltip', ['手法 × 学習パターンごとに、1 枚（X・Y）の推定にかかった秒数を集計し、「4. 結果一覧」の指標と' ...
                'Excel の「処理時間」シートに出します。各手法の初回は予備の推定を1回して、読み込みの時間を除きます。']);
            place(c.recordTiming, 35, [1, 2]);
            heading(s, 'Overlay 補正の評価（推定誤差で Overlay 残差がどれだけ増えるか）', 36);
            label(s, 'Wafer 成分（Shot 中心の座標の多項式、または式）', 37, 1);
            label(s, 'Shot 共通成分（全 Shot で同じ Shot 内の補正）', 37, 2);
            c.overlayWafer = uidropdown(s, 'Items', {'なし', '1次（並進・倍率・回転・直交度）', '2次', '3次', '4次', '5次', ...
                '式を入力'}, 'ItemsData', {0, 1, 2, 3, 4, 5, app.FORMULA_CHOICE}, 'ValueChangedFcn', onChange);
            place(c.overlayWafer, 38, 1);
            c.overlayShotCommon = uidropdown(s, 'Items', {'なし', '1次（k1〜k6）', '式を入力'}, ...
                'ItemsData', {'none', 'linear', 'formula'}, 'ValueChangedFcn', onChange, ...
                'Tooltip', ['1次：Shot 内の座標（markXmm・markYmm）の1次の補正（k1〜k6：並進・倍率・回転・直交度）。' ...
                '式を入力：下の dx・dy の式。どちらも全 Shot で同じ補正量にします。']);
            place(c.overlayShotCommon, 38, 2);
            formulaHelp = ['項を + でつなぎ、各項は係数と x・y のべきの積（例：k1 + k3*x + k5*y + k7*x^2 + k9*x*y）。' ...
                '係数の値は最小二乗で求めるので、係数の名前・符号は補正量に影響しません。'];
            [c.overlayWaferDx, c.overlayWaferDy] = formulaFields(s, 39, 1, onChange, ['x・y は Shot 中心の座標' ...
                '（Wafer 中心から）。' formulaHelp]);
            [c.overlayShotDx, c.overlayShotDy] = formulaFields(s, 39, 2, onChange, ['x・y は Shot 内の座標' ...
                '（markXmm・markYmm、Shot 中心から）。' formulaHelp]);
            label(s, 'Shot ごとの成分', 40, 1);
            c.overlayPerShot = uidropdown(s, 'Items', {'なし', '並進（k1・k2）', '1次（k1〜k6）', '式を入力'}, ...
                'ItemsData', {'none', 'translation', 'linear', 'formula'}, 'ValueChangedFcn', onChange, ...
                'Tooltip', '式を入力：下の dx・dy の式の係数を、Shot ごとに別々に求めます（x・y は Shot 内の座標）。');
            place(c.overlayPerShot, 41, 1);
            [c.overlayPerShotDx, c.overlayPerShotDy] = formulaFields(s, 42, 1, onChange, ['x・y は Shot 内の座標' ...
                '（markXmm・markYmm、Shot 中心から）。係数は Shot ごとに求めます。' formulaHelp]);
            c.overlayHelp = label(s, '', [40, 42], 2);
            c.overlayHelp.FontColor = app.Palette.muted;
            c.overlayHelp.UserData = "muted";
            c.overlayFormulaError = errorLabel(app, s, 43, [1, 2]);

            methodPanel = uipanel(grid, 'Title', '比べる手法');
            m = uigridlayout(methodPanel, [27, 4], 'RowHeight', repmat({'fit'}, 1, 27), 'ColumnWidth', {'1x', '1x', '1x', '1x'}, ...
                'Padding', 10, 'RowSpacing', 6, 'Scrollable', 'on');
            presetGrid = uigridlayout(m, [1, 3], 'Padding', 0, 'ColumnWidth', {'fit', 'fit', 'fit'});
            place(presetGrid, 1, [1, 4]);
            uibutton(presetGrid, 'Text', '推奨の組み合わせ', 'ButtonPushedFcn', @(~, ~) app.onPreset("recommended"));
            uibutton(presetGrid, 'Text', 'すべて選ぶ', 'ButtonPushedFcn', @(~, ~) app.onPreset("all"));
            uibutton(presetGrid, 'Text', 'すべて外す', 'ButtonPushedFcn', @(~, ~) app.onPreset("none"));
            label(m, '説明変数（GPR・TPS・RBF・Kriging・GAM に共通）', 2, [1, 4]);
            c.featureXY = uicheckbox(m, 'Text', 'X, Y', 'ValueChangedFcn', onChange);
            place(c.featureXY, 3, 1);
            c.featureXYR = uicheckbox(m, 'Text', 'X, Y, 半径', 'ValueChangedFcn', onChange);
            place(c.featureXYR, 3, 2);
            factorGrid = uigridlayout(m, [5, 5], 'Padding', 0, 'RowSpacing', 4, ...
                'RowHeight', {'fit', 'fit', 'fit', 'fit', 72}, 'ColumnWidth', {'fit', 'fit', 'fit', 'fit', '1x'});
            place(factorGrid, 4, [1, 4]);
            label(factorGrid, ['質的変数（GPR・GAM と、TPS・RBF・Kriging の Backfitting で使う。' ...
                'ANOVA では選ばなくても Scan・Mark・Shot 行を調べる）'], 1, [1, 5]);
            label(factorGrid, 'X 成分', 2, 1);
            c.factorScan = uicheckbox(factorGrid, 'Text', 'Scan 方向', 'ValueChangedFcn', onChange, ...
                'Tooltip', 'Direction の列、または「Scan 方向が無い行に付ける値」で付けた値。値が無い Wafer では使いません。');
            place(c.factorScan, 2, 2);
            c.factorMark = uicheckbox(factorGrid, 'Text', 'Mark 番号', 'ValueChangedFcn', onChange);
            place(c.factorMark, 2, 3);
            rowTooltip = '各 Wafer・測定日時で、入力の Shot 中心 Y 座標を上から1行目として数えます。半径除外前に判定。入力にない行は数えません。';
            c.shotRowParity = uicheckbox(factorGrid, 'Text', 'Shot 行の奇数・偶数', 'Tooltip', rowTooltip, ...
                'ValueChangedFcn', onChange);
            place(c.shotRowParity, 2, 4);
            c.factorSeparate = uicheckbox(factorGrid, 'Text', 'Y 成分は別に選ぶ', 'ValueChangedFcn', onChange, ...
                'Tooltip', 'オフなら Y 成分も X 成分と同じ質的変数を使います。オンにすると下の行で Y 成分の質的変数を選べます。');
            place(c.factorSeparate, 2, 5);
            label(factorGrid, 'Y 成分', 3, 1);
            c.factorScanY = uicheckbox(factorGrid, 'Text', 'Scan 方向', 'ValueChangedFcn', onChange);
            place(c.factorScanY, 3, 2);
            c.factorMarkY = uicheckbox(factorGrid, 'Text', 'Mark 番号', 'ValueChangedFcn', onChange);
            place(c.factorMarkY, 3, 3);
            c.shotRowParityY = uicheckbox(factorGrid, 'Text', 'Shot 行の奇数・偶数', 'Tooltip', rowTooltip, ...
                'ValueChangedFcn', onChange);
            place(c.shotRowParityY, 3, 4);
            columnsTooltip = ['選んだ列の値（文字・数字）を水準とする質的変数。値が空の Mark がある Wafer では、その列を使いません。' ...
                '一覧はデータを読み込むと出ます。'];
            c.factorColumnsLabel = label(factorGrid, 'その他の列：X 成分（標準の項目に対応づけなかった列。Ctrl・Shift で複数）', ...
                4, [1, 4]);
            label(factorGrid, 'その他の列：Y 成分', 4, 5);
            c.factorColumns = uilistbox(factorGrid, 'Items', {}, 'Multiselect', 'on', 'ValueChangedFcn', onChange, ...
                'Tooltip', columnsTooltip);
            place(c.factorColumns, 5, [1, 4]);
            c.factorColumnsY = uilistbox(factorGrid, 'Items', {}, 'Multiselect', 'on', 'ValueChangedFcn', onChange, ...
                'Tooltip', columnsTooltip);
            place(c.factorColumnsY, 5, 5);
            c.factorColumnsError = errorLabel(app, m, 5, [1, 4]);
            c.gpr = uicheckbox(m, 'Text', 'GPR（ガウス過程回帰）', 'ValueChangedFcn', onChange);
            place(c.gpr, 6, [1, 4]);
            label(m, 'カーネル（Ctrl・Shift で複数選ぶ）', 7, [1, 2]);
            label(m, '質的変数の扱い（上で選んだ質的変数）', 7, [3, 4]);
            [kernelNames, kernelLabels] = alignest.models.gprKernelChoices();
            c.kernels = uilistbox(m, 'Items', cellstr(kernelLabels), 'ItemsData', cellstr(kernelNames), 'Multiselect', 'on', ...
                'ValueChangedFcn', onChange);
            place(c.kernels, 8, [1, 2]);
            [modeNames, modeLabels] = alignest.models.gprFactorModes();
            modeGrid = uigridlayout(m, [numel(modeNames), 1], 'Padding', 0, 'RowSpacing', 2, ...
                'RowHeight', repmat({'fit'}, 1, numel(modeNames)));
            place(modeGrid, 8, [3, 4]);
            c.factorModes = gobjects(1, numel(modeNames));
            for k = 1:numel(modeNames)
                c.factorModes(k) = uicheckbox(modeGrid, 'Text', modeLabels(k), 'UserData', modeNames(k), ...
                    'ValueChangedFcn', onChange);
            end
            m.RowHeight{8} = 300;
            label(m, 'Matérn の ν（matern・ardmatern を選んだとき。空白区切り）', 9, [1, 2]);
            c.maternNu = uieditfield(m, 'text', 'ValueChangedFcn', onChange, 'Tooltip', ['Matérn カーネルの次数 ν' ...
                '（0 より大きく 50 以下）。大きいほど滑らか。0.5・1.5・2.5 は exponential・matern32・matern52 と同じ。' ...
                '複数入れると ν ごとに比べます（例：0.75 1 2 3.5）。']);
            place(c.maternNu, 9, [3, 4]);
            c.maternNuError = errorLabel(app, m, 10, [1, 4]);
            c.tps = uicheckbox(m, 'Text', 'TPS（薄板スプライン）', 'ValueChangedFcn', onChange);
            place(c.tps, 11, [1, 2]);
            c.tpsFactors = spatialFactorDropdown(m, onChange);
            place(c.tpsFactors, 11, [3, 4]);
            c.rbf = uicheckbox(m, 'Text', 'RBF（ガウス型・平滑化つき）', 'ValueChangedFcn', onChange);
            place(c.rbf, 12, [1, 2]);
            c.rbfFactors = spatialFactorDropdown(m, onChange);
            place(c.rbfFactors, 12, [3, 4]);
            c.ordinaryKriging = uicheckbox(m, 'Text', 'Kriging（通常）', 'ValueChangedFcn', onChange);
            place(c.ordinaryKriging, 13, [1, 2]);
            c.ordinaryFactors = spatialFactorDropdown(m, onChange);
            place(c.ordinaryFactors, 13, [3, 4]);
            c.universalKriging = uicheckbox(m, 'Text', 'Universal Kriging', 'ValueChangedFcn', onChange);
            place(c.universalKriging, 14, [1, 2]);
            c.universalFactors = spatialFactorDropdown(m, onChange);
            place(c.universalFactors, 14, [3, 4]);
            label(m, 'バリオグラム（通常・Universal 共通）', 15, [1, 4]);
            variograms = ["linear", "gaussian", "power", "exponential", "spherical"];
            variogramGrid = uigridlayout(m, [1, numel(variograms)], 'Padding', 0, ...
                'ColumnWidth', repmat({'1x'}, 1, numel(variograms)));
            place(variogramGrid, 16, [1, 4]);
            c.variograms = gobjects(1, numel(variograms));
            for k = 1:numel(variograms)
                c.variograms(k) = uicheckbox(variogramGrid, 'Text', variograms(k), 'UserData', variograms(k), ...
                    'ValueChangedFcn', onChange);
            end
            c.variograms(end).Tooltip = '球形モデル（range より遠い点の相関は 0）。説明変数（X,Y・X,Y,半径）は3次元までなので正定値が保証されます。';
            c.gam = uicheckbox(m, 'Text', 'GAM（一般化加法モデル。選んだ質的変数を含む）', 'ValueChangedFcn', onChange);
            place(c.gam, 17, [1, 4]);
            % 形状関数は項（X・Y、半径）ごとに1行、カーネルは2行に並べる（画面の幅が狭くても切れないように）
            [termNames, termLabels] = alignest.models.gamTerms("XYR");
            [gamKernelNames, gamKernelLabels] = alignest.models.gamKernelChoices();
            kernelColumns = 2;   % カーネルの名前が長いので2列（rationalquadratic（α = 1）が切れないように）
            nShapeRows = numel(termNames) + ceil(numel(gamKernelNames) / kernelColumns) + 1;
            shapeGrid = uigridlayout(m, [nShapeRows, kernelColumns + 1], 'Padding', 0, 'RowSpacing', 2, ...
                'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, kernelColumns)], 'RowHeight', repmat({'fit'}, 1, nShapeRows));
            place(shapeGrid, 18, [1, 4]);
            shapeNames = ["spline", "gp"];
            shapeLabels = ["スプライン", "ガウス過程回帰"];
            c.gamShapeChecks = gobjects(numel(termNames), numel(shapeNames));
            for k = 1:numel(termNames)
                label(shapeGrid, "形状関数（" + termLabels(k) + "）：", k, 1);
                for j = 1:numel(shapeNames)
                    c.gamShapeChecks(k, j) = uicheckbox(shapeGrid, 'Text', shapeLabels(j), 'ValueChangedFcn', onChange, ...
                        'UserData', struct("term", termNames(k), "shape", shapeNames(j)), ...
                        'Tooltip', ['チェックした形状関数の組み合わせをすべて評価します（例：X・Y でスプラインとガウス過程回帰の' ...
                        '両方なら2通り）。スプライン：P-spline（B スプライン＋2階差分の罰則）。ガウス過程回帰：下で選んだカーネルの' ...
                        'ガウス過程（節点で近似、線形部分は罰則なし）。長さスケールは候補から REML で選び、罰則の強さは' ...
                        'どちらも REML で選びます。半径の項は説明変数が X,Y,半径 のときだけ使います。']);
                    place(c.gamShapeChecks(k, j), k, 1 + j);
                end
            end
            % ガウス過程回帰の形状関数のカーネル（チェックしたカーネルごとに比べる）
            kernelRow = numel(termNames) + 1;
            label(shapeGrid, 'ガウス過程回帰のカーネル：', kernelRow, 1);
            c.gamKernelChecks = gobjects(1, numel(gamKernelNames));
            for k = 1:numel(gamKernelNames)
                c.gamKernelChecks(k) = uicheckbox(shapeGrid, 'Text', gamKernelLabels(k), 'UserData', gamKernelNames(k), ...
                    'ValueChangedFcn', onChange, 'Tooltip', ['形状関数をガウス過程回帰にした項で使うカーネル（等方。' ...
                    '式は GPR と同じ）。チェックしたカーネルごとに評価します。rationalquadratic の α は 1 に固定します。']);
                place(c.gamKernelChecks(k), kernelRow + floor((k - 1) / kernelColumns), 2 + mod(k - 1, kernelColumns));
            end
            nuGrid = uigridlayout(shapeGrid, [1, 2], 'ColumnWidth', {'fit', 120}, 'Padding', 0);
            kernelRows = ceil(numel(gamKernelNames) / kernelColumns);
            place(nuGrid, kernelRow + kernelRows, [1, kernelColumns + 1]);
            label(nuGrid, 'matern（ν を指定）の ν =', 1, 1);
            c.gamMaternNu = uieditfield(nuGrid, 'text', 'ValueChangedFcn', onChange, 'Tooltip', ['matern（ν を指定）' ...
                'の ν。空白で区切ると ν ごとに比べます（例：1 2.5）。']);
            place(c.gamMaternNu, 1, 2);
            c.polynomial = uicheckbox(m, 'Text', 'XY 多項式　次数：', 'ValueChangedFcn', onChange);
            place(c.polynomial, 19, 1);
            c.polynomialOrder = uispinner(m, 'Limits', [1, 8], 'RoundFractionalValues', 'on', 'ValueChangedFcn', onChange);
            place(c.polynomialOrder, 19, 2);
            c.rt = uicheckbox(m, 'Text', 'RT モデル　次数 K：', 'ValueChangedFcn', onChange);
            place(c.rt, 20, 1);
            c.rtOrders = uieditfield(m, 'text', 'ValueChangedFcn', onChange);
            place(c.rtOrders, 20, 2);
            c.zernike = uicheckbox(m, 'Text', 'Fringe Zernike', 'ValueChangedFcn', onChange, ...
                'Tooltip', ['Fringe Zernike 多項式（Z1〜Z(k+1)²）の最小二乗。k = 3：Z1〜Z16、4：Z1〜Z25、5：Z1〜Z36。' ...
                '空白で区切ると次数ごとに比べます。式は「7. ヘルプ」。']);
            place(c.zernike, 21, 1);
            c.zernikeOrders = uieditfield(m, 'text', 'ValueChangedFcn', onChange);
            place(c.zernikeOrders, 21, 2);
            zernikeHelp = label(m, '← 次数 k（空白区切りで複数）。Z1〜Z(k+1)² を使う（k = 4 で Z25 まで）', 21, [3, 4]);
            zernikeHelp.FontColor = app.Palette.muted;
            zernikeHelp.UserData = "muted";
            c.rtError = errorLabel(app, m, 22, [1, 4]);
            c.zernikeError = errorLabel(app, m, 23, [1, 4]);
            c.gamShapeError = errorLabel(app, m, 24, [1, 4]);
            % RBFe（仮）：面内を領域に分け、領域ごとの TPS を重みでつなぐ形状関数の GAM。領域の数がハイパーパラメータ
            c.rbfe = uicheckbox(m, 'Text', 'RBFe（仮）', 'ValueChangedFcn', onChange, 'Tooltip', ...
                ['学習点の位置を領域の数のまとまりに分け（k-means）、領域ごとに TPS を当てはめ（λ は領域ごとに GCV）、' ...
                '重なる所は滑らかな重みでつなぎ合わせます。右で選ぶ質的変数は Backfitting で足します（GAM）。' ...
                '領域の数 1 は TPS と同じです。式は「7. ヘルプ」。']);
            place(c.rbfe, 25, 1);
            c.rbfeRegions = uieditfield(m, 'text', 'ValueChangedFcn', onChange, 'Tooltip', ...
                '領域の数（ハイパーパラメータ、1〜25 の整数）。空白で区切ると領域の数ごとに比べます（例：4 9）。');
            place(c.rbfeRegions, 25, 2);
            c.rbfeFactors = spatialFactorDropdown(m, onChange);
            place(c.rbfeFactors, 25, [3, 4]);
            rbfeHelp = label(m, ['↑ RBFe（仮）：面内を領域に分けた TPS をつなぐ GAM。欄は領域の数（ハイパーパラメータ。' ...
                '空白区切りで複数）、右は質的変数の扱い。学習点が少ないときは自動で領域を減らします。'], 26, [1, 4]);
            rbfeHelp.FontColor = app.Palette.muted;
            rbfeHelp.UserData = "muted";
            c.rbfeError = errorLabel(app, m, 27, [1, 4]);

            footer = uigridlayout(grid, [1, 4], 'ColumnWidth', {'fit', 'fit', 'fit', '1x'}, 'Padding', 0);
            place(footer, 2, [1, 2]);
            uibutton(footer, 'Text', '設定を保存…', 'ButtonPushedFcn', @(~, ~) app.onSaveSettings());
            uibutton(footer, 'Text', '設定を読み込む…', 'ButtonPushedFcn', @(~, ~) app.onLoadSettings());
            uibutton(footer, 'Text', '初期設定に戻す', 'ButtonPushedFcn', @(~, ~) app.setSettings(alignest.siteDefaults()), ...
                'Tooltip', ['アプリの初期設定に戻します（今のフォルダに既定の設定ファイル alignment_estimation_defaults.json が' ...
                'あれば、その値）。']);
            c.countLabel = uilabel(footer, 'WordWrap', 'on', 'Text', '');
            app.Controls = mergeStruct(app.Controls, c);
        end

        function settingsToControls(app)
            c = app.Controls;
            s = app.Settings;
            c.validRadius.Value = s.data.validRadiusMm;
            c.excludeZeroMeasurements.Value = s.data.excludeZeroMeasurements;
            c.excludeUnmeasuredRecords.Value = s.data.excludeUnmeasuredRecords;
            c.directionRule.Value = char(s.data.directionRule);
            c.invertDirection.Value = s.data.invertDirection;
            c.invertDirection.Enable = onOff(s.data.directionRule ~= "none");
            c.coordinateMode.Value = char(fieldOr(s.data, "coordinateMode", "shotMark"));
            c.valueUnit.Value = char(fieldOr(s.data, "valueUnit", "nm"));
            refreshValueColumns(app);
            fillUnitTable(app);
            choice = alignest.factorChoice(s, "X");
            c.factorScan.Value = choice.scan;
            c.factorMark.Value = choice.mark;
            c.shotRowParity.Value = choice.row;
            choiceY = alignest.factorChoice(s, "Y");   % 別に選ばないときは X と同じ（画面にもそのまま出す）
            c.factorSeparate.Value = isfield(s.factors, "separateY") && s.factors.separateY;
            c.factorScanY.Value = choiceY.scan;
            c.factorMarkY.Value = choiceY.mark;
            c.shotRowParityY.Value = choiceY.row;
            refreshFactorColumns(app, choice.columns, choiceY.columns);
            c.samplingMethod.Value = cellstr(s.sampling.method(:).');
            c.markPerShot.Value = char(strjoin(string(fieldOr(s.sampling, "markPerShot", 1)), " "));
            c.markRatio.Value = logical(fieldOr(s.sampling.constraints, "markRatio", true));
            c.nShotsStart.Value = s.sampling.nShotsStart;
            c.nShotsEnd.Value = s.sampling.nShotsEnd;
            c.nShotsStep.Value = s.sampling.nShotsStep;
            c.countBy.Value = char(s.sampling.countBy);
            c.rateStart.Value = s.sampling.rateStart;
            c.rateEnd.Value = s.sampling.rateEnd;
            c.rateStep.Value = s.sampling.rateStep;
            c.requiredShots.Value = char(strjoin(string(s.sampling.requiredShots), " "));
            c.requireOuter.Value = s.sampling.requireOuterShots;
            c.randomRepeats.Value = s.sampling.randomRepeats;
            c.seed.Value = s.sampling.seed;
            c.manualPlans.Value = cellstr(ternary(isempty(s.sampling.manualPlans), "", s.sampling.manualPlans(:)));
            c.priorityInfo.Text = priorityText(s.sampling);
            c.zoneEdges.Value = char(strjoin(string(s.sampling.constraints.radialZoneEdgesMm), " "));
            c.quadrants.Value = s.sampling.constraints.quadrants;
            c.scanConstraint.Value = s.sampling.constraints.scanDirection;
            c.slack.Value = s.sampling.constraints.slack;
            c.designOrder.Value = s.sampling.designOrder;
            c.exchangeStarts.Value = s.sampling.exchangeStarts;
            c.outerRadius.Value = s.evaluation.outerRadiusMm;
            c.removeLinear.Value = s.evaluation.removeLinear;
            c.recordTiming.Value = s.evaluation.recordTiming;
            c.excludeOutliers.Value = s.evaluation.excludeOutliers;
            c.outlierSigma.Value = s.evaluation.outlierSigma;
            c.outlierMethod.Value = char(alignest.outlierMethod(s));
            % 式は画面に出してから確かめる（読めない式でも設定を読み込めるように、ここでは式を読まない）
            rawOverlay = fieldOr(s, "overlay", struct());
            defaultOverlay = alignest.defaultSettings().overlay;
            plain = s;
            plain.overlay = rawOverlay;
            plain.overlay.waferUseFormula = false;
            if string(fieldOr(rawOverlay, "shotCommon", "none")) == "formula"
                plain.overlay.shotCommon = "none";
            end
            if string(fieldOr(rawOverlay, "perShot", "none")) == "formula"
                plain.overlay.perShot = "none";
            end
            overlay = alignest.overlayChoice(plain);
            useWaferFormula = logical(fieldOr(rawOverlay, "waferUseFormula", false));
            c.overlayWafer.Value = ternary(useWaferFormula, app.FORMULA_CHOICE, overlay.waferOrder);
            % 画面で選べる Shot 共通成分は「なし」「1次」「式を入力」（以前の設定のメーカー別の高次式は 1次にする）
            shotCommon = string(fieldOr(rawOverlay, "shotCommon", overlay.shotCommon));
            if ~any(shotCommon == ["none", "linear", "formula"])
                shotCommon = "linear";
            end
            c.overlayShotCommon.Value = char(shotCommon);
            c.overlayPerShot.Value = char(string(fieldOr(rawOverlay, "perShot", overlay.perShot)));
            perShotFormula = fieldOr(rawOverlay, "perShotFormula", defaultOverlay.perShotFormula);
            c.overlayPerShotDx.Value = char(perShotFormula.dx);
            c.overlayPerShotDy.Value = char(perShotFormula.dy);
            waferFormula = fieldOr(rawOverlay, "waferFormula", defaultOverlay.waferFormula);
            shotFormula = fieldOr(rawOverlay, "shotFormula", defaultOverlay.shotFormula);
            c.overlayWaferDx.Value = char(waferFormula.dx);
            c.overlayWaferDy.Value = char(waferFormula.dy);
            c.overlayShotDx.Value = char(shotFormula.dx);
            c.overlayShotDy.Value = char(shotFormula.dy);
            methods = s.methods;
            c.featureXY.Value = any(methods.featureSets == "XY");
            c.featureXYR.Value = any(methods.featureSets == "XYR");
            c.gpr.Value = methods.gpr.enabled;
            c.kernels.Value = cellstr(methods.gpr.kernels);
            c.maternNu.Value = char(strjoin(string(methods.gpr.maternNu), " "));
            for check = reshape(c.gamShapeChecks, 1, [])
                chosen = "spline";
                if isfield(methods.gam.shapes, check.UserData.term)
                    chosen = string(methods.gam.shapes.(check.UserData.term));
                end
                check.Value = any(chosen == check.UserData.shape);
            end
            for check = c.gamKernelChecks
                check.Value = any(string(methods.gam.gpKernels) == check.UserData);
            end
            c.gamMaternNu.Value = char(strjoin(string(methods.gam.gpMaternNu), " "));
            for k = 1:numel(c.factorModes)
                c.factorModes(k).Value = any(methods.gpr.factorModes == c.factorModes(k).UserData);
            end
            c.tps.Value = methods.tps.enabled;
            c.rbf.Value = methods.rbf.enabled;
            c.rbfFactors.Value = modeSelection(methods.rbf.factorModes);
            c.rbfe.Value = methods.rbfe.enabled;
            c.rbfeRegions.Value = char(strjoin(string(methods.rbfe.regions), " "));
            c.rbfeFactors.Value = modeSelection(methods.rbfe.factorModes);
            c.tpsFactors.Value = modeSelection(methods.tps.factorModes);
            c.ordinaryFactors.Value = modeSelection(methods.kriging.ordinaryFactorModes);
            c.universalFactors.Value = modeSelection(methods.kriging.universalFactorModes);
            c.ordinaryKriging.Value = methods.kriging.ordinary;
            c.universalKriging.Value = methods.kriging.universal;
            for k = 1:numel(c.variograms)
                c.variograms(k).Value = any(methods.kriging.variograms == c.variograms(k).UserData);
            end
            c.gam.Value = methods.gam.enabled;
            c.polynomial.Value = methods.polynomial.enabled;
            c.polynomialOrder.Value = methods.polynomial.order;
            c.rt.Value = methods.rt.enabled;
            c.rtOrders.Value = char(strjoin(string(methods.rt.orders), " "));
            c.zernike.Value = methods.zernike.enabled;
            c.zernikeOrders.Value = char(strjoin(string(methods.zernike.orders), " "));
            validateSettings(app);
            updateEnabled(app);
        end

        function controlsToSettings(app)
            % 画面の値を設定に移す。数字の欄が正しくないときは前の値のまま（欄の下に理由を出す）
            c = app.Controls;
            s = app.Settings;
            s.data.validRadiusMm = c.validRadius.Value;
            s.data.coordinateUnits = currentCoordinateUnits(app);
            s.data.excludeZeroMeasurements = c.excludeZeroMeasurements.Value;
            s.data.excludeUnmeasuredRecords = c.excludeUnmeasuredRecords.Value;
            s.data.directionRule = string(c.directionRule.Value);
            s.data.invertDirection = c.invertDirection.Value;
            s.factors.scan = c.factorScan.Value;
            s.factors.mark = c.factorMark.Value;
            s.factors.shotRowParity = c.shotRowParity.Value;
            s.factors.columns = reshape(string(c.factorColumns.Value), 1, []);
            s.factors.separateY = c.factorSeparate.Value;
            if ~s.factors.separateY
                % 別に選ばないときは、Y 成分の欄を X 成分と同じにしておく（オンにしたときの初めの値）
                c.factorScanY.Value = c.factorScan.Value;
                c.factorMarkY.Value = c.factorMark.Value;
                c.shotRowParityY.Value = c.shotRowParity.Value;
                c.factorColumnsY.Value = c.factorColumns.Value;
            end
            s.factors.y.scan = c.factorScanY.Value;
            s.factors.y.mark = c.factorMarkY.Value;
            s.factors.y.shotRowParity = c.shotRowParityY.Value;
            s.factors.y.columns = reshape(string(c.factorColumnsY.Value), 1, []);
            if ~isempty(c.samplingMethod.Value)
                s.sampling.method = reshape(string(c.samplingMethod.Value), 1, []);   % 空のときは前の値のまま（欄の下に理由）
            end
            [values, ok] = parseNumbers(c.markPerShot.Value);
            if ok && ~isempty(values) && all(values >= 1)
                s.sampling.markPerShot = unique(values);
            end
            s.sampling.constraints.markRatio = c.markRatio.Value;
            try
                s.sampling.nShots = alignest.shotCountList(c.nShotsStart.Value, c.nShotsEnd.Value, c.nShotsStep.Value);
                s.sampling.nShotsStart = c.nShotsStart.Value;
                s.sampling.nShotsEnd = c.nShotsEnd.Value;
                s.sampling.nShotsStep = c.nShotsStep.Value;
            catch
                % 正しくない組み合わせのときは前の値のまま（欄の下に理由を出す）
            end
            s.sampling.countBy = string(c.countBy.Value);
            try
                alignest.measurementRateList(c.rateStart.Value, c.rateEnd.Value, c.rateStep.Value);
                s.sampling.rateStart = c.rateStart.Value;
                s.sampling.rateEnd = c.rateEnd.Value;
                s.sampling.rateStep = c.rateStep.Value;
            catch
                % 正しくない組み合わせのときは前の値のまま（欄の下に理由を出す）
            end
            [values, ok] = parseNumbers(c.requiredShots.Value);
            if ok && all(values == round(values))
                s.sampling.requiredShots = unique(values);
            end
            s.sampling.requireOuterShots = c.requireOuter.Value;
            s.sampling.randomRepeats = c.randomRepeats.Value;
            s.sampling.seed = c.seed.Value;
            lines = string(c.manualPlans.Value);
            s.sampling.manualPlans = lines(strlength(strtrim(lines)) > 0);
            [values, ok] = parseNumbers(c.zoneEdges.Value);
            if ok && all(values > 0 & values < s.data.waferRadiusMm)
                s.sampling.constraints.radialZoneEdgesMm = unique(values);
            end
            s.sampling.constraints.quadrants = c.quadrants.Value;
            s.sampling.constraints.scanDirection = c.scanConstraint.Value;
            s.sampling.constraints.slack = c.slack.Value;
            s.sampling.designOrder = c.designOrder.Value;
            s.sampling.exchangeStarts = c.exchangeStarts.Value;
            s.evaluation.outerRadiusMm = c.outerRadius.Value;
            s.evaluation.removeLinear = c.removeLinear.Value;
            s.evaluation.excludeOutliers = c.excludeOutliers.Value;
            s.evaluation.outlierSigma = c.outlierSigma.Value;
            s.evaluation.outlierMethod = string(c.outlierMethod.Value);
            s.evaluation.recordTiming = c.recordTiming.Value;
            s.overlay.waferUseFormula = c.overlayWafer.Value == app.FORMULA_CHOICE;
            if ~s.overlay.waferUseFormula
                s.overlay.waferOrder = c.overlayWafer.Value;
            end
            s.overlay.shotCommon = string(c.overlayShotCommon.Value);
            s.overlay.perShot = string(c.overlayPerShot.Value);
            s.overlay.waferFormula = struct("dx", string(c.overlayWaferDx.Value), "dy", string(c.overlayWaferDy.Value));
            s.overlay.shotFormula = struct("dx", string(c.overlayShotDx.Value), "dy", string(c.overlayShotDy.Value));
            s.overlay.perShotFormula = struct("dx", string(c.overlayPerShotDx.Value), "dy", string(c.overlayPerShotDy.Value));
            featureNames = ["XY", "XYR"];
            s.methods.featureSets = featureNames([c.featureXY.Value, c.featureXYR.Value]);
            s.methods.gpr.enabled = c.gpr.Value;
            s.methods.gpr.kernels = string(c.kernels.Value);
            [values, ok] = parseNumbers(c.maternNu.Value);
            if ok && ~isempty(values) && all(values > 0 & values <= app.MAX_MATERN_NU)
                s.methods.gpr.maternNu = unique(values, 'stable');
            end
            for k = 1:size(c.gamShapeChecks, 1)
                checks = c.gamShapeChecks(k, :);
                chosen = strings(1, 0);
                for check = checks([checks.Value])
                    chosen(end + 1) = check.UserData.shape; %#ok<AGROW>
                end
                s.methods.gam.shapes.(checks(1).UserData.term) = chosen;
            end
            s.methods.gam.gpKernels = checkedValues(c.gamKernelChecks);
            [values, ok] = parseNumbers(c.gamMaternNu.Value);
            if ok && ~isempty(values) && all(values > 0 & values <= app.MAX_MATERN_NU)
                s.methods.gam.gpMaternNu = unique(values, 'stable');
            end
            s.methods.gpr.factorModes = checkedValues(c.factorModes);
            s.methods.tps.enabled = c.tps.Value;
            s.methods.rbf.enabled = c.rbf.Value;
            s.methods.rbf.factorModes = selectedModes(c.rbfFactors.Value);
            s.methods.rbfe.enabled = c.rbfe.Value;
            s.methods.rbfe.factorModes = selectedModes(c.rbfeFactors.Value);
            [values, ok] = parseNumbers(c.rbfeRegions.Value);
            if ok && ~isempty(values) && all(values >= 1 & values <= app.MAX_RBFE_REGIONS & values == round(values))
                s.methods.rbfe.regions = unique(values);
            end
            s.methods.tps.factorModes = selectedModes(c.tpsFactors.Value);
            s.methods.kriging.ordinaryFactorModes = selectedModes(c.ordinaryFactors.Value);
            s.methods.kriging.universalFactorModes = selectedModes(c.universalFactors.Value);
            s.methods.kriging.ordinary = c.ordinaryKriging.Value;
            s.methods.kriging.universal = c.universalKriging.Value;
            s.methods.kriging.variograms = checkedValues(c.variograms);
            s.methods.gam.enabled = c.gam.Value;
            s.methods.polynomial.enabled = c.polynomial.Value;
            s.methods.polynomial.order = c.polynomialOrder.Value;
            s.methods.rt.enabled = c.rt.Value;
            [values, ok] = parseNumbers(c.rtOrders.Value);
            if ok && ~isempty(values) && all(values >= 1 & values <= 10 & values == round(values))
                s.methods.rt.orders = unique(values);
            end
            s.methods.zernike.enabled = c.zernike.Value;
            [values, ok] = parseNumbers(c.zernikeOrders.Value);
            if ok && ~isempty(values) && all(values >= 1 & values <= app.MAX_ZERNIKE_ORDER & values == round(values))
                s.methods.zernike.orders = unique(values);
            end
            app.Settings = s;
        end

        function messages = validateSettings(app)
            % 入力欄ごとに確かめ、欄の下に理由を出す（色だけでなく「⚠」と文で示す）
            c = app.Controls;
            messages = strings(0, 1);
            method = string(c.samplingMethod.Value);
            text = "";
            listText = "";
            try
                if string(c.countBy.Value) == "rate"
                    rates = alignest.measurementRateList(c.rateStart.Value, c.rateEnd.Value, c.rateStep.Value);
                    listText = "→ 計測率：" + previewList(rates, app.LIST_PREVIEW_COUNT) + sprintf(" %%（%d 通り）", ...
                        numel(rates)) + rateExample(app, rates);
                else
                    counts = alignest.shotCountList(c.nShotsStart.Value, c.nShotsEnd.Value, c.nShotsStep.Value);
                    listText = "→ 学習 Shot 数：" + previewList(counts, app.LIST_PREVIEW_COUNT) + ...
                        sprintf("（%d 通り）", numel(counts));
                end
            catch err
                if any(ismember(method, ["ioptimal", "doptimal", "random", "file"]))
                    text = "⚠ " + string(err.message);
                end
            end
            if isempty(method)
                text = "⚠ 学習 Shot の選び方を1つ以上選んでください。";
            end
            c.nShotsList.Text = listText;
            c.nShotsError.Text = text;
            messages = [messages; text(text ~= "")];
            text = "";
            if any(method == "manual")
                try
                    alignest.buildPlanSpecs(struct("method", "manual", "manualPlans", string(c.manualPlans.Value)));
                catch err
                    text = "⚠ " + string(err.message);
                end
            end
            c.manualError.Text = text;
            messages = [messages; text(text ~= "")];
            text = "";
            if any(method == "file") && isempty(app.Settings.sampling.priorityShots)
                text = "⚠ 「優先順のファイルを読み込む…」で、Shot 番号と優先度のファイルを読み込んでください。";
            end
            c.priorityError.Text = text;
            messages = [messages; text(text ~= "")];
            [values, ok] = parseNumbers(c.requiredShots.Value);
            text = "";
            if any(ismember(method, ["ioptimal", "doptimal", "random"])) && (~ok || any(values ~= round(values)))
                text = "⚠ 必ず計測する shotNo は整数を空白またはカンマで区切って入れてください（使わないなら空欄）。";
            end
            c.requiredError.Text = text;
            c.requiredInfo.Text = requiredText(app);
            c.exchangeInfo.Text = exchangeText(app);
            messages = [messages; text(text ~= "")];
            [values, ok] = parseNumbers(c.zoneEdges.Value);
            text = "";
            radiusMm = app.Settings.data.waferRadiusMm;
            if ~ok || any(values <= 0 | values >= radiusMm)
                text = sprintf("⚠ 同心円の区切りは 0 より大きく %g mm より小さい半径 [mm] を空白で区切って入れてください" + ...
                    "（使わないなら空欄）。", radiusMm);
            end
            c.zoneError.Text = text;
            messages = [messages; text(text ~= "")];
            text = "";
            selectedColumns = string(c.factorColumns.Value);
            if c.factorSeparate.Value
                selectedColumns = unique([selectedColumns, string(c.factorColumnsY.Value)], 'stable');
            end
            missing = missingFactorColumns(app, selectedColumns);
            if ~isempty(missing)
                text = "⚠ 質的変数に選んだ列が、読み込んだデータにありません：" + strjoin(missing, "、") + ...
                    "。選び直すか、その列を含むファイルを読み込んでください。";
            end
            c.factorColumnsError.Text = text;
            messages = [messages; text(text ~= "")];
            [values, ok] = parseNumbers(c.maternNu.Value);
            text = "";
            if usesMaternNu(c) && (~ok || isempty(values) || any(values <= 0 | values > app.MAX_MATERN_NU))
                text = sprintf("⚠ Matérn の ν は 0 より大きく %g 以下の数を空白で区切って入れてください（例：0.75 1 2）。", ...
                    app.MAX_MATERN_NU);
            end
            c.maternNuError.Text = text;
            messages = [messages; text(text ~= "")];
            [values, ok] = parseNumbers(c.rtOrders.Value);
            text = "";
            if c.rt.Value && (~ok || isempty(values) || any(values < 1 | values > 10 | values ~= round(values)))
                text = "⚠ RT モデルの次数は 1〜10 の整数を空白で区切って入れてください（例：4 5）。";
            end
            c.rtError.Text = text;
            messages = [messages; text(text ~= "")];
            [values, ok] = parseNumbers(c.zernikeOrders.Value);
            text = "";
            if c.zernike.Value && (~ok || isempty(values) || any(values < 1 | values > app.MAX_ZERNIKE_ORDER | ...
                    values ~= round(values)))
                text = sprintf("⚠ Fringe Zernike の次数は 1〜%d の整数を空白で区切って入れてください（例：3 4）。", ...
                    app.MAX_ZERNIKE_ORDER);
            end
            c.zernikeError.Text = text;
            messages = [messages; text(text ~= "")];
            [values, ok] = parseNumbers(c.rbfeRegions.Value);
            text = "";
            if c.rbfe.Value && (~ok || isempty(values) || any(values < 1 | values > app.MAX_RBFE_REGIONS | ...
                    values ~= round(values)))
                text = sprintf("⚠ RBFe の領域の数は 1〜%d の整数を空白で区切って入れてください（例：4 9）。", ...
                    app.MAX_RBFE_REGIONS);
            end
            c.rbfeError.Text = text;
            messages = [messages; text(text ~= "")];
            [values, ok] = parseNumbers(c.markPerShot.Value);
            text = "";
            if any(method == "mark") && (~ok || isempty(values) || any(values < 1))
                text = "⚠ 1 Shot あたりの計測 Mark 数は 1 以上の数を空白で区切って入れてください（例：1 1.5 2）。";
            end
            c.markError.Text = text;
            messages = [messages; text(text ~= "")];
            text = "";
            if c.gam.Value
                terms = string(arrayfun(@(k) c.gamShapeChecks(k, 1).UserData.term, 1:size(c.gamShapeChecks, 1), ...
                    'UniformOutput', false));
                used = terms == "xy" | (terms == "r" & c.featureXYR.Value);
                empty = ~any(reshape([c.gamShapeChecks.Value], size(c.gamShapeChecks)), 2).';
                if any(empty & used)
                    text = "⚠ GAM の形状関数を、項（X・Y、半径）ごとにスプラインかガウス過程回帰の少なくとも1つ選んでください。";
                elseif usesGamKernels(c) && ~any([c.gamKernelChecks.Value])
                    text = "⚠ GAM のガウス過程回帰のカーネルを1つ以上選んでください。";
                elseif usesGamKernels(c) && usesGamMaternNu(c)
                    [values, ok] = parseNumbers(c.gamMaternNu.Value);
                    if ~ok || isempty(values) || any(values <= 0 | values > app.MAX_MATERN_NU)
                        text = sprintf("⚠ GAM の Matérn の ν は 0 より大きく %g 以下の数を空白で区切って入れてください。", ...
                            app.MAX_MATERN_NU);
                    end
                end
            end
            c.gamShapeError.Text = text;
            messages = [messages; text(text ~= "")];
            % Overlay 補正の式（選んだ成分だけ確かめる）
            texts = strings(0, 1);
            formulas = {c.overlayWafer.Value == app.FORMULA_CHOICE, "Wafer 成分", c.overlayWaferDx, c.overlayWaferDy; ...
                string(c.overlayShotCommon.Value) == "formula", "Shot 共通成分", c.overlayShotDx, c.overlayShotDy; ...
                string(c.overlayPerShot.Value) == "formula", "Shot ごとの成分", c.overlayPerShotDx, c.overlayPerShotDy};
            for k = 1:size(formulas, 1)
                if ~formulas{k, 1}
                    continue
                end
                fields = [formulas{k, 3}, formulas{k, 4}];
                axisNames = ["dx", "dy"];
                for a = 1:2
                    try
                        alignest.parseCorrectionFormula(fields(a).Value, formulas{k, 2} + "の " + axisNames(a));
                    catch err
                        texts(end + 1, 1) = "⚠ " + string(err.message); %#ok<AGROW>
                    end
                end
            end
            c.overlayFormulaError.Text = strjoin(texts, newline);
            messages = [messages; texts];
        end

        function updateEnabled(app)
            c = app.Controls;
            set([c.factorScanY, c.factorMarkY, c.shotRowParityY, c.factorColumnsY], 'Enable', onOff(c.factorSeparate.Value));
            method = string(c.samplingMethod.Value);
            constrained = any(ismember(method, ["ioptimal", "doptimal", "random", "file"]));
            optimal = any(ismember(method, ["ioptimal", "doptimal", "mark"]));
            shotConstraints = any(ismember(method, ["ioptimal", "doptimal", "random"]));
            byRate = string(c.countBy.Value) == "rate";
            c.countBy.Enable = onOff(constrained);
            c.nShotsList.Enable = onOff(constrained);
            set([c.nShotsStart, c.nShotsEnd, c.nShotsStep], 'Enable', onOff(constrained && ~byRate));
            set([c.rateStart, c.rateEnd, c.rateStep], 'Enable', onOff(constrained && byRate));
            set([c.requiredShots, c.requireOuter, c.requiredInfo], 'Enable', onOff(shotConstraints));
            set([c.zoneEdges, c.quadrants, c.scanConstraint], 'Enable', onOff(shotConstraints));
            c.slack.Enable = onOff(shotConstraints || any(method == "mark"));
            set([c.loadPriority, c.priorityInfo], 'Enable', onOff(any(method == "file")));
            set([c.randomRepeats], 'Enable', onOff(any(method == "random")));
            c.seed.Enable = onOff(any(ismember(method, ["random", "ioptimal", "doptimal", "mark"])));
            set([c.designOrder, c.exchangeStarts], 'Enable', onOff(optimal));
            set([c.markPerShot, c.markRatio], 'Enable', onOff(any(method == "mark")));
            c.manualPlans.Enable = onOff(any(method == "manual"));
            c.outlierMethod.Enable = onOff(c.excludeOutliers.Value);
            set([c.overlayPerShotDx, c.overlayPerShotDy], 'Enable', onOff(string(c.overlayPerShot.Value) == "formula"));
            c.zernikeOrders.Enable = onOff(c.zernike.Value);
            c.outlierSigma.Enable = onOff(c.excludeOutliers.Value);
            set([c.overlayWaferDx, c.overlayWaferDy], 'Enable', onOff(c.overlayWafer.Value == app.FORMULA_CHOICE));
            set([c.overlayShotDx, c.overlayShotDy], 'Enable', onOff(string(c.overlayShotCommon.Value) == "formula"));
            set([c.kernels, c.factorModes], 'Enable', onOff(c.gpr.Value));
            c.maternNu.Enable = onOff(usesMaternNu(c));
            set(c.gamShapeChecks, 'Enable', onOff(c.gam.Value));
            set(c.gamKernelChecks, 'Enable', onOff(usesGamKernels(c)));
            c.gamMaternNu.Enable = onOff(usesGamKernels(c) && usesGamMaternNu(c));
            set(c.variograms, 'Enable', onOff(c.ordinaryKriging.Value || c.universalKriging.Value));
            c.tpsFactors.Enable = onOff(c.tps.Value);
            c.rbfFactors.Enable = onOff(c.rbf.Value);
            set([c.rbfeRegions, c.rbfeFactors], 'Enable', onOff(c.rbfe.Value));
            c.ordinaryFactors.Enable = onOff(c.ordinaryKriging.Value);
            c.universalFactors.Enable = onOff(c.universalKriging.Value);
            c.polynomialOrder.Enable = onOff(c.polynomial.Value);
            % 1変数の推定では、Overlay 補正の評価と RT モデル（どちらも X・Y の2成分が要る）を使わない
            scalar = alignest.valueSpec(app.Settings.data).scalar;
            set([c.overlayWafer, c.overlayShotCommon, c.overlayPerShot], 'Enable', onOff(~scalar));
            if scalar
                set([c.overlayWaferDx, c.overlayWaferDy, c.overlayShotDx, c.overlayShotDy, c.overlayPerShotDx, ...
                    c.overlayPerShotDy], 'Enable', 'off');
            end
            c.rt.Enable = onOff(~scalar);
            c.rtOrders.Enable = onOff(c.rt.Value && ~scalar);
            c.overlayHelp.Text = char(ternary(scalar, "1変数の推定（「1. データの読み込み」の「推定する値」）では、" + ...
                "Overlay 補正の評価と RT モデルは使いません（X・Y の2成分が要るため）。", ...
                "すべて「なし」なら評価しません。結果一覧の指標「OVL …」と、Wafer ごとのマップの「Overlay 補正」で" + ...
                "見られます。補正の式は「7. ヘルプ」にまとめています。"));
        end

        function refreshFactorColumns(app, selected, selectedY)
            % 質的変数に選べるその他の列の一覧（X 成分・Y 成分）：読み込んだデータの列と、設定で選んであるがデータに無い列
            c = app.Controls;
            if nargin < 2
                selected = string(c.factorColumns.Value);
                selectedY = string(c.factorColumnsY.Value);
            end
            available = strings(1, 0);
            if ~isempty(app.Data) && isfield(app.Data, "attributeNames")
                available = reshape(app.Data.attributeNames, 1, []);
            end
            lists = [c.factorColumns, c.factorColumnsY];
            choices = {reshape(string(selected), 1, []), reshape(string(selectedY), 1, [])};
            for k = 1:2
                absent = choices{k}(~ismember(choices{k}, available));
                names = [available, absent];
                lists(k).Items = cellstr([available, absent + "（データに無い）"]);
                lists(k).ItemsData = cellstr(names);
                lists(k).Value = cellstr(choices{k}(ismember(choices{k}, names)));
            end
        end

        function missing = missingFactorColumns(app, selected)
            % データを読み込んでいるときだけ、データに無い列を返す
            missing = strings(1, 0);
            if ~isempty(app.Data) && isfield(app.Data, "attributeNames")
                missing = selected(~ismember(selected, app.Data.attributeNames));
            end
        end

        function onSettingsChanged(app)
            validateSettings(app);
            controlsToSettings(app);
            updateEnabled(app);
            refreshRunSummary(app);
        end

        function onPreset(app, selection)
            controlsToSettings(app);
            app.Settings.methods = alignest.recommendedMethods(selection);
            settingsToControls(app);
            refreshRunSummary(app);
        end

        function onLoadPriority(app)
            [fileName, folder] = uigetfile({'*.xlsx;*.xlsm;*.xls;*.csv', 'Shot の優先順 (*.xlsx, *.xlsm, *.xls, *.csv)'}, ...
                '計測する Shot の優先順のファイルを選ぶ');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.loadShotPriority(fullfile(folder, fileName)), "優先順のファイルを読み込めませんでした", ...
                "1行目に項目名（Shot 番号・優先度）、2行目から Shot 番号と優先度を書いたファイルを選んでください。");
        end

        function onLoadLayouts(app)
            [fileName, folder] = uigetfile({'*.xlsx;*.xlsm;*.xls;*.csv', '計測配置 (*.xlsx, *.xlsm, *.xls, *.csv)'}, ...
                '人が選んだ計測配置のファイルを選ぶ');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.loadLayoutPlans(fullfile(folder, fileName)), "計測配置を読み込めませんでした", ...
                "1行目に shotNo とパターンの名前、2行目から shotNo と 1（計測する）・0（しない）を書いたファイルを選んでください。");
        end

        function onSaveSettings(app)
            controlsToSettings(app);
            [fileName, folder] = uiputfile({'*.json', '設定ファイル (*.json)'}, '設定を保存', 'alignment_estimation_settings.json');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            if runWithAlert(app, @() alignest.saveSettings(app.Settings, fullfile(folder, fileName)), ...
                    "設定を保存できませんでした", "保存先のフォルダを変えてもう一度試してください。")
                uialert(app.Figure, sprintf('設定を保存しました：%s', fullfile(folder, fileName)), '保存しました', 'Icon', 'success');
            end
        end

        function onLoadSettings(app)
            [fileName, folder] = uigetfile({'*.json', '設定ファイル (*.json)'}, '設定を読み込む');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.setSettings(alignest.loadSettings(fullfile(folder, fileName))), ...
                "設定を読み込めませんでした", "このアプリで保存した設定ファイル（.json）を選んでください。");
        end

        % ================= 3. 実行 =================
        function buildRunTab(app)
            grid = uigridlayout(app.Tabs.run, [4, 1], 'RowHeight', {'fit', 'fit', 'fit', '1x'}, 'Padding', 12, ...
                'RowSpacing', 10);
            c.runSummary = uilabel(grid, 'WordWrap', 'on', 'Text', '');
            buttonGrid = uigridlayout(grid, [1, 4], 'ColumnWidth', {240, 200, 280, '1x'}, 'Padding', 0);
            c.run = primaryButton(app, buttonGrid, '評価を始める', @(~, ~) app.onRun());
            c.resumeRun = uibutton(buttonGrid, 'Text', '続きから再開', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onResumeRun(), 'Tooltip', ['「一時中断」で止めた評価の残りを計算します' ...
                '（中断の後に設定を変えると再開できません）。']);
            c.extendRun = uibutton(buttonGrid, 'Text', '条件を追加して評価（評価済みに足す）', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onExtendRun(), 'Tooltip', ['評価の後に「2. 評価の設定」で手法や学習 Shot 数' ...
                '（計測率）を増やしてから押すと、増えた組み合わせだけを計算して今の結果に加えます。データ・質的変数・制約・' ...
                '評価の条件などを変えたときは追加できません（「評価を始める」で計算し直してください）。']);
            c.runStatus = uilabel(buttonGrid, 'WordWrap', 'on', 'Text', '');
            uilabel(grid, 'WordWrap', 'on', 'Text', ['評価の考え方：学習 Shot の計測値で推定し、学習しなかった Shot の計測値と比べます。' ...
                '実データには計測ノイズが含まれるので、誤差は模擬データの評価（真の値と比べた値）より少し大きく出ます。' ...
                '計算中は「一時中断」で途中までの結果を残して止め、「続きから再開」で残りを計算できます。' ...
                '評価の後に手法や学習 Shot 数を増やしたときは「条件を追加して評価」で、増えた分だけを計算して結果に足せます。']);
            lower = uigridlayout(grid, [1, 2], 'ColumnWidth', {'1x', '2.4x'}, 'Padding', 0, 'ColumnSpacing', 12);
            logGrid = uigridlayout(lower, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 0);
            label(logGrid, '記録（データの確認・学習パターン・推定できなかった組み合わせ）');
            c.log = uitextarea(logGrid, 'Editable', 'off', 'Value', {''});
            % 計測マップ：評価の前に、学習に使う（計測する）Shot を Wafer 上で確かめる
            mapPanel = uipanel(lower, 'Title', '計測マップ（学習に使う Shot。評価の前に確かめられます）');
            mapGrid = uigridlayout(mapPanel, [4, 1], 'RowHeight', {'fit', 'fit', '1x', 90}, 'Padding', 8, 'RowSpacing', 6);
            choose = uigridlayout(mapGrid, [2, 4], 'ColumnWidth', {'fit', '1x', 'fit', '1.4x'}, 'RowHeight', {66, 'fit'}, ...
                'Padding', 0);
            label(choose, 'Wafer', 1, 1);
            onMeasure = @(~, ~) app.onDrawMeasurementMap();
            multiTip = 'Ctrl・Shift で複数選ぶと、Wafer × 学習パターンの図を並べます（最大 6 枚）。';
            c.measureWafer = uilistbox(choose, 'Items', {'—'}, 'ItemsData', {1}, 'Multiselect', 'on', 'Tooltip', multiTip);
            place(c.measureWafer, 1, 2);
            label(choose, '学習パターン', 1, 3);
            c.measurePlan = uilistbox(choose, 'Items', {'—'}, 'Multiselect', 'on', 'Tooltip', multiTip);
            place(c.measurePlan, 1, 4);
            c.measureScan = uicheckbox(choose, 'Text', 'Scan 方向を色で示す（緑 ▲ = 1、紫 ▼ = 2）', 'Value', true, ...
                'ValueChangedFcn', onMeasure, 'Tooltip', ['緑の枠と ▲ が Scan 方向 1、紫の枠と ▼ が Scan 方向 2 の Shot' ...
                '（Scan 方向の制約で Shot 数がそろっているかを確かめる）。']);
            place(c.measureScan, 2, [1, 2]);
            c.measureRings = uicheckbox(choose, 'Text', '同心円の区切り（制約）を描く', 'Value', true, ...
                'ValueChangedFcn', onMeasure, 'Tooltip', ['I 最適・ランダムで同心円の制約を使うとき、区切りの半径（Shot 中心' ...
                'の半径）を橙の一点鎖線で描きます。']);
            place(c.measureRings, 2, [3, 4]);
            buttons = uigridlayout(mapGrid, [1, 3], 'ColumnWidth', {'fit', 'fit', 'fit'}, 'Padding', 0);
            c.drawMeasure = uibutton(buttons, 'Text', '計測マップを作る', 'ButtonPushedFcn', onMeasure);
            c.saveMeasure = uibutton(buttons, 'Text', '図を画像で保存…', 'ButtonPushedFcn', @(~, ~) app.onSaveMeasurementMap());
            c.exportMeasure = uibutton(buttons, 'Text', '計測マップを Excel に書き出す…', ...
                'ButtonPushedFcn', @(~, ~) app.onExportMeasurementMap(), 'Tooltip', ['選んだ Wafer の Shot ごとに、' ...
                'すべての学習パターンで計測するか（1）しないか（0）を書き出します。']);
            % 図は専用の枠に、並べる数に合わせて tiledlayout で作る（凡例を1つにまとめて右に置くため）
            c.measurePanel = uipanel(mapGrid, 'BorderType', 'none');
            c.measureAxes = gobjects(1, 0);
            c.measureInfo = uitextarea(mapGrid, 'Editable', 'off', 'Value', ...
                {'「2. 評価の設定」で学習 Shot の選び方を決め、Wafer と学習パターンを選んで「計測マップを作る」を押してください。'});
            app.Controls = mergeStruct(app.Controls, c);
        end

        function onResetScanDirections(app)
            runWithAlert(app, @() app.setScanDirection([], []), "Scan 方向を元に戻せませんでした", ...
                "「1. データの読み込み」の設定を確かめてください。");
        end

        function prepareEvaluation(app)
            % 評価の前に、読み込みの条件と設定を確かめる
            if ~isempty(app.Data) && (~isequal(currentMapping(app), app.AppliedMapping) || ...
                    ~isequal(currentDataOptions(app), dataOptions(app.Data)))
                invalidatePreparedData(app);
            end
            if isempty(app.Data)
                error('alignest:noData', '先に「1. データの読み込み」でデータを読み込んでください。');
            end
            controlsToSettings(app);
            settingsErrors = validateSettings(app);
            if ~isempty(settingsErrors)
                error('alignest:settings', '%s', strjoin(settingsErrors, newline));
            end
        end

        function results = evaluate(app, showProgress, previous, pauseAfter, mode)
            % 評価を実行して（previous があれば続きから、mode = "extend" なら条件を足して）結果の画面を更新する。
            % pauseAfter 件で一時中断する
            if nargin < 5
                mode = "resume";
            end
            c = app.Controls;
            set([c.run, c.resumeRun, c.extendRun], 'Enable', 'off');
            restore = onCleanup(@() set(c.run, 'Enable', 'on'));
            c.runStatus.Text = "計算中…";
            c.runStatus.FontColor = app.Palette.text;
            dialog = [];
            if showProgress
                dialog = uiprogressdlg(app.Figure, 'Title', '評価中', 'Message', '学習パターンを作っています…', ...
                    'Cancelable', 'on', 'CancelText', '一時中断', 'ShowPercentage', 'on');
            end
            timer = tic;
            lastUpdate = -Inf;
            startDone = 0;
            if ~isempty(previous)
                startDone = height(previous.table);
            end
            progressFcn = @(done, total, message) reportProgress(done, total, message);
            try
                results = alignest.runEvaluation(app.Data, app.Settings, progressFcn, previous, mode);
            catch err
                closeDialog(dialog);
                c.runStatus.Text = "⚠ 評価を実行できませんでした。";
                c.runStatus.FontColor = app.Palette.error;
                c.extendRun.Enable = onOff(~isempty(app.BaseResults) && ~isImportedResults(app.BaseResults));
                c.resumeRun.Enable = onOff(~isempty(app.BaseResults) && app.BaseResults.cancelled && ...
                    ~isImportedResults(app.BaseResults));
                rethrow(err);
            end
            closeDialog(dialog);
            app.BaseResults = results;
            app.Results = alignest.filterResults(results, app.Data, app.ResultFilter);
            app.MapCache = estimateCache(results);
            nFailed = nnz(results.table.note ~= "");
            if results.cancelled
                status = sprintf(['一時中断しました：%d / %d 件を計算済み（%.0f 秒）。結果一覧には途中までの結果が' ...
                    '出ています。「続きから再開」で残りを計算します。'], height(results.table), results.nTotal, ...
                    results.elapsedSeconds);
            elseif mode == "extend"
                status = sprintf("追加の評価が完了：新たに %d 件を計算し、評価済みの %d 件と合わせて %d 件になりました" + ...
                    "（計算時間は合計 %.0f 秒）。", height(results.table) - height(previous.table), height(previous.table), ...
                    height(results.table), results.elapsedSeconds);
            else
                status = sprintf("完了：%d 件を %.0f 秒で計算しました%s。", height(results.table), results.elapsedSeconds, ...
                    ternary(isempty(previous), "", "（一時中断の前と後の合計）"));
            end
            if nFailed > 0
                status = status + sprintf(" うち %d 件は推定できませんでした（理由は下の記録）。", nFailed);
            end
            c.runStatus.Text = status;
            c.log.Value = cellstr([status; results.additions(:); results.log(:)]);
            refreshResultControls(app);
            c.resumeRun.Enable = onOff(results.cancelled);
            c.extendRun.Enable = 'on';
            app.TabGroup.SelectedTab = app.Tabs.results;

            function continueRun = reportProgress(done, total, message)
                continueRun = done < pauseAfter;
                if isempty(dialog) || ~continueRun
                    return
                end
                elapsed = toc(timer);
                if elapsed - lastUpdate < app.PROGRESS_INTERVAL_SECONDS && done < total
                    continueRun = ~dialog.CancelRequested;
                    return
                end
                lastUpdate = elapsed;
                remaining = elapsed / max(done - startDone, 1) * (total - done);
                dialog.Value = done / total;
                dialog.Message = sprintf('%d / %d 件（残り 約 %s）\n%s', done, total, durationText(remaining), message);
                drawnow;
                continueRun = ~dialog.CancelRequested;
            end
        end

        function onResumeRun(app)
            runWithAlert(app, @() app.resumeEvaluation(true), "続きから再開できませんでした", ...
                "「評価を始める」で最初から計算してください。");
        end

        function onExtendRun(app)
            runWithAlert(app, @() app.extendEvaluation(true), "条件を追加して評価できませんでした", ...
                "「2. 評価の設定」で増やしたのが手法か学習 Shot 数（計測率）だけか確かめてください。" + ...
                "ほかの設定を変えたときは「評価を始める」で最初から計算してください。");
        end

        function onCompareDistributions(app)
            runWithAlert(app, @() app.compareDistributions(), "分布を比べられませんでした", ...
                "手法・学習パターン・Wafer を選び直して、もう一度試してください。");
        end

        function drawDistributionHistograms(app)
            % 「分布の比較」のヒストグラム（選んだ軸）：左は全面・学習・予測対象、右は予測対象の実測値と推定値
            c = app.Controls;
            if isempty(app.Distribution)
                return
            end
            spec = resultSpec(app);
            setChoices(c.distributionAxis, spec.labels, cellstr(spec.components));   % 1変数は X 成分（値の名前）だけ
            part = app.Distribution.(string(c.distributionAxis.Value));
            axisLabel = string(c.distributionAxis.Items{strcmp(c.distributionAxis.ItemsData, c.distributionAxis.Value)});
            alignest.plot.distributionHistograms(c.distributionAxes(1), part.samples(1:3), part.names(1:3), part.edges, ...
                axisLabel + " の計測値：全面・学習・予測対象", spec.unit);
            alignest.plot.distributionHistograms(c.distributionAxes(2), part.samples([3, 4]), part.names([3, 4]), part.edges, ...
                axisLabel + "：予測対象の実測値と推定値", spec.unit);
            set(c.distributionAxes, 'Visible', 'on', 'FontSize', app.AXES_FONT_SIZE);
            note = "";
            if isfield(app.Distribution, "note") && app.Distribution.note ~= ""
                note = "⚠ " + app.Distribution.note + "｜";
            end
            c.distributionInfo.Text = app.Distribution.title + "｜" + note + string(c.distributionInfo.UserData);
        end

        function onDrawMeasurementMap(app)
            runWithAlert(app, @() app.drawMeasurementMap(), "計測マップを作れませんでした", ...
                "「1. データの読み込み」と「2. 評価の設定」を確かめてから、もう一度試してください。");
        end

        function onSaveMeasurementMap(app)
            [fileName, folder] = uiputfile({'*.png', 'PNG 画像 (*.png)'}, '計測マップを保存', 'measurement_map.png');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            if runWithAlert(app, @() exportgraphics(app.Controls.measurePanel, target, 'Resolution', 150), ...
                    "計測マップを保存できませんでした", "保存先のフォルダを変えてもう一度試してください。")
                uialert(app.Figure, sprintf('計測マップを保存しました：%s', target), '保存しました', 'Icon', 'success');
            end
        end

        function onExportMeasurementMap(app)
            [fileName, folder] = uiputfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, '計測マップを書き出す', 'measurement_map.xlsx');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            if runWithAlert(app, @() app.exportMeasurementMap(target), "計測マップを書き出せませんでした", ...
                    "同じ名前の Excel を開いていれば閉じて、もう一度試してください。")
                uialert(app.Figure, sprintf('計測マップを書き出しました：%s', target), '書き出しました', 'Icon', 'success');
            end
        end

        function plan = measurementPlan(app, unitIndex, spec, dialog)
            % 計測マップ用の学習パターン（評価と同じ作り方。同じ配置の Wafer・同じ設定では使い回す）
            if ~isa(app.MeasurementCache, 'containers.Map')
                app.MeasurementCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
            end
            if ~isempty(dialog)
                dialog.Message = sprintf("%s の「%s」を作っています…", app.Data.units(unitIndex).label, spec.label);
            end
            plan = alignest.cachedTrainingPlan(app.Data.units(unitIndex), spec, app.Settings, app.MeasurementCache);
        end

        function text = rateExample(app, rates)
            % 計測率から決まる Shot 数の例（最初の Wafer の候補 Shot 数で）
            text = "";
            if isempty(app.Data)
                return
            end
            unit = app.Data.units(1);
            nCandidates = nnz(unit.shots.nValidX + unit.shots.nValidY > 0);
            counts = max(1, round(rates / 100 * nCandidates));
            text = sprintf("。%s（候補 %d Shot）では %s Shot", unit.label, nCandidates, ...
                previewList(counts, app.LIST_PREVIEW_COUNT));
        end

        function text = exchangeText(app)
            % 交換法で学習パターンを作る時間の目安（alignest.exchangeSecondsGuide。I 最適のときだけ）
            c = app.Controls;
            text = "";
            if ~any(ismember(string(c.samplingMethod.Value), ["ioptimal", "doptimal"]))
                return
            end
            nCandidates = 99;
            source = "候補 99 Shot として";
            if ~isempty(app.Data)
                unit = app.Data.units(1);
                nCandidates = nnz(unit.shots.nValidX + unit.shots.nValidY > 0);
                source = sprintf("%s の候補 %d Shot で", unit.label, nCandidates);
            end
            try
                if string(c.countBy.Value) == "rate"
                    rates = alignest.measurementRateList(c.rateStart.Value, c.rateEnd.Value, c.rateStep.Value);
                    counts = max(1, round(rates / 100 * nCandidates));
                else
                    counts = alignest.shotCountList(c.nShotsStart.Value, c.nShotsEnd.Value, c.nShotsStep.Value);
                end
            catch
                return   % 学習 Shot 数の欄が正しくないとき（欄の下に理由が出る）
            end
            seconds = alignest.exchangeSecondsGuide(counts, c.exchangeStarts.Value, nCandidates);
            text = sprintf("→ 目安（%s）：学習パターン1つ 約 %s〜%s、全 %d 個で 約 %s（配置が同じ Wafer は使い回す）", ...
                source, durationText(min(seconds)), durationText(max(seconds)), numel(counts), durationText(sum(seconds)));
        end

        function text = requiredText(app)
            % 必ず計測する Shot の数（最初の Wafer で。画面の入力から数える）
            c = app.Controls;
            text = "";
            [values, ok] = parseNumbers(c.requiredShots.Value);
            if ~ok || isempty(app.Data)
                return
            end
            sampling = struct("requiredShots", values, "requireOuterShots", c.requireOuter.Value);
            unit = app.Data.units(1);
            candidates = find(unit.shots.nValidX + unit.shots.nValidY > 0);
            [index, details] = alignest.requiredShotIndex(unit.shots, candidates, sampling);
            if isempty(index) && isempty(details.missingNos)
                text = "→ 必ず計測する Shot はありません（すべての学習 Shot を選び方に従って選びます）。";
                return
            end
            text = sprintf("→ %s では %d Shot を必ず計測（指定 %d・最外周 %d", unit.label, numel(index), ...
                numel(details.specified), numel(details.outer));
            overlap = numel(details.specified) + numel(details.outer) - numel(index);
            text = text + ternary(overlap > 0, sprintf("、重なり %d）", overlap), "）");
            if ~isempty(details.missingNos)
                text = text + "。この Wafer に無い、または計測値の無い shotNo：" + strjoin(string(details.missingNos.'), " ");
            end
            text = text + "。「3. 実行」の計測マップで確かめられます。";
        end

        function onRun(app)
            runWithAlert(app, @() app.runEvaluationNow(true), "評価を実行できませんでした", ...
                "「1. データの読み込み」と「2. 評価の設定」を確かめてから、もう一度実行してください。");
        end

        function refreshRunSummary(app)
            c = app.Controls;
            if ~isfield(c, 'runSummary')
                return
            end
            try
                methods = alignest.buildMethodList(app.Settings.methods);
            catch
                % 手法の設定が正しくないとき（欄の下に理由が出る）は数えない
                methods = struct("id", {}, "family", {});
            end
            try
                specs = alignest.buildPlanSpecs(app.Settings.sampling);
                nPlans = numel(specs);
            catch
                nPlans = 0;
            end
            nUnits = 0;
            if ~isempty(app.Data)
                nUnits = numel(app.Data.units);
            end
            total = numel(methods) * nPlans * nUnits;
            seconds = 0;
            detail = struct("nMaternNuMethods", 0, "maternNuFactor", 1, "secondsPerRun", 2);
            if nUnits > 0 && nPlans > 0
                try
                    [seconds, detail] = alignest.estimateRunSeconds(app.Data.units, app.Settings);
                catch
                    % 設定が正しくないときは目安を出さない（「2. 評価の設定」に理由が出る）
                end
            end
            nuText = "";
            if detail.nMaternNuMethods > 0
                % ν を指定した Matérn は ν ごとに手法が増え、1条件の時間も長いので、目安に含めたことを示す
                nuText = sprintf("。うち ν を指定した Matérn の手法 %d 種類は 1条件 %g 秒で見積もり", ...
                    detail.nMaternNuMethods, detail.secondsPerRun * detail.maternNuFactor);
            end
            text = sprintf("手法 %d 種類 × 学習パターン %d × Wafer %d 枚 = %d 回の推定（目安 %s%s）", ...
                numel(methods), nPlans, nUnits, total, durationText(seconds), nuText);
            c.countLabel.Text = text;
            if nUnits == 0
                c.runSummary.Text = "データがまだ読み込まれていません。「1. データの読み込み」から始めてください。";
            elseif isempty(methods)
                c.runSummary.Text = "比べる手法が選ばれていません。「2. 評価の設定」で手法を選んでください。";
            else
                c.runSummary.Text = "これから計算する組み合わせ：" + text + "。";
            end
            refreshMeasurementChoices(app);
        end

        function refreshMeasurementChoices(app)
            % 計測マップの Wafer・学習パターンの選択肢を、データと設定に合わせる。設定が変わったら描いた図を消す
            c = app.Controls;
            if ~isfield(c, 'measurePlan')
                return
            end
            labels = "—";
            try
                specs = alignest.buildPlanSpecs(app.Settings.sampling);
                labels = unique(string({specs.label}), 'stable');
            catch
                % 設定が正しくないときは選べない（「2. 評価の設定」に理由が出る）
            end
            if ~isequal(string(c.measurePlan.Items), labels)
                previous = string(c.measurePlan.Value);
                c.measurePlan.Items = cellstr(labels);
                kept = previous(ismember(previous, labels));
                if isempty(kept)
                    kept = labels(1);
                end
                c.measurePlan.Value = cellstr(kept);
            end
            units = "—";
            if ~isempty(app.Data)
                units = string({app.Data.units.label});
            end
            if ~isequal(string(c.measureWafer.Items), units)
                c.measureWafer.Items = cellstr(units);
                c.measureWafer.ItemsData = num2cell(1:numel(units));
                c.measureWafer.Value = {1};
            end
            signature = {app.Settings.sampling, app.Settings.data.waferRadiusMm, numel(app.Data)};
            if ~isequaln(signature, c.measurePanel.UserData)
                app.MeasurementCache = [];
                if ~isempty(c.measurePanel.Children)
                    clearMeasurePanel(app);
                    c.measureInfo.Value = {'設定またはデータが変わりました。「計測マップを作る」で作り直してください。'};
                end
                c.measurePanel.UserData = signature;
            end
        end

        function lines = measurementLines(app, unit, plan)
            % 計測マップの説明（Shot 数・計測率・必ず計測した数・I 基準・D 基準・shotNo・メモ）
            nCandidates = nnz(unit.shots.nValidX + unit.shots.nValidY > 0);
            if ~isempty(plan.markIndex)
                % Mark 単位の計画：計測する Mark の数と、Mark 番号ごとの数（全計測での割合と比べる）
                marks = unit.marks;
                candidateMarks = ismember(marks.shotIndex, find(unit.shots.nValidX + unit.shots.nValidY > 0)) & ...
                    (marks.validX | marks.validY);
                levels = unique(marks.markNo(candidateMarks)).';
                shares = string(arrayfun(@(level) sprintf("M%d %d（全計測 %.0f%%）", level, ...
                    nnz(marks.markNo(plan.markIndex) == level), 100 * nnz(marks.markNo(candidateMarks) == level) / ...
                    nnz(candidateMarks)), levels, 'UniformOutput', false));
                lines = sprintf(['%s｜%s｜計測 %d / 候補 %d Mark（計測率 %.1f%%）｜全 %d Shot で1点以上｜I 基準 %.4g・' ...
                    'D 基準 %.4g｜全計測に対する I 効率 %.1f%%・D 効率 %.1f%%｜制約の違反量 %d'], unit.label, plan.label, ...
                    numel(plan.markIndex), nnz(candidateMarks), 100 * numel(plan.markIndex) / max(nnz(candidateMarks), 1), ...
                    nCandidates, plan.criterionI, plan.criterionD, 100 * plan.efficiencyI, 100 * plan.efficiencyD, plan.violation);
                lines = [lines; "Mark 番号ごとの計測数：" + strjoin(shares, "、")];
                if plan.message ~= ""
                    lines = [lines; "メモ：" + plan.message];
                end
                return
            end
            lines = sprintf(['%s｜%s｜計測 %d / 候補 %d Shot（計測率 %.1f%%）｜必ず計測 %d Shot｜I 基準 %.4g・D 基準 %.4g' ...
                '｜全計測に対する I 効率 %.1f%%・D 効率 %.1f%%'], unit.label, plan.label, plan.nShots, nCandidates, ...
                100 * plan.nShots / max(nCandidates, 1), numel(plan.requiredShotIndex), plan.criterionI, plan.criterionD, ...
                100 * plan.efficiencyI, 100 * plan.efficiencyD);
            if any(plan.type == ["ioptimal", "doptimal", "random"])
                lines = lines + sprintf("｜制約の違反量 %d", plan.violation);
            end
            lines = [lines; "計測する shotNo：" + strjoin(string(plan.shotNos(:).'), " ")];
            if plan.message ~= ""
                lines = [lines; "メモ：" + plan.message];
            end
        end

        function layout = resetMeasurePanel(app, nPanels)
            % 計測マップの枠を空にし、nPanels 枚を並べる tiledlayout を作る（枠の縦横に合わせ、1枚が最も大きくなる並べ方）
            clearMeasurePanel(app);
            [nRows, nColumns] = tileShape(app.Controls.measurePanel, nPanels);
            layout = tiledlayout(app.Controls.measurePanel, nRows, nColumns, 'TileSpacing', 'compact', 'Padding', 'compact');
        end

        function clearMeasurePanel(app)
            % 描いた計測マップを消す（枠の中の tiledlayout と図）
            delete(app.Controls.measurePanel.Children);
            app.Controls.measureAxes = gobjects(1, 0);
        end

        % ================= 4. 結果一覧 =================
        function buildResultsTab(app)
            grid = uigridlayout(app.Tabs.results, [3, 1], 'RowHeight', {'fit', 'fit', '1x'}, 'Padding', 12, 'RowSpacing', 8);
            controls = uigridlayout(grid, [3, 7], 'ColumnWidth', {260, 160, '1x', 'fit', 'fit', 'fit', 'fit'}, 'Padding', 0, ...
                'RowHeight', {'fit', 'fit', 0});
            label(controls, '指標', 1, 1);
            label(controls, '集計（Wafer 間）', 1, 2);
            label(controls, '基準の手法（「基準の手法との比較」で比べる相手）', 1, 3);
            [names, labels] = alignest.metricNames();
            onChange = @(~, ~) app.refreshResults();
            c.metric = uidropdown(controls, 'Items', cellstr(labels), 'ItemsData', cellstr(names), 'Value', 'RMSE_XY', ...
                'ValueChangedFcn', onChange);
            place(c.metric, 2, 1);
            [statistics, statisticLabels] = alignest.statisticNames();
            c.statistic = uidropdown(controls, 'Items', cellstr(statisticLabels), 'ItemsData', cellstr(statistics), ...
                'Tooltip', ['ワースト値：最も悪い Wafer の値（誤差は最大、R² は最小）。' ...
                '95%値：95% の Wafer がこの値より良い（誤差は 95 パーセント点、R² は 5 パーセント点）。'], ...
                'ValueChangedFcn', onChange);
            place(c.statistic, 2, 2);
            c.reference = uidropdown(controls, 'Items', {'—'}, 'ValueChangedFcn', onChange);
            place(c.reference, 2, 3);
            c.export = primaryButton(app, controls, '結果を Excel に書き出す…', @(~, ~) app.onExport());
            place(c.export, 2, 4);
            c.saveChart = uibutton(controls, 'Text', 'グラフを画像で保存…', 'ButtonPushedFcn', @(~, ~) app.onSaveChart());
            place(c.saveChart, 2, 5);
            set([c.export, c.saveChart], 'Enable', 'off');
            c.importResults = uibutton(controls, 'Text', '結果を読み込む…', 'ButtonPushedFcn', @(~, ~) app.onImportResults(), ...
                'Tooltip', '「結果を Excel に書き出す」で書き出したファイルを読み込み、表・グラフ・基準の手法との比較を見ます。');
            place(c.importResults, 2, 6);
            c.importEstimates = uibutton(controls, 'Text', '推定値の Excel を読み込む…', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onImportEstimates(), 'Tooltip', ['「推定値を Excel に書き出す」で書き出した' ...
                'ファイルを読み込むと、Excel から読み込んだ結果でも Wafer マップ・推定値と誤差の分布・散布図・分布の比較を' ...
                '描けます（書き出した範囲だけ）。先に「結果を読み込む…」で評価結果を読み込んでください。']);
            place(c.importEstimates, 2, 7);
            c.resultSource = uilabel(controls, 'WordWrap', 'on', 'Text', '');
            c.resultSource.Layout.Row = 3;
            c.resultSource.Layout.Column = [1, 7];
            c.resultControls = controls;
            c.filterResults = buildFilterControls(app, grid, "results");

            % 表・グラフ・比較・誤差の分布は、それぞれ画面の幅いっぱいに出す（手法の名前が切れないように）
            c.resultTabs = uitabgroup(grid);
            tableTab = uitab(c.resultTabs, 'Title', '表（手法 × 学習パターン）');
            tableGrid = uigridlayout(tableTab, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 8);
            c.tableNote = uilabel(tableGrid, 'WordWrap', 'on', ...
                'Text', ['各列で最も良い手法に「★」を付け、背景も色づけしています。集計の「ワースト値」は最も悪い Wafer の値、' ...
                '「95%値」は 95% の Wafer がそれより良い値（誤差は大きい側、R²・改善率は小さい側）です。']);
            c.summaryTable = uitable(tableGrid, 'RowName', {}, 'ColumnName', {'手法'});
            c.chartTab = uitab(c.resultTabs, 'Title', 'グラフ');
            chartGrid = uigridlayout(c.chartTab, [2, 2], 'RowHeight', {'fit', '1x'}, 'ColumnWidth', {'1x', 380}, 'Padding', 8);
            chartControls = uigridlayout(chartGrid, [1, 5], 'ColumnWidth', {'fit', 380, 'fit', 190, 'fit'}, 'Padding', 0);
            place(chartControls, 1, 1);
            label(chartControls, '横軸', 1, 1);
            c.chartXAxis = uidropdown(chartControls, 'Items', {'学習 Shot 数（学習パターン）', ...
                'I 基準と D 基準（I 最適計画の評価指標。2つ並べる）'}, 'ItemsData', {'plan', 'criteria'}, ...
                'Tooltip', ['学習 Shot の組の I 基準 tr(M⁻¹) と D 基準 det(M)^(−1/p)（XY 多項式の基準モデル）に対する推定誤差。' ...
                '点は学習パターンの列ごとの Wafer の集計。基準は Wafer の平均。'], 'ValueChangedFcn', @(~, ~) app.drawChart());
            place(c.chartXAxis, 1, 2);
            label(chartControls, 'エラーバー', 1, 3);
            c.chartErrorBars = uidropdown(chartControls, 'Items', {'なし', '±1σ（Wafer 間）', '95% 区間（平均）'}, ...
                'ItemsData', {'none', 'sd', 'ci'}, 'ValueChangedFcn', @(~, ~) app.drawChart(), ...
                'Tooltip', ['±1σ：Wafer ごとの値（ランダムのくり返しは平均）の標準偏差。95% 区間：Wafer の平均の区間' ...
                '（± 1.96σ/√Wafer 数）。点の値（平均・中央値など、上の「集計」）を中心に描きます。']);
            place(c.chartErrorBars, 1, 4);
            c.chartPoints = uicheckbox(chartControls, 'Text', 'Wafer ごとの点（I・D 基準）', ...
                'ValueChangedFcn', @(~, ~) app.drawChart());
            place(c.chartPoints, 1, 5);
            c.chartPanel = uipanel(chartGrid, 'BorderType', 'none');
            place(c.chartPanel, 2, 1);
            c.chartAxesGrid = uigridlayout(c.chartPanel, [1, 2], 'ColumnWidth', {'1x', 0}, 'Padding', 0, 'ColumnSpacing', 8);
            c.chartAxes = uiaxes(c.chartAxesGrid);
            c.chartAxes2 = uiaxes(c.chartAxesGrid, 'Visible', 'off');
            label(chartGrid, 'グラフに描く手法（Ctrl・Shift で複数選ぶ）', 1, 2);
            c.chartMethods = uilistbox(chartGrid, 'Items', {}, 'Multiselect', 'on', 'ValueChangedFcn', @(~, ~) app.drawChart());
            place(c.chartMethods, 2, 2);
            compareTab = uitab(c.resultTabs, 'Title', '基準の手法との比較');
            compareGrid = uigridlayout(compareTab, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 8);
            c.comparisonNote = uilabel(compareGrid, 'WordWrap', 'on', 'Text', '');
            c.comparisonTable = uitable(compareGrid, 'RowName', {}, ...
                'ColumnName', {'手法', '列', '基準との差', '95% 区間', '基準より良かった割合', 'Wafer 数'});
            % 計測配置の比較：選び方（I 最適・D 最適・人の選択など）ごとに、学習点の数に対する指標を比べる
            c.layoutCompareTab = uitab(c.resultTabs, 'Title', '計測配置の比較');
            layoutGrid = uigridlayout(c.layoutCompareTab, [3, 2], 'RowHeight', {'fit', '1x', 'fit'}, ...
                'ColumnWidth', {'1.2x', '1x'}, 'Padding', 8, 'ColumnSpacing', 12);
            layoutControls = uigridlayout(layoutGrid, [1, 4], 'ColumnWidth', {'fit', '1x', 'fit', 220}, 'Padding', 0);
            place(layoutControls, 1, [1, 2]);
            label(layoutControls, '手法', 1, 1);
            c.compareLayoutMethod = uidropdown(layoutControls, 'Items', {'—'}, 'Enable', 'off', ...
                'ValueChangedFcn', @(~, ~) app.drawLayoutComparison());
            place(c.compareLayoutMethod, 1, 2);
            label(layoutControls, '横軸', 1, 3);
            c.compareLayoutXAxis = uidropdown(layoutControls, 'Items', {'計測する Mark の数', '学習 Shot 数'}, ...
                'ItemsData', {'marks', 'shots'}, 'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.drawLayoutComparison(), ...
                'Tooltip', ['計測する Mark の数：Shot 単位と Mark 単位の計画を同じ計測の手間で比べる。学習 Shot 数：Shot 単位の' ...
                '計画どうしを比べる（Mark 単位の計画は全 Shot を計測するので右端に寄る）。']);
            place(c.compareLayoutXAxis, 1, 4);
            c.compareLayoutAxes = uiaxes(layoutGrid);
            place(c.compareLayoutAxes, 2, 1);
            c.compareLayoutTable = uitable(layoutGrid, 'RowName', {}, 'ColumnName', {'選び方', '列', '学習 Shot 数', ...
                '計測 Mark 数', '指標', 'I 基準', 'D 基準'}, 'ColumnWidth', {120, 150, 80, 80, 'auto', 70, 70});
            place(c.compareLayoutTable, 2, 2);
            layoutNote = ['「2. 評価の設定」の選び方を2つ以上選んで評価すると、選び方ごとの線（人の選択・手動は点）で比べられます' ...
                '（指標と Wafer の集計は上の「指標」「集計」）。I 基準・D 基準は小さいほど良い計画（Wafer の平均）。'];
            c.compareLayoutInfo = uilabel(layoutGrid, 'WordWrap', 'on', 'Text', layoutNote, 'UserData', string(layoutNote));
            place(c.compareLayoutInfo, 3, [1, 2]);

            analysisTab = uitab(c.resultTabs, 'Title', '推定値と誤差の分布');
            analysisGrid = uigridlayout(analysisTab, [5, 1], 'RowHeight', {'fit', '1.6x', 96, '1x', 'fit'}, ...
                'Padding', 8, 'RowSpacing', 8);
            analysisControls = uigridlayout(analysisGrid, [2, 6], 'ColumnWidth', {'1x', 150, 220, 'fit', 300, 'fit'}, ...
                'RowHeight', {'fit', 'fit'}, 'Padding', 0);
            label(analysisControls, '手法', 1, 1);
            label(analysisControls, '学習パターン（列）', 1, 2);
            label(analysisControls, 'Wafer', 1, 3);
            label(analysisControls, 'Excel に書き出す範囲', 1, 5);
            c.analysisMethod = uidropdown(analysisControls, 'Items', {'—'});
            place(c.analysisMethod, 2, 1);
            c.analysisGroup = uidropdown(analysisControls, 'Items', {'—'});
            place(c.analysisGroup, 2, 2);
            c.analysisWafer = uidropdown(analysisControls, 'Items', {'—'});
            place(c.analysisWafer, 2, 3);
            c.analyze = uibutton(analysisControls, 'Text', '分析する', 'ButtonPushedFcn', @(~, ~) app.onAnalyze());
            place(c.analyze, 2, 4);
            c.estimateScope = uidropdown(analysisControls, 'Items', {'左で選んだ手法・学習パターン・Wafer', ...
                'すべての手法・学習パターン・Wafer（行が多い）'}, 'ItemsData', {'selected', 'all'});
            place(c.estimateScope, 2, 5);
            c.exportEstimates = uibutton(analysisControls, 'Text', '推定値を Excel に書き出す…', ...
                'ButtonPushedFcn', @(~, ~) app.onExportEstimates());
            place(c.exportEstimates, 2, 6);
            c.histogramGrid = uigridlayout(analysisGrid, [1, 2], 'Padding', 0, 'ColumnSpacing', 12);
            c.histogramAxes = [uiaxes(c.histogramGrid), uiaxes(c.histogramGrid)];
            c.normalityTable = uitable(analysisGrid, 'RowName', {}, 'ColumnName', {'軸', '点数', '平均 [nm]', ...
                '標準偏差 [nm]', '歪度', '尖度（過剰）', 'Shapiro–Wilk W', 'p 値', 'Anderson–Darling A²', 'p 値', ...
                'Jarque–Bera', 'p 値', '判定（5%）'}, ...
                'ColumnWidth', {40, 60, 80, 105, 60, 90, 120, 70, 155, 70, 100, 70, 'auto'});
            c.anovaTable = uitable(analysisGrid, 'RowName', {}, 'ColumnName', {'軸', '質的変数', ...
                '水準ごとの平均残差 [nm]（点数）', 'F（一元配置）', 'p 値', 'η²', 'F（ほかの変数で調整）', 'p 値', ...
                '判定（一元配置、5%）・メモ'}, 'ColumnWidth', {40, 125, 340, 100, 70, 55, 150, 70, 'auto'});
            noteText = ['残差 = 計測値 − 推定値（評価点）。p 値 < 0.05 なら、正規分布から外れている（ANOVA は水準で残差の' ...
                '平均が違う）と判断。点数が多いと小さなずれでも p 値が小さくなるので、ヒストグラムと合わせて見てください。'];
            c.analysisNote = uilabel(analysisGrid, 'WordWrap', 'on', 'Text', noteText, 'UserData', string(noteText), ...
                'Tooltip', ['評価点は学習しなかった Shot の有効な Mark。選んだ Wafer の評価点をまとめて検定します。' ...
                'Shapiro–Wilk は 5000 点以下のときだけ計算し、判定に使います（超えるときは Anderson–Darling）。' ...
                '「ほかの変数で調整」は、ほかの質的変数の効果を差し引いた主効果（交互作用なし、Type II）の検定です。']);
            % 残差の箱ひげ図：「推定値と誤差の分布」で分析した残差を、質的変数の水準ごとに X・Y 別に描く（ANOVA の中身を見る）
            c.boxTab = uitab(c.resultTabs, 'Title', '残差の箱ひげ図（ANOVA）');
            boxGrid = uigridlayout(c.boxTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 8, 'RowSpacing', 8);
            boxControls = uigridlayout(boxGrid, [1, 3], 'ColumnWidth', {'fit', 260, '1x'}, 'Padding', 0);
            label(boxControls, '質的変数', 1, 1);
            c.boxFactor = uidropdown(boxControls, 'Items', {'—'}, 'Enable', 'off', ...
                'ValueChangedFcn', @(~, ~) app.onDrawResidualBoxplot(), 'Tooltip', ['「推定値と誤差の分布」の ANOVA と同じ' ...
                '質的変数（Scan 方向・Mark 番号・Shot 行の奇偶・工程・装置・ロット・その他の列）。']);
            place(c.boxFactor, 1, 2);
            boxHelp = label(boxControls, ['「推定値と誤差の分布」で「分析する」を押した残差を描きます。箱は四分位範囲、中の線は' ...
                '中央値、ひげは箱から 1.5 × 四分位範囲まで、外の点は外れ値、◆ は平均（ANOVA は水準の平均の違いを調べる）。'], 1, 3);
            boxHelp.FontColor = app.Palette.muted;
            boxAxesGrid = uigridlayout(boxGrid, [1, 2], 'Padding', 0, 'ColumnSpacing', 12);
            c.boxAxes = [uiaxes(boxAxesGrid), uiaxes(boxAxesGrid)];
            set(c.boxAxes, 'Visible', 'off');
            c.boxInfo = uilabel(boxGrid, 'WordWrap', 'on', 'Text', '');
            c.scatterTab = uitab(c.resultTabs, 'Title', '推定値と実測値の散布図');
            scatterGrid = uigridlayout(c.scatterTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 8, 'RowSpacing', 8);
            scatterControls = uigridlayout(scatterGrid, [2, 5], 'ColumnWidth', {'1x', 150, 220, 240, 'fit'}, ...
                'RowHeight', {'fit', 'fit'}, 'Padding', 0);
            label(scatterControls, '手法', 1, 1);
            label(scatterControls, '学習パターン（列）', 1, 2);
            label(scatterControls, 'Wafer', 1, 3);
            label(scatterControls, '色分け', 1, 4);
            c.scatterMethod = uidropdown(scatterControls, 'Items', {'—'});
            place(c.scatterMethod, 2, 1);
            c.scatterGroup = uidropdown(scatterControls, 'Items', {'—'});
            place(c.scatterGroup, 2, 2);
            c.scatterWafer = uidropdown(scatterControls, 'Items', {'—'});
            place(c.scatterWafer, 2, 3);
            c.scatterColor = uidropdown(scatterControls, 'Items', {'—'}, ...
                'Tooltip', ['点の色を分ける項目（LotID・EqpId・Operation・Scan 方向・Mark 番号・Shot 行・外周と内側' ...
                '（「2. 評価の設定」の外周の半径）・象限・ファイルのその他の列）']);
            place(c.scatterColor, 2, 4);
            c.drawScatterButton = uibutton(scatterControls, 'Text', '描く', 'ButtonPushedFcn', @(~, ~) app.onDrawScatter());
            place(c.drawScatterButton, 2, 5);
            c.scatterAxesGrid = uigridlayout(scatterGrid, [1, 2], 'Padding', 0, 'ColumnSpacing', 12);
            c.scatterAxes = [uiaxes(c.scatterAxesGrid), uiaxes(c.scatterAxesGrid)];
            c.scatterInfo = uilabel(scatterGrid, 'WordWrap', 'on', 'Text', ['評価点（学習しなかった Shot の有効な Mark）の' ...
                '実測値と推定値。破線は y = x、赤い線は回帰直線（推定値 = a + b·実測値）。r は相関係数。']);
            % 分布の比較：Wafer 全面・学習データ・予測対象の計測値と、予測対象の実測値と推定値
            c.distributionTab = uitab(c.resultTabs, 'Title', '分布の比較');
            distributionGrid = uigridlayout(c.distributionTab, [4, 1], 'RowHeight', {'fit', '1x', 300, 'fit'}, ...
                'Padding', 8, 'RowSpacing', 8);
            distributionControls = uigridlayout(distributionGrid, [2, 5], 'ColumnWidth', {'1x', 150, 220, 90, 'fit'}, ...
                'RowHeight', {'fit', 'fit'}, 'Padding', 0);
            label(distributionControls, '手法', 1, 1);
            label(distributionControls, '学習パターン（列）', 1, 2);
            label(distributionControls, 'Wafer', 1, 3);
            label(distributionControls, '軸', 1, 4);
            c.distributionMethod = uidropdown(distributionControls, 'Items', {'—'});
            place(c.distributionMethod, 2, 1);
            c.distributionGroup = uidropdown(distributionControls, 'Items', {'—'});
            place(c.distributionGroup, 2, 2);
            c.distributionWafer = uidropdown(distributionControls, 'Items', {'—'});
            place(c.distributionWafer, 2, 3);
            c.distributionAxis = uidropdown(distributionControls, 'Items', {'X', 'Y'}, 'ItemsData', {'X', 'Y'}, ...
                'ValueChangedFcn', @(~, ~) app.drawDistributionHistograms());
            place(c.distributionAxis, 2, 4);
            c.compareDistributionsButton = uibutton(distributionControls, 'Text', '比べる', ...
                'ButtonPushedFcn', @(~, ~) app.onCompareDistributions());
            place(c.compareDistributionsButton, 2, 5);
            distributionAxesGrid = uigridlayout(distributionGrid, [1, 2], 'Padding', 0, 'ColumnSpacing', 12);
            c.distributionAxes = [uiaxes(distributionAxesGrid), uiaxes(distributionAxesGrid)];
            set(c.distributionAxes, 'Visible', 'off');
            tableGrid = uigridlayout(distributionGrid, [1, 2], 'ColumnWidth', {'1.4x', '1x'}, 'Padding', 0, 'ColumnSpacing', 12);
            c.distributionTable = uitable(tableGrid, 'RowName', {}, 'ColumnName', {'軸', '分布', '点数', '平均 [nm]', ...
                '標準偏差 [nm]', '中央値 [nm]', '最小 [nm]', '最大 [nm]', '|平均|+3σ [nm]'}, ...
                'ColumnWidth', {35, 150, 55, 80, 100, 85, 80, 80, 'auto'});
            c.jsTable = uitable(tableGrid, 'RowName', {}, 'ColumnName', {'軸', '比べる分布', 'JS ダイバージェンス', ...
                '見ること'}, 'ColumnWidth', {35, 270, 120, 'auto'});
            distributionNote = ['左：Wafer 全面・学習データ・予測対象（学習しなかった Shot の有効な Mark）の計測値。' ...
                '右：予測対象の実測値と推定値。ヒストグラムは4つに共通の区間の割合。JS ダイバージェンス（Jensen–Shannon、' ...
                '底 2）は分布の一致性で、0 なら同じ、1 なら重なりなし（同じ区間で求める）。'];
            c.distributionInfo = uilabel(distributionGrid, 'WordWrap', 'on', 'Text', distributionNote, ...
                'UserData', string(distributionNote));
            % 処理時間の内訳：1つの条件の処理を段階（学習パターンの作成・異常値の判定・学習・推論など）に分けて測る
            c.timingTab = uitab(c.resultTabs, 'Title', '処理時間の内訳');
            timingGrid = uigridlayout(c.timingTab, [4, 1], 'RowHeight', {'fit', '1x', 120, 'fit'}, 'Padding', 8, ...
                'RowSpacing', 8);
            timingControls = uigridlayout(timingGrid, [2, 5], 'ColumnWidth', {220, 220, '1x', 110, 'fit'}, ...
                'RowHeight', {'fit', 66}, 'Padding', 0);
            label(timingControls, 'Wafer', 1, 1);
            label(timingControls, '学習パターン', 1, 2);
            label(timingControls, '手法（Ctrl・Shift で複数選ぶ）', 1, 3);
            label(timingControls, '測る回数', 1, 4);
            c.timingWafer = uidropdown(timingControls, 'Items', {'—'}, 'Enable', 'off');
            place(c.timingWafer, 2, 1);
            c.timingPlan = uidropdown(timingControls, 'Items', {'—'}, 'Enable', 'off');
            place(c.timingPlan, 2, 2);
            c.timingMethods = uilistbox(timingControls, 'Items', {}, 'Multiselect', 'on', 'Enable', 'off');
            place(c.timingMethods, 2, 3);
            c.timingRepeats = uispinner(timingControls, 'Limits', app.TIMING_REPEAT_LIMITS, 'Value', 3, ...
                'RoundFractionalValues', 'on', 'Enable', 'off', 'Tooltip', '同じ計算を何回測って中央値をとるか（多いほど安定するが遅い）。');
            place(c.timingRepeats, 2, 4);
            c.measureTimingButton = uibutton(timingControls, 'Text', '測る', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onMeasureTiming());
            place(c.measureTimingButton, 2, 5);
            timingAxesGrid = uigridlayout(timingGrid, [1, 2], 'ColumnWidth', {'1x', '1.2x'}, 'Padding', 0, 'ColumnSpacing', 12);
            c.timingAxes = [uiaxes(timingAxesGrid), uiaxes(timingAxesGrid)];
            set(c.timingAxes, 'Visible', 'off');
            c.timingTable = uitable(timingGrid, 'RowName', {}, 'ColumnName', {'手法'});
            timingNote = ['選んだ Wafer・学習パターン・手法の1回分の処理（学習パターンの作成 → 異常値の判定 → 推定の準備 → ' ...
                '学習 → 推論 → 評価指標・Overlay 補正の評価）を、評価と同じ関数で測ります（評価の結果は変えません）。' ...
                '学習と推論は、全評価点を推定した時間と評価点を1点にした時間の差を推論としています。評価では学習パターンを' ...
                '同じ配置の Wafer・手法で使い回すので、評価全体に占める作成の割合はこれより小さくなります。'];
            c.timingInfo = uilabel(timingGrid, 'WordWrap', 'on', 'Text', timingNote, 'UserData', string(timingNote));
            app.Controls = mergeStruct(app.Controls, c);
        end

        function f = buildFilterControls(app, parent, source)
            % 評価点の絞り込みの欄。「4. 結果一覧」と「5. Waferごとのマップ」に同じものを置き、どちらで変えても両方をそろえる
            f.grid = uigridlayout(parent, [2, 14], 'ColumnWidth', {'fit', 64, 'fit', 64, 'fit', 175, 110, 'fit', 80, 'fit', ...
                160, 'fit', 'fit', '1x'}, 'RowHeight', {'fit', 'fit'}, 'Padding', 0, 'ColumnSpacing', 6, 'RowSpacing', 2);
            filterTip = ['評価点（学習しなかった Shot の Mark）を、Mark の半径・Shot の条件で絞り込み、指標を計算し直して' ...
                '表・グラフ・比較・マップを描き直します（推定はやり直しません）。'];
            title_ = label(f.grid, '評価点の絞り込み：半径 [mm]', 1, 1);
            title_.FontWeight = 'bold';
            title_.Tooltip = filterTip;
            f.radiusMin = uieditfield(f.grid, 'numeric', 'Limits', [0, Inf], 'Value', 0, 'ValueDisplayFormat', '%g', ...
                'Tooltip', 'Mark の半径の下限 [mm]（この値以上）');
            place(f.radiusMin, 1, 2);
            label(f.grid, '〜', 1, 3);
            f.radiusMax = uieditfield(f.grid, 'numeric', 'Limits', [0, Inf], 'Value', Inf, 'ValueDisplayFormat', '%g', ...
                'Tooltip', 'Mark の半径の上限 [mm]（この値未満。Inf なら上限なし）');
            place(f.radiusMax, 1, 4);
            label(f.grid, 'Shot', 1, 5);
            f.shotMode = uidropdown(f.grid, 'Items', {'すべて', '右の shotNo だけ', '右の shotNo を除く'}, ...
                'ItemsData', {'all', 'include', 'exclude'});
            place(f.shotMode, 1, 6);
            f.shotNos = uieditfield(f.grid, 'text', 'Placeholder', '例：1 5 12', ...
                'Tooltip', 'shotNo を空白またはカンマで区切って入れます。');
            place(f.shotNos, 1, 7);
            label(f.grid, 'Scan', 1, 8);
            f.scan = uidropdown(f.grid, 'Items', {'すべて', '1', '2'}, 'ItemsData', {0, 1, 2});
            place(f.scan, 1, 9);
            label(f.grid, '最外周', 1, 10);
            f.outer = uidropdown(f.grid, 'Items', {'含める', '最外周の Shot だけ', '最外周の Shot を除く'}, ...
                'ItemsData', {'all', 'only', 'exclude'}, 'Tooltip', '最外周の Shot：上下左右のどこかに隣の Shot が無い Shot');
            place(f.outer, 1, 11);
            f.apply = uibutton(f.grid, 'Text', '絞り込んで再計算', 'Enable', 'off', 'Tooltip', filterTip, ...
                'ButtonPushedFcn', @(~, ~) app.onApplyFilter(source));
            place(f.apply, 1, 12);
            f.clear = uibutton(f.grid, 'Text', '解除', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.onClearFilter());
            place(f.clear, 1, 13);
            f.status = uilabel(f.grid, 'WordWrap', 'on', 'Text', '絞り込みなし');
            place(f.status, 2, [1, 14]);
        end

        function onApplyFilter(app, source)
            % 押した側（結果一覧・マップ）の欄から条件を読んで絞り込む
            controls = app.Controls.(ternary(source == "map", "filterMap", "filterResults"));
            runWithAlert(app, @() app.applyResultFilter(readFilterControls(controls)), "絞り込めませんでした", ...
                "半径は 下限 < 上限 にし、shotNo を使うときは整数を空白で区切って入れてください。");
        end

        function onClearFilter(app)
            runWithAlert(app, @() app.applyResultFilter(), "絞り込みを解除できませんでした", ...
                "もう一度「解除」を押してください。");
        end

        function showFilter(app)
            % 絞り込みの条件を、結果一覧とマップの両方の欄と説明に出す
            filter = app.ResultFilter;
            [~, text, active] = alignest.pointFilterMask(filter);
            status = "絞り込みなし";
            if active && ~isempty(app.Results)
                if isImportedResults(app.Results)
                    status = "絞り込み中：" + text + "（Excel から読み込んだ結果の表・グラフは計算し直せません。" + ...
                        "読み込んだ推定値の図・分布・散布図だけに使います）";
                else
                    base = app.BaseResults.table;
                    shown = app.Results.table;
                    status = sprintf("絞り込み中：%s（評価点 %d / %d 点。X・Y の合計、全行）", text, ...
                        sum(shown.nTest_X + shown.nTest_Y), sum(base.nTest_X + base.nTest_Y));
                end
            elseif active
                status = "絞り込みの条件：" + text;
            end
            for name = ["filterResults", "filterMap"]
                if ~isfield(app.Controls, name)
                    continue
                end
                f = app.Controls.(name);
                f.radiusMin.Value = filter.radiusMinMm;
                f.radiusMax.Value = filter.radiusMaxMm;
                f.shotMode.Value = char(filter.shotMode);
                f.shotNos.Value = char(strjoin(string(filter.shotNos), " "));
                f.scan.Value = filter.scan;
                f.outer.Value = char(filter.outer);
                f.status.Text = status;
                f.status.FontColor = ternary(active, app.Palette.accent, app.Palette.text);
                f.clear.Enable = onOff(active && ~isempty(app.Results));
            end
        end

        function clearPointViews(app)
            % 絞り込みを変えたら、評価点から描いた図・表（分布・箱ひげ図・散布図・分布の比較）を消す（古い点のままにしない）
            c = app.Controls;
            app.Analysis = [];
            app.Distribution = [];
            c.normalityTable.Data = {};
            c.anovaTable.Data = {};
            c.distributionTable.Data = {};
            c.jsTable.Data = {};
            for ax = [c.histogramAxes, c.scatterAxes, c.boxAxes, c.distributionAxes]
                cla(ax, 'reset');
                legend(ax, 'off');
            end
            set([c.boxAxes, c.distributionAxes], 'Visible', 'off');
            c.boxFactor.Items = {'—'};
            c.boxFactor.Enable = 'off';
            c.boxInfo.Text = '';
            c.analysisNote.Text = c.analysisNote.UserData;
        end

        function onDrawResidualBoxplot(app)
            runWithAlert(app, @() app.drawResidualBoxplot(), "箱ひげ図を描けませんでした", ...
                "「推定値と誤差の分布」で「分析する」を押してから、質的変数を選び直してください。");
        end

        function onMeasureTiming(app)
            runWithAlert(app, @() app.measureTiming(), "処理時間を測れませんでした", ...
                "Wafer・学習パターン・手法を選び直してから、もう一度「測る」を押してください。");
        end

        function refreshResultControls(app)
            c = app.Controls;
            results = app.Results;
            labels = string({results.methods.label});
            ids = string({results.methods.id});
            [metricList, metricLabels] = alignest.metricNames(isfield(results, "timingRecorded") && results.timingRecorded, ...
                isfield(results, "overlayEvaluated") && results.overlayEvaluated, resultSpec(app));
            current = string(c.metric.Value);
            c.metric.Items = cellstr(metricLabels);
            c.metric.ItemsData = cellstr(metricList);
            c.metric.Value = char(ternary(any(metricList == current), current, "RMSE_XY"));
            c.reference.Items = cellstr(labels);
            c.reference.ItemsData = cellstr(ids);
            preferred = find(ids == "GPR_matern52_XYR_basis", 1);
            if isempty(preferred)
                preferred = 1;
            end
            c.reference.Value = char(ids(preferred));
            c.chartMethods.Items = cellstr(labels);
            c.chartMethods.ItemsData = num2cell(1:numel(labels));
            summary = alignest.summarizeResults(results, "RMSE_XY", "mean");
            [~, order] = sort(mean(summary.values, 2, 'omitnan'));
            c.chartMethods.Value = num2cell(sort(order(1:min(app.MAX_CURVES, numel(order)))).');
            % 計測配置の比較（初めは推定値と誤差の分布と同じ手法）
            c.compareLayoutMethod.Items = cellstr(labels);
            c.compareLayoutMethod.ItemsData = 1:numel(labels);
            c.compareLayoutMethod.Value = order(1);
            set([c.compareLayoutMethod, c.compareLayoutXAxis], 'Enable', 'on');
            set([c.export, c.saveChart], 'Enable', 'on');
            imported = isImportedResults(results);
            c.importEstimates.Enable = onOff(imported);
            if imported
                % Excel から読み込んだ結果：表・グラフ・比較。推定値の Excel も読み込めば、推定値を使う画面も（その範囲で）
                c.export.Enable = 'off';
                c.resultControls.RowHeight{3} = 'fit';
                sourceText = string(sprintf('Excel から読み込んだ結果：%s（%s に作成）。', results.imported, results.createdAt));
                if isempty(app.ImportedEstimates)
                    c.resultSource.Text = sourceText + "表・グラフ・基準の手法との比較を見られます。" + ...
                        "Wafer マップ・推定値と誤差の分布・散布図・分布の比較は、「推定値の Excel を読み込む…」で" + ...
                        "推定値の Excel も読み込むと使えます（または計測ファイルを読み込んで「3. 実行」で評価し直す）。";
                    c.mapInfo.Text = "Excel から読み込んだ結果で Wafer ごとの図を描くには、「4. 結果一覧」の" + ...
                        "「推定値の Excel を読み込む…」で推定値の Excel も読み込んでください。";
                    refreshResults(app);
                    return
                end
                estimates = app.ImportedEstimates.estimates;
                c.resultSource.Text = sourceText + sprintf(['推定値：%s（手法 %d・学習パターンの列 %d・Wafer %d 枚）。' ...
                    'Wafer マップ・推定値と誤差の分布・散布図・分布の比較は、この推定値の範囲で描けます（Shot の枠・' ...
                    '推定値の書き出しは使えません）。'], app.ImportedEstimates.file, numel(unique(estimates.methodId)), ...
                    numel(unique(estimates.group)), numel(unique(estimates.Wafer)));
            else
                c.resultSource.Text = '';
                c.resultControls.RowHeight{3} = 0;
            end
            % マップの選択肢
            setGroupItems(c.mapWafer, alignest.groupOptions(mapUnits(app)));
            planLabels = unique(string({results.plans.label}), 'stable');
            c.mapPlan.Items = cellstr(planLabels);
            c.mapMethod.Items = cellstr(labels);
            c.mapMethod.ItemsData = 1:numel(labels);
            set([c.mapWafer, c.mapPlan, c.mapMethod, c.mapMode, c.mapScale, c.mapMarkerSize, c.mapMarkerShape, c.mapEllipse, ...
                c.mapEllipseOnly, c.mapShotFrames, c.saveMap, c.mapScanFrames, c.mapRings, c.mapView, c.mapCompareValue, ...
                c.mapConditions, c.mapAddCondition, c.mapRemoveCondition, c.mapClearConditions], 'Enable', 'on');
            app.MapConditions = app.MapConditions([]);   % 結果が変わると Wafer・手法の番号が変わるので、一覧は空にする
            refreshMapConditions(app);
            c.mapView.Value = 'single';
            c.mapContent.Enable = onOff(isfield(results, "overlayEvaluated") && results.overlayEvaluated && ...
                (~imported || height(app.ImportedEstimates.overlayPoints) > 0));
            set([c.mapShotFrames, c.mapScanFrames], 'Enable', onOff(~imported));   % 読み込んだ推定値には Shot 中心の座標が無い
            if c.mapContent.Enable == "off"
                c.mapContent.Value = 'estimate';
            end
            % 推定値と誤差の分布の選択肢（初めは最も RMSE の小さい手法・最も多い学習 Shot 数）
            c.analysisMethod.Items = cellstr(labels);
            c.analysisMethod.ItemsData = 1:numel(labels);
            c.analysisMethod.Value = order(1);
            c.analysisGroup.Items = cellstr(results.groups);
            c.analysisGroup.Value = char(results.groups(end));
            c.analysisWafer.Items = cellstr(["すべての Wafer"; results.unitLabels(:)]);
            c.analysisWafer.ItemsData = 0:numel(results.unitLabels);
            c.analysisWafer.Value = 0;
            set([c.analysisMethod, c.analysisGroup, c.analysisWafer, c.analyze, c.estimateScope, c.exportEstimates], ...
                'Enable', 'on');
            set([c.estimateScope, c.exportEstimates], 'Enable', onOff(~imported));
            % 散布図の選択肢（初めは推定値と誤差の分布と同じ手法・学習パターン）
            c.scatterMethod.Items = c.analysisMethod.Items;
            c.scatterMethod.ItemsData = c.analysisMethod.ItemsData;
            c.scatterMethod.Value = c.analysisMethod.Value;
            c.scatterGroup.Items = c.analysisGroup.Items;
            c.scatterGroup.Value = c.analysisGroup.Value;
            c.scatterWafer.Items = c.analysisWafer.Items;
            c.scatterWafer.ItemsData = c.analysisWafer.ItemsData;
            c.scatterWafer.Value = 0;
            if imported
                [colorKeys, colorLabels] = scatterColorChoices(app.ImportedEstimates.estimates, results.settings);
            else
                [colorKeys, colorLabels] = scatterColorChoices(app.Data, results.settings);
            end
            c.scatterColor.Items = cellstr(colorLabels);
            c.scatterColor.ItemsData = cellstr(colorKeys);
            c.scatterColor.Value = 'none';
            set([c.scatterMethod, c.scatterGroup, c.scatterWafer, c.scatterColor, c.drawScatterButton], 'Enable', 'on');
            c.distributionMethod.Items = c.analysisMethod.Items;
            c.distributionMethod.ItemsData = c.analysisMethod.ItemsData;
            c.distributionMethod.Value = c.analysisMethod.Value;
            c.distributionGroup.Items = c.analysisGroup.Items;
            c.distributionGroup.Value = c.analysisGroup.Value;
            c.distributionWafer.Items = c.analysisWafer.Items;
            c.distributionWafer.ItemsData = c.analysisWafer.ItemsData;
            c.distributionWafer.Value = 0;
            set([c.distributionMethod, c.distributionGroup, c.distributionWafer, c.distributionAxis, ...
                c.compareDistributionsButton], 'Enable', 'on');
            % 処理時間の内訳（計測データを読み込んで評価した結果だけ。初めは推定値と誤差の分布と同じ手法・最も多い学習 Shot 数）
            c.timingWafer.Items = cellstr(results.unitLabels);
            c.timingWafer.ItemsData = 1:numel(results.unitLabels);
            c.timingWafer.Value = 1;
            c.timingPlan.Items = cellstr(planLabels);
            c.timingPlan.Value = char(planLabels(end));
            c.timingMethods.Items = cellstr(labels);
            c.timingMethods.ItemsData = num2cell(1:numel(labels));
            c.timingMethods.Value = {order(1)};
            set([c.timingWafer, c.timingPlan, c.timingMethods, c.timingRepeats, c.measureTimingButton], ...
                'Enable', onOff(~imported && ~isempty(app.Data)));
            set([c.filterResults.apply, c.filterMap.apply], 'Enable', 'on');
            showFilter(app);
            refreshResults(app);
            drawMap(app);
        end

        function refreshResults(app)
            if isempty(app.Results)
                return
            end
            c = app.Controls;
            metric = string(c.metric.Value);
            summary = alignest.summarizeResults(app.Results, metric, string(c.statistic.Value));
            data = cell(numel(summary.methodLabels), numel(summary.groups) + 1);
            data(:, 1) = cellstr(summary.methodLabels);
            removeStyle(c.summaryTable);
            for g = 1:numel(summary.groups)
                column = summary.values(:, g);
                if summary.lowerIsBetter
                    [~, best] = min(column);
                else
                    [~, best] = max(column);
                end
                for m = 1:numel(column)
                    text = sprintf('%.3f', column(m));
                    if m == best && ~isnan(column(m))
                        text = [text, ' ★']; %#ok<AGROW>
                    end
                    data{m, g + 1} = text;
                end
                if ~all(isnan(column))
                    addStyle(c.summaryTable, uistyle('BackgroundColor', app.Palette.best, 'FontWeight', 'bold'), 'cell', [best, g + 1]);
                end
            end
            c.summaryTable.Data = data;
            c.summaryTable.ColumnName = cellstr(["手法", summary.groups]);
            c.summaryTable.ColumnWidth = [{app.METHOD_COLUMN_WIDTH}, repmat({app.VALUE_COLUMN_WIDTH}, 1, numel(summary.groups))];
            comparison = alignest.pairedComparison(app.Results, string(c.reference.Value), metric);
            unitText = ternary(comparison.Properties.UserData.lowerIsBetter, "%", "");
            rows = cell(height(comparison), 6);
            for k = 1:height(comparison)
                rows{k, 1} = char(comparison.method(k));
                rows{k, 2} = char(comparison.group(k));
                rows{k, 3} = sprintf('%+.2f%s', comparison.difference(k), unitText);
                rows{k, 4} = sprintf('%+.2f 〜 %+.2f', comparison.lower95(k), comparison.upper95(k));
                rows{k, 5} = sprintf('%.0f%%', 100 * comparison.winRate(k));
                rows{k, 6} = sprintf('%d', comparison.nWafers(k));
            end
            c.comparisonTable.Data = rows;
            c.comparisonTable.ColumnName = {'手法', '列', ...
                char("基準との差（" + ternary(unitText == "%", "割合", "差") + "）"), '95% 区間', '基準より良かった割合', 'Wafer 数'};
            c.comparisonTable.ColumnWidth = {app.METHOD_COLUMN_WIDTH, 120, 200, 230, 210, 100};
            c.comparisonNote.Text = sprintf(['基準の手法：%s。同じ Wafer・同じ学習パターンどうしで比べた差の平均（%s）、' ...
                'その 95%% 区間、基準より良かった Wafer の割合。'], comparison.Properties.UserData.referenceLabel, ...
                ternary(unitText == "%", "誤差の差の割合。負なら基準より良い", "差。正なら基準より良い"));
            drawChart(app);
            drawLayoutComparison(app);
        end

        function drawChart(app)
            if isempty(app.Results)
                return
            end
            c = app.Controls;
            if string(c.chartXAxis.Value) == "criteria"
                c.chartAxesGrid.ColumnWidth = {'1x', '1x'};
                drawCriteriaChart(app);
                return
            end
            c.chartAxesGrid.ColumnWidth = {'1x', 0};
            cla(c.chartAxes2, 'reset');
            legend(c.chartAxes2, 'off');
            c.chartAxes2.Visible = 'off';
            ax = c.chartAxes;
            metric = string(c.metric.Value);
            summary = alignest.summarizeResults(app.Results, metric, string(c.statistic.Value));
            selected = cell2mat(c.chartMethods.Value);
            cla(ax, 'reset');
            hold(ax, 'on');
            positions = groupPositions(summary.groups);
            markers = {'o', 's', 'd', '^', 'v', '>', '<', 'p', 'h', 'x'};
            halfWidth = errorBarHalfWidth(app.Results, metric, string(c.chartErrorBars.Value));
            for k = 1:numel(selected)
                m = selected(k);
                style = ['-', markers{mod(k - 1, numel(markers)) + 1}];
                if isempty(halfWidth)
                    plot(ax, positions, summary.values(m, :), style, 'LineWidth', 1.5, 'MarkerSize', 7, ...
                        'DisplayName', summary.methodLabels(m));
                else
                    errorbar(ax, positions, summary.values(m, :), halfWidth(m, :), style, 'LineWidth', 1.5, ...
                        'MarkerSize', 7, 'CapSize', 6, 'DisplayName', summary.methodLabels(m));
                end
            end
            hold(ax, 'off');
            ax.XTick = positions;
            [numbers, axisLabel] = groupNumbers(summary.groups);
            if all(isfinite(numbers))
                ax.XTickLabel = cellstr(string(numbers));
                xlabel(ax, axisLabel);
            else
                ax.XTickLabel = cellstr(summary.groups);
                xlabel(ax, '学習パターン');
            end
            [names, labels] = alignest.metricNames(true, true, resultSpec(app));
            ylabel(ax, labels(names == metric));
            title(ax, "Wafer の" + statisticLabel(string(c.statistic.Value)) + errorBarCaption(string(c.chartErrorBars.Value)));
            grid(ax, 'on');
            if ~isempty(selected)
                legend(ax, 'Location', 'southoutside', 'NumColumns', 1, 'Interpreter', 'none', 'FontSize', 10, 'Box', 'off');
            end
            ax.FontSize = app.AXES_FONT_SIZE;
        end

        function drawCriteriaChart(app)
            % I 基準・D 基準（学習 Shot の組の評価指標）を横軸に、推定誤差の集計値を描く。学習パターンの列ごとに1点。
            c = app.Controls;
            metric = string(c.metric.Value);
            statistic = string(c.statistic.Value);
            summary = alignest.summarizeResults(app.Results, metric, statistic);
            selected = cell2mat(c.chartMethods.Value);
            [names, labels] = alignest.metricNames(true, true, resultSpec(app));
            criteria = ["criterionI", "criterionD"];
            criteriaLabels = ["I 基準 tr(M^{-1})", "D 基準 det(M)^{-1/p}"];
            criteriaNames = ["I 基準", "D 基準"];
            markers = {'o', 's', 'd', '^', 'v', '>', '<', 'p', 'h', 'x'};
            groupNames = string(summary.groups);
            shortNames = extractBefore(groupNames, " Shot");
            shortNames(ismissing(shortNames)) = groupNames(ismissing(shortNames));
            axesList = [c.chartAxes, c.chartAxes2];
            halfWidth = errorBarHalfWidth(app.Results, metric, string(c.chartErrorBars.Value));
            for a = 1:2
                ax = axesList(a);
                cla(ax, 'reset');
                hold(ax, 'on');
                perUnit = alignest.perUnitValues(app.Results, criteria(a));
                for k = 1:numel(selected)
                    m = selected(k);
                    x = cellfun(@(values) mean(values, 'omitnan'), perUnit(m, :));
                    y = summary.values(m, :);
                    valid = find(isfinite(x) & isfinite(y) & x > 0);
                    [xs, order] = sort(x(valid));
                    ys = y(valid(order));
                    style = ['-', markers{mod(k - 1, numel(markers)) + 1}];
                    if isempty(halfWidth)
                        curve = plot(ax, xs, ys, style, 'LineWidth', 1.5, 'MarkerSize', 7, ...
                            'DisplayName', summary.methodLabels(m));
                    else
                        bars = halfWidth(m, valid(order));
                        curve = errorbar(ax, xs, ys, bars, style, 'LineWidth', 1.5, 'MarkerSize', 7, 'CapSize', 6, ...
                            'DisplayName', summary.methodLabels(m));
                    end
                    if k == 1
                        text(ax, xs, ys, "  " + shortNames(valid(order)), 'FontSize', 10, 'Color', curve.Color, ...
                            'VerticalAlignment', 'bottom', 'HandleVisibility', 'off');
                    end
                    if c.chartPoints.Value
                        rows = app.Results.table(app.Results.table.methodIndex == m, :);
                        scatter(ax, rows.(criteria(a)), rows.(metric), 14, curve.Color, 'filled', ...
                            'MarkerFaceAlpha', 0.25, 'HandleVisibility', 'off');
                    end
                end
                hold(ax, 'off');
                ax.XScale = 'log';
                xlabel(ax, criteriaLabels(a) + "（対数目盛、小さいほど良い計画）");
                ylabel(ax, labels(names == metric));
                title(ax, sprintf("%s と推定誤差（Wafer の%s%s）", criteriaNames(a), statisticLabel(statistic), ...
                    errorBarCaption(string(c.chartErrorBars.Value))));
                grid(ax, 'on');
                ax.FontSize = app.AXES_FONT_SIZE;
                ax.Visible = 'on';
            end
            if ~isempty(selected)
                legend(c.chartAxes, 'Location', 'southoutside', 'NumColumns', 1, 'Interpreter', 'none', 'FontSize', 10, ...
                    'Box', 'off');
            end
        end

        function onExport(app)
            [fileName, folder] = uiputfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, '結果を書き出す', 'alignment_estimation_results.xlsx');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            ok = runWithAlert(app, @() app.exportResultsTo(target), "書き出せませんでした", ...
                "同じ名前のファイルを Excel で開いていれば閉じてから、もう一度試してください。");
            if ok
                uialert(app.Figure, sprintf('書き出しました：%s', target), '書き出しました', 'Icon', 'success');
            end
        end

        function onImportResults(app)
            [fileName, folder] = uigetfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, '結果を読み込む');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.importResultsFrom(fullfile(folder, fileName)), "結果を読み込めませんでした", ...
                "このアプリの「結果を Excel に書き出す」で書き出したファイル（.xlsx）を選んでください。");
        end

        function onImportEstimates(app)
            [fileName, folder] = uigetfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, '推定値の Excel を読み込む');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.importEstimatesFrom(fullfile(folder, fileName)), "推定値を読み込めませんでした", ...
                "このアプリの「推定値を Excel に書き出す…」で、読み込んだ評価結果と同じ評価から書き出したファイルを選んでください。");
        end

        function onSaveChart(app)
            [fileName, folder] = uiputfile({'*.png', 'PNG 画像 (*.png)'}, 'グラフを保存', 'metric_by_plan.png');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            app.Controls.resultTabs.SelectedTab = app.Controls.chartTab;
            drawnow;
            if runWithAlert(app, @() exportgraphics(app.Controls.chartPanel, target, 'Resolution', 150), ...
                    "グラフを保存できませんでした", "保存先のフォルダを変えてもう一度試してください。")
                uialert(app.Figure, sprintf('保存しました：%s', target), '保存しました', 'Icon', 'success');
            end
        end

        function selection = analysisSelection(app)
            c = app.Controls;
            unitIndex = c.analysisWafer.Value;
            if unitIndex == 0
                unitIndex = 1:numel(app.Results.unitLabels);
            end
            selection = struct("methodIndex", c.analysisMethod.Value, "groups", string(c.analysisGroup.Value), ...
                "unitIndex", unitIndex);
        end

        function [estimates, messages, overlayPoints] = collectWithProgress(app, selection, cache, maxRows, titleText, ...
                includeTraining)
            % 推定値を集める（画面が出ているときは進み具合を出し、「止める」で中止できる）
            if nargin < 6
                includeTraining = false;
            end
            if isImportedResults(app.Results)
                [estimates, messages, overlayPoints] = importedEstimates(app, selection, includeTraining);
                estimates = filterEstimates(app, estimates);
                return
            end
            dialog = [];
            if app.Figure.Visible == "on"
                dialog = uiprogressdlg(app.Figure, 'Title', titleText, 'Message', '推定値を計算しています…', ...
                    'Cancelable', 'on', 'CancelText', '止める', 'ShowPercentage', 'on');
            end
            cleanup = onCleanup(@() closeDialog(dialog));
            if nargin < 6
                includeTraining = false;
            end
            [estimates, messages, cancelled, overlayPoints] = alignest.collectEstimates(app.Data, app.Results, selection, cache=cache, ...
                maxRows=maxRows, progressFcn=@(done, total) reportCollectProgress(dialog, done, total), ...
                includeTraining=includeTraining);
            if cancelled
                error('alignest:cancelled', '途中で止めました。');
            end
            estimates = filterEstimates(app, estimates);
        end

        function estimates = filterEstimates(app, estimates)
            % 評価点の絞り込み（結果一覧・マップと同じ条件）に合わない評価の行を除く（学習の行はそのまま）
            [~, ~, active] = alignest.pointFilterMask(app.ResultFilter);
            if ~active || height(estimates) == 0
                return
            end
            if isImportedResults(app.Results)
                mask = alignest.pointFilterMask(app.ResultFilter, estimates);
            else
                mask = true(height(estimates), 1);
                [~, unitOfRow] = ismember(estimates.Wafer, app.Results.unitLabels);
                for u = unique(unitOfRow(unitOfRow > 0)).'
                    unitMask = alignest.unitPointFilter(app.Data.units(u), app.ResultFilter);
                    rows = unitOfRow == u;
                    mask(rows) = unitMask(estimates.markIndex(rows));
                end
            end
            estimates = estimates(estimates.role ~= "評価" | mask, :);
        end

        function text = filterNote(app)
            % 説明の文の後ろに付ける、絞り込みの条件（絞り込んでいなければ空）
            [~, description, active] = alignest.pointFilterMask(app.ResultFilter);
            text = "";
            if active
                text = "｜評価点の絞り込み：" + description;
            end
        end

        function showAnalysis(app)
            c = app.Controls;
            estimates = app.Analysis.estimates;
            spec = resultSpec(app);
            alignest.plot.residualHistogram(c.histogramAxes(1), estimates.residualX, spec.labels(1) + " の残差", spec.unit);
            if spec.scalar
                c.histogramGrid.ColumnWidth = {'1x', 0};   % 1変数は Y 成分が無い
                cla(c.histogramAxes(2), 'reset');
                c.histogramAxes(2).Visible = 'off';
            else
                c.histogramGrid.ColumnWidth = {'1x', '1x'};
                c.histogramAxes(2).Visible = 'on';
                alignest.plot.residualHistogram(c.histogramAxes(2), estimates.residualY, "Y の残差");
            end
            set(c.histogramAxes, 'FontSize', app.AXES_FONT_SIZE);
            normality = app.Analysis.analysis.normality;
            rows = cell(height(normality), 13);
            for k = 1:height(normality)
                r = normality(k, :);
                rows(k, :) = {char(r.axis), sprintf('%d', r.n), numberText(r.mean, '%.3f'), numberText(r.std, '%.3f'), ...
                    numberText(r.skewness, '%.3f'), numberText(r.excessKurtosis, '%.3f'), numberText(r.swW, '%.4f'), ...
                    pValueText(r.swP), numberText(r.adA2, '%.3f'), pValueText(r.adP), numberText(r.jb, '%.2f'), ...
                    pValueText(r.jbP), char(r.judgement)};
            end
            c.normalityTable.Data = rows;
            anova = app.Analysis.analysis.anova;
            rows = cell(height(anova), 9);
            for k = 1:height(anova)
                r = anova(k, :);
                rows(k, :) = {char(r.axis), char(r.factor), char(r.levelSummary), numberText(r.F, '%.2f'), ...
                    pValueText(r.p), numberText(r.etaSquared, '%.3f'), numberText(r.adjustedF, '%.2f'), ...
                    pValueText(r.adjustedP), char(judgementWithNote(r.judgement, r.note))};
            end
            c.anovaTable.Data = rows;
            results = app.Results;
            selection = app.Analysis.selection;
            scopeText = sprintf("%s｜%s｜Wafer %d 枚", results.methods(selection.methodIndex).label, selection.groups, ...
                numel(selection.unitIndex));
            note = "分析した範囲：" + scopeText + filterNote(app) + "。" + c.analysisNote.UserData;
            if ~isempty(app.Analysis.messages)
                note = note + " ⚠ 推定できなかった組み合わせ：" + strjoin(app.Analysis.messages, "／");
            end
            c.analysisNote.Text = note;
        end

        function onDrawScatter(app)
            runWithAlert(app, @() app.drawScatter(), "散布図を描けませんでした", ...
                "手法・学習パターン・Wafer を選び直してから、もう一度「描く」を押してください。");
        end

        function categories = scatterCategories(app, estimates, colorBy)
            % 散布図の点ごとの色分けの水準（文字列）
            n = height(estimates);
            switch colorBy
                case "none"
                    categories = strings(n, 1);
                case "wafer"
                    categories = string(estimates.Wafer);
                case "lot"
                    categories = string(estimates.LotID);
                case "eqp"
                    categories = string(estimates.EqpId);
                case "operation"
                    categories = string(estimates.Operation);
                case "scan"
                    categories = "Scan " + string(estimates.direction);
                    categories(isnan(estimates.direction)) = "Scan なし";
                case "mark"
                    categories = "Mark " + string(estimates.markNo);
                case "row"
                    categories = repmat("偶数行", n, 1);
                    categories(estimates.shotRowParity == 1) = "奇数行";
                case "slot"
                    % Wafer ID のハイフンの後の番号（Slot）の奇数・偶数。読めない Wafer は「Slot 不明」
                    [~, parity] = alignest.waferSlot(estimates.Wafer);
                    names = ["Slot 奇数", "Slot 偶数", "Slot 不明"];
                    labels_ = repmat(names(3), n, 1);
                    labels_(parity == "奇数") = names(1);
                    labels_(parity == "偶数") = names(2);
                    categories = categorical(labels_, names);
                    return
                case "outer"
                    % 外周の RMSE と同じ境目（Mark の半径が外周の半径以上なら外周）。凡例は 内側 → 外周 の順
                    outerMm = alignest.upgradeRadiusSettings(app.Results.settings).evaluation.outerRadiusMm;
                    names = [sprintf("内側（半径 %g mm 未満）", outerMm), sprintf("外周（半径 %g mm 以上）", outerMm)];
                    categories = categorical(names(1 + (estimates.r >= outerMm)).', names);
                    return
                case "quadrant"
                    % I 最適の4象限の制約と同じ分け方（偏角で数え、軸の上は反時計回りに次の象限）。Mark の座標で分ける
                    names = ["第1象限（x > 0, y > 0）", "第2象限（x < 0, y > 0）", "第3象限（x < 0, y < 0）", ...
                        "第4象限（x > 0, y < 0）"];
                    angle = mod(atan2(estimates.y, estimates.x), 2 * pi);
                    categories = categorical(names(mod(floor(angle / (pi / 2)), 4) + 1).', names);
                    return
                otherwise
                    column = extractAfter(colorBy, "col:");
                    categories = repmat("（空）", n, 1);
                    if any(string(estimates.Properties.VariableNames) == "質的変数:" + column)
                        categories = string(estimates.("質的変数:" + column));   % 推定値の表にある列（読み込んだ推定値など）
                        categories(categories == "") = "（空）";
                        return
                    end
                    [~, unitOfPoint] = ismember(string(estimates.Wafer), app.Results.unitLabels);
                    for u = unique(unitOfPoint(unitOfPoint > 0)).'
                        unit = app.Data.units(u);
                        position = find(unit.attributeNames == column, 1);
                        if isempty(position)
                            continue
                        end
                        rows = unitOfPoint == u;
                        values = unit.marks.attributes(estimates.markIndex(rows), position);
                        values(values == "") = "（空）";
                        categories(rows) = values;
                    end
            end
            categories(categories == "") = "（空）";
            if colorBy == "none"
                categories(:) = "";
            end
        end

        function onAnalyze(app)
            runWithAlert(app, @() app.analyzeResiduals(), "分析できませんでした", ...
                "手法・学習パターン・Wafer を選び直してから、もう一度「分析する」を押してください。");
        end

        function onExportEstimates(app)
            [fileName, folder] = uiputfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, '推定値を書き出す', ...
                'alignment_estimates.xlsx');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            ok = runWithAlert(app, @() app.exportEstimatesTo(target), "推定値を書き出せませんでした", ...
                "同じ名前のファイルを Excel で開いていれば閉じてから、または書き出す範囲を絞ってから、もう一度試してください。");
            if ok
                uialert(app.Figure, sprintf('書き出しました：%s', target), '書き出しました', 'Icon', 'success');
            end
        end

        % ================= 5. Waferごとのマップ =================
        function buildMapTab(app)
            grid = uigridlayout(app.Tabs.map, [5, 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit'}, 'Padding', 12, ...
                'RowSpacing', 8);
            controls = uigridlayout(grid, [2, 11], 'ColumnWidth', {170, 140, '2x', '1x', 110, 110, 80, 70, 80, 'fit', 'fit'}, ...
                'Padding', 0, 'RowHeight', {'fit', 'fit'});
            label(controls, 'Wafer・平均', 1, 1);
            label(controls, '学習パターン', 1, 2);
            label(controls, '手法', 1, 3);
            label(controls, '図の内容', 1, 4);
            label(controls, '点の形', 1, 8);
            label(controls, '共分散楕円', 1, 9);
            label(controls, '表示', 1, 5);
            label(controls, '矢印の倍率（0 = 自動）', 1, 6);
            label(controls, '色の点の大きさ', 1, 7);
            onChange = @(~, ~) app.drawMap();
            c.mapWafer = uidropdown(controls, 'Items', {'—'}, 'ValueChangedFcn', onChange);
            place(c.mapWafer, 2, 1);
            c.mapPlan = uidropdown(controls, 'Items', {'—'}, 'ValueChangedFcn', onChange);
            place(c.mapPlan, 2, 2);
            c.mapMethod = uidropdown(controls, 'Items', {'—'}, 'ValueChangedFcn', onChange);
            place(c.mapMethod, 2, 3);
            c.mapContent = uidropdown(controls, 'Items', {'推定（計測値・推定値・残差）', ...
                'Overlay 補正（実測値で補正・推定値で補正・変化）'}, 'ItemsData', {'estimate', 'overlay'}, ...
                'Tooltip', ['Overlay 補正：実測値で補正した残差、推定値で補正した残差（学習 Shot は計測値、それ以外は推定値で' ...
                '補正を求めて実際の値に当てた残差）、推定による変化（両者の差）。補正モデルは「2. 評価の設定」で選びます。'], ...
                'ValueChangedFcn', onChange);
            place(c.mapContent, 2, 4);
            c.mapMode = uidropdown(controls, 'Items', {'ベクトル（矢印）', 'X（色）', 'Y（色）'}, ...
                'ItemsData', {'vector', 'X', 'Y'}, 'ValueChangedFcn', onChange);
            place(c.mapMode, 2, 5);
            c.mapScale = uieditfield(controls, 'numeric', 'Value', 0, 'Limits', [0, Inf], 'ValueChangedFcn', onChange);
            place(c.mapScale, 2, 6);
            c.mapMarkerSize = markerSizeSpinner(app, controls, onChange);
            place(c.mapMarkerSize, 2, 7);
            c.mapMarkerShape = markerShapeDropdown(controls, onChange);
            place(c.mapMarkerShape, 2, 8);
            c.mapEllipse = ellipseDropdown(controls, onChange);
            place(c.mapEllipse, 2, 9);
            c.mapShotFrames = uicheckbox(controls, 'Text', 'Shot の枠', 'Value', true, 'ValueChangedFcn', onChange);
            place(c.mapShotFrames, 2, 10);
            c.mapEllipseOnly = ellipseOnlyCheckbox(controls, onChange);
            place(c.mapEllipseOnly, 1, [10, 11]);
            c.saveMap = uibutton(controls, 'Text', '図を画像で保存…', 'ButtonPushedFcn', @(~, ~) app.onSaveMap());
            place(c.saveMap, 2, 11);
            % 図に重ねるもの：Scan 方向の色の Shot の枠・同心円の制約の区切り
            extras = uigridlayout(grid, [1, 3], 'ColumnWidth', {'fit', 'fit', '1x'}, 'Padding', 0);
            c.mapScanFrames = uicheckbox(extras, 'Text', 'Shot の枠を Scan 方向で色分け（緑 ▲ = 1、紫 ▼ = 2）', ...
                'ValueChangedFcn', onChange, 'Tooltip', ['Shot の枠を Scan 方向の色で描き、枠の左上に ▲（Scan 方向 1）・' ...
                '▼（Scan 方向 2）を付けます。Scan 方向が無い Shot は灰色の枠です。']);
            c.mapRings = uicheckbox(extras, 'Text', '同心円の区切り（制約）を描く', 'ValueChangedFcn', onChange, ...
                'Tooltip', ['評価で I 最適・ランダムの同心円の制約を使ったとき、区切りの半径（Shot 中心の半径 [mm]）を' ...
                '橙の一点鎖線で描きます。']);
            c.mapExtrasInfo = uilabel(extras, 'Text', '', 'FontColor', app.Palette.muted);
            c.filterMap = buildFilterControls(app, grid, "map");
            % 図（1つの条件の3枚、または並べて比べる図）と、並べて比べる条件の一覧
            body = uigridlayout(grid, [1, 2], 'ColumnWidth', {'1x', 300}, 'Padding', 0, 'ColumnSpacing', 10);
            c.mapPanel = uipanel(body, 'BorderType', 'none');
            c.mapStack = uigridlayout(c.mapPanel, [2, 1], 'RowHeight', {'1x', 0}, 'Padding', 0, 'RowSpacing', 0);
            axesGrid = uigridlayout(c.mapStack, [1, 3], 'Padding', 0, 'ColumnSpacing', 8);
            c.mapAxes = [uiaxes(axesGrid), uiaxes(axesGrid), uiaxes(axesGrid)];
            c.comparePanel = uipanel(c.mapStack, 'BorderType', 'none');
            c.compareAxes = gobjects(1, 0);
            side = uigridlayout(body, [9, 1], 'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit', '1x', 'fit', 'fit', 'fit'}, ...
                'Padding', 0, 'RowSpacing', 4);
            label(side, '並べ方', 1, 1);
            c.mapView = uidropdown(side, 'Items', {'1つの条件（計測値・推定値・残差）', '一覧の条件を並べて比べる'}, ...
                'ItemsData', {'single', 'compare'}, 'ValueChangedFcn', onChange);
            place(c.mapView, 2, 1);
            label(side, '並べて比べる値', 3, 1);
            c.mapCompareValue = uidropdown(side, 'Items', {'計測値', '推定値', '残差'}, 'ItemsData', {1, 2, 3}, 'Value', 3, ...
                'ValueChangedFcn', onChange, 'Tooltip', ['並べた図はすべて同じ値の種類で、矢印の倍率と色の範囲をそろえて' ...
                '描きます（上の「図の内容」が Overlay 補正なら、補正した残差・推定による変化）。']);
            place(c.mapCompareValue, 4, 1);
            label(side, sprintf('比べる条件（最大 %d。上の選択を追加）', app.MAX_COMPARE_PANELS), 5, 1);
            c.mapConditions = uilistbox(side, 'Items', {}, 'Multiselect', 'on');
            place(c.mapConditions, 6, 1);
            c.mapAddCondition = uibutton(side, 'Text', '上の条件を一覧に追加', ...
                'ButtonPushedFcn', @(~, ~) app.onAddMapCondition(), 'Tooltip', ['上で選んだ Wafer・平均、学習パターン、手法を' ...
                '一覧に足して、並べて描きます（Wafer どうし、手法どうし、学習パターンどうしを比べられます）。']);
            place(c.mapAddCondition, 7, 1);
            c.mapRemoveCondition = uibutton(side, 'Text', '選んだ条件を外す', ...
                'ButtonPushedFcn', @(~, ~) app.removeMapConditions(cell2mat(app.Controls.mapConditions.Value)));
            place(c.mapRemoveCondition, 8, 1);
            c.mapClearConditions = uibutton(side, 'Text', '一覧を空にする', ...
                'ButtonPushedFcn', @(~, ~) app.removeMapConditions(1:numel(app.MapConditions)));
            place(c.mapClearConditions, 9, 1);
            set([c.mapWafer, c.mapPlan, c.mapMethod, c.mapContent, c.mapMode, c.mapScale, c.mapMarkerSize, ...
                c.mapMarkerShape, c.mapEllipse, c.mapEllipseOnly, c.mapShotFrames, c.saveMap, c.mapScanFrames, c.mapRings, ...
                c.mapView, c.mapCompareValue, c.mapConditions, c.mapAddCondition, c.mapRemoveCondition, ...
                c.mapClearConditions], 'Enable', 'off');
            c.mapInfo = uilabel(grid, 'WordWrap', 'on', 'Text', '「3. 実行」で評価すると、ここに Wafer ごとの図が出ます。');
            app.Controls = mergeStruct(app.Controls, c);
        end

        function drawMap(app)
            % 「5. Waferごとのマップ」を描く：1つの条件の 計測値・推定値・残差（または Overlay 補正の3つ）を並べるか、
            % 一覧の条件を同じ値の種類で並べて比べる
            if isempty(app.Results) || (isImportedResults(app.Results) && isempty(app.ImportedEstimates))
                return
            end
            c = app.Controls;
            spec = resultSpec(app);
            setModeChoices(c.mapMode, spec);
            if spec.scalar
                setChoices(c.mapContent, "推定（計測値・推定値・残差）", {'estimate'});
                set([c.mapEllipse, c.mapEllipseOnly], 'Enable', 'off');   % 楕円は X・Y の2成分が要る
                c.mapEllipse.Value = 0;
            end
            content = string(c.mapContent.Value);
            overlayContent = content == "overlay";
            names = ternary(overlayContent, ["実測値で補正した残差", "推定値で補正した残差", "推定による変化"], ...
                ["計測値", "推定値", "残差"]);
            if ~isequal(string(c.mapCompareValue.Items), names)
                c.mapCompareValue.Items = cellstr(names);   % ItemsData（1〜3）と選んだ番号はそのまま
            end
            rings = activeZoneEdges(app.Results.settings);
            c.mapRings.Enable = onOff(~isempty(rings));
            c.mapExtrasInfo.Text = ternary(isempty(rings), "（この評価では同心円の制約を使っていません）", ...
                "区切り：" + strjoin(string(rings), "・") + " mm");
            compare = string(c.mapView.Value) == "compare";
            c.mapStack.RowHeight = ternary(compare, {0, '1x'}, {'1x', 0});
            if compare
                drawComparison(app);
                return
            end
            f = mapFields(app, c.mapWafer.Value, string(c.mapPlan.Value), c.mapMethod.Value, content);
            if ~f.ok
                c.mapInfo.Text = f.message;
                arrayfun(@(ax) cla(ax), c.mapAxes);
                return
            end
            [scale, limit, magnitudes] = mapScales(app, f.values, 1 + overlayContent, overlayContent);
            ranges = repmat({[NaN, NaN]}, 1, 3);
            limits = repmat(limit, 1, 3);
            if spec.scalar
                % 計測値と推定値は同じ値の範囲（最小〜最大）、残差は 0 を中心に自分の範囲
                ranges(1:2) = {valueRange([f.values{1}(:, 1); f.values{2}(:, 1)])};
                limits(3) = absoluteLimit(f.values{3}(:, 1));
            end
            for k = 1:3
                drawMapPanel(app, c.mapAxes(k), f, k, scale(k), limits(k), magnitudes(k), f.titles(k), true, ranges{k});
            end
            c.mapInfo.Text = f.info;
        end

        function drawComparison(app)
            % 一覧の条件を、選んだ値の種類で並べて描く（矢印の倍率・色の範囲・矢印の色の範囲はすべての図で共通）
            c = app.Controls;
            delete(c.comparePanel.Children);
            app.Controls.compareAxes = gobjects(1, 0);
            conditions = app.MapConditions;
            if isempty(conditions)
                c.mapInfo.Text = "比べる条件がありません。上で Wafer・平均、学習パターン、手法を選び、右の「上の条件を一覧に追加」を" + ...
                    "押してください。";
                return
            end
            content = string(c.mapContent.Value);
            valueIndex = c.mapCompareValue.Value;
            spec = resultSpec(app);
            nPanels = min(numel(conditions), app.MAX_COMPARE_PANELS);
            fieldsList = cell(1, nPanels);
            lines = strings(nPanels, 1);
            for k = 1:nPanels
                fieldsList{k} = mapFields(app, conditions(k).option, conditions(k).plan, conditions(k).method, content);
                lines(k) = conditions(k).label + "：" + ternary(fieldsList{k}.ok, sprintf("RMSE（%s）%.3f %s", ...
                    spec.combinedLabel, fieldsList{k}.rmse, spec.unit), fieldsList{k}.message);
            end
            usable = cellfun(@(f) f.ok, fieldsList);
            if ~any(usable)
                c.mapInfo.Text = strjoin(lines, "　／　");
                return
            end
            values = cellfun(@(f) f.values, fieldsList(usable), 'UniformOutput', false);
            stacked = cell2mat(cellfun(@(v) v{valueIndex}, values(:), 'UniformOutput', false));
            [scale, limit] = mapScales(app, {stacked, stacked, stacked}, 1, false);
            magnitude = max([0; hypot(stacked(:, 1), stacked(:, 2))], [], 'omitnan');
            range = [NaN, NaN];
            if spec.scalar && valueIndex < 3
                range = valueRange(stacked(:, 1));   % 1変数の計測値・推定値は値の範囲（すべての図で共通）
            end
            [nRows, nColumns] = tileShape(c.comparePanel, nPanels);
            layout = tiledlayout(c.comparePanel, nRows, nColumns, 'TileSpacing', 'compact', 'Padding', 'compact');
            axesList = gobjects(1, nPanels);
            for k = 1:nPanels
                ax = nexttile(layout);
                axesList(k) = ax;
                f = fieldsList{k};
                if ~f.ok
                    title(ax, conditions(k).label + newline + "（描けません）", 'Interpreter', 'none', 'FontSize', 10);
                    axis(ax, 'off');
                    continue
                end
                titleText = conditions(k).label + newline + f.titles(valueIndex) + sprintf("（RMSE %.3f %s）", f.rmse, ...
                    spec.unit);
                drawMapPanel(app, ax, f, valueIndex, scale(1), limit, magnitude, titleText, false, range);
                ax.FontSize = app.SMALL_AXES_FONT_SIZE;
                if ~isempty(ax.Colorbar)
                    % 色の目盛りの名前は横に書く（並べた図では上に書くと題名と重なる）
                    ax.Colorbar.Label.String = ax.Colorbar.Title.String;
                    ax.Colorbar.Title.String = '';
                end
            end
            app.Controls.compareAxes = axesList;
            header = sprintf("並べて比べる：%s（%d 条件。矢印の倍率・色の範囲は共通。灰色の四角は学習に使った Mark）", ...
                string(c.mapCompareValue.Items{valueIndex}), nPanels);
            if numel(conditions) > nPanels
                header = header + sprintf("。一覧の %d 条件のうち、はじめの %d 条件を描きました", numel(conditions), nPanels);
            end
            c.mapInfo.Text = header + "｜" + strjoin(lines, "　／　") + filterNote(app);
        end

        function drawMapPanel(app, ax, f, k, scale, limit, magnitude, titleText, showLegend, colorRange)
            % マップの1枚（mapFields の k 番目の値）を描く。Shot の枠・Scan 方向の色・同心円の区切りは画面の選択に従う。
            % colorRange（省略可）：1変数の計測値・推定値の色の範囲 [最小, 最大]（alignest.plot.waferMap）
            if nargin < 10
                colorRange = [NaN, NaN];
            end
            c = app.Controls;
            settings = app.Results.settings;
            spec = resultSpec(app);
            colorTitle = "";
            if spec.scalar
                colorTitle = spec.name + " [" + spec.unit + "]";
            end
            centers = zeros(0, 2);
            sizeMm = [NaN, NaN];
            directions = zeros(0, 1);
            if c.mapShotFrames.Value || c.mapScanFrames.Value
                centers = f.centers;
                sizeMm = f.sizeMm;
                if c.mapScanFrames.Value
                    directions = f.directions;
                end
            end
            rings = zeros(1, 0);
            if c.mapRings.Value
                rings = activeZoneEdges(settings);
            end
            ellipseSigma = c.mapEllipse.Value * f.isGroup;
            alignest.plot.waferMap(ax, f.points, f.values{k}, mode=string(c.mapMode.Value), scaleMmPerNm=scale, ...
                colorLimit=limit, trainPoints=f.trainPoints, outlierPoints=f.outlierPoints, titleText=titleText, ...
                waferRadiusMm=settings.data.waferRadiusMm, magnitudeLimit=magnitude, arrowColor=app.ARROW_COLORS(k, :), ...
                markerSize=c.mapMarkerSize.Value, markerShape=c.mapMarkerShape.Value, shotCenters=centers, ...
                shotSizeMm=sizeMm, shotDirections=directions, ringRadiiMm=rings, covariance=f.covariance{k}, ...
                ellipseSigma=ellipseSigma, showArrows=~(c.mapEllipseOnly.Value && ellipseSigma > 0), showLegend=showLegend, ...
                colorRange=colorRange, colorTitle=colorTitle);
            ax.FontSize = app.AXES_FONT_SIZE;
        end

        function [scale, limit, magnitudes] = mapScales(app, values, referenceIndex, separateThird)
            % 矢印の倍率（0 = 自動なら基準の値から）・色の範囲（基準の値の最大の絶対値）・矢印の色の範囲。
            % separateThird（Overlay 補正）なら、3つ目（推定による変化）は小さいので自分の値で倍率を決める
            c = app.Controls;
            reference = values{referenceIndex};
            scale = repmat(c.mapScale.Value, 1, 3);
            if c.mapScale.Value <= 0
                scale(:) = alignest.plot.vectorScale(reference);
                if separateThird
                    scale(3) = alignest.plot.vectorScale(values{3});
                end
            end
            limit = max(abs(reference(isfinite(reference))), [], 'all');
            if isempty(limit) || limit <= 0
                limit = 1;
            end
            magnitudes = sharedMagnitudeLimits(values{1}, values{2});
        end

        function f = mapFields(app, optionIndex, planLabel, m, content)
            % 1つの条件（Wafer・平均 × 学習パターン × 手法）のマップの値。描けないときは f.ok = false、f.message に理由。
            % f.values{1〜3}：計測値・推定値・残差（content = "overlay" なら 実測値で補正した残差・推定値で補正した残差・
            % 推定による変化）。点数 × 2 [nm]、点の座標は f.points。平均（f.isGroup）では座標ごとの Wafer 間の平均と
            % 共分散（f.covariance）。評価点の絞り込みの条件に合う点だけを入れる。f.rmse は RMSE（X・Y）の値（平均なら
            % Wafer の平均）、f.info は図の下の説明
            c = app.Controls;
            results = app.Results;
            option = c.mapWafer.UserData(optionIndex);
            method = results.methods(m);
            f = struct("ok", false, "message", "", "points", zeros(0, 2), "values", {cell(1, 3)}, ...
                "covariance", {repmat({zeros(0, 3)}, 1, 3)}, "titles", strings(1, 3), "trainPoints", zeros(0, 2), ...
                "outlierPoints", zeros(0, 2), "centers", zeros(0, 2), "sizeMm", [NaN, NaN], "directions", zeros(0, 1), ...
                "isGroup", option.isGroup, "rmse", NaN, "info", "");
            overlayContent = string(content) == "overlay";
            if overlayContent && option.isGroup
                f.titles = ["実測値で補正した残差の平均", "推定値で補正した残差の平均", "推定による変化の平均"];
            elseif overlayContent
                f.titles = ["実測値で補正した残差", "推定値で補正した残差", "推定による変化（推定値で補正 − 実測値で補正）"];
            elseif option.isGroup
                f.titles = ["計測値の平均（評価した Shot）", "推定値の平均", "残差（計測値 − 推定値）の平均"];
            else
                f.titles = ["計測値（評価した Shot）", "推定値", "残差（計測値 − 推定値）"];
            end
            try
                if isImportedResults(results)
                    f = importedMapFields(app, f, option, string(planLabel), method, m, overlayContent);
                else
                    f = computedMapFields(app, f, option, string(planLabel), method, m, overlayContent);
                end
            catch err
                f.ok = false;
                f.message = "⚠ " + string(err.message);
            end
            if f.ok
                f.info = f.info + filterNote(app);
            end
        end

        function f = computedMapFields(app, f, option, planLabel, method, m, overlayContent)
            % このセッションで評価した結果のマップの値（推定値は評価のときの値を使い回す。alignest.compactEstimate）
            results = app.Results;
            settings = results.settings;
            plans = results.plans;
            [~, ~, filterActive] = alignest.pointFilterMask(app.ResultFilter);
            if overlayContent
                choice = alignest.overlayChoice(settings);
            end
            pointsList = cell(1, 0);
            panelValues = {cell(1, 0), cell(1, 0), cell(1, 0)};
            firstUnit = [];
            skipped = 0;
            for u = option.unitIndex
                planIndex = find(string({plans.label}) == planLabel & [plans.unitIndex] == u, 1);
                if isempty(planIndex) || ~plans(planIndex).ok
                    if ~option.isGroup && isempty(planIndex)
                        f.message = "⚠ この Wafer はこの学習パターンを計算していません（途中で止めた場合など）。";
                        return
                    elseif ~option.isGroup
                        f.message = "⚠ この Wafer ではこの学習パターンを作れませんでした：" + plans(planIndex).message;
                        return
                    end
                    skipped = skipped + 1;
                    continue
                end
                try
                    out = cachedEstimate(app, u, planIndex, m);
                catch err
                    if ~option.isGroup
                        f.message = "⚠ この組み合わせでは推定できませんでした：" + string(err.message);
                        return
                    end
                    skipped = skipped + 1;
                    continue
                end
                unit = app.Data.units(u);
                marks = unit.marks;
                mask = true(numel(marks.x), 1);
                if filterActive
                    mask = alignest.unitPointFilter(unit, app.ResultFilter);
                end
                if overlayContent
                    correction = alignest.overlayCorrection(unit, out, ...
                        alignest.overlayProjector(unit, choice, settings.data.waferRadiusMm), mask);
                    usable = (marks.validX | marks.validY) & mask;
                    values = {correction.fields.residualActual, correction.fields.residualEstimated, correction.fields.change};
                else
                    measured = nan(numel(marks.x), 2);
                    estimate = nan(numel(marks.x), 2);
                    measured(out.testIndex.X, 1) = marks.measX(out.testIndex.X);
                    measured(out.testIndex.Y, 2) = marks.measY(out.testIndex.Y);
                    estimate(out.testIndex.X, 1) = out.estimate.X;
                    estimate(out.testIndex.Y, 2) = out.estimate.Y;
                    usable = any(isfinite(measured), 2) & mask;
                    values = {measured, estimate, measured - estimate};
                end
                pointsList{end + 1} = [marks.x(usable), marks.y(usable)]; %#ok<AGROW>
                for k = 1:3
                    panelValues{k}{end + 1} = values{k}(usable, :);
                end
                if isempty(firstUnit)
                    % 学習 Shot の四角・異常値の × は最初の Wafer の位置（平均の図でも）
                    firstUnit = unit;
                    plan = plans(planIndex);
                    trainMarks = alignest.trainingMarks(unit, plan) & (marks.validX | marks.validY) & mask;
                    f.trainPoints = [marks.x(trainMarks), marks.y(trainMarks)];
                    if ~overlayContent && ~option.isGroup && isfield(out, "outlierIndex")
                        outlierIndex = out.outlierIndex(mask(out.outlierIndex));
                        f.outlierPoints = [marks.x(outlierIndex), marks.y(outlierIndex)];
                    end
                    firstOut = out;
                    firstMask = mask;
                    if overlayContent
                        firstCorrection = correction;
                    end
                end
            end
            if isempty(firstUnit)
                f.message = "⚠ この平均に使える Wafer がありません（学習パターンを作れなかった、または推定できなかった）。";
                return
            end
            if sum(cellfun(@(points) size(points, 1), pointsList)) == 0
                f.message = "⚠ 評価点の絞り込みの条件に合う点がありません（「解除」または条件を変えてください）。";
                return
            end
            shots = firstUnit.shots;
            f.centers = [shots.Xmm, shots.Ymm];
            f.sizeMm = firstUnit.shotSizeMm;
            f.directions = nan(numel(shots.Xmm), 1);
            if firstUnit.hasDirection
                f.directions = shots.direction;
            end
            table_ = results.table;
            if option.isGroup
                for k = 1:3
                    average = alignest.averageFields(pointsList, panelValues{k});
                    f.values{k} = average.mean;
                    f.covariance{k} = average.covariance;
                end
                f.points = average.points;
                rows = table_(ismember(table_.unitIndex, option.unitIndex) & table_.plan == planLabel & ...
                    table_.methodIndex == m, :);
                f.rmse = mean(rows.RMSE_XY, 'omitnan');
                f.info = sprintf(['%s｜%s｜%s｜平均した Wafer %d 枚%s｜座標ごとに Wafer 間で平均（楕円は Wafer 間の' ...
                    'ばらつき、色は X・Y の相関係数の絶対値 |r|）｜Wafer ごとの RMSE（X・Y）の平均 %.3f nm'], option.label, ...
                    planLabel, method.label, numel(pointsList), ternary(skipped > 0, sprintf("（使えなかった Wafer %d 枚）", ...
                    skipped), ""), f.rmse);
                f = addWorstValues(app, f, rows);
                f.ok = true;
                return
            end
            f.points = pointsList{1};
            f.values = cellfun(@(values) values{1}, panelValues, 'UniformOutput', false);
            if overlayContent
                metrics = firstCorrection.metrics;
                f.rmse = mean(table_.RMSE_XY(table_.unitIndex == option.unitIndex & table_.planIndex == planIndex & ...
                    table_.methodIndex == m));
                f.info = sprintf(['%s｜%s｜%s｜補正モデル：%s｜|平均|+3σ [nm]：実測値で補正 X %.3f・Y %.3f、' ...
                    '推定値で補正 X %.3f・Y %.3f、推定による変化 X %.3f・Y %.3f（増加 X %+.3f・Y %+.3f）'], firstUnit.label, ...
                    planLabel, method.label, choice.description, metrics.overlayActual_X, metrics.overlayActual_Y, ...
                    metrics.overlayEstimated_X, metrics.overlayEstimated_Y, metrics.overlayChange_X, metrics.overlayChange_Y, ...
                    metrics.overlayIncrease_X, metrics.overlayIncrease_Y);
                f = addWorstValues(app, f, rowsOf(table_, option, planLabel, m));
                f.ok = true;
                return
            end
            row = table_(table_.unitIndex == option.unitIndex & table_.planIndex == planIndex & table_.methodIndex == m, :);
            metricsText = "";
            if ~isempty(row)
                f.rmse = row.RMSE_XY;
                metricsText = sprintf("RMSE（X・Y）%.3f nm、X %.3f nm、Y %.3f nm｜R² %.3f｜MAE %.3f nm｜平均値に対する改善率 %.1f%%", ...
                    row.RMSE_XY, row.RMSE_X, row.RMSE_Y, row.R2_XY, row.MAE_XY, row.improveMeanPct_XY);
                spec = alignest.valueSpec(settings.data);
                if spec.scalar
                    metricsText = sprintf("RMSE（%s）%.3f %s｜R² %.3f｜MAE %.3f %s｜平均値に対する改善率 %.1f%%", spec.name, ...
                        row.RMSE_XY, spec.unit, row.R2_XY, row.MAE_XY, spec.unit, row.improveMeanPct_XY);
                end
            end
            outlierText = "";
            evaluation = settings.evaluation;
            if isfield(evaluation, "excludeOutliers") && evaluation.excludeOutliers
                outlierText = sprintf("｜学習から除いた異常値 %d 点（%gσ 超、×印）", size(f.outlierPoints, 1), ...
                    evaluation.outlierSigma);
            end
            plan = plans(planIndex);
            trainText = sprintf("学習 Shot %d（shotNo：%s）", plan.nShots, strjoin(string(plan.shotNos(:).'), " "));
            if ~isempty(plan.markIndex)
                trainText = sprintf("学習 Mark %d（全 %d Shot で1点以上）", numel(plan.markIndex), plan.nShots);
            end
            testText = sprintf("評価点 X %d・Y %d", nnz(firstMask(firstOut.testIndex.X)), nnz(firstMask(firstOut.testIndex.Y)));
            if alignest.valueSpec(settings.data).scalar
                testText = sprintf("評価点 %d", nnz(firstMask(firstOut.testIndex.X)));
            end
            f.info = sprintf("%s｜%s｜%s｜%s｜%s%s｜%s", firstUnit.label, plan.label, method.label, trainText, testText, ...
                outlierText, metricsText);
            f = addWorstValues(app, f, rowsOf(table_, option, planLabel, m));
            f.ok = true;
        end

        function f = importedMapFields(app, f, option, planLabel, method, m, overlayContent)
            % Excel から読み込んだ推定値のマップの値（Shot 中心の座標は Excel に無いので、Shot の枠は描かない）
            results = app.Results;
            if overlayContent
                source = app.ImportedEstimates.overlayPoints;
                columns = ["residualActual", "residualEstimated", "change"];
            else
                source = app.ImportedEstimates.estimates;
                source = source(source.role == "評価" | startsWith(source.role, "学習"), :);
                columns = ["meas", "estimate", "residual"];
            end
            [~, ~, filterActive] = alignest.pointFilterMask(app.ResultFilter);
            pointsList = cell(1, 0);
            panelValues = {cell(1, 0), cell(1, 0), cell(1, 0)};
            for u = option.unitIndex
                rows = source(source.Wafer == results.unitLabels(u) & source.plan == planLabel & ...
                    source.methodId == method.id, :);
                if height(rows) == 0
                    continue
                end
                mask = true(height(rows), 1);
                if filterActive
                    % Overlay 残差のシートには半径・Scan 方向の列が無いので、座標から半径を求める（Scan 方向は無し）
                    direction = nan(height(rows), 1);
                    if any(rows.Properties.VariableNames == "direction")
                        direction = rows.direction;
                    end
                    mask = alignest.pointFilterMask(app.ResultFilter, struct("r", hypot(rows.x, rows.y), ...
                        "shotNo", rows.shotNo, "direction", direction));
                end
                train = startsWith(rows.role, "学習");
                if isempty(pointsList)
                    f.trainPoints = [rows.x(train & mask), rows.y(train & mask)];   % 平均の図でも最初の Wafer の位置
                    outlier = rows.role == "学習（異常値として除外）" & mask;
                    f.outlierPoints = [rows.x(outlier), rows.y(outlier)];
                end
                keep = mask;
                if ~overlayContent
                    keep = mask & ~train;   % 計測値・推定値・残差は評価点だけ
                end
                rows = rows(keep, :);
                pointsList{end + 1} = [rows.x, rows.y]; %#ok<AGROW>
                for k = 1:3
                    panelValues{k}{end + 1} = [rows.(columns(k) + "X"), rows.(columns(k) + "Y")];
                end
            end
            if isempty(pointsList)
                f.message = "⚠ この Wafer・学習パターン・手法の推定値は、読み込んだ推定値の Excel にありません" + ...
                    "（書き出した範囲の外）。";
                return
            end
            if sum(cellfun(@(points) size(points, 1), pointsList)) == 0
                f.message = "⚠ 評価点の絞り込みの条件に合う点がありません（「解除」または条件を変えてください）。";
                return
            end
            if option.isGroup
                for k = 1:3
                    average = alignest.averageFields(pointsList, panelValues{k});
                    f.values{k} = average.mean;
                    f.covariance{k} = average.covariance;
                end
                f.points = average.points;
                f.outlierPoints = zeros(0, 2);
            else
                f.points = pointsList{1};
                f.values = cellfun(@(values) values{1}, panelValues, 'UniformOutput', false);
            end
            rows = rowsOf(results.table, option, planLabel, m);
            f.rmse = mean(rows.RMSE_XY, 'omitnan');
            f.info = sprintf("%s｜%s｜%s｜Excel から読み込んだ推定値（Wafer %d 枚）｜Wafer ごとの RMSE（X・Y）の平均 %.3f nm", ...
                option.label, planLabel, method.label, numel(pointsList), f.rmse);
            f = addWorstValues(app, f, rows);
            f.ok = true;
        end

        function refreshMapConditions(app)
            % 並べて比べる条件の一覧を画面に出す
            c = app.Controls;
            conditions = app.MapConditions;
            c.mapConditions.Items = cellstr(string({conditions.label}));
            c.mapConditions.ItemsData = num2cell(1:numel(conditions));
            c.mapConditions.Value = {};
        end

        function f = addWorstValues(app, f, rows)
            % マップの3枚目（残差・推定による変化）の点の大きさ |v| のワースト値と 95%値を題名に、X・Y 別の値と
            % （平均の図では）Wafer ごとの RMSE のワースト値・95%値を説明に足す（結果一覧の集計と同じ PERCENTILE.INC）
            values = f.values{3};
            spec = resultSpec(app);
            if spec.scalar
                % 1変数：残差の絶対値のワースト値・95%値
                magnitude = abs(values(:, 1));
                worst = max(magnitude, [], 'omitnan');
                if isempty(worst) || ~isfinite(worst)
                    return
                end
                f.titles(3) = f.titles(3) + newline + sprintf("|残差| のワースト %.3f %s・95%%値 %.3f %s", worst, ...
                    spec.unit, alignest.stats.percentile(magnitude, app.WORST_PERCENT), spec.unit);
                f.info = f.info + sprintf("｜残差：ワースト値 %.3f %s、95%%値 %.3f %s", worst, spec.unit, ...
                    alignest.stats.percentile(magnitude, app.WORST_PERCENT), spec.unit);
                if f.isGroup && height(rows) > 0
                    f.info = f.info + sprintf("｜Wafer ごとの RMSE：ワースト値 %.3f %s、95%%値 %.3f %s", ...
                        max(rows.RMSE_XY, [], 'omitnan'), spec.unit, ...
                        alignest.stats.percentile(rows.RMSE_XY, app.WORST_PERCENT), spec.unit);
                end
                return
            end
            magnitude = hypot(values(:, 1), values(:, 2));
            worst = max(magnitude, [], 'omitnan');
            if isempty(worst) || ~isfinite(worst)
                return
            end
            f.titles(3) = f.titles(3) + newline + sprintf("|v| のワースト %.2f nm・95%%値 %.2f nm", worst, ...
                alignest.stats.percentile(magnitude, app.WORST_PERCENT));
            f.info = f.info + sprintf("｜%s：ワースト値 X %.3f・Y %.3f nm、95%%値 X %.3f・Y %.3f nm", ...
                extractBefore(f.titles(3) + "（", "（"), max(abs(values(:, 1)), [], 'omitnan'), ...
                max(abs(values(:, 2)), [], 'omitnan'), alignest.stats.percentile(abs(values(:, 1)), app.WORST_PERCENT), ...
                alignest.stats.percentile(abs(values(:, 2)), app.WORST_PERCENT));
            if f.isGroup && height(rows) > 0
                f.info = f.info + sprintf("｜Wafer ごとの RMSE（X・Y）：ワースト値 %.3f nm、95%%値 %.3f nm", ...
                    max(rows.RMSE_XY, [], 'omitnan'), alignest.stats.percentile(rows.RMSE_XY, app.WORST_PERCENT));
            end
        end

        function onAddMapCondition(app)
            runWithAlert(app, @() app.addMapCondition(), "条件を追加できませんでした", ...
                "Wafer・平均、学習パターン、手法を選び直してください。");
        end

        function out = cachedEstimate(app, u, planIndex, m)
            % 推定結果を使い回す（マップ・散布図・推定値の書き出しで共通のキー）
            key = sprintf('%d|%d|%d', u, planIndex, m);
            if isKey(app.MapCache, key)
                out = app.MapCache(key);
                return
            end
            app.Figure.Pointer = 'watch';
            drawnow;
            restore = onCleanup(@() set(app.Figure, 'Pointer', 'arrow'));
            plan = app.Results.plans(planIndex);
            out = alignest.estimateWafer(app.Data.units(u), plan, app.Results.methods(m), app.Results.settings);
            app.MapCache(key) = out;
        end

        function units = mapUnits(app)
            % マップの「Wafer・平均」の選択肢を作る Wafer の並び（読み込んだ結果では、結果の表の Wafer・LotID・EqpId・Operation）
            if ~isImportedResults(app.Results)
                units = app.Data.units;
                return
            end
            results = app.Results;
            units = struct("label", {}, "lotId", {}, "eqpId", {}, "operation", {});
            for u = 1:numel(results.unitLabels)
                row = find(results.table.unitIndex == u, 1);
                units(u) = struct("label", results.unitLabels(u), "lotId", results.table.LotID(row), ...
                    "eqpId", results.table.EqpId(row), "operation", results.table.Operation(row));
            end
        end

        function onSaveMap(app)
            [fileName, folder] = uiputfile({'*.png', 'PNG 画像 (*.png)'}, '図を保存', 'wafer_map.png');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            if runWithAlert(app, @() exportgraphics(app.Controls.mapPanel, target, 'Resolution', 150), ...
                    "図を保存できませんでした", "保存先のフォルダを変えてもう一度試してください。")
                uialert(app.Figure, sprintf('保存しました：%s', target), '保存しました', 'Icon', 'success');
            end
        end

        % ================= 6. 未知の座標の推定 =================
        function buildTargetTab(app)
            % 左：推定する点（未知の座標）の表と、その作り方。右：推定の条件・メッセージ・図・推定値の表
            grid = uigridlayout(app.Tabs.target, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 12, 'RowSpacing', 8);
            label(grid, ['学習データ（計測値）から、計測していない座標（新しい Mark の位置・Wafer 上の任意の点）の値を推定します。' ...
                '左の表で点を決め（Excel・CSV から読み込むか、画面で入力・作成）、右で Wafer・学習データ・手法を選んで' ...
                '「推定する」を押します。学習点の範囲の外（外挿）になる点は、右のメッセージと表・図で知らせます。'], 1, 1);
            body = uigridlayout(grid, [1, 2], 'ColumnWidth', {610, '1x'}, 'Padding', 0, 'ColumnSpacing', 14);
            left = uigridlayout(body, [6, 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit', 'fit'}, ...
                'Padding', 0, 'RowSpacing', 6);
            place(uilabel(left, 'Text', '① 推定する点（未知の座標）', 'FontWeight', 'bold'), 1, 1);
            buttons = uigridlayout(left, [1, 4], 'ColumnWidth', {'fit', 'fit', 'fit', 'fit'}, 'Padding', 0);
            c.targetLoad = uibutton(buttons, 'Text', 'Excel・CSV から読み込む…', 'ButtonPushedFcn', @(~, ~) app.onLoadTargets(), ...
                'Tooltip', ['1行目が見出し（Xmm・Ymm は必須。markXmm・markYmm・markNo・shotNo・Direction・名前 は任意）の表を' ...
                '読み、下の表を置き換えます。「未知の座標」シートがあればそれを読みます。']);
            c.targetAddRow = uibutton(buttons, 'Text', '行を追加', 'ButtonPushedFcn', @(~, ~) app.onAddTargets("row"));
            c.targetDeleteRows = uibutton(buttons, 'Text', '選んだ行を削除', 'ButtonPushedFcn', @(~, ~) app.onDeleteTargetRows());
            c.targetClear = uibutton(buttons, 'Text', 'すべて消す', 'ButtonPushedFcn', @(~, ~) app.setTargetPoints( ...
                alignest.targetTemplate()));
            % 点の作り方：全 Shot の同じ位置（新しい Mark の位置など）・Wafer 上の格子（Wafer 全面）
            makers = uigridlayout(left, [2, 8], 'ColumnWidth', {'fit', 'fit', 55, 'fit', 55, 'fit', 45, 'fit'}, ...
                'RowHeight', {'fit', 'fit'}, 'Padding', 0, 'ColumnSpacing', 8);
            label(makers, '全 Shot に置く [mm]', 1, 1);
            label(makers, 'X', 1, 2);
            c.targetShotX = uieditfield(makers, 'numeric', 'Value', 0, 'Tooltip', 'Shot 中心から見た X [mm]（markXmm）');
            place(c.targetShotX, 1, 3);
            label(makers, 'Y', 1, 4);
            c.targetShotY = uieditfield(makers, 'numeric', 'Value', 0, 'Tooltip', 'Shot 中心から見た Y [mm]（markYmm）');
            place(c.targetShotY, 1, 5);
            label(makers, 'Mark 番号', 1, 6);
            c.targetShotMark = uieditfield(makers, 'text', 'Value', '', 'Tooltip', ['空欄でもよい（Mark 番号の効果は平均）。' ...
                '学習データに無い番号でもよい（新しい Mark）。']);
            place(c.targetShotMark, 1, 7);
            c.targetAddShots = uibutton(makers, 'Text', '表に追加', 'ButtonPushedFcn', @(~, ~) app.onAddTargets("shots"), ...
                'Tooltip', '右で選んだ Wafer（すべてなら最初の Wafer）の全 Shot の、同じ位置に点を置きます。');
            place(c.targetAddShots, 1, 8);
            label(makers, '格子で置く [mm]', 2, 1);
            label(makers, '間隔', 2, 2);
            c.targetPitch = uieditfield(makers, 'numeric', 'Value', app.TARGET_GRID_PITCH_MM, 'Limits', [0, Inf], ...
                'LowerLimitInclusive', 'off', 'Tooltip', '格子の点の間隔 [mm]');
            place(c.targetPitch, 2, 3);
            label(makers, '半径', 2, 4);
            c.targetRadius = uieditfield(makers, 'numeric', 'Value', app.TARGET_GRID_RADIUS_MM, 'Limits', [0, Inf], ...
                'LowerLimitInclusive', 'off', 'Tooltip', 'Wafer の中心からこの半径 [mm] 以内に置く');
            place(c.targetRadius, 2, 5);
            c.targetAddGrid = uibutton(makers, 'Text', '表に追加', 'ButtonPushedFcn', @(~, ~) app.onAddTargets("grid"), ...
                'Tooltip', 'Wafer の中心から半径以内に、間隔ごとの格子の点を置きます（Wafer 全面の推定値を見るとき）。');
            place(c.targetAddGrid, 2, 8);
            c.targetTable = uitable(left, 'ColumnName', app.TARGET_COLUMNS, 'ColumnEditable', true, 'RowName', 'numbered', ...
                'Data', cell(0, numel(app.TARGET_COLUMNS)), 'ColumnFormat', repmat({'char'}, 1, numel(app.TARGET_COLUMNS)), ...
                'ColumnWidth', [{76}, repmat({66}, 1, numel(app.TARGET_COLUMNS) - 1)], ...
                'CellEditCallback', @(~, ~) app.onTargetEdited(), ...
                'CellSelectionCallback', @(~, event) app.onTargetSelected(event));
            place(c.targetTable, 4, 1);
            c.targetInfo = uilabel(left, 'WordWrap', 'on', 'FontColor', app.Palette.muted, 'Text', '');
            place(c.targetInfo, 5, 1);
            c.targetError = errorLabel(app, left, 6, 1);

            % 右：条件（Wafer・学習データ・手法）、メッセージ、結果（図と推定値の表を中のタブで切り替える）
            right = uigridlayout(body, [4, 1], 'RowHeight', {'fit', 'fit', 'fit', '1x'}, 'Padding', 0, 'RowSpacing', 6);
            place(uilabel(right, 'Text', '② 推定の条件と結果', 'FontWeight', 'bold'), 1, 1);
            controls = uigridlayout(right, [3, 3], 'ColumnWidth', {'1x', '1.2x', '1.6x'}, ...
                'RowHeight', {'fit', 'fit', 'fit'}, 'Padding', 0);
            label(controls, 'Wafer', 1, 1);
            label(controls, '学習データ', 1, 2);
            label(controls, '手法', 1, 3);
            c.targetWafer = uidropdown(controls, 'Items', {'—'}, 'ItemsData', {1}, ...
                'ValueChangedFcn', @(~, ~) app.drawTargetMap());
            place(c.targetWafer, 2, 1);
            c.targetTraining = uidropdown(controls, 'Items', {'計測値のある全 Mark（全 Shot）'}, ...
                'ItemsData', {char(app.TARGET_ALL_TRAINING)}, 'Tooltip', ['計測値のある全 Mark：読み込んだ計測値をすべて学習に' ...
                '使います。学習パターン：評価で選んだ Shot（Mark）だけを学習に使います（「3. 実行」で評価した後に選べます）。']);
            place(c.targetTraining, 2, 2);
            c.targetMethod = uidropdown(controls, 'Items', {'—'}, 'ItemsData', {1}, ...
                'Tooltip', '「2. 評価の設定」で選んだ手法から選びます。推定の条件（1次を除く・異常値の除外）も今の設定のとおりです。');
            place(c.targetMethod, 2, 3);
            actions = uigridlayout(controls, [1, 2], 'ColumnWidth', {160, 'fit'}, 'Padding', 0);
            place(actions, 3, [1, 3]);
            c.targetRun = primaryButton(app, actions, '推定する', @(~, ~) app.onEstimateTargets());
            c.targetExport = uibutton(actions, 'Text', '推定値を Excel に書き出す…', ...
                'ButtonPushedFcn', @(~, ~) app.onExportTargets());
            c.targetMessage = uilabel(right, 'WordWrap', 'on', 'FontWeight', 'bold', 'Text', ...
                '「1. データの読み込み」で計測データを読み込み、左の表に推定する点を決めてから「推定する」を押してください。');
            place(c.targetMessage, 3, 1);
            outputs = uitabgroup(right);
            place(outputs, 4, 1);
            figureTab = uitab(outputs, 'Title', '図');
            figureGrid = uigridlayout(figureTab, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 6, 'RowSpacing', 4);
            figureControls = uigridlayout(figureGrid, [1, 3], 'ColumnWidth', {'fit', 140, 'fit'}, 'Padding', 0);
            label(figureControls, '表示', 1, 1);
            c.targetMode = uidropdown(figureControls, 'Items', {'ベクトル（矢印）', 'X（色）', 'Y（色）'}, ...
                'ItemsData', {'vector', 'X', 'Y'}, 'ValueChangedFcn', @(~, ~) app.drawTargetMap());
            place(c.targetMode, 1, 2);
            c.targetSaveFigure = uibutton(figureControls, 'Text', '図を画像で保存…', ...
                'ButtonPushedFcn', @(~, ~) app.onSaveTargetFigure());
            place(c.targetSaveFigure, 1, 3);
            c.targetPanel = uipanel(figureGrid, 'BorderType', 'none');
            place(c.targetPanel, 2, 1);
            c.targetAxes = uiaxes(uigridlayout(c.targetPanel, [1, 1], 'Padding', 0));
            tableTab = uitab(outputs, 'Title', '推定値の表');
            c.targetResultTable = uitable(uigridlayout(tableTab, [1, 1], 'Padding', 6), 'RowName', {}, 'Data', table());
            set([c.targetRun, c.targetExport, c.targetSaveFigure, c.targetAddShots], 'Enable', 'off');
            app.Controls = mergeStruct(app.Controls, c);
            onTargetEdited(app);
        end

        function onTabChanged(app, event)
            % 「6. 未知の座標の推定」を開いたら、選択肢（Wafer・学習データ・手法）を今のデータ・結果・設定に合わせる
            if event.NewValue == app.Tabs.target
                refreshTargetChoices(app);
            end
        end

        function refreshTargetChoices(app)
            % 推定の条件の選択肢を作り直す（前に選んでいたものが残っていれば、そのまま選ぶ）
            c = app.Controls;
            hasData = ~isempty(app.Data);
            if hasData
                labels = string({app.Data.units.label});
                setChoices(c.targetWafer, [labels, "すべての Wafer（Wafer ごとに推定して並べる）"], [num2cell(1:numel(labels)), {0}]);
            else
                setChoices(c.targetWafer, "—（データを読み込んでください）", {1});
            end
            trainingItems = "計測値のある全 Mark（全 Shot）";
            trainingData = {char(app.TARGET_ALL_TRAINING)};
            if ~isempty(app.Results) && ~isImportedResults(app.Results) && isfield(app.Results, 'plans')
                planLabels = unique(string({app.Results.plans.label}), 'stable');
                trainingItems = [trainingItems, "学習パターン：" + planLabels];
                trainingData = [trainingData, cellstr(planLabels)];
            end
            setChoices(c.targetTraining, trainingItems, trainingData);
            setModeChoices(c.targetMode, alignest.valueSpec(app.Settings.data));
            methods = alignest.activeMethods(app.Settings);   % 1変数では RT モデルを除く
            if isempty(methods)
                setChoices(c.targetMethod, "—（「2. 評価の設定」で手法を選んでください）", {1});
            else
                setChoices(c.targetMethod, string({methods.label}), num2cell(1:numel(methods)));
            end
            c.targetAddShots.Enable = onOff(hasData);   % 「全 Shot に置く」は読み込んだ Wafer の Shot の並びを使う
            c.targetRun.Enable = onOff(hasData && ~isempty(methods));
        end

        function targets = currentTargets(app)
            % 表（画面）の点を alignest.targetTemplate の形にする。数でない欄は行の番号を出して止める
            data = app.Controls.targetTable.Data;
            n = size(data, 1);
            if n == 0
                error('alignest:noTargets', '推定する点がありません。左の表に点を読み込むか、足してください。');
            end
            text = strings(size(data));
            for k = 1:numel(data)
                if ~isempty(data{k})
                    text(k) = strtrim(alignest.normalizeNumberText(string(data{k})));
                end
            end
            numbers = str2double(text(:, 2:end));
            targets = alignest.targetTemplate(n);
            targets.name = text(:, 1);
            unnamed = targets.name == "";
            targets.name(unnamed) = "P" + string(find(unnamed));
            names = ["Xmm", "Ymm", "markXmm", "markYmm", "markNo", "shotNo", "direction"];
            for k = 1:numel(names)
                column = numbers(:, k);
                unreadable = isnan(column) & text(:, k + 1) ~= "";
                if any(unreadable)
                    error('alignest:targetTable', '%s 列に数でない値があります（表の %s 行目）。', app.TARGET_COLUMNS{k + 1}, ...
                        strjoin(string(find(unreadable).'), "・"));
                end
                targets.(names(k)) = column;
            end
            missing = isnan(targets.Xmm) | isnan(targets.Ymm);
            if any(missing)
                error('alignest:targetTable', 'Xmm・Ymm が空欄の行があります（表の %s 行目）。', ...
                    strjoin(string(find(missing).'), "・"));
            end
            badDirection = ~isnan(targets.direction) & ~ismember(targets.direction, [1, 2]);
            if any(badDirection)
                error('alignest:targetTable', 'Direction（Scan 方向）は 1 か 2 にしてください（表の %s 行目）。', ...
                    strjoin(string(find(badDirection).'), "・"));
            end
            targets.markXmm(isnan(targets.markXmm)) = 0;   % 空欄は Shot 中心（Xmm・Ymm がそのまま点の座標）
            targets.markYmm(isnan(targets.markYmm)) = 0;
        end

        function onTargetEdited(app)
            % 表を変えたら、点の数と入力の誤りを出す（前の推定値は残すが、推定し直すよう伝える）
            c = app.Controls;
            n = size(c.targetTable.Data, 1);
            c.targetInfo.Text = sprintf(['%d 点。Xmm・Ymm：Shot 中心の Wafer 上の座標 [mm]（markXmm・markYmm が 0 なら点そのもの）、' ...
                'markXmm・markYmm：Shot 中心から見た位置 [mm]。markNo・shotNo・Direction は空欄でもよい' ...
                '（推定のとき、点を含む Shot から Scan 方向を補います）。'], n);
            c.targetError.Text = '';
            if n > 0
                try
                    currentTargets(app);
                catch err
                    c.targetError.Text = ['⚠ ', err.message];
                end
            end
            if ~isempty(app.TargetRun) && ~app.TargetRun.stale
                app.TargetRun.stale = true;
                c.targetMessage.Text = ['表の点を変えました。「推定する」を押すと、今の点で推定し直します。' newline ...
                    char(strjoin(app.TargetRun.messages, newline))];
            end
        end

        function onTargetSelected(app, event)
            app.TargetSelection = unique(event.Indices(:, 1));
        end

        function onDeleteTargetRows(app)
            rows = app.TargetSelection;
            data = app.Controls.targetTable.Data;
            rows = rows(rows >= 1 & rows <= size(data, 1));
            if isempty(rows)
                uialert(app.Figure, '削除する行を表で選んでください（Ctrl・Shift で複数選べます）。', '行を選んでください', ...
                    'Icon', 'info');
                return
            end
            data(rows, :) = [];
            app.Controls.targetTable.Data = data;
            app.TargetSelection = zeros(0, 1);
            onTargetEdited(app);
        end

        function onAddTargets(app, kind)
            c = app.Controls;
            switch kind
                case "shots"
                    markNo = str2double(alignest.normalizeNumberText(c.targetShotMark.Value));
                    if strtrim(c.targetShotMark.Value) ~= "" && isnan(markNo)
                        uialert(app.Figure, 'Mark 番号は数にしてください（空欄でもよい）。', 'Mark 番号', 'Icon', 'warning');
                        return
                    end
                    runWithAlert(app, @() app.addTargetPoints("shots", c.targetShotX.Value, c.targetShotY.Value, markNo), ...
                        "点を足せませんでした", "Shot 内の位置と Mark 番号を確かめてください。");
                case "grid"
                    runWithAlert(app, @() app.addTargetPoints("grid", c.targetPitch.Value, c.targetRadius.Value), ...
                        "点を足せませんでした", "間隔を広げるか、半径を小さくしてください。");
                otherwise
                    app.addTargetPoints("row");
                    scroll(c.targetTable, 'bottom');
            end
        end

        function onLoadTargets(app)
            [fileName, folder] = uigetfile({'*.xlsx;*.xls;*.csv', 'Excel・CSV (*.xlsx, *.xls, *.csv)'}, ...
                '未知の座標（推定する点）の表を選ぶ');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.loadTargetPoints(fullfile(folder, fileName)), "点を読み込めませんでした", ...
                "1行目に Xmm・Ymm の見出しがあるか、数の欄に文字が入っていないかを確かめてください。");
        end

        function onEstimateTargets(app)
            runWithAlert(app, @() app.estimateTargets(), "推定できませんでした", ...
                "左の表の点・学習データ・手法を確かめてください。学習点が少ないときは学習データを「計測値のある全 Mark」にしてください。");
        end

        function onExportTargets(app)
            [fileName, folder] = uiputfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, '推定値を書き出す', 'target_estimates.xlsx');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            if runWithAlert(app, @() app.exportTargetsTo(target), "書き出せませんでした", ...
                    "同じ名前のファイルを Excel で開いていれば閉じて、もう一度試してください。")
                uialert(app.Figure, sprintf('書き出しました：%s', target), '書き出しました', 'Icon', 'success');
            end
        end

        function onSaveTargetFigure(app)
            [fileName, folder] = uiputfile({'*.png', 'PNG 画像 (*.png)'}, '図を保存', 'target_map.png');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            if runWithAlert(app, @() exportgraphics(app.Controls.targetPanel, target, 'Resolution', 150), ...
                    "図を保存できませんでした", "保存先のフォルダを変えてもう一度試してください。")
                uialert(app.Figure, sprintf('保存しました：%s', target), '保存しました', 'Icon', 'success');
            end
        end

        function [plan, text] = targetTraining(app, unitIndex, training)
            % 学習データ：計測値のある全 Mark（全 Shot）、または評価の学習パターン（その Wafer のもの）
            if training == app.TARGET_ALL_TRAINING
                plan = 1:numel(app.Data.units(unitIndex).shots.shotNo);
                text = "計測値のある全 Mark（全 Shot）";
                return
            end
            plans = app.Results.plans;
            position = find(string({plans.label}) == training & [plans.unitIndex] == unitIndex, 1);
            if isempty(position)
                error('alignest:targetTraining', 'Wafer「%s」には学習パターン「%s」がありません。', ...
                    app.Data.units(unitIndex).label, training);
            end
            plan = plans(position);
            text = "学習パターン：" + training;
        end

        function showTargetRun(app)
            % 推定値の表・メッセージ・図を出す（外挿の行は色を付け、メッセージは目立つ色にする）
            run = app.TargetRun;
            c = app.Controls;
            e = run.estimates;
            mark = strings(height(e), 1);
            mark(e.extrapolated) = "外挿";
            spec = alignest.valueSpec(app.Settings.data);
            shown = table(e.wafer, e.name, round(e.x, 3), round(e.y, 3), e.markNo, e.shotNo, ...
                round(e.estimateX, 3), round(e.estimateY, 3), mark, round(e.outsideMm, 1), e.note, 'VariableNames', ...
                ["Wafer", "名前", "x [mm]", "y [mm]", "markNo", "shotNo", "推定値 X [nm]", "推定値 Y [nm]", "外挿", ...
                "範囲の外 [mm]", "メモ"]);
            if spec.scalar
                % 1変数：推定値は1列（値の名前と単位）
                shown = removevars(shown, "推定値 Y [nm]");
                shown.Properties.VariableNames{'推定値 X [nm]'} = char("推定値 " + spec.name + " [" + spec.unit + "]");
            end
            c.targetResultTable.Data = shown;
            removeStyle(c.targetResultTable);
            if any(e.extrapolated)
                addStyle(c.targetResultTable, uistyle('BackgroundColor', app.Palette.warning), 'row', find(e.extrapolated));
            end
            warn = any(e.extrapolated) || any(e.unseenMark);
            c.targetMessage.Text = char(strjoin(run.messages, newline));
            c.targetMessage.FontColor = ternary(warn, app.Palette.error, app.Palette.text);
            set([c.targetExport, c.targetSaveFigure], 'Enable', 'on');
            drawTargetMap(app);
        end

        function drawTargetMap(app)
            % 推定した Wafer（すべてなら選んだもの、無ければ最初）の図を描く
            run = app.TargetRun;
            c = app.Controls;
            if isempty(run)
                return
            end
            position = find(run.unitIndex == c.targetWafer.Value, 1);
            if isempty(position)
                position = 1;
            end
            unit = app.Data.units(run.unitIndex(position));
            titleText = unit.label + " の推定値";   % 手法・学習データは上の欄に出ている（題名が長いと色の目盛りの名前と重なる）
            alignest.plot.targetMap(c.targetAxes, run.results{position}, unit, mode=string(c.targetMode.Value), ...
                titleText=titleText, waferRadiusMm=app.Settings.data.waferRadiusMm, spec=alignest.valueSpec(app.Settings.data));
            c.targetAxes.FontSize = app.AXES_FONT_SIZE;
        end

        function clearTargetRun(app)
            app.TargetRun = [];
            c = app.Controls;
            if ~isfield(c, 'targetResultTable')
                return
            end
            c.targetResultTable.Data = table();
            removeStyle(c.targetResultTable);
            cla(c.targetAxes, 'reset');
            legend(c.targetAxes, 'off');
            set([c.targetExport, c.targetSaveFigure], 'Enable', 'off');
            c.targetMessage.Text = '左の表に推定する点を決めてから「推定する」を押してください。';
            c.targetMessage.FontColor = app.Palette.text;
        end

        function spec = resultSpec(app)
            % 結果を表示するときの推定する値（評価した設定の data。結果が無ければ今の設定）
            source = app.Settings.data;
            if ~isempty(app.Results) && isfield(app.Results, 'settings') && isfield(app.Results.settings, 'data')
                source = app.Results.settings.data;
            end
            spec = alignest.valueSpec(source);
        end

        % ================= 7. ヘルプ =================
        function buildHelpTab(app)
            % 用語・推定の手法・カーネル・Overlay 補正の式の説明（help/help.html。exe にも入れる）を出す
            grid = uigridlayout(app.Tabs.help, [1, 1], 'Padding', 0);
            helpFile = fullfile(fileparts(mfilename('fullpath')), 'help', 'help.html');
            c.helpView = uihtml(grid, 'HTMLSource', helpFile, 'Data', struct("theme", app.Theme));
            if ~isfile(helpFile)
                c.helpView.HTMLSource = ['<p style="font-family:sans-serif">ヘルプのファイルが見つかりません：', ...
                    char(helpFile), '</p>'];
            end
            app.Controls = mergeStruct(app.Controls, c);
        end

        % ================= 画面の色（ライト・ダーク） =================
        function applyTheme(app, old, new)
            % 画面の部品と図の色を old から new の色の組に変える。これから描く図の色は、図の既定値（Default…）で決める
            % （図を描き直す関数は cla(ax, 'reset') で既定値に戻すので、そのまま新しい色になる）
            fig = app.Figure;
            fig.Color = new.background;
            set(fig, 'DefaultAxesColor', new.axes, 'DefaultAxesXColor', new.axisLine, 'DefaultAxesYColor', new.axisLine, ...
                'DefaultAxesZColor', new.axisLine, 'DefaultAxesGridColor', new.grid, 'DefaultAxesMinorGridColor', new.grid, ...
                'DefaultTextColor', new.text, 'DefaultLegendTextColor', new.text, 'DefaultLegendColor', new.axes, ...
                'DefaultLegendEdgeColor', new.grid, 'DefaultColorbarColor', new.axisLine);
            for object = reshape(findall(fig), 1, [])
                if ~isvalid(object) || ~isprop(object, 'Type')
                    continue   % 色を持たない部品（図の中の空の置き場など）
                end
                switch object.Type
                    case 'uigridlayout'
                        object.BackgroundColor = new.background;
                    case 'uipanel'
                        object.BackgroundColor = new.background;
                        object.ForegroundColor = new.text;
                    case 'uitab'
                        % タブの見出しの地はどちらのモードでも明るいので、見出しの文字は黒のまま（中の地だけ変える）
                        object.BackgroundColor = new.background;
                    case 'uilabel'
                        object.FontColor = themeColor(object.FontColor, old, new);
                    case 'uicheckbox'
                        object.FontColor = new.text;
                    case 'uibutton'
                        if object.Tag ~= "primary"
                            object.BackgroundColor = new.button;
                            object.FontColor = new.text;
                        end
                    case 'uidropdown'
                        object.BackgroundColor = new.button;
                        object.FontColor = new.text;
                    case {'uieditfield', 'uinumericeditfield', 'uispinner', 'uitextarea', 'uilistbox'}
                        object.BackgroundColor = new.field;
                        object.FontColor = new.text;
                    case 'uitable'
                        object.BackgroundColor = [new.field; new.fieldAlt];
                        object.ForegroundColor = new.text;
                    case 'axes'
                        themeAxes(object, old, new);
                    case 'uihtml'
                        object.Data = struct("theme", app.Theme);
                end
            end
            % 色に依存する表の印（座標の単位の警告・各列の最良）を付け直す
            fillUnitTable(app);
            if ~isempty(app.Results)
                refreshResults(app);
            end
            if ~isempty(app.TargetRun)
                showTargetRun(app);   % 外挿の行の色・メッセージの色を新しい色の組にする
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
            set([c.export, c.saveChart, c.mapWafer, c.mapPlan, c.mapMethod, c.mapContent, c.mapMode, c.mapScale, ...
                c.mapMarkerSize, c.mapMarkerShape, c.mapEllipse, c.mapEllipseOnly, c.mapShotFrames, c.saveMap, c.analysisMethod, ...
                c.analysisGroup, ...
                c.analysisWafer, c.analyze, ...
                c.estimateScope, c.exportEstimates, c.scatterMethod, c.scatterGroup, c.scatterWafer, c.scatterColor, ...
                c.drawScatterButton, c.distributionMethod, c.distributionGroup, c.distributionWafer, c.distributionAxis, ...
                c.compareDistributionsButton, c.resumeRun, c.extendRun, c.mapScanFrames, c.mapRings, c.mapView, ...
                c.mapCompareValue, c.mapConditions, c.mapAddCondition, c.mapRemoveCondition, c.mapClearConditions, ...
                c.boxFactor, c.timingWafer, c.timingPlan, c.timingMethods, c.timingRepeats, c.measureTimingButton, ...
                c.compareLayoutMethod, c.compareLayoutXAxis, ...
                c.filterResults.apply, c.filterMap.apply], 'Enable', 'off');
            showFilter(app);
            app.Distribution = [];
            c.distributionTable.Data = {};
            c.jsTable.Data = {};
            for ax = c.distributionAxes
                cla(ax, 'reset');
                legend(ax, 'off');
                ax.Visible = 'off';
            end
            c.runStatus.Text = "";
            c.mapInfo.Text = "「3. 実行」で評価すると、ここに Wafer ごとの図が出ます。";
            c.resultSource.Text = '';
            c.resultControls.RowHeight{3} = 0;
            c.importEstimates.Enable = 'off';
            c.analysisNote.Text = c.analysisNote.UserData;
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

% ================= 画面の部品を作る小さな関数 =================
function item = label(parent, text, row, column)
item = uilabel(parent, 'Text', text, 'WordWrap', 'on');
if nargin >= 3
    place(item, row, column);
end
end

function heading(parent, text, row)
item = uilabel(parent, 'Text', text, 'FontWeight', 'bold', 'WordWrap', 'on');   % 欄が狭くても切れないように折り返す
place(item, row, [1, 2]);
end

function place(item, row, column)
item.Layout.Row = row;
item.Layout.Column = column;
end

function merged = mergeStruct(base, extra)
merged = base;
for name = string(fieldnames(extra)).'
    merged.(name) = extra.(name);
end
end

function value = ternary(condition, whenTrue, whenFalse)
if condition
    value = whenTrue;
else
    value = whenFalse;
end
end

function values = checkedValues(boxes)
% チェックの入った項目の UserData（文字列）を並べる
values = strings(1, 0);
for box = boxes(:).'
    if box.Value
        values(end + 1) = string(box.UserData); %#ok<AGROW>
    end
end
end

function closeDialog(dialog)
if ~isempty(dialog) && isvalid(dialog)
    close(dialog);
end
end

function value = isImportedResults(results)
% Excel から読み込んだ結果か（alignest.importResults は imported に読んだファイルを入れる）
value = isstruct(results) && isfield(results, "imported") && strlength(results.imported) > 0;
end

function state = onOff(condition)
state = matlab.lang.OnOffSwitchState(condition);
end

function used = usesGamKernels(c)
% GAM の形状関数にガウス過程回帰を1つでも選んでいるか（半径の項は説明変数に半径があるときだけ）
used = false;
if ~c.gam.Value
    return
end
for check = reshape(c.gamShapeChecks, 1, [])
    if check.Value && check.UserData.shape == "gp" && (check.UserData.term == "xy" || c.featureXYR.Value)
        used = true;
    end
end
end

function used = usesGamMaternNu(c)
used = any(string({c.gamKernelChecks([c.gamKernelChecks.Value]).UserData}) == "matern");
end

function used = usesMaternNu(c)
% GPR で ν を指定する Matérn（matern・ardmatern）を選んでいるか
used = c.gpr.Value && any(ismember(string(c.kernels.Value), ["matern", "ardmatern"]));
end

function control = spatialFactorDropdown(parent, callback)
control = uidropdown(parent, 'Items', {'質的変数なし', 'Backfitting', 'なし・Backfitting を比較'}, ...
    'ItemsData', {'none', 'backfit', 'both'}, 'ValueChangedFcn', callback, ...
    'Tooltip', '上で選んだ質的変数を固定効果として、空間成分と交互に推定します（Backfitting）。');
end

function selection = modeSelection(modes)
modes = unique(string(modes));
if numel(modes) == 2 && all(ismember(modes, ["none", "backfit"]))
    selection = 'both';
elseif isscalar(modes) && any(modes == ["none", "backfit"])
    selection = char(modes);
else
    error('alignest:spatialFactorMode', '質的変数の扱いは none・backfit のいずれか、または両方を選んでください。');
end
end

function modes = selectedModes(selection)
if string(selection) == "both"
    modes = ["none", "backfit"];
else
    modes = string(selection);
end
end

function [values, ok] = parseNumbers(text)
% 空白・カンマ区切りの数字を読む。空欄は空の並び。全角の数字・空白・カンマも読む（日本語入力のまま打てるように）
text = strtrim(regexprep(char(alignest.normalizeNumberText(strjoin(string(text), " "))), '[,、\s]+', ' '));
if isempty(text)
    values = zeros(1, 0);
    ok = true;
    return
end
values = str2double(split(string(text), " ")).';
ok = all(isfinite(values));
end

function value = round4(value)
% 表に出す数値（有効数字 4 桁）
value = round(value, 4, 'significant');
end

function limits = sharedMagnitudeLimits(first, second)
% 矢印の色（長さ）の上限：はじめの2つの図（計測値と推定値、または2つの補正残差）はそろえて比べられるようにし、
% 3つ目（残差・推定による変化）は値が小さいので自分の最大（0 = 自動）にする
magnitude = [hypot(first(:, 1), first(:, 2)); hypot(second(:, 1), second(:, 2))];
top = max(magnitude(isfinite(magnitude)), [], 'all');
if isempty(top)
    top = 0;
end
limits = [top, top, 0];
end

function positions = groupPositions(groups)
% 「20 Shot」のような列は Shot 数、「計測率 20%」は計測率を横軸の位置に、それ以外（手動）は 1, 2, … にする
[numbers, ~] = groupNumbers(groups);
if all(isfinite(numbers))
    positions = numbers;
else
    positions = 1:numel(groups);
end
end

function [numbers, axisLabel] = groupNumbers(groups)
% 学習パターンの列の名前から、横軸の数（Shot 数または計測率 [%]）と軸の名前を読む
groups = string(groups);
if all(startsWith(groups, "計測率 ") & endsWith(groups, "%"))
    numbers = str2double(extractBetween(groups, "計測率 ", "%"));
    axisLabel = "計測率 [%]";
else
    numbers = str2double(extractBefore(groups, " Shot"));
    axisLabel = "学習 Shot 数";
end
numbers = reshape(numbers, 1, []);
end

function control = rateField(parent, callback)
% 計測率 [%] の入力欄（0 より大きく 100 より小さい。並びの確かめは alignest.measurementRateList）
control = uieditfield(parent, 'numeric', 'Limits', [0, 100], 'ValueDisplayFormat', '%g', 'ValueChangedFcn', callback);
end

function [dxField, dyField] = formulaFields(parent, row, column, callback, tooltip)
% 補正の式（dx・dy）を入れる欄
grid = uigridlayout(parent, [2, 2], 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', 'fit'}, 'Padding', 0, ...
    'RowSpacing', 4);
place(grid, row, column);
label(grid, 'dx =', 1, 1);
dxField = uieditfield(grid, 'text', 'ValueChangedFcn', callback, 'Tooltip', tooltip);
place(dxField, 1, 2);
label(grid, 'dy =', 2, 1);
dyField = uieditfield(grid, 'text', 'ValueChangedFcn', callback, 'Tooltip', tooltip);
place(dyField, 2, 2);
end

function control = ellipseOnlyCheckbox(parent, callback)
% 共分散楕円を描くときに、矢印（ベクトル）を描かず楕円だけにする
control = uicheckbox(parent, 'Text', 'ベクトルを描かない（楕円だけ）', 'Value', false, 'ValueChangedFcn', callback, ...
    'Tooltip', ['共分散楕円を描くときに、矢印を消して楕円だけを描きます（楕円の中心は平均の矢印の先のまま）。' ...
    '楕円を描かない図（Wafer ごとの図・「なし」）では矢印を描きます。']);
end

function control = markerShapeDropdown(parent, callback)
% X・Y の色の図（ヒートマップ）の点の形
control = uidropdown(parent, 'Items', {'●', '■'}, 'ItemsData', {'o', 's'}, 'ValueChangedFcn', callback, ...
    'Tooltip', 'X・Y 成分の色の図（ヒートマップ）で、点を丸（●）で描くか四角（■）で描くか');
end

function control = ellipseDropdown(parent, callback)
control = uidropdown(parent, 'Items', {'なし', '1σ', '2σ', '3σ'}, 'ItemsData', {0, 1, 2, 3}, 'Value', 1, ...
    'Tooltip', ['平均の図（全 Wafer・LotID・EqpId・Operation）で、座標ごとの Wafer 間の X・Y のばらつきと相関から' ...
    '共分散楕円を、矢印の先に矢印と同じ倍率で描きます。楕円の色は X・Y の相関係数の絶対値 |r|' ...
    '（灰色 = 相関なし、紫 = 強い相関。図の右上の目盛り）です。'], 'ValueChangedFcn', callback);
end

function [keys, labels] = scatterColorChoices(source, settings)
% 散布図の色分けの選択肢（ファイルのその他の列も加える）。source は読み込んだデータ、または推定値の表
% （読み込んだ推定値の Excel。その他の列は「質的変数:<列名>」の列だけ）。settings は評価の設定（外周の半径）
outerMm = alignest.upgradeRadiusSettings(settings).evaluation.outerRadiusMm;
keys = ["none", "wafer", "lot", "eqp", "operation", "slot", "scan", "mark", "row", "outer", "quadrant"];
labels = ["なし（1色）", "Wafer", "LotID", "EqpId", "Operation", "Slot の偶奇（Wafer ID のハイフンの後の番号）", ...
    "Scan 方向", "Mark 番号", "Shot 行の奇偶", sprintf("外周・内側（Mark の半径 %g mm で分ける）", outerMm), ...
    "象限（Mark の位置、第1〜第4象限）"];
columns = strings(1, 0);
if istable(source)
    names = string(source.Properties.VariableNames);
    columns = extractAfter(names(startsWith(names, "質的変数:")), "質的変数:");
elseif ~isempty(source) && isfield(source, "attributeNames")
    columns = reshape(string(source.attributeNames), 1, []);
end
keys = [keys, "col:" + columns];
labels = [labels, "列：" + columns];
end

function text = priorityText(sampling)
% 読み込んだ優先順のファイルの要約
if ~isfield(sampling, "priorityShots") || isempty(sampling.priorityShots)
    text = "まだ読み込んでいません";
    return
end
levels = sampling.priorityLevels;
text = sprintf("%s：%d 行（必ず計測 %d、計測しない %d、順に使う %d）。先頭：%s", sampling.priorityFile, ...
    numel(sampling.priorityShots), nnz(levels == 1), nnz(levels == 0), nnz(~(levels == 0 | levels == 1)), ...
    strjoin(string(sampling.priorityShots(1:min(end, 8))), " "));
end

function setGroupItems(dropdown, options)
% Wafer ごと・平均の選択肢を入れる（UserData に選択肢の中身を持つ）
dropdown.Items = cellstr([options.label]);
dropdown.ItemsData = 1:numel(options);
dropdown.UserData = options;
dropdown.Value = 1;
end

function spinner = shotCountSpinner(parent, callback)
MAX_SHOT_COUNT = 10000;
spinner = uispinner(parent, 'Limits', [1, MAX_SHOT_COUNT], 'RoundFractionalValues', 'on', 'ValueChangedFcn', callback);
end

function lines = overlayLines(overlay)
% Shot 重ね合わせの Mark の位置ごとの平均・σ・相関（Shot・Wafer 間）の説明
average = overlay.average;
lines = strings(size(average.points, 1), 1);
for k = 1:numel(lines)
    deviation = sqrt(average.covariance(k, 1:2));
    correlation = average.covariance(k, 3) / prod(deviation);
    lines(k) = sprintf("M%g（%.3f, %.3f）：平均 X %+.2f・Y %+.2f nm、σ X %.2f・Y %.2f nm、相関 %+.2f（%d 点）", ...
        overlay.markLabels(k), average.points(k, :), average.mean(k, :), deviation, correlation, ...
        min(average.count(k, :)));
end
end

function text = previewList(values, maxCount)
% 並びを「10, 15, 20」のように出す。多いときは途中を「…」で省く
values = string(values);
if numel(values) > maxCount
    values = [values(1:maxCount - 1), "…", values(end)];
end
text = strjoin(values, ", ");
end

function options = dataOptions(data)
% 前処理を決める項目（設定の data、前処理の結果、画面の値を同じ形にそろえて比べる）
options = struct("validRadiusMm", double(data.validRadiusMm), ...
    "coordinateUnits", alignest.coordinateUnits(data.coordinateUnits), ...
    "excludeZeroMeasurements", logical(data.excludeZeroMeasurements), ...
    "excludeUnmeasuredRecords", logical(data.excludeUnmeasuredRecords), ...
    "directionRule", string(data.directionRule), "invertDirection", logical(data.invertDirection), ...
    "directionOverrideShots", reshape(double(fieldOr(data, "directionOverrideShots", zeros(1, 0))), 1, []), ...
    "directionOverrideValues", reshape(double(fieldOr(data, "directionOverrideValues", zeros(1, 0))), 1, []), ...
    "coordinateMode", string(fieldOr(data, "coordinateMode", "shotMark")), ...
    "valueColumn", string(fieldOr(data, "valueColumn", "")));
end

function value = fieldOr(data, name, fallback)
% 以前の設定・データに無い項目は fallback
value = fallback;
if isfield(data, name)
    value = data.(name);
end
end

function text = displayUnit(units)
text = replace(string(units), "um", "µm");
end

function text = numberText(value, format)
if nargin < 2
    format = '%.6g';
end
if isnan(value)
    text = '—';
else
    text = sprintf(format, value);
end
end

function text = pValueText(p)
% p 値：小さい値は指数で出す
if isnan(p)
    text = '—';
elseif p < 1e-4
    text = sprintf('%.1e', p);
else
    text = sprintf('%.4f', p);
end
end

function text = judgementWithNote(judgement, note)
% 判定とメモを1つの欄にまとめる（判定できないときはメモだけ）
if judgement == "—" && note ~= ""
    text = note;
elseif note ~= ""
    text = judgement + "（" + note + "）";
else
    text = judgement;
end
end

function text = listOrNone(values)
if isempty(values)
    text = "（列なし・空）";
else
    text = strjoin(string(values), "、");
end
end

function text = shotSizeText(rangeMm)
% rangeMm は [最小の幅, 最小の高さ; 最大の幅, 最大の高さ]
if isequal(rangeMm(1, :), rangeMm(2, :))
    text = sprintf("%.3f × %.3f mm", rangeMm(1, :));
else
    text = sprintf("%.3f × %.3f 〜 %.3f × %.3f mm（Wafer によって違う）", rangeMm(1, :), rangeMm(2, :));
end
end

function text = directionText(summary)
switch summary.directionSource
    case "なし"
        text = "なし（質的変数・制約に使わない。「Scan 方向が無い行に付ける値」で付けられます）";
    otherwise
        text = summary.directionSource + "（質的変数・制約に使う）";
end
end

function [centers, sizeMm] = shotFrameData(unit, show)
% Wafer マップに Shot の枠を描くための中心と大きさ（描かないときは空）
if show
    centers = [unit.shots.Xmm, unit.shots.Ymm];
    sizeMm = unit.shotSizeMm;
else
    centers = zeros(0, 2);
    sizeMm = [NaN, NaN];
end
end

function limit = colorLimitOf(values)
limit = max(abs(values(isfinite(values))), [], 'all');
if isempty(limit) || limit <= 0
    limit = 1;
end
end

function halfWidth = errorBarHalfWidth(results, metric, kind)
% エラーバーの片側の長さ（手法 × 学習パターンの列）。なしなら空
halfWidth = [];
if kind == "none"
    return
end
[deviation, count] = alignest.waferSpread(results, metric);
halfWidth = deviation;
if kind == "ci"
    halfWidth = 1.96 * deviation ./ sqrt(count);
end
end

function text = errorBarCaption(kind)
switch kind
    case "sd"
        text = "、エラーバーは ±1σ（Wafer 間）";
    case "ci"
        text = "、エラーバーは平均の 95% 区間";
    otherwise
        text = "";
end
end

function text = statisticLabel(statistic)
[names, labels] = alignest.statisticNames();
text = labels(names == statistic);
end

function continueRun = reportCollectProgress(dialog, done, total)
continueRun = true;
if isempty(dialog) || ~isvalid(dialog)
    return
end
dialog.Value = done / total;
dialog.Message = sprintf('%d / %d 組み合わせ（Wafer × 学習パターン × 手法）', done, total);
drawnow limitrate;
continueRun = ~dialog.CancelRequested;
end

function text = durationText(seconds)
if ~isfinite(seconds)
    text = "—";
elseif seconds < 60
    text = sprintf("%.0f 秒", max(seconds, 1));
elseif seconds < 3600
    text = sprintf("%.0f 分", seconds / 60);
else
    text = sprintf("%.1f 時間", seconds / 3600);
end
end

function cache = estimateCache(results)
% 評価で求めた評価点の推定値（results.pointEstimates）を、マップ・散布図・推定値の表で使い回す記憶に入れる
% （キーは 'Wafer|学習パターン|手法' の番号。推定をやり直さずに描ける）
cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
if ~isfield(results, "pointEstimates")
    return
end
table_ = results.table;
for k = 1:height(table_)
    if ~isempty(results.pointEstimates{k})
        cache(sprintf('%d|%d|%d', table_.unitIndex(k), table_.planIndex(k), table_.methodIndex(k))) = ...
            results.pointEstimates{k};
    end
end
end

function filter = readFilterControls(controls)
% 評価点の絞り込みの欄（buildFilterControls）から条件を作る
filter = alignest.defaultPointFilter();
filter.radiusMinMm = controls.radiusMin.Value;
filter.radiusMaxMm = controls.radiusMax.Value;
filter.shotMode = string(controls.shotMode.Value);
[values, ok] = parseNumbers(controls.shotNos.Value);
if ~ok || any(values ~= round(values))
    error('alignest:pointFilter', 'shotNo は整数を空白またはカンマで区切って入れてください。');
end
filter.shotNos = reshape(unique(values), 1, []);
filter.scan = controls.scan.Value;
filter.outer = string(controls.outer.Value);
end

function validateFilter(filter)
% 絞り込みの条件を確かめる（範囲が逆・shotNo が空など）
if ~(filter.radiusMinMm >= 0) || ~(filter.radiusMaxMm > filter.radiusMinMm)
    error('alignest:pointFilter', '半径は 0 以上で、下限 < 上限 にしてください（上限なしは Inf）。');
end
if filter.shotMode ~= "all" && isempty(filter.shotNos)
    error('alignest:pointFilter', 'shotNo で絞り込むときは、右の欄に shotNo を入れてください。');
end
end

function edges = activeZoneEdges(settings)
% 同心円の制約の区切り [mm]（I 最適・ランダムで使うときだけ。手動・ファイルの優先順では制約を使わないので空）
edges = zeros(1, 0);
if any(ismember(string(settings.sampling.method), ["ioptimal", "doptimal", "random"]))
    edges = alignest.zoneEdgesMm(settings.sampling, settings.data.waferRadiusMm);
end
end

function [nRows, nColumns] = tileShape(panel, nPanels)
% 図を並べる段と列の数：枠の幅・高さに合わせ、1枚（Wafer の正方形の図）が最も大きくなる並べ方にする
% （枠の大きさがまだ決まっていないときは、3枚までは横に、4枚以上は2段に並べる）
MIN_PANEL_SIZE = 50;
position = panel.Position;
nRows = 1 + (nPanels > 3);
nColumns = ceil(nPanels / nRows);
if numel(position) < 4 || position(3) < MIN_PANEL_SIZE || position(4) < MIN_PANEL_SIZE
    return
end
best = 0;
for rows = 1:nPanels
    columns = ceil(nPanels / rows);
    side = min(position(3) / columns, position(4) / rows);
    if side > best
        best = side;
        nRows = rows;
        nColumns = columns;
    end
end
end

function rows = rowsOf(table_, option, planLabel, methodIndex)
% マップの条件（Wafer・平均 × 学習パターン × 手法）の、結果の表の行
rows = table_(ismember(table_.unitIndex, option.unitIndex) & table_.plan == planLabel & ...
    table_.methodIndex == methodIndex, :);
end

function cells = targetCells(targets)
% 推定する点（alignest.targetTemplate の形）を、画面の表の文字の欄にする（NaN は空欄）
columns = {targets.name, targets.Xmm, targets.Ymm, targets.markXmm, targets.markYmm, targets.markNo, targets.shotNo, ...
    targets.direction};
cells = cell(height(targets), numel(columns));
for k = 1:numel(columns)
    text = string(columns{k});
    text(ismissing(text)) = "";
    cells(:, k) = cellstr(text);
end
end

function messages = targetMessages(results, estimates)
% 画面に出すメッセージ。Wafer が1枚ならその結果のまま、複数なら外挿の数をまとめ、ほかの注意は重ねずに並べる
if isscalar(results)
    messages = results{1}.messages;
    return
end
n = height(estimates);
nOutside = nnz(estimates.extrapolated);
if nOutside > 0
    messages = sprintf(['⚠ 外挿：%d 枚の Wafer の計 %d / %d 点が学習点の範囲（学習点を囲む凸包）の外にあります' ...
        '（最大 %.1f mm 外）。学習点から離れるほど推定値は信頼できません（表の「外挿」、図の × 印）。'], numel(results), ...
        nOutside, n, max(estimates.outsideMm));
else
    messages = sprintf('外挿なし：%d 枚の Wafer の計 %d 点すべてが学習点の範囲（学習点を囲む凸包）の中です。', ...
        numel(results), n);
end
others = strings(0, 1);
for k = 1:numel(results)
    others = [others; results{k}.messages(2:end)]; %#ok<AGROW>
end
messages = [string(messages); unique(others, 'stable')];
end

function setModeChoices(dropdown, spec)
% 図の表示（ベクトル・X・Y）の選択肢。1変数は色（値の名前）だけ
if spec.scalar
    setChoices(dropdown, spec.name + "（色）", {'X'});
elseif ~isequal(dropdown.ItemsData, {'vector', 'X', 'Y'})
    setChoices(dropdown, ["ベクトル（矢印）", "X（色）", "Y（色）"], {'vector', 'X', 'Y'});
end
end

function range = valueRange(values)
% 1変数の値を色で描く範囲 [最小, 最大]（値が無ければ NaN：0 を中心にした色の範囲になる）
values = values(isfinite(values));
range = [NaN, NaN];
if ~isempty(values)
    range = [min(values), max(values)];
end
end

function limit = absoluteLimit(values)
% 0 を中心にした色の範囲 ±limit（残差など）
limit = max(abs(values(isfinite(values))), [], 'all');
if isempty(limit) || limit <= 0
    limit = 1;
end
end

function text = onOffText(value)
text = "しない";
if value
    text = "する";
end
end

function setChoices(dropdown, items, itemsData)
% ドロップダウンの選択肢を変える（前に選んでいた値が残っていれば、そのまま選ぶ）
previous = dropdown.Value;
dropdown.Items = cellstr(items);
dropdown.ItemsData = itemsData;
if any(cellfun(@(value) isequal(value, previous), itemsData))
    dropdown.Value = previous;
end
end

function palette = themePalette(mode)
% 画面の色の組（ライトモードは MATLAB の画面の既定の色、ダークモードは暗い背景に明るい文字）
if string(mode) == "dark"
    palette = struct("background", [0.13, 0.14, 0.16], "text", [0.92, 0.92, 0.93], "muted", [0.66, 0.67, 0.70], ...
        "error", [1.0, 0.48, 0.45], "accent", [0.45, 0.70, 1.0], "best", [0.42, 0.36, 0.10], "warning", [0.45, 0.24, 0.16], ...
        "field", [0.20, 0.21, 0.24], "fieldAlt", [0.17, 0.18, 0.21], "button", [0.25, 0.26, 0.30], ...
        "axes", [0.10, 0.11, 0.13], "axisLine", [0.82, 0.82, 0.84], "grid", [0.55, 0.55, 0.58]);
else
    palette = struct("background", [0.94, 0.94, 0.94], "text", [0, 0, 0], "muted", [0.35, 0.35, 0.35], ...
        "error", [0.72, 0.11, 0.11], "accent", [0.0, 0.36, 0.67], "best", [1.0, 0.93, 0.70], "warning", [1.0, 0.86, 0.80], ...
        "field", [1, 1, 1], "fieldAlt", [0.94, 0.94, 0.94], "button", [0.96, 0.96, 0.96], ...
        "axes", [1, 1, 1], "axisLine", [0.15, 0.15, 0.15], "grid", [0.15, 0.15, 0.15]);
end
end

function color = themeColor(current, old, new)
% 文字の色を、前の色の組での役割（エラー・補足・強調・ふつう）のまま新しい色の組の色にする
near = @(a, b) isnumeric(a) && numel(a) == 3 && all(abs(a(:).' - b) < 0.03);
if near(current, old.error)
    color = new.error;
elseif near(current, old.muted)
    color = new.muted;
elseif near(current, old.accent)
    color = new.accent;
else
    color = new.text;
end
end

function themeAxes(ax, old, new)
% 描いてある図の色を変える（軸・題名・凡例・色の目盛り・文字。塗りの上に書いた文字（Tag = keepColor）は変えない）
if ~(ischar(ax.Color) || isstring(ax.Color))
    ax.Color = new.axes;
end
set(ax, 'XColor', new.axisLine, 'YColor', new.axisLine, 'ZColor', new.axisLine, 'GridColor', new.grid, ...
    'MinorGridColor', new.grid);
set([ax.Title, ax.XLabel, ax.YLabel], 'Color', new.text);
if ~isempty(ax.Legend) && isvalid(ax.Legend)
    ax.Legend.TextColor = new.text;
    ax.Legend.EdgeColor = new.grid;
    if ~(ischar(ax.Legend.Color) || isstring(ax.Legend.Color))
        ax.Legend.Color = new.axes;
    end
end
if ~isempty(ax.Colorbar) && isvalid(ax.Colorbar)
    ax.Colorbar.Color = new.axisLine;
    set([ax.Colorbar.Title, ax.Colorbar.Label], 'Color', new.text);
end
for item = reshape(findall(ax, 'Type', 'text'), 1, [])
    if item.Tag ~= "keepColor" && isnumeric(item.Color) && all(abs(item.Color - old.text) < 0.03)
        item.Color = new.text;
    end
end
for item = reshape(findall(ax, 'Tag', 'foreground'), 1, [])
    item.Color = new.text;   % 長さの目安の矢印など、背景と反対の色で描くもの
end
end
