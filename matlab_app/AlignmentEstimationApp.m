classdef AlignmentEstimationApp < handle
    %ALIGNMENTESTIMATIONAPP アライメント計測値の面内推定を、実データ（Excel）で比べる画面。
    %   app = AlignmentEstimationApp();       画面を開く
    %   app = AlignmentEstimationApp(false);  画面を出さずに作る（自動テスト用）
    %   流れ：1. データの読み込み（列の対応・座標の単位・Wafer マップ・Shot レイアウト） → 2. 評価の設定 → 3. 実行
    %         → 4. 結果一覧（表・グラフ・基準の手法との比較・推定値と誤差の分布） → 5. Waferごとのマップ
    %   計算は +alignest パッケージ（MATLAB 本体だけで動く）。画面はその呼び出しと表示だけを受け持つ。

    properties (Constant, Access = private)
        APP_TITLE = "アライメント計測値の面内推定 検証ツール"
        FONT_SIZE = 16
        AXES_FONT_SIZE = 13
        FIGURE_SIZE = [1440, 900]          % 画面がこれより小さいときは画面に合わせて縮める
        SCREEN_MARGIN = 40
        PRIMARY_COLOR = [0.0, 0.36, 0.67]
        ERROR_COLOR = [0.72, 0.11, 0.11]
        BEST_COLOR = [1.0, 0.93, 0.70]
        NONE_LABEL = "（なし）"
        MAX_CURVES = 8
        METHOD_COLUMN_WIDTH = 440        % 結果の表の手法の列の幅 [px]（最も長い名前が収まる幅）
        VALUE_COLUMN_WIDTH = 90          % 結果の表の数値の列の幅 [px]
        PROGRESS_INTERVAL_SECONDS = 0.2
        RESIDUAL_COLOR = [0.75, 0.25, 0.10]
        % 1回の当てはめ（X・Y）の計算時間の目安 [秒]（M1 Mac・約150 Shot の Wafer で測った値を切り上げ）
        % RBF は候補数からの概算。TPS・Kriging の Backfitting は反復上限を掛けた保守的な目安。
        SECONDS_PER_FIT = struct("GPR", 0.1, "TPS", 0.03, "RBF", 0.1, "OK", 0.05, "UK", 0.05, "GAM", 0.1, "XY", 0.01, "RT", 0.02)
        SECONDS_PER_IOPTIMAL_PLAN = 8   % I 最適の計画1つ（同じ配置の Wafer では1回だけ計算する）
        DEFAULT_MARKER_SIZE = 30        % 色で描く Wafer マップの点の大きさの初期値（scatter の面積 [ポイント²]）
        MARKER_SIZE_LIMITS = [1, 400]
        UNIT_CHOICES = {'mm', 'µm', 'nm', 'm'}  % 座標の入力単位の選択肢（µm は内部では um として扱う）
        TABLE_FONT_SIZE = 13            % 列の多い表（座標の単位・検定の結果）の文字の大きさ
        LIST_PREVIEW_COUNT = 12         % 学習 Shot 数の並びを画面に出す数（多いときは途中を省く）
        EXCEL_MAX_DATA_ROWS = 1048575   % Excel の最大行数から見出しの1行を除いた数
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
    end

    methods
        function app = AlignmentEstimationApp(visible)
            if nargin < 1
                visible = true;
            end
            app.Settings = alignest.defaultSettings();
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
            buildDataTab(app);
            buildSettingsTab(app);
            buildRunTab(app);
            buildResultsTab(app);
            buildMapTab(app);
            set(findall(app.Figure, '-property', 'FontSize'), 'FontSize', app.FONT_SIZE);
            set(findall(app.Figure, 'Type', 'axes'), 'FontSize', app.AXES_FONT_SIZE);
            set([app.Controls.unitTable, app.Controls.normalityTable, app.Controls.anovaTable], 'FontSize', app.TABLE_FONT_SIZE);
            settingsToControls(app);
            refreshRunSummary(app);
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
            fillMappingTable(app, alignest.guessColumnMapping(raw.Properties.VariableNames));
            fillUnitTable(app);
            c.mappingStatus.Text = sprintf(['%d 行・%d 列を読みました。「ファイルの列」の対応と、右の「座標の単位」を' ...
                '確かめてから、「この対応で読み込む」を押してください。'], height(raw), width(raw));
            c.mappingStatus.FontColor = [0, 0, 0];
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
                invertDirection=options.invertDirection);
            app.AppliedMapping = mapping;
            app.Settings.data = mergeStruct(app.Settings.data, options);
            summary = app.Data.summary;
            lines = [sprintf("Wafer（評価の単位）：%d 枚", summary.nUnits); ...
                "工程（Operation）：" + listOrNone(summary.operations); ...
                "装置（EqpId）：" + listOrNone(summary.eqpIds); ...
                sprintf("Shot 数：%d〜%d／Wafer、Mark 数：%d〜%d／Wafer", summary.nShotsRange, summary.nMarksRange); ...
                "Shot の大きさ（中心の間隔から推定）：" + shotSizeText(summary.shotSizeRangeMm); ...
                sprintf("Mark 番号の水準：%s", strjoin(string(summary.markLevels), "、")); ...
                "Scan 方向（Direction）：" + directionText(summary); ...
                summary.messages(:)];
            app.Controls.summary.Value = cellstr(lines);
            labels = string({app.Data.units.label});
            for dropdown = [app.Controls.previewWafer, app.Controls.layoutWafer]
                dropdown.Items = cellstr(labels);
                dropdown.ItemsData = 1:numel(labels);
                dropdown.Value = 1;
            end
            app.Controls.mappingStatus.Text = sprintf(['読み込みました（%d 枚）。上の「Wafer マップ」「Shot レイアウト」で' ...
                'データを確かめ、「2. 評価の設定」で比べ方を決めてください。'], summary.nUnits);
            app.Controls.mappingStatus.FontColor = [0, 0, 0];
            drawPreview(app);
            drawLayout(app);
            refreshRunSummary(app);
        end

        function setSettings(app, settings)
            %SETSETTINGS 設定を画面に反映する（設定ファイルの読み込みと同じ）。
            %   以前の設定に無い項目は初期値にする。学習 Shot 数は並び（nShots）と開始・終了・刻みをそろえる。
            settings.methods = alignest.completeMethodSettings(settings.methods);
            defaults = alignest.defaultSettings();
            for group = ["data", "factors", "sampling", "evaluation"]
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

        function results = runEvaluationNow(app, showProgress)
            %RUNEVALUATIONNOW 評価を実行して結果の画面を更新する。
            if nargin < 2
                showProgress = true;
            end
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
            c = app.Controls;
            c.run.Enable = 'off';
            restore = onCleanup(@() set(c.run, 'Enable', 'on'));
            c.runStatus.Text = "計算中…";
            c.runStatus.FontColor = [0, 0, 0];
            dialog = [];
            if showProgress
                dialog = uiprogressdlg(app.Figure, 'Title', '評価中', 'Message', '学習パターンを作っています…', ...
                    'Cancelable', 'on', 'CancelText', '止める', 'ShowPercentage', 'on');
            end
            timer = tic;
            lastUpdate = -Inf;
            progressFcn = @(done, total, message) reportProgress(done, total, message);
            try
                results = alignest.runEvaluation(app.Data, app.Settings, progressFcn);
            catch err
                closeDialog(dialog);
                c.runStatus.Text = "⚠ 評価を実行できませんでした。";
                c.runStatus.FontColor = app.ERROR_COLOR;
                rethrow(err);
            end
            closeDialog(dialog);
            app.Results = results;
            app.MapCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
            nFailed = nnz(results.table.note ~= "");
            status = sprintf("%s：%d 件を %.0f 秒で計算しました。", ternary(results.cancelled, "途中で止めました", "完了"), ...
                height(results.table), results.elapsedSeconds);
            if nFailed > 0
                status = status + sprintf(" うち %d 件は推定できませんでした（理由は下の記録）。", nFailed);
            end
            c.runStatus.Text = status;
            c.log.Value = cellstr([status; results.log(:)]);
            refreshResultControls(app);
            app.TabGroup.SelectedTab = app.Tabs.results;

            function continueRun = reportProgress(done, total, message)
                continueRun = true;
                if isempty(dialog)
                    return
                end
                elapsed = toc(timer);
                if elapsed - lastUpdate < app.PROGRESS_INTERVAL_SECONDS && done < total
                    continueRun = ~dialog.CancelRequested;
                    return
                end
                lastUpdate = elapsed;
                remaining = elapsed / done * (total - done);
                dialog.Value = done / total;
                dialog.Message = sprintf('%d / %d 件（残り 約 %s）\n%s', done, total, durationText(remaining), message);
                drawnow;
                continueRun = ~dialog.CancelRequested;
            end
        end

        function exportResultsTo(app, filePath)
            %EXPORTRESULTSTO 結果を Excel に書き出す。
            if isempty(app.Results)
                error('alignest:noResults', '先に「3. 実行」で評価してください。');
            end
            alignest.exportResults(app.Results, filePath, app.FilePath);
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
                status.FontColor = [0, 0, 0];
            elseif all(checks.ok)
                status.Text = "すべての座標の大きさが目安の範囲内なので、単位は変えていません。";
                status.FontColor = [0, 0, 0];
            else
                status.Text = "⚠ 目安に合う単位が見つからない列があります。列の対応が正しいか確かめてください。";
                status.FontColor = app.ERROR_COLOR;
            end
        end

        function analysis = analyzeResiduals(app, methodIndex, group, unitIndex)
            %ANALYZERESIDUALS 選んだ手法・学習パターンの列・Wafer（0 = すべて）の評価点の残差を、
            %   ヒストグラム・正規性検定・質的変数の ANOVA で調べて「推定値と誤差の分布」に出す。
            if isempty(app.Results)
                error('alignest:noResults', '先に「3. 実行」で評価してください。');
            end
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
        end

        function exportEstimatesTo(app, filePath, scope)
            %EXPORTESTIMATESTO 推定値（評価点ごとの計測値・推定値・残差）と残差の検定結果を Excel に書き出す。
            %   scope = "selected"：「推定値と誤差の分布」で選んだ手法・学習パターン・Wafer
            %           "all"     ：すべての手法・学習パターン・Wafer（推定をやり直すので時間がかかる）
            if isempty(app.Results)
                error('alignest:noResults', '先に「3. 実行」で評価してください。');
            end
            if nargin < 3
                scope = string(app.Controls.estimateScope.Value);
            end
            results = app.Results;
            if scope == "all"
                selection = struct("methodIndex", 1:numel(results.methods), "groups", results.groups, ...
                    "unitIndex", 1:numel(results.unitLabels));
                cache = [];  % すべての組み合わせを画面の記憶に残すと大きくなるので、使い回さない
                scopeText = "すべての手法・学習パターン・Wafer";
            else
                selection = analysisSelection(app);
                cache = app.MapCache;
                scopeText = "選んだ手法・学習パターン・Wafer";
            end
            [estimates, messages] = collectWithProgress(app, selection, cache, app.EXCEL_MAX_DATA_ROWS, ...
                "推定値を計算しています");
            analysis = alignest.residualAnalysis(estimates);
            notes = ["読み込んだファイル", app.FilePath; "書き出した範囲", scopeText; ...
                "手法", strjoin(string({results.methods(selection.methodIndex).label}), "、"); ...
                "学習パターンの列", strjoin(selection.groups, "、"); ...
                "Wafer", strjoin(results.unitLabels(selection.unitIndex), "、")];
            if ~isempty(messages)
                notes = [notes; [repmat("推定できなかった組み合わせ", numel(messages), 1), messages(:)]];
            end
            alignest.exportEstimates(estimates, analysis, filePath, notes);
        end

        function showMap(app, unitIndex, planLabel, methodIndex, displayMode)
            %SHOWMAP 選んだ Wafer・学習パターン・手法の計測値・推定値・残差を描く。
            c = app.Controls;
            if nargin >= 2
                c.mapWafer.Value = unitIndex;
                c.mapPlan.Value = char(planLabel);
                c.mapMethod.Value = methodIndex;
            end
            if nargin >= 5
                c.mapMode.Value = char(displayMode);
            end
            drawMap(app);
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
            fileGrid = uigridlayout(filePanel, [5, 4], 'ColumnWidth', {'fit', '1x', 260, 300}, ...
                'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit'}, 'Padding', 10);
            help = uilabel(fileGrid, 'WordWrap', 'on', 'Text', ['Excel（.xlsx）または CSV。1行目に項目名、2行目からデータ。' ...
                '項目名がアライメント計測テーブルの標準（Operation, EqpId, Wafer, DateTime, shotNo, Direction, Xmm, Ymm, ' ...
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
            directionHelp.FontColor = [0.35, 0.35, 0.35];

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
            unitHelp.FontColor = [0.2, 0.2, 0.2];
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
            previewControls = uigridlayout(previewGrid, [1, 6], 'ColumnWidth', {'fit', 260, 'fit', 90, 'fit', '1x'}, ...
                'Padding', 0);
            label(previewControls, '表示する Wafer', 1, 1);
            c.previewWafer = uidropdown(previewControls, 'Items', {'—'}, 'ValueChangedFcn', @(~, ~) app.drawPreview());
            place(c.previewWafer, 1, 2);
            label(previewControls, '色の点の大きさ', 1, 3);
            c.previewMarkerSize = markerSizeSpinner(app, previewControls, @(~, ~) app.drawPreview());
            place(c.previewMarkerSize, 1, 4);
            c.previewShotFrames = uicheckbox(previewControls, 'Text', 'Shot の枠を表示', 'Value', true, ...
                'ValueChangedFcn', @(~, ~) app.drawPreview());
            place(c.previewShotFrames, 1, 5);
            c.previewInfo = uilabel(previewControls, 'WordWrap', 'on', 'Text', '');
            place(c.previewInfo, 1, 6);
            c.previewPanel = uipanel(previewGrid, 'BorderType', 'none');
            previewAxesGrid = uigridlayout(c.previewPanel, [1, 3], 'Padding', 0, 'ColumnSpacing', 8);
            c.previewAxes = [uiaxes(previewAxesGrid), uiaxes(previewAxesGrid), uiaxes(previewAxesGrid)];
            set(c.previewAxes, 'Visible', 'off');  % 読み込むまでは空の枠を出さない

            c.layoutTab = uitab(c.dataTabs, 'Title', 'Shot レイアウト');
            layoutGrid = uigridlayout(c.layoutTab, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 8, 'RowSpacing', 8);
            layoutControls = uigridlayout(layoutGrid, [1, 3], 'ColumnWidth', {'fit', 260, '1x'}, 'Padding', 0);
            label(layoutControls, '表示する Wafer', 1, 1);
            c.layoutWafer = uidropdown(layoutControls, 'Items', {'—'}, 'ValueChangedFcn', @(~, ~) app.drawLayout());
            place(c.layoutWafer, 1, 2);
            c.layoutInfo = uilabel(layoutControls, 'WordWrap', 'on', 'Text', '');
            place(c.layoutInfo, 1, 3);
            c.layoutPanel = uipanel(layoutGrid, 'BorderType', 'none');
            layoutAxesGrid = uigridlayout(c.layoutPanel, [1, 2], 'ColumnWidth', {'1.25x', '1x'}, 'Padding', 0, ...
                'ColumnSpacing', 12);
            c.layoutAxes = [uiaxes(layoutAxesGrid), uiaxes(layoutAxesGrid)];
            set(c.layoutAxes, 'Visible', 'off');
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
                app.Controls.mappingStatus.FontColor = app.ERROR_COLOR;
            end
        end

        function fillMappingTable(app, mapping)
            columns = alignest.standardColumns();
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
                status.FontColor = [0, 0, 0];
            else
                addStyle(unitTable, uistyle('FontColor', app.ERROR_COLOR, 'FontWeight', 'bold'), 'cell', ...
                    [warnings, repmat(6, numel(warnings), 1)]);
                status.Text = "⚠ 大きさが目安の外の列があります。入力の単位を確かめてください（「値の大きさから単位を推定」で選べます）。";
                status.FontColor = app.ERROR_COLOR;
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
                "directionRule", string(c.directionRule.Value), "invertDirection", c.invertDirection.Value));
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
            app.Controls.summary.Value = {''};
            clearDataMaps(app);
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
            invalidatePreparedData(app);
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
            unit = app.Data.units(c.previewWafer.Value);
            marks = unit.marks;
            values = [marks.measX, marks.measY];
            values(~marks.validX, 1) = NaN;
            values(~marks.validY, 2) = NaN;
            points = [marks.x, marks.y];
            [centers, sizeMm] = shotFrameData(unit, c.previewShotFrames.Value);
            limit = colorLimitOf(values);
            radius = app.Settings.data.waferRadiusMm;
            common = {'waferRadiusMm', radius, 'shotCenters', centers, 'shotSizeMm', sizeMm, 'showLegend', false};
            % name=value の書き方は最後に置く決まりなので、共通の指定（common）を先に渡す
            alignest.plot.waferMap(c.previewAxes(1), points, values, common{:}, ...
                scaleMmPerNm=alignest.plot.vectorScale(values), titleText="計測値（ベクトル）");
            alignest.plot.waferMap(c.previewAxes(2), points, values, common{:}, mode="X", colorLimit=limit, ...
                markerSize=c.previewMarkerSize.Value, titleText="X 成分（色）");
            alignest.plot.waferMap(c.previewAxes(3), points, values, common{:}, mode="Y", colorLimit=limit, ...
                markerSize=c.previewMarkerSize.Value, titleText="Y 成分（色）");
            set(c.previewAxes, 'Visible', 'on', 'FontSize', app.AXES_FONT_SIZE);
            c.previewInfo.Text = sprintf("%s：%d 点。点線は半径 %g mm%s。色の範囲は X・Y 共通で ±%.2f nm。", unit.label, ...
                numel(marks.x), radius, ternary(c.previewShotFrames.Value, "、灰色の枠は Shot", ""), limit);
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
            c.layoutInfo.Text = sprintf(['%s：%d Shot・%d Mark、Shot の大きさ %.3f × %.3f mm、Scan 方向 %s。' ...
                '左の数字は shotNo、右は Shot 中心から見た Mark の位置（M の後が markNo）。'], unit.label, ...
                numel(unit.shots.Xmm), numel(unit.marks.x), unit.shotSizeMm, ...
                ternary(unit.hasDirection, "あり（S1・S2 で表示）", "なし"));
        end

        function clearDataMaps(app)
            c = app.Controls;
            if ~isfield(c, 'layoutAxes')
                return
            end
            for ax = [c.previewAxes, c.layoutAxes]
                cla(ax, 'reset');
                colorbar(ax, 'off');
                legend(ax, 'off');
                ax.Visible = 'off';
            end
            c.previewInfo.Text = '';
            c.layoutInfo.Text = '';
        end

        % ================= 2. 評価の設定 =================
        function buildSettingsTab(app)
            grid = uigridlayout(app.Tabs.settings, [2, 2], 'RowHeight', {'1x', 'fit'}, ...
                'ColumnWidth', {'1x', '1.35x'}, 'Padding', 12, 'ColumnSpacing', 12);
            onChange = @(~, ~) app.onSettingsChanged();

            samplingPanel = uipanel(grid, 'Title', '学習に使う Shot（この Shot の計測値で、残りの Shot を推定する）');
            s = uigridlayout(samplingPanel, [26, 2], 'RowHeight', repmat({'fit'}, 1, 26), 'ColumnWidth', {'1x', '1x'}, ...
                'Padding', 10, 'RowSpacing', 6, 'Scrollable', 'on');
            label(s, '選び方', 1, [1, 2]);
            c.samplingMethod = uidropdown(s, 'Items', {'制約付き I 最適（前回の評価と同じ）', '制約つきランダム', '手動で指定'}, ...
                'ItemsData', {'ioptimal', 'random', 'manual'}, 'ValueChangedFcn', onChange);
            place(c.samplingMethod, 2, [1, 2]);
            label(s, '学習 Shot 数（開始から終了まで、刻みごとに増やして比べる）', 3, [1, 2]);
            sweep = uigridlayout(s, [2, 3], 'RowHeight', {'fit', 'fit'}, 'ColumnWidth', {'1x', '1x', '1x'}, ...
                'Padding', 0, 'RowSpacing', 2);
            place(sweep, 4, [1, 2]);
            label(sweep, '開始', 1, 1);
            label(sweep, '終了', 1, 2);
            label(sweep, '刻み（スイープ幅）', 1, 3);
            c.nShotsStart = shotCountSpinner(sweep, onChange);
            place(c.nShotsStart, 2, 1);
            c.nShotsEnd = shotCountSpinner(sweep, onChange);
            place(c.nShotsEnd, 2, 2);
            c.nShotsStep = shotCountSpinner(sweep, onChange);
            place(c.nShotsStep, 2, 3);
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
            label(s, '手動で指定する Shot（1行に1パターン。shotNo を空白またはカンマで区切る）', 9, [1, 2]);
            c.manualPlans = uitextarea(s, 'ValueChangedFcn', onChange);
            place(c.manualPlans, 10, [1, 2]);
            s.RowHeight{10} = 90;
            c.manualError = errorLabel(app, s, 11, [1, 2]);
            heading(s, '制約（I 最適・ランダム）', 12);
            label(s, '同心円の区切り（Wafer 半径に対する比、空白区切り）', 13, [1, 2]);
            c.zoneEdges = uieditfield(s, 'text', 'ValueChangedFcn', onChange);
            place(c.zoneEdges, 14, [1, 2]);
            c.zoneError = errorLabel(app, s, 15, [1, 2]);
            c.quadrants = uicheckbox(s, 'Text', '4象限の Shot 数をそろえる', 'ValueChangedFcn', onChange);
            place(c.quadrants, 16, [1, 2]);
            c.scanConstraint = uicheckbox(s, 'Text', 'Scan 方向ごとの Shot 数をそろえる', 'ValueChangedFcn', onChange);
            place(c.scanConstraint, 17, [1, 2]);
            label(s, '許容幅（各区画の Shot 数の ±）', 18, 1);
            label(s, 'I 最適の基準モデル（XY 多項式の次数）', 18, 2);
            c.slack = uispinner(s, 'Limits', [0, 10], 'RoundFractionalValues', 'on', 'ValueChangedFcn', onChange);
            place(c.slack, 19, 1);
            c.designOrder = uispinner(s, 'Limits', [1, 8], 'RoundFractionalValues', 'on', 'ValueChangedFcn', onChange);
            place(c.designOrder, 19, 2);
            label(s, '交換法の初期配置の数（多いほど良い組が見つかるが遅い）', 20, [1, 2]);
            c.exchangeStarts = uispinner(s, 'Limits', [1, 100], 'RoundFractionalValues', 'on', 'ValueChangedFcn', onChange);
            place(c.exchangeStarts, 21, 1);
            heading(s, '評価', 22);
            label(s, '外周とみなす半径（Wafer 半径に対する比）', 23, [1, 2]);
            c.outerRatio = uieditfield(s, 'numeric', 'Limits', [0, 1], 'ValueDisplayFormat', '%.2f', 'ValueChangedFcn', onChange);
            place(c.outerRatio, 24, 1);
            c.removeLinear = uicheckbox(s, 'ValueChangedFcn', onChange, ...
                'Text', 'XY 1次（並進・倍率・回転・直交度）を除いてから推定する');
            place(c.removeLinear, 25, [1, 2]);
            c.recordTiming = uicheckbox(s, 'ValueChangedFcn', onChange, ...
                'Text', '条件ごとの処理時間を記録する（1 枚あたりの推定時間）', ...
                'Tooltip', ['手法 × 学習パターンごとに、1 枚（X・Y）の推定にかかった秒数を集計し、「4. 結果一覧」の指標と' ...
                'Excel の「処理時間」シートに出します。各手法の初回は予備の推定を1回して、読み込みの時間を除きます。']);
            place(c.recordTiming, 26, [1, 2]);

            methodPanel = uipanel(grid, 'Title', '比べる手法');
            m = uigridlayout(methodPanel, [17, 4], 'RowHeight', repmat({'fit'}, 1, 17), 'ColumnWidth', {'1x', '1x', '1x', '1x'}, ...
                'Padding', 10, 'RowSpacing', 6, 'Scrollable', 'on');
            presetGrid = uigridlayout(m, [1, 3], 'Padding', 0, 'ColumnWidth', {'fit', 'fit', 'fit'});
            place(presetGrid, 1, [1, 4]);
            uibutton(presetGrid, 'Text', '推奨の組み合わせ', 'ButtonPushedFcn', @(~, ~) app.onPreset("recommended"));
            uibutton(presetGrid, 'Text', 'すべて選ぶ', 'ButtonPushedFcn', @(~, ~) app.onPreset("all"));
            uibutton(presetGrid, 'Text', 'すべて外す', 'ButtonPushedFcn', @(~, ~) app.onPreset("none"));
            label(m, '説明変数（GPR・TPS・RBF・Kriging・GAM に共通。T は方位角）', 2, [1, 4]);
            c.featureXY = uicheckbox(m, 'Text', 'X, Y', 'ValueChangedFcn', onChange);
            place(c.featureXY, 3, 1);
            c.featureXYR = uicheckbox(m, 'Text', 'X, Y, 半径', 'ValueChangedFcn', onChange);
            place(c.featureXYR, 3, 2);
            c.featureXYRT = uicheckbox(m, 'Text', 'X, Y, 半径, T', 'ValueChangedFcn', onChange);
            place(c.featureXYRT, 3, 3);
            c.shotRowParity = uicheckbox(m, 'Text', 'Shot 行の奇数・偶数を質的変数に追加', ...
                'Tooltip', '各 Wafer・測定日時で、入力の Shot 中心 Y 座標を上から1行目として数えます。半径除外前に判定。入力にない行は数えません。', ...
                'ValueChangedFcn', onChange);
            place(c.shotRowParity, 4, [1, 4]);
            c.gpr = uicheckbox(m, 'Text', 'GPR（ガウス過程回帰）', 'ValueChangedFcn', onChange);
            place(c.gpr, 5, [1, 4]);
            label(m, 'カーネル（Ctrl・Shift で複数選ぶ）', 6, [1, 2]);
            label(m, '質的変数の扱い（Scan・Mark・任意の行奇偶）', 6, [3, 4]);
            c.kernels = uilistbox(m, 'Items', cellstr(alignest.models.gprKernelNames()), 'Multiselect', 'on', ...
                'ValueChangedFcn', onChange);
            place(c.kernels, 7, [1, 2]);
            [modeNames, modeLabels] = alignest.models.gprFactorModes();
            modeGrid = uigridlayout(m, [numel(modeNames), 1], 'Padding', 0, 'RowSpacing', 2, ...
                'RowHeight', repmat({'fit'}, 1, numel(modeNames)));
            place(modeGrid, 7, [3, 4]);
            c.factorModes = gobjects(1, numel(modeNames));
            for k = 1:numel(modeNames)
                c.factorModes(k) = uicheckbox(modeGrid, 'Text', modeLabels(k), 'UserData', modeNames(k), ...
                    'ValueChangedFcn', onChange);
            end
            m.RowHeight{7} = 300;
            c.tps = uicheckbox(m, 'Text', 'TPS（薄板スプライン）', 'ValueChangedFcn', onChange);
            place(c.tps, 8, [1, 2]);
            c.tpsFactors = spatialFactorDropdown(m, onChange);
            place(c.tpsFactors, 8, [3, 4]);
            c.rbf = uicheckbox(m, 'Text', 'RBF（ガウス型・平滑化つき）', 'ValueChangedFcn', onChange);
            place(c.rbf, 9, [1, 4]);
            c.ordinaryKriging = uicheckbox(m, 'Text', 'Kriging（通常）', 'ValueChangedFcn', onChange);
            place(c.ordinaryKriging, 10, [1, 2]);
            c.ordinaryFactors = spatialFactorDropdown(m, onChange);
            place(c.ordinaryFactors, 10, [3, 4]);
            c.universalKriging = uicheckbox(m, 'Text', 'Universal Kriging', 'ValueChangedFcn', onChange);
            place(c.universalKriging, 11, [1, 2]);
            c.universalFactors = spatialFactorDropdown(m, onChange);
            place(c.universalFactors, 11, [3, 4]);
            label(m, 'バリオグラム（通常・Universal 共通）', 12, [1, 4]);
            variograms = ["linear", "gaussian", "power", "exponential"];
            c.variograms = gobjects(1, numel(variograms));
            for k = 1:numel(variograms)
                c.variograms(k) = uicheckbox(m, 'Text', variograms(k), 'UserData', variograms(k), 'ValueChangedFcn', onChange);
                place(c.variograms(k), 13, k);
            end
            c.gam = uicheckbox(m, 'Text', 'GAM（一般化加法モデル。Scan 方向・Mark 番号を含む）', 'ValueChangedFcn', onChange);
            place(c.gam, 14, [1, 4]);
            c.polynomial = uicheckbox(m, 'Text', 'XY 多項式　次数：', 'ValueChangedFcn', onChange);
            place(c.polynomial, 15, 1);
            c.polynomialOrder = uispinner(m, 'Limits', [1, 8], 'RoundFractionalValues', 'on', 'ValueChangedFcn', onChange);
            place(c.polynomialOrder, 15, 2);
            c.rt = uicheckbox(m, 'Text', 'RT モデル　次数 K：', 'ValueChangedFcn', onChange);
            place(c.rt, 16, 1);
            c.rtOrders = uieditfield(m, 'text', 'ValueChangedFcn', onChange);
            place(c.rtOrders, 16, 2);
            c.rtError = errorLabel(app, m, 17, [1, 4]);

            footer = uigridlayout(grid, [1, 4], 'ColumnWidth', {'fit', 'fit', 'fit', '1x'}, 'Padding', 0);
            place(footer, 2, [1, 2]);
            uibutton(footer, 'Text', '設定を保存…', 'ButtonPushedFcn', @(~, ~) app.onSaveSettings());
            uibutton(footer, 'Text', '設定を読み込む…', 'ButtonPushedFcn', @(~, ~) app.onLoadSettings());
            uibutton(footer, 'Text', '初期設定に戻す', 'ButtonPushedFcn', @(~, ~) app.setSettings(alignest.defaultSettings()));
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
            fillUnitTable(app);
            c.shotRowParity.Value = s.factors.shotRowParity;
            c.samplingMethod.Value = char(s.sampling.method);
            c.nShotsStart.Value = s.sampling.nShotsStart;
            c.nShotsEnd.Value = s.sampling.nShotsEnd;
            c.nShotsStep.Value = s.sampling.nShotsStep;
            c.randomRepeats.Value = s.sampling.randomRepeats;
            c.seed.Value = s.sampling.seed;
            c.manualPlans.Value = cellstr(ternary(isempty(s.sampling.manualPlans), "", s.sampling.manualPlans(:)));
            c.zoneEdges.Value = char(strjoin(string(s.sampling.constraints.radialZoneEdges), " "));
            c.quadrants.Value = s.sampling.constraints.quadrants;
            c.scanConstraint.Value = s.sampling.constraints.scanDirection;
            c.slack.Value = s.sampling.constraints.slack;
            c.designOrder.Value = s.sampling.designOrder;
            c.exchangeStarts.Value = s.sampling.exchangeStarts;
            c.outerRatio.Value = s.evaluation.outerRadiusRatio;
            c.removeLinear.Value = s.evaluation.removeLinear;
            c.recordTiming.Value = s.evaluation.recordTiming;
            methods = s.methods;
            c.featureXY.Value = any(methods.featureSets == "XY");
            c.featureXYR.Value = any(methods.featureSets == "XYR");
            c.featureXYRT.Value = any(methods.featureSets == "XYRT");
            c.gpr.Value = methods.gpr.enabled;
            c.kernels.Value = cellstr(methods.gpr.kernels);
            for k = 1:numel(c.factorModes)
                c.factorModes(k).Value = any(methods.gpr.factorModes == c.factorModes(k).UserData);
            end
            c.tps.Value = methods.tps.enabled;
            c.rbf.Value = methods.rbf.enabled;
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
            s.factors.shotRowParity = c.shotRowParity.Value;
            s.sampling.method = string(c.samplingMethod.Value);
            try
                s.sampling.nShots = alignest.shotCountList(c.nShotsStart.Value, c.nShotsEnd.Value, c.nShotsStep.Value);
                s.sampling.nShotsStart = c.nShotsStart.Value;
                s.sampling.nShotsEnd = c.nShotsEnd.Value;
                s.sampling.nShotsStep = c.nShotsStep.Value;
            catch
                % 正しくない組み合わせのときは前の値のまま（欄の下に理由を出す）
            end
            s.sampling.randomRepeats = c.randomRepeats.Value;
            s.sampling.seed = c.seed.Value;
            lines = string(c.manualPlans.Value);
            s.sampling.manualPlans = lines(strlength(strtrim(lines)) > 0);
            [values, ok] = parseNumbers(c.zoneEdges.Value);
            if ok && all(values > 0 & values < 1)
                s.sampling.constraints.radialZoneEdges = sort(values);
            end
            s.sampling.constraints.quadrants = c.quadrants.Value;
            s.sampling.constraints.scanDirection = c.scanConstraint.Value;
            s.sampling.constraints.slack = c.slack.Value;
            s.sampling.designOrder = c.designOrder.Value;
            s.sampling.exchangeStarts = c.exchangeStarts.Value;
            s.evaluation.outerRadiusRatio = c.outerRatio.Value;
            s.evaluation.removeLinear = c.removeLinear.Value;
            s.evaluation.recordTiming = c.recordTiming.Value;
            featureNames = ["XY", "XYR", "XYRT"];
            s.methods.featureSets = featureNames([c.featureXY.Value, c.featureXYR.Value, c.featureXYRT.Value]);
            s.methods.gpr.enabled = c.gpr.Value;
            s.methods.gpr.kernels = string(c.kernels.Value);
            s.methods.gpr.factorModes = checkedValues(c.factorModes);
            s.methods.tps.enabled = c.tps.Value;
            s.methods.rbf.enabled = c.rbf.Value;
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
                counts = alignest.shotCountList(c.nShotsStart.Value, c.nShotsEnd.Value, c.nShotsStep.Value);
                listText = "→ 学習 Shot 数：" + previewList(counts, app.LIST_PREVIEW_COUNT) + sprintf("（%d 通り）", numel(counts));
            catch err
                if method ~= "manual"
                    text = "⚠ " + string(err.message);
                end
            end
            c.nShotsList.Text = listText;
            c.nShotsError.Text = text;
            messages = [messages; text(text ~= "")];
            text = "";
            if method == "manual"
                try
                    alignest.buildPlanSpecs(struct("method", "manual", "manualPlans", string(c.manualPlans.Value)));
                catch err
                    text = "⚠ " + string(err.message);
                end
            end
            c.manualError.Text = text;
            messages = [messages; text(text ~= "")];
            [values, ok] = parseNumbers(c.zoneEdges.Value);
            text = "";
            if ~ok || any(values <= 0 | values >= 1)
                text = "⚠ 同心円の区切りは 0 より大きく 1 より小さい数を空白で区切って入れてください（使わないなら空欄）。";
            end
            c.zoneError.Text = text;
            messages = [messages; text(text ~= "")];
            [values, ok] = parseNumbers(c.rtOrders.Value);
            text = "";
            if c.rt.Value && (~ok || isempty(values) || any(values < 1 | values > 10 | values ~= round(values)))
                text = "⚠ RT モデルの次数は 1〜10 の整数を空白で区切って入れてください（例：4 5）。";
            end
            c.rtError.Text = text;
            messages = [messages; text(text ~= "")];
        end

        function updateEnabled(app)
            c = app.Controls;
            method = string(c.samplingMethod.Value);
            constrained = method ~= "manual";
            set([c.nShotsStart, c.nShotsEnd, c.nShotsStep, c.nShotsList, c.zoneEdges, c.quadrants, c.scanConstraint, ...
                c.slack], 'Enable', onOff(constrained));
            set([c.randomRepeats, c.seed], 'Enable', onOff(method == "random"));
            set([c.designOrder, c.exchangeStarts], 'Enable', onOff(method == "ioptimal"));
            c.manualPlans.Enable = onOff(method == "manual");
            set([c.kernels, c.factorModes], 'Enable', onOff(c.gpr.Value));
            set(c.variograms, 'Enable', onOff(c.ordinaryKriging.Value || c.universalKriging.Value));
            c.tpsFactors.Enable = onOff(c.tps.Value);
            c.ordinaryFactors.Enable = onOff(c.ordinaryKriging.Value);
            c.universalFactors.Enable = onOff(c.universalKriging.Value);
            c.polynomialOrder.Enable = onOff(c.polynomial.Value);
            c.rtOrders.Enable = onOff(c.rt.Value);
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
            grid = uigridlayout(app.Tabs.run, [5, 1], 'RowHeight', {'fit', 'fit', 'fit', 'fit', '1x'}, 'Padding', 12, ...
                'RowSpacing', 10);
            c.runSummary = uilabel(grid, 'WordWrap', 'on', 'Text', '');
            buttonGrid = uigridlayout(grid, [1, 2], 'ColumnWidth', {240, '1x'}, 'Padding', 0);
            c.run = primaryButton(app, buttonGrid, '評価を始める', @(~, ~) app.onRun());
            c.runStatus = uilabel(buttonGrid, 'WordWrap', 'on', 'Text', '');
            uilabel(grid, 'WordWrap', 'on', 'Text', ['評価の考え方：学習 Shot の計測値で推定し、学習しなかった Shot の計測値と比べます。' ...
                '実データには計測ノイズが含まれるので、誤差は模擬データの評価（真の値と比べた値）より少し大きく出ます。' ...
                '計算中は「止める」で途中までの結果を残して止められます。']);
            label(grid, '記録（データの確認・学習パターン・推定できなかった組み合わせ）');
            c.log = uitextarea(grid, 'Editable', 'off', 'Value', {''});
            app.Controls = mergeStruct(app.Controls, c);
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
            methods = alignest.buildMethodList(app.Settings.methods);
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
            for k = 1:numel(methods)
                repeats = 1;
                if any(methods(k).family == ["TPS", "OK", "UK"]) && methods(k).factorMode == "backfit"
                    repeats = app.Settings.methods.options.backfitMaxIterations;
                end
                seconds = seconds + repeats * app.SECONDS_PER_FIT.(methods(k).family);
            end
            seconds = seconds * nPlans * nUnits;
            if string(app.Settings.sampling.method) == "ioptimal"
                seconds = seconds + app.SECONDS_PER_IOPTIMAL_PLAN * nPlans;
            end
            text = sprintf("手法 %d 種類 × 学習パターン %d × Wafer %d 枚 = %d 回の推定（目安 %s）", ...
                numel(methods), nPlans, nUnits, total, durationText(seconds));
            c.countLabel.Text = text;
            if nUnits == 0
                c.runSummary.Text = "データがまだ読み込まれていません。「1. データの読み込み」から始めてください。";
            elseif isempty(methods)
                c.runSummary.Text = "比べる手法が選ばれていません。「2. 評価の設定」で手法を選んでください。";
            else
                c.runSummary.Text = "これから計算する組み合わせ：" + text + "。";
            end
        end

        % ================= 4. 結果一覧 =================
        function buildResultsTab(app)
            grid = uigridlayout(app.Tabs.results, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 12, 'RowSpacing', 10);
            controls = uigridlayout(grid, [2, 5], 'ColumnWidth', {260, 160, '1x', 'fit', 'fit'}, 'Padding', 0, ...
                'RowHeight', {'fit', 'fit'});
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

            % 表・グラフ・比較・誤差の分布は、それぞれ画面の幅いっぱいに出す（手法の名前が切れないように）
            c.resultTabs = uitabgroup(grid);
            tableTab = uitab(c.resultTabs, 'Title', '表（手法 × 学習パターン）');
            tableGrid = uigridlayout(tableTab, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 8);
            c.tableNote = uilabel(tableGrid, 'WordWrap', 'on', ...
                'Text', ['各列で最も良い手法に「★」を付け、背景も色づけしています。集計の「ワースト値」は最も悪い Wafer の値、' ...
                '「95%値」は 95% の Wafer がそれより良い値（誤差は大きい側、R² は小さい側）です。']);
            c.summaryTable = uitable(tableGrid, 'RowName', {}, 'ColumnName', {'手法'});
            c.chartTab = uitab(c.resultTabs, 'Title', 'グラフ');
            chartGrid = uigridlayout(c.chartTab, [2, 2], 'RowHeight', {'fit', '1x'}, 'ColumnWidth', {'1x', 380}, 'Padding', 8);
            chartControls = uigridlayout(chartGrid, [1, 3], 'ColumnWidth', {'fit', 420, 'fit'}, 'Padding', 0);
            place(chartControls, 1, 1);
            label(chartControls, '横軸', 1, 1);
            c.chartXAxis = uidropdown(chartControls, 'Items', {'学習 Shot 数（学習パターン）', ...
                'I 基準と D 基準（I 最適計画の評価指標。2つ並べる）'}, 'ItemsData', {'plan', 'criteria'}, ...
                'Tooltip', ['学習 Shot の組の I 基準 tr(M⁻¹) と D 基準 det(M)^(−1/p)（XY 多項式の基準モデル）に対する推定誤差。' ...
                '点は学習パターンの列ごとの Wafer の集計。基準は Wafer の平均。'], 'ValueChangedFcn', @(~, ~) app.drawChart());
            place(c.chartXAxis, 1, 2);
            c.chartPoints = uicheckbox(chartControls, 'Text', 'Wafer ごとの点も描く（I・D 基準）', ...
                'ValueChangedFcn', @(~, ~) app.drawChart());
            place(c.chartPoints, 1, 3);
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
                'すべての手法・学習パターン・Wafer（時間がかかる）'}, 'ItemsData', {'selected', 'all'});
            place(c.estimateScope, 2, 5);
            c.exportEstimates = uibutton(analysisControls, 'Text', '推定値を Excel に書き出す…', ...
                'ButtonPushedFcn', @(~, ~) app.onExportEstimates());
            place(c.exportEstimates, 2, 6);
            histogramGrid = uigridlayout(analysisGrid, [1, 2], 'Padding', 0, 'ColumnSpacing', 12);
            c.histogramAxes = [uiaxes(histogramGrid), uiaxes(histogramGrid)];
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
            app.Controls = mergeStruct(app.Controls, c);
        end

        function refreshResultControls(app)
            c = app.Controls;
            results = app.Results;
            labels = string({results.methods.label});
            ids = string({results.methods.id});
            [metricList, metricLabels] = alignest.metricNames(isfield(results, "timingRecorded") && results.timingRecorded);
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
            set([c.export, c.saveChart], 'Enable', 'on');
            % マップの選択肢
            c.mapWafer.Items = cellstr(results.unitLabels);
            c.mapWafer.ItemsData = 1:numel(results.unitLabels);
            planLabels = unique(string({results.plans.label}), 'stable');
            c.mapPlan.Items = cellstr(planLabels);
            c.mapMethod.Items = cellstr(labels);
            c.mapMethod.ItemsData = 1:numel(labels);
            set([c.mapWafer, c.mapPlan, c.mapMethod, c.mapMode, c.mapScale, c.mapMarkerSize, c.mapShotFrames, c.saveMap], ...
                'Enable', 'on');
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
                    addStyle(c.summaryTable, uistyle('BackgroundColor', app.BEST_COLOR, 'FontWeight', 'bold'), 'cell', [best, g + 1]);
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
            for k = 1:numel(selected)
                m = selected(k);
                plot(ax, positions, summary.values(m, :), ['-', markers{mod(k - 1, numel(markers)) + 1}], 'LineWidth', 1.5, ...
                    'MarkerSize', 7, 'DisplayName', summary.methodLabels(m));
            end
            hold(ax, 'off');
            ax.XTick = positions;
            numbers = str2double(extractBefore(summary.groups, " Shot"));
            if all(isfinite(numbers))
                ax.XTickLabel = cellstr(string(numbers));
                xlabel(ax, '学習 Shot 数');
            else
                ax.XTickLabel = cellstr(summary.groups);
                xlabel(ax, '学習パターン');
            end
            [names, labels] = alignest.metricNames(true);
            ylabel(ax, labels(names == metric));
            title(ax, "Wafer の" + statisticLabel(string(c.statistic.Value)));
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
            [names, labels] = alignest.metricNames(true);
            criteria = ["criterionI", "criterionD"];
            criteriaLabels = ["I 基準 tr(M^{-1})", "D 基準 det(M)^{-1/p}"];
            criteriaNames = ["I 基準", "D 基準"];
            markers = {'o', 's', 'd', '^', 'v', '>', '<', 'p', 'h', 'x'};
            groupNames = string(summary.groups);
            shortNames = extractBefore(groupNames, " Shot");
            shortNames(ismissing(shortNames)) = groupNames(ismissing(shortNames));
            axesList = [c.chartAxes, c.chartAxes2];
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
                    curve = plot(ax, xs, ys, ['-', markers{mod(k - 1, numel(markers)) + 1}], 'LineWidth', 1.5, ...
                        'MarkerSize', 7, 'DisplayName', summary.methodLabels(m));
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
                title(ax, sprintf("%s と推定誤差（Wafer の%s）", criteriaNames(a), statisticLabel(statistic)));
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

        function [estimates, messages] = collectWithProgress(app, selection, cache, maxRows, titleText)
            % 推定値を集める（画面が出ているときは進み具合を出し、「止める」で中止できる）
            dialog = [];
            if app.Figure.Visible == "on"
                dialog = uiprogressdlg(app.Figure, 'Title', titleText, 'Message', '推定値を計算しています…', ...
                    'Cancelable', 'on', 'CancelText', '止める', 'ShowPercentage', 'on');
            end
            cleanup = onCleanup(@() closeDialog(dialog));
            [estimates, messages, cancelled] = alignest.collectEstimates(app.Data, app.Results, selection, cache=cache, ...
                maxRows=maxRows, progressFcn=@(done, total) reportCollectProgress(dialog, done, total));
            if cancelled
                error('alignest:cancelled', '途中で止めました。');
            end
        end

        function showAnalysis(app)
            c = app.Controls;
            estimates = app.Analysis.estimates;
            alignest.plot.residualHistogram(c.histogramAxes(1), estimates.residualX, "X の残差");
            alignest.plot.residualHistogram(c.histogramAxes(2), estimates.residualY, "Y の残差");
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
            note = "分析した範囲：" + scopeText + "。" + c.analysisNote.UserData;
            if ~isempty(app.Analysis.messages)
                note = note + " ⚠ 推定できなかった組み合わせ：" + strjoin(app.Analysis.messages, "／");
            end
            c.analysisNote.Text = note;
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
            grid = uigridlayout(app.Tabs.map, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 12, 'RowSpacing', 10);
            controls = uigridlayout(grid, [2, 8], 'ColumnWidth', {170, 200, '1x', 170, 170, 120, 'fit', 'fit'}, ...
                'Padding', 0, 'RowHeight', {'fit', 'fit'});
            label(controls, 'Wafer', 1, 1);
            label(controls, '学習パターン', 1, 2);
            label(controls, '手法', 1, 3);
            label(controls, '表示', 1, 4);
            label(controls, '矢印の倍率 [mm/nm]（0 = 自動）', 1, 5);
            label(controls, '色の点の大きさ', 1, 6);
            onChange = @(~, ~) app.drawMap();
            c.mapWafer = uidropdown(controls, 'Items', {'—'}, 'ValueChangedFcn', onChange);
            place(c.mapWafer, 2, 1);
            c.mapPlan = uidropdown(controls, 'Items', {'—'}, 'ValueChangedFcn', onChange);
            place(c.mapPlan, 2, 2);
            c.mapMethod = uidropdown(controls, 'Items', {'—'}, 'ValueChangedFcn', onChange);
            place(c.mapMethod, 2, 3);
            c.mapMode = uidropdown(controls, 'Items', {'ベクトル（矢印）', 'X（色）', 'Y（色）'}, ...
                'ItemsData', {'vector', 'X', 'Y'}, 'ValueChangedFcn', onChange);
            place(c.mapMode, 2, 4);
            c.mapScale = uieditfield(controls, 'numeric', 'Value', 0, 'Limits', [0, Inf], 'ValueChangedFcn', onChange);
            place(c.mapScale, 2, 5);
            c.mapMarkerSize = markerSizeSpinner(app, controls, onChange);
            place(c.mapMarkerSize, 2, 6);
            c.mapShotFrames = uicheckbox(controls, 'Text', 'Shot の枠', 'Value', true, 'ValueChangedFcn', onChange);
            place(c.mapShotFrames, 2, 7);
            c.saveMap = uibutton(controls, 'Text', '図を画像で保存…', 'ButtonPushedFcn', @(~, ~) app.onSaveMap());
            place(c.saveMap, 2, 8);
            set([c.mapWafer, c.mapPlan, c.mapMethod, c.mapMode, c.mapScale, c.mapMarkerSize, c.mapShotFrames, c.saveMap], ...
                'Enable', 'off');
            c.mapPanel = uipanel(grid, 'BorderType', 'none');
            axesGrid = uigridlayout(c.mapPanel, [1, 3], 'Padding', 0, 'ColumnSpacing', 8);
            c.mapAxes = [uiaxes(axesGrid), uiaxes(axesGrid), uiaxes(axesGrid)];
            c.mapInfo = uilabel(grid, 'WordWrap', 'on', 'Text', '「3. 実行」で評価すると、ここに Wafer ごとの図が出ます。');
            app.Controls = mergeStruct(app.Controls, c);
        end

        function drawMap(app)
            if isempty(app.Results)
                return
            end
            c = app.Controls;
            u = c.mapWafer.Value;
            planLabel = string(c.mapPlan.Value);
            m = c.mapMethod.Value;
            planIndex = find(string({app.Results.plans.label}) == planLabel & [app.Results.plans.unitIndex] == u, 1);
            if isempty(planIndex)
                c.mapInfo.Text = "⚠ この Wafer はこの学習パターンを計算していません（途中で止めた場合など）。";
                arrayfun(@(ax) cla(ax), c.mapAxes);
                return
            end
            unit = app.Data.units(u);
            marks = unit.marks;
            method = app.Results.methods(m);
            plan = app.Results.plans(planIndex);
            if ~plan.ok
                c.mapInfo.Text = "⚠ この Wafer ではこの学習パターンを作れませんでした：" + plan.message;
                arrayfun(@(ax) cla(ax), c.mapAxes);
                return
            end
            key = sprintf('%d|%d|%d', u, planIndex, m);
            if isKey(app.MapCache, key)
                out = app.MapCache(key);
            else
                app.Figure.Pointer = 'watch';
                drawnow;
                try
                    out = alignest.estimateWafer(unit, plan.shotIndex, method, app.Results.settings);
                catch err
                    app.Figure.Pointer = 'arrow';
                    c.mapInfo.Text = "⚠ この組み合わせでは推定できませんでした：" + string(err.message);
                    arrayfun(@(ax) cla(ax), c.mapAxes);
                    return
                end
                app.Figure.Pointer = 'arrow';
                app.MapCache(key) = out;
            end
            measured = nan(numel(marks.x), 2);
            estimate = nan(numel(marks.x), 2);
            measured(out.testIndex.X, 1) = marks.measX(out.testIndex.X);
            measured(out.testIndex.Y, 2) = marks.measY(out.testIndex.Y);
            estimate(out.testIndex.X, 1) = out.estimate.X;
            estimate(out.testIndex.Y, 2) = out.estimate.Y;
            evaluated = any(isfinite(measured), 2);
            residual = measured - estimate;
            trainMarks = ismember(marks.shotIndex, plan.shotIndex) & (marks.validX | marks.validY);
            trainPoints = [marks.x(trainMarks), marks.y(trainMarks)];
            points = [marks.x(evaluated), marks.y(evaluated)];
            scale = c.mapScale.Value;
            if scale <= 0
                scale = alignest.plot.vectorScale(measured(evaluated, :));
            end
            mode = string(c.mapMode.Value);
            limit = max(abs(measured(isfinite(measured))), [], 'all');
            if isempty(limit)
                limit = 1;
            end
            panels = {measured(evaluated, :), "計測値（評価した Shot）"; estimate(evaluated, :), "推定値"; ...
                residual(evaluated, :), "残差（計測値 − 推定値）"};
            colors = [0.0, 0.33, 0.62; 0.0, 0.33, 0.62; app.RESIDUAL_COLOR];
            [centers, sizeMm] = shotFrameData(unit, c.mapShotFrames.Value);
            for k = 1:3
                alignest.plot.waferMap(c.mapAxes(k), points, panels{k, 1}, mode=mode, scaleMmPerNm=scale, ...
                    colorLimit=limit, trainPoints=trainPoints, titleText=panels{k, 2}, ...
                    waferRadiusMm=app.Results.settings.data.waferRadiusMm, arrowColor=colors(k, :), ...
                    markerSize=c.mapMarkerSize.Value, shotCenters=centers, shotSizeMm=sizeMm);
                c.mapAxes(k).FontSize = app.AXES_FONT_SIZE;
            end
            row = app.Results.table(app.Results.table.unitIndex == u & app.Results.table.planIndex == planIndex & ...
                app.Results.table.methodIndex == m, :);
            if isempty(row)
                metricsText = "";
            else
                metricsText = sprintf("RMSE（X・Y）%.3f nm、X %.3f nm、Y %.3f nm｜R² %.3f｜調整済み R² %.3f｜MAE %.3f nm", ...
                    row.RMSE_XY, row.RMSE_X, row.RMSE_Y, row.R2_XY, row.adjR2_XY, row.MAE_XY);
            end
            c.mapInfo.Text = sprintf("%s｜%s｜%s｜学習 Shot %d（shotNo：%s）｜評価点 X %d・Y %d｜%s", unit.label, plan.label, ...
                method.label, plan.nShots, strjoin(string(plan.shotNos(:).'), " "), numel(out.testIndex.X), ...
                numel(out.testIndex.Y), metricsText);
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

        % ================= 共通 =================
        function clearResults(app)
            app.Results = [];
            app.Analysis = [];
            app.MapCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
            c = app.Controls;
            if ~isfield(c, 'summaryTable')
                return
            end
            c.summaryTable.Data = {};
            c.comparisonTable.Data = {};
            c.normalityTable.Data = {};
            c.anovaTable.Data = {};
            for ax = [c.chartAxes, c.chartAxes2, c.histogramAxes, c.mapAxes]
                cla(ax);
                legend(ax, 'off');
            end
            c.chartAxes2.Visible = 'off';
            set([c.export, c.saveChart, c.mapWafer, c.mapPlan, c.mapMethod, c.mapMode, c.mapScale, c.mapMarkerSize, ...
                c.mapShotFrames, c.saveMap, c.analysisMethod, c.analysisGroup, c.analysisWafer, c.analyze, ...
                c.estimateScope, c.exportEstimates], 'Enable', 'off');
            c.runStatus.Text = "";
            c.mapInfo.Text = "「3. 実行」で評価すると、ここに Wafer ごとの図が出ます。";
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
                'BackgroundColor', app.PRIMARY_COLOR, 'FontColor', [1, 1, 1], 'FontWeight', 'bold');
        end

        function spinner = markerSizeSpinner(app, parent, callback)
            spinner = uispinner(parent, 'Limits', app.MARKER_SIZE_LIMITS, 'Value', app.DEFAULT_MARKER_SIZE, 'Step', 5, ...
                'Tooltip', '色で描く点の大きさ（面積）。点が重なるときは小さく、まばらなときは大きくします。', ...
                'ValueChangedFcn', callback);
        end

        function item = errorLabel(app, parent, row, column)
            item = uilabel(parent, 'Text', '', 'FontColor', app.ERROR_COLOR, 'WordWrap', 'on');
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
item = uilabel(parent, 'Text', text, 'FontWeight', 'bold');
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

function state = onOff(condition)
state = matlab.lang.OnOffSwitchState(condition);
end

function control = spatialFactorDropdown(parent, callback)
control = uidropdown(parent, 'Items', {'質的変数なし', 'Backfitting', 'なし・Backfitting を比較'}, ...
    'ItemsData', {'none', 'backfit', 'both'}, 'ValueChangedFcn', callback, ...
    'Tooltip', 'Scan 方向・Mark 番号（選択時は Shot 行奇偶も）を固定効果として空間成分と交互に推定します。');
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
% 空白・カンマ区切りの数字を読む。空欄は空の並び
text = strtrim(regexprep(char(strjoin(string(text), " ")), '[,、\s]+', ' '));
if isempty(text)
    values = zeros(1, 0);
    ok = true;
    return
end
values = str2double(split(string(text), " ")).';
ok = all(isfinite(values));
end

function positions = groupPositions(groups)
% 「20 Shot」のような列は Shot 数を横軸の位置に、それ以外（手動）は 1, 2, … にする
numbers = str2double(extractBefore(groups, " Shot"));
if all(isfinite(numbers))
    positions = numbers;
else
    positions = 1:numel(groups);
end
end

function spinner = shotCountSpinner(parent, callback)
MAX_SHOT_COUNT = 10000;
spinner = uispinner(parent, 'Limits', [1, MAX_SHOT_COUNT], 'RoundFractionalValues', 'on', 'ValueChangedFcn', callback);
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
    "directionRule", string(data.directionRule), "invertDirection", logical(data.invertDirection));
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
