classdef (Abstract) HighOrderAnalysisTab < appui.Core
    %HIGHORDERANALYSISTAB 「7. Shot高次補正」の残差を調べて書き出す部分：ヒストグラム（補正前の値・Shot ごとの1次の残差・
    %   高次補正の残差、または補正の比較の条件の残差を重ねる。内周・外周で分けられる）、残差の成分分解（Wafer 線形成分・Shot
    %   共通成分・Shot 成分・残りに分け、k パラメータのどの項に近いかを出す。alignest.decomposeHighOrderResidual）、書き出し
    %   （点ごとの補正量・残差を計測データの形で、Shot ごとの k を横に並べて、補正の比較の全条件をまとめて。CSV・Excel）。
    %   入力のデータ・補正の計算・マップは HighOrderTab.m、補正の比較は HighOrderCompareTab.m。AlignmentEstimationApp（画面の
    %   本体）の一部で、ほかのタブの関数も同じように呼べる（どれも AlignmentEstimationApp の関数になる）。

    methods
        function data = drawHighOrderHistogram(app, source, axisName, waferIndex, region, series)
            %DRAWHIGHORDERHISTOGRAM 「ヒストグラム」：値の分布を重ねて描く（alignest.plot.residualHistogram。区間の幅は、
            %   重ねる値のうち最も狭い分布に合わせる）。source："run"（この計算の補正前の値・Shot ごとの1次の残差・高次補正の
            %   残差。どちらの補正もできた点）・"comparison"（「補正の比較」の条件ごとの高次補正の残差）、axisName："X"・"Y"、
            %   waferIndex：0 = すべての Wafer、region："all"・"内周"・"外周"、series：重ねる値の番号（一覧の番号。複数）。
            %   省略すると画面の選択。data は重ねた値ごとの名前・点の数・平均・標準偏差・|平均|+3σ の表。
            c = app.Controls;
            if nargin >= 2
                c.highOrderHistogramSource.Value = char(source);
                refreshHighOrderHistogramChoices(app);
            end
            if nargin >= 3
                c.highOrderHistogramAxis.Value = char(axisName);
            end
            if nargin >= 4
                c.highOrderHistogramWafer.Value = waferIndex;
            end
            if nargin >= 5
                c.highOrderHistogramRegion.Value = char(region);
            end
            if nargin >= 6
                c.highOrderHistogramSeries.Value = num2cell(reshape(series, 1, []));
            end
            ax = c.highOrderHistogramAxes;
            cla(ax, 'reset');
            legend(ax, 'off');
            data = table();
            set([c.highOrderHistogramSave, c.highOrderHistogramCopy], 'Enable', 'off');
            [series, names, waferLabels] = highOrderHistogramSeries(app);
            if isempty(waferLabels)
                c.highOrderHistogramInfo.Text = ternary(string(c.highOrderHistogramSource.Value) == "run", ...
                    '「補正を計算する」を押すと、補正前の値と残差の分布を重ねます。', ...
                    '「補正の比較」で「すべて計算して比べる」を押すと、条件ごとの残差の分布を重ねます。');
                return
            end
            chosen = cell2mat(c.highOrderHistogramSeries.Value);
            chosen = chosen(chosen >= 1 & chosen <= numel(series));
            if isempty(chosen)
                c.highOrderHistogramInfo.Text = '左の一覧で、重ねる値を選んでください（Ctrl・Shift で複数）。';
                return
            end
            axisName = string(c.highOrderHistogramAxis.Value);
            waferChoice = c.highOrderHistogramWafer.Value;
            region = string(c.highOrderHistogramRegion.Value);
            values = cell(1, numel(chosen));
            for k = 1:numel(chosen)
                points = series{chosen(k)}.points;
                keep = true(height(points), 1);
                if waferChoice >= 1
                    keep = points.wafer == waferLabels(waferChoice);
                end
                if region ~= "all"
                    keep = keep & points.zone == region;
                end
                values{k} = series{chosen(k)}.value(keep, 1 + (axisName == "Y"));
                values{k} = values{k}(isfinite(values{k}));
            end
            names = names(chosen);
            waferText = ternary(waferChoice >= 1, waferLabels(max(waferChoice, 1)), "すべての Wafer");
            regionText = ternary(region == "all", "", "・" + region + "の Shot");
            alignest.plot.residualHistogram(ax, values, waferText + regionText + "（" + axisName + "）", "nm", names, ...
                xLabelText="値 [nm]（補正前の値・残差）", seriesWord="値", finestBins=true);
            styleAxes(app, ax, app.AXES_FONT_SIZE);
            set([c.highOrderHistogramSave, c.highOrderHistogramCopy], 'Enable', 'on');
            [count, average, spread, overlay] = deal(zeros(numel(values), 1));
            for k = 1:numel(values)
                count(k) = numel(values{k});
                average(k) = mean(values{k});
                spread(k) = std(values{k});
                overlay(k) = abs(average(k)) + 3 * spread(k);
            end
            data = table(names(:), count, average, spread, overlay, 'VariableNames', ["name", "n", "mean", "std", ...
                "meanPlus3Sigma"]);
            texts = compose("%s：%d 点・|平均|+3σ %.3f nm", names(:), count, overlay);
            c.highOrderHistogramInfo.Text = char(strjoin(texts, "　") + "（確率密度。同じ区間で輪郭を重ねます）");
        end

        function decomposition = showHighOrderDecomposition(app, waferIndex, axisName, basis, shotTerms)
            %SHOWHIGHORDERDECOMPOSITION 「残差の成分分解」：高次補正の残差を Wafer 線形成分・Shot 共通成分・Shot 成分・残りに
            %   分け（alignest.decomposeHighOrderResidual）、成分ごと・項（k パラメータ）ごとの分を表と図に出す。
            %   waferIndex：0 = すべての Wafer、axisName："dx"・"dy"、basis："custom"（カスタムの k1〜k38 の項）・"formula"
            %   （補正の式の使う項。外周の式を分けたときは内周の式）、shotTerms："linear"（Shot 成分は k1〜k6）・"same"（分析の
            %   項と同じ）。省略すると画面の選択。decomposition は alignest.decomposeHighOrderResidual の結果（結果が無ければ []）。
            c = app.Controls;
            if nargin >= 2
                c.highOrderDecompositionWafer.Value = waferIndex;
            end
            if nargin >= 3
                c.highOrderDecompositionAxis.Value = char(axisName);
            end
            if nargin >= 4
                c.highOrderDecompositionBasis.Value = char(basis);
            end
            if nargin >= 5
                c.highOrderDecompositionShotTerms.Value = char(shotTerms);
            end
            ax = c.highOrderDecompositionAxes;
            cla(ax, 'reset');
            legend(ax, 'off');
            c.highOrderDecompositionTable.Data = table();
            removeStyle(c.highOrderDecompositionTable);
            set([c.highOrderDecompositionSave, c.highOrderDecompositionCopy], 'Enable', 'off');
            decomposition = [];
            run = app.HighOrderRun;
            if isempty(run)
                c.highOrderDecompositionInfo.Text = '「補正を計算する」を押すと、高次補正の残差を成分に分けます。';
                return
            end
            decomposition = highOrderDecompositionOf(app, run.result.points);
            labels = [string({run.wafers.label}), "すべての Wafer"];
            choice = c.highOrderDecompositionWafer.Value;
            waferLabel = labels(end);
            if choice >= 1 && choice <= numel(labels) - 1
                waferLabel = labels(choice);
            end
            axisName = ternary(string(c.highOrderDecompositionAxis.Value) == "dx", "X", "Y");
            levels = decomposition.levels(decomposition.levels.wafer == waferLabel & decomposition.levels.axis == axisName, :);
            terms = decomposition.terms(decomposition.terms.wafer == waferLabel & decomposition.terms.axis == axisName & ...
                decomposition.terms.nUnits > 0, :);   % 点の配置で決まらない項は出さない
            [rows, totalRows] = decompositionRows(levels, terms);
            c.highOrderDecompositionTable.Data = rows;
            addStyle(c.highOrderDecompositionTable, uistyle('FontWeight', 'bold'), 'row', totalRows);
            drawDecompositionChart(ax, levels, terms, waferLabel + "（" + string(c.highOrderDecompositionAxis.Value) + ...
                "）の残差の成分");
            styleAxes(app, ax, app.AXES_FONT_SIZE);
            set([c.highOrderDecompositionSave, c.highOrderDecompositionCopy], 'Enable', 'on');
            shares = compose("%s %.1f%%", levels.level, levels.share);
            c.highOrderDecompositionInfo.Text = char(sprintf(['高次補正の残差（%d 点、RMS %.3f nm）を、%s に分けました' ...
                '（残差の二乗和に占める割合）。項は k の小さい順に足し、足して減った二乗和をその項の分としています' ...
                '（前の項・前の成分で表せる分は前に入ります）。点の配置で決まらない項は出していません。'], levels.n(1), ...
                sqrt(sum(levels.ss) / max(levels.n(1), 1)), strjoin(shares, "・")));
        end

        function data = exportHighOrderValues(app, kind, value, filePath)
            %EXPORTHIGHORDERVALUES 「書き出し」：補正値・補正残差などの表を作り、filePath（.csv・.xlsx）に書く
            %   （alignest.writeHighOrderTable）。kind："points"（点ごとの値を計測データの形で。alignest.highOrderMeasurementTable。
            %   「1. データの読み込み」でそのまま読み直せる）・"shots"（Shot ごとの k を横に並べる。alignest.highOrderShotTable）・
            %   "conditions"（補正の比較の全条件の点ごとの値。alignest.highOrderConditionTable）。value：点ごとの値の種類
            %   （"residual"・"correction"・"linear"・"value"。shots では使わない）。filePath を省くか "" なら書かずに表だけ
            %   返す（画面の「書き出す表」に出す）。計算した後に設定・入力を変えていれば、書く前に計算し直す（「結果を Excel に
            %   書き出す…」と同じ）。補正の比較は、比べた後に条件・入力を変えていれば書かない（比べ直してください）。
            c = app.Controls;
            if nargin >= 2
                c.highOrderOutputKind.Value = char(kind);
            end
            if nargin >= 3
                c.highOrderOutputValue.Value = char(value);
            end
            if nargin < 4
                filePath = "";
            end
            filePath = string(filePath);
            kind = string(c.highOrderOutputKind.Value);
            value = string(c.highOrderOutputValue.Value);
            if filePath ~= "" && kind ~= "conditions" && ~isempty(app.HighOrderRun) && staleHighOrderText(app) ~= ""
                shown = c.highOrderOutputs.SelectedTab;
                computeHighOrder(app);   % 画面と同じ結果を書くため、今の設定・入力で計算し直す
                c.highOrderOutputs.SelectedTab = shown;
            end
            [data, notes] = highOrderOutputTable(app, kind, value);
            showHighOrderOutputPreview(app, data);
            if filePath ~= ""
                alignest.writeHighOrderTable(filePath, data, notes);
            end
        end
    end

    methods (Access = {?appui.Core})
        % ================= 7. Shot高次補正：ヒストグラム・残差の成分分解・書き出し =================
        function buildHighOrderHistogramTab(app, outputs)
            % 「ヒストグラム」のタブ：重ねる値の種類・軸・Wafer・範囲、重ねる値の一覧と図
            c = struct();
            tab = uitab(outputs, 'Title', 'ヒストグラム');
            c.highOrderHistogramTab = tab;
            grid = uigridlayout(tab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            controls = uigridlayout(grid, [2, 1], 'RowHeight', {'fit', 'fit'}, 'Padding', 0, 'RowSpacing', 4);
            onDraw = @(~, ~) app.drawHighOrderHistogram();
            first = uigridlayout(controls, [1, 4], 'ColumnWidth', {'fit', '1x', 'fit', 80}, 'Padding', 0);
            label(first, '重ねる値', 1, 1);
            c.highOrderHistogramSource = uidropdown(first, 'Items', {'この計算（補正前の値・Shot ごとの1次・高次補正の残差）', ...
                '補正の比較の条件（高次補正の残差）'}, 'ItemsData', {'run', 'comparison'}, 'ValueChangedFcn', ...
                @(~, ~) app.onHighOrderHistogramSourceChanged(), 'Tooltip', ['この計算：「補正を計算する」の結果の、' ...
                'どちらの補正もできた点の値。補正の比較の条件：「すべて計算して比べる」で計算した条件ごとの残差。']);
            place(c.highOrderHistogramSource, 1, 2);
            label(first, '軸', 1, 3);
            c.highOrderHistogramAxis = uidropdown(first, 'Items', {'X', 'Y'}, 'ItemsData', {'X', 'Y'}, ...
                'ValueChangedFcn', onDraw);
            place(c.highOrderHistogramAxis, 1, 4);
            second = uigridlayout(controls, [1, 6], 'ColumnWidth', {'fit', '1.2x', 'fit', '1x', 'fit', 'fit'}, 'Padding', 0);
            label(second, 'Wafer', 1, 1);
            c.highOrderHistogramWafer = uidropdown(second, 'Items', {'すべての Wafer'}, 'ItemsData', {0}, ...
                'ValueChangedFcn', onDraw);
            place(c.highOrderHistogramWafer, 1, 2);
            label(second, '範囲', 1, 3);
            c.highOrderHistogramRegion = uidropdown(second, 'Items', {'すべての Shot', '内周の Shot', '外周の Shot'}, ...
                'ItemsData', {'all', '内周', '外周'}, 'ValueChangedFcn', onDraw, 'Tooltip', ['外周：Shot 中心の半径が' ...
                '「外周の半径」以上の Shot（計算したときの値）。']);
            place(c.highOrderHistogramRegion, 1, 4);
            c.highOrderHistogramSave = uibutton(second, 'Text', '図を画像で保存…', 'Enable', 'off', 'ButtonPushedFcn', ...
                @(~, ~) app.saveFigureWithDialog("highOrderHistogram", 'shot_high_order_histogram.png'));
            place(c.highOrderHistogramSave, 1, 5);
            c.highOrderHistogramCopy = uibutton(second, 'Text', '図をコピー', 'Enable', 'off', 'Tooltip', ...
                app.COPY_TOOLTIP, 'ButtonPushedFcn', @(source, ~) app.onCopyFigure("highOrderHistogram", source));
            place(c.highOrderHistogramCopy, 1, 6);
            body = uigridlayout(grid, [1, 2], 'ColumnWidth', {190, '1x'}, 'Padding', 0, 'ColumnSpacing', 6);
            place(body, 2, 1);
            c.highOrderHistogramSeries = uilistbox(body, 'Items', {'—'}, 'ItemsData', {0}, 'Multiselect', 'on', ...
                'Value', {}, 'ValueChangedFcn', onDraw, 'Tooltip', '重ねる値（Ctrl・Shift を押しながらクリックで複数）。');
            panel = uipanel(body, 'BorderType', 'none');
            c.highOrderHistogramAxes = uiaxes(uigridlayout(panel, [1, 1], 'Padding', 0));
            c.highOrderHistogramInfo = uilabel(grid, 'WordWrap', 'on', 'Text', ...
                '「補正を計算する」を押すと、補正前の値と残差の分布を重ねます。');
            place(c.highOrderHistogramInfo, 3, 1);
            app.Controls = mergeStruct(app.Controls, c);
        end

        function buildHighOrderDecompositionTab(app, outputs)
            % 「残差の成分分解」のタブ：Wafer・式・分析の項・Shot 成分の項、図と表
            c = struct();
            tab = uitab(outputs, 'Title', '残差の成分分解');
            c.highOrderDecompositionTab = tab;
            grid = uigridlayout(tab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            controls = uigridlayout(grid, [2, 1], 'RowHeight', {'fit', 'fit'}, 'Padding', 0, 'RowSpacing', 4);
            onShow = @(~, ~) app.showHighOrderDecomposition();
            first = uigridlayout(controls, [1, 6], 'ColumnWidth', {'fit', '1.4x', 'fit', '0.6x', 'fit', 'fit'}, 'Padding', 0);
            label(first, 'Wafer', 1, 1);
            c.highOrderDecompositionWafer = uidropdown(first, 'Items', {'すべての Wafer'}, 'ItemsData', {0}, ...
                'ValueChangedFcn', onShow, 'Tooltip', 'すべての Wafer：Wafer ごとに分けた成分の二乗和を足し、係数は Wafer・Shot の平均。');
            place(c.highOrderDecompositionWafer, 1, 2);
            label(first, '式', 1, 3);
            c.highOrderDecompositionAxis = uidropdown(first, 'Items', {'dx（X）', 'dy（Y）'}, 'ItemsData', {'dx', 'dy'}, ...
                'ValueChangedFcn', onShow);
            place(c.highOrderDecompositionAxis, 1, 4);
            c.highOrderDecompositionSave = uibutton(first, 'Text', '図を画像で保存…', 'Enable', 'off', 'ButtonPushedFcn', ...
                @(~, ~) app.saveFigureWithDialog("highOrderDecomposition", 'shot_high_order_decomposition.png'));
            place(c.highOrderDecompositionSave, 1, 5);
            c.highOrderDecompositionCopy = uibutton(first, 'Text', '図をコピー', 'Enable', 'off', 'Tooltip', ...
                app.COPY_TOOLTIP, 'ButtonPushedFcn', @(source, ~) app.onCopyFigure("highOrderDecomposition", source));
            place(c.highOrderDecompositionCopy, 1, 6);
            second = uigridlayout(controls, [1, 4], 'ColumnWidth', {'fit', '1x', 'fit', '1x'}, 'Padding', 0);
            label(second, '分析の項', 1, 1);
            c.highOrderDecompositionBasis = uidropdown(second, 'Items', {'カスタム（k1〜k38）', '補正の式の使う項'}, ...
                'ItemsData', {'custom', 'formula'}, 'ValueChangedFcn', onShow, 'Tooltip', ['Shot 共通成分・Shot 成分を、どの' ...
                '項で表すか。カスタム：k1〜k38 のすべての項（補正の式に無い項に残差が近いかも分かります）。補正の式：計算に' ...
                '使った項（外周の式を分けたときは内周の式）。点の配置で決まらない項は使いません。']);
            place(c.highOrderDecompositionBasis, 1, 2);
            label(second, 'Shot 成分の項', 1, 3);
            c.highOrderDecompositionShotTerms = uidropdown(second, 'Items', {'k1〜k6（並進・倍率・回転）', ...
                '分析の項と同じ'}, 'ItemsData', {'linear', 'same'}, 'ValueChangedFcn', onShow, 'Tooltip', ['Shot ごとに' ...
                '別の係数で表す項。Shot の点の数より少ない項だけを使います（点の数と同じだけ項を使うと、計測の雑音まで項に' ...
                '入ってしまうため）。']);
            place(c.highOrderDecompositionShotTerms, 1, 4);
            views = uitabgroup(grid);
            place(views, 2, 1);
            chartTab = uitab(views, 'Title', '図');
            panel = uipanel(uigridlayout(chartTab, [1, 1], 'Padding', 0), 'BorderType', 'none');
            c.highOrderDecompositionAxes = uiaxes(uigridlayout(panel, [1, 1], 'Padding', 0));
            tableTab = uitab(views, 'Title', '表');
            c.highOrderDecompositionTable = uitable(uigridlayout(tableTab, [1, 1], 'Padding', 4), 'RowName', {}, ...
                'Data', table(), 'ColumnWidth', {110, 120, 90, 90, 70, 100, 80, 'auto'});
            c.highOrderDecompositionInfo = uilabel(grid, 'WordWrap', 'on', 'Text', ...
                '「補正を計算する」を押すと、高次補正の残差を成分に分けます。');
            place(c.highOrderDecompositionInfo, 3, 1);
            app.Controls = mergeStruct(app.Controls, c);
        end

        function refreshHighOrderHistogramChoices(app)
            % 「ヒストグラム」の重ねる値と Wafer の一覧（入力が変わったら、重ねる値はすべて選ぶ）
            c = app.Controls;
            if ~isfield(c, 'highOrderHistogramSeries')
                return
            end
            [series, names, waferLabels] = highOrderHistogramSeries(app);
            list = c.highOrderHistogramSeries;
            if isempty(series)
                list.Items = {'（値がありません）'};
                list.ItemsData = {0};
                list.Value = {};
            else
                changed = ~isequal(list.Items, cellstr(names));
                list.Items = cellstr(names);
                list.ItemsData = num2cell(1:numel(names));
                if changed
                    list.Value = list.ItemsData;
                end
            end
            setChoices(c.highOrderHistogramWafer, ["すべての Wafer", reshape(waferLabels, 1, [])], ...
                num2cell(0:numel(waferLabels)));
        end

        function refreshHighOrderDecompositionChoices(app)
            % 「残差の成分分解」の Wafer の一覧
            c = app.Controls;
            if ~isfield(c, 'highOrderDecompositionWafer')
                return
            end
            labels = strings(1, 0);
            if ~isempty(app.HighOrderRun)
                labels = string({app.HighOrderRun.wafers.label});
            end
            setChoices(c.highOrderDecompositionWafer, ["すべての Wafer", labels], num2cell(0:numel(labels)));
        end

        function [series, names, waferLabels] = highOrderHistogramSeries(app)
            % 重ねられる値：構造体の cell（points：点の表、value：点ごとの X・Y の値）と名前、Wafer の名前
            c = app.Controls;
            series = {};
            names = strings(0, 1);
            waferLabels = strings(0, 1);
            if string(c.highOrderHistogramSource.Value) == "run"
                run = app.HighOrderRun;
                if isempty(run)
                    return
                end
                points = run.result.points;
                compared = isfinite(points.residualX + points.linearResidualX);
                compared(:, 2) = isfinite(points.residualY + points.linearResidualY);
                columns = ["value", "linearResidual", "residual"];
                names = ["補正前の値"; "Shot ごとの1次の残差"; "高次補正の残差"];
                for k = 1:numel(columns)
                    value = [points.(columns(k) + "X"), points.(columns(k) + "Y")];
                    value(~compared) = NaN;   % どちらの補正もできた点（「補正の評価」と同じ）
                    series{end + 1} = struct("points", points, "value", value); %#ok<AGROW>
                end
                waferLabels = reshape(string({run.wafers.label}), [], 1);
                return
            end
            comparison = app.HighOrderComparison;
            if isempty(comparison) || ~isfield(comparison, 'results')
                return
            end
            labels = string({comparison.conditions.label});
            for k = 1:numel(comparison.results)
                result = comparison.results{k};
                if isempty(result)
                    continue
                end
                series{end + 1} = struct("points", result.points, "value", [result.points.residualX, ...
                    result.points.residualY]); %#ok<AGROW>
                names(end + 1, 1) = sprintf("%d. %s", k, labels(k)); %#ok<AGROW>
            end
            waferLabels = reshape(string({comparison.wafers.label}), [], 1);
        end

        function [decomposition, description] = highOrderDecompositionOf(app, points)
            % 「残差の成分分解」の画面の選択（分析の項・Shot 成分の項）で、点の残差を成分に分ける。description は選択の説明
            c = app.Controls;
            basis = string(c.highOrderDecompositionBasis.Value);
            shotTerms = string(c.highOrderDecompositionShotTerms.Value);
            terms = alignest.highOrderTerms("custom");
            basisText = "カスタム（k1〜k38）の項";
            if basis == "formula" && ~isempty(app.HighOrderRun)
                terms = app.HighOrderRun.result.terms;
                terms = terms(terms.zone ~= "外周", :);
                basisText = "補正の式の使う項";
            end
            decomposition = alignest.decomposeHighOrderResidual(points, terms=terms, shotTerms=shotTerms);
            description = "高次補正の残差を、Wafer 線形成分（Shot 中心の座標の1次）・Shot 共通成分・Shot 成分・残りの順に" + ...
                "最小二乗で分けた（分析の項：" + basisText + "、Shot 成分の項：" + ...
                ternary(shotTerms == "linear", "k1〜k6", "分析の項と同じ") + "。項は k の小さい順に足した）";
        end

        function drawShownHighOrderAnalysis(app)
            % 「ヒストグラム」「残差の成分分解」を開いているときだけ描き直す（閉じているときは、開いたときに描く：
            % onHighOrderOutputChanged。計算のたびに成分分解を求め直さないように）
            c = app.Controls;
            if ~isfield(c, 'highOrderDecompositionTab')
                return   % 画面を作っている途中
            end
            if c.highOrderOutputs.SelectedTab == c.highOrderHistogramTab
                drawHighOrderHistogram(app);
            elseif c.highOrderOutputs.SelectedTab == c.highOrderDecompositionTab
                showHighOrderDecomposition(app);
            elseif c.highOrderOutputs.SelectedTab == c.highOrderOutputTab
                showHighOrderOutputPreview(app);
            end
        end

        function buildHighOrderOutputTab(app, outputs)
            % 「書き出し」のタブ：書き出すもの・値・書き出すボタンと、書き出す表（はじめの行）
            c = struct();
            tab = uitab(outputs, 'Title', '書き出し');
            c.highOrderOutputTab = tab;
            grid = uigridlayout(tab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            controls = uigridlayout(grid, [2, 4], 'ColumnWidth', {'fit', '1x', 'fit', '0.8x'}, 'RowHeight', ...
                {'fit', 'fit'}, 'Padding', 0);
            onChange = @(~, ~) app.showHighOrderOutputPreview();
            label(controls, '書き出すもの', 1, 1);
            c.highOrderOutputKind = uidropdown(controls, 'Items', {'点ごとの値（計測データの形。読み直せる）', ...
                'Shot ごとの補正値（k を横に並べる）', '補正の比較の全条件の点ごとの値'}, 'ItemsData', {'points', 'shots', ...
                'conditions'}, 'ValueChangedFcn', onChange, 'Tooltip', ['点ごとの値：Operation・EqpId・LotID・Wafer・' ...
                'DateTime・shotNo・Direction・Xmm・Ymm・Radius・markNo・markXmm・markYmm・measX・measY・StsX・StsY の列で、' ...
                'measX・measY に選んだ値を入れます（「1. データの読み込み」や「Excel・CSV を読み込む…」でそのまま読めます）。' ...
                'Shot ごとの補正値：1行 = 1 Shot、k1〜kN（k1・k2 は Wafer 成分を足した Shot 中心での並進）。補正の比較：' ...
                '比べた条件ごとの値を列に並べます。']);
            place(c.highOrderOutputKind, 1, 2);
            label(controls, '値', 1, 3);
            c.highOrderOutputValue = uidropdown(controls, 'Items', {'高次補正の残差', '補正量', ...
                'Shot ごとの1次で補正した残差', '補正前の値'}, 'ItemsData', {'residual', 'correction', 'linear', 'value'}, ...
                'ValueChangedFcn', onChange);
            place(c.highOrderOutputValue, 1, 4);
            c.highOrderOutputInfo = uilabel(controls, 'WordWrap', 'on', 'Text', '');
            place(c.highOrderOutputInfo, 2, [1, 3]);
            c.highOrderOutputWrite = primaryButton(app, controls, '書き出す…', @(~, ~) app.onExportHighOrderValues());
            place(c.highOrderOutputWrite, 2, 4);
            c.highOrderOutputTable = uitable(grid, 'RowName', {}, 'Data', table());
            place(c.highOrderOutputTable, 2, 1);
            c.highOrderOutputNote = uilabel(grid, 'WordWrap', 'on', 'FontColor', app.Palette.muted, 'UserData', "muted", ...
                'Text', ['CSV は UTF-8（Windows の Excel でも日本語が読める形）、値の無いところは空欄です（計測データの形では ' ...
                'StsX・StsY が −1）。Excel は「説明」と「値」のシートに書きます。係数は mm の座標での値です。']);
            place(c.highOrderOutputNote, 3, 1);
            app.Controls = mergeStruct(app.Controls, c);
        end

        function showHighOrderOutputPreview(app, data)
            % 「書き出し」の表のはじめの行と説明（data を省くと、今の選択で作る。作れなければ知らせる）
            PREVIEW_ROWS = 200;   % 画面に出す行の数（すべての行はファイルに書く）
            c = app.Controls;
            if ~isfield(c, 'highOrderOutputTable')
                return
            end
            kind = string(c.highOrderOutputKind.Value);
            c.highOrderOutputValue.Enable = onOff(kind ~= "shots");
            c.highOrderOutputInfo.FontColor = app.Palette.text;
            if nargin < 2
                try
                    data = highOrderOutputTable(app, kind, string(c.highOrderOutputValue.Value));
                catch err
                    c.highOrderOutputTable.Data = table();
                    c.highOrderOutputWrite.Enable = 'off';
                    c.highOrderOutputInfo.Text = char("⚠ " + err.message);
                    c.highOrderOutputInfo.FontColor = app.Palette.error;
                    return
                end
            end
            c.highOrderOutputTable.Data = data(1:min(height(data), PREVIEW_ROWS), :);
            c.highOrderOutputWrite.Enable = 'on';
            text = sprintf("%d 行・%d 列", height(data), width(data));
            if height(data) > PREVIEW_ROWS
                text = text + sprintf("（はじめの %d 行を表示。すべての行を書きます）", PREVIEW_ROWS);
            end
            stale = "";
            if kind ~= "conditions" && staleHighOrderText(app) ~= ""
                stale = "。前の計算の結果です（書き出すときに計算し直します）";
            end
            c.highOrderOutputInfo.Text = char(text + stale);
        end

        function [data, notes] = highOrderOutputTable(app, kind, value)
            % 書き出す表と、Excel の「説明」シートに書く行
            [~, ~, valueLabel] = alignest.highOrderValueColumns(value);
            notes = ["作成日時", string(datetime('now', 'Format', 'yyyy/MM/dd HH:mm:ss'))];
            if kind == "conditions"
                comparison = app.HighOrderComparison;
                if isempty(comparison) || ~isfield(comparison, 'results') || isempty(comparison.results)
                    error('alignest:highOrderConditions', ['「補正の比較」で条件を足して「すべて計算して比べる」を押すと、' ...
                        '全条件の値を書き出せます。']);
                end
                if staleComparisonText(app) ~= ""
                    error('alignest:highOrderConditions', ['比べた後に条件・入力を変えました。「補正の比較」の「すべて計算して' ...
                        '比べる」で比べ直してから書き出してください。']);
                end
                labels = string({comparison.conditions.label});
                data = alignest.highOrderConditionTable(comparison.results, labels, value);
                descriptions = strings(numel(labels), 1);
                for k = 1:numel(labels)
                    descriptions(k) = "（計算できなかった）";
                    if ~isempty(comparison.results{k})
                        descriptions(k) = comparison.results{k}.description;
                    end
                end
                notes = [notes; "値", valueLabel + " [nm]"; compose("条件 %d. ", (1:numel(labels)).') + labels(:), ...
                    descriptions];
                return
            end
            run = app.HighOrderRun;
            if isempty(run)
                error('alignest:noHighOrder', '「補正を計算する」を押すと、補正値・残差を書き出せます。');
            end
            notes = [notes; "補正", run.result.description; "入力のデータ", highOrderSourceText(app, run.source)];
            if kind == "shots"
                data = alignest.highOrderShotTable(run.result);
                notes = [notes; "値", "Shot ごとの補正値（k）。k1・k2 は Wafer 成分を足した Shot 中心での並進"];
            else
                data = alignest.highOrderMeasurementTable(run.result, run.wafers, value);
                notes = [notes; "値", "measX・measY = " + valueLabel + " [nm]"];
            end
        end

        function onExportHighOrderValues(app)
            c = app.Controls;
            names = struct("points", "shot_high_order_values", "shots", "shot_high_order_k_per_shot", "conditions", ...
                "shot_high_order_conditions");
            [fileName, folder] = uiputfile({'*.csv', 'CSV（UTF-8） (*.csv)'; '*.xlsx', 'Excel ブック (*.xlsx)'}, ...
                '補正値・残差を書き出す', char(names.(string(c.highOrderOutputKind.Value)) + ".csv"));
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            if runWithAlert(app, @() app.exportHighOrderValues(string(c.highOrderOutputKind.Value), ...
                    string(c.highOrderOutputValue.Value), target), "書き出せませんでした", ...
                    "同じ名前のファイルを Excel で開いていれば閉じて、もう一度試してください。")
                uialert(app.Figure, sprintf('書き出しました：%s', target), '書き出しました', 'Icon', 'success');
            end
        end

        function onHighOrderHistogramSourceChanged(app)
            refreshHighOrderHistogramChoices(app);
            drawHighOrderHistogram(app);
        end
    end
end

% ================= このファイルだけで使う小さな関数 =================
function [rows, totalRows] = decompositionRows(levels, terms)
% 「残差の成分分解」の表：成分ごとに、成分の計の行（太字）とその項の行（k の小さい順）
parts = cell(height(levels), 1);
totalRows = zeros(1, 0);
count = 0;
for k = 1:height(levels)
    level = levels.level(k);
    mine = terms(terms.level == level, :);
    total = table(level + "（計）", "", "", "", "", sprintf("%.3f", levels.rms(k)), sprintf("%.2f", levels.share(k)), "", ...
        'VariableNames', ["成分", "項", "係数", "係数のばらつき", "係数を求めた数", "寄与の RMS [nm]", "割合 [%]", ...
        "最も大きい Shot"]);
    detail = table(repmat(level, height(mine), 1), mine.term, compose("%.4g", mine.coefficient), ...
        blankNaN(compose("%.4g", mine.spread), mine.spread), string(mine.nUnits), compose("%.3f", mine.rms), ...
        compose("%.2f", mine.share), mine.largest, 'VariableNames', total.Properties.VariableNames);
    parts{k} = [total; detail];
    totalRows(end + 1) = count + 1; %#ok<AGROW>
    count = count + 1 + height(mine);
end
rows = vertcat(parts{:});
end

function text = blankNaN(text, values)
text(~isfinite(values)) = "";
end

function drawDecompositionChart(ax, levels, terms, titleText)
% 成分の割合（上の4本）と、割合の大きい項（下）を横棒で描く。色は成分ごと。項の棒の数は、図の高さで名前が重ならない
% 数まで（最大 MAX_TERMS 本。すべての項は表にある）
MAX_TERMS = 12;
MIN_TERMS = 3;
BAR_PIXELS = 22;        % 棒1本に要る高さ（名前の文字が重ならない高さ）
OTHER_PIXELS = 110;     % 題名・横軸・凡例に使う高さ
LEVEL_COLORS = [0.0, 0.45, 0.74; 0.85, 0.33, 0.10; 0.47, 0.67, 0.19; 0.55, 0.55, 0.55];
GAP = 0.8;   % 成分の棒と項の棒の間
heightPixels = getpixelposition(ax);
fits = floor((heightPixels(4) - OTHER_PIXELS) / BAR_PIXELS) - height(levels) - 1;
maxTerms = min(MAX_TERMS, max(MIN_TERMS, fits));
[~, order] = sort(terms.share, 'descend');
terms = terms(order(1:min(maxTerms, numel(order))), :);
[~, levelOfTerm] = ismember(terms.level, levels.level);
positions = [1:height(levels), height(levels) + GAP + (1:height(terms))];
values = [levels.share; terms.share];
colorIndex = [(1:height(levels)).'; levelOfTerm];
names = [levels.level + "（計）"; terms.level + "：" + terms.term];
hold(ax, 'on');
handles = gobjects(1, height(levels));
for k = 1:numel(values)
    handle = barh(ax, positions(k), values(k), 0.7, 'FaceColor', LEVEL_COLORS(colorIndex(k), :), 'EdgeColor', 'none');
    if k <= height(levels)
        handle.DisplayName = levels.level(k);
        handles(k) = handle;
    else
        handle.HandleVisibility = 'off';
    end
    text(ax, values(k), positions(k), sprintf(' %.1f%%', values(k)), 'VerticalAlignment', 'middle', 'FontSize', 9, ...
        'Clipping', 'on');
end
hold(ax, 'off');
set(ax, 'YDir', 'reverse', 'YTick', positions, 'YTickLabel', cellstr(names), 'TickLabelInterpreter', 'none');
ylim(ax, [0.4, max(positions) + 0.6]);
xlim(ax, [0, max([values; 1]) * 1.15]);
xlabel(ax, '残差の二乗和に占める割合 [%]');
title(ax, titleText, 'Interpreter', 'none');
legend(ax, handles, 'Location', 'southoutside', 'NumColumns', 4, 'Box', 'off', 'AutoUpdate', 'off');
grid(ax, 'on');
box(ax, 'on');
end
