classdef (Abstract) HighOrderTab < appui.Core
    %HIGHORDERTAB 「7. Shot高次補正」タブ：Shot 高次補正（Shot 内の座標の補正の式）の評価。入力のデータ（計測データ・未知の座標の
    %   推定値・Excel（列は読んだ後で選ぶ））、補正の式と k パラメータ（VIF で選ぶ。カスタムの式は k1〜k38）、k の組のくくり
    %   （Wafer 内で共通・Scan 方向ごと・行の偶奇ごと・Shot ごと）、回帰（ロバスト回帰・高次項だけの L2 正則化）、補正の評価・
    %   補正値・マップ（グリッド・並べて表示）・書き出し。計算は alignest.shotHighOrder。補正の比較・Wafer の比較・項の
    %   組み合わせの保存は HighOrderCompareTab.m。
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
            %   maker（"asml"・"canon"・"nikon"・"custom"）・unit（k の組のくくり："common"・"scan"・"row"・"shot"）・
            %   waferOrder（0〜5）・outerRadiusMm（外周の Shot の半径 [mm]）・outerMaker（外周の式："none"（分けない）・
            %   "asml"・"canon"・"nikon"・"custom"）・outerTermSet（外周の式にする保存した項の組み合わせの名前）・vifThreshold・
            %   loss（"ols"・"huber"・"lad"）・huberTuning・l2（true・false）・lambda・measured（推定値に学習に使った Mark の
            %   実測値も足すか）。例：app.setHighOrderSettings(unit="shot", loss="ols", l2=false)
            arguments
                app
                options.maker (1, 1) string
                options.unit (1, 1) string
                options.waferOrder (1, 1) double
                options.outerRadiusMm (1, 1) double
                options.outerMaker (1, 1) string
                options.outerTermSet (1, 1) string
                options.vifThreshold (1, 1) double
                options.loss (1, 1) string
                options.huberTuning (1, 1) double
                options.l2 (1, 1) logical
                options.lambda (1, 1) double
                options.measured (1, 1) logical
            end
            c = app.Controls;
            controls = struct("maker", c.highOrderMaker, "unit", c.highOrderUnit, "waferOrder", c.highOrderWaferOrder, ...
                "outerRadiusMm", c.highOrderOuterRadius, "outerMaker", c.highOrderOuterFormula, "outerTermSet", ...
                c.highOrderOuterFormula, "vifThreshold", c.highOrderVifThreshold, "loss", c.highOrderLoss, ...
                "huberTuning", c.highOrderHuber, "l2", c.highOrderL2, "lambda", c.highOrderLambda, "measured", ...
                c.highOrderMeasured);
            if isfield(options, "outerTermSet")
                if ~any(termSetTable(app.Settings.highOrder.termSets).name == options.outerTermSet)
                    error('alignest:highOrderTermSet', '保存した項の組み合わせ「%s」がありません。', options.outerTermSet);
                end
                options.outerTermSet = outerSetPrefix() + options.outerTermSet;
            end
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
            %LOADHIGHORDERFILE Shot 高次補正の入力にする Excel・CSV を読み（列の名前は自由）、項目に合う列を見出しから推定して
            %   「Excel・CSV の列」の表に出す（alignest.readHighOrderFile）。必須の項目の列がすべて見つかれば、その列で
            %   Wafer ごとのデータにして入力にする（applyHighOrderMapping）。見つからなければ、表で列を選んで「この列で使う」を
            %   押す。data は Wafer ごとのデータ（まだ列を選んでいなければ []）。
            if nargin < 3
                sheetName = "";
            end
            [raw, info] = alignest.readHighOrderFile(filePath, sheetName);
            app.HighOrderFile = struct("raw", raw, "info", info, "data", [], "mapping", info.mapping, ...
                "directionRule", "none");
            highOrderInputChanged(app, "file");   % 前に読んだ表で求めた結果は消す
            c = app.Controls;
            showHighOrderMapping(app, info.mapping);
            c.highOrderOutputs.SelectedTab = c.highOrderColumnTab;
            data = [];
            required = string({alignest.highOrderColumns().name});
            required = required([alignest.highOrderColumns().required]);
            if all(arrayfun(@(name) info.mapping.(name) ~= "", required))
                try
                    data = applyHighOrderMapping(app);
                    c.highOrderMappingStatus.Text = char("見出しから列を推定して読み込みました（" + ...
                        highOrderFileSummary(app) + "）。違っていれば列を選び直し、「この列で使う」を押してください。");
                    c.highOrderMappingStatus.FontColor = app.Palette.text;
                catch err
                    c.highOrderMappingStatus.Text = ['⚠ 推定した列では読み込めませんでした：' err.message ...
                        ' 列を選び直し、「この列で使う」を押してください。'];
                    c.highOrderMappingStatus.FontColor = app.Palette.error;
                end
            else
                c.highOrderMappingStatus.Text = sprintf(['%d 行・%d 列を読みました。「必須」の項目に、ファイルのどの列を' ...
                    '使うかを選び、「この列で使う」を押してください（見出しから推定できた列は選んであります）。'], ...
                    info.rows, numel(info.columns));
                c.highOrderMappingStatus.FontColor = app.Palette.text;
            end
            setHighOrderSource(app, "file");
        end

        function data = applyHighOrderMapping(app, columns, directionRule)
            %APPLYHIGHORDERMAPPING 「この列で使う」：「Excel・CSV の列」の表で選んだ列で、読み込んだ表を Wafer ごとのデータにし、
            %   入力を「Excel・CSV のデータ」にする（すべての Wafer を選ぶ。alignest.prepareHighOrderData）。
            %   columns（省略可）：表の選択を変える項目と列の名前の構造体（例：struct("measX", "OVL_X", "Direction", "")。
            %   "" は列なし）。directionRule（省略可）：Direction が無い行に付ける規則（alignest.directionRules の名前）。
            c = app.Controls;
            if isempty(app.HighOrderFile)
                error('alignest:noHighOrderFile', '先に「Excel・CSV を読み込む…」で表を読み込んでください。');
            end
            mapping = currentHighOrderMapping(app);
            if nargin >= 2
                for name = string(fieldnames(columns)).'
                    mapping.(name) = string(columns.(name));
                end
            end
            if nargin >= 3
                c.highOrderDirectionRule.Value = char(directionRule);
            end
            rule = string(c.highOrderDirectionRule.Value);
            showHighOrderMapping(app, mapping);
            [data, used] = alignest.prepareHighOrderData(app.HighOrderFile.raw, mapping, directionRule=rule);
            app.HighOrderFile.data = data;
            app.HighOrderFile.mapping = used;
            app.HighOrderFile.directionRule = rule;
            highOrderInputChanged(app, "file");   % 前の列で求めた結果は消す
            setHighOrderSource(app, "file");
            c.highOrderWafer.Value = num2cell(1:numel(data.units));   % 読み込んだ Wafer をすべて選ぶ
            refreshHighOrderTerms(app);
            c.highOrderMappingStatus.Text = char("この列で読み込みました（" + highOrderFileSummary(app) + "）。");
            c.highOrderMappingStatus.FontColor = app.Palette.text;
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
            %   求め、補正の評価・補正値・Wafer の比較・マップに出す（alignest.shotHighOrder。設定は settings.highOrder）。
            %   点の数が最も少ない k の組で求められない項は、k の小さい順に絞って求め、表の「使う」からも外す（メッセージで知らせる）。
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
            dropped = [result.reduction([result.reduction.zoneIndex] == 1).dropped];
            if ~isempty(dropped)
                % 点の数が最も少ない k の組で求められない項を外した：表の「使う」も外す（次の計算も同じ項になる）
                app.Settings.highOrder.excludedTerms = unique([reshape(app.Settings.highOrder.excludedTerms, 1, []), dropped]);
                refreshHighOrderTerms(app);
            end
            outerDropped = [result.reduction([result.reduction.zoneIndex] == 2).dropped];
            if ~isempty(outerDropped)
                app.Settings.highOrder.outerExcludedTerms = unique([reshape( ...
                    app.Settings.highOrder.outerExcludedTerms, 1, []), outerDropped]);   % 外周の式も同じ
            end
            app.HighOrderRun = struct("result", result, "wafers", wafers, "source", string(c.highOrderSource.Value), ...
                "selection", {c.highOrderWafer.Value}, "settings", app.Settings.highOrder, ...
                "measured", c.highOrderMeasured.Value);
            c.highOrderOutputs.SelectedTab = c.highOrderSummaryTab;   % 結果（補正の評価）を見せる
            showHighOrderRun(app);
        end

        function summary = drawHighOrderMap(app, waferIndex, view, value, mode, group, layout)
            %DRAWHIGHORDERMAP 「マップ」：選んだ Wafer の補正後の残差（または Shot ごとの1次で補正した残差・補正量・2次以上の
            %   項だけの補正量・補正前の値）を、Wafer 上（alignest.plot.correctionMap）か、Shot を重ねて（alignest.plot.shotStackMap）
            %   描く。表示がグリッドなら、求めた補正の式で変形させた Shot の形（alignest.plot.shotGridMap）を描く。
            %   waferIndex：計算した Wafer の番号、view："wafer"・"stack"、value："residual"・"linear"・"correction"・"highOnly"・
            %   "value"、mode："vector"・"X"・"Y"・"grid"、group：描く k の組（"" = すべての点。Scan 方向ごと・行の偶奇ごとの
            %   とき "Scan 方向 1"・"奇数行" など）、layout："single"（1つの図）・"side"（補正前の値・補正量・補正後の残差を並べる。
            %   矢印の倍率と色の範囲をそろえる）。省略すると画面の選択。summary は1つ目の図の点の数と |平均|+3σ
            %   （グリッドは Shot の数・倍率。結果が無ければ []）。
            c = app.Controls;
            if nargin >= 6
                c.highOrderMapGroup.Value = char(group);
            end
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
            if nargin >= 7
                c.highOrderMapLayout.Value = char(layout);
            end
            summary = [];
            run = app.HighOrderRun;
            axesList = [c.highOrderAxes, c.highOrderAxes2, c.highOrderAxes3];
            if isempty(run)
                showHighOrderMapPanels(app, 1);
                cla(c.highOrderAxes, 'reset');
                legend(c.highOrderAxes, 'off');
                set([c.highOrderSaveFigure, c.highOrderCopyFigure], 'Enable', 'off');
                c.highOrderMapInfo.Text = c.highOrderMapInfo.UserData;
                return
            end
            position = min(max(c.highOrderMapWafer.Value, 1), numel(run.wafers));
            wafer = run.wafers(position);
            points = run.result.points(run.result.points.wafer == string(wafer.label), :);
            groupName = string(c.highOrderMapGroup.Value);
            titleText = string(wafer.label);
            inGroup = true(height(points), 1);
            if groupName ~= ""
                inGroup = points.group == groupName;
                titleText = titleText + "（" + groupName + "）";
            end
            mode = string(c.highOrderMapMode.Value);
            stack = string(c.highOrderMapView.Value) == "stack";
            side = string(c.highOrderMapLayout.Value) == "side";
            c.highOrderMapValue.Enable = onOff(~side);   % 並べるときは補正前の値・補正量・残差で決まっている
            if side
                valueNames = ["value", "correction", "residual"];
            else
                valueNames = string(c.highOrderMapValue.Value);
            end
            showHighOrderMapPanels(app, numel(valueNames));
            % 残差の成分は Wafer のすべての点で分けてから、くくりの点を選ぶ
            components = [];
            if any(startsWith(valueNames, "decomp"))
                components = highOrderDecompositionOf(app, points).components;
                components = structfun(@(part) part(inGroup, :), components, 'UniformOutput', false);
            end
            points = points(inGroup, :);
            % 並べる図の矢印の倍率・色の範囲をそろえる（点の値の図だけ。グリッドは補正量の図だけで、倍率は自分で決める）
            values = cell(1, numel(valueNames));
            for k = 1:numel(valueNames)
                values{k} = highOrderMapValues(run, points, valueNames(k), string(wafer.label), components);
            end
            showRing = ~stack && (run.result.options.outerMaker ~= "none" || c.highOrderSummaryZones.Value);
            together = vertcat(values{:});
            column = 1 + (mode == "Y");
            if stack
                scale = stackArrowScale(together, wafer.unit.shotSizeMm);
            else
                scale = alignest.plot.vectorScale(together);
            end
            colorLimit = max([abs(together(isfinite(together(:, column)), column)); eps]);
            magnitudeLimit = max([hypot(together(:, 1), together(:, 2)); 0], [], 'omitnan');
            texts = strings(1, numel(valueNames));
            for k = 1:numel(valueNames)
                ax = axesList(k);
                valueLabel = highOrderValueLabel(valueNames(k));
                % 並べるときは図が狭いので、題名は値の名前だけ（Wafer の名前は図の下の説明に出す）、凡例は出さない
                panelTitle = ternary(side, valueLabel, titleText + "｜" + valueLabel);
                if mode == "grid" && any(valueNames(k) == ["correction", "highOnly"])
                    part = ternary(valueNames(k) == "highOnly", "highOrder", "all");
                    shots = highOrderShots(points);
                    gridSummary = alignest.plot.shotGridMap(ax, [shots.Xc, shots.Yc], wafer.unit.shotSizeMm, ...
                        @(local) alignest.highOrderModelAt(run.result.coefficients, run.result.options.unit, ...
                        string(wafer.label), shots, local, part), stack=stack, titleText=panelTitle + "（グリッド）", ...
                        waferRadiusMm=app.Settings.data.waferRadiusMm);
                    if side
                        legend(ax, 'off');
                    end
                    panelSummary = struct("n", gridSummary.n, "meanPlus3SigmaX", NaN, "meanPlus3SigmaY", NaN, "valueLabel", ...
                        valueLabel, "positions", NaN, "scaleMmPerNm", gridSummary.scaleMmPerNm, "maxNm", gridSummary.maxNm);
                    texts(k) = sprintf("%s（グリッド）：%d Shot、変位の最大 %.3f nm（1 nm = %.3g mm で描く）", valueLabel, ...
                        gridSummary.n, gridSummary.maxNm, gridSummary.scaleMmPerNm);
                else
                    drawMode = ternary(mode == "grid", "vector", mode);
                    panelSummary = drawHighOrderPanel(app, ax, points, wafer, values{k}, valueLabel, drawMode, stack, ...
                        panelTitle, scale, colorLimit, magnitudeLimit, run.source == "target", ~side);
                    texts(k) = sprintf("%s：%d 点、|平均|+3σ X %.3f nm・Y %.3f nm", valueLabel, panelSummary.n, ...
                        panelSummary.meanPlus3SigmaX, panelSummary.meanPlus3SigmaY);
                end
                if showRing
                    drawOuterRing(ax, run.result.options.outerRadiusMm);
                end
                styleAxes(app, ax, app.AXES_FONT_SIZE);
                if k == 1
                    summary = panelSummary;
                end
            end
            set([c.highOrderSaveFigure, c.highOrderCopyFigure], 'Enable', 'on');
            note = "";
            if mode == "grid" && ~any(valueNames == "correction" | valueNames == "highOnly")
                note = "（グリッドは補正量だけで描けます。値を「補正量」にしてください）";
            elseif run.source == "target" && ~stack
                note = "（四角は実測値の点、◇ は未知の座標の点）";
            end
            if side
                note = "（" + titleText + "）" + note;
            end
            if showRing
                note = note + sprintf("（一点鎖線の円は外周の境界：Shot 中心の半径 %g mm）", run.result.options.outerRadiusMm);
            end
            c.highOrderMapInfo.Text = char(strjoin(texts, "　") + note);
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
            comparison = [];
            pair = [];
            if ~isempty(app.HighOrderComparison) && staleComparisonText(app) == ""
                comparison = app.HighOrderComparison.table;
                pair = highOrderPairForExport(app);
                if ~isempty(pair)
                    notes(end + 1, :) = ["2つの条件の比べ方", pair.description];
                end
            end
            [decomposition, decompositionText] = highOrderDecompositionOf(app, run.result.points);
            notes(end + 1, :) = ["残差の成分分解", decompositionText];
            alignest.exportHighOrder(filePath, run.result, notes, comparison, decomposition, pair);
        end

        function data = showHighOrderSummary(app, split)
            %SHOWHIGHORDERSUMMARY 「補正の評価」の表を出す。split（省略可）：true なら Wafer ごとに、すべての Shot・内周の
            %   Shot・外周の Shot の行を出す（「内周・外周に分けて出す」。外周は Shot 中心の半径が「外周の半径」以上の Shot）。
            %   data は表に出した値。
            c = app.Controls;
            if nargin >= 2
                c.highOrderSummaryZones.Value = logical(split);
            end
            run = app.HighOrderRun;
            removeStyle(c.highOrderSummaryTable);
            if isempty(run)
                c.highOrderSummaryTable.Data = table();
                data = table();
                return
            end
            result = run.result;
            s = result.summary;
            split = c.highOrderSummaryZones.Value;
            if split
                s = [s; result.regionSummary];
                [~, waferOrder] = ismember(s.wafer, [string({run.wafers.label}), "すべての Wafer"]);
                [~, regionOrder] = ismember(s.region, ["すべて", "内周", "外周"]);
                [~, order] = sortrows([s.axis == "Y", waferOrder, regionOrder]);
                s = s(order, :);
            end
            skippedNames = struct("common", "補正しなかった Wafer", "scan", "補正しなかった組", "row", ...
                "補正しなかった組", "shot", "補正しなかった Shot");
            % 大事な数（|平均|+3σ）を左に、点の数などを右に並べる（列が多く、狭い窓では右がスクロールになるため）
            data = table(s.wafer, s.axis, round(s.before, 3), round(s.linear, 3), round(s.highOrder, 3), ...
                round(s.improvement, 3), round(s.highOrderP95, 3), round(s.highOrderMedian, 3), s.n, s.nCorrected, ...
                s.shots, s.kSets, s.skipped, s.downweighted, round(s.rmsHighOrder, 3), 'VariableNames', ...
                ["Wafer", "軸", "補正前 [nm]", "Shot ごとの1次 [nm]", "高次補正 [nm]", "改善 [nm]", ...
                "高次補正 |残差| 95% 点 [nm]", "高次補正 |残差| 中央値 [nm]", "点の数", "比べた点", "Shot の数", ...
                "k の組の数", skippedNames.(result.options.unit), "重みを下げた点", "高次補正の RMS [nm]"]);
            widths = [{170, 40}, repmat({90}, 1, 6), repmat({70}, 1, 7)];
            if split
                data = [data(:, 1:2), table(s.region, 'VariableNames', "範囲"), data(:, 3:end)];
                widths = [widths(1:2), {50}, widths(3:end)];
            end
            c.highOrderSummaryTable.Data = data;
            c.highOrderSummaryTable.ColumnWidth = widths;
            totals = find(s.wafer == "すべての Wafer");
            if ~isempty(totals)
                addStyle(c.highOrderSummaryTable, uistyle('FontWeight', 'bold'), 'row', totals);
            end
            c.highOrderSummaryZoneInfo.Text = sprintf(['外周：Shot 中心の半径 %g mm 以上の Shot（左の②の「外周の半径」。' ...
                '変えたら計算し直してください）'], result.options.outerRadiusMm);
        end
    end

    methods (Access = {?appui.Core})
        % ================= 7. Shot高次補正 =================
        function buildHighOrderTab(app)
            % 左：入力のデータ・補正の式・回帰の設定。右：メッセージと、使う項と VIF（k パラメータを選ぶ表）・補正の評価・
            % 補正値・マップ（中のタブで切り替える）
            grid = uigridlayout(app.Tabs.highOrder, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 12, 'RowSpacing', 8);
            label(grid, ['Shot 高次補正（Shot 内の座標の補正の式。ASML・Canon・Nikon・カスタム）の k パラメータを求め、' ...
                '補正の効果を評価します。左で入力のデータ・補正の式（VIF で使う項を選べます）・回帰（ロバスト回帰、高次項だけの' ...
                ' L2 正則化）を決めて「補正を計算する」を押すと、高次補正の残差を、Shot ごとの1次（k1〜k6）で補正した残差と' ...
                '比べて出します。'], 1, 1);
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
                '組み合わせごと）。Excel・CSV：右のボタンで読み込んだ表（列は読んだ後で「Excel・CSV の列」で選ぶ）。']);
            place(c.highOrderSource, 1, 2);
            c.highOrderLoad = uibutton(inputGrid, 'Text', 'Excel・CSV を読み込む…', ...
                'ButtonPushedFcn', @(~, ~) app.onLoadHighOrderFile(), 'Tooltip', ['1行目が見出しの表（列の名前は自由）。' ...
                '読んだ後で、右の「Excel・CSV の列」で Shot 中心の座標 [mm]・Shot 内の座標 [mm]・X・Y の値 [nm]（必須）と、' ...
                'Wafer・shotNo・Scan 方向など（任意）の列を選びます。このアプリが書き出した推定値の Excel も読めます。']);
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
            modelGrid = uigridlayout(left, [3, 4], 'ColumnWidth', {'fit', '1x', 'fit', '1x'}, 'RowHeight', ...
                {'fit', 'fit', 'fit'}, 'Padding', 0);
            place(modelGrid, 6, 1);
            label(modelGrid, '補正の式', 1, 1);
            c.highOrderMaker = uidropdown(modelGrid, 'Items', {'ASML', 'Canon', 'Nikon', 'カスタム（k1〜k38）'}, ...
                'ItemsData', {'asml', 'canon', 'nikon', 'custom'}, 'ValueChangedFcn', onSetting, 'Tooltip', ['Overlay 計測' ...
                'ルールの Shot 高次補正の式（Canon・Nikon はルールの式のまま、ASML は k1〜k19 のすべての項）。カスタム：' ...
                'Nikon・Canon と同じ番号の付け方の k1〜k38（4次までのすべての項と5次の項の一部。使う項は表で選び、' ...
                '組み合わせを保存できます）。' ...
                '式は「8. ヘルプ」。']);
            place(c.highOrderMaker, 1, 2);
            label(modelGrid, '補正のくくり', 1, 3);
            c.highOrderUnit = uidropdown(modelGrid, 'Items', {'Wafer 内で共通', 'Scan 方向ごと', '行の偶奇ごと', ...
                'Shot ごと'}, 'ItemsData', {'common', 'scan', 'row', 'shot'}, 'ValueChangedFcn', onSetting, 'Tooltip', ...
                ['k の組をどの Shot で共通にするか。Wafer 内で共通：Wafer ごとに1組。Scan 方向ごと：Scan 方向（Direction 1・2）' ...
                'ごとに1組ずつ。行の偶奇ごと：Shot 行（上から1行目が奇数行）の奇数行・偶数行ごとに1組ずつ。Shot ごと：Shot ' ...
                'ごとに1組（その Shot の点だけで求める。項の数より多い点があるとよい）。どれがよいかは「補正の比較」で比べられます。']);
            place(c.highOrderUnit, 1, 4);
            label(modelGrid, 'Wafer 成分', 2, 1);
            c.highOrderWaferOrder = uidropdown(modelGrid, 'Items', {'なし', '1次', '2次', '3次', '4次', '5次'}, ...
                'ItemsData', {0, 1, 2, 3, 4, 5}, 'ValueChangedFcn', onSetting, 'Tooltip', ['Shot 中心の座標（Xc・Yc）の' ...
                '多項式（定数を除く）を、Wafer で共通の1組として k と一緒に求めます（Wafer の倍率・回転などが Shot の k に' ...
                '混ざらないように）。Shot ごとのときは、先に（Wafer 内で共通の k と一緒に）求めて引き、残りを Shot ごとに' ...
                '求めます（補正量・残差は Wafer 成分なしと同じで、Shot ごとの k1・k2 が Wafer 成分を除いた値になります）。']);
            place(c.highOrderWaferOrder, 2, 2);
            label(modelGrid, 'VIF のしきい値', 2, 3);
            c.highOrderVifThreshold = uieditfield(modelGrid, 'numeric', 'Limits', [1, Inf], 'LowerLimitInclusive', 'off', ...
                'ValueChangedFcn', onSetting, 'Tooltip', ['「VIF で選ぶ」で、VIF がこの値以上の高次項を外します' ...
                '（よく使う値は 5〜10）。表では、使う項のうち VIF がこの値以上の行に色を付けます。']);
            place(c.highOrderVifThreshold, 2, 4);
            label(modelGrid, '外周の半径 [mm]', 3, 1);
            c.highOrderOuterRadius = uieditfield(modelGrid, 'numeric', 'Limits', [0, Inf], 'LowerLimitInclusive', 'off', ...
                'ValueChangedFcn', onSetting, 'Tooltip', ['Shot 中心の半径（Wafer 中心からの距離）がこの値以上の Shot を' ...
                '外周にします。「補正の評価」で内周・外周に分けて出すときと、外周の式を分けるときに使います。']);
            place(c.highOrderOuterRadius, 3, 2);
            label(modelGrid, '外周の式', 3, 3);
            c.highOrderOuterFormula = uidropdown(modelGrid, 'Items', {'分けない'}, 'ItemsData', {'none'}, ...
                'ValueChangedFcn', onSetting, 'Tooltip', ['外周の Shot だけ別の補正の式にします（例：外周は ASML、内周は' ...
                'Nikon やカスタム）。k の組は内周と外周で別に求めます（くくりの組ごと。Wafer 成分は共通）。式の全項か、' ...
                '「使う項と VIF」で保存した項の組み合わせを選べます。']);
            place(c.highOrderOuterFormula, 3, 4);
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
            columnTab = uitab(outputs, 'Title', 'Excel・CSV の列');
            c.highOrderColumnTab = columnTab;
            columnGrid = uigridlayout(columnTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            columnControls = uigridlayout(columnGrid, [2, 3], 'ColumnWidth', {'fit', '1x', 'fit'}, ...
                'RowHeight', {'fit', 'fit'}, 'Padding', 0);
            label(columnControls, 'シート', 1, 1);
            c.highOrderSheet = uidropdown(columnControls, 'Items', {'—'}, 'Enable', 'off', ...
                'ValueChangedFcn', @(~, ~) app.onHighOrderSheetChanged());
            place(c.highOrderSheet, 1, 2);
            c.highOrderApplyMapping = primaryButton(app, columnControls, 'この列で使う', ...
                @(~, ~) app.onApplyHighOrderMapping());
            place(c.highOrderApplyMapping, 1, 3);
            c.highOrderApplyMapping.Enable = 'off';
            label(columnControls, 'Scan 方向が無いとき', 2, 1);
            [ruleNames, ruleLabels] = alignest.directionRules();
            c.highOrderDirectionRule = uidropdown(columnControls, 'Items', cellstr(ruleLabels), 'ItemsData', ...
                cellstr(ruleNames), 'Value', 'none', 'ValueChangedFcn', @(~, ~) app.onHighOrderMappingEdited(), ...
                'Tooltip', ['Direction（Scan 方向）の列を選ばないとき、または空の行に、この規則で 1・2 を付けます' ...
                '（「1. データの読み込み」の「Scan 方向の付与」と同じ）。「付けない」なら Scan 方向ごとには求められません。']);
            place(c.highOrderDirectionRule, 2, [2, 3]);
            c.highOrderMappingTable = uitable(columnGrid, 'ColumnName', {'項目', '意味', '必須', 'ファイルの列'}, ...
                'RowName', {}, 'ColumnEditable', [false, false, false, true], 'ColumnWidth', {90, 'auto', 50, 180}, ...
                'Data', cell(0, 4), 'CellEditCallback', @(~, ~) app.onHighOrderMappingEdited(), 'Tooltip', ...
                '「ファイルの列」をクリックして、項目に使う列を選びます（使わない任意の項目は「（なし）」）。');
            place(c.highOrderMappingTable, 2, 1);
            c.highOrderMappingStatus = uilabel(columnGrid, 'WordWrap', 'on', 'Text', ['入力を Excel・CSV にするときは、' ...
                '左の「Excel・CSV を読み込む…」で表を選んでください（列の名前は自由。読んだ後でここで列を選びます）。']);
            place(c.highOrderMappingStatus, 3, 1);
            termTab = uitab(outputs, 'Title', '使う項と VIF');
            termGrid = uigridlayout(termTab, [3, 1], 'RowHeight', {'1x', 'fit', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
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
            buildHighOrderTermSetControls(app, termGrid, 3);
            summaryTab = uitab(outputs, 'Title', '補正の評価');
            c.highOrderSummaryTab = summaryTab;
            summaryGrid = uigridlayout(summaryTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            zoneGrid = uigridlayout(summaryGrid, [1, 2], 'ColumnWidth', {'fit', '1x'}, 'Padding', 0);
            c.highOrderSummaryZones = uicheckbox(zoneGrid, 'Text', '内周・外周に分けて出す', 'Value', false, ...
                'ValueChangedFcn', @(~, ~) app.showHighOrderSummary(), 'Tooltip', ['Wafer ごとに、すべての Shot・内周の Shot・' ...
                '外周の Shot の行を出します（外周は左の②の「外周の半径」以上の Shot）。']);
            c.highOrderSummaryZoneInfo = label(zoneGrid, '', 1, 2);
            c.highOrderSummaryZoneInfo.FontColor = app.Palette.muted;
            c.highOrderSummaryZoneInfo.UserData = "muted";
            c.highOrderSummaryTable = uitable(summaryGrid, 'RowName', {}, 'Data', table(), 'ColumnWidth', ...
                [{170, 40}, repmat({90}, 1, 6), repmat({70}, 1, 7)]);
            place(c.highOrderSummaryTable, 2, 1);
            note = label(summaryGrid, ['補正前・Shot ごとの1次・高次補正・改善の列は |平均|+3σ [nm]。|残差| 95% 点・中央値は' ...
                '、高次補正の残差の大きさ（絶対値）の 95% 点と中央値 [nm]。高次補正と Shot ごとの1次（k1〜k6 を Shot ごとに' ...
                '求めた補正。同じ損失関数）の両方ができた点で比べます。改善 = Shot ごとの1次 − 高次補正。重みを下げた点：' ...
                'ロバスト回帰で外れ値とみなして重みを下げた点の数。'], 3, 1);
            note.FontColor = app.Palette.muted;
            note.UserData = "muted";
            buildHighOrderCompareTab(app, outputs);
            buildHighOrderPairTab(app, outputs);
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
                'Shot ごとの補正のとき、どの Wafer の Shot ごとの k を出すか（ほかのくくりのときは、すべての Wafer を並べます）。');
            place(c.highOrderCoefficientWafer, 1, 4);
            c.highOrderCoefficientTable = uitable(coefficientGrid, 'RowName', {}, 'Data', table());
            place(c.highOrderCoefficientTable, 2, 1);
            c.highOrderCoefficientInfo = label(coefficientGrid, ['回帰の残差は、その行の k の組で補正した後の残差' ...
                '（選んだ式の軸。点の数・|平均|+3σ・大きさの 95% 点と中央値 [nm]）。係数は mm の座標での値（定数 nm、1次 ' ...
                'nm/mm = ppm、n 次 nm/mm^n）、x・y は Shot 内の座標。空欄は決まらない・補正しなかった組。Wafer 成分' ...
                '（Shot 中心の座標の項）の係数は Excel の書き出しにあります。'], 3, 1);
            c.highOrderCoefficientInfo.FontColor = app.Palette.muted;
            c.highOrderCoefficientInfo.UserData = "muted";
            buildHighOrderWaferTab(app, outputs);
            mapTab = uitab(outputs, 'Title', 'マップ');
            c.highOrderMapTab = mapTab;
            mapGrid = uigridlayout(mapTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            mapControls = uigridlayout(mapGrid, [2, 7], 'ColumnWidth', {'fit', '1x', 'fit', '1.2x', 'fit', '1.1x', 'fit'}, ...
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
            label(mapControls, 'くくり', 1, 5);
            c.highOrderMapGroup = uidropdown(mapControls, 'Items', {'すべての点'}, 'ItemsData', {''}, 'Enable', 'off', ...
                'ValueChangedFcn', onMap, 'Tooltip', ['Scan 方向ごと・行の偶奇ごとのとき、1つの k の組の点だけを描きます' ...
                '（「Shot を重ねる」で組ごとの Shot 内の形を見るとき）。']);
            place(c.highOrderMapGroup, 1, 6);
            c.highOrderSaveFigure = uibutton(mapControls, 'Text', '図を画像で保存…', ...
                'ButtonPushedFcn', @(~, ~) app.saveFigureWithDialog("highOrder", 'shot_high_order_map.png'));
            place(c.highOrderSaveFigure, 1, 7);
            label(mapControls, '値', 2, 1);
            c.highOrderMapValue = uidropdown(mapControls, 'Items', {'高次補正の残差', ...
                'Shot ごとの1次（k1〜k6）で補正した残差', '補正量', '補正量（2次以上の項だけ）', '補正前の値', ...
                '残差の成分：Wafer 線形', '残差の成分：Shot 共通', '残差の成分：Shot', '残差の成分：残り'}, ...
                'ItemsData', {'residual', 'linear', 'correction', 'highOnly', 'value', 'decompWafer', 'decompCommon', ...
                'decompShot', 'decompRest'}, 'ValueChangedFcn', onMap, ...
                'Tooltip', ['残差 = 値 − 補正量。補正量は高次補正（使う項と Wafer 成分）を当てはめた値。2次以上の項だけ：' ...
                '補正量のうち2次以上の項の分（Shot の形の高次の歪み）。残差の成分：高次補正の残差を「残差の成分分解」の' ...
                'タブの項で分けた成分。']);
            place(c.highOrderMapValue, 2, 2);
            label(mapControls, '表示', 2, 3);
            c.highOrderMapMode = uidropdown(mapControls, 'Items', {'ベクトル（矢印）', 'X（色）', 'Y（色）', ...
                'グリッド（Shot の形）'}, 'ItemsData', {'vector', 'X', 'Y', 'grid'}, 'ValueChangedFcn', onMap, 'Tooltip', ...
                ['グリッド：求めた補正の式で、Shot の枠のグリッドを変形させて描きます（値が補正量のとき。変位は拡大して' ...
                '描きます）。']);
            place(c.highOrderMapMode, 2, 4);
            label(mapControls, '並べ方', 2, 5);
            c.highOrderMapLayout = uidropdown(mapControls, 'Items', {'1つの図', '補正前・補正量・残差を並べる'}, ...
                'ItemsData', {'single', 'side'}, 'ValueChangedFcn', onMap, 'Tooltip', ['補正前の値・補正量・高次補正の' ...
                '残差を横に並べます（矢印の倍率と色の範囲をそろえます）。']);
            place(c.highOrderMapLayout, 2, 6);
            c.highOrderCopyFigure = uibutton(mapControls, 'Text', '図をコピー', 'Tooltip', app.COPY_TOOLTIP, ...
                'ButtonPushedFcn', @(source, ~) app.onCopyFigure("highOrder", source));
            place(c.highOrderCopyFigure, 2, 7);
            c.highOrderPanel = uipanel(mapGrid, 'BorderType', 'none');
            place(c.highOrderPanel, 2, 1);
            c.highOrderAxesGrid = uigridlayout(c.highOrderPanel, [1, 3], 'ColumnWidth', {'1x', 0, 0}, 'Padding', 0, ...
                'ColumnSpacing', 6);
            c.highOrderAxes = uiaxes(c.highOrderAxesGrid);
            c.highOrderAxes2 = uiaxes(c.highOrderAxesGrid, 'Visible', 'off');
            c.highOrderAxes3 = uiaxes(c.highOrderAxesGrid, 'Visible', 'off');
            c.highOrderMapInfo = uilabel(mapGrid, 'WordWrap', 'on', 'Text', ...
                '「補正を計算する」を押すと、補正後の残差を描きます。', 'UserData', '「補正を計算する」を押すと、補正後の残差を描きます。');
            place(c.highOrderMapInfo, 3, 1);
            set([c.highOrderExport, c.highOrderSaveFigure, c.highOrderCopyFigure], 'Enable', 'off');
            outputs.SelectedTab = termTab;   % 「Excel・CSV の列」は表を読み込んだときに開く
            app.Controls = mergeStruct(app.Controls, c);
            buildHighOrderHistogramTab(app, outputs);
            buildHighOrderDecompositionTab(app, outputs);
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
            c.highOrderOuterRadius.Value = options.outerRadiusMm;
            refreshHighOrderOuterChoices(app);
            c.highOrderVifThreshold.Value = options.vifThreshold;
            c.highOrderLoss.Value = char(options.loss);
            c.highOrderHuber.Value = options.huberTuning;
            c.highOrderL2.Value = options.l2;
            c.highOrderLambda.Value = options.lambda;
            updateHighOrderEnabled(app);
            refreshHighOrderTerms(app);
            refreshHighOrderTermSets(app);
        end

        function refreshHighOrderOuterChoices(app)
            % 「外周の式」の選択肢（分けない・式の全項・保存した項の組み合わせ）を作り、設定（settings.highOrder の
            % outerMaker・outerName）の外周の式を選ぶ。保存から消した組み合わせを選んでいたら、設定の項のまま残す
            c = app.Controls;
            if ~isfield(c, 'highOrderOuterFormula')
                return
            end
            source = app.Settings.highOrder;
            sets = termSetTable(fieldOr(source, "termSets", strings(0, 1)));
            items = ["分けない", "ASML（全項）", "Canon（全項）", "Nikon（全項）", "カスタム（k1〜k38 の全項）", ...
                reshape("組み合わせ：" + sets.name + "（" + sets.makerLabel + "・" + sets.count + " 項）", 1, [])];
            values = ["none", "asml", "canon", "nikon", "custom", reshape(outerSetPrefix() + sets.name, 1, [])];
            maker = lower(string(fieldOr(source, "outerMaker", "none")));
            name = string(fieldOr(source, "outerName", ""));
            value = maker;
            if maker ~= "none" && name ~= ""
                value = outerSetPrefix() + name;
                if ~any(values == value)
                    items(end + 1) = "組み合わせ：" + name + "（保存から消した）";
                    values(end + 1) = value;
                end
            end
            if ~any(values == value)
                value = "none";
            end
            c.highOrderOuterFormula.Items = cellstr(items);
            c.highOrderOuterFormula.ItemsData = cellstr(values);
            c.highOrderOuterFormula.Value = char(value);
        end

        function readHighOrderOuterFormula(app)
            % 「外周の式」の選択を設定に移す（選び直したときだけ。計算で絞った外周の項 outerExcludedTerms は残す）
            value = string(app.Controls.highOrderOuterFormula.Value);
            source = app.Settings.highOrder;
            currentMaker = lower(string(fieldOr(source, "outerMaker", "none")));
            currentName = string(fieldOr(source, "outerName", ""));
            if startsWith(value, outerSetPrefix())
                name = extractAfter(value, strlength(outerSetPrefix()));
                sets = termSetTable(fieldOr(source, "termSets", strings(0, 1)));
                row = find(sets.name == name, 1);
                if isempty(row) || (currentName == name && currentMaker == sets.maker(row))
                    return   % 同じ組み合わせ（または保存から消した組み合わせ）：設定のまま
                end
                app.Settings.highOrder.outerMaker = sets.maker(row);
                app.Settings.highOrder.outerExcludedTerms = excludedFor(sets.maker(row), sets.terms{row});
                app.Settings.highOrder.outerName = name;
            elseif currentMaker ~= value || currentName ~= ""
                app.Settings.highOrder.outerMaker = value;
                app.Settings.highOrder.outerExcludedTerms = zeros(1, 0);
                app.Settings.highOrder.outerName = "";
            end
        end

        function readHighOrderControls(app)
            % 画面の欄を設定（settings.highOrder）に移す（使う項 excludedTerms は表の操作で変える）
            c = app.Controls;
            app.Settings.highOrder.maker = string(c.highOrderMaker.Value);
            app.Settings.highOrder.unit = string(c.highOrderUnit.Value);
            app.Settings.highOrder.waferOrder = c.highOrderWaferOrder.Value;
            app.Settings.highOrder.outerRadiusMm = c.highOrderOuterRadius.Value;
            readHighOrderOuterFormula(app);
            app.Settings.highOrder.vifThreshold = c.highOrderVifThreshold.Value;
            app.Settings.highOrder.loss = string(c.highOrderLoss.Value);
            app.Settings.highOrder.huberTuning = c.highOrderHuber.Value;
            app.Settings.highOrder.l2 = c.highOrderL2.Value;
            app.Settings.highOrder.lambda = c.highOrderLambda.Value;
        end

        function updateHighOrderEnabled(app)
            c = app.Controls;
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
                    if isempty(app.HighOrderFile)
                        info = "「Excel・CSV を読み込む…」で、Wafer ごとの dx・dy の値の表を読み込んでください。";
                    elseif isempty(app.HighOrderFile.data)
                        info = app.HighOrderFile.info.file + "：右の「Excel・CSV の列」で列を選び、「この列で使う」を" + ...
                            "押してください。";
                    else
                        labels = string({app.HighOrderFile.data.units.label});
                        info = highOrderFileSummary(app) + "。";
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
            source = app.Settings.highOrder;
            if string(fieldOr(source, "outerMaker", "none")) ~= "none"
                % 外周の式を分けるときは、表の式（内周の式）を内周の Shot の点で（alignest.shotHighOrder と同じ）
                points = points(hypot(points.Xc, points.Yc) < fieldOr(source, "outerRadiusMm", Inf) - 1e-9, :);
            end
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
                    if isempty(app.HighOrderFile.data)
                        error('alignest:noHighOrderFile', ['「Excel・CSV の列」で列を選び、「この列で使う」を押して' ...
                            'ください。']);
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
            unit = result.options.unit;
            showHighOrderSummary(app);
            labels = string({run.wafers.label});
            setChoices(c.highOrderCoefficientWafer, labels, num2cell(1:numel(labels)));
            c.highOrderCoefficientWafer.Enable = onOff(unit == "shot");
            setChoices(c.highOrderMapWafer, labels, num2cell(1:numel(labels)));
            c.highOrderMapWafer.Enable = 'on';
            groups = strings(0, 1);
            if any(unit == ["scan", "row"]) || (unit == "common" && result.options.outerMaker ~= "none")
                groups = orderedGroups(result.points, unit);
            end
            setChoices(c.highOrderMapGroup, ["すべての点", reshape(groups, 1, [])], [{''}, reshape(cellstr(groups), 1, [])]);
            c.highOrderMapGroup.Enable = onOff(~isempty(groups));
            c.highOrderExport.Enable = 'on';
            showHighOrderCoefficients(app);
            drawHighOrderWaferComparison(app);
            drawHighOrderMap(app);
            refreshHighOrderHistogramChoices(app);
            refreshHighOrderDecompositionChoices(app);
            drawShownHighOrderAnalysis(app);
            showHighOrderMessages(app);
        end

        function showHighOrderCoefficients(app)
            % 補正値の表：行は Wafer（Wafer 内で共通）、Wafer × k の組（Scan 方向ごと・行の偶奇ごと）、Shot（Shot ごと。選んだ
            % Wafer）、列はその行の点の回帰の残差（点の数・|平均|+3σ・|残差| の 95% 点と中央値）と、使う項の k。
            % Wafer 成分（Shot 中心の座標 Xc・Yc の項）は行ごとの値ではないので出さない（Excel の書き出しにある）
            run = app.HighOrderRun;
            c = app.Controls;
            if isempty(run)
                c.highOrderCoefficientTable.Data = table();
                return
            end
            axisName = string(c.highOrderCoefficientAxis.Value);
            coefficients = run.result.coefficients;
            coefficients = coefficients(coefficients.axis == axisName & coefficients.component == "Shot 高次補正", :);
            points = run.result.points;
            waferLabels = reshape(string({run.wafers.label}), [], 1);
            unit = run.result.options.unit;
            if unit == "common" && run.result.options.outerMaker ~= "none"
                unit = "zone";   % 外周の式を分けた Wafer 内で共通：Wafer × 内周・外周の行
            end
            switch unit
                case "shot"
                    position = min(max(c.highOrderCoefficientWafer.Value, 1), numel(run.wafers));
                    coefficients = coefficients(coefficients.wafer == waferLabels(position), :);
                    points = points(points.wafer == waferLabels(position) & isfinite(points.shotNo), :);
                    [shots, first] = unique(points.shotNo);
                    allKeys = string(shots);
                    keys = string(coefficients.shotNo);
                    pointKeys = string(points.shotNo);
                    keyColumns = table(allKeys, points.zone(first), 'VariableNames', ["shotNo", "範囲"]);
                case "common"
                    allKeys = waferLabels;
                    keys = coefficients.wafer;
                    pointKeys = points.wafer;
                    keyColumns = table(allKeys, 'VariableNames', "Wafer");
                otherwise
                    pairs = unique(points(points.group ~= "", ["wafer", "group"]));
                    [~, waferOrder] = ismember(pairs.wafer, waferLabels);
                    [~, groupOrder] = ismember(pairs.group, orderedGroups(points, run.result.options.unit));
                    [~, order] = sortrows([waferOrder, groupOrder]);
                    pairs = pairs(order, :);
                    allKeys = pairs.wafer + "｜" + pairs.group;
                    keys = coefficients.wafer + "｜" + coefficients.group;
                    pointKeys = points.wafer + "｜" + points.group;
                    keyColumns = table(pairs.wafer, pairs.group, 'VariableNames', ["Wafer", "くくり"]);
            end
            terms = run.result.terms;   % 点の数で絞った後の使う項（外周の式を分けたときは内周・外周の項をまとめる）
            terms = terms(terms.axis == axisName & terms.used, :);
            [~, first] = unique(terms.k);
            terms = terms(first, :);
            names = "k" + string(terms.k) + "（" + terms.term + "）";
            values = strings(numel(allKeys), numel(names));
            [~, row] = ismember(keys, allKeys);
            [~, column] = ismember(coefficients.k, terms.k);
            text = compose("%.4g", coefficients.value);
            text(contains(coefficients.note, "決まらない")) = "（決まらない）";
            text(contains(coefficients.note, "値が変わらない")) = "0（定数と同じ）";
            use = find(row > 0 & column > 0);
            values(sub2ind(size(values), row(use), column(use))) = text(use);
            residuals = residualColumns(points.("residual" + ternary(axisName == "dx", "X", "Y")), pointKeys, allKeys);
            c.highOrderCoefficientTable.Data = [keyColumns, residuals, array2table(values, 'VariableNames', cellstr(names))];
        end

        function showHighOrderMapPanels(app, n)
            % マップの図を n 個（1 または 3）にする。使わない図は中身を消して隠す（保存・コピーは中身のある図だけ）
            c = app.Controls;
            axesList = [c.highOrderAxes, c.highOrderAxes2, c.highOrderAxes3];
            c.highOrderAxesGrid.ColumnWidth = [repmat({'1x'}, 1, n), repmat({0}, 1, numel(axesList) - n)];
            for k = n + 1:numel(axesList)
                cla(axesList(k), 'reset');
                legend(axesList(k), 'off');
                colorbar(axesList(k), 'off');
                axesList(k).Visible = 'off';
            end
            set(axesList(1:n), 'Visible', 'on');
        end

        function summary = drawHighOrderPanel(app, ax, points, wafer, values, valueLabel, mode, stack, titleText, ...
                scale, colorLimit, magnitudeLimit, markMeasured, showLegend)
            % マップの1つの図：点の値 values（点の数 × 2：X・Y [nm]）を Wafer 上か、Shot を重ねて描く。矢印の倍率・色の範囲は
            % 並べた図でそろえた値。summary は描いた点の数と X・Y の |平均|+3σ、Shot を重ねるときは Mark の位置の数
            summary = struct("n", nnz(any(isfinite(values), 2)), "meanPlus3SigmaX", meanPlus3Sigma(values(:, 1)), ...
                "meanPlus3SigmaY", meanPlus3Sigma(values(:, 2)), "valueLabel", valueLabel, "positions", NaN);
            if stack
                positions = alignest.plot.shotStackMap(ax, [points.localX, points.localY], values, mode=mode, ...
                    shotSizeMm=wafer.unit.shotSizeMm, scaleMmPerNm=scale, colorLimit=colorLimit, titleText=titleText, ...
                    showLegend=showLegend);
                summary.positions = height(positions);
                return
            end
            drawn = points;
            drawn.valueX = values(:, 1);
            drawn.valueY = values(:, 2);
            alignest.plot.correctionMap(ax, struct("points", drawn), wafer.unit, value="value", mode=mode, ...
                titleText=titleText, showStatistics=false, valueLabel=valueLabel, markMeasured=markMeasured, ...
                scaleMmPerNm=scale, colorLimit=colorLimit, magnitudeLimit=magnitudeLimit, ...
                waferRadiusMm=app.Settings.data.waferRadiusMm);
            if ~showLegend
                legend(ax, 'off');
            end
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
            % 保存した項の組み合わせ（termSets）は計算に使わないので比べない
            if ~isequaln(withoutTermSets(run.settings), withoutTermSets(app.Settings.highOrder)) || ...
                    run.source ~= string(c.highOrderSource.Value) || ...
                    ~isequal(run.selection, c.highOrderWafer.Value) || run.measured ~= c.highOrderMeasured.Value
                text = "⚠ 設定・入力を変えました。「補正を計算する」で計算し直してください（下は前の計算の結果）。";
            end
        end

        function markHighOrderStale(app)
            % 設定・入力を変えたら、前の結果が古いことをメッセージに出す（結果は残す）
            if ~isempty(app.HighOrderRun)
                showHighOrderMessages(app);
            end
            if ~isempty(app.HighOrderComparison)
                showHighOrderComparison(app);
            end
        end

        function showHighOrderMapping(app, mapping)
            % 「Excel・CSV の列」の表とシートの一覧を、読み込んだ表と対応（項目 → ファイルの列）に合わせて作る
            c = app.Controls;
            file = app.HighOrderFile;
            columns = alignest.highOrderColumns();
            data = cell(numel(columns), 4);
            for k = 1:numel(columns)
                value = string(mapping.(columns(k).name));
                if value == ""
                    value = app.NONE_LABEL;
                end
                data(k, :) = {columns(k).name, columns(k).meaning, char(ternary(columns(k).required, "必須", "任意")), ...
                    char(value)};
            end
            c.highOrderMappingTable.Data = data;
            c.highOrderMappingTable.ColumnFormat = {'char', 'char', 'char', cellstr([app.NONE_LABEL, file.info.columns])};
            removeStyle(c.highOrderMappingTable);
            missing = find([columns.required].' & string(data(:, 4)) == app.NONE_LABEL);
            if ~isempty(missing)
                addStyle(c.highOrderMappingTable, uistyle('BackgroundColor', app.Palette.warning), 'row', missing);
            end
            if all(file.info.sheets == "")
                setChoices(c.highOrderSheet, "（CSV にはシートがありません）", {''});
                c.highOrderSheet.Enable = 'off';
            else
                setChoices(c.highOrderSheet, file.info.sheets, cellstr(file.info.sheets));
                c.highOrderSheet.Value = char(file.info.sheet);
                c.highOrderSheet.Enable = 'on';
            end
            c.highOrderApplyMapping.Enable = 'on';
        end

        function mapping = currentHighOrderMapping(app)
            % 「Excel・CSV の列」の表で選んでいる対応（項目 → ファイルの列。「（なし）」は ""）
            data = app.Controls.highOrderMappingTable.Data;
            mapping = struct();
            for k = 1:size(data, 1)
                value = string(data{k, 4});
                if value == app.NONE_LABEL
                    value = "";
                end
                mapping.(data{k, 1}) = value;
            end
        end

        function text = highOrderFileSummary(app)
            % 読み込んだ表の説明（ファイル・シート・Wafer と点の数・Scan 方向）
            file = app.HighOrderFile;
            text = file.info.file;
            if file.info.sheet ~= ""
                text = text + "（シート「" + file.info.sheet + "」）";
            end
            if isempty(file.data)
                return
            end
            units = file.data.units;
            marks = arrayfun(@(unit) numel(unit.marks.x), units);
            directions = arrayfun(@(unit) nnz(ismember(unit.marks.direction, [1, 2])), units);
            scanText = "Scan 方向なし（Scan 方向ごとには求められません）";
            if sum(directions) == sum(marks)
                scanText = "Scan 方向あり";
            elseif sum(directions) > 0
                scanText = sprintf("Scan 方向は %d / %d 点", sum(directions), sum(marks));
            end
            text = text + sprintf("：%d 行・%d Wafer・%d 点、", file.info.rows, numel(units), sum(marks)) + scanText;
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
            comparison = app.HighOrderComparison;
            if ~isempty(comparison) && (comparison.source == kind || (kind == "data" && comparison.source == "target"))
                app.HighOrderComparison = [];
                showHighOrderComparison(app);
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
            setChoices(c.highOrderMapGroup, "すべての点", {''});
            set([c.highOrderCoefficientWafer, c.highOrderMapWafer, c.highOrderMapGroup, c.highOrderExport], 'Enable', 'off');
            c.highOrderSummaryZoneInfo.Text = '';
            drawHighOrderWaferComparison(app);
            drawHighOrderMap(app);
            refreshHighOrderHistogramChoices(app);
            refreshHighOrderDecompositionChoices(app);
            drawShownHighOrderAnalysis(app);
            c.highOrderMessage.Value = {'入力のデータと Wafer を選び、補正の式・回帰を決めてから「補正を計算する」を押してください。'};
            c.highOrderMessage.FontColor = app.Palette.text;
        end

        function onHighOrderOutputChanged(app, event)
            % 図のあるタブを開いたら描き直す（見えていないタブに描いた図は、開いたときに一部しか描かれないことがあるため）
            c = app.Controls;
            try
                if event.NewValue == c.highOrderMapTab && ~isempty(app.HighOrderRun)
                    drawHighOrderMap(app);
                elseif event.NewValue == c.highOrderWaferTab
                    drawHighOrderWaferComparison(app);
                elseif event.NewValue == c.highOrderCompareTab
                    drawHighOrderComparisonChart(app);
                elseif event.NewValue == c.highOrderPairTab
                    drawHighOrderPair(app);
                elseif event.NewValue == c.highOrderHistogramTab
                    drawHighOrderHistogram(app);
                elseif event.NewValue == c.highOrderDecompositionTab
                    showHighOrderDecomposition(app);
                end
            catch
                % 描き直せなくても前の図のままにする（表示を変えるだけなので止めない）
            end
        end

        function onComputeHighOrder(app)
            app.Controls.highOrderError.Text = '';
            runWithAlert(app, @() app.computeHighOrder(), "Shot 高次補正を計算できませんでした", ...
                ['入力のデータと Wafer、補正の式の設定を確かめてください。Shot ごとのときは、1つの Shot に点が足りているか' ...
                '（「VIF で選ぶ」で項を減らす・L2 正則化をかける）を確かめてください。']);
        end

        function onHighOrderSheetChanged(app)
            file = app.HighOrderFile;
            if isempty(file)
                return
            end
            runWithAlert(app, @() app.loadHighOrderFile(file.info.path, string(app.Controls.highOrderSheet.Value)), ...
                "シートを読み込めませんでした", "別のシートを選ぶか、ファイルの中身を確かめてください。");
        end

        function onHighOrderMappingEdited(app)
            % 列・規則を選び直したら、まだ反映していないことを知らせる（「この列で使う」で反映する）
            c = app.Controls;
            if isempty(app.HighOrderFile)
                return
            end
            showHighOrderMapping(app, currentHighOrderMapping(app));
            c.highOrderMappingStatus.Text = '列（または Scan 方向の規則）を選び直しました。「この列で使う」を押すと反映します。';
            c.highOrderMappingStatus.FontColor = app.Palette.error;
        end

        function onApplyHighOrderMapping(app)
            c = app.Controls;
            ok = runWithAlert(app, @() app.applyHighOrderMapping(), "この列では読み込めませんでした", ...
                "「必須」の項目の列と、数の列に文字が入っていないかを確かめてください。");
            if ~ok
                c.highOrderMappingStatus.Text = '⚠ 読み込めませんでした。列の選び方を確かめてください。';
                c.highOrderMappingStatus.FontColor = app.Palette.error;
            end
        end

        function onLoadHighOrderFile(app)
            [fileName, folder] = uigetfile({'*.xlsx;*.xlsm;*.xls;*.csv', 'Excel・CSV (*.xlsx, *.xlsm, *.xls, *.csv)'}, ...
                'Shot 高次補正の入力にする表を選ぶ');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.loadHighOrderFile(fullfile(folder, fileName)), "表を読み込めませんでした", ...
                '1行目が見出しの表か（Excel は1つ目のシート、または「推定値」のシート）を確かめてください。');
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

function settings = withoutTermSets(settings)
% 計算に使う設定だけにする（保存した項の組み合わせ termSets を除く）
if isfield(settings, "termSets")
    settings = rmfield(settings, "termSets");
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

function groups = orderedGroups(points, unit)
% 点の k の組の名前を、範囲（内周・外周）と組の番号の順（Scan 方向 1・2、奇数行・偶数行）に並べる
keys = zeros(height(points), 1);
if unit == "scan"
    keys = points.direction;
elseif unit == "row"
    keys = points.rowParity;
end
zones = double(points.zone == "外周");
named = find(points.group ~= "");
[groups, first] = unique(points.group(named));
[~, order] = sortrows([zones(named(first)), keys(named(first))]);
groups = groups(order);
end

function values = highOrderMapValues(run, points, valueName, waferLabel, components)
% マップに描く点の値（点の数 × 2：X・Y [nm]）。"highOnly" は補正量のうち2次以上の項の分（Shot ごとに式で求める）。
% "decomp…" は残差の成分（components：alignest.decomposeHighOrderResidual の components を points の行に合わせたもの）
COMPONENT_NAMES = struct("decompWafer", "waferLinear", "decompCommon", "common", "decompShot", "shot", ...
    "decompRest", "rest");
if isfield(COMPONENT_NAMES, valueName)
    values = components.(COMPONENT_NAMES.(valueName));
    return
end
switch valueName
    case "residual"
        values = [points.residualX, points.residualY];
    case "linear"
        values = [points.linearResidualX, points.linearResidualY];
    case "correction"
        values = [points.correctionX, points.correctionY];
    case "value"
        values = [points.valueX, points.valueY];
    otherwise
        values = nan(height(points), 2);
        shots = highOrderShots(points);
        for s = 1:height(shots)
            rows = find(points.shotNo == shots.shotNo(s));
            [dx, dy] = alignest.highOrderModelAt(run.result.coefficients, run.result.options.unit, waferLabel, ...
                shots(s, :), [points.localX(rows), points.localY(rows)], "highOrder");
            values(rows, :) = [dx(:), dy(:)];
        end
        values(~isfinite(points.correctionX), 1) = NaN;   % 補正しなかった点は描かない
        values(~isfinite(points.correctionY), 2) = NaN;
end
end

function text = highOrderValueLabel(valueName)
% マップの値の名前
names = struct("residual", "高次補正の残差", "linear", "Shot ごとの1次で補正した残差", "correction", "補正量", ...
    "highOnly", "補正量（2次以上の項）", "value", "補正前の値", "decompWafer", "残差の Wafer 線形成分", ...
    "decompCommon", "残差の Shot 共通成分", "decompShot", "残差の Shot 成分", "decompRest", "残差の残り");
text = string(names.(valueName));
end

function shots = highOrderShots(points)
% 点の Shot ごとの表（shotNo・Shot 中心 Xc・Yc [mm]・k の組の名前 group。alignest.highOrderModelAt の入力）
points = points(isfinite(points.shotNo), :);
[~, first] = unique(points.shotNo);
shots = table(points.shotNo(first), points.x(first) - points.localX(first), points.y(first) - points.localY(first), ...
    points.group(first), 'VariableNames', ["shotNo", "Xc", "Yc", "group"]);
end

function scale = stackArrowScale(values, sizeMm)
% Shot を重ねる図の矢印の倍率 [mm/nm]：大きさの95%点の矢印が Shot の短い辺の ARROW_RATIO 倍
% （alignest.plot.shotStackMap の自動の倍率と同じ。図を並べるとき、3つの図の値をまとめて決める）
ARROW_RATIO = 0.18;
magnitude = sort(hypot(values(:, 1), values(:, 2)));
magnitude = magnitude(isfinite(magnitude));
scale = 0;   % 0 なら shotStackMap が決める（値が無い・Shot の大きさが分からない）
if isempty(magnitude) || magnitude(end) <= 0 || any(~isfinite(sizeMm))
    return
end
reference = magnitude(max(1, ceil(0.95 * numel(magnitude))));
scale = min(sizeMm) * ARROW_RATIO / max(reference, eps);
end

function residuals = residualColumns(residual, pointKeys, allKeys)
% 補正値の表の残差の列：行（allKeys）ごとの点の数・|平均|+3σ・|残差| の 95% 点と中央値（補正しなかった行は空欄）
n = numel(allKeys);
[count, spread, p95, middle] = deal(zeros(n, 1), strings(n, 1), strings(n, 1), strings(n, 1));
for k = 1:n
    values = residual(pointKeys == allKeys(k));
    values = values(isfinite(values));
    count(k) = numel(values);
    if count(k) >= 2
        spread(k) = sprintf("%.3f", abs(mean(values)) + 3 * std(values));
    end
    if count(k) >= 1
        p95(k) = sprintf("%.3f", alignest.stats.percentile(abs(values), 95));
        middle(k) = sprintf("%.3f", median(abs(values)));
    end
end
residuals = table(count, spread, p95, middle, 'VariableNames', ["残差の点の数", "残差 |平均|+3σ [nm]", ...
    "|残差| 95% 点 [nm]", "|残差| 中央値 [nm]"]);
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

function prefix = outerSetPrefix()
% 「外周の式」で保存した項の組み合わせを選ぶ値の頭（"set:名前"。式の名前 asml などと見分ける）
prefix = "set:";
end

function drawOuterRing(ax, radiusMm)
% 外周の境界（Shot 中心の半径）の円を描く（凡例には足さない）
legendHandle = ax.Legend;
if ~isempty(legendHandle)
    legendHandle.AutoUpdate = 'off';
end
ring = alignest.plot.zoneRings(ax, radiusMm);
set(ring, 'HandleVisibility', 'off');
end
