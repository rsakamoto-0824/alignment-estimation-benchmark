classdef (Abstract) HighOrderCompareTab < appui.Core
    %HIGHORDERCOMPARETAB 「7. Shot高次補正」の比べる部分：補正の比較（条件をまとめて計算する。くくり・λ のスイープ・保存した
    %   項の組み合わせ）、Wafer の比較（k パラメータ・残差を Wafer ごとに並べる）、項の組み合わせの保存と呼び出し。
    %   入力のデータ・補正の計算・マップは HighOrderTab.m。AlignmentEstimationApp（画面の本体）の一部で、ほかのタブの関数も
    %   同じように呼べる（どれも AlignmentEstimationApp の関数になる）。

    methods
        function conditions = addHighOrderConditions(app, kind, values)
            %ADDHIGHORDERCONDITIONS 「補正の比較」の条件を足す（今の補正の式・使う項・くくり・回帰の設定をもとにする）。
            %   kind："current"（今の設定のまま1つ）・"units"（くくりを Wafer 内で共通・Scan 方向ごと・行の偶奇ごと・Shot ごとに
            %   変えた4つ）・"lambda"（values の λ ごと。L2 正則化をかける）・"termSet"（values の名前の保存した項の組み合わせ）。
            %   足した後の条件の一覧を返す。
            if nargin < 3
                values = [];
            end
            readHighOrderControls(app);
            base = app.Settings.highOrder;
            options = alignest.highOrderOptions(app.Settings);   % 今の設定の誤りを先に知らせる
            added = struct("label", {}, "highOrder", {});
            switch string(kind)
                case "current"
                    added(1) = condition(conditionLabel(options), base);
                case "units"
                    names = ["common", "scan", "row", "shot"];
                    labels = ["Wafer 内で共通", "Scan 方向ごと", "行の偶奇ごと", "Shot ごと"];
                    for k = 1:numel(names)
                        variant = base;
                        variant.unit = names(k);
                        added(end + 1) = condition("くくり：" + labels(k) + "｜" + makerLabel(options), variant); %#ok<AGROW>
                    end
                case "lambda"
                    lambdas = reshape(double(values), 1, []);
                    if isempty(lambdas) || any(~isfinite(lambdas) | lambdas < 0)
                        error('alignest:highOrderLambda', 'λ は 0 以上の数を空白で区切って入れてください（例：0 0.01 0.1 1）。');
                    end
                    for lambda = unique(lambdas, 'stable')
                        variant = base;
                        variant.lambda = lambda;
                        variant.l2 = lambda > 0;
                        added(end + 1) = condition(sprintf("λ = %g｜%s", lambda, unitLabel(options)), variant); %#ok<AGROW>
                    end
                case "termSet"
                    sets = termSetTable(base.termSets);
                    row = find(sets.name == string(values), 1);
                    if isempty(row)
                        error('alignest:highOrderTermSet', '保存した項の組み合わせ「%s」がありません。', string(values));
                    end
                    variant = base;
                    variant.maker = sets.maker(row);
                    variant.excludedTerms = excludedFor(sets.maker(row), sets.terms{row});
                    added(1) = condition("組み合わせ：" + sets.name(row) + "｜" + unitLabel(options), variant);
                otherwise
                    error('alignest:highOrderCondition', '足す条件の種類が違います: %s', string(kind));
            end
            labels = string({app.HighOrderConditions.label});
            for k = 1:numel(added)
                label = added(k).label;
                suffix = 2;
                while any(labels == label)
                    label = added(k).label + sprintf("（%d）", suffix);
                    suffix = suffix + 1;
                end
                added(k).label = label;
                labels(end + 1) = label; %#ok<AGROW>
            end
            app.HighOrderConditions = [app.HighOrderConditions, added];
            conditions = app.HighOrderConditions;
            refreshHighOrderConditions(app);
        end

        function removeHighOrderConditions(app, indices)
            %REMOVEHIGHORDERCONDITIONS 「補正の比較」の条件を消す（indices を省くと、一覧で選んでいる条件。"all" ならすべて）。
            if nargin < 2
                indices = cell2mat(app.Controls.highOrderConditionList.Value);
            end
            if isequal(string(indices), "all")
                indices = 1:numel(app.HighOrderConditions);
            end
            app.HighOrderConditions(indices) = [];
            refreshHighOrderConditions(app);
        end

        function comparison = compareHighOrderConditionsNow(app, waferChoice)
            %COMPAREHIGHORDERCONDITIONSNOW 「すべて計算して比べる」：「補正の比較」の条件をすべて、今の入力のデータ・Wafer で
            %   計算し、すべての Wafer をまとめた評価を並べる（alignest.compareHighOrderConditions）。
            %   waferChoice：一覧の番号（複数可。0 = すべて）。省略すると画面で選んでいるもの。
            c = app.Controls;
            if isempty(app.HighOrderConditions)
                error('alignest:highOrderCondition', ['比べる条件がありません。「今の設定を足す」「4つのくくりを足す」' ...
                    '「λ ごとに足す」で条件を足してください。']);
            end
            refreshHighOrderChoices(app);
            if nargin >= 2
                if isequal(waferChoice, 0)
                    waferChoice = 1:numel(c.highOrderWafer.ItemsData);
                end
                c.highOrderWafer.Value = num2cell(reshape(waferChoice, 1, []));
            end
            readHighOrderControls(app);
            app.Figure.Pointer = 'watch';
            drawnow;
            restore = onCleanup(@() set(app.Figure, 'Pointer', 'arrow'));
            wafers = highOrderWafers(app);
            comparison = alignest.compareHighOrderConditions(wafers, app.Settings, app.HighOrderConditions);
            app.HighOrderComparison = struct("table", comparison, "conditions", app.HighOrderConditions, ...
                "source", string(c.highOrderSource.Value), "selection", {c.highOrderWafer.Value}, ...
                "measured", c.highOrderMeasured.Value);
            c.highOrderOutputs.SelectedTab = c.highOrderCompareTab;
            showHighOrderComparison(app);
        end

        function sets = saveHighOrderTermSet(app, name)
            %SAVEHIGHORDERTERMSET 今の補正の式と使う項（「使う項と VIF」の表）を、名前を付けて保存する（同じ名前は置き換える）。
            %   設定 settings.highOrder.termSets に入る（「設定を保存…」の JSON にも書く。画面を出しているときは、次に開いた
            %   ときも使えるようにする）。保存した組み合わせの名前の一覧を返す。
            name = strtrim(string(name));
            if name == "" || contains(name, "|")
                error('alignest:highOrderTermSet', '組み合わせの名前を入れてください（「|」は使えません）。');
            end
            readHighOrderControls(app);
            options = alignest.highOrderOptions(app.Settings);
            terms = alignest.highOrderTerms(options.maker, options.excludedTerms);
            line = name + "|" + options.maker + "|" + strjoin(string(terms.k(terms.used)).', " ");
            current = termSetTable(app.Settings.highOrder.termSets);
            lines = string(app.Settings.highOrder.termSets(:));
            lines = lines(current.name ~= name);
            app.Settings.highOrder.termSets = [lines; line];
            savePreference(app, 'highOrderTermSets', cellstr(app.Settings.highOrder.termSets));
            refreshHighOrderTermSets(app, name);
            sets = termSetTable(app.Settings.highOrder.termSets).name;
        end

        function applyHighOrderTermSet(app, name)
            %APPLYHIGHORDERTERMSET 保存した項の組み合わせを呼び出す（補正の式と使う項を、その組み合わせにする）。
            sets = termSetTable(app.Settings.highOrder.termSets);
            row = find(sets.name == string(name), 1);
            if isempty(row)
                error('alignest:highOrderTermSet', '保存した項の組み合わせ「%s」がありません。', string(name));
            end
            app.Settings.highOrder.maker = sets.maker(row);
            app.Settings.highOrder.excludedTerms = excludedFor(sets.maker(row), sets.terms{row});
            highOrderSettingsToControls(app);
            markHighOrderStale(app);
        end

        function deleteHighOrderTermSet(app, name)
            %DELETEHIGHORDERTERMSET 保存した項の組み合わせを消す。
            sets = termSetTable(app.Settings.highOrder.termSets);
            lines = string(app.Settings.highOrder.termSets(:));
            app.Settings.highOrder.termSets = lines(sets.name ~= string(name));
            savePreference(app, 'highOrderTermSets', cellstr(app.Settings.highOrder.termSets));
            refreshHighOrderTermSets(app);
        end

        function data = drawHighOrderWaferComparison(app, view, axisName, statistic)
            %DRAWHIGHORDERWAFERCOMPARISON 「Wafer の比較」：計算した Wafer ごとに、k パラメータ（view = "edge"：Shot の端での
            %   大きさ [nm]、"value"：係数そのもの）か残差（view = "residual"：補正前・Shot ごとの1次・高次補正の残差の
            %   statistic）を並べて描く。axisName："dx"・"dy"。statistic："meanPlus3Sigma"・"p95"・"median"。
            %   省略すると画面の選択。data は描いた値の表（Wafer × 項、または Wafer × 補正）。
            c = app.Controls;
            if nargin >= 2
                c.highOrderWaferView.Value = char(view);
            end
            if nargin >= 3
                c.highOrderWaferAxis.Value = char(axisName);
            end
            if nargin >= 4
                c.highOrderWaferStatistic.Value = char(statistic);
            end
            ax = c.highOrderWaferAxes;
            data = table();
            run = app.HighOrderRun;
            cla(ax, 'reset');
            legend(ax, 'off');
            c.highOrderWaferStatistic.Enable = onOff(string(c.highOrderWaferView.Value) == "residual");
            if isempty(run)
                c.highOrderWaferInfo.Text = '「補正を計算する」を押すと、Wafer ごとの k パラメータ・残差を並べます。';
                return
            end
            view = string(c.highOrderWaferView.Value);
            axisName = string(c.highOrderWaferAxis.Value);
            labels = reshape(string({run.wafers.label}), [], 1);
            colors = lines(max(numel(labels), 1));
            if view == "residual"
                data = residualByWafer(run.result.points, labels, axisName, string(c.highOrderWaferStatistic.Value));
                bars = bar(ax, categorical(labels, labels), data{:, 2:end}, 'grouped');
                names = ["補正前", "Shot ごとの1次（k1〜k6）", "高次補正"];
                for k = 1:numel(bars)
                    bars(k).DisplayName = names(k);
                end
                ylabel(ax, statisticLabel(string(c.highOrderWaferStatistic.Value)) + " [nm]");
                title(ax, sprintf("Wafer ごとの残差（%s）", axisName), 'Interpreter', 'none');
                legend(ax, 'Location', 'northoutside', 'NumColumns', 3, 'Box', 'off');
                c.highOrderWaferInfo.Text = ['残差は、高次補正と Shot ごとの1次の補正の両方ができた点で求めます' ...
                    '（|残差| の 95% 点・中央値は残差の大きさ）。'];
            else
                [data, termNames] = coefficientsByWafer(run, labels, axisName, view);
                hold(ax, 'on');
                x = 1:numel(termNames);
                for w = 1:numel(labels)
                    values = data{w, 2:2:end};
                    spread = data{w, 3:2:end};
                    errorbar(ax, x + (w - (numel(labels) + 1) / 2) * 0.08, values, spread, 'o-', 'Color', ...
                        colors(w, :), 'MarkerFaceColor', colors(w, :), 'LineWidth', 1, 'DisplayName', labels(w));
                end
                plot(ax, [0.5, numel(termNames) + 0.5], [0, 0], ':', 'Color', [0.4, 0.4, 0.4], 'HandleVisibility', 'off');
                hold(ax, 'off');
                set(ax, 'XTick', x, 'XTickLabel', cellstr(termNames), 'XTickLabelRotation', 45);
                xlim(ax, [0.5, max(numel(termNames), 1) + 0.5]);
                if view == "edge"
                    ylabel(ax, 'Shot の端での大きさ [nm]');
                    info = ['Shot の端での大きさ = 係数 × (Shot の幅/2)^(x のべき) × (Shot の高さ/2)^(y のべき)。項の効き目を' ...
                        '同じ単位 [nm] で比べられます。'];
                else
                    ylabel(ax, '係数（nm/mm^次数）');
                    info = '係数は mm の座標での値（定数 nm、1次 nm/mm、n 次 nm/mm^n）。';
                end
                if run.result.options.unit ~= "common"
                    info = [info, ' 1つの Wafer に k の組が複数あるとき（Shot ごと・Scan 方向ごと・行の偶奇ごと）は、組の平均と' ...
                        '標準偏差（ひげ）です。'];
                end
                title(ax, sprintf("Wafer ごとの k パラメータ（%s）", axisName), 'Interpreter', 'none');
                legend(ax, 'Location', 'northoutside', 'NumColumns', min(numel(labels), 4), 'Box', 'off', 'Interpreter', 'none');
                c.highOrderWaferInfo.Text = info;
            end
            grid(ax, 'on');
            box(ax, 'on');
            styleAxes(app, ax, app.AXES_FONT_SIZE);
        end
    end

    methods (Access = {?appui.Core})
        % ================= 7. Shot高次補正：補正の比較・Wafer の比較・項の組み合わせ =================
        function buildHighOrderCompareTab(app, outputs)
            % 「補正の比較」のタブ：条件の一覧（足す・消す）、すべて計算して比べる、結果の表と図
            c = struct();
            tab = uitab(outputs, 'Title', '補正の比較');
            c.highOrderCompareTab = tab;
            grid = uigridlayout(tab, [4, 1], 'RowHeight', {'fit', 70, '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            % 条件を足す・消す・計算するボタン（1行目）、λ のスイープ（2行目）、保存した組み合わせ（3行目）
            controls = uigridlayout(grid, [3, 1], 'RowHeight', {'fit', 'fit', 'fit'}, 'Padding', 0, 'RowSpacing', 4);
            buttons = uigridlayout(controls, [1, 5], 'ColumnWidth', {'fit', 'fit', '1x', 'fit', 'fit'}, 'Padding', 0);
            uibutton(buttons, 'Text', '今の設定を足す', 'ButtonPushedFcn', ...
                @(~, ~) app.onAddHighOrderConditions("current"), 'Tooltip', ['左の補正の式・使う項・くくり・回帰の設定を' ...
                '条件として足します。設定を変えて何回か押すと、補正の内容をまとめて比べられます。']);
            uibutton(buttons, 'Text', '4つのくくりを足す', 'ButtonPushedFcn', ...
                @(~, ~) app.onAddHighOrderConditions("units"), 'Tooltip', ['今の設定で、くくりだけを Wafer 内で共通・' ...
                'Scan 方向ごと・行の偶奇ごと・Shot ごとに変えた4つの条件を足します。']);
            c.highOrderConditionRemove = uibutton(buttons, 'Text', '選んだ条件を消す', 'ButtonPushedFcn', ...
                @(~, ~) app.onRemoveHighOrderConditions(), 'Tooltip', '一覧で何も選んでいなければ、すべての条件を消します。');
            place(c.highOrderConditionRemove, 1, 4);
            c.highOrderCompare = primaryButton(app, buttons, 'すべて計算して比べる', @(~, ~) app.onCompareHighOrder());
            place(c.highOrderCompare, 1, 5);
            sweep = uigridlayout(controls, [1, 3], 'ColumnWidth', {'fit', '1x', 'fit'}, 'Padding', 0);
            label(sweep, 'λ（空白で区切る）', 1, 1);
            c.highOrderSweepLambda = uieditfield(sweep, 'text', 'Value', '0 0.01 0.1 1', 'Tooltip', ...
                'L2 正則化の強さ λ を空白で区切って入れます（0 は L2 なし）。');
            place(c.highOrderSweepLambda, 1, 2);
            c.highOrderSweepButton = uibutton(sweep, 'Text', 'λ ごとに足す（スイープ）', 'ButtonPushedFcn', ...
                @(~, ~) app.onAddHighOrderConditions("lambda"), 'Tooltip', ['今の設定で、λ だけを左の値に変えた条件を' ...
                '足します（高次項だけの L2 正則化。λ ごとの残差を比べられます）。']);
            place(c.highOrderSweepButton, 1, 3);
            sets = uigridlayout(controls, [1, 3], 'ColumnWidth', {'fit', '1x', 'fit'}, 'Padding', 0);
            label(sets, '保存した組み合わせ', 1, 1);
            c.highOrderCompareTermSet = uidropdown(sets, 'Items', {'（保存した組み合わせはありません）'}, ...
                'ItemsData', {''}, 'Enable', 'off');
            place(c.highOrderCompareTermSet, 1, 2);
            c.highOrderCompareTermSetAdd = uibutton(sets, 'Text', 'この組み合わせを足す', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onAddHighOrderConditions("termSet"), 'Tooltip', ['「使う項と VIF」で' ...
                '保存した項の組み合わせを、今のくくり・回帰の設定で条件として足します。']);
            place(c.highOrderCompareTermSetAdd, 1, 3);
            c.highOrderConditionList = uilistbox(grid, 'Items', {'（条件はまだありません）'}, 'ItemsData', {0}, ...
                'Multiselect', 'on', 'Value', {}, 'Tooltip', '比べる条件（Ctrl・Shift で複数選んで消せます）。');
            place(c.highOrderConditionList, 2, 1);
            % 結果：表と図（中のタブで切り替える。狭い画面でも図の高さを取れるように）
            results = uitabgroup(grid, 'SelectionChangedFcn', @(~, ~) app.drawHighOrderComparisonChart());
            place(results, 3, 1);
            c.highOrderCompareResults = results;
            c.highOrderCompareTableTab = uitab(results, 'Title', '表');
            c.highOrderCompareTable = uitable(uigridlayout(c.highOrderCompareTableTab, [1, 1], 'Padding', 4), ...
                'RowName', {}, 'Data', table(), 'ColumnWidth', {170, 40, 90, 90, 90, 90, 90, 60, 60, 60, 70, 'auto'});
            c.highOrderCompareChartTab = uitab(results, 'Title', '図');
            chartGrid = uigridlayout(c.highOrderCompareChartTab, [2, 3], 'RowHeight', {'fit', '1x'}, 'ColumnWidth', ...
                {'fit', 260, '1x'}, 'Padding', 4, 'RowSpacing', 2);
            label(chartGrid, '図の値', 1, 1);
            c.highOrderCompareMetric = uidropdown(chartGrid, 'Items', {'高次補正の |平均|+3σ', ...
                '高次補正の |残差| 95% 点', '高次補正の |残差| 中央値'}, 'ItemsData', {'highOrder', 'highOrderP95', ...
                'highOrderMedian'}, 'ValueChangedFcn', @(~, ~) app.drawHighOrderComparisonChart());
            place(c.highOrderCompareMetric, 1, 2);
            c.highOrderComparePanel = uipanel(chartGrid, 'BorderType', 'none');
            place(c.highOrderComparePanel, 2, [1, 3]);
            c.highOrderCompareAxes = uiaxes(uigridlayout(c.highOrderComparePanel, [1, 1], 'Padding', 0));
            c.highOrderCompareInfo = uilabel(grid, 'WordWrap', 'on', 'Text', '');
            place(c.highOrderCompareInfo, 4, 1);
            app.Controls = mergeStruct(app.Controls, c);
        end

        function buildHighOrderWaferTab(app, outputs)
            % 「Wafer の比較」のタブ：Wafer ごとの k パラメータ・残差
            c = struct();
            tab = uitab(outputs, 'Title', 'Wafer の比較');
            c.highOrderWaferTab = tab;
            grid = uigridlayout(tab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            controls = uigridlayout(grid, [1, 6], 'ColumnWidth', {'fit', '1.4x', 'fit', '0.6x', 'fit', '1x'}, 'Padding', 0);
            onDraw = @(~, ~) app.drawHighOrderWaferComparison();
            label(controls, '表示', 1, 1);
            c.highOrderWaferView = uidropdown(controls, 'Items', {'k パラメータ（Shot の端での大きさ）', ...
                'k パラメータ（係数）', '残差'}, 'ItemsData', {'edge', 'value', 'residual'}, 'ValueChangedFcn', onDraw);
            place(c.highOrderWaferView, 1, 2);
            label(controls, '式', 1, 3);
            c.highOrderWaferAxis = uidropdown(controls, 'Items', {'dx（X）', 'dy（Y）'}, 'ItemsData', {'dx', 'dy'}, ...
                'ValueChangedFcn', onDraw);
            place(c.highOrderWaferAxis, 1, 4);
            label(controls, '残差の値', 1, 5);
            c.highOrderWaferStatistic = uidropdown(controls, 'Items', {'|平均|+3σ', '|残差| 95% 点', '|残差| 中央値'}, ...
                'ItemsData', {'meanPlus3Sigma', 'p95', 'median'}, 'ValueChangedFcn', onDraw);
            place(c.highOrderWaferStatistic, 1, 6);
            panel = uipanel(grid, 'BorderType', 'none');
            place(panel, 2, 1);
            c.highOrderWaferAxes = uiaxes(uigridlayout(panel, [1, 1], 'Padding', 0));
            c.highOrderWaferInfo = uilabel(grid, 'WordWrap', 'on', 'Text', ...
                '「補正を計算する」を押すと、Wafer ごとの k パラメータ・残差を並べます。');
            place(c.highOrderWaferInfo, 3, 1);
            app.Controls = mergeStruct(app.Controls, c);
        end

        function buildHighOrderTermSetControls(app, parent, row)
            % 「使う項と VIF」の下：項の組み合わせを名前を付けて保存・呼び出し・削除
            c = struct();
            setGrid = uigridlayout(parent, [1, 7], 'ColumnWidth', {'fit', '1x', 'fit', 'fit', '1.2x', 'fit', 'fit'}, ...
                'Padding', 0);
            place(setGrid, row, 1);
            label(setGrid, '組み合わせの名前', 1, 1);
            c.highOrderTermSetName = uieditfield(setGrid, 'text', 'Tooltip', ['今の補正の式と使う項（表の「使う」）に' ...
                '名前を付けて保存します。「補正の比較」の条件にも使えます。']);
            place(c.highOrderTermSetName, 1, 2);
            c.highOrderTermSetSave = uibutton(setGrid, 'Text', '保存', 'ButtonPushedFcn', ...
                @(~, ~) app.onSaveHighOrderTermSet());
            place(c.highOrderTermSetSave, 1, 3);
            label(setGrid, '保存した組み合わせ', 1, 4);
            c.highOrderTermSetList = uidropdown(setGrid, 'Items', {'（ありません）'}, 'ItemsData', {''}, 'Enable', 'off');
            place(c.highOrderTermSetList, 1, 5);
            c.highOrderTermSetApply = uibutton(setGrid, 'Text', '呼び出す', 'Enable', 'off', 'ButtonPushedFcn', ...
                @(~, ~) app.onApplyHighOrderTermSet());
            place(c.highOrderTermSetApply, 1, 6);
            c.highOrderTermSetDelete = uibutton(setGrid, 'Text', '削除', 'Enable', 'off', 'ButtonPushedFcn', ...
                @(~, ~) app.onDeleteHighOrderTermSet());
            place(c.highOrderTermSetDelete, 1, 7);
            app.Controls = mergeStruct(app.Controls, c);
        end

        function refreshHighOrderTermSets(app, selected)
            % 保存した項の組み合わせの一覧（「使う項と VIF」と「補正の比較」の2か所）を作り直す
            c = app.Controls;
            if ~isfield(c, 'highOrderTermSetList')
                return
            end
            sets = termSetTable(fieldOr(app.Settings.highOrder, "termSets", strings(0, 1)));
            has = ~isempty(sets.name);
            for list = [c.highOrderTermSetList, c.highOrderCompareTermSet]
                if has
                    previous = string(list.Value);
                    list.Items = cellstr(sets.name + "（" + sets.makerLabel + "・" + sets.count + " 項）");
                    list.ItemsData = cellstr(sets.name);
                    if nargin >= 2 && any(sets.name == string(selected))
                        list.Value = char(selected);
                    elseif any(sets.name == previous)
                        list.Value = char(previous);
                    end
                else
                    list.Items = {'（保存した組み合わせはありません）'};
                    list.ItemsData = {''};
                end
            end
            set([c.highOrderTermSetList, c.highOrderTermSetApply, c.highOrderTermSetDelete, c.highOrderCompareTermSet, ...
                c.highOrderCompareTermSetAdd], 'Enable', onOff(has));
        end

        function refreshHighOrderConditions(app)
            % 「補正の比較」の条件の一覧
            c = app.Controls;
            conditions = app.HighOrderConditions;
            if isempty(conditions)
                c.highOrderConditionList.Items = {'（条件はまだありません。上のボタンで足してください）'};
                c.highOrderConditionList.ItemsData = {0};
                c.highOrderConditionList.Value = {};
            else
                details = strings(1, numel(conditions));
                for k = 1:numel(conditions)
                    settings = app.Settings;
                    settings.highOrder = conditions(k).highOrder;
                    details(k) = alignest.highOrderOptions(settings).description;
                end
                c.highOrderConditionList.Items = cellstr(compose("%d. ", (1:numel(conditions)).') + ...
                    reshape(string({conditions.label}), [], 1) + "　（" + details(:) + "）");
                c.highOrderConditionList.ItemsData = num2cell(1:numel(conditions));
                c.highOrderConditionList.Value = {};
            end
            set([c.highOrderConditionRemove, c.highOrderCompare], 'Enable', onOff(~isempty(conditions)));
            showHighOrderComparison(app);
        end

        function showHighOrderComparison(app)
            % 補正の比較の表（軸ごとに高次補正の |平均|+3σ が最も小さい行を太字）と図、条件・入力を変えた後の知らせ
            c = app.Controls;
            if ~isfield(c, 'highOrderCompareTable')
                return   % 画面を作っている途中（色を付けるとき）
            end
            comparison = app.HighOrderComparison;
            removeStyle(c.highOrderCompareTable);
            if isempty(comparison) || isempty(comparison.table)
                c.highOrderCompareTable.Data = table();
                c.highOrderCompareInfo.Text = '';
                drawHighOrderComparisonChart(app);
                return
            end
            t = comparison.table;
            c.highOrderCompareTable.Data = table(t.label, t.axis, round(t.highOrder, 3), round(t.highOrderP95, 3), ...
                round(t.highOrderMedian, 3), round(t.linear, 3), round(t.before, 3), t.nTerms, t.kSets, t.skipped, ...
                t.nCorrected, t.note, 'VariableNames', ["条件", "軸", "高次補正 |平均|+3σ [nm]", "|残差| 95% 点 [nm]", ...
                "|残差| 中央値 [nm]", "Shot ごとの1次 [nm]", "補正前 [nm]", "項の数", "k の組の数", "補正しなかった組", ...
                "比べた点", "メモ"]);
            for axisName = ["X", "Y"]
                rows = find(t.axis == axisName & isfinite(t.highOrder));
                [~, best] = min(t.highOrder(rows));
                if ~isempty(best)
                    addStyle(c.highOrderCompareTable, uistyle('FontWeight', 'bold'), 'row', rows(best));
                end
            end
            stale = staleComparisonText(app);
            if stale == ""
                c.highOrderCompareInfo.Text = sprintf(['%d 条件を比べました（すべての Wafer の点。軸ごとに高次補正の ' ...
                    '|平均|+3σ が最も小さい行を太字）。'], numel(comparison.conditions));
                c.highOrderCompareInfo.FontColor = app.Palette.text;
            else
                c.highOrderCompareInfo.Text = char(stale);
                c.highOrderCompareInfo.FontColor = app.Palette.error;
            end
            drawHighOrderComparisonChart(app);
        end

        function drawHighOrderComparisonChart(app)
            % 補正の比較の図：条件ごとの高次補正の残差（選んだ値）を X・Y で並べる（Shot ごとの1次は破線）
            c = app.Controls;
            ax = c.highOrderCompareAxes;
            cla(ax, 'reset');
            legend(ax, 'off');
            comparison = app.HighOrderComparison;
            if isempty(comparison) || isempty(comparison.table)
                return
            end
            t = comparison.table;
            metric = string(c.highOrderCompareMetric.Value);
            labels = string({comparison.conditions.label});
            colors = [0, 0.447, 0.741; 0.850, 0.325, 0.098];
            hold(ax, 'on');
            axisNames = ["X", "Y"];
            for a = 1:2
                rows = t(t.axis == axisNames(a), :);
                [~, order] = ismember(labels, rows.label);
                values = nan(1, numel(labels));
                linear = nan(1, numel(labels));
                values(order > 0) = rows.(metric)(order(order > 0));
                linear(order > 0) = rows.linear(order(order > 0));
                plot(ax, 1:numel(labels), values, 'o-', 'Color', colors(a, :), 'MarkerFaceColor', colors(a, :), ...
                    'LineWidth', 1.2, 'DisplayName', "高次補正 " + axisNames(a));
                if metric == "highOrder"
                    plot(ax, 1:numel(labels), linear, 's--', 'Color', colors(a, :), 'LineWidth', 0.8, ...
                        'DisplayName', "Shot ごとの1次 " + axisNames(a));
                end
            end
            hold(ax, 'off');
            set(ax, 'XTick', 1:numel(labels), 'XTickLabel', cellstr(compose("%d", 1:numel(labels))));
            xlim(ax, [0.5, numel(labels) + 0.5]);
            xlabel(ax, '条件の番号（上の一覧の番号）');
            ylabel(ax, '残差 [nm]');   % 値の名前は上の「図の値」と凡例（図が低いと長い名前は切れるため）
            legend(ax, 'Location', 'northoutside', 'NumColumns', 4, 'Box', 'off');
            grid(ax, 'on');
            box(ax, 'on');
            styleAxes(app, ax, app.AXES_FONT_SIZE);
        end

        function text = staleComparisonText(app)
            % 比べた後に条件・入力を変えていれば、その知らせ（変えていなければ ""）
            comparison = app.HighOrderComparison;
            text = "";
            if isempty(comparison)
                return
            end
            c = app.Controls;
            if ~isequaln(comparison.conditions, app.HighOrderConditions) || ...
                    comparison.source ~= string(c.highOrderSource.Value) || ...
                    ~isequal(comparison.selection, c.highOrderWafer.Value) || comparison.measured ~= c.highOrderMeasured.Value
                text = "⚠ 条件・入力を変えました。「すべて計算して比べる」で比べ直してください（下は前の結果）。";
            end
        end

        function onAddHighOrderConditions(app, kind)
            c = app.Controls;
            values = [];
            if kind == "lambda"
                [values, ok] = parseNumbers(c.highOrderSweepLambda.Value);
                if ~ok
                    values = NaN;
                end
            elseif kind == "termSet"
                values = string(c.highOrderCompareTermSet.Value);
            end
            runWithAlert(app, @() app.addHighOrderConditions(kind, values), "条件を足せませんでした", ...
                "左の補正の式・回帰の設定と、λ の値（0 以上の数を空白区切り）を確かめてください。");
        end

        function onRemoveHighOrderConditions(app)
            if isempty(app.Controls.highOrderConditionList.Value)
                removeHighOrderConditions(app, "all");
            else
                removeHighOrderConditions(app);
            end
        end

        function onCompareHighOrder(app)
            app.Controls.highOrderError.Text = '';
            runWithAlert(app, @() app.compareHighOrderConditionsNow(), "補正を比べられませんでした", ...
                "入力のデータと Wafer を選び、比べる条件を足してください。");
        end

        function onSaveHighOrderTermSet(app)
            runWithAlert(app, @() app.saveHighOrderTermSet(app.Controls.highOrderTermSetName.Value), ...
                "組み合わせを保存できませんでした", "名前を入れてから「保存」を押してください（「|」は使えません）。");
        end

        function onApplyHighOrderTermSet(app)
            runWithAlert(app, @() app.applyHighOrderTermSet(string(app.Controls.highOrderTermSetList.Value)), ...
                "組み合わせを呼び出せませんでした", "保存した組み合わせを選んでください。");
        end

        function onDeleteHighOrderTermSet(app)
            runWithAlert(app, @() app.deleteHighOrderTermSet(string(app.Controls.highOrderTermSetList.Value)), ...
                "組み合わせを削除できませんでした", "保存した組み合わせを選んでください。");
        end
    end
end

% ================= このファイルだけで使う小さな関数 =================
function item = condition(label, highOrder)
item = struct("label", string(label), "highOrder", highOrder);
end

function text = conditionLabel(options)
% 条件の名前（補正の式・くくり・回帰・λ）
text = makerLabel(options) + "・" + unitLabel(options);
if options.l2 && options.lambda > 0
    text = text + sprintf("・λ = %g", options.lambda);
else
    text = text + "・L2 なし";
end
end

function text = makerLabel(options)
names = ["asml", "canon", "nikon", "custom"];
labels = ["ASML", "Canon", "Nikon", "カスタム"];
text = labels(names == options.maker);
end

function text = unitLabel(options)
names = ["common", "scan", "row", "shot"];
labels = ["Wafer 内で共通", "Scan 方向ごと", "行の偶奇ごと", "Shot ごと"];
text = labels(names == options.unit);
end

function sets = termSetTable(lines)
% 保存した項の組み合わせ（"名前|式|k の番号 …"）を表にする（読めない行は使わない）
lines = string(lines(:));
lines = lines(strlength(strtrim(lines)) > 0);
names = strings(0, 1);
makers = strings(0, 1);
terms = cell(0, 1);
for k = 1:numel(lines)
    parts = split(lines(k), "|");
    if numel(parts) ~= 3 || ~any(parts(2) == ["asml", "canon", "nikon", "custom"])
        continue
    end
    numbers = str2double(split(strtrim(parts(3))));
    if any(~isfinite(numbers))
        continue
    end
    names(end + 1, 1) = strtrim(parts(1)); %#ok<AGROW>
    makers(end + 1, 1) = parts(2); %#ok<AGROW>
    terms{end + 1, 1} = reshape(numbers, 1, []); %#ok<AGROW>
end
makerNames = ["asml", "canon", "nikon", "custom"];
makerLabels = ["ASML", "Canon", "Nikon", "カスタム"];
[~, position] = ismember(makers, makerNames);
labels = strings(size(makers));
labels(position > 0) = makerLabels(position(position > 0));
sets = struct("name", names, "maker", makers, "terms", {terms}, "makerLabel", labels, ...
    "count", cellfun(@numel, terms));
end

function excluded = excludedFor(maker, used)
% 使う項の k の番号から、使わない項（excludedTerms）を求める（k1〜k6 は外さない）
terms = alignest.highOrderTerms(maker);
excluded = reshape(terms.k(~terms.protected & ~ismember(terms.k, used)), 1, []);
end

function data = residualByWafer(points, labels, axisName, statistic)
% Wafer ごとの補正前・Shot ごとの1次・高次補正の残差の値（どちらの補正もできた点）
suffix = "X";
if axisName == "dy"
    suffix = "Y";
end
values = nan(numel(labels), 3);
for w = 1:numel(labels)
    rows = points(points.wafer == labels(w), :);
    compared = isfinite(rows.("residual" + suffix)) & isfinite(rows.("linearResidual" + suffix));
    columns = ["value", "linearResidual", "residual"] + suffix;
    for k = 1:3
        values(w, k) = statisticOf(rows.(columns(k))(compared), statistic);
    end
end
data = table(labels, values(:, 1), values(:, 2), values(:, 3), 'VariableNames', ["Wafer", "補正前", ...
    "Shot ごとの1次", "高次補正"]);
end

function value = statisticOf(values, statistic)
values = values(isfinite(values));
value = NaN;
if isempty(values)
    return
end
switch statistic
    case "meanPlus3Sigma"
        if numel(values) >= 2
            value = abs(mean(values)) + 3 * std(values);
        end
    case "p95"
        value = alignest.stats.percentile(abs(values), 95);
    otherwise
        value = median(abs(values));
end
end

function text = statisticLabel(statistic)
switch statistic
    case "meanPlus3Sigma"
        text = "|平均|+3σ";
    case "p95"
        text = "|残差| 95% 点";
    otherwise
        text = "|残差| 中央値";
end
end

function [data, termNames] = coefficientsByWafer(run, labels, axisName, view)
% Wafer ごとの項の値（Wafer の k の組の平均と標準偏差）。view = "edge" なら Shot の端での大きさ [nm]
coefficients = run.result.coefficients;
coefficients = coefficients(coefficients.axis == axisName & coefficients.component == "Shot 高次補正", :);
terms = run.result.terms(run.result.terms.axis == axisName & run.result.terms.used, :);
termNames = "k" + string(terms.k) + "（" + terms.term + "）";
values = nan(numel(labels), height(terms));
spread = zeros(numel(labels), height(terms));
for w = 1:numel(labels)
    rows = coefficients(coefficients.wafer == labels(w), :);
    sizeMm = run.wafers(w).unit.shotSizeMm;
    for t = 1:height(terms)
        mine = rows.value(rows.k == terms.k(t));
        if view == "edge"
            mine = mine * (sizeMm(1) / 2) ^ terms.xPower(t) * (sizeMm(2) / 2) ^ terms.yPower(t);
        end
        mine = mine(isfinite(mine));
        if ~isempty(mine)
            values(w, t) = mean(mine);
            if numel(mine) > 1
                spread(w, t) = std(mine);
            end
        end
    end
end
columns = cell(1, 2 * height(terms));
names = strings(1, 2 * height(terms));
for t = 1:height(terms)
    columns{2 * t - 1} = values(:, t);
    columns{2 * t} = spread(:, t);
    names(2 * t - 1) = termNames(t);
    names(2 * t) = termNames(t) + "の標準偏差";
end
data = [table(labels, 'VariableNames', "Wafer"), table(columns{:}, 'VariableNames', names)];
end
