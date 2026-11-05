classdef (Abstract) HighOrderSweepTab < appui.Core
    %HIGHORDERSWEEPTAB 「7. Shot高次補正」の「λ・c のスイープ」：正則化の強さ λ・Huber の c を、範囲（開始・終了）と刻みで
    %   変えて計算し、補正残差（当てはめた残差と 1点抜きの予測の誤差）の推移を図と表に出す（alignest.sweepHighOrder）。
    %   1点抜きの誤差が最も小さい値を、左の設定にできる。入力のデータ・補正の計算は HighOrderTab.m。
    %   AlignmentEstimationApp（画面の本体）の一部で、ほかのタブの関数も同じように呼べる。

    properties (Constant, Access = {?appui.Core})
        SWEEP_LAMBDA_RANGE = [0.001, 10, 0.25]   % λ の初めの範囲（開始・終了・刻み。対数の刻み：10 の 0.25 乗ずつ）
        SWEEP_TUNING_RANGE = [0.5, 3, 0.25]      % Huber の c の初めの範囲（開始・終了・刻み。等間隔）
        SWEEP_MAX_VALUES = 101                   % λ・c それぞれの値の数の上限
        SWEEP_MAX_TICKS = 12                     % λ と c の組み合わせの図で、軸に名前を付ける値の数の上限
    end

    methods
        function sweep = sweepHighOrderParameters(app, parameter, options)
            %SWEEPHIGHORDERPARAMETERS 「スイープを実行する」：今の入力のデータ・Wafer・設定で、λ・c を範囲と刻みで変えて計算し、
            %   補正残差の推移を図と表に出す（alignest.sweepHighOrder）。parameter："lambda"・"huberTuning"・"both"（λ と c の
            %   すべての組み合わせ）。名前と値の組で欄を変えられる（省略すると画面の欄のまま）：lambdaRange（[開始, 終了, 刻み]）・
            %   lambdaScale（"log"：刻みは 10 の何乗ずつ・"linear"：等間隔）・tuningRange（[開始, 終了, 刻み]。等間隔）。
            %   例：app.sweepHighOrderParameters("lambda", lambdaRange=[0.01, 1, 0.5], lambdaScale="log")
            arguments
                app
                parameter (1, 1) string = ""
                options.lambdaRange (1, 3) double
                options.lambdaScale (1, 1) string
                options.tuningRange (1, 3) double
            end
            c = app.Controls;
            if parameter ~= ""
                c.highOrderTuneParameter.Value = char(parameter);
            end
            if isfield(options, "lambdaRange")
                set([c.highOrderTuneLambdaStart, c.highOrderTuneLambdaEnd, c.highOrderTuneLambdaStep], ...
                    {'Value'}, num2cell(options.lambdaRange(:)));
            end
            if isfield(options, "lambdaScale")
                c.highOrderTuneLambdaScale.Value = char(options.lambdaScale);
            end
            if isfield(options, "tuningRange")
                set([c.highOrderTuneTuningStart, c.highOrderTuneTuningEnd, c.highOrderTuneTuningStep], ...
                    {'Value'}, num2cell(options.tuningRange(:)));
            end
            refreshHighOrderSweepCount(app);
            readHighOrderControls(app);
            alignest.highOrderOptions(app.Settings);   % 設定の誤りを先に知らせる
            [lambdas, tunings] = highOrderSweepValues(app);
            wafers = highOrderWafers(app);
            if isempty(wafers)
                error('alignest:highOrderInput', 'スイープする入力のデータと Wafer を選んでください。');
            end
            dialog = [];
            if app.Figure.Visible == "on"
                dialog = appui.ProgressWindow(app.Figure, "λ・c のスイープ", "計算を始めています…", app.Palette, ...
                    app.FontSize, "止める");
            end
            cleanup = onCleanup(@() closeDialog(dialog));
            started = tic;
            sweep = alignest.sweepHighOrder(wafers, app.Settings, lambda=lambdas, huberTuning=tunings, ...
                progressFcn=@(done, total, message) reportProgress(done, total, message));
            sweep.seconds = toc(started);
            sweep.lambdaScale = string(c.highOrderTuneLambdaScale.Value);
            sweep.snapshot = highOrderSweepSnapshot(app);
            app.HighOrderSweep = sweep;
            c.highOrderTuneApply.Enable = 'on';
            c.highOrderOutputs.SelectedTab = c.highOrderTuneTab;
            drawHighOrderSweep(app);

            function continueRun = reportProgress(done, total, message)
                continueRun = true;
                if isempty(dialog) || ~isvalid(dialog)
                    return
                end
                elapsed = toc(started);
                dialog.Value = done / total;
                dialog.Message = sprintf('%d / %d 通り（%s。残り 約 %.0f 秒）', done, total, message, ...
                    elapsed / done * (total - done));
                drawnow;
                continueRun = ~dialog.CancelRequested;
            end
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
                        sweep.parameter == "lambda" && sweep.lambdaScale == "log");
                    ylabel(ax, statisticLabel + " [nm]");
                    title(ax, titleText, 'Interpreter', 'none');
                    legend(ax, 'Location', 'northoutside', 'NumColumns', 2, 'Box', 'off', 'Interpreter', 'none');
                end
                grid(ax, 'on');
                box(ax, 'on');
                styleAxes(app, ax, app.AXES_FONT_SIZE);
            end
            % 表：値の組ごとに、X・Y の当てはめた残差と 1点抜きの誤差
            data = sweepTable(sweep, fitName, looName);
            c.highOrderTuneTable.Data = data;
            removeStyle(c.highOrderTuneTable);
            [best, bestText] = bestOf(sweep, looName, statisticLabel);
            if ~isempty(best)
                row = find(data.("λ") == best.lambda & data.("c") == best.huberTuning, 1);
                addStyle(c.highOrderTuneTable, uistyle('FontWeight', 'bold'), 'row', row);
            end
            % 説明は短くし（図の高さを取るため）、詳しい見方は「9. ヘルプ」
            howToRead = "λ・c は破線（1点抜きの予測の誤差）で選びます（実線の当てはめた残差は λ が小さいほど小さく見える）。";
            if sweep.parameter == "both"
                howToRead = "色は 1点抜きの予測の誤差（★ が最小。当てはめた残差は「表」）。";
            end
            info = sprintf("%d 通りを %.0f 秒で計算しました%s。", sweep.nRuns, sweep.seconds, ...
                ternary(sweep.cancelled, "（途中で止めました）", "")) + bestText + howToRead;
            if ~isequaln(sweep.snapshot, highOrderSweepSnapshot(app))
                info = "⚠ スイープの後に入力・Wafer・設定（λ・c・正則化の種類・損失関数のほか）を変えました。" + ...
                    "スイープし直してください（下は前の結果）。" + info;
            end
            c.highOrderTuneInfo.Text = char(info);
        end

        function best = applyHighOrderSweepBest(app)
            %APPLYHIGHORDERSWEEPBEST 「最もよい値を使う」：図の値の 1点抜きの予測の誤差（X・Y の平均）が最も小さい λ・c を、
            %   左の設定にする（λ を変えたとき、正則化がなしなら L2 に、c を変えたとき、損失関数を Huber にする）。best は使った値。
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
                changes.lambda = best.lambda;
                changes.regularization = sweep.regularization;
            end
            if any(sweep.parameter == ["huberTuning", "both"])
                changes.huberTuning = best.huberTuning;
                changes.loss = "huber";
            end
            arguments_ = namedArguments(changes);
            setHighOrderSettings(app, arguments_{:});
            drawHighOrderSweep(app);
            app.Controls.highOrderTuneInfo.Text = char("左の設定を " + valueText(best, sweep.parameter) + ...
                " にしました。「補正を計算する」で計算し直してください。" + string(app.Controls.highOrderTuneInfo.Text));
        end
    end

    methods (Access = {?appui.Core})
        function buildHighOrderSweepTab(app, outputs)
            % 「λ・c のスイープ」のタブ：スイープする値・範囲と刻み・図の値・実行と最もよい値を使うボタン、結果の図と表
            c = struct();
            tab = uitab(outputs, 'Title', 'λ・c のスイープ');
            c.highOrderTuneTab = tab;
            grid = uigridlayout(tab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            % 1行目：変える値・図の値、2行目：λ の範囲と刻み、3行目：c の範囲と刻みと計算する数、4行目：ボタン
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
            % λ の範囲と刻み
            label(controls, 'λ：開始', 2, 1);
            c.highOrderTuneLambdaStart = uieditfield(controls, 'numeric', 'Value', app.SWEEP_LAMBDA_RANGE(1), ...
                'Limits', [0, Inf], 'ValueChangedFcn', onRange);
            place(c.highOrderTuneLambdaStart, 2, 2);
            label(controls, '終了', 2, 3);
            c.highOrderTuneLambdaEnd = uieditfield(controls, 'numeric', 'Value', app.SWEEP_LAMBDA_RANGE(2), ...
                'Limits', [0, Inf], 'ValueChangedFcn', onRange);
            place(c.highOrderTuneLambdaEnd, 2, 4);
            label(controls, '刻み', 2, 5);
            c.highOrderTuneLambdaStep = uieditfield(controls, 'numeric', 'Value', app.SWEEP_LAMBDA_RANGE(3), ...
                'Limits', [0, Inf], 'LowerLimitInclusive', 'off', 'ValueChangedFcn', onRange);
            place(c.highOrderTuneLambdaStep, 2, 6);
            c.highOrderTuneLambdaScale = uidropdown(controls, 'Items', {'対数で刻む', '等間隔で刻む'}, ...
                'ItemsData', {'log', 'linear'}, 'ValueChangedFcn', onRange, 'Tooltip', ...
                ['対数：刻みは 10 の何乗ずつ。λ = 開始・開始 × 10^刻み・… と、桁をまたいで比べます（例：0.001〜10、刻み 0.25 で 17 通り。0 は' ...
                '入れられないので、正則化なしと比べるときは等間隔に）。等間隔：開始・開始 + 刻み・… 。']);
            place(c.highOrderTuneLambdaScale, 2, [7, 8]);
            % c の範囲と刻み
            label(controls, 'c：開始', 3, 1);
            c.highOrderTuneTuningStart = uieditfield(controls, 'numeric', 'Value', app.SWEEP_TUNING_RANGE(1), ...
                'Limits', [0, Inf], 'LowerLimitInclusive', 'off', 'ValueChangedFcn', onRange);
            place(c.highOrderTuneTuningStart, 3, 2);
            label(controls, '終了', 3, 3);
            c.highOrderTuneTuningEnd = uieditfield(controls, 'numeric', 'Value', app.SWEEP_TUNING_RANGE(2), ...
                'Limits', [0, Inf], 'LowerLimitInclusive', 'off', 'ValueChangedFcn', onRange);
            place(c.highOrderTuneTuningEnd, 3, 4);
            label(controls, '刻み', 3, 5);
            c.highOrderTuneTuningStep = uieditfield(controls, 'numeric', 'Value', app.SWEEP_TUNING_RANGE(3), ...
                'Limits', [0, Inf], 'LowerLimitInclusive', 'off', 'ValueChangedFcn', onRange);
            place(c.highOrderTuneTuningStep, 3, 6);
            c.highOrderTuneCount = uilabel(controls, 'Text', '', 'WordWrap', 'on');
            place(c.highOrderTuneCount, 3, [7, 8]);
            buttons = uigridlayout(controls, [1, 3], 'ColumnWidth', {'fit', 'fit', '1x'}, 'Padding', 0);
            place(buttons, 4, [1, 8]);
            c.highOrderTuneRun = primaryButton(app, buttons, 'スイープを実行する', @(~, ~) app.onRunHighOrderSweep());
            c.highOrderTuneApply = uibutton(buttons, 'Text', '最もよい値を使う', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onApplyHighOrderSweepBest(), 'Tooltip', ['図の値の 1点抜きの予測の誤差' ...
                '（X・Y の平均）が最も小さい λ・c を、左の設定にします。']);
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
            emptyText = ['λ・c の範囲と刻みを決めて「スイープを実行する」を押すと、今の入力・Wafer・設定で値ごとに計算し、' ...
                '補正残差の推移を出します。'];
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
            set([c.highOrderTuneLambdaStart, c.highOrderTuneLambdaEnd, c.highOrderTuneLambdaStep, ...
                c.highOrderTuneLambdaScale], 'Enable', onOff(useLambda));
            set([c.highOrderTuneTuningStart, c.highOrderTuneTuningEnd, c.highOrderTuneTuningStep], ...
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
            % 欄の範囲と刻みから、スイープする λ・c の値（スイープしない方は空）
            c = app.Controls;
            parameter = string(c.highOrderTuneParameter.Value);
            [lambdas, tunings] = deal(zeros(1, 0));
            if any(parameter == ["lambda", "both"])
                lambdas = sweepValues([c.highOrderTuneLambdaStart.Value, c.highOrderTuneLambdaEnd.Value, ...
                    c.highOrderTuneLambdaStep.Value], string(c.highOrderTuneLambdaScale.Value), "λ", app.SWEEP_MAX_VALUES);
            end
            if any(parameter == ["huberTuning", "both"])
                tunings = sweepValues([c.highOrderTuneTuningStart.Value, c.highOrderTuneTuningEnd.Value, ...
                    c.highOrderTuneTuningStep.Value], "linear", "c", app.SWEEP_MAX_VALUES);
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

        function onRunHighOrderSweep(app)
            runWithAlert(app, @() app.sweepHighOrderParameters(), "スイープできませんでした", ...
                "入力のデータと Wafer を選び、範囲（開始 ≦ 終了）と刻み（0 より大きい）を確かめてください。");
        end

        function onApplyHighOrderSweepBest(app)
            runWithAlert(app, @() app.applyHighOrderSweepBest(), "最もよい値を使えませんでした", ...
                "「スイープを実行する」で計算し直してから押してください。");
        end
    end
end

function values = sweepValues(range, scale, name, maxValues)
% 範囲 [開始, 終了, 刻み] の値。scale："log"（開始 × 10^(刻み × i)。終了も入れる）・"linear"（開始 + 刻み × i。終了も入れる）
TOLERANCE = 1e-9;   % 終了と同じとみなす差（刻みに対する割合）
start = range(1);
finish = range(2);
step = range(3);
if any(~isfinite(range)) || step <= 0
    error('alignest:highOrderSweep', '%s の刻みは 0 より大きい数にしてください。', name);
end
if finish < start
    error('alignest:highOrderSweep', '%s の終了は開始以上にしてください。', name);
end
if scale == "log"
    if start <= 0
        error('alignest:highOrderSweep', ['%s を対数で刻むときは、開始を 0 より大きくしてください（0 を入れるときは' ...
            '等間隔にしてください）。'], name);
    end
    exponents = log10(start):step:(log10(finish) + TOLERANCE * step);
    if log10(finish) - exponents(end) > TOLERANCE * step
        exponents(end + 1) = log10(finish);   % 刻みが割り切れないときも終了を入れる
    end
    values = round(10 .^ exponents, 6, 'significant');
else
    values = start:step:(finish + TOLERANCE * step);
    if finish - values(end) > TOLERANCE * step
        values(end + 1) = finish;
    end
    values = round(values, 12);   % 0.1 刻みの計算の丸めの差（0.30000000000000004 など）を除く
end
if numel(values) > maxValues
    error('alignest:highOrderSweep', '%s が %d 通りになります。%d 通り以下になるように刻みを大きくしてください。', ...
        name, numel(values), maxValues);
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

function drawSweepLines(ax, rows, parameterName, parameterLabel, fitName, looName, logScale)
% 1つの値（λ か c）を変えたときの推移：当てはめた残差（実線）・1点抜きの予測の誤差（破線）・その最小（★）
FIT_COLOR = [0.0, 0.45, 0.74];
LOO_COLOR = [0.85, 0.33, 0.10];
[x, order] = sort(rows.(parameterName));
fitValues = rows.(fitName)(order);
looValues = rows.(looName)(order);
hold(ax, 'on');
plot(ax, x, fitValues, '-o', 'Color', FIT_COLOR, 'MarkerFaceColor', FIT_COLOR, 'MarkerSize', 5, 'LineWidth', 1.4, ...
    'DisplayName', '当てはめた残差');
plot(ax, x, looValues, '--s', 'Color', LOO_COLOR, 'MarkerFaceColor', LOO_COLOR, 'MarkerSize', 5, 'LineWidth', 1.4, ...
    'DisplayName', '1点抜きの予測の誤差');
[minimum, position] = min(looValues);
if isfinite(minimum)
    plot(ax, x(position), minimum, 'p', 'MarkerSize', 16, 'MarkerFaceColor', [1.0, 0.8, 0.1], ...
        'MarkerEdgeColor', [0.2, 0.2, 0.2], 'DisplayName', sprintf('最小：%g', x(position)));
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
% 表：値の組ごとに、X・Y の当てはめた残差と 1点抜きの誤差（図の値）、項の数・補正しなかった組・メモ
pairs = unique(sweep.table(:, ["lambda", "huberTuning"]), 'stable');
n = height(pairs);
[fitX, looX, fitY, looY] = deal(nan(n, 1));
[nTerms, skipped] = deal(nan(n, 1));
note = strings(n, 1);
for k = 1:n
    mine = sweep.table(sweep.table.lambda == pairs.lambda(k) & sweep.table.huberTuning == pairs.huberTuning(k), :);
    x = mine(mine.axis == "X", :);
    y = mine(mine.axis == "Y", :);
    if height(x) > 0
        [fitX(k), looX(k)] = deal(x.(fitName)(1), x.(looName)(1));
    end
    if height(y) > 0
        [fitY(k), looY(k)] = deal(y.(fitName)(1), y.(looName)(1));
    end
    nTerms(k) = mine.nTerms(1);
    skipped(k) = mine.skipped(1);
    note(k) = mine.note(1);
end
data = table(pairs.lambda, pairs.huberTuning, round(fitX, 4), round(looX, 4), round(fitY, 4), round(looY, 4), nTerms, ...
    skipped, note, 'VariableNames', ["λ", "c", "X 当てはめた残差 [nm]", "X 1点抜きの誤差 [nm]", ...
    "Y 当てはめた残差 [nm]", "Y 1点抜きの誤差 [nm]", "項の数", "補正しなかった組", "メモ"]);
[~, order] = sortrows([data.("λ"), data.("c")]);
data = data(order, :);
end

function [best, text] = bestOf(sweep, looName, statisticLabel)
% 1点抜きの予測の誤差（X・Y の平均）が最も小さい値の組と、軸ごとの最小の説明
rows = sweep.table(sweep.table.axis ~= "", :);
best = [];
text = "";
if isempty(rows)
    return
end
pairs = unique(rows(:, ["lambda", "huberTuning"]), 'stable');
score = nan(height(pairs), 1);
for k = 1:height(pairs)
    mine = rows(rows.lambda == pairs.lambda(k) & rows.huberTuning == pairs.huberTuning(k), :);
    score(k) = mean(mine.(looName), 'omitnan');
end
[minimum, position] = min(score);
if ~isfinite(minimum)
    return
end
best = table2struct(pairs(position, :));
parts = strings(1, 0);
for axisName = ["X", "Y"]
    mine = rows(rows.axis == axisName, :);
    [value, index] = min(mine.(looName));
    if isfinite(value)
        parts(end + 1) = sprintf("%s は %s（%.3f nm）", axisName, valueText(table2struct(mine(index, :)), ...
            sweep.parameter), value); %#ok<AGROW>
    end
end
text = "1点抜きの予測の誤差の " + statisticLabel + " が最小：" + strjoin(parts, "、") + "、X・Y の平均は " + ...
    valueText(best, sweep.parameter) + "（表の太字。「最もよい値を使う」で左の設定に）。";
end

function text = valueText(values, parameter)
% 値の組の説明（例："λ = 0.1"・"c = 1.5"・"λ = 0.1、c = 1.5"）
switch parameter
    case "lambda"
        text = sprintf("λ = %g", values.lambda);
    case "huberTuning"
        text = sprintf("c = %g", values.huberTuning);
    otherwise
        text = sprintf("λ = %g、c = %g", values.lambda, values.huberTuning);
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
