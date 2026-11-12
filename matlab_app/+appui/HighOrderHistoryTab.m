classdef (Abstract) HighOrderHistoryTab < appui.Core
    %HIGHORDERHISTORYTAB 「7. Shot高次補正」の3つのタブ：
    %   - 「k の選定」：単純な回帰で k パラメータ（補正の式の項）を選ぶ（変数重要度 |t| で一括して外す・BIC でステップワイズに
    %     足す。alignest.highOrderTermSelection）。結果を見てから「使う項にする」で表の「使う」に写す
    %   - 「結果の履歴」：「補正を計算する」を押すたびに結果（すべての Wafer の評価と設定）を足し、条件どうしを表と図で比べる。
    %     選んだ結果の設定を左の設定に戻せる
    %   - 「他の Wafer の補正」：補正元の Wafer で求めた補正値を補正先の Wafer に当てて評価する（補正元が複数なら、補正値を
    %     平均するか、実測値を平均してから補正値を求める）
    %     （alignest.transferHighOrder）
    %   入力のデータ・補正の計算は HighOrderTab.m。AlignmentEstimationApp（画面の本体）の一部で、ほかのタブの関数も同じように呼べる。

    properties (Constant, Access = {?appui.Core})
        HIGH_ORDER_HISTORY_MAX = 50       % 結果の履歴に残す数の上限（古いものから消す）
        HIGH_ORDER_TRANSFER_LIST_HEIGHT = 70   % 補正元・補正先の Wafer の一覧の高さ
    end

    methods
        function selection = selectHighOrderTerms(app, method, threshold)
            %SELECTHIGHORDERTERMS 「k の選定」：今の入力のデータ・選んだ Wafer で k パラメータを選ぶ（表の「使う」はまだ変えない）。
            %   method："importance"（変数重要度 |t| がしきい値より小さい項を一括して外す）・"stepwise"（今の使う項から、BIC が
            %   最も下がる項を1つずつ足す）。threshold：|t| のしきい値。省略すると画面の選択。
            c = app.Controls;
            if nargin >= 2
                c.highOrderSelectMethod.Value = char(method);
            end
            if nargin >= 3
                c.highOrderSelectThreshold.Value = threshold;
            end
            readHighOrderControls(app);
            wafers = highOrderWafers(app);
            selection = alignest.highOrderTermSelection(wafers, app.Settings, string(c.highOrderSelectMethod.Value), ...
                threshold=c.highOrderSelectThreshold.Value);
            app.HighOrderTermSelection = selection;
            showHighOrderTermSelection(app);
        end

        function applyHighOrderTermSelection(app)
            %APPLYHIGHORDERTERMSELECTION 「k の選定」の結果を、「使う項と VIF」の表の「使う」に写す（使わない項 = 選ばなかった項）
            selection = app.HighOrderTermSelection;
            if isempty(selection)
                error('alignest:highOrderSelection', '先に「計算する」で k パラメータを選んでください。');
            end
            options = alignest.highOrderOptions(app.Settings);
            if options.maker ~= selection.maker
                error('alignest:highOrderSelection', '選んだ後に補正の式を変えました。「計算する」で選び直してください。');
            end
            app.Settings.highOrder.excludedTerms = selection.excludedTerms;
            refreshHighOrderTerms(app);
            app.Controls.highOrderSelectInfo.Text = sprintf(['使う項を dx %d 項・dy %d 項にしました（「使う項と VIF」の表）。' ...
                '「補正を計算する」で補正を求め直してください。'], numel(selection.used{1}), numel(selection.used{2}));
        end

        function data = compareHighOrderHistory(app, rows, metric)
            %COMPAREHIGHORDERHISTORY 「結果の履歴」の図：選んだ結果（rows：履歴の行の番号。空ならすべて）の、すべての Wafer の
            %   値（metric："highOrder"・"highOrderP95"・"highOrderMedian"・"rSquared"・"waferStage"・"commonStage"）を X・Y の
            %   棒で並べる。省略すると画面の選択。data は図の値（number・X・Y）。
            c = app.Controls;
            if nargin >= 2
                app.HighOrderHistorySelection = reshape(rows, 1, []);
            end
            if nargin >= 3
                c.highOrderHistoryMetric.Value = char(metric);
            end
            data = drawHighOrderHistoryChart(app);
        end

        function removeHighOrderHistory(app, rows)
            %REMOVEHIGHORDERHISTORY 結果の履歴から行 rows を消す（空ならすべて消す）
            if nargin < 2 || isempty(rows)
                app.HighOrderHistory = app.HighOrderHistory([]);
            else
                app.HighOrderHistory(rows(rows >= 1 & rows <= numel(app.HighOrderHistory))) = [];
            end
            app.HighOrderHistorySelection = zeros(1, 0);
            showHighOrderHistory(app);
        end

        function restoreHighOrderHistory(app, row)
            %RESTOREHIGHORDERHISTORY 結果の履歴の行 row の設定（settings.highOrder）を、左の設定に戻す（計算はし直さない）
            if row < 1 || row > numel(app.HighOrderHistory)
                error('alignest:highOrderHistory', '結果の履歴に %d 番目の行はありません。', row);
            end
            entry = app.HighOrderHistory(row);
            app.Settings.highOrder = entry.settings;
            highOrderSettingsToControls(app);
            app.Controls.highOrderHistoryInfo.Text = sprintf(['結果 #%d の設定を左の設定に戻しました。「補正を計算する」で' ...
                '同じ条件の結果を求め直せます。'], entry.number);
        end

        function transfer = transferHighOrderCorrection(app, sources, targets, method)
            %TRANSFERHIGHORDERCORRECTION 「他の Wafer の補正」：補正元の Wafer（sources）で求めた補正値を、補正先の Wafer
            %   （targets）に当てて評価する（alignest.transferHighOrder）。sources・targets：計算した Wafer の番号か名前。
            %   method：補正元が複数のときの求め方。"coefficients"（それぞれで求めた補正値を平均する）・"values"（実測値を
            %   平均してから補正値を求める）。省略すると画面の選択。
            c = app.Controls;
            run = app.HighOrderRun;
            if isempty(run)
                error('alignest:highOrderTransfer', '先に「補正を計算する」で、補正元と補正先の Wafer を一緒に計算してください。');
            end
            labels = string({run.wafers.label});
            if nargin >= 2
                c.highOrderTransferSources.Value = num2cell(waferIndexes(labels, sources));
            end
            if nargin >= 3
                c.highOrderTransferTargets.Value = num2cell(waferIndexes(labels, targets));
            end
            if nargin >= 4
                c.highOrderTransferMethod.Value = char(method);
            end
            sourceLabels = labels([c.highOrderTransferSources.Value{:}]);
            targetLabels = labels([c.highOrderTransferTargets.Value{:}]);
            transfer = alignest.transferHighOrder(run.result, sourceLabels, targetLabels, app.Settings.data.waferRadiusMm, ...
                method=string(c.highOrderTransferMethod.Value));
            app.HighOrderTransfer = transfer;
            showHighOrderTransfer(app);
        end
    end

    methods (Access = {?appui.Core})
        function buildHighOrderSelectionTab(app, outputs)
            % 「k の選定」のタブ：方法・しきい値・計算する・使う項にする、結果の表
            c = struct();
            tab = uitab(outputs, 'Title', 'k の選定');
            c.highOrderSelectTab = tab;
            grid = uigridlayout(tab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            controls = uigridlayout(grid, [1, 6], 'ColumnWidth', {'fit', 260, 'fit', 70, 'fit', 'fit'}, 'Padding', 0);
            label(controls, '方法', 1, 1);
            c.highOrderSelectMethod = uidropdown(controls, 'Items', {'変数重要度', ...
                'ステップワイズ（BIC）で足す'}, 'ItemsData', {'importance', 'stepwise'}, ...
                'ValueChangedFcn', @(~, ~) app.updateHighOrderSelectionEnabled(), 'Tooltip', ['変数重要度：式のすべての項で' ...
                '当てはめ、項ごとの |t 値|（係数 ÷ 標準誤差）の Wafer の間の中央値がしきい値より小さい項を外します。' ...
                'ステップワイズ：今の「使う」項から始め、BIC が最も下がる項を1つずつ足します。どちらも Wafer ごとの最小二乗' ...
                '（Wafer 内で共通の1組）で、k1〜k6 は必ず使います。詳しくは「ヘルプ」。']);
            place(c.highOrderSelectMethod, 1, 2);
            label(controls, 'しきい値', 1, 3);
            c.highOrderSelectThreshold = uieditfield(controls, 'numeric', 'Value', 2, 'Limits', [0, Inf], ...
                'Tooltip', ['変数重要度がこの値より小さい項を外します（変数重要度は |t 値| の Wafer の間の中央値。' ...
                '2 なら、おおよそ有意水準 5%）。']);
            place(c.highOrderSelectThreshold, 1, 4);
            c.highOrderSelectRun = uibutton(controls, 'Text', '計算する', 'ButtonPushedFcn', ...
                @(~, ~) app.onSelectHighOrderTerms());
            place(c.highOrderSelectRun, 1, 5);
            c.highOrderSelectApply = uibutton(controls, 'Text', '使う項にする', 'Enable', 'off', 'ButtonPushedFcn', ...
                @(~, ~) app.onApplyHighOrderTermSelection(), 'Tooltip', '選んだ結果を「使う項と VIF」の表の「使う」に写します。');
            place(c.highOrderSelectApply, 1, 6);
            c.highOrderSelectTable = uitable(grid, 'RowName', {}, 'Data', table());
            place(c.highOrderSelectTable, 2, 1);
            c.highOrderSelectInfo = uilabel(grid, 'WordWrap', 'on', 'Text', ['左の①の入力のデータと Wafer で、' ...
                '「計算する」を押すと k パラメータを選びます。']);
            place(c.highOrderSelectInfo, 3, 1);
            app.Controls = mergeStruct(app.Controls, c);
        end

        function buildHighOrderHistoryTab(app, outputs)
            % 「結果の履歴」のタブ：計算するたびに足した結果の表と、選んだ結果の図
            c = struct();
            tab = uitab(outputs, 'Title', '結果の履歴');
            c.highOrderHistoryTab = tab;
            grid = uigridlayout(tab, [4, 1], 'RowHeight', {'fit', 170, '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            controls = uigridlayout(grid, [1, 5], 'ColumnWidth', {'fit', 230, 'fit', 'fit', 'fit'}, 'Padding', 0);
            label(controls, '図の値', 1, 1);
            c.highOrderHistoryMetric = uidropdown(controls, 'Items', {'高次補正の残差 |平均|+3σ', ...
                '高次補正の |残差| 95% 点', '高次補正の |残差| 中央値', '決定係数 R²', 'Wafer 高次補正だけの残差', ...
                '＋Shot 共通補正の残差'}, 'ItemsData', {'highOrder', 'highOrderP95', 'highOrderMedian', 'rSquared', ...
                'waferStage', 'commonStage'}, 'ValueChangedFcn', @(~, ~) app.drawHighOrderHistoryChart());
            place(c.highOrderHistoryMetric, 1, 2);
            c.highOrderHistoryRestore = uibutton(controls, 'Text', '選んだ条件を設定に戻す', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onRestoreHighOrderHistory(), 'Tooltip', ['表で1つ選んだ結果の設定を、左の②③の' ...
                '設定に戻します（計算はし直しません）。']);
            place(c.highOrderHistoryRestore, 1, 3);
            c.highOrderHistoryRemove = uibutton(controls, 'Text', '選んだ結果を消す', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.removeHighOrderHistory(app.HighOrderHistorySelection));
            place(c.highOrderHistoryRemove, 1, 4);
            c.highOrderHistoryClear = uibutton(controls, 'Text', 'すべて消す', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.removeHighOrderHistory());
            place(c.highOrderHistoryClear, 1, 5);
            c.highOrderHistoryTable = uitable(grid, 'RowName', {}, 'Data', cell(0, 14), 'ColumnName', ...
                {'No', '時刻', 'Wafer', '条件', 'X 高次補正|｜平均｜+3σ', 'Y 高次補正|｜平均｜+3σ', 'X Wafer 高次|だけ', ...
                'Y Wafer 高次|だけ', 'X ＋Shot|共通', 'Y ＋Shot|共通', 'X ｜残差｜|95% 点', 'Y ｜残差｜|95% 点', 'X R²', 'Y R²'}, ...
                'ColumnWidth', {40, 70, 54, 'auto', 96, 96, 80, 80, 70, 70, 80, 80, 56, 56}, ...
                'CellSelectionCallback', @(~, event) app.onHighOrderHistorySelected(event), 'Tooltip', ...
                ['「補正を計算する」を押すたびに、すべての Wafer の評価を足します（値は [nm]）。行を選ぶと、図にその結果だけを' ...
                '並べます（Shift・Ctrl で複数）。']);
            place(c.highOrderHistoryTable, 2, 1);
            c.highOrderHistoryAxes = axesInPanel(grid, 3);
            c.highOrderHistoryInfo = uilabel(grid, 'WordWrap', 'on', 'Text', ...
                '「補正を計算する」を押すたびに、ここに結果を足します。');
            place(c.highOrderHistoryInfo, 4, 1);
            app.Controls = mergeStruct(app.Controls, c);
        end

        function buildHighOrderTransferTab(app, outputs)
            % 「他の Wafer の補正」のタブ：補正元・補正先の Wafer、当てはめて評価する、結果の表
            c = struct();
            tab = uitab(outputs, 'Title', '他の Wafer の補正');
            c.highOrderTransferTab = tab;
            grid = uigridlayout(tab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            controls = uigridlayout(grid, [2, 5], 'ColumnWidth', {'fit', '1x', 'fit', '1x', 'fit'}, ...
                'RowHeight', {app.HIGH_ORDER_TRANSFER_LIST_HEIGHT, 'fit'}, 'Padding', 0);
            label(controls, '補正元の Wafer', 1, 1);
            c.highOrderTransferSources = uilistbox(controls, 'Items', {'—'}, 'ItemsData', {1}, 'Multiselect', 'on', ...
                'Enable', 'off', 'Tooltip', ['補正値を使う Wafer。2枚以上選ぶと、補正値を項ごとに平均して当てます' ...
                '（Shot ごとの k は shotNo ごと）。']);
            place(c.highOrderTransferSources, 1, 2);
            label(controls, '補正先の Wafer', 1, 3);
            c.highOrderTransferTargets = uilistbox(controls, 'Items', {'—'}, 'ItemsData', {1}, 'Multiselect', 'on', ...
                'Enable', 'off', 'Tooltip', '補正値を当てて評価する Wafer（Shift・Ctrl で複数）。');
            place(c.highOrderTransferTargets, 1, 4);
            c.highOrderTransferRun = uibutton(controls, 'Text', '当てはめて評価する', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onTransferHighOrder());
            place(c.highOrderTransferRun, 1, 5);
            % 補正元が2枚以上のときの補正値の求め方
            label(controls, '補正元が複数', 2, 1);
            c.highOrderTransferMethod = uidropdown(controls, 'Items', {'それぞれで求めた補正値を平均する', ...
                '実測値を平均してから補正値を求める'}, 'ItemsData', {'coefficients', 'values'}, 'Enable', 'off', ...
                'Tooltip', ['補正値を平均する：補正元の Wafer ごとに求めた補正値（k）を項ごとに平均して当てます。実測値を平均' ...
                'する：補正元の計測値を、同じ Shot・Shot 内の位置の点ごとに平均してから、同じ設定で補正値を求めて当てます。' ...
                '補正元が1枚なら、どちらも同じです。']);
            place(c.highOrderTransferMethod, 2, [2, 4]);
            c.highOrderTransferTable = uitable(grid, 'RowName', {}, 'Data', table());
            place(c.highOrderTransferTable, 2, 1);
            c.highOrderTransferInfo = uilabel(grid, 'WordWrap', 'on', 'Text', ['「補正を計算する」で補正元と補正先の Wafer を' ...
                '一緒に計算してから、補正元・補正先を選んで「当てはめて評価する」を押します（同じ補正の式・くくり・設定の' ...
                '補正値を当てます）。']);
            place(c.highOrderTransferInfo, 3, 1);
            app.Controls = mergeStruct(app.Controls, c);
        end

        function addHighOrderHistory(app)
            % 「補正を計算する」の結果を、結果の履歴に足す（すべての Wafer の評価と、計算したときの設定）
            run = app.HighOrderRun;
            if isempty(run)
                return
            end
            numbers = [app.HighOrderHistory.number];
            totals = run.result.summary(run.result.summary.wafer == "すべての Wafer", :);
            entry = struct("number", max([numbers, 0]) + 1, "time", string(datetime('now', 'Format', 'HH:mm:ss')), ...
                "description", string(run.result.description), "nWafers", numel(run.wafers), "summary", totals, ...
                "settings", run.settings);
            app.HighOrderHistory(end + 1) = entry;
            if numel(app.HighOrderHistory) > app.HIGH_ORDER_HISTORY_MAX
                app.HighOrderHistory(1:end - app.HIGH_ORDER_HISTORY_MAX) = [];   % 古い結果から消す
            end
            app.HighOrderHistorySelection = zeros(1, 0);
            showHighOrderHistory(app);
        end

        function showHighOrderHistory(app)
            % 結果の履歴の表と図
            c = app.Controls;
            history = app.HighOrderHistory;
            data = cell(numel(history), 14);
            for k = 1:numel(history)
                entry = history(k);
                x = entry.summary(entry.summary.axis == "X", :);
                y = entry.summary(entry.summary.axis == "Y", :);
                data(k, :) = {int32(entry.number), char(entry.time), int32(entry.nWafers), char(entry.description), ...
                    roundOrNaN(x, "highOrder", 3), roundOrNaN(y, "highOrder", 3), roundOrNaN(x, "waferStage", 3), ...
                    roundOrNaN(y, "waferStage", 3), roundOrNaN(x, "commonStage", 3), roundOrNaN(y, "commonStage", 3), ...
                    roundOrNaN(x, "highOrderP95", 3), roundOrNaN(y, "highOrderP95", 3), roundOrNaN(x, "rSquared", 4), ...
                    roundOrNaN(y, "rSquared", 4)};
            end
            c.highOrderHistoryTable.Data = data;
            set([c.highOrderHistoryClear, c.highOrderHistoryRemove], 'Enable', onOff(~isempty(history)));
            c.highOrderHistoryRestore.Enable = onOff(numel(app.HighOrderHistorySelection) == 1);
            drawHighOrderHistoryChart(app);
        end

        function data = drawHighOrderHistoryChart(app)
            % 選んだ結果（選んでいなければすべて）の、すべての Wafer の値を X・Y の棒で並べる
            c = app.Controls;
            ax = c.highOrderHistoryAxes;
            cla(ax, 'reset');
            legend(ax, 'off');
            data = table();
            history = app.HighOrderHistory;
            rows = app.HighOrderHistorySelection;
            rows = rows(rows >= 1 & rows <= numel(history));
            if isempty(rows)
                rows = 1:numel(history);
            end
            if isempty(rows)
                c.highOrderHistoryInfo.Text = '「補正を計算する」を押すたびに、ここに結果を足します。';
                return
            end
            metric = string(c.highOrderHistoryMetric.Value);
            values = nan(numel(rows), 2);
            for j = 1:numel(rows)
                summary = history(rows(j)).summary;
                values(j, :) = [roundOrNaN(summary(summary.axis == "X", :), metric, 6), ...
                    roundOrNaN(summary(summary.axis == "Y", :), metric, 6)];
            end
            numbers = [history(rows).number];
            bars = bar(ax, 1:numel(rows), values, 'grouped');
            bars(1).FaceColor = app.PRIMARY_COLOR;
            bars(1).DisplayName = 'X';
            bars(2).DisplayName = 'Y';
            xticks(ax, 1:numel(rows));
            xticklabels(ax, cellstr("#" + string(numbers)));
            xlabel(ax, '結果の番号（表の No）');
            ylabel(ax, historyMetricLabel(metric));
            title(ax, 'すべての Wafer の評価（結果ごと）', 'Interpreter', 'none');
            grid(ax, 'on');
            box(ax, 'on');
            legend(ax, 'Location', 'northeast', 'Interpreter', 'none');
            styleAxes(app, ax, app.AXES_FONT_SIZE);
            data = table(numbers(:), values(:, 1), values(:, 2), 'VariableNames', ["number", "X", "Y"]);
            c.highOrderHistoryInfo.Text = sprintf(['%d 件の結果を並べました（表で行を選ぶと、その結果だけを並べます）。' ...
                '値は「すべての Wafer」の行です。'], numel(rows));
        end

        function onHighOrderHistorySelected(app, event)
            if isempty(event.Indices)
                app.HighOrderHistorySelection = zeros(1, 0);
            else
                app.HighOrderHistorySelection = unique(event.Indices(:, 1)).';
            end
            c = app.Controls;
            c.highOrderHistoryRestore.Enable = onOff(numel(app.HighOrderHistorySelection) == 1);
            drawHighOrderHistoryChart(app);
        end

        function onRestoreHighOrderHistory(app)
            rows = app.HighOrderHistorySelection;
            if numel(rows) ~= 1
                return
            end
            runWithAlert(app, @() app.restoreHighOrderHistory(rows), "設定に戻せませんでした", ...
                "結果の履歴で1つの行を選んでください。");
        end

        function refreshHighOrderTransferChoices(app)
            % 補正元・補正先の Wafer の一覧を、計算した Wafer に合わせる（計算し直したら前の評価は消す）
            c = app.Controls;
            if ~isfield(c, 'highOrderTransferTable')
                return   % タブを作る前
            end
            run = app.HighOrderRun;
            app.HighOrderTransfer = [];
            c.highOrderTransferTable.Data = table();
            if isempty(run)
                setListChoices(c.highOrderTransferSources, "—", {1});
                setListChoices(c.highOrderTransferTargets, "—", {1});
                set([c.highOrderTransferSources, c.highOrderTransferTargets, c.highOrderTransferRun, c.highOrderTransferMethod], ...
                    'Enable', 'off');
                return
            end
            labels = string({run.wafers.label});
            setListChoices(c.highOrderTransferSources, labels, num2cell(1:numel(labels)));
            setListChoices(c.highOrderTransferTargets, labels, num2cell(1:numel(labels)));
            c.highOrderTransferSources.Value = {1};
            c.highOrderTransferTargets.Value = num2cell(max(1, 2):max(numel(labels), 1));   % はじめは2枚目から（1枚なら同じ）
            set([c.highOrderTransferSources, c.highOrderTransferTargets, c.highOrderTransferRun, c.highOrderTransferMethod], ...
                'Enable', 'on');
        end

        function showHighOrderTransfer(app)
            % 「他の Wafer の補正」の結果の表と知らせ
            c = app.Controls;
            transfer = app.HighOrderTransfer;
            if isempty(transfer)
                c.highOrderTransferTable.Data = table();
                return
            end
            s = transfer.summary;
            c.highOrderTransferTable.Data = table(s.wafer, s.axis, round(s.before, 3), round(s.own, 3), ...
                round(s.transferred, 3), round(s.difference, 3), round(s.transferredP95, 3), round(s.transferredMedian, 3), ...
                s.n, s.nCorrected, 'VariableNames', ["補正先の Wafer", "軸", "補正前の値|｜平均｜+3σ [nm]", ...
                "補正先で求めた|補正の残差|｜平均｜+3σ [nm]", "補正元の補正値を|当てた残差|｜平均｜+3σ [nm]", ...
                "差 [nm]|当てた − 補正先で|求めた", "当てた残差の|｜残差｜95% 点 [nm]", "当てた残差の|｜残差｜中央値 [nm]", ...
                "点の数", "比べた点"]);
            c.highOrderTransferTable.ColumnWidth = {170, 40, 120, 150, 160, 130, 130, 130, 70, 70};
            removeStyle(c.highOrderTransferTable);
            totals = find(s.wafer == "すべての補正先");
            if ~isempty(totals)
                addStyle(c.highOrderTransferTable, uistyle('FontWeight', 'bold'), 'row', totals);
            end
            c.highOrderTransferInfo.Text = char(strjoin([transfer.description + "を当てました。"; transfer.messages], " "));
        end

        function showHighOrderTermSelection(app)
            % 「k の選定」の結果の表
            c = app.Controls;
            selection = app.HighOrderTermSelection;
            if isempty(selection)
                c.highOrderSelectTable.Data = table();
                c.highOrderSelectApply.Enable = 'off';
                return
            end
            if selection.method == "importance"
                t = selection.importance;
                verdict = repmat("外す", height(t), 1);
                verdict(~t.keep & ~isfinite(t.importance)) = "外す（点の配置で決まらない）";
                verdict(t.keep) = "使う";
                verdict(t.protected) = "使う（k1〜k6）";
                % 列の名前の「|」は見出しの改行になるので、絶対値の記号は全角の「｜」にする
                c.highOrderSelectTable.Data = table(t.axis, "k" + string(t.k), t.term, t.order, round(t.importance, 2), ...
                    round(t.minT, 2), round(t.maxT, 2), t.nWafers, verdict, 'VariableNames', ["式", "k", "項", "次数", ...
                    "変数重要度", "Wafer 間の|最小", "Wafer 間の|最大", "Wafer の数", "判定"]);
                c.highOrderSelectTable.ColumnWidth = {40, 50, 80, 50, 110, 80, 80, 70, 'auto'};
                text = sprintf(['変数重要度が %g より小さい項を外すと、dx %d 項・dy %d 項になります。' ...
                    '「使う項にする」で表に写します。'], selection.threshold, numel(selection.used{1}), numel(selection.used{2}));
            else
                t = selection.steps;
                kText = "k" + string(t.k);
                kText(~isfinite(t.k)) = "";
                c.highOrderSelectTable.Data = table(t.axis, t.step, kText, t.term, round(t.bic, 2), round(t.change, 2), ...
                    'VariableNames', ["式", "手順", "足した k", "項", "BIC", "1つ前との差"]);
                text = sprintf(['今の使う項から、BIC が下がる項を足すと dx %d 項・dy %d 項になります（BIC が下がらなくなったら' ...
                    '止める）。「使う項にする」で表に写します。'], numel(selection.used{1}), numel(selection.used{2}));
            end
            c.highOrderSelectInfo.Text = char(strjoin([text; selection.messages], " "));
            c.highOrderSelectApply.Enable = 'on';
        end

        function updateHighOrderSelectionEnabled(app)
            % しきい値は変数重要度のときだけ使う
            c = app.Controls;
            c.highOrderSelectThreshold.Enable = onOff(string(c.highOrderSelectMethod.Value) == "importance");
        end

        function onSelectHighOrderTerms(app)
            runWithAlert(app, @() app.selectHighOrderTerms(), "k パラメータを選べませんでした", ...
                "左の①の入力のデータと Wafer を確かめてから、もう一度試してください。");
        end

        function onApplyHighOrderTermSelection(app)
            runWithAlert(app, @() app.applyHighOrderTermSelection(), "使う項にできませんでした", ...
                "「計算する」で選び直してから、もう一度試してください。");
        end

        function onTransferHighOrder(app)
            runWithAlert(app, @() app.transferHighOrderCorrection(), "補正値を当てられませんでした", ...
                "「補正を計算する」で補正元と補正先の Wafer を一緒に計算してから、もう一度試してください。");
        end
    end
end

function ax = axesInPanel(parent, row)
% 図を枠（uipanel）に入れて格子の row 行目に置く（下の行の説明が長くなっても図と重ならないように。MarkLayoutTab と同じ）
panel = uipanel(parent, 'BorderType', 'none');
place(panel, row, 1);
ax = uiaxes(uigridlayout(panel, [1, 1], 'Padding', 0));
end

function index = waferIndexes(labels, chosen)
% Wafer の番号か名前を、計算した Wafer の番号に直す
if isnumeric(chosen)
    index = reshape(chosen, 1, []);
    if any(index < 1 | index > numel(labels) | index ~= round(index))
        error('alignest:highOrderTransfer', 'Wafer の番号は 1〜%d です。', numel(labels));
    end
    return
end
[found, index] = ismember(string(chosen), labels);
if ~all(found)
    error('alignest:highOrderTransfer', '計算した Wafer にありません：%s', strjoin(string(chosen(~found)), "・"));
end
index = reshape(index, 1, []);
end

function value = roundOrNaN(row, name, digits)
% 表の1行の値を丸める（行が無ければ NaN）
value = NaN;
if height(row) >= 1
    value = round(row.(name)(1), digits);
end
end

function text = historyMetricLabel(metric)
labels = struct("highOrder", "高次補正の残差 |平均|+3σ [nm]", "highOrderP95", "高次補正の |残差| 95% 点 [nm]", ...
    "highOrderMedian", "高次補正の |残差| 中央値 [nm]", "rSquared", "決定係数 R²", "waferStage", ...
    "Wafer 高次補正だけの残差 |平均|+3σ [nm]", "commonStage", "＋Shot 共通補正の残差 |平均|+3σ [nm]");
text = labels.(metric);
end
