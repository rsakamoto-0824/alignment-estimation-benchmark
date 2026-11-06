classdef (Abstract) HighOrderSweepTab < appui.Core
    %HIGHORDERSWEEPTAB 「7. Shot高次補正」の「λ・c のスイープ」：正則化の強さ λ・Huber の c を、範囲（開始・終了）と評価数で
    %   変えて計算し、補正残差（当てはめた残差と 1点抜きの予測の誤差）の推移を図と表に出す（alignest.sweepHighOrder）。
    %   基準（最小二乗・正則化なし）を図に描き、Wafer 間のばらつきをエラーバーで描ける。途中で一時中断し、続きから再開できる。
    %   X・Y それぞれで 1点抜きの誤差が最も小さい値を、左の設定にできる。入力のデータ・補正の計算は HighOrderTab.m。
    %   AlignmentEstimationApp（画面の本体）の一部で、ほかのタブの関数も同じように呼べる。

    properties (Constant, Access = {?appui.Core})
        SWEEP_LAMBDA_RANGE = [0, 1, 11]          % λ の初めの範囲（開始・終了・評価数）
        SWEEP_TUNING_RANGE = [0, 3, 13]          % Huber の c の初めの範囲（開始・終了・評価数。0 は LAD）
        SWEEP_MAX_VALUES = 101                   % λ・c それぞれの評価数の上限
        SWEEP_MAX_TICKS = 12                     % λ と c の組み合わせの図で、軸に名前を付ける値の数の上限
    end

    methods
        function sweep = sweepHighOrderParameters(app, parameter, options)
            %SWEEPHIGHORDERPARAMETERS 「スイープを実行する」：今の入力のデータ・Wafer・設定で、λ・c を範囲と評価数で変えて計算し、
            %   補正残差の推移を図と表に出す（alignest.sweepHighOrder）。parameter："lambda"・"huberTuning"・"both"（λ と c の
            %   すべての組み合わせ）。名前と値の組で欄を変えられる（省略すると画面の欄のまま）：lambdaRange（[開始, 終了, 評価数]）・
            %   lambdaScale（"linear"：等間隔・"log"：対数で等間隔）・tuningRange（[開始, 終了, 評価数]。等間隔。0 は LAD）・
            %   progressFcn（progressFcn(済んだ数, 全体の数, 説明) が false なら一時中断する。進み具合の窓を出さずに動かすとき）。
            %   例：app.sweepHighOrderParameters("lambda", lambdaRange=[0.01, 1, 5], lambdaScale="log")
            arguments
                app
                parameter (1, 1) string = ""
                options.lambdaRange (1, 3) double
                options.lambdaScale (1, 1) string
                options.tuningRange (1, 3) double
                options.progressFcn = []
            end
            c = app.Controls;
            if parameter ~= ""
                c.highOrderTuneParameter.Value = char(parameter);
            end
            if isfield(options, "lambdaRange")
                set([c.highOrderTuneLambdaStart, c.highOrderTuneLambdaEnd, c.highOrderTuneLambdaPoints], ...
                    {'Value'}, num2cell(options.lambdaRange(:)));
            end
            if isfield(options, "lambdaScale")
                c.highOrderTuneLambdaScale.Value = char(options.lambdaScale);
            end
            if isfield(options, "tuningRange")
                set([c.highOrderTuneTuningStart, c.highOrderTuneTuningEnd, c.highOrderTuneTuningPoints], ...
                    {'Value'}, num2cell(options.tuningRange(:)));
            end
            refreshHighOrderSweepCount(app);
            readHighOrderControls(app);
            alignest.highOrderOptions(app.Settings);   % 設定の誤りを先に知らせる
            [lambdas, tunings] = highOrderSweepValues(app);
            sweep = runHighOrderSweep(app, lambdas, tunings, [], options.progressFcn);
        end

        function sweep = resumeHighOrderSweep(app, progressFcn)
            %RESUMEHIGHORDERSWEEP 「続きから再開」：一時中断したスイープの残りの値を計算する（同じ入力・設定のときだけ）。
            %   progressFcn（省略可）：sweepHighOrderParameters と同じ。
            if nargin < 2
                progressFcn = [];
            end
            previous = app.HighOrderSweep;
            if isempty(previous) || ~previous.cancelled
                error('alignest:highOrderSweep', '続きから再開できるスイープがありません。');
            end
            readHighOrderControls(app);
            if ~isequaln(previous.snapshot, highOrderSweepSnapshot(app)) || ...
                    ~isequaln(previous.regression, highOrderSweepRegression(app))
                error('alignest:highOrderSweep', ['一時中断の後に入力・Wafer・設定を変えたので、続きから再開できません。' ...
                    '「スイープを実行する」で計算し直してください。']);
            end
            sweep = runHighOrderSweep(app, previous.request.lambda, previous.request.huberTuning, previous, progressFcn);
        end

        function data = drawHighOrderSweep(app, statistic)
            %DRAWHIGHORDERSWEEP 「λ・c のスイープ」の図と表を出す。statistic："meanPlus3Sigma"・"p95"・"median"・"rms"
            %   （省略すると画面の選択）。図は X（dx の式）と Y（dy の式）を左右に並べ、λ か c を変えたときは、当てはめた残差
            %   （実線）と 1点抜きの予測の誤差（破線）の推移と、1点抜きの誤差が最も小さい値（★）。λ と c の組み合わせのときは、
            %   1点抜きの誤差の色の図。data は表に出した値（値の組ごとの行）。
            c = app.Controls;
            if nargin >= 2
                c.highOrderTuneStatistic.Value = char(statistic);
            end
            data = table();
            for ax = c.highOrderTuneAxes
                cla(ax, 'reset');
                legend(ax, 'off');
                colorbar(ax, 'off');
            end
            sweep = app.HighOrderSweep;
            if isempty(sweep)
                c.highOrderTuneTable.Data = table();
                c.highOrderTuneInfo.Text = c.highOrderTuneInfo.UserData;
                return
            end
            statistic = string(c.highOrderTuneStatistic.Value);
            [fitName, looName, statisticLabel] = sweepColumns(statistic);
            rows = sweep.table(sweep.table.axis ~= "", :);
            axisNames = ["X", "Y"];
            formulas = ["dx", "dy"];
            [parameterName, parameterLabel] = parameterOf(sweep.parameter);
            for k = 1:2
                ax = c.highOrderTuneAxes(k);
                mine = rows(rows.axis == axisNames(k), :);
                titleText = sprintf("%s（%s の式）", axisNames(k), formulas(k));
                if sweep.parameter == "both"
                    drawSweepGrid(ax, mine, looName, titleText + "：1点抜きの予測の誤差 " + statisticLabel, ...
                        app.SWEEP_MAX_TICKS);
                else
                    drawSweepLines(ax, mine, parameterName, parameterLabel, fitName, looName, ...
                        sweep.parameter == "lambda" && sweep.lambdaScale == "log", sweep.perWafer, ...
                        string(c.highOrderTuneErrorBar.Value), axisBaseline(sweep, axisNames(k)));
                    ylabel(ax, statisticLabel + " [nm]");
                    title(ax, titleText, 'Interpreter', 'none');
                    legend(ax, 'Location', 'northoutside', 'NumColumns', 2, 'Box', 'off', 'Interpreter', 'none');
                end
                grid(ax, 'on');
                box(ax, 'on');
                styleAxes(app, ax, app.AXES_FONT_SIZE);
            end
            % 表：値の組ごとに、X・Y の当てはめた残差と 1点抜きの誤差（1行目は基準）
            data = sweepTable(sweep, fitName, looName);
            c.highOrderTuneTable.Data = data;
            removeStyle(c.highOrderTuneTable);
            [best, bestText] = bestOf(sweep, looName, statisticLabel);
            for chosen = best
                row = find(data.("λ") == chosen.lambda & data.("c") == chosen.huberTuning, 1);
                addStyle(c.highOrderTuneTable, uistyle('FontWeight', 'bold'), 'row', row);
            end
            c.highOrderTuneResume.Enable = onOff(sweep.cancelled);
            info = sprintf("%d / %d 通りを %.0f 秒で計算しました%s。", sweep.nRuns, sweep.total, sweep.seconds, ...
                ternary(sweep.cancelled, "（一時中断。「続きから再開」で続けます）", "")) + bestText + baselineText(sweep, looName);
            if ~isequaln(sweep.snapshot, highOrderSweepSnapshot(app))
                info = "⚠ スイープの後に入力・Wafer・設定を変えました。" + ...
                    "スイープし直してください（下は前の結果）。" + info;
            end
            c.highOrderTuneInfo.Text = char(info);
        end

        function best = applyHighOrderSweepBest(app)
            %APPLYHIGHORDERSWEEPBEST 「最もよい値を使う」：図の値の 1点抜きの予測の誤差が最も小さい λ・c を、X・Y それぞれ左の設定に
            %   する（λ を変えたとき、正則化がなしの軸は L2 に、c を変えたとき、損失関数を Huber に。c = 0 は LAD にする）。
            %   best は軸ごとの使った値（[X, Y] の構造体）。
            sweep = app.HighOrderSweep;
            if isempty(sweep)
                error('alignest:highOrderSweep', '先に「スイープを実行する」を押してください。');
            end
            [~, looName] = sweepColumns(string(app.Controls.highOrderTuneStatistic.Value));
            best = bestOf(sweep, looName, "");
            if isempty(best)
                error('alignest:highOrderSweep', '1点抜きの予測の誤差を求められた値がありません。');
            end
            changes = struct();
            if any(sweep.parameter == ["lambda", "both"])
                changes.lambda = [best.lambda];
                changes.regularization = sweep.regularization;
            end
            if any(sweep.parameter == ["huberTuning", "both"])
                tuning = [best.huberTuning];
                loss = sweep.loss;
                lad = tuning == 0;
                loss(lad) = "lad";
                current = alignest.highOrderOptions(app.Settings).huberTuning;
                tuning(lad) = current(lad);
                changes.huberTuning = tuning;
                changes.loss = loss;
            end
            arguments_ = namedArguments(changes);
            setHighOrderSettings(app, arguments_{:});
            drawHighOrderSweep(app);
            app.Controls.highOrderTuneInfo.Text = char("左の設定を X は " + valueText(best(1), sweep.parameter) + "、Y は " + ...
                valueText(best(2), sweep.parameter) + " にしました。「補正を計算する」で計算し直してください。" + ...
                string(app.Controls.highOrderTuneInfo.Text));
        end
    end

    methods (Access = {?appui.Core})
        function buildHighOrderSweepTab(app, outputs)
            % 「λ・c のスイープ」のタブ：スイープする値・範囲と評価数・図の値・実行と再開と最もよい値を使うボタン、結果の図と表
            c = struct();
            tab = uitab(outputs, 'Title', 'λ・c のスイープ');
            c.highOrderTuneTab = tab;
            grid = uigridlayout(tab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            % 1行目：変える値・図の値、2行目：λ の範囲と評価数、3行目：c の範囲と評価数と計算する数、4行目：ボタン
            % （ボタンを別の行にして、狭い窓でも欄が切れないようにする）
            controls = uigridlayout(grid, [4, 8], 'ColumnWidth', {'fit', 64, 'fit', 64, 'fit', 64, 'fit', '1x'}, ...
                'RowHeight', {'fit', 'fit', 'fit', 'fit'}, 'Padding', 0, 'RowSpacing', 4);
            onRange = @(~, ~) app.refreshHighOrderSweepCount();
            label(controls, '変える値', 1, 1);
            c.highOrderTuneParameter = uidropdown(controls, 'Items', {'正則化の強さ λ', 'Huber の c', ...
                'λ と c の組み合わせ'}, 'ItemsData', {'lambda', 'huberTuning', 'both'}, 'ValueChangedFcn', onRange, ...
                'Tooltip', ['λ：左の正則化の種類（なしなら L2）とかける次数のまま、強さだけを変えます。c：損失関数を Huber にして、' ...
                'c だけを変えます。組み合わせ：λ と c のすべての組み合わせを計算します（数が多いと時間がかかります）。']);
            place(c.highOrderTuneParameter, 1, [2, 4]);
            label(controls, '図の値', 1, 5);
            c.highOrderTuneStatistic = uidropdown(controls, 'Items', {'|平均|+3σ', '|残差| 95% 点', '|残差| 中央値', ...
                'RMS'}, 'ItemsData', {'meanPlus3Sigma', 'p95', 'median', 'rms'}, ...
                'ValueChangedFcn', @(~, ~) app.drawHighOrderSweep());
            place(c.highOrderTuneStatistic, 1, [6, 8]);
            % λ の範囲と評価数
            label(controls, 'λ：開始', 2, 1);
            c.highOrderTuneLambdaStart = uieditfield(controls, 'numeric', 'Value', app.SWEEP_LAMBDA_RANGE(1), ...
                'Limits', [0, Inf], 'ValueChangedFcn', onRange);
            place(c.highOrderTuneLambdaStart, 2, 2);
            label(controls, '終了', 2, 3);
            c.highOrderTuneLambdaEnd = uieditfield(controls, 'numeric', 'Value', app.SWEEP_LAMBDA_RANGE(2), ...
                'Limits', [0, Inf], 'ValueChangedFcn', onRange);
            place(c.highOrderTuneLambdaEnd, 2, 4);
            label(controls, '評価数', 2, 5);
            c.highOrderTuneLambdaPoints = uieditfield(controls, 'numeric', 'Value', app.SWEEP_LAMBDA_RANGE(3), ...
                'Limits', [1, app.SWEEP_MAX_VALUES], 'RoundFractionalValues', 'on', 'ValueChangedFcn', onRange);
            place(c.highOrderTuneLambdaPoints, 2, 6);
            c.highOrderTuneLambdaScale = uidropdown(controls, 'Items', {'等間隔', '対数で等間隔'}, ...
                'ItemsData', {'linear', 'log'}, 'ValueChangedFcn', onRange, 'Tooltip', ...
                '等間隔：開始から終了までを評価数で等しく分けます。対数で等間隔：桁をまたいで比べます（開始は 0 より大きく）。');
            place(c.highOrderTuneLambdaScale, 2, [7, 8]);
            % c の範囲と評価数
            label(controls, 'c：開始', 3, 1);
            c.highOrderTuneTuningStart = uieditfield(controls, 'numeric', 'Value', app.SWEEP_TUNING_RANGE(1), ...
                'Limits', [0, Inf], 'ValueChangedFcn', onRange, 'Tooltip', 'c = 0 は LAD で計算します。');
            place(c.highOrderTuneTuningStart, 3, 2);
            label(controls, '終了', 3, 3);
            c.highOrderTuneTuningEnd = uieditfield(controls, 'numeric', 'Value', app.SWEEP_TUNING_RANGE(2), ...
                'Limits', [0, Inf], 'ValueChangedFcn', onRange);
            place(c.highOrderTuneTuningEnd, 3, 4);
            label(controls, '評価数', 3, 5);
            c.highOrderTuneTuningPoints = uieditfield(controls, 'numeric', 'Value', app.SWEEP_TUNING_RANGE(3), ...
                'Limits', [1, app.SWEEP_MAX_VALUES], 'RoundFractionalValues', 'on', 'ValueChangedFcn', onRange);
            place(c.highOrderTuneTuningPoints, 3, 6);
            c.highOrderTuneCount = uilabel(controls, 'Text', '', 'WordWrap', 'on');
            place(c.highOrderTuneCount, 3, [7, 8]);
            buttons = uigridlayout(controls, [1, 5], 'ColumnWidth', {'fit', 'fit', 'fit', 'fit', '1x'}, 'Padding', 0);
            place(buttons, 4, [1, 8]);
            c.highOrderTuneRun = primaryButton(app, buttons, 'スイープを実行する', @(~, ~) app.onRunHighOrderSweep());
            c.highOrderTuneResume = uibutton(buttons, 'Text', '続きから再開', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onResumeHighOrderSweep(), 'Tooltip', ['進み具合の窓の「一時中断」で止めた' ...
                'スイープの続きを計算します（入力・設定を変えていないとき）。']);
            c.highOrderTuneApply = uibutton(buttons, 'Text', '最もよい値を使う', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onApplyHighOrderSweepBest(), 'Tooltip', ['X・Y それぞれ、図の値の 1点抜きの' ...
                '予測の誤差が最も小さい λ・c を、左の設定にします。']);
            label(buttons, 'エラーバー', 1, 4);
            [barKinds, barLabels] = alignest.errorBarKinds();
            c.highOrderTuneErrorBar = uidropdown(buttons, 'Items', cellstr(plainLabels(barLabels)), 'ItemsData', cellstr(barKinds), ...
                'ValueChangedFcn', @(~, ~) app.drawHighOrderSweep(), 'Tooltip', ['Wafer ごとに求めた図の値の、Wafer 間の' ...
                'ばらつきを描きます（Wafer が2枚以上のとき）。']);
            place(c.highOrderTuneErrorBar, 1, 5);
            % 結果：図と表（中のタブで切り替える）
            results = uitabgroup(grid, 'SelectionChangedFcn', @(~, ~) app.drawHighOrderSweep());
            place(results, 2, 1);
            c.highOrderTuneResults = results;
            chartTab = uitab(results, 'Title', '図');
            chartGrid = uigridlayout(chartTab, [1, 2], 'Padding', 4, 'ColumnSpacing', 8);
            c.highOrderTuneAxes = [uiaxes(chartGrid), uiaxes(chartGrid)];
            tableTab = uitab(results, 'Title', '表');
            c.highOrderTuneTable = uitable(uigridlayout(tableTab, [1, 1], 'Padding', 4), 'RowName', {}, ...
                'Data', table());
            emptyText = '「スイープを実行する」で補正残差の推移を描きます。';
            c.highOrderTuneInfo = uilabel(grid, 'WordWrap', 'on', 'Text', emptyText, 'UserData', emptyText);
            place(c.highOrderTuneInfo, 3, 1);
            app.Controls = mergeStruct(app.Controls, c);
            refreshHighOrderSweepCount(app);
        end

        function refreshHighOrderSweepCount(app)
            % スイープする値の欄の使える・使えないと、計算する値の数（誤りは ⚠）
            c = app.Controls;
            parameter = string(c.highOrderTuneParameter.Value);
            useLambda = any(parameter == ["lambda", "both"]);
            useTuning = any(parameter == ["huberTuning", "both"]);
            set([c.highOrderTuneLambdaStart, c.highOrderTuneLambdaEnd, c.highOrderTuneLambdaPoints, ...
                c.highOrderTuneLambdaScale], 'Enable', onOff(useLambda));
            set([c.highOrderTuneTuningStart, c.highOrderTuneTuningEnd, c.highOrderTuneTuningPoints], ...
                'Enable', onOff(useTuning));
            try
                [lambdas, tunings] = highOrderSweepValues(app);
                parts = strings(1, 0);
                if useLambda
                    parts(end + 1) = sprintf("λ %d 通り（%s）", numel(lambdas), rangeText(lambdas));
                end
                if useTuning
                    parts(end + 1) = sprintf("c %d 通り（%s）", numel(tunings), rangeText(tunings));
                end
                total = max(numel(lambdas), 1) * max(numel(tunings), 1);
                c.highOrderTuneCount.Text = char(strjoin(parts, " × ") + sprintf("：%d 回計算します。", total));
                c.highOrderTuneCount.FontColor = app.Palette.text;
            catch err
                c.highOrderTuneCount.Text = char("⚠ " + err.message);
                c.highOrderTuneCount.FontColor = app.Palette.error;
            end
        end

        function [lambdas, tunings] = highOrderSweepValues(app)
            % 欄の範囲と評価数から、スイープする λ・c の値（スイープしない方は空）
            c = app.Controls;
            parameter = string(c.highOrderTuneParameter.Value);
            [lambdas, tunings] = deal(zeros(1, 0));
            if any(parameter == ["lambda", "both"])
                lambdas = sweepValues([c.highOrderTuneLambdaStart.Value, c.highOrderTuneLambdaEnd.Value, ...
                    c.highOrderTuneLambdaPoints.Value], string(c.highOrderTuneLambdaScale.Value), "λ");
            end
            if any(parameter == ["huberTuning", "both"])
                tunings = sweepValues([c.highOrderTuneTuningStart.Value, c.highOrderTuneTuningEnd.Value, ...
                    c.highOrderTuneTuningPoints.Value], "linear", "c");
            end
        end

        function snapshot = highOrderSweepSnapshot(app)
            % スイープの後に変えたかを見る入力・設定（スイープする λ・c と、それに合わせて変える正則化の種類・損失関数、
            % 計算に使わない保存した項の組み合わせは除く）
            settings = app.Settings.highOrder;
            settings = rmfield(settings, intersect(fieldnames(settings), {'lambda', 'huberTuning', 'regularization', ...
                'loss', 'termSets', 'l2'}));
            snapshot = struct("settings", settings, "source", string(app.Controls.highOrderSource.Value), ...
                "selection", {app.Controls.highOrderWafer.Value}, "measured", app.Controls.highOrderMeasured.Value);
        end

        function regression = highOrderSweepRegression(app)
            % 続きから再開できるかを見る回帰の設定（スイープの値を決める左の欄）
            regression = rmfield(app.Settings.highOrder, intersect(fieldnames(app.Settings.highOrder), {'termSets', 'l2'}));
        end

        function sweep = runHighOrderSweep(app, lambdas, tunings, previous, progressFcn)
            % スイープを計算して結果を出す（previous があれば、その続き）。進み具合の窓の「一時中断」か progressFcn で止める
            c = app.Controls;
            wafers = highOrderWafers(app);
            if isempty(wafers)
                error('alignest:highOrderInput', 'スイープする入力のデータと Wafer を選んでください。');
            end
            dialog = [];
            if app.Figure.Visible == "on"
                dialog = appui.ProgressWindow(app.Figure, "λ・c のスイープ", "計算を始めています…", app.Palette, ...
                    app.FontSize, "一時中断");
            end
            cleanup = onCleanup(@() closeDialog(dialog));
            started = tic;
            firstRun = 0;
            secondsBefore = 0;
            state = [];
            scale = string(c.highOrderTuneLambdaScale.Value);
            if ~isempty(previous)
                firstRun = previous.nRuns;
                secondsBefore = previous.seconds;
                state = previous.state;
                scale = previous.lambdaScale;
            end
            sweep = alignest.sweepHighOrder(wafers, app.Settings, lambda=lambdas, huberTuning=tunings, resume=state, ...
                progressFcn=@(done, total, message) reportProgress(done, total, message));
            sweep.seconds = secondsBefore + toc(started);
            sweep.lambdaScale = scale;
            sweep.request = struct("lambda", lambdas, "huberTuning", tunings);
            sweep.snapshot = highOrderSweepSnapshot(app);
            sweep.regression = highOrderSweepRegression(app);
            app.HighOrderSweep = sweep;
            c.highOrderTuneApply.Enable = 'on';
            c.highOrderOutputs.SelectedTab = c.highOrderTuneTab;
            drawHighOrderSweep(app);

            function continueRun = reportProgress(done, total, message)
                continueRun = isempty(progressFcn) || progressFcn(done, total, message);
                if isempty(dialog) || ~isvalid(dialog)
                    return
                end
                elapsed = toc(started);
                dialog.Value = done / total;
                dialog.Message = sprintf('%d / %d 通り（%s。残り 約 %.0f 秒）', done, total, message, ...
                    elapsed / max(done - firstRun, 1) * (total - done));
                drawnow;
                continueRun = continueRun && ~dialog.CancelRequested;
            end
        end

        function onRunHighOrderSweep(app)
            runWithAlert(app, @() app.sweepHighOrderParameters(), "スイープできませんでした", ...
                "入力のデータと Wafer を選び、範囲（開始 ≦ 終了）と評価数を確かめてください。");
        end

        function onResumeHighOrderSweep(app)
            runWithAlert(app, @() app.resumeHighOrderSweep(), "続きから再開できませんでした", ...
                "「スイープを実行する」で計算し直してください。");
        end

        function onApplyHighOrderSweepBest(app)
            runWithAlert(app, @() app.applyHighOrderSweepBest(), "最もよい値を使えませんでした", ...
                "「スイープを実行する」で計算し直してから押してください。");
        end
    end
end

function values = sweepValues(range, scale, name)
% 範囲 [開始, 終了, 評価数] の値。開始から終了までを評価数で等しく分ける。scale："linear"（等間隔）・"log"（対数で等間隔）。
% 評価数が 1 なら開始の値だけ
start = range(1);
finish = range(2);
count = range(3);
if any(~isfinite(range)) || count < 1 || count ~= round(count)
    error('alignest:highOrderSweep', '%s の評価数は 1 以上の整数にしてください。', name);
end
if finish < start
    error('alignest:highOrderSweep', '%s の終了は開始以上にしてください。', name);
end
if count == 1
    values = start;
elseif scale == "log"
    if start <= 0
        error('alignest:highOrderSweep', '%s を対数で等間隔にするときは、開始を 0 より大きくしてください。', name);
    end
    values = round(logspace(log10(start), log10(finish), count), 6, 'significant');
else
    values = round(linspace(start, finish, count), 12);   % 丸めの差（0.30000000000000004 など）を除く
end
end

function text = rangeText(values)
% 値の並びの短い説明（例："0.001〜10"）
if isscalar(values)
    text = sprintf("%g", values);
else
    text = sprintf("%g〜%g", values(1), values(end));
end
end

function [fitName, looName, label] = sweepColumns(statistic)
% 図の値の名前から、alignest.sweepHighOrder の表の列（当てはめた残差・1点抜きの誤差）と、図の軸の名前
names = struct("meanPlus3Sigma", "MeanPlus3Sigma", "p95", "P95", "median", "Median", "rms", "Rms");
labels = struct("meanPlus3Sigma", "|平均|+3σ", "p95", "|残差| 95% 点", "median", "|残差| 中央値", "rms", "RMS");
fitName = "fit" + names.(statistic);
looName = "loo" + names.(statistic);
label = labels.(statistic);
end

function [name, label] = parameterOf(parameter)
% 横軸にする値の列の名前と、軸の名前
if parameter == "huberTuning"
    [name, label] = deal("huberTuning", "Huber の c");
else
    [name, label] = deal("lambda", "λ（正則化の強さ）");
end
end

function drawSweepLines(ax, rows, parameterName, parameterLabel, fitName, looName, logScale, perWafer, barKind, baseline)
% 1つの値（λ か c）を変えたときの推移：当てはめた残差（実線）・1点抜きの予測の誤差（破線）・その最小（★）。
% barKind：エラーバーの種類（Wafer 間のばらつき）、baseline：基準（最小二乗・正則化なし）の行（無ければ空の表）
FIT_COLOR = [0.0, 0.45, 0.74];
LOO_COLOR = [0.85, 0.33, 0.10];
[x, order] = sort(rows.(parameterName));
rows = rows(order, :);
fitValues = rows.(fitName);
looValues = rows.(looName);
hold(ax, 'on');
drawLine(ax, x, fitValues, sweepErrorBars(perWafer, rows, fitName, barKind), '-o', FIT_COLOR, '当てはめ');
drawLine(ax, x, looValues, sweepErrorBars(perWafer, rows, looName, barKind), '--s', LOO_COLOR, '1点抜き');
if height(baseline) > 0
    yline(ax, baseline.(fitName), ':', 'Color', FIT_COLOR, 'LineWidth', 1.6, 'DisplayName', '基準 OLS 当てはめ');
    yline(ax, baseline.(looName), ':', 'Color', LOO_COLOR, 'LineWidth', 1.6, 'DisplayName', '基準 OLS 1点抜き');
end
[minimum, position] = min(looValues);
if isfinite(minimum)
    plot(ax, x(position), minimum, 'p', 'MarkerSize', 16, 'MarkerFaceColor', [1.0, 0.8, 0.1], ...
        'MarkerEdgeColor', [0.2, 0.2, 0.2], 'DisplayName', sprintf('最小 %g', x(position)));
end
hold(ax, 'off');
if logScale && all(x > 0)
    ax.XScale = 'log';
end
if numel(x) >= 2
    xlim(ax, [min(x), max(x)]);
end
xlabel(ax, parameterLabel);
end

function drawLine(ax, x, values, bars, style, color, name)
% 推移の線。エラーバーがあれば一緒に描く
if any(isfinite(bars(:)))
    errorbar(ax, x, values, bars(:, 1), bars(:, 2), style, 'Color', color, 'MarkerFaceColor', color, 'MarkerSize', 5, ...
        'LineWidth', 1.4, 'CapSize', 3, 'DisplayName', name);
else
    plot(ax, x, values, style, 'Color', color, 'MarkerFaceColor', color, 'MarkerSize', 5, 'LineWidth', 1.4, ...
        'DisplayName', name);
end
end

function bars = sweepErrorBars(perWafer, rows, column, kind)
% 値の組ごとのエラーバーの下・上の長さ（行の数 × 2）。Wafer ごとに求めた値の Wafer 間のばらつき（alignest.layoutErrorBars と同じ種類）
Z_95 = 1.96;   % 95% 区間（正規近似）
n = height(rows);
bars = nan(n, 2);
if kind == "none"
    return
end
for k = 1:n
    values = perWafer.(column)(perWafer.run == rows.run(k) & perWafer.axis == rows.axis(k));
    values = values(isfinite(values));
    count = numel(values);
    if count < 2
        continue
    end
    switch kind
        case "sd"
            bars(k, :) = std(values);
        case "ci95"
            bars(k, :) = Z_95 * std(values) / sqrt(count);
        otherwise
            bars(k, :) = [max(rows.(column)(k) - min(values), 0), max(max(values) - rows.(column)(k), 0)];
    end
end
end

function rows = axisBaseline(sweep, axisName)
% その軸の基準（最小二乗・正則化なし）の行（無ければ空の表）
rows = sweep.baseline;
if height(rows) > 0
    rows = rows(rows.axis == axisName, :);
end
end

function text = baselineText(sweep, looName)
% 基準の説明
text = "";
if height(sweep.baseline) == 2
    text = sprintf("基準（最小二乗・正則化なし）の 1点抜きの誤差：X %.3f nm・Y %.3f nm。", sweep.baseline.(looName)(1), ...
        sweep.baseline.(looName)(2));
end
end

function drawSweepGrid(ax, rows, looName, titleText, maxTicks)
% λ と c の組み合わせ：1点抜きの予測の誤差の色の図（横軸 λ・縦軸 c）と、最小の組（★）。maxTicks：軸に名前を付ける値の数の上限
lambdas = unique(rows.lambda);
tunings = unique(rows.huberTuning);
values = nan(numel(tunings), numel(lambdas));
[~, column] = ismember(rows.lambda, lambdas);
[~, row] = ismember(rows.huberTuning, tunings);
values(sub2ind(size(values), row, column)) = rows.(looName);
picture = imagesc(ax, values);
picture.AlphaData = isfinite(values);   % 求められなかった組は塗らない
axis(ax, 'tight');
ax.YDir = 'normal';
colorbar(ax);
hold(ax, 'on');
[minimum, position] = min(values(:));
if isfinite(minimum)
    [bestRow, bestColumn] = ind2sub(size(values), position);
    plot(ax, bestColumn, bestRow, 'p', 'MarkerSize', 16, 'MarkerFaceColor', [1.0, 0.8, 0.1], ...
        'MarkerEdgeColor', [0.2, 0.2, 0.2]);
end
hold(ax, 'off');
xTicks = tickPositions(numel(lambdas), maxTicks);
yTicks = tickPositions(numel(tunings), maxTicks);
set(ax, 'XTick', xTicks, 'XTickLabel', compose('%g', lambdas(xTicks)), 'YTick', yTicks, ...
    'YTickLabel', compose('%g', tunings(yTicks)), 'XTickLabelRotation', 45);
xlabel(ax, 'λ（正則化の強さ）');
ylabel(ax, 'Huber の c');
title(ax, titleText, 'Interpreter', 'none');
end

function positions = tickPositions(n, maxTicks)
% 名前を付ける値の位置（多いときは間引く）
positions = unique(round(linspace(1, n, min(n, maxTicks))));
end

function data = sweepTable(sweep, fitName, looName)
% 表：値の組ごとに、X・Y の当てはめた残差と 1点抜きの誤差（図の値）、項の数・補正しなかった組・メモ。1行目は基準
runs = unique(sweep.table.run);
n = numel(runs);
[fitX, looX, fitY, looY, lambda, tuning, nTerms, skipped] = deal(nan(n, 1));
note = strings(n, 1);
for k = 1:n
    mine = sweep.table(sweep.table.run == runs(k), :);
    x = mine(mine.axis == "X", :);
    y = mine(mine.axis == "Y", :);
    if height(x) > 0
        [fitX(k), looX(k)] = deal(x.(fitName)(1), x.(looName)(1));
    end
    if height(y) > 0
        [fitY(k), looY(k)] = deal(y.(fitName)(1), y.(looName)(1));
    end
    lambda(k) = mine.lambda(1);
    tuning(k) = mine.huberTuning(1);
    nTerms(k) = mine.nTerms(1);
    skipped(k) = mine.skipped(1);
    note(k) = mine.note(1);
end
data = table(lambda, tuning, round(fitX, 4), round(looX, 4), round(fitY, 4), round(looY, 4), nTerms, ...
    skipped, note, 'VariableNames', ["λ", "c", "X 当てはめた残差 [nm]", "X 1点抜きの誤差 [nm]", ...
    "Y 当てはめた残差 [nm]", "Y 1点抜きの誤差 [nm]", "項の数", "補正しなかった組", "メモ"]);
[~, order] = sortrows([data.("λ"), data.("c")]);
data = data(order, :);
if height(sweep.baseline) == 2
    base = sweep.baseline;
    first = table(0, NaN, round(base.(fitName)(1), 4), round(base.(looName)(1), 4), round(base.(fitName)(2), 4), ...
        round(base.(looName)(2), 4), NaN, NaN, "基準（最小二乗・正則化なし）", 'VariableNames', data.Properties.VariableNames);
    data = [first; data];
end
end

function [best, text] = bestOf(sweep, looName, statisticLabel)
% 軸ごとに 1点抜きの予測の誤差が最も小さい値（[X, Y] の構造体。求められなければ空）と、その説明
rows = sweep.table(sweep.table.axis ~= "", :);
best = [];
text = "";
parts = strings(1, 0);
for axisName = ["X", "Y"]
    mine = rows(rows.axis == axisName, :);
    [value, index] = min(mine.(looName));
    if isempty(value) || ~isfinite(value)
        best = [];
        return
    end
    chosen = table2struct(mine(index, :));
    best = [best, chosen]; %#ok<AGROW>
    parts(end + 1) = sprintf("%s は %s（%.3f nm）", axisName, valueText(chosen, sweep.parameter), value); %#ok<AGROW>
end
text = "1点抜きの予測の誤差の " + statisticLabel + " が最小：" + strjoin(parts, "、") + "（表の太字）。";
end

function text = valueText(values, parameter)
% 値の組の説明（例："λ = 0.1"・"c = 1.5"・"λ = 0.1、c = 1.5"）
switch parameter
    case "lambda"
        text = sprintf("λ = %g", values.lambda);
    case "huberTuning"
        text = tuningText(values.huberTuning);
    otherwise
        text = sprintf("λ = %g、", values.lambda) + tuningText(values.huberTuning);
end
end

function text = tuningText(tuning)
% c の説明（c = 0 は LAD）
text = sprintf("c = %g", tuning);
if tuning == 0
    text = text + "（LAD）";
end
end

function arguments_ = namedArguments(values)
% 構造体を名前と値の組の並びにする（setHighOrderSettings に渡す）
names = fieldnames(values);
arguments_ = cell(1, 2 * numel(names));
for k = 1:numel(names)
    arguments_{2 * k - 1} = names{k};
    arguments_{2 * k} = values.(names{k});
end
end
