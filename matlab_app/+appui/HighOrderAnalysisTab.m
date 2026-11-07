classdef (Abstract) HighOrderAnalysisTab < appui.Core
    %HIGHORDERANALYSISTAB 「7. Shot高次補正」の残差を調べて書き出す部分：ヒストグラム（補正前の値・Shot ごとの1次の残差・
    %   Wafer 高次補正だけの残差・Wafer 高次補正＋Shot 共通補正の残差・高次補正の残差、または補正の比較の条件の残差を、X・Y を
    %   並べて重ねる。内周・外周で分けられる）、書き出し
    %   （点ごとの補正量・残差を計測データの形で、Shot ごとの k を横に並べて、補正の比較の全条件をまとめて。CSV・Excel）。
    %   入力のデータ・補正の計算・マップは HighOrderTab.m、補正の比較は HighOrderCompareTab.m。AlignmentEstimationApp（画面の
    %   本体）の一部で、ほかのタブの関数も同じように呼べる（どれも AlignmentEstimationApp の関数になる）。

    methods
        function data = drawHighOrderHistogram(app, source, waferIndex, region, series)
            %DRAWHIGHORDERHISTOGRAM 「ヒストグラム」：値の分布を X・Y を並べて重ねて描く（alignest.plot.residualHistogram。区間の
            %   幅は、重ねる値のうち最も狭い分布に合わせる）。source："run"（この計算の補正前の値・Shot ごとの1次の残差・Wafer 高次
            %   補正だけの残差・Wafer 高次補正＋Shot 共通補正の残差・高次補正の残差。補正できた点）・"comparison"（「補正の比較」の
            %   条件ごとの高次補正の残差）、waferIndex：0 = すべての Wafer、region："all"・"内周"・"外周"、series：重ねる値の番号
            %   （一覧の番号。複数）。省略すると画面の選択。data は軸・重ねた値ごとの名前・点の数・平均・標準偏差・|平均|+3σ の表。
            c = app.Controls;
            if nargin >= 2
                c.highOrderHistogramSource.Value = char(source);
                refreshHighOrderHistogramChoices(app);
            end
            if nargin >= 3
                c.highOrderHistogramWafer.Value = waferIndex;
            end
            if nargin >= 4
                c.highOrderHistogramRegion.Value = char(region);
            end
            if nargin >= 5
                c.highOrderHistogramSeries.Value = num2cell(reshape(series, 1, []));
            end
            axesList = c.highOrderHistogramAxes;
            for ax = axesList
                cla(ax, 'reset');
                legend(ax, 'off');
            end
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
                c.highOrderHistogramInfo.Text = '重ねる値を選んでください。';
                return
            end
            waferChoice = c.highOrderHistogramWafer.Value;
            region = string(c.highOrderHistogramRegion.Value);
            names = names(chosen);
            shortNames = highOrderHistogramShortNames(names);
            waferText = ternary(waferChoice >= 1, waferLabels(max(waferChoice, 1)), "すべての Wafer");
            regionText = ternary(region == "all", "", "・" + region + "の Shot");
            axisNames = ["X", "Y"];
            parts = cell(1, 2);
            for a = 1:2
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
                    values{k} = series{chosen(k)}.value(keep, a);
                    values{k} = values{k}(isfinite(values{k}));
                end
                alignest.plot.residualHistogram(axesList(a), values, waferText + regionText + "（" + axisNames(a) + "）", ...
                    "nm", shortNames, xLabelText="値 [nm]", seriesWord="値", finestBins=true, legendLocation="southoutside", ...
                    compactLegend=true);
                [count, average, spread, overlay] = deal(zeros(numel(values), 1));
                for k = 1:numel(values)
                    count(k) = numel(values{k});
                    average(k) = mean(values{k});
                    spread(k) = std(values{k});
                    overlay(k) = abs(average(k)) + 3 * spread(k);
                end
                parts{a} = table(repmat(axisNames(a), numel(values), 1), names(:), count, average, spread, overlay, ...
                    'VariableNames', ["axis", "name", "n", "mean", "std", "meanPlus3Sigma"]);
            end
            styleAxes(app, axesList, app.AXES_FONT_SIZE);
            set([c.highOrderHistogramSave, c.highOrderHistogramCopy], 'Enable', 'on');
            data = vertcat(parts{:});
            x = parts{1};
            y = parts{2};
            c.highOrderHistogramInfo.Text = char("|平均|+3σ [nm]（X・Y）：" + strjoin(compose("%s %.2f・%.2f", shortNames(:), ...
                x.meanPlus3Sigma, y.meanPlus3Sigma), "　"));
        end

        function data = exportHighOrderValues(app, kind, value, filePath)
            %EXPORTHIGHORDERVALUES 「書き出し」：補正値・補正残差などの表を作り、filePath（.csv・.xlsx）に書く
            %   （alignest.writeHighOrderTable）。kind："points"（点ごとの値を計測データの形で。alignest.highOrderMeasurementTable。
            %   「1. データの読み込み」でそのまま読み直せる）・"shots"（Shot ごとの k を横に並べる。alignest.highOrderShotTable）・
            %   "conditions"（補正の比較の全条件の点ごとの値。alignest.highOrderConditionTable）。value：点ごとの値の種類
            %   （"residual"・"correction"・"linear"・"wafer"・"common"・"value"。shots では使わない）。filePath を省くか "" なら書かずに表だけ
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
        % ================= 7. Shot高次補正：ヒストグラム・書き出し =================
        function buildHighOrderHistogramTab(app, outputs)
            % 「ヒストグラム」のタブ：重ねる値の種類・Wafer・範囲、重ねる値の一覧と X・Y の図
            c = struct();
            tab = uitab(outputs, 'Title', 'ヒストグラム');
            c.highOrderHistogramTab = tab;
            grid = uigridlayout(tab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            controls = uigridlayout(grid, [2, 1], 'RowHeight', {'fit', 'fit'}, 'Padding', 0, 'RowSpacing', 4);
            onDraw = @(~, ~) app.drawHighOrderHistogram();
            first = uigridlayout(controls, [1, 2], 'ColumnWidth', {'fit', '1x'}, 'Padding', 0);
            label(first, '重ねる値', 1, 1);
            c.highOrderHistogramSource = uidropdown(first, 'Items', {'この計算', ...
                '補正の比較の条件'}, 'ItemsData', {'run', 'comparison'}, 'ValueChangedFcn', ...
                @(~, ~) app.onHighOrderHistogramSourceChanged(), 'Tooltip', ['この計算：「補正を計算する」の結果の、' ...
                'どちらの補正もできた点の値。補正の比較の条件：「すべて計算して比べる」で計算した条件ごとの残差。']);
            place(c.highOrderHistogramSource, 1, 2);
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
            axesGrid = uigridlayout(panel, [1, 2], 'Padding', 0, 'ColumnSpacing', 6);
            c.highOrderHistogramAxes = [uiaxes(axesGrid), uiaxes(axesGrid)];
            c.highOrderHistogramInfo = uilabel(grid, 'WordWrap', 'on', 'Text', ...
                '「補正を計算する」を押すと、補正前の値と残差の分布を重ねます。');
            place(c.highOrderHistogramInfo, 3, 1);
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
                columns = ["value", "linearResidual", "waferResidual", "commonResidual", "residual"];
                names = ["補正前の値"; "Shot ごとの1次の残差"; "Wafer 高次補正だけの残差"; ...
                    "Wafer 高次補正＋Shot 共通補正の残差"; "高次補正の残差"];
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

        function drawShownHighOrderAnalysis(app)
            % 「ヒストグラム」「書き出し」を開いているときだけ描き直す（閉じているときは、開いたときに描く：
            % onHighOrderOutputChanged）
            c = app.Controls;
            if ~isfield(c, 'highOrderOutputTab')
                return   % 画面を作っている途中
            end
            if c.highOrderOutputs.SelectedTab == c.highOrderHistogramTab
                drawHighOrderHistogram(app);
            elseif c.highOrderOutputs.SelectedTab == c.highOrderOutputTab
                showHighOrderOutputPreview(app);
            end
        end

        function buildHighOrderOutputTab(app, outputs)
            % 「書き出し」のタブ：書き出すもの・値・書き出すボタンと、書き出す表（はじめの行）
            c = struct();
            tab = uitab(outputs, 'Title', '書き出し');
            c.highOrderOutputTab = tab;
            grid = uigridlayout(tab, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 6, 'RowSpacing', 4);
            controls = uigridlayout(grid, [2, 4], 'ColumnWidth', {'fit', '1x', 'fit', '0.8x'}, 'RowHeight', ...
                {'fit', 'fit'}, 'Padding', 0);
            onChange = @(~, ~) app.showHighOrderOutputPreview();
            label(controls, '書き出すもの', 1, 1);
            c.highOrderOutputKind = uidropdown(controls, 'Items', {'点ごとの値', ...
                'Shot ごとの補正値', '補正の比較の全条件の点ごとの値'}, 'ItemsData', {'points', 'shots', ...
                'conditions'}, 'ValueChangedFcn', onChange, 'Tooltip', ['点ごとの値：Operation・EqpId・LotID・Wafer・' ...
                'DateTime・shotNo・Direction・Xmm・Ymm・Radius・markNo・markXmm・markYmm・measX・measY・StsX・StsY の列で、' ...
                'measX・measY に選んだ値を入れます（「1. データの読み込み」や「Excel・CSV を読み込む…」でそのまま読めます）。' ...
                'Shot ごとの補正値：1行 = 1 Shot に、Wafer 低次・Wafer 高次・Shot 共通 低次・高次・Shot 毎 低次・高次の順と、' ...
                'その Shot に当てる k の合計。補正の比較：' ...
                '比べた条件ごとの値を列に並べます。']);
            place(c.highOrderOutputKind, 1, 2);
            label(controls, '値', 1, 3);
            c.highOrderOutputValue = uidropdown(controls, 'Items', {'高次補正の残差', '補正量', ...
                'Shot ごとの1次の残差', 'Wafer 高次補正だけの残差', 'Wafer 高次補正＋Shot 共通補正の残差', ...
                '補正前の値'}, 'ItemsData', {'residual', 'correction', 'linear', 'wafer', 'common', 'value'}, ...
                'ValueChangedFcn', onChange);
            place(c.highOrderOutputValue, 1, 4);
            c.highOrderOutputInfo = uilabel(controls, 'WordWrap', 'on', 'Text', '');
            place(c.highOrderOutputInfo, 2, [1, 3]);
            c.highOrderOutputWrite = primaryButton(app, controls, '書き出す…', @(~, ~) app.onExportHighOrderValues());
            place(c.highOrderOutputWrite, 2, 4);
            c.highOrderOutputTable = uitable(grid, 'RowName', {}, 'Data', table());
            place(c.highOrderOutputTable, 2, 1);
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
                text = text + sprintf("（はじめの %d 行を表示）", PREVIEW_ROWS);
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
                notes = [notes; "値", "Shot ごとの補正値。Wafer 低次・高次（Wafer 成分を Shot 中心で求めた並進 [nm]）、" + ...
                    "Wafer RT（使うとき。Shot の並進 [nm]）、" + ...
                    "Shot 共通 低次（k1〜k6）・高次、Shot 毎 低次・高次（Shot ごとのときだけ。Shot ごとの k − Shot 共通の k）の" + ...
                    "順。合計はその Shot に当てる k（Shot 共通 + Shot 毎。k1・k2 には Wafer 成分・Wafer RT の並進も足す）"];
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

function names = highOrderHistogramShortNames(names)
% 図の凡例の短い名前（図が狭いので。条件は番号だけ）
long = ["補正前の値", "Shot ごとの1次の残差", "Wafer 高次補正だけの残差", "Wafer 高次補正＋Shot 共通補正の残差", "高次補正の残差"];
short = ["補正前", "Shot ごとの1次", "Wafer 高次", "Wafer 高次＋Shot 共通", "高次補正"];
for k = 1:numel(long)
    names(names == long(k)) = short(k);
end
numbered = ~ismember(names, short);
names(numbered) = "条件 " + extractBefore(names(numbered), ".");
end
