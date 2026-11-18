classdef (Abstract) RotationTab < appui.Core
    %ROTATIONTAB 「9. 計測マップのローテーション」タブ：Shot・Mark ごとのばらつき（3σ）、しきい値で分けた計測の優先度と
    %   ローテーションする計測マップ、取り込んだ Wafer を FB 側と検証側に分けて、FB の補正値を検証側に当てた補正残差、条件を
    %   変えた検証の結果の比較、計測マップの書き出し。入力は「1. データ読込」の計測データ・「4. 結果一覧」の評価の推定値・
    %   「6. 未知の座標の推定」の推定値。計算は alignest.markVariability・rotationMaps・feedbackSimulation・exportRotationMaps。
    %   AlignmentEstimationApp（画面の本体）の一部。画面の部品は Controls、データ・結果は Core のプロパティに持つ。

    properties (Constant, Access = {?appui.Core})
        ROTATION_MAX_MAP_AXES = 6     % 計測マップを並べて描く数の上限
        ROTATION_DEFAULT_INTERVALS = "1 3"   % 計測の間隔の初期値（2段：優先度 1 は毎回、2 は 3 Lot に1回）
        ROTATION_THRESHOLD_QUANTILE = 0.75   % しきい値が空のとき、3σ のこの分位点を初期値にする（上位 25% を毎回計測）
        ROTATION_METRICS = {'sigma3Vector', 'sigma3Length', 'sigma3X', 'sigma3Y', 'sigma3Target'}
        ROTATION_METRIC_LABELS = {'ベクトル 3√(σX²+σY²)', '長さ |v| の 3σ', 'X の 3σ', 'Y の 3σ', '目的変数の 3σ'}
    end

    methods
        function setRotationInput(app, source, methodIndex, plan, group)
            %SETROTATIONINPUT 入力を選ぶ（画面で選ぶのと同じ）。source："data"（1. データ読込の計測データ）・"estimate"
            %   （4. 結果一覧の評価の推定値：学習に使った Mark は計測値、ほかは推定値）・"target"（6. 未知の座標の推定値）。
            %   methodIndex・plan：評価の推定値の手法の番号と学習パターン（"estimate" のとき）。group：対象の Wafer（"all"、
            %   "op:<Operation>"・"eqp:<EqpId>"・"both:<Operation>|<EqpId>"）。省略した値は今の選択のまま。
            c = app.Controls;
            c.rotationSource.Value = char(source);
            refreshRotationChoices(app);
            if nargin >= 3 && ~isempty(methodIndex)
                c.rotationMethod.Value = methodIndex;
            end
            if nargin >= 4 && strlength(string(plan)) > 0
                c.rotationPlan.Value = char(plan);
            end
            if nargin >= 5
                if ~any(strcmp(c.rotationGroup.ItemsData, char(group)))
                    error('alignest:rotationInput', '対象「%s」がありません。', group);
                end
                c.rotationGroup.Value = char(group);
            end
            onRotationInputChanged(app);
        end

        function variability = computeRotationVariability(app, level, shotStatistic, targetColumn)
            %COMPUTEROTATIONVARIABILITY 「ばらつきを求める」：選んだ入力・対象の Wafer で、Shot・Mark ごとの Wafer 間の 3σ
            %   （X・Y・ベクトル 3√(σX²+σY²)・長さ |v|・目的変数）を求め、図と表に出す（alignest.markVariability）。
            %   level："mark"・"shot"、shotStatistic："max"・"mean"（Shot ごとの代表値）、targetColumn：目的変数の列の名前
            %   （"" = なし。1. データ読込の計測データのときだけ）。省略すると画面の選択。
            c = app.Controls;
            if nargin >= 2
                c.rotationLevel.Value = char(level);
            end
            if nargin >= 3
                c.rotationShotStatistic.Value = char(shotStatistic);
            end
            if nargin >= 4
                if ~any(strcmp(c.rotationTarget.ItemsData, char(targetColumn)))
                    error('alignest:rotationInput', '目的変数の列「%s」がありません（数値の列を選んでください）。', targetColumn);
                end
                c.rotationTarget.Value = char(targetColumn);
            end
            updateRotationEnabled(app);
            [wafers, description] = rotationWafers(app);
            variability = alignest.markVariability(wafers, level=string(c.rotationLevel.Value), ...
                shotStatistic=string(c.rotationShotStatistic.Value));
            variability.description = description;
            app.RotationWafers = wafers;
            app.RotationVariability = variability;
            app.RotationMaps = [];
            app.RotationRun = [];
            if strlength(strtrim(string(c.rotationThresholds.Value))) == 0
                c.rotationThresholds.Value = char(defaultThreshold(app, variability));   % 上位の点を毎回計測する初期値
            end
            drawRotationVariability(app);
            drawRotationMaps(app);
            showRotationRun(app);
            c.rotationOutputs.SelectedTab = c.rotationVariabilityTab;
            c.rotationInfo.Text = char(sprintf("%s：%d Wafer、%s %d か所。", description, variability.nWafers, ...
                ternary(variability.level == "shot", "Shot", "Mark"), height(variability.table)));
            updateRotationEnabled(app);
        end

        function maps = makeRotationMaps(app, metric, thresholds, intervals)
            %MAKEROTATIONMAPS 「計測マップを作る」：指標の 3σ をしきい値（いくつでも）で優先度に分け、優先度ごとの計測の
            %   間隔（n Lot に1回）でローテーションする計測マップを作る（alignest.rotationMaps）。metric：指標の列の名前
            %   （"sigma3Vector" など）、thresholds：しきい値（数の並び）、intervals：優先度ごとの間隔。省略すると画面の値。
            c = app.Controls;
            if isempty(app.RotationVariability)
                error('alignest:rotationMaps', '先に「ばらつきを求める」を押してください。');
            end
            if nargin >= 2
                c.rotationMetric.Value = char(metric);
            end
            if nargin >= 3
                c.rotationThresholds.Value = char(strjoin(string(thresholds), " "));
            end
            if nargin >= 4
                c.rotationIntervals.Value = char(strjoin(string(intervals), " "));
            end
            [thresholdValues, ok] = parseNumbers(c.rotationThresholds.Value);
            if ~ok
                error('alignest:rotationMaps', 'しきい値は数を空白で区切って入れてください（例：5 3）。');
            end
            [intervalValues, ok] = parseNumbers(c.rotationIntervals.Value);
            if ~ok || isempty(intervalValues)
                error('alignest:rotationMaps', '計測の間隔は数を空白で区切って入れてください（例：1 3）。');
            end
            metricName = string(c.rotationMetric.Value);
            if metricName == "sigma3Target" && ~app.RotationVariability.hasTarget
                error('alignest:rotationMaps', '目的変数を選んで「ばらつきを求める」を押してから、目的変数の 3σ で分けてください。');
            end
            maps = alignest.rotationMaps(app.RotationVariability, metricName, thresholdValues, intervalValues);
            app.RotationMaps = maps;
            app.RotationRun = [];
            names = cellstr(maps.mapNames);
            c.rotationMapList.Items = names;
            c.rotationMapList.ItemsData = num2cell(1:maps.nMaps);
            c.rotationMapList.Value = num2cell(1:min(maps.nMaps, app.ROTATION_MAX_MAP_AXES));
            drawRotationVariability(app);
            drawRotationMaps(app);
            showRotationRun(app);
            c.rotationOutputs.SelectedTab = c.rotationMapTab;
            c.rotationMapInfo.Text = char(sprintf("計測マップ %d 枚、平均の計測率 %.1f%%。", maps.nMaps, ...
                100 * maps.averageRate) + strjoin(maps.rankNames, "、") + "。");
            updateRotationEnabled(app);
        end

        function result = runRotationFeedback(app, options)
            %RUNROTATIONFEEDBACK 「検証する」：選んだ入力の Wafer を並べて FB 側と検証側に分け、計測マップをローテーションして
            %   FB の補正値を求め、検証側に当てた補正残差を出す（alignest.feedbackSimulation）。結果は「条件の比較」に足す
            %   （「全計測とも比べる」なら、全点を計測した FB も足す）。名前と値の組で画面の欄を変えられる：order（"dateTime"・
            %   "lot"・"input"）・splitKind（"count"・"ratio"）・splitValue・rotationLots・model（"overlay"・"highOrder"）・
            %   transferMethod（"values"・"coefficients"）・compareFull（true・false）。result は計測マップで FB した結果。
            arguments
                app
                options.order (1, 1) string
                options.splitKind (1, 1) string
                options.splitValue (1, 1) double
                options.rotationLots (1, 1) double
                options.model (1, 1) string
                options.transferMethod (1, 1) string
                options.compareFull (1, 1) logical
            end
            c = app.Controls;
            controls = struct("order", c.rotationOrder, "splitKind", c.rotationSplitKind, "splitValue", c.rotationSplitValue, ...
                "rotationLots", c.rotationLots, "model", c.rotationModel, "transferMethod", c.rotationTransferMethod, ...
                "compareFull", c.rotationCompareFull);
            for name = string(fieldnames(options)).'
                value = options.(name);
                if isstring(value)
                    value = char(value);
                end
                controls.(name).Value = value;
            end
            if isempty(app.RotationMaps)
                error('alignest:feedbackSimulation', '先に「計測マップを作る」を押してください。');
            end
            updateRotationEnabled(app);
            simulationOptions = {'order', string(c.rotationOrder.Value), 'splitKind', string(c.rotationSplitKind.Value), ...
                'splitValue', c.rotationSplitValue.Value, 'rotationLots', c.rotationLots.Value, ...
                'model', string(c.rotationModel.Value), 'transferMethod', string(c.rotationTransferMethod.Value)};
            app.Figure.Pointer = 'watch';
            drawnow;
            restore = onCleanup(@() set(app.Figure, 'Pointer', 'arrow'));
            if c.rotationCompareFull.Value
                full = alignest.feedbackSimulation(app.RotationWafers, [], app.Settings, simulationOptions{:}, ...
                    'fullMeasurement', true);
                addRotationHistory(app, full, "全計測");
            end
            result = alignest.feedbackSimulation(app.RotationWafers, app.RotationMaps, app.Settings, simulationOptions{:});
            addRotationHistory(app, result, "計測マップ");
            app.RotationRun = result;
            showRotationRun(app);
            showRotationHistory(app);
            c.rotationOutputs.SelectedTab = c.rotationRunTab;
        end

        function data = compareRotationConditions(app, rows)
            %COMPAREROTATIONCONDITIONS 「条件の比較」：選んだ検証の結果（rows：履歴の番号。空ならすべて）の、検証側すべての
            %   Wafer の補正残差（|平均|+3σ、X・Y）と FB 側の計測率を並べて描く。data は図の値（number・計測率・X・Y の残差）。
            c = app.Controls;
            if nargin >= 2
                app.RotationHistorySelection = reshape(rows, 1, []);
            end
            data = drawRotationComparison(app);
            c.rotationOutputs.SelectedTab = c.rotationCompareTab;
        end

        function removeRotationConditions(app, rows)
            %REMOVEROTATIONCONDITIONS 検証の結果の履歴から rows（履歴の番号）を消す（空ならすべて消す）
            if nargin < 2 || isempty(rows)
                app.RotationHistory = app.RotationHistory([]);
            else
                app.RotationHistory(ismember([app.RotationHistory.number], rows)) = [];
            end
            app.RotationHistorySelection = zeros(1, 0);
            showRotationHistory(app);
        end

        function exportRotationMapsTo(app, filePath, selection)
            %EXPORTROTATIONMAPSTO 選んだ計測マップ（selection：マップの番号。省略すると「計測マップ」のタブで選んでいる
            %   マップ）を Excel（.xlsx）に書き出す（alignest.exportRotationMaps。「2. 評価の設定」の「Excel ファイルで指定」で
            %   そのまま読める形）。
            maps = app.RotationMaps;
            if isempty(maps)
                error('alignest:rotationMaps', '先に「計測マップを作る」を押してください。');
            end
            if nargin < 3
                selection = cell2mat(app.Controls.rotationMapList.Value);
            end
            alignest.exportRotationMaps(string(filePath), maps, selection, app.RotationVariability.description);
        end
    end

    methods (Access = {?appui.Core})
        function buildRotationTab(app)
            % 左：入力・ばらつき・優先度と計測マップ・FB の検証の欄、右：結果（ばらつき・計測マップ・FB の検証・条件の比較）
            tab = app.Tabs.rotation;
            body = uigridlayout(tab, [1, 2], 'ColumnWidth', {390, '1x'}, 'Padding', 8, 'ColumnSpacing', 10);
            registerResponsiveColumn(app, body, 1);
            left = uigridlayout(body, [16, 1], 'RowHeight', repmat({'fit'}, 1, 16), 'Padding', [0, 0, 6, 0], ...
                'RowSpacing', 5, 'Scrollable', 'on');
            sectionTitle = @(text, row) set(label(left, text, row, 1), 'FontWeight', 'bold');   % 左の欄の見出し（1列なので private の heading は使わない）
            sectionTitle('① 入力', 1);
            inputGrid = uigridlayout(left, [4, 2], 'ColumnWidth', {'fit', '1x'}, 'RowHeight', repmat({'fit'}, 1, 4), 'Padding', 0);
            place(inputGrid, 2, 1);
            label(inputGrid, '入力', 1, 1);
            c.rotationSource = uidropdown(inputGrid, 'Items', {'1. データ読込の計測データ', '4. 結果一覧の評価の推定値', ...
                '6. 未知の座標の推定値'}, 'ItemsData', {'data', 'estimate', 'target'}, ...
                'ValueChangedFcn', @(~, ~) app.onRotationSourceChanged(), 'Tooltip', ['ばらつきと FB の検証に使う値。' ...
                '評価の推定値：選んだ手法・学習パターンで、学習に使った Mark は計測値、ほかの Mark は推定値。未知の座標の' ...
                '推定値：「6.」で推定した点の値（Wafer × 学習データの組み合わせごと）。']);
            place(c.rotationSource, 1, 2);
            label(inputGrid, '手法', 2, 1);
            c.rotationMethod = uidropdown(inputGrid, 'Items', {'—'}, 'ItemsData', {0}, 'Enable', 'off', ...
                'ValueChangedFcn', @(~, ~) app.onRotationInputChanged());
            place(c.rotationMethod, 2, 2);
            label(inputGrid, '学習パターン', 3, 1);
            c.rotationPlan = uidropdown(inputGrid, 'Items', {'—'}, 'ItemsData', {''}, 'Enable', 'off', ...
                'ValueChangedFcn', @(~, ~) app.onRotationInputChanged());
            place(c.rotationPlan, 3, 2);
            label(inputGrid, '対象', 4, 1);
            c.rotationGroup = uidropdown(inputGrid, 'Items', {'すべての Wafer'}, 'ItemsData', {'all'}, ...
                'ValueChangedFcn', @(~, ~) app.onRotationInputChanged(), 'Tooltip', ['ばらつき・FB の検証に使う Wafer。' ...
                'Operation・EqpId の列があれば、Operation ごと・装置ごと・その組ごとに分けて求められます。']);
            place(c.rotationGroup, 4, 2);
            c.rotationInputInfo = uilabel(left, 'WordWrap', 'on', 'FontColor', app.Palette.muted, 'UserData', "muted", ...
                'Text', '');
            place(c.rotationInputInfo, 3, 1);

            sectionTitle('② Shot・Mark ごとのばらつき（3σ）', 4);
            spreadGrid = uigridlayout(left, [3, 2], 'ColumnWidth', {'fit', '1x'}, 'RowHeight', repmat({'fit'}, 1, 3), ...
                'Padding', 0);
            place(spreadGrid, 5, 1);
            label(spreadGrid, '単位', 1, 1);
            c.rotationLevel = uidropdown(spreadGrid, 'Items', {'Mark ごと', 'Shot ごと'}, 'ItemsData', {'mark', 'shot'}, ...
                'ValueChangedFcn', @(~, ~) app.updateRotationEnabled(), 'Tooltip', ['ばらつきと計測マップの単位。Shot ごと：' ...
                'Shot の中の Mark の 3σ の代表値で優先度を決め、Shot のすべての Mark をまとめて計測します。']);
            place(c.rotationLevel, 1, 2);
            label(spreadGrid, 'Shot の代表値', 2, 1);
            c.rotationShotStatistic = uidropdown(spreadGrid, 'Items', {'最大の Mark', '平均'}, 'ItemsData', {'max', 'mean'}, ...
                'Enable', 'off', 'Tooltip', 'Shot ごとのとき、Shot の中の Mark の 3σ のうち、最も大きい値か平均を Shot の値にします。');
            place(c.rotationShotStatistic, 2, 2);
            label(spreadGrid, '目的変数', 3, 1);
            c.rotationTarget = uidropdown(spreadGrid, 'Items', {'（なし）'}, 'ItemsData', {''}, 'Tooltip', ['ファイルの' ...
                '数値の列（列の対応で標準の項目にしなかった列）。選ぶと、その列の Shot・Mark ごとの 3σ も求めます' ...
                '（1. データ読込の計測データのとき）。']);
            place(c.rotationTarget, 3, 2);
            c.rotationComputeVariability = uibutton(left, 'Text', 'ばらつきを求める', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onComputeRotationVariability());
            place(c.rotationComputeVariability, 6, 1);

            sectionTitle('③ 計測の優先度と計測マップ', 7);
            mapGrid = uigridlayout(left, [3, 2], 'ColumnWidth', {'fit', '1x'}, 'RowHeight', repmat({'fit'}, 1, 3), ...
                'Padding', 0);
            place(mapGrid, 8, 1);
            label(mapGrid, '指標', 1, 1);
            c.rotationMetric = uidropdown(mapGrid, 'Items', app.ROTATION_METRIC_LABELS, 'ItemsData', app.ROTATION_METRICS, ...
                'ValueChangedFcn', @(~, ~) app.onRotationMetricChanged(), 'Tooltip', '優先度を分ける 3σ。');
            place(c.rotationMetric, 1, 2);
            label(mapGrid, 'しきい値', 2, 1);
            c.rotationThresholds = uieditfield(mapGrid, 'text', 'Value', '', 'Tooltip', ['3σ のしきい値（空白で区切って' ...
                'いくつでも。例：5 3）。しきい値が k 個なら優先度は k + 1 段で、しきい値以上の点ほど優先度が高い。空欄で' ...
                '「ばらつきを求める」を押すと、上位 25% の点を分ける値を入れます。']);
            place(c.rotationThresholds, 2, 2);
            label(mapGrid, '計測の間隔', 3, 1);
            c.rotationIntervals = uieditfield(mapGrid, 'text', 'Value', char(app.ROTATION_DEFAULT_INTERVALS), 'Tooltip', ...
                ['優先度ごとに、何 Lot に1回計測するか（空白で区切って、優先度の数だけ。例：しきい値 1 つなら「1 3」= ' ...
                '優先度 1 は毎回、2 は 3 Lot に1回）。計測マップの数は間隔の最小公倍数です。']);
            place(c.rotationIntervals, 3, 2);
            c.rotationMakeMaps = uibutton(left, 'Text', '計測マップを作る', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onMakeRotationMaps());
            place(c.rotationMakeMaps, 9, 1);

            sectionTitle('④ FB の検証', 10);
            fbGrid = uigridlayout(left, [6, 3], 'ColumnWidth', {'fit', '1x', 70}, 'RowHeight', repmat({'fit'}, 1, 6), ...
                'Padding', 0);
            place(fbGrid, 11, 1);
            label(fbGrid, '並び順', 1, 1);
            c.rotationOrder = uidropdown(fbGrid, 'Items', {'日時（DateTime）の古い順', 'LotID の順', '読み込みの順'}, ...
                'ItemsData', {'dateTime', 'lot', 'input'}, 'Tooltip', ['Wafer を並べ、前から FB 側にします（実際の FB と同じく、' ...
                '古い Wafer の補正値を新しい Wafer に当てる）。日時が読めない Wafer は後ろに並べます。']);
            place(c.rotationOrder, 1, [2, 3]);
            label(fbGrid, 'FB 側', 2, 1);
            c.rotationSplitKind = uidropdown(fbGrid, 'Items', {'割合', '枚数'}, 'ItemsData', {'ratio', 'count'}, ...
                'ValueChangedFcn', @(~, ~) app.onRotationSplitKindChanged(), 'Tooltip', '前から何枚（全体の何割）を FB 側にするか。');
            place(c.rotationSplitKind, 2, 2);
            c.rotationSplitValue = uieditfield(fbGrid, 'numeric', 'Value', 0.5, 'Limits', [0, Inf]);
            place(c.rotationSplitValue, 2, 3);
            label(fbGrid, 'ローテーション', 3, 1);
            c.rotationLots = uispinner(fbGrid, 'Value', 1, 'Limits', [1, 99], 'Step', 1, 'RoundFractionalValues', 'on', ...
                'Tooltip', ['何 Lot ごとに次の計測マップにするか（LotID が2つ以上なければ Wafer ごと）。最後のマップの次は' ...
                '1枚目に戻ります。']);
            place(c.rotationLots, 3, 2);
            label(fbGrid, 'Lot ごと', 3, 3);
            label(fbGrid, '補正のモデル', 4, 1);
            c.rotationModel = uidropdown(fbGrid, 'Items', {'2. の Overlay 補正', '7. の Shot 高次補正'}, ...
                'ItemsData', {'overlay', 'highOrder'}, 'ValueChangedFcn', @(~, ~) app.updateRotationEnabled(), 'Tooltip', ...
                ['FB の補正値を求めるモデル。2. の Overlay 補正：「2. 評価の設定」の Wafer 成分＋Shot 共通成分＋Shot ごとの' ...
                '成分。7. の Shot 高次補正：「7. Shot高次補正」の補正の式・くくり・回帰の設定。どちらも FB の補正値を' ...
                'そのまま検証側に当てます。']);
            place(c.rotationModel, 4, [2, 3]);
            label(fbGrid, '求め方', 5, 1);
            c.rotationTransferMethod = uidropdown(fbGrid, 'Items', {'点ごとに平均して求める', '補正値を平均する'}, ...
                'ItemsData', {'values', 'coefficients'}, 'Enable', 'off', 'Tooltip', ['7. の Shot 高次補正で FB 側が複数枚の' ...
                'とき：計測値を点ごとに平均して補正値を求めるか、Wafer ごとに求めた補正値を平均するか（2. の Overlay 補正は' ...
                '点ごとに平均）。']);
            place(c.rotationTransferMethod, 5, [2, 3]);
            c.rotationCompareFull = uicheckbox(fbGrid, 'Text', '全計測とも比べる', 'Value', true, 'Tooltip', ...
                '同じ分け方で、FB 側の全点を計測したときの検証も「条件の比較」に足します。');
            place(c.rotationCompareFull, 6, [1, 3]);
            actions = uigridlayout(left, [1, 2], 'ColumnWidth', {'1x', '1x'}, 'Padding', 0);
            place(actions, 12, 1);
            c.rotationRunButton = primaryButton(app, actions, '検証する', @(~, ~) app.onRunRotationFeedback());
            c.rotationRunButton.Enable = 'off';
            c.rotationExport = uibutton(actions, 'Text', '計測マップを書き出す…', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onExportRotationMaps(), 'Tooltip', ['「計測マップ」のタブで選んだマップを' ...
                ' Excel に書き出します（「2. 評価の設定」の「Excel ファイルで指定」で読める形）。']);
            c.rotationInfo = uilabel(left, 'WordWrap', 'on', 'Text', '');
            place(c.rotationInfo, 13, 1);
            c.rotationError = errorLabel(app, left, 14, 1);

            % 右：結果のタブ
            outputs = uitabgroup(body);
            c.rotationOutputs = outputs;
            c.rotationVariabilityTab = uitab(outputs, 'Title', 'ばらつき');
            spread = uigridlayout(c.rotationVariabilityTab, [2, 1], 'RowHeight', {'1.4x', '1x'}, 'Padding', 6, 'RowSpacing', 6);
            spreadAxes = uigridlayout(spread, [1, 2], 'ColumnWidth', {'1x', '1x'}, 'Padding', 0, 'ColumnSpacing', 8);
            c.rotationSpreadAxes = [uiaxes(spreadAxes), uiaxes(spreadAxes)];
            set(c.rotationSpreadAxes, 'Visible', 'off');
            c.rotationSpreadTable = uitable(spread, 'RowName', {}, 'Data', table());

            c.rotationMapTab = uitab(outputs, 'Title', '計測マップ');
            mapsGrid = uigridlayout(c.rotationMapTab, [3, 1], 'RowHeight', {'fit', '1x', 120}, 'Padding', 6, 'RowSpacing', 6);
            mapControls = uigridlayout(mapsGrid, [1, 3], 'ColumnWidth', {'fit', 260, '1x'}, 'Padding', 0);
            label(mapControls, '描く・書き出すマップ', 1, 1);
            c.rotationMapList = uilistbox(mapControls, 'Items', {}, 'Multiselect', 'on', 'Value', {}, ...
                'ValueChangedFcn', @(~, ~) app.drawRotationMaps(), 'Tooltip', ['描く計測マップ（6枚まで並べる）と、' ...
                '「計測マップを書き出す…」で書き出すマップ。Ctrl・Shift で複数。']);
            place(c.rotationMapList, 1, 2);
            c.rotationMapInfo = uilabel(mapControls, 'WordWrap', 'on', 'Text', '');
            place(c.rotationMapInfo, 1, 3);
            c.rotationMapAxesGrid = uigridlayout(mapsGrid, [2, 3], 'Padding', 0, 'RowSpacing', 6, 'ColumnSpacing', 6);
            c.rotationMapAxes = gobjects(1, app.ROTATION_MAX_MAP_AXES);
            for k = 1:app.ROTATION_MAX_MAP_AXES
                c.rotationMapAxes(k) = uiaxes(c.rotationMapAxesGrid);
                c.rotationMapAxes(k).Layout.Row = ceil(k / 3);
                c.rotationMapAxes(k).Layout.Column = mod(k - 1, 3) + 1;
            end
            set(c.rotationMapAxes, 'Visible', 'off');
            c.rotationMapTable = uitable(mapsGrid, 'RowName', {}, 'Data', table());

            c.rotationRunTab = uitab(outputs, 'Title', 'FB の検証');
            runGrid = uigridlayout(c.rotationRunTab, [3, 1], 'RowHeight', {'1x', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 6);
            runAxes = uigridlayout(runGrid, [1, 2], 'Padding', 0, 'ColumnSpacing', 8);
            c.rotationRunAxes = [uiaxes(runAxes), uiaxes(runAxes)];
            set(c.rotationRunAxes, 'Visible', 'off');
            runTables = uitabgroup(runGrid);
            summaryTab = uitab(runTables, 'Title', '補正残差');
            c.rotationRunTable = uitable(uigridlayout(summaryTab, [1, 1], 'Padding', 4), 'RowName', {}, 'Data', table());
            assignmentTab = uitab(runTables, 'Title', 'FB 側・検証側と計測マップ');
            c.rotationAssignmentTable = uitable(uigridlayout(assignmentTab, [1, 1], 'Padding', 4), 'RowName', {}, ...
                'Data', table());
            c.rotationRunInfo = uilabel(runGrid, 'WordWrap', 'on', 'Text', '');

            c.rotationCompareTab = uitab(outputs, 'Title', '条件の比較');
            compareGrid = uigridlayout(c.rotationCompareTab, [4, 1], 'RowHeight', {'fit', '1x', '1x', 'fit'}, 'Padding', 6, ...
                'RowSpacing', 6);
            compareControls = uigridlayout(compareGrid, [1, 3], 'ColumnWidth', {'fit', 'fit', '1x'}, 'Padding', 0);
            c.rotationCompareButton = uibutton(compareControls, 'Text', '選んだ条件を並べる', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.compareRotationConditions());
            c.rotationRemoveButton = uibutton(compareControls, 'Text', '選んだ条件を消す', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.removeRotationConditions(app.RotationHistorySelection));
            label(compareControls, '表で行を選んで（Ctrl・Shift で複数）並べます。選ばなければすべて。', 1, 3);
            c.rotationHistoryTable = uitable(compareGrid, 'RowName', {}, 'Data', table(), ...
                'CellSelectionCallback', @(~, event) app.onRotationHistorySelected(event));
            compareAxes = uigridlayout(compareGrid, [1, 2], 'ColumnWidth', {'2x', '1x'}, 'Padding', 0, 'ColumnSpacing', 8);
            c.rotationCompareAxes = [uiaxes(compareAxes), uiaxes(compareAxes)];
            set(c.rotationCompareAxes, 'Visible', 'off');
            c.rotationCompareInfo = uilabel(compareGrid, 'WordWrap', 'on', 'Text', ['「検証する」を押すたびに、条件と結果を' ...
                'ここに足します（アプリを閉じるまで残ります）。']);
            app.Controls = mergeStruct(app.Controls, c);
            refreshRotationChoices(app);
        end

        function refreshRotationChoices(app)
            % 入力の選択肢（評価の手法・学習パターン、対象の Wafer、目的変数の列）を、今のデータ・結果・推定に合わせる
            c = app.Controls;
            if ~isfield(c, 'rotationSource')
                return
            end
            % 評価の推定値：手法・学習パターン（計測データを読み込んで評価した結果だけ）
            results = app.Results;
            if ~isempty(results) && ~isImportedResults(results) && ~isempty(app.Data)
                labels = string({results.methods.label});
                setChoices(c.rotationMethod, labels, num2cell(1:numel(labels)));
                planLabels = unique(string({results.plans.label}), 'stable');
                setChoices(c.rotationPlan, planLabels, reshape(cellstr(planLabels), 1, []));
            else
                setChoices(c.rotationMethod, "—", {0});
                setChoices(c.rotationPlan, "—", {''});
            end
            % 目的変数：ファイルの数値の列
            names = strings(1, 0);
            if ~isempty(app.Data)
                names = numericAttributes(app.Data.units);
            end
            setChoices(c.rotationTarget, ["（なし）", names], [{''}, reshape(cellstr(names), 1, [])]);
            refreshRotationGroups(app);
            updateRotationEnabled(app);
        end

        function refreshRotationGroups(app)
            % 対象の Wafer の選択肢：すべて、Operation ごと・装置ごと（列に値があるとき）・その組ごと（どちらも2種類以上のとき）
            c = app.Controls;
            units = rotationUnits(app);
            operations = reshape(unique(string({units.operation})), 1, []);
            operations = operations(operations ~= "");
            eqpIds = reshape(unique(string({units.eqpId})), 1, []);
            eqpIds = eqpIds(eqpIds ~= "");
            items = "すべての Wafer";
            values = "all";
            items = [items, "Operation：" + operations];
            values = [values, "op:" + operations];
            items = [items, "装置：" + eqpIds];
            values = [values, "eqp:" + eqpIds];
            if numel(operations) >= 2 && numel(eqpIds) >= 2
                pairs = reshape(unique(string({units.operation}) + "|" + string({units.eqpId})), 1, []);
                items = [items, "Operation × 装置：" + replace(pairs, "|", "｜")];
                values = [values, "both:" + pairs];
            end
            setChoices(c.rotationGroup, items, cellstr(values));
        end

        function units = rotationUnits(app)
            % 選んだ入力の Wafer の計測データ（対象の選択肢を作るため。推定値の入力も元の Wafer の Operation・装置を使う）
            units = struct("operation", {}, "eqpId", {});
            if isempty(app.Data)
                return
            end
            units = app.Data.units;
        end

        function updateRotationEnabled(app)
            c = app.Controls;
            source = string(c.rotationSource.Value);
            hasData = ~isempty(app.Data);
            hasResults = ~isempty(app.Results) && ~isImportedResults(app.Results) && hasData;
            set([c.rotationMethod, c.rotationPlan], 'Enable', onOff(source == "estimate" && hasResults));
            c.rotationTarget.Enable = onOff(source == "data" && numel(c.rotationTarget.Items) > 1);
            c.rotationShotStatistic.Enable = onOff(string(c.rotationLevel.Value) == "shot");
            ready = hasData && (source == "data" || (source == "estimate" && hasResults) || ...
                (source == "target" && ~isempty(app.TargetRun)));
            c.rotationComputeVariability.Enable = onOff(ready);
            c.rotationMakeMaps.Enable = onOff(~isempty(app.RotationVariability));
            hasMaps = ~isempty(app.RotationMaps);
            set([c.rotationRunButton, c.rotationExport], 'Enable', onOff(hasMaps));
            c.rotationTransferMethod.Enable = onOff(string(c.rotationModel.Value) == "highOrder");
            hasHistory = ~isempty(app.RotationHistory);
            set([c.rotationCompareButton, c.rotationRemoveButton], 'Enable', onOff(hasHistory));
            infoText = "";
            switch source
                case "data"
                    if ~hasData
                        infoText = "「1. データ読込」で計測データを読み込んでください。";
                    end
                case "estimate"
                    if ~hasResults
                        infoText = "「3. 実行」で評価してください（計測データを読み込んで評価した結果の推定値を使います）。";
                    end
                case "target"
                    if isempty(app.TargetRun)
                        infoText = "「6. 未知の座標の推定」で推定してください。";
                    end
            end
            c.rotationInputInfo.Text = char(infoText);
        end

        function [wafers, description] = rotationWafers(app)
            % 選んだ入力・対象の Wafer を、ばらつき・FB の検証の入力（label・points・lot・dateTime・operation・eqpId）にする
            c = app.Controls;
            source = string(c.rotationSource.Value);
            group = string(c.rotationGroup.Value);
            targetColumn = string(c.rotationTarget.Value);
            wafers = struct("label", {}, "points", {}, "lot", {}, "dateTime", {}, "operation", {}, "eqpId", {});
            if isempty(app.Data)
                error('alignest:noData', '先に「1. データ読込」で計測データを読み込んでください。');
            end
            switch source
                case "data"
                    for k = 1:numel(app.Data.units)
                        unit = app.Data.units(k);
                        target = [];
                        if targetColumn ~= ""
                            target = str2double(unit.marks.attributes(:, string(unit.attributeNames) == targetColumn));
                        end
                        points = alignest.rotationPoints(alignest.highOrderUnitPoints(unit), unit.marks.markNo, target);
                        wafers(end + 1) = waferEntry(unit, unit.label, points); %#ok<AGROW>
                    end
                    description = "1. データ読込の計測データ";
                case "estimate"
                    results = app.Results;
                    if isempty(results) || isImportedResults(results)
                        error('alignest:rotationInput', '先に「3. 実行」で評価してください。');
                    end
                    methodIndex = c.rotationMethod.Value;
                    planLabel = string(c.rotationPlan.Value);
                    plans = results.plans;
                    chosen = find(string({plans.label}) == planLabel & [plans.ok]);
                    for p = chosen
                        unit = app.Data.units(plans(p).unitIndex);
                        out = cachedRotationEstimate(app, plans(p), p, methodIndex);
                        estimated = unit;
                        estimated.marks.measX(out.testIndex.X) = out.estimate.X;
                        estimated.marks.measY(out.testIndex.Y) = out.estimate.Y;
                        estimated.marks.validX(out.testIndex.X) = isfinite(out.estimate.X);
                        estimated.marks.validY(out.testIndex.Y) = isfinite(out.estimate.Y);
                        points = alignest.rotationPoints(alignest.highOrderUnitPoints(estimated, "推定値"), unit.marks.markNo);
                        wafers(end + 1) = waferEntry(unit, unit.label, points); %#ok<AGROW>
                    end
                    description = "4. 評価の推定値（" + results.methods(methodIndex).label + "｜" + planLabel + "）";
                otherwise
                    run = app.TargetRun;
                    if isempty(run)
                        error('alignest:rotationInput', '先に「6. 未知の座標の推定」で推定してください。');
                    end
                    for k = 1:numel(run.labels)
                        unit = app.Data.units(run.unitIndex(k));
                        points = alignest.rotationPoints(alignest.highOrderTargetPoints(unit, run.results{k}.table));
                        wafers(end + 1) = waferEntry(unit, string(run.labels(k)), points); %#ok<AGROW>
                    end
                    description = "6. 未知の座標の推定値（" + run.method.label + "）";
            end
            if group ~= "all"
                wafers = wafers(arrayfun(@(wafer) inGroup(wafer, group), wafers));
                description = description + "・" + string(c.rotationGroup.Items{strcmp(c.rotationGroup.ItemsData, group)});
            end
            if isempty(wafers)
                error('alignest:rotationInput', '選んだ入力・対象に Wafer がありません。');
            end
        end

        function out = cachedRotationEstimate(app, plan, planIndex, methodIndex)
            % 評価の推定値（alignest.estimateWafer。画面の推定結果の Map を使い回す。キーは alignest.collectEstimates と同じ）
            key = sprintf('%d|%d|%d', plan.unitIndex, planIndex, methodIndex);
            if isKey(app.MapCache, key)
                out = app.MapCache(key);
                return
            end
            unit = app.Data.units(plan.unitIndex);
            out = alignest.estimateWafer(unit, plan, app.Results.methods(methodIndex), app.Results.settings);
            app.MapCache(key) = out;
        end

        function threshold = defaultThreshold(app, variability)
            % しきい値の初期値：選んだ指標の 3σ の上位 25% を分ける値（2桁に丸める）
            metric = string(app.Controls.rotationMetric.Value);
            if metric == "sigma3Target" && ~variability.hasTarget
                metric = "sigma3Vector";
            end
            values = variability.table.(metric);
            values = sort(values(isfinite(values)));
            threshold = "";
            if isempty(values)
                return
            end
            value = values(max(1, ceil(app.ROTATION_THRESHOLD_QUANTILE * numel(values))));
            threshold = string(round(value, 2, 'significant'));
        end

        function drawRotationVariability(app)
            % 「ばらつき」：選んだ指標の 3σ を Wafer 上の色（左）と分布（右。しきい値の線）で描き、表に 3σ の大きい順に出す
            c = app.Controls;
            variability = app.RotationVariability;
            for ax = c.rotationSpreadAxes
                cla(ax, 'reset');
                colorbar(ax, 'off');
                legend(ax, 'off');
            end
            if isempty(variability)
                set(c.rotationSpreadAxes, 'Visible', 'off');
                c.rotationSpreadTable.Data = table();
                return
            end
            set(c.rotationSpreadAxes, 'Visible', 'on');
            metric = string(c.rotationMetric.Value);
            if metric == "sigma3Target" && ~variability.hasTarget
                metric = "sigma3Vector";
            end
            metricLabel = variability.metricLabels(variability.metrics == metric);
            rows = variability.table;
            values = rows.(metric);
            unit = app.Data.units(1);
            [centers, sizeMm] = deal(unique([unit.shots.Xmm, unit.shots.Ymm], 'rows'), unit.shotSizeMm);
            upper = max([values(isfinite(values)); eps]);
            markerSize = ternary(variability.level == "shot", 90, 30);
            alignest.plot.waferMap(c.rotationSpreadAxes(1), [rows.x, rows.y], [values, nan(size(values))], mode="X", ...
                colorRange=[0, upper], colorTitle="3σ", waferRadiusMm=app.Settings.data.waferRadiusMm, ...
                shotCenters=centers, shotSizeMm=sizeMm, showLegend=false, markerSize=markerSize, ...
                titleText=metricLabel);
            ax = c.rotationSpreadAxes(2);
            histogram(ax, values(isfinite(values)), 'FaceColor', [0.00, 0.45, 0.74], 'EdgeColor', 'none');
            [thresholds, ok] = parseNumbers(c.rotationThresholds.Value);
            if ok
                for t = thresholds
                    xline(ax, t, '--', sprintf('%.4g', t), 'Color', [0.85, 0.20, 0.15], 'LineWidth', 1.5, ...
                        'LabelVerticalAlignment', 'top');
                end
            end
            xlabel(ax, metricLabel);
            ylabel(ax, ternary(variability.level == "shot", 'Shot の数', 'Mark の数'));
            title(ax, sprintf('3σ の分布（%d Wafer）', variability.nWafers), 'Interpreter', 'none');
            grid(ax, 'on');
            box(ax, 'on');
            styleAxes(app, c.rotationSpreadAxes, app.AXES_FONT_SIZE);
            % 表：3σ の大きい順（計測マップを作っていれば優先度も）
            [~, order] = sort(values, 'descend', 'MissingPlacement', 'last');
            shown = rows(order, :);
            rank = nan(height(shown), 1);
            if ~isempty(app.RotationMaps)
                [~, position] = ismember(shown.key, app.RotationMaps.table.key);
                rank(position > 0) = app.RotationMaps.table.rank(position(position > 0));
            end
            data = table(shown.shotNo, shown.markNo, rank, round(shown.sigma3X, 3), round(shown.sigma3Y, 3), ...
                round(shown.sigma3Vector, 3), round(shown.sigma3Length, 3), round(shown.sigma3Target, 3), shown.nWafers, ...
                'VariableNames', ["shotNo", "markNo", "優先度", "X の 3σ", "Y の 3σ", "ベクトルの 3σ", "長さ｜v｜の 3σ", ...
                "目的変数の 3σ", "Wafer の数"]);
            if variability.level == "shot"
                data.markNo = [];
                data = renamevars(data, "Wafer の数", "Wafer の数（最大）");
            end
            c.rotationSpreadTable.Data = data;
        end

        function drawRotationMaps(app)
            % 「計測マップ」：選んだマップ（6枚まで）を並べて描き、マップごと・優先度ごとの計測数を表に出す
            c = app.Controls;
            maps = app.RotationMaps;
            for ax = c.rotationMapAxes
                cla(ax, 'reset');
                legend(ax, 'off');
                ax.Visible = 'off';
            end
            if isempty(maps)
                c.rotationMapTable.Data = table();
                c.rotationMapInfo.Text = '';
                return
            end
            chosen = cell2mat(c.rotationMapList.Value);
            chosen = chosen(1:min(numel(chosen), app.ROTATION_MAX_MAP_AXES));
            nShown = numel(chosen);
            nColumns = min(max(nShown, 1), 3);
            c.rotationMapAxesGrid.ColumnWidth = [repmat({'1x'}, 1, nColumns), repmat({0}, 1, 3 - nColumns)];
            c.rotationMapAxesGrid.RowHeight = ternary(nShown > 3, {'1x', '1x'}, {'1x', 0});
            unit = app.Data.units(1);
            centers = unique([unit.shots.Xmm, unit.shots.Ymm], 'rows');
            markerSize = ternary(maps.level == "shot", 60, 16);
            for k = 1:nShown
                ax = c.rotationMapAxes(k);
                ax.Visible = 'on';
                alignest.plot.rotationMap(ax, maps, chosen(k), waferRadiusMm=app.Settings.data.waferRadiusMm, ...
                    shotCenters=centers, shotSizeMm=unit.shotSizeMm, showLegend=k == 1, markerSize=markerSize);
            end
            styleAxes(app, c.rotationMapAxes(1:nShown), app.SMALL_AXES_FONT_SIZE);
            nRanks = numel(maps.rankNames);
            counts = zeros(maps.nMaps, nRanks);
            for r = 1:nRanks
                counts(:, r) = sum(maps.membership(maps.table.rank == r, :), 1).';
            end
            data = [table(maps.mapNames.', maps.counts.', round(100 * maps.rates.', 1), 'VariableNames', ...
                ["計測マップ", "計測数", "計測率 [%]"]), array2table(counts, 'VariableNames', "優先度 " + string(1:nRanks))];
            c.rotationMapTable.Data = data;
        end

        function showRotationRun(app)
            % 「FB の検証」：直近の検証の補正前・補正残差（検証側の Wafer ごと・すべて）と、FB 側・検証側の並び・計測マップ
            c = app.Controls;
            run = app.RotationRun;
            for ax = c.rotationRunAxes
                cla(ax, 'reset');
                legend(ax, 'off');
            end
            if isempty(run)
                set(c.rotationRunAxes, 'Visible', 'off');
                c.rotationRunTable.Data = table();
                c.rotationAssignmentTable.Data = table();
                c.rotationRunInfo.Text = '';
                return
            end
            s = run.summary;
            axisNames = unique(s.axis(s.n > 0), 'stable');
            for a = 1:2
                ax = c.rotationRunAxes(a);
                if a > numel(axisNames)
                    ax.Visible = 'off';
                    continue
                end
                ax.Visible = 'on';
                mine = s(s.axis == axisNames(a), :);
                bars = bar(ax, 1:height(mine), [mine.before, mine.residual], 'grouped');
                set(bars(1), 'FaceColor', [0.65, 0.65, 0.65], 'DisplayName', '補正前');
                set(bars(2), 'FaceColor', [0.00, 0.45, 0.74], 'DisplayName', '補正残差');
                xticks(ax, 1:height(mine));
                xticklabels(ax, cellstr(mine.wafer));
                ax.TickLabelInterpreter = 'none';
                ax.XTickLabelRotation = 30;
                ylabel(ax, '|平均|+3σ');
                title(ax, "検証側の補正残差（" + axisNames(a) + "）", 'Interpreter', 'none');
                grid(ax, 'on');
                box(ax, 'on');
                legend(ax, 'Location', 'northeast', 'Box', 'off');
            end
            styleAxes(app, c.rotationRunAxes, app.AXES_FONT_SIZE);
            c.rotationRunTable.Data = table(s.wafer, s.axis, s.n, s.nCorrected, round(s.before, 3), round(s.residual, 3), ...
                round(s.improvement, 3), 'VariableNames', ["Wafer", "軸", "点の数", "補正した点", "補正前の値|｜平均｜+3σ", ...
                "補正残差|｜平均｜+3σ", "改善|補正前 − 残差"]);
            a_ = run.assignment;
            c.rotationAssignmentTable.Data = table(a_.order, a_.wafer, a_.lot, a_.dateTime, a_.role, a_.map, a_.measured, ...
                a_.available, 'VariableNames', ["順", "Wafer", "LotID", "日時", "役割", "計測マップ", "使った点", "値のある点"]);
            c.rotationRunInfo.Text = char(strjoin([run.description + "。"; run.messages], " "));
        end

        function addRotationHistory(app, result, kind)
            % 検証の結果を履歴に足す（条件の比較に使う。アプリを閉じるまで残す）
            all_ = result.summary(result.summary.wafer == "すべての検証 Wafer", :);
            pick = @(axisName, name) firstOr(all_.(name)(all_.axis == axisName), NaN);
            history = app.RotationHistory;
            number = 1;
            if ~isempty(history)
                number = max([history.number]) + 1;
            end
            modelNames = struct("overlay", "2. Overlay 補正", "highOrder", "7. Shot 高次補正");
            entry = struct("number", number, "kind", string(kind), "model", modelNames.(result.options.model), ...
                "input", string(app.RotationVariability.description), ...
                "description", result.description, "rate", result.measurementRate, ...
                "beforeX", pick("X", "before"), "beforeY", pick("Y", "before"), ...
                "residualX", pick("X", "residual"), "residualY", pick("Y", "residual"), "result", result);
            if kind ~= "全計測"
                maps = app.RotationMaps;
                entry.description = entry.description + "、優先度：" + maps.metricLabel + " " + ...
                    strjoin(string(maps.thresholds), "・") + "（間隔 " + strjoin(string(maps.intervals), "・") + "）";
            end
            if isempty(history)
                app.RotationHistory = entry;
            else
                app.RotationHistory(end + 1) = entry;
            end
        end

        function showRotationHistory(app)
            % 「条件の比較」の表（番号・種類・計測率・補正前・補正残差・入力・条件）と図
            c = app.Controls;
            history = app.RotationHistory;
            updateRotationEnabled(app);
            if isempty(history)
                c.rotationHistoryTable.Data = table();
                drawRotationComparison(app);
                return
            end
            c.rotationHistoryTable.Data = table([history.number].', [history.kind].', [history.model].', ...
                round(100 * [history.rate].', 1), round([history.beforeX].', 3), round([history.residualX].', 3), ...
                round([history.beforeY].', 3), round([history.residualY].', 3), [history.input].', ...
                [history.description].', 'VariableNames', ["番号", "種類", "補正のモデル", "FB 側の計測率 [%]", ...
                "補正前 X", "補正残差 X", "補正前 Y", "補正残差 Y", "入力", "条件"]);
            c.rotationHistoryTable.ColumnWidth = {50, 100, 130, 120, 80, 90, 80, 90, 200, 'auto'};
            drawRotationComparison(app);
        end

        function data = drawRotationComparison(app)
            % 選んだ条件（無ければすべて）の補正残差（X・Y）と計測率を並べる
            c = app.Controls;
            history = app.RotationHistory;
            for ax = c.rotationCompareAxes
                cla(ax, 'reset');
                legend(ax, 'off');
            end
            data = table();
            if isempty(history)
                set(c.rotationCompareAxes, 'Visible', 'off');
                return
            end
            rows = app.RotationHistorySelection;
            chosen = history;
            if ~isempty(rows)
                chosen = history(ismember([history.number], rows));
            end
            if isempty(chosen)
                chosen = history;
            end
            set(c.rotationCompareAxes, 'Visible', 'on');
            numbers = [chosen.number];
            residuals = [[chosen.residualX].', [chosen.residualY].'];
            ax = c.rotationCompareAxes(1);
            bars = bar(ax, 1:numel(chosen), residuals, 'grouped');
            set(bars(1), 'FaceColor', [0.00, 0.45, 0.74], 'DisplayName', 'X');
            set(bars(2), 'FaceColor', [0.85, 0.33, 0.10], 'DisplayName', 'Y');
            xticks(ax, 1:numel(chosen));
            xticklabels(ax, cellstr(string(numbers)));
            xlabel(ax, '条件（番号）');
            ylabel(ax, '検証側の補正残差 |平均|+3σ');
            title(ax, '補正残差', 'Interpreter', 'none');
            grid(ax, 'on');
            box(ax, 'on');
            legend(ax, 'Location', 'northeast', 'Box', 'off');
            ax = c.rotationCompareAxes(2);
            bar(ax, 1:numel(chosen), 100 * [chosen.rate], 'FaceColor', [0.40, 0.65, 0.20]);
            xticks(ax, 1:numel(chosen));
            xticklabels(ax, cellstr(string(numbers)));
            xlabel(ax, '条件（番号）');
            ylabel(ax, 'FB 側の計測率 [%]');
            ylim(ax, [0, 105]);
            title(ax, '計測率', 'Interpreter', 'none');
            grid(ax, 'on');
            box(ax, 'on');
            styleAxes(app, c.rotationCompareAxes, app.AXES_FONT_SIZE);
            data = table(numbers.', 100 * [chosen.rate].', residuals(:, 1), residuals(:, 2), 'VariableNames', ...
                ["number", "rate", "residualX", "residualY"]);
            c.rotationCompareInfo.Text = char("番号：" + strjoin(string(numbers) + " = " + [chosen.kind] + "（" + ...
                [chosen.description] + "）", "、") + "。");
        end

        function onRotationSourceChanged(app)
            refreshRotationChoices(app);
            onRotationInputChanged(app);
        end

        function onRotationInputChanged(app)
            % 入力・対象を変えたら、前の入力で求めたばらつき・計測マップ・検証は消す（履歴は残す）
            app.RotationVariability = [];
            app.RotationMaps = [];
            app.RotationRun = [];
            drawRotationVariability(app);
            drawRotationMaps(app);
            showRotationRun(app);
            app.Controls.rotationInfo.Text = '';
            updateRotationEnabled(app);
        end

        function onRotationMetricChanged(app)
            drawRotationVariability(app);
        end

        function onRotationSplitKindChanged(app)
            % 割合なら 0.5、枚数なら全体の半分を初期値にする
            c = app.Controls;
            if string(c.rotationSplitKind.Value) == "ratio"
                c.rotationSplitValue.Value = 0.5;
            else
                count = 1;
                if ~isempty(app.RotationWafers)
                    count = max(1, floor(numel(app.RotationWafers) / 2));
                end
                c.rotationSplitValue.Value = count;
            end
        end

        function onRotationHistorySelected(app, event)
            if isempty(event.Indices)
                app.RotationHistorySelection = zeros(1, 0);
                return
            end
            history = app.RotationHistory;
            rows = unique(event.Indices(:, 1)).';
            rows = rows(rows <= numel(history));
            app.RotationHistorySelection = [history(rows).number];
        end

        function onComputeRotationVariability(app)
            c = app.Controls;
            c.rotationError.Text = '';
            runWithAlert(app, @() app.computeRotationVariability(), "ばらつきを求められませんでした", ...
                "入力と対象の Wafer を確かめてから、もう一度試してください。");
        end

        function onMakeRotationMaps(app)
            runWithAlert(app, @() app.makeRotationMaps(), "計測マップを作れませんでした", ...
                "しきい値と計測の間隔を確かめてから、もう一度試してください。");
        end

        function onRunRotationFeedback(app)
            runWithAlert(app, @() app.runRotationFeedback(), "FB の検証ができませんでした", ...
                "並び順・FB 側の枚数（割合）・補正のモデルの設定を確かめてから、もう一度試してください。");
        end

        function onExportRotationMaps(app)
            [fileName, folder] = uiputfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, '計測マップを書き出す', 'rotation_maps.xlsx');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            if runWithAlert(app, @() app.exportRotationMapsTo(target), "書き出せませんでした", ...
                    "保存先のフォルダを変えるか、同じ名前のファイルを Excel で開いていれば閉じてください。")
                uialert(app.Figure, sprintf('書き出しました：%s', target), '書き出しました', 'Icon', 'success');
            end
        end

        function clearRotation(app)
            % データを読み直したら、前のデータで求めたばらつき・計測マップ・検証を消す（条件の比較の履歴は残す）
            if ~isfield(app.Controls, 'rotationSource')
                return
            end
            app.RotationWafers = [];
            onRotationInputChanged(app);
            refreshRotationChoices(app);
        end
    end
end

% ================= このファイルだけで使う小さな関数 =================
function entry = waferEntry(unit, label, points)
entry = struct("label", string(label), "points", points, "lot", string(unit.lotId), "dateTime", string(unit.dateTime), ...
    "operation", string(unit.operation), "eqpId", string(unit.eqpId));
end

function yes = inGroup(wafer, group)
% 対象の Wafer か（"op:<Operation>"・"eqp:<EqpId>"・"both:<Operation>|<EqpId>"）
parts = split(group, ":");
kind = parts(1);
value = strjoin(parts(2:end), ":");
switch kind
    case "op"
        yes = wafer.operation == value;
    case "eqp"
        yes = wafer.eqpId == value;
    case "both"
        yes = wafer.operation + "|" + wafer.eqpId == value;
    otherwise
        yes = true;
end
end

function names = numericAttributes(units)
% 数値の「その他の列」（空でない値の 90% 以上が数として読める列）
MIN_NUMERIC_RATIO = 0.9;
names = strings(1, 0);
if isempty(units)
    return
end
allNames = string(units(1).attributeNames);
for j = 1:numel(allNames)
    values = strings(0, 1);
    for u = 1:numel(units)
        values = [values; units(u).marks.attributes(:, j)]; %#ok<AGROW>
    end
    values = values(strlength(strtrim(values)) > 0);
    if ~isempty(values) && mean(isfinite(str2double(values))) >= MIN_NUMERIC_RATIO
        names(end + 1) = allNames(j); %#ok<AGROW>
    end
end
end

function value = firstOr(values, fallback)
value = fallback;
if ~isempty(values)
    value = values(1);
end
end
