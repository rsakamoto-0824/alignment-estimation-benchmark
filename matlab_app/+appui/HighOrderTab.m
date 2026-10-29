classdef (Abstract) HighOrderTab < appui.Core
    %HIGHORDERTAB 「7. Shot高次補正」タブ：Shot 高次補正（Shot 内の座標の補正の式）の評価。入力のデータ（計測データ・未知の座標の
    %   推定値・Excel）、補正の式と k パラメータ（VIF で選ぶ）、回帰（ロバスト回帰・高次項だけの L2 正則化）、補正の評価・補正値・
    %   マップ・書き出し。計算は alignest.shotHighOrder。
    %   AlignmentEstimationApp（画面の本体）の一部。画面の部品は Controls、データ・結果は Core のプロパティに持つ。
    %   ほかのタブの関数も同じように呼べる（どれも AlignmentEstimationApp の関数になる）。

    methods
        function setHighOrderSource(app, source)
            %SETHIGHORDERSOURCE 入力のデータを選ぶ："data"（「1. データの読み込み」の計測データ）・"target"（「6. 未知の座標の
            %   推定」の推定値）・"file"（「Excel・CSV を読み込む…」で読み込んだデータ）。
            app.Controls.highOrderSource.Value = char(source);
            onHighOrderSourceChanged(app);
        end

        function setHighOrderSettings(app, options)
            %SETHIGHORDERSETTINGS 補正の式・単位・回帰の欄を変える（画面で選ぶのと同じ）。名前と値の組で渡す：
            %   maker（"asml"・"canon"・"nikon"）・unit（"common"・"shot"）・waferOrder（0〜3）・vifThreshold・
            %   loss（"ols"・"huber"・"lad"）・huberTuning・l2（true・false）・lambda・measured（推定値に学習に使った Mark の
            %   実測値も足すか）。例：app.setHighOrderSettings(unit="shot", loss="ols", l2=false)
            arguments
                app
                options.maker (1, 1) string
                options.unit (1, 1) string
                options.waferOrder (1, 1) double
                options.vifThreshold (1, 1) double
                options.loss (1, 1) string
                options.huberTuning (1, 1) double
                options.l2 (1, 1) logical
                options.lambda (1, 1) double
                options.measured (1, 1) logical
            end
            c = app.Controls;
            controls = struct("maker", c.highOrderMaker, "unit", c.highOrderUnit, "waferOrder", c.highOrderWaferOrder, ...
                "vifThreshold", c.highOrderVifThreshold, "loss", c.highOrderLoss, "huberTuning", c.highOrderHuber, ...
                "l2", c.highOrderL2, "lambda", c.highOrderLambda, "measured", c.highOrderMeasured);
            for name = string(fieldnames(options)).'
                value = options.(name);
                if isstring(value)
                    value = char(value);
                end
                controls.(name).Value = value;
            end
            if isfield(options, "measured")
                onHighOrderInputEdited(app);
            end
            onHighOrderSettingsChanged(app);
        end

        function data = loadHighOrderFile(app, filePath, sheetName)
            %LOADHIGHORDERFILE Shot 高次補正の入力にする Excel・CSV を読み、入力を「Excel・CSV のデータ」にする
            %   （alignest.readHighOrderFile。列は Xmm・Ymm・markXmm・markYmm・measX・measY など）。
            if nargin < 3
                sheetName = "";
            end
            [data, info] = alignest.readHighOrderFile(filePath, sheetName);
            app.HighOrderFile = struct("data", data, "info", info);
            highOrderInputChanged(app, "file");   % 前に読んだ表で求めた結果は消す
            setHighOrderSource(app, "file");
            app.Controls.highOrderWafer.Value = num2cell(1:numel(data.units));   % 読み込んだ Wafer をすべて選ぶ
            refreshHighOrderTerms(app);
        end

        function excluded = selectHighOrderTermsByVif(app, threshold)
            %SELECTHIGHORDERTERMSBYVIF 「VIF で選ぶ」：式のすべての項から始めて、VIF がしきい値以上の高次項を外す
            %   （alignest.highOrderVif）。threshold を省略すると画面のしきい値。外した k の番号を返す。
            c = app.Controls;
            if nargin >= 2
                c.highOrderVifThreshold.Value = threshold;
            end
            readHighOrderControls(app);
            options = alignest.highOrderOptions(app.Settings);
            [local, valid] = highOrderLocal(app);
            terms = alignest.highOrderTerms(options.maker);
            [~, info] = alignest.highOrderVif(terms, local, valid, options.vifThreshold);
            excluded = info.suggestedExcluded;
            app.Settings.highOrder.excludedTerms = excluded;
            refreshHighOrderTerms(app);
            markHighOrderStale(app);
        end

        function useAllHighOrderTerms(app)
            %USEALLHIGHORDERTERMS 「すべての項を使う」：外した項を戻す
            app.Settings.highOrder.excludedTerms = zeros(1, 0);
            refreshHighOrderTerms(app);
            markHighOrderStale(app);
        end

        function setHighOrderTermUsed(app, k, used)
            %SETHIGHORDERTERMUSED k の番号の項を使う（used = true）・使わない（false）にする（表のチェックと同じ）。
            %   k1〜k6（定数・1次）は外せない。
            if k <= 6 && ~used
                error('alignest:highOrderTerms', 'k1〜k6（並進・倍率・回転）は補正の土台なので外せません。');
            end
            excluded = reshape(app.Settings.highOrder.excludedTerms, 1, []);
            if used
                excluded = excluded(excluded ~= k);
            else
                excluded = unique([excluded, k]);
            end
            app.Settings.highOrder.excludedTerms = excluded;
            refreshHighOrderTerms(app);
            markHighOrderStale(app);
        end

        function result = computeHighOrder(app, waferChoice)
            %COMPUTEHIGHORDER 選んだ Wafer（「6. 未知の座標の推定」のときは Wafer × 学習データの組み合わせ）の Shot 高次補正を
            %   求め、補正の評価・補正値・マップに出す（alignest.shotHighOrder。設定は settings.highOrder）。
            %   waferChoice：一覧の番号（複数可。0 = すべて）。省略すると画面で選んでいるもの。
            c = app.Controls;
            refreshHighOrderChoices(app);
            if nargin >= 2
                if isequal(waferChoice, 0)
                    waferChoice = 1:numel(c.highOrderWafer.ItemsData);
                end
                c.highOrderWafer.Value = num2cell(reshape(waferChoice, 1, []));
            end
            readHighOrderControls(app);
            alignest.highOrderOptions(app.Settings);   % 設定の誤りを先に知らせる
            app.Figure.Pointer = 'watch';
            drawnow;
            restore = onCleanup(@() set(app.Figure, 'Pointer', 'arrow'));
            [wafers, notes] = highOrderWafers(app);
            started = tic;
            result = alignest.shotHighOrder(wafers, app.Settings);
            result.seconds = toc(started);
            result.messages = [result.messages; notes(:)];
            app.HighOrderRun = struct("result", result, "wafers", wafers, "source", string(c.highOrderSource.Value), ...
                "selection", {c.highOrderWafer.Value}, "settings", app.Settings.highOrder, ...
                "measured", c.highOrderMeasured.Value);
            c.highOrderOutputs.SelectedTab = c.highOrderSummaryTab;   % 結果（補正の評価）を見せる
            showHighOrderRun(app);
        end

        function summary = drawHighOrderMap(app, waferIndex, view, value, mode)
            %DRAWHIGHORDERMAP 「マップ」：選んだ Wafer の補正後の残差（または1次だけで補正した残差・補正量・補正前の値）を、
            %   Wafer 上（alignest.plot.correctionMap）か、Shot を重ねて（alignest.plot.shotStackMap）描く。
            %   waferIndex：計算した Wafer の番号、view："wafer"・"stack"、value："residual"・"linear"・"loo"（1点抜きの予測の
            %   誤差）・"correction"・"value"、
            %   mode："vector"・"X"・"Y"。省略すると画面の選択。summary は描いた点の数と |平均|+3σ（結果が無ければ []）。
            c = app.Controls;
            if nargin >= 2
                c.highOrderMapWafer.Value = waferIndex;
            end
            if nargin >= 3
                c.highOrderMapView.Value = char(view);
            end
            if nargin >= 4
                c.highOrderMapValue.Value = char(value);
            end
            if nargin >= 5
                c.highOrderMapMode.Value = char(mode);
            end
            summary = [];
            run = app.HighOrderRun;
            if isempty(run)
                cla(c.highOrderAxes, 'reset');
                legend(c.highOrderAxes, 'off');
                set([c.highOrderSaveFigure, c.highOrderCopyFigure], 'Enable', 'off');
                c.highOrderMapInfo.Text = c.highOrderMapInfo.UserData;
                return
            end
            position = min(max(c.highOrderMapWafer.Value, 1), numel(run.wafers));
            wafer = run.wafers(position);
            points = run.result.points(run.result.points.wafer == string(wafer.label), :);
            valueName = string(c.highOrderMapValue.Value);
            mode = string(c.highOrderMapMode.Value);
            labels = struct("residual", "高次補正の残差", "linear", "1次だけで補正した残差", "loo", ...
                "高次補正の予測の誤差（1点抜き）", "correction", "補正量", "value", "補正前の値");
            columns = struct("residual", ["residualX", "residualY"], "linear", ["linearResidualX", "linearResidualY"], ...
                "loo", ["looX", "looY"], "correction", ["correctionX", "correctionY"], "value", ["valueX", "valueY"]);
            valueLabel = labels.(valueName);
            if string(c.highOrderMapView.Value) == "stack"
                values = [points.(columns.(valueName)(1)), points.(columns.(valueName)(2))];
                stack = alignest.plot.shotStackMap(c.highOrderAxes, [points.localX, points.localY], values, mode=mode, ...
                    shotSizeMm=wafer.unit.shotSizeMm, titleText=wafer.label + "｜" + valueLabel + "（Shot を重ねる）");
                used = isfinite(values(:, 1 + (mode == "Y")));
                if mode == "vector"
                    used = all(isfinite(values), 2);
                end
                summary = struct("n", nnz(used), "meanPlus3SigmaX", meanPlus3Sigma(values(used, 1)), ...
                    "meanPlus3SigmaY", meanPlus3Sigma(values(used, 2)), "valueLabel", valueLabel, "positions", height(stack));
            else
                shown = points;
                plotted = valueName;
                if any(valueName == ["linear", "loo"])
                    % 1次だけで補正した残差・予測の誤差は「補正後の残差」の欄に入れて描く（値の名前は valueLabel で出す）
                    shown.residualX = points.(columns.(valueName)(1));
                    shown.residualY = points.(columns.(valueName)(2));
                    plotted = "residual";
                end
                summary = alignest.plot.correctionMap(c.highOrderAxes, struct("points", shown), wafer.unit, ...
                    value=plotted, source="all", mode=mode, titleText=wafer.label, showStatistics=false, ...
                    legendLocation="eastoutside", waferRadiusMm=app.Settings.data.waferRadiusMm, valueLabel=valueLabel, ...
                    markMeasured=run.source == "target");
            end
            styleAxes(app, c.highOrderAxes, app.AXES_FONT_SIZE);
            set([c.highOrderSaveFigure, c.highOrderCopyFigure], 'Enable', 'on');
            c.highOrderMapInfo.Text = char(sprintf("%s：%d 点、|平均|+3σ X %.3f nm・Y %.3f nm", valueLabel, summary.n, ...
                summary.meanPlus3SigmaX, summary.meanPlus3SigmaY) + ternary(run.source == "target" && ...
                string(c.highOrderMapView.Value) == "wafer", "（四角は実測値の点、◇ は未知の座標の点）", ""));
        end

        function exportHighOrderTo(app, filePath)
            %EXPORTHIGHORDERTO Shot 高次補正の評価を Excel に書き出す（alignest.exportHighOrder）。計算した後に設定・入力を
            %   変えていれば、書き出す前に今の設定・入力で計算し直す（画面と同じ結果を書くため）。
            if isempty(app.HighOrderRun)
                error('alignest:noHighOrder', '書き出す結果がありません。先に「補正を計算する」を押してください。');
            end
            recomputed = staleHighOrderText(app) ~= "";
            if recomputed
                computeHighOrder(app);
            end
            run = app.HighOrderRun;
            notes = ["入力のデータ", highOrderSourceText(app, run.source); ...
                "Wafer", strjoin(string({run.wafers.label}), "・")];
            if recomputed
                notes(end + 1, :) = ["計算", "書き出すときに、今の設定・入力で計算し直した"];
            end
            alignest.exportHighOrder(filePath, run.result, notes);
        end
    end

    methods (Access = {?appui.Core})
        % ================= 7. Shot高次補正 =================
        function buildHighOrderTab(app)
            % 左：入力のデータ・補正の式・回帰の設定。右：メッセージと、使う項と VIF（k パラメータを選ぶ表）・補正の評価・
            % 補正値・マップ（中のタブで切り替える）
            grid = uigridlayout(app.Tabs.highOrder, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 12, 'RowSpacing', 8);
            label(grid, ['Shot 高次補正（Shot 内の座標の補正の式。ASML・Canon・Nikon）の k パラメータを求め、補正の効果を' ...
                '評価します。左で入力のデータ・補正の式（VIF で使う項を選べます）・回帰（ロバスト回帰、高次項だけの L2 正則化）' ...
                'を決めて「補正を計算する」を押すと、高次補正の残差を、1次（k1〜k6）だけで補正した残差と比べて出します。'], 1, 1);
            body = uigridlayout(grid, [1, 2], 'ColumnWidth', {600, '1x'}, 'Padding', 0, 'ColumnSpacing', 14);
            registerResponsiveColumn(app, body, 1);
            left = uigridlayout(body, [9, 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit', 'fit', 'fit', 'fit', 'fit'}, ...
                'Padding', 0, 'RowSpacing', 6);
            place(uilabel(left, 'Text', '① 入力のデータ', 'FontWeight', 'bold'), 1, 1);
            inputGrid = uigridlayout(left, [2, 3], 'ColumnWidth', {'fit', '1x', 'fit'}, 'RowHeight', {'fit', 'fit'}, ...
                'Padding', 0);
            place(inputGrid, 2, 1);
            label(inputGrid, '入力', 1, 1);
            c.highOrderSource = uidropdown(inputGrid, 'Items', {'1. データの読み込みの計測データ', ...
                '6. 未知の座標の推定の推定値', 'Excel・CSV から読み込んだデータ'}, 'ItemsData', {'data', 'target', 'file'}, ...
                'ValueChangedFcn', @(~, ~) app.onHighOrderSourceChanged(), 'Tooltip', ['計測データ：「1. データの読み込み」で' ...
                '読み込んだ計測値（面内推定の入力と同じ）。推定値：「6. 未知の座標の推定」で推定した点の値（Wafer × 学習データの' ...
                '組み合わせごと）。Excel・CSV：右のボタンで読み込んだ表（Xmm・Ymm・markXmm・markYmm・measX・measY）。']);
            place(c.highOrderSource, 1, 2);
            c.highOrderLoad = uibutton(inputGrid, 'Text', 'Excel・CSV を読み込む…', ...
                'ButtonPushedFcn', @(~, ~) app.onLoadHighOrderFile(), 'Tooltip', ['1行目が見出しの表：Xmm・Ymm（Shot 中心の' ...
                '座標 [mm]）・markXmm・markYmm（Shot 内の座標 [mm]）・measX・measY（値 [nm]。dx・dy でもよい）は必須。' ...
                'Wafer・shotNo・StsX・StsY は任意。このアプリが書き出した推定値の Excel（「推定値」シート）も読めます。']);
            place(c.highOrderLoad, 1, 3);
            c.highOrderMeasured = uicheckbox(inputGrid, 'Text', '実測値（学習に使った Mark）も使う', 'Value', false, ...
                'ValueChangedFcn', @(~, ~) app.onHighOrderInputEdited(), 'Tooltip', ['「6. 未知の座標の推定」の推定値に、' ...
                'その推定の学習に使った Mark の計測値を足して補正を求めます。']);
            place(c.highOrderMeasured, 2, [2, 3]);
            c.highOrderInputInfo = uilabel(left, 'WordWrap', 'on', 'FontColor', app.Palette.muted, 'UserData', "muted", ...
                'Text', '');
            place(c.highOrderInputInfo, 3, 1);
            c.highOrderWafer = uilistbox(left, 'Items', {'—'}, 'ItemsData', {1}, 'Multiselect', 'on', 'Value', {1}, ...
                'ValueChangedFcn', @(~, ~) app.onHighOrderInputEdited(), 'Tooltip', ['補正を求める Wafer（推定値のときは ' ...
                'Wafer × 学習データの組み合わせ）。Ctrl・Shift を押しながらクリックで複数。Ctrl + A ですべて。']);
            place(c.highOrderWafer, 4, 1);

            place(uilabel(left, 'Text', '② 補正の式と k パラメータ', 'FontWeight', 'bold'), 5, 1);
            onSetting = @(~, ~) app.onHighOrderSettingsChanged();
            modelGrid = uigridlayout(left, [2, 4], 'ColumnWidth', {'fit', '1x', 'fit', '1x'}, 'RowHeight', {'fit', 'fit'}, ...
                'Padding', 0);
            place(modelGrid, 6, 1);
            label(modelGrid, '補正の式', 1, 1);
            c.highOrderMaker = uidropdown(modelGrid, 'Items', {'ASML', 'Canon', 'Nikon'}, 'ItemsData', ...
                {'asml', 'canon', 'nikon'}, 'ValueChangedFcn', onSetting, 'Tooltip', ['Overlay 計測ルールの Shot 高次補正の式' ...
                '（項・係数番号・変数・符号は変えない）。式は「8. ヘルプ」。']);
            place(c.highOrderMaker, 1, 2);
            label(modelGrid, '補正の単位', 1, 3);
            c.highOrderUnit = uidropdown(modelGrid, 'Items', {'Wafer 内で共通', 'Shot ごと'}, 'ItemsData', ...
                {'common', 'shot'}, 'ValueChangedFcn', onSetting, 'Tooltip', ['Wafer 内で共通：Wafer 内の Shot で共通の' ...
                '1組の k を、Wafer ごとにその Wafer のすべての点で求める。Shot ごと：Shot ごとに1組の k を、その Shot の' ...
                '点だけで求める（1つの Shot に、項の数より多い点があるとよい）。']);
            place(c.highOrderUnit, 1, 4);
            label(modelGrid, 'Wafer 成分', 2, 1);
            c.highOrderWaferOrder = uidropdown(modelGrid, 'Items', {'なし', '1次', '2次', '3次'}, 'ItemsData', {0, 1, 2, 3}, ...
                'ValueChangedFcn', onSetting, 'Tooltip', ['Wafer 内で共通のとき、Shot 中心の座標（Xc・Yc）の多項式' ...
                '（定数を除く）を k と一緒に求めます（Wafer の倍率・回転などが Shot の k に混ざらないように）。' ...
                'Shot ごとのときは、Shot ごとの k1・k2 が含むので使いません。']);
            place(c.highOrderWaferOrder, 2, 2);
            label(modelGrid, 'VIF のしきい値', 2, 3);
            c.highOrderVifThreshold = uieditfield(modelGrid, 'numeric', 'Limits', [1, Inf], 'LowerLimitInclusive', 'off', ...
                'ValueChangedFcn', onSetting, 'Tooltip', ['「VIF で選ぶ」で、VIF がこの値以上の高次項を外します' ...
                '（よく使う値は 5〜10）。表では、使う項のうち VIF がこの値以上の行に色を付けます。']);
            place(c.highOrderVifThreshold, 2, 4);
            termButtons = uigridlayout(left, [1, 3], 'ColumnWidth', {'fit', 'fit', '1x'}, 'Padding', 0);
            place(termButtons, 7, 1);
            c.highOrderVifSelect = uibutton(termButtons, 'Text', 'VIF で選ぶ', 'ButtonPushedFcn', ...
                @(~, ~) app.onHighOrderVifSelect(), 'Tooltip', ['式のすべての項から始めて、VIF がしきい値以上の高次項を、' ...
                '次数の高い項から1つずつ外します（k1〜k6 は外しません）。VIF は Shot 内の座標だけで決まります。']);
            c.highOrderAllTerms = uibutton(termButtons, 'Text', 'すべての項を使う', 'ButtonPushedFcn', ...
                @(~, ~) app.useAllHighOrderTerms());
            c.highOrderTermInfo = uilabel(termButtons, 'WordWrap', 'on', 'FontColor', app.Palette.muted, 'UserData', "muted", ...
                'Text', '');

            regression = uigridlayout(left, [2, 4], 'ColumnWidth', {'fit', '1x', 'fit', '1x'}, 'RowHeight', {'fit', 'fit'}, ...
                'Padding', 0);
            place(regression, 8, 1);
            regressionHeading = label(regression, '③ 回帰', 1, 1);
            regressionHeading.FontWeight = 'bold';
            c.highOrderLoss = uidropdown(regression, 'Items', {'最小二乗', 'Huber（ロバスト）', 'LAD（ロバスト）'}, ...
                'ItemsData', {'ols', 'huber', 'lad'}, 'ValueChangedFcn', onSetting, 'Tooltip', ['Huber・LAD：残差の大きい点' ...
                '（外れ値）ほど重みを下げて求め直します（尺度は残差の MAD × 1.4826）。最小二乗は比べるとき用。']);
            place(c.highOrderLoss, 1, 2);
            label(regression, 'Huber の c', 1, 3);
            c.highOrderHuber = uieditfield(regression, 'numeric', 'Limits', [0, Inf], 'LowerLimitInclusive', 'off', ...
                'ValueChangedFcn', onSetting, 'Tooltip', '残差が c × 尺度 を超える点の重みを下げます（1.345 で正規分布の誤差のとき効率 95%）。');
            place(c.highOrderHuber, 1, 4);
            c.highOrderL2 = uicheckbox(regression, 'Text', '高次項だけに L2 正則化', 'ValueChangedFcn', onSetting, ...
                'Tooltip', ['2次以上の項の係数を小さくする向きに罰則をかけます（k1〜k6 と Wafer 成分にはかけない）。' ...
                '点が少ない・項が似ているときの係数のばらつきを抑えます。']);
            place(c.highOrderL2, 2, [1, 2]);
            label(regression, 'λ', 2, 3);
            c.highOrderLambda = uieditfield(regression, 'numeric', 'Limits', [0, Inf], 'ValueChangedFcn', onSetting, ...
                'Tooltip', ['L2 正則化の強さ。項（列）を平均0・標準偏差1にそろえた係数にかけます。過去のシミュレーション' ...
                '（7×11点）の標準は 0.1。点を減らすときは λ × √(77 / 点の数) が目安。']);
            place(c.highOrderLambda, 2, 4);
            actions = uigridlayout(left, [2, 2], 'ColumnWidth', {180, 'fit'}, 'RowHeight', {'fit', 'fit'}, 'Padding', 0);
            place(actions, 9, 1);
            c.highOrderCompute = primaryButton(app, actions, '補正を計算する', @(~, ~) app.onComputeHighOrder());
            c.highOrderExport = uibutton(actions, 'Text', '結果を Excel に書き出す…', ...
                'ButtonPushedFcn', @(~, ~) app.onExportHighOrder());
            c.highOrderError = errorLabel(app, actions, 2, [1, 2]);

            % 右：メッセージと結果（補正の評価・補正値・マップを中のタブで切り替える）
            right = uigridlayout(body, [2, 1], 'RowHeight', {app.TARGET_MESSAGE_HEIGHT, '1x'}, 'Padding', 0, 'RowSpacing', 6);
            c.highOrderMessage = uitextarea(right, 'Editable', 'off', 'Value', {['入力のデータと Wafer を選び、補正の式・' ...
                '回帰を決めてから「補正を計算する」を押してください。']});
            place(c.highOrderMessage, 1, 1);
            outputs = uitabgroup(right, 'SelectionChangedFcn', @(~, event) app.onHighOrderOutputChanged(event));
            place(outputs, 2, 1);
            c.highOrderOutputs = outputs;
            termTab = uitab(outputs, 'Title', '使う項と VIF');
            termGrid = uigridlayout(termTab, [2, 1], 'RowHeight', {'1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            c.highOrderTermTable = uitable(termGrid, 'ColumnName', {'使う', '式', 'k', '項', '次数', 'VIF（全項）', ...
                'VIF（使う項）'}, 'ColumnFormat', {'logical', 'char', 'char', 'char', 'numeric', 'char', 'char'}, ...
                'ColumnEditable', [true, false, false, false, false, false, false], 'RowName', {}, ...
                'ColumnWidth', {50, 50, 56, 90, 56, 130, 130}, 'Data', cell(0, 7), ...
                'CellEditCallback', @(~, event) app.onHighOrderTermEdited(event), 'Tooltip', ['VIF（全項）：式のすべての項で' ...
                '求めた VIF。VIF（使う項）：「使う」の項だけで求めた VIF（10 を超えると、ほかの項と似ていて係数が不安定）。' ...
                '∞ は点の配置では決まらない項。']);
            c.highOrderVifInfo = label(termGrid, '', 2, 1);
            c.highOrderVifInfo.FontColor = app.Palette.muted;
            c.highOrderVifInfo.UserData = "muted";
            summaryTab = uitab(outputs, 'Title', '補正の評価');
            c.highOrderSummaryTab = summaryTab;
            summaryGrid = uigridlayout(summaryTab, [2, 1], 'RowHeight', {'1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            c.highOrderSummaryTable = uitable(summaryGrid, 'RowName', {}, 'Data', table(), 'ColumnWidth', ...
                [{170, 40}, repmat({90}, 1, 6), repmat({70}, 1, 6)]);
            note = label(summaryGrid, ['[nm] の列は |平均|+3σ。高次補正と1次（k1〜k6）だけの補正の両方ができた点で比べます' ...
                '（1次だけの補正にも、同じ損失関数と Wafer 成分を使う）。改善 = 1次だけ − 高次補正。予測の誤差：点を1つずつ' ...
                '抜いて求め直した補正で、抜いた点を予測したときの誤差（同じ点の残差は項を増やすほど小さく見えるので、' ...
                '項の選び方はこちらでも比べる）。重みを下げた点：ロバスト回帰で外れ値とみなして重みを下げた点の数。'], 2, 1);
            note.FontColor = app.Palette.muted;
            note.UserData = "muted";
            coefficientTab = uitab(outputs, 'Title', '補正値（k パラメータ）');
            coefficientGrid = uigridlayout(coefficientTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, ...
                'RowSpacing', 4);
            coefficientControls = uigridlayout(coefficientGrid, [1, 4], 'ColumnWidth', {'fit', 120, 'fit', '1x'}, ...
                'Padding', 0);
            label(coefficientControls, '式', 1, 1);
            c.highOrderCoefficientAxis = uidropdown(coefficientControls, 'Items', {'dx（X）', 'dy（Y）'}, 'ItemsData', ...
                {'dx', 'dy'}, 'ValueChangedFcn', @(~, ~) app.showHighOrderCoefficients());
            place(c.highOrderCoefficientAxis, 1, 2);
            label(coefficientControls, 'Wafer', 1, 3);
            c.highOrderCoefficientWafer = uidropdown(coefficientControls, 'Items', {'—'}, 'ItemsData', {1}, ...
                'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.showHighOrderCoefficients(), 'Tooltip', ...
                'Shot ごとの補正のとき、どの Wafer の Shot ごとの k を出すか（Shot で共通のときは、すべての Wafer を並べます）。');
            place(c.highOrderCoefficientWafer, 1, 4);
            c.highOrderCoefficientTable = uitable(coefficientGrid, 'RowName', {}, 'Data', table());
            place(c.highOrderCoefficientTable, 2, 1);
            c.highOrderCoefficientInfo = label(coefficientGrid, ['係数は mm の座標での値（定数 nm、1次 nm/mm = ppm、' ...
                'n 次 nm/mm^n）。x・y は Shot 内の座標、Wafer 成分の Xc・Yc は Shot 中心の座標。空欄は決まらない・' ...
                '補正しなかった組。'], 3, 1);
            c.highOrderCoefficientInfo.FontColor = app.Palette.muted;
            c.highOrderCoefficientInfo.UserData = "muted";
            mapTab = uitab(outputs, 'Title', 'マップ');
            c.highOrderMapTab = mapTab;
            mapGrid = uigridlayout(mapTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            mapControls = uigridlayout(mapGrid, [2, 6], 'ColumnWidth', {'fit', '1x', 'fit', '1x', 'fit', 'fit'}, ...
                'RowHeight', {'fit', 'fit'}, 'Padding', 0);
            onMap = @(~, ~) app.drawHighOrderMap();
            label(mapControls, 'Wafer', 1, 1);
            c.highOrderMapWafer = uidropdown(mapControls, 'Items', {'—'}, 'ItemsData', {1}, 'Enable', 'off', ...
                'ValueChangedFcn', onMap);
            place(c.highOrderMapWafer, 1, 2);
            label(mapControls, '図', 1, 3);
            c.highOrderMapView = uidropdown(mapControls, 'Items', {'Wafer 上', 'Shot を重ねる（Shot 内の座標）'}, ...
                'ItemsData', {'wafer', 'stack'}, 'ValueChangedFcn', onMap, 'Tooltip', ['Shot を重ねる：全 Shot の点を Shot 内の' ...
                '座標で1つの Shot に重ね、位置ごとの平均を濃い矢印で描きます（Shot 内に残った形を見るとき）。']);
            place(c.highOrderMapView, 1, 4);
            c.highOrderSaveFigure = uibutton(mapControls, 'Text', '図を画像で保存…', ...
                'ButtonPushedFcn', @(~, ~) app.saveFigureWithDialog("highOrder", 'shot_high_order_map.png'));
            place(c.highOrderSaveFigure, 1, 5);
            c.highOrderCopyFigure = uibutton(mapControls, 'Text', '図をコピー', 'Tooltip', app.COPY_TOOLTIP, ...
                'ButtonPushedFcn', @(source, ~) app.onCopyFigure("highOrder", source));
            place(c.highOrderCopyFigure, 1, 6);
            label(mapControls, '値', 2, 1);
            c.highOrderMapValue = uidropdown(mapControls, 'Items', {'高次補正の残差', '1次だけで補正した残差', ...
                '高次補正の予測の誤差（1点抜き）', '補正量', '補正前の値'}, 'ItemsData', {'residual', 'linear', 'loo', ...
                'correction', 'value'}, 'ValueChangedFcn', onMap, 'Tooltip', ['残差 = 値 − 補正量。補正量は高次補正' ...
                '（使う項と Wafer 成分）を当てはめた値。予測の誤差は、その点を抜いて求め直した補正で予測したときの誤差。']);
            place(c.highOrderMapValue, 2, 2);
            label(mapControls, '表示', 2, 3);
            c.highOrderMapMode = uidropdown(mapControls, 'Items', {'ベクトル（矢印）', 'X（色）', 'Y（色）'}, ...
                'ItemsData', {'vector', 'X', 'Y'}, 'ValueChangedFcn', onMap);
            place(c.highOrderMapMode, 2, 4);
            c.highOrderPanel = uipanel(mapGrid, 'BorderType', 'none');
            place(c.highOrderPanel, 2, 1);
            c.highOrderAxes = uiaxes(uigridlayout(c.highOrderPanel, [1, 1], 'Padding', 0));
            c.highOrderMapInfo = uilabel(mapGrid, 'WordWrap', 'on', 'Text', ...
                '「補正を計算する」を押すと、補正後の残差を描きます。', 'UserData', '「補正を計算する」を押すと、補正後の残差を描きます。');
            place(c.highOrderMapInfo, 3, 1);
            set([c.highOrderExport, c.highOrderSaveFigure, c.highOrderCopyFigure], 'Enable', 'off');
            app.Controls = mergeStruct(app.Controls, c);
            highOrderSettingsToControls(app);
            refreshHighOrderChoices(app);
        end

        function highOrderSettingsToControls(app)
            % 設定（settings.highOrder）を画面の欄に写す（設定ファイルを読んだ・初期設定に戻したときも呼ぶ）
            c = app.Controls;
            if ~isfield(c, 'highOrderMaker')
                return
            end
            try
                options = alignest.highOrderOptions(app.Settings);
            catch
                app.Settings.highOrder = alignest.defaultSettings().highOrder;   % 読めない値は初期値にする
                options = alignest.highOrderOptions(app.Settings);
            end
            source = app.Settings.highOrder;
            c.highOrderMaker.Value = char(options.maker);
            c.highOrderUnit.Value = char(options.unit);
            c.highOrderWaferOrder.Value = double(fieldOr(source, "waferOrder", options.waferOrder));
            c.highOrderVifThreshold.Value = options.vifThreshold;
            c.highOrderLoss.Value = char(options.loss);
            c.highOrderHuber.Value = options.huberTuning;
            c.highOrderL2.Value = options.l2;
            c.highOrderLambda.Value = options.lambda;
            updateHighOrderEnabled(app);
            refreshHighOrderTerms(app);
        end

        function readHighOrderControls(app)
            % 画面の欄を設定（settings.highOrder）に移す（使う項 excludedTerms は表の操作で変える）
            c = app.Controls;
            app.Settings.highOrder.maker = string(c.highOrderMaker.Value);
            app.Settings.highOrder.unit = string(c.highOrderUnit.Value);
            app.Settings.highOrder.waferOrder = c.highOrderWaferOrder.Value;
            app.Settings.highOrder.vifThreshold = c.highOrderVifThreshold.Value;
            app.Settings.highOrder.loss = string(c.highOrderLoss.Value);
            app.Settings.highOrder.huberTuning = c.highOrderHuber.Value;
            app.Settings.highOrder.l2 = c.highOrderL2.Value;
            app.Settings.highOrder.lambda = c.highOrderLambda.Value;
        end

        function updateHighOrderEnabled(app)
            c = app.Controls;
            c.highOrderWaferOrder.Enable = onOff(string(c.highOrderUnit.Value) == "common");
            c.highOrderHuber.Enable = onOff(string(c.highOrderLoss.Value) == "huber");
            c.highOrderLambda.Enable = onOff(c.highOrderL2.Value);
            c.highOrderMeasured.Enable = onOff(string(c.highOrderSource.Value) == "target");
        end

        function onHighOrderSettingsChanged(app)
            % 補正の式・単位・回帰の欄を変えたら設定に移し、項の表（式を変えたとき）と知らせを更新する
            c = app.Controls;
            readHighOrderControls(app);
            updateHighOrderEnabled(app);
            c.highOrderError.Text = '';
            try
                alignest.highOrderOptions(app.Settings);
            catch err
                c.highOrderError.Text = ['⚠ ', err.message];
            end
            refreshHighOrderTerms(app);
            markHighOrderStale(app);
        end

        function onHighOrderSourceChanged(app)
            refreshHighOrderChoices(app);
            markHighOrderStale(app);
        end

        function onHighOrderInputEdited(app)
            refreshHighOrderTerms(app);   % VIF は選んだ Wafer の点の配置で決まる
            markHighOrderStale(app);
        end

        function refreshHighOrderChoices(app)
            % 入力のデータに合わせて Wafer の一覧と説明を作り直す（前に選んでいた番号が残っていれば、そのまま選ぶ）
            c = app.Controls;
            if ~isfield(c, 'highOrderSource')
                return
            end
            source = string(c.highOrderSource.Value);
            labels = strings(1, 0);
            info = "";
            switch source
                case "data"
                    if ~isempty(app.Data)
                        labels = string({app.Data.units.label});
                        info = sprintf("「1. データの読み込み」の計測データ：%d Wafer。", numel(labels));
                    else
                        info = "「1. データの読み込み」で計測データを読み込んでください。";
                    end
                case "target"
                    if ~isempty(app.TargetRun)
                        labels = reshape(string(app.TargetRun.labels), 1, []);
                        info = sprintf("「6. 未知の座標の推定」の推定値：%d 組（Wafer × 学習データ）、手法 %s。", ...
                            numel(labels), app.TargetRun.method.label);
                    else
                        info = "「6. 未知の座標の推定」で推定してください（推定した点の値を使います）。";
                    end
                case "file"
                    if ~isempty(app.HighOrderFile)
                        file = app.HighOrderFile;
                        labels = string({file.data.units.label});
                        sheetText = "";
                        if file.info.sheet ~= ""
                            sheetText = "（シート「" + file.info.sheet + "」）";
                        end
                        info = sprintf("%s%s：%d 行・%d Wafer。", file.info.file, sheetText, file.info.rows, numel(labels));
                    else
                        info = "「Excel・CSV を読み込む…」で、Wafer ごとの dx・dy の値の表を読み込んでください。";
                    end
            end
            if isempty(labels)
                setHighOrderList(c.highOrderWafer, "—", {1});
            else
                setHighOrderList(c.highOrderWafer, labels, num2cell(1:numel(labels)));
            end
            c.highOrderInputInfo.Text = char(info);
            hasInput = ~isempty(labels);
            set([c.highOrderCompute, c.highOrderWafer, c.highOrderVifSelect], 'Enable', onOff(hasInput));   % VIF は点の配置で決まる
            updateHighOrderEnabled(app);
            refreshHighOrderTerms(app);
        end

        function refreshHighOrderTerms(app)
            % 補正の式の項の表（使うか・VIF）を作り直す。VIF は選んだ Wafer の点の Shot 内の座標で求める（入力が無ければ空欄）
            c = app.Controls;
            if ~isfield(c, 'highOrderTermTable')
                return
            end
            try
                options = alignest.highOrderOptions(app.Settings);
            catch
                return   % 設定の誤りは欄の下に出している
            end
            terms = alignest.highOrderTerms(options.maker, options.excludedTerms);
            try
                [local, valid] = highOrderLocal(app);
                [terms, info] = alignest.highOrderVif(terms, local, valid, options.vifThreshold);
                pointText = sprintf("VIF は Shot 内の位置 dx %d・dy %d か所（%d・%d 点）で求めました。", info.positions(1), ...
                    info.positions(2), info.points(1), info.points(2));
                if isempty(info.suggestedExcluded)
                    pointText = pointText + "「VIF で選ぶ」で外れる項はありません。";
                else
                    pointText = pointText + "「VIF で選ぶ」で外れる項：" + strjoin("k" + string(info.suggestedExcluded), "・") + "。";
                end
            catch
                [terms.vifAll, terms.vifUsed] = deal(nan(height(terms), 1));
                pointText = "入力のデータを選ぶと VIF を出します。";
            end
            n = height(terms);
            data = cell(n, 7);
            for k = 1:n
                data(k, :) = {terms.used(k), char(terms.axis(k)), sprintf('k%d', terms.k(k)), char(terms.term(k)), ...
                    terms.order(k), vifText(terms.vifAll(k)), vifText(terms.vifUsed(k))};
            end
            table_ = c.highOrderTermTable;
            table_.Data = data;
            table_.UserData = terms;
            removeStyle(table_);
            high = find(terms.used & terms.vifUsed >= options.vifThreshold);
            if ~isempty(high)
                addStyle(table_, uistyle('BackgroundColor', app.Palette.warning), 'row', high);
            end
            unused = find(~terms.used);
            if ~isempty(unused)
                addStyle(table_, uistyle('FontColor', app.Palette.muted), 'row', unused);
            end
            c.highOrderTermInfo.Text = sprintf('使う項：dx %d / %d・dy %d / %d（右の「使う項と VIF」で選べます）', ...
                nnz(terms.used & terms.axis == "dx"), nnz(terms.axis == "dx"), nnz(terms.used & terms.axis == "dy"), ...
                nnz(terms.axis == "dy"));
            c.highOrderVifInfo.Text = char(pointText);
        end

        function [local, valid] = highOrderLocal(app)
            % VIF に使う点：選んだ Wafer の点の Shot 内の座標と、dx・dy の値があるか（Shot の分からない点は除く）
            wafers = highOrderWafers(app);
            points = vertcat(wafers.points);
            local = [points.localX, points.localY];
            valid = [isfinite(points.valueX), isfinite(points.valueY)] & isfinite(points.shotNo);
        end

        function onHighOrderTermEdited(app, event)
            % 表の「使う」を変えたら設定に移す（k1〜k6 は外せないので戻す）
            terms = app.Controls.highOrderTermTable.UserData;
            row = event.Indices(1);
            if isempty(terms) || row > height(terms)
                return
            end
            if terms.protected(row) && ~event.NewData
                refreshHighOrderTerms(app);
                app.Controls.highOrderTermInfo.Text = 'k1〜k6 は外せません';
                app.Controls.highOrderTermInfo.Tooltip = 'k1〜k6（並進・倍率・回転）は補正の土台なので外せません。';
                return
            end
            setHighOrderTermUsed(app, terms.k(row), logical(event.NewData));
        end

        function onHighOrderVifSelect(app)
            runWithAlert(app, @() app.selectHighOrderTermsByVif(), "VIF で選べませんでした", ...
                "入力のデータと Wafer を選んでください（VIF は点の Shot 内の座標で求めます）。");
        end

        function [wafers, notes] = highOrderWafers(app)
            % 選んだ入力のデータ・Wafer を、alignest.shotHighOrder の入力（label・points・unit）にする。notes は知らせ
            c = app.Controls;
            source = string(c.highOrderSource.Value);
            selection = cell2mat(c.highOrderWafer.Value);
            notes = strings(0, 1);
            wafers = struct("label", {}, "points", {}, "unit", {});
            switch source
                case "data"
                    if isempty(app.Data)
                        error('alignest:noData', '先に「1. データの読み込み」で計測データを読み込んでください。');
                    end
                    if alignest.valueSpec(app.Settings.data).scalar
                        error('alignest:highOrderScalar', ['Shot 高次補正は X・Y の2成分（dx・dy）が要ります（1変数の推定の' ...
                            'データでは計算できません）。']);
                    end
                    for k = reshape(selection, 1, [])
                        unit = app.Data.units(k);
                        wafers(end + 1) = struct("label", unit.label, "points", alignest.highOrderUnitPoints(unit), ...
                            "unit", unit); %#ok<AGROW>
                    end
                case "target"
                    run = app.TargetRun;
                    if isempty(run)
                        error('alignest:noTargets', '先に「6. 未知の座標の推定」で推定してください。');
                    end
                    if alignest.valueSpec(app.Settings.data).scalar
                        error('alignest:highOrderScalar', ['Shot 高次補正は X・Y の2成分（dx・dy）が要ります（1変数の推定' ...
                            'では計算できません）。']);
                    end
                    [outside, noShot] = deal(0);
                    for k = reshape(selection, 1, [])
                        unit = app.Data.units(run.unitIndex(k));
                        measured = false(0, 1);
                        if c.highOrderMeasured.Value
                            measured = alignest.trainingMarks(unit, targetTraining(app, run.unitIndex(k), run.training(k)));
                        end
                        [points, info] = alignest.highOrderTargetPoints(unit, run.results{k}.table, measured);
                        wafers(end + 1) = struct("label", run.labels(k), "points", points, "unit", unit); %#ok<AGROW>
                        outside = outside + info.outsideWafer;
                        noShot = noShot + info.noShot;
                    end
                    if outside + noShot > 0
                        notes(end + 1) = sprintf(['未知の座標の点のうち、Wafer の外の点 %d 点と、どの Shot にも入らない点 %d 点は' ...
                            '使っていません。'], outside, noShot);
                    end
                otherwise
                    if isempty(app.HighOrderFile)
                        error('alignest:noHighOrderFile', '先に「Excel・CSV を読み込む…」で表を読み込んでください。');
                    end
                    for k = reshape(selection, 1, [])
                        unit = app.HighOrderFile.data.units(k);
                        wafers(end + 1) = struct("label", unit.label, "points", alignest.highOrderUnitPoints(unit), ...
                            "unit", unit); %#ok<AGROW>
                    end
            end
            if isempty(wafers)
                error('alignest:highOrderInput', 'Wafer を1つ以上選んでください。');
            end
        end

        function text = highOrderSourceText(app, source)
            switch source
                case "data"
                    text = "「1. データの読み込み」の計測データ（" + app.FilePath + "）";
                case "target"
                    text = "「6. 未知の座標の推定」の推定値（手法 " + app.TargetRun.method.label + "）";
                    if app.HighOrderRun.measured
                        text = text + "と、学習に使った Mark の実測値";
                    end
                otherwise
                    text = "Excel・CSV（" + app.HighOrderFile.info.file + "）";
            end
        end

        function showHighOrderRun(app)
            % 補正の評価・補正値・マップ・メッセージを出す
            run = app.HighOrderRun;
            c = app.Controls;
            result = run.result;
            s = result.summary;
            skippedName = "補正しなかった Wafer";
            if result.options.unit == "shot"
                skippedName = "補正しなかった Shot";
            end
            % 大事な数（|平均|+3σ）を左に、点の数などを右に並べる（列が多く、狭い窓では右がスクロールになるため）
            c.highOrderSummaryTable.Data = table(s.wafer, s.axis, round(s.before, 3), round(s.linear, 3), ...
                round(s.highOrder, 3), round(s.improvement, 3), round(s.looLinear, 3), round(s.looHighOrder, 3), s.n, ...
                s.nCorrected, s.shots, s.skipped, s.downweighted, round(s.rmsHighOrder, 3), 'VariableNames', ["Wafer", ...
                "軸", "補正前 [nm]", "1次だけ [nm]", "高次補正 [nm]", "改善 [nm]", "予測の誤差：1次だけ [nm]", ...
                "予測の誤差：高次補正 [nm]", "点の数", "比べた点", "Shot の数", skippedName, "重みを下げた点", ...
                "高次補正の RMS [nm]"]);
            removeStyle(c.highOrderSummaryTable);
            totals = find(s.wafer == "すべての Wafer");
            if ~isempty(totals)
                addStyle(c.highOrderSummaryTable, uistyle('FontWeight', 'bold'), 'row', totals);
            end
            labels = string({run.wafers.label});
            setChoices(c.highOrderCoefficientWafer, labels, num2cell(1:numel(labels)));
            c.highOrderCoefficientWafer.Enable = onOff(result.options.unit == "shot");
            setChoices(c.highOrderMapWafer, labels, num2cell(1:numel(labels)));
            c.highOrderMapWafer.Enable = 'on';
            c.highOrderExport.Enable = 'on';
            showHighOrderCoefficients(app);
            drawHighOrderMap(app);
            showHighOrderMessages(app);
        end

        function showHighOrderCoefficients(app)
            % 補正値の表：行は Wafer（Shot で共通）か Shot（Shot ごと。選んだ Wafer）、列は項（k と Wafer 成分）
            run = app.HighOrderRun;
            c = app.Controls;
            if isempty(run)
                c.highOrderCoefficientTable.Data = table();
                return
            end
            coefficients = run.result.coefficients;
            coefficients = coefficients(coefficients.axis == string(c.highOrderCoefficientAxis.Value), :);
            perShot = run.result.options.unit == "shot";
            if perShot
                position = min(max(c.highOrderCoefficientWafer.Value, 1), numel(run.wafers));
                coefficients = coefficients(coefficients.wafer == string(run.wafers(position).label), :);
                keys = coefficients.shotNo;
                allKeys = unique(run.result.points.shotNo(run.result.points.wafer == string(run.wafers(position).label) & ...
                    isfinite(run.result.points.shotNo)));
                keyName = "shotNo";
            else
                keys = coefficients.wafer;
                allKeys = reshape(string({run.wafers.label}), [], 1);
                keyName = "Wafer";
            end
            terms = alignest.highOrderTerms(run.result.options.maker, run.result.options.excludedTerms);
            terms = terms(terms.axis == string(c.highOrderCoefficientAxis.Value) & terms.used, :);
            names = [ "k" + string(terms.k) + "（" + terms.term + "）"; ...
                unique(coefficients.term(coefficients.component == "Wafer 成分"), 'stable')];
            values = strings(numel(allKeys), numel(names));
            [~, row] = ismember(keys, allKeys);
            [~, column] = ismember(coefficients.term, names);
            use = row > 0 & column > 0;
            text = compose("%.4g", coefficients.value(use));
            notes = coefficients.note(use);
            text(contains(notes, "決まらない")) = "（決まらない）";
            text(contains(notes, "値が変わらない")) = "0（定数と同じ）";
            values(sub2ind(size(values), row(use), column(use))) = text;
            shown = array2table(values, 'VariableNames', cellstr(names));
            shown = [table(string(allKeys), 'VariableNames', cellstr(keyName)), shown];
            c.highOrderCoefficientTable.Data = shown;
        end

        function showHighOrderMessages(app)
            run = app.HighOrderRun;
            c = app.Controls;
            if isempty(run)
                return
            end
            stale = staleHighOrderText(app);
            messages = run.result.messages;
            if stale ~= ""
                messages = [stale; messages];
            end
            c.highOrderMessage.Value = cellstr(messages);
            warn = stale ~= "" || any(startsWith(messages, "⚠"));
            c.highOrderMessage.FontColor = ternary(warn, app.Palette.error, app.Palette.text);
        end

        function text = staleHighOrderText(app)
            % 計算した後に設定・入力を変えていれば、その知らせ（変えていなければ ""）
            run = app.HighOrderRun;
            text = "";
            if isempty(run)
                return
            end
            c = app.Controls;
            if ~isequaln(run.settings, app.Settings.highOrder) || run.source ~= string(c.highOrderSource.Value) || ...
                    ~isequal(run.selection, c.highOrderWafer.Value) || run.measured ~= c.highOrderMeasured.Value
                text = "⚠ 設定・入力を変えました。「補正を計算する」で計算し直してください（下は前の計算の結果）。";
            end
        end

        function markHighOrderStale(app)
            % 設定・入力を変えたら、前の結果が古いことをメッセージに出す（結果は残す）
            if ~isempty(app.HighOrderRun)
                showHighOrderMessages(app);
            end
        end

        function highOrderInputChanged(app, kind)
            % 「1. データの読み込み」のデータ・「6. 未知の座標の推定」の推定値・読み込んだ表が変わったら、それを入力にした結果を
            % 消す（kind = "data"：計測データ、"target"：推定値、"file"：表。計測データが変わると推定値も消えるので、どちらも消す）
            c = app.Controls;
            if ~isfield(c, 'highOrderSource')
                return
            end
            run = app.HighOrderRun;
            if ~isempty(run) && (run.source == kind || (kind == "data" && run.source == "target"))
                clearHighOrderRun(app);
            end
            refreshHighOrderChoices(app);
        end

        function clearHighOrderRun(app)
            app.HighOrderRun = [];
            c = app.Controls;
            c.highOrderSummaryTable.Data = table();
            removeStyle(c.highOrderSummaryTable);
            c.highOrderCoefficientTable.Data = table();
            setChoices(c.highOrderCoefficientWafer, "—", {1});
            setChoices(c.highOrderMapWafer, "—", {1});
            set([c.highOrderCoefficientWafer, c.highOrderMapWafer, c.highOrderExport], 'Enable', 'off');
            drawHighOrderMap(app);
            c.highOrderMessage.Value = {'入力のデータと Wafer を選び、補正の式・回帰を決めてから「補正を計算する」を押してください。'};
            c.highOrderMessage.FontColor = app.Palette.text;
        end

        function onHighOrderOutputChanged(app, event)
            % 「マップ」を開いたら描き直す（見えていないタブに描いた図は、開いたときに一部しか描かれないことがあるため）
            if event.NewValue == app.Controls.highOrderMapTab && ~isempty(app.HighOrderRun)
                try
                    drawHighOrderMap(app);
                catch
                    % 描き直せなくても前の図のままにする（表示を変えるだけなので止めない）
                end
            end
        end

        function onComputeHighOrder(app)
            app.Controls.highOrderError.Text = '';
            runWithAlert(app, @() app.computeHighOrder(), "Shot 高次補正を計算できませんでした", ...
                ['入力のデータと Wafer、補正の式の設定を確かめてください。Shot ごとのときは、1つの Shot に点が足りているか' ...
                '（「VIF で選ぶ」で項を減らす・L2 正則化をかける）を確かめてください。']);
        end

        function onLoadHighOrderFile(app)
            [fileName, folder] = uigetfile({'*.xlsx;*.xlsm;*.xls;*.csv', 'Excel・CSV (*.xlsx, *.xlsm, *.xls, *.csv)'}, ...
                'Shot 高次補正の入力にする表を選ぶ');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.loadHighOrderFile(fullfile(folder, fileName)), "表を読み込めませんでした", ...
                ['1行目に Xmm・Ymm・markXmm・markYmm・measX・measY（dx・dy でもよい）の見出しがあるか、数の欄に文字が' ...
                '入っていないかを確かめてください。']);
        end

        function onExportHighOrder(app)
            [fileName, folder] = uiputfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, '結果を書き出す', 'shot_high_order.xlsx');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            if runWithAlert(app, @() app.exportHighOrderTo(target), "書き出せませんでした", ...
                    "同じ名前のファイルを Excel で開いていれば閉じて、もう一度試してください。")
                uialert(app.Figure, sprintf('書き出しました：%s', target), '書き出しました', 'Icon', 'success');
            end
        end
    end
end

% ================= このファイルだけで使う小さな関数 =================
function text = vifText(value)
% 表に出す VIF（NaN は「—」、決まらない項は「∞」）
if isnan(value)
    text = '—';
elseif isinf(value)
    text = '∞（決まらない）';
else
    text = sprintf('%.3g', value);
end
end

function value = meanPlus3Sigma(values)
% |平均| + 3σ（σ は不偏標準偏差）。点が2点未満なら NaN
values = values(isfinite(values));
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end

function setHighOrderList(listbox, items, itemsData)
% 複数選べる一覧の選択肢を変える（前に選んでいた番号のうち残っているものは選んだまま。無ければ最初の1つを選ぶ）
previous = listbox.Value;
listbox.Items = cellstr(items);
listbox.ItemsData = itemsData;
kept = previous(cellfun(@(value) any(cellfun(@(item) isequal(item, value), itemsData)), previous));
if isempty(kept)
    kept = itemsData(1);
end
listbox.Value = kept;
end
