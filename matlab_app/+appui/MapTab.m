classdef (Abstract) MapTab < appui.Core
    %MAPTAB 「5. Waferごとのマップ」タブ：1つの条件の計測値・推定値・残差、条件を並べて比べる図、Shot スタックマップ。
    %   AlignmentEstimationApp（画面の本体）の一部。画面の部品は Controls、データ・結果は Core のプロパティに持つ。
    %   ほかのタブの関数も同じように呼べる（どれも AlignmentEstimationApp の関数になる）。

    methods
        function showMap(app, unitIndex, planLabel, methodIndex, displayMode, content)
            %SHOWMAP 選んだ Wafer・学習パターン・手法の計測値・推定値・残差（content = "overlay" なら補正残差）を描く。
            c = app.Controls;
            if nargin >= 6
                c.mapContent.Value = char(content);
            end
            if nargin >= 2
                c.mapWafer.Value = unitIndex;
                c.mapPlan.Value = char(planLabel);
                c.mapMethod.Value = methodIndex;
            end
            if nargin >= 5
                c.mapMode.Value = char(displayMode);
            end
            c.mapView.Value = 'single';
            drawMap(app);
        end

        function conditions = addMapCondition(app, optionIndex, planLabel, methodIndex)
            %ADDMAPCONDITION 「5. Waferごとのマップ」の並べて比べる一覧に、条件（Wafer・平均 × 学習パターン × 手法）を足して
            %   並べて描く（並べ方を「一覧の条件を並べて比べる」にする）。引数を省くと画面の選択。同じ条件は足さない。
            c = app.Controls;
            if isempty(app.Results)
                error('alignest:noResults', '先に「3. 実行」で評価してください。');
            end
            if nargin >= 2
                c.mapWafer.Value = optionIndex;
                c.mapPlan.Value = char(planLabel);
                c.mapMethod.Value = methodIndex;
            end
            option = c.mapWafer.UserData(c.mapWafer.Value);
            condition = struct("option", c.mapWafer.Value, "plan", string(c.mapPlan.Value), "method", c.mapMethod.Value, ...
                "label", option.label + "｜" + string(c.mapPlan.Value) + "｜" + app.Results.methods(c.mapMethod.Value).label);
            known = arrayfun(@(item) item.option == condition.option && item.plan == condition.plan && ...
                item.method == condition.method, app.MapConditions);
            if ~any(known)
                if numel(app.MapConditions) >= app.MAX_COMPARE_PANELS
                    error('alignest:mapCompare', '並べて比べる条件は %d までです。「選んだ条件を外す」で減らしてから追加してください。', ...
                        app.MAX_COMPARE_PANELS);
                end
                app.MapConditions(end + 1) = condition;
            end
            refreshMapConditions(app);
            c.mapView.Value = 'compare';
            drawMap(app);
            conditions = app.MapConditions;
        end

        function removeMapConditions(app, indices)
            %REMOVEMAPCONDITIONS 並べて比べる一覧から条件（一覧の何番目か）を外して描き直す。
            app.MapConditions(indices) = [];
            refreshMapConditions(app);
            drawMap(app);
        end
    end

    methods (Access = {?appui.Core})
        % ================= 5. Waferごとのマップ =================
        function buildMapTab(app)
            grid = uigridlayout(app.Tabs.map, [5, 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit'}, 'Padding', 12, ...
                'RowSpacing', 8);
            % 「Shot の枠」は下の行、「図を画像で保存…」は右の列に置く（この行に置くと、狭い窓で手法・図の内容の欄が詰まるため）
            controls = uigridlayout(grid, [2, 9], 'ColumnWidth', {170, 140, '2x', '1x', 110, 110, 80, 70, 80}, ...
                'Padding', 0, 'RowHeight', {'fit', 'fit'});
            arrayfun(@(column) registerResponsiveColumn(app, controls, column), [1, 2, 5, 6, 7, 9]);
            label(controls, 'Wafer・平均', 1, 1);
            label(controls, '学習パターン', 1, 2);
            label(controls, '手法', 1, 3);
            label(controls, '図の内容', 1, 4);
            label(controls, '点の形', 1, 8);
            label(controls, '共分散楕円', 1, 9);
            label(controls, '表示', 1, 5);
            label(controls, '矢印の倍率（0 = 自動）', 1, 6);
            label(controls, '色の点の大きさ', 1, 7);
            onChange = @(~, ~) app.drawMap();
            c.mapWafer = uidropdown(controls, 'Items', {'—'}, 'ValueChangedFcn', onChange);
            place(c.mapWafer, 2, 1);
            c.mapPlan = uidropdown(controls, 'Items', {'—'}, 'ValueChangedFcn', onChange);
            place(c.mapPlan, 2, 2);
            c.mapMethod = uidropdown(controls, 'Items', {'—'}, 'ValueChangedFcn', onChange);
            place(c.mapMethod, 2, 3);
            c.mapContent = uidropdown(controls, 'Items', {'推定（計測値・推定値・残差）', ...
                'Overlay 補正（実測値で補正・推定値で補正・変化）'}, 'ItemsData', {'estimate', 'overlay'}, ...
                'Tooltip', ['Overlay 補正：実測値で補正した残差、推定値で補正した残差（学習 Shot は計測値、それ以外は推定値で' ...
                '補正を求めて実際の値に当てた残差）、推定による変化（両者の差）。補正モデルは「2. 評価の設定」で選びます。'], ...
                'ValueChangedFcn', onChange);
            place(c.mapContent, 2, 4);
            c.mapMode = uidropdown(controls, 'Items', {'ベクトル（矢印）', 'X（色）', 'Y（色）'}, ...
                'ItemsData', {'vector', 'X', 'Y'}, 'ValueChangedFcn', onChange);
            place(c.mapMode, 2, 5);
            c.mapScale = uieditfield(controls, 'numeric', 'Value', 0, 'Limits', [0, Inf], 'ValueChangedFcn', onChange);
            place(c.mapScale, 2, 6);
            c.mapMarkerSize = markerSizeSpinner(app, controls, onChange);
            place(c.mapMarkerSize, 2, 7);
            c.mapMarkerShape = markerShapeDropdown(controls, onChange);
            place(c.mapMarkerShape, 2, 8);
            c.mapEllipse = ellipseDropdown(controls, onChange);
            place(c.mapEllipse, 2, 9);
            % 図に重ねるもの：Shot の枠・Scan 方向の色の Shot の枠・同心円の制約の区切りと、「ベクトルを描かない（楕円だけ）」
            % （上の行の右に置くと、手法・図の内容の欄が狭くなるため）
            extras = uigridlayout(grid, [1, 5], 'ColumnWidth', {'fit', 'fit', 'fit', 'fit', '1x'}, 'Padding', 0);
            c.mapShotFrames = uicheckbox(extras, 'Text', 'Shot の枠', 'Value', true, 'ValueChangedFcn', onChange);
            c.mapScanFrames = uicheckbox(extras, 'Text', 'Shot の枠を Scan 方向で色分け（▲ 上・▼ 下の印つき）', ...
                'ValueChangedFcn', onChange, 'Tooltip', ['Shot の枠を Scan 方向の色で描き、枠の左上に ▲（上向き）・' ...
                '▼（下向き）を付けます。Scan 方向が無い Shot は灰色の枠です。色と、Scan 方向 1・2 のどちらが上向きかは' ...
                '「2. 評価の設定」の表示で変えられます。']);
            c.mapRings = uicheckbox(extras, 'Text', '同心円の区切り（制約）を描く', 'ValueChangedFcn', onChange, ...
                'Tooltip', ['評価で I 最適・ランダムの同心円の制約を使ったとき、区切りの半径（Shot 中心の半径 [mm]）を' ...
                '橙の一点鎖線で描きます。']);
            c.mapEllipseOnly = ellipseOnlyCheckbox(extras, onChange);
            c.mapExtrasInfo = uilabel(extras, 'Text', '', 'FontColor', app.Palette.muted);
            c.filterMap = buildFilterControls(app, grid, "map");
            % 図（1つの条件の3枚、または並べて比べる図）と、並べて比べる条件の一覧
            body = uigridlayout(grid, [1, 2], 'ColumnWidth', {'1x', 300}, 'Padding', 0, 'ColumnSpacing', 10);
            registerResponsiveColumn(app, body, 2);
            c.mapPanel = uipanel(body, 'BorderType', 'none');
            c.mapStack = uigridlayout(c.mapPanel, [2, 1], 'RowHeight', {'1x', 0}, 'Padding', 0, 'RowSpacing', 0);
            axesGrid = uigridlayout(c.mapStack, [1, 3], 'Padding', 0, 'ColumnSpacing', 8);
            c.mapAxes = [uiaxes(axesGrid), uiaxes(axesGrid), uiaxes(axesGrid)];
            c.comparePanel = uipanel(c.mapStack, 'BorderType', 'none');
            c.compareAxes = gobjects(1, 0);
            side = uigridlayout(body, [14, 1], 'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', '1x', ...
                'fit', 'fit', 'fit', 'fit', 'fit'}, 'Padding', 0, 'RowSpacing', 4);
            label(side, '並べ方', 1, 1);
            c.mapView = uidropdown(side, 'Items', {'1つの条件（計測値・推定値・残差）', '一覧の条件を並べて比べる', ...
                'Shot スタックマップ（全 Shot を重ねる）'}, 'ItemsData', {'single', 'compare', 'stack'}, ...
                'ValueChangedFcn', onChange, 'Tooltip', ['Shot スタックマップ：上で選んだ条件の評価点を、Shot 内の座標' ...
                '（markXmm・markYmm）で1つの Shot に重ねて描きます（Shot ごとの値と、Mark の位置ごとの平均）。' ...
                '平均を選ぶと、その Wafer すべての Shot を重ねます。']);
            place(c.mapView, 2, 1);
            label(side, '並べて比べる値・スタックする値', 3, 1);
            c.mapCompareValue = uidropdown(side, 'Items', {'計測値', '推定値', '残差'}, 'ItemsData', {1, 2, 3}, 'Value', 3, ...
                'ValueChangedFcn', onChange, 'Tooltip', ['並べた図・Shot スタックマップはすべて同じ値の種類で、矢印の倍率と' ...
                '色の範囲をそろえて描きます（上の「図の内容」が Overlay 補正なら、補正した残差・推定による変化）。']);
            place(c.mapCompareValue, 4, 1);
            label(side, 'Shot スタックマップの分け方', 5, 1);
            c.mapStackBy = uidropdown(side, 'Items', {'すべての Shot を1つに重ねる', 'Scan 方向ごと', 'Shot 行の偶奇ごと', ...
                'Scan 方向 × 行の偶奇ごと'}, 'ItemsData', {'all', 'scan', 'row', 'scanRow'}, 'ValueChangedFcn', onChange, ...
                'Tooltip', ['Shot スタックマップを、Scan 方向（1・2）や Shot 行の奇数・偶数ごとに分けて重ねます' ...
                '（Scan 方向 × 行の偶奇は 4 枚）。']);
            place(c.mapStackBy, 6, 1);
            c.mapStackAll = uicheckbox(side, 'Text', '計測値・推定値・残差を並べる', 'ValueChangedFcn', onChange, ...
                'Tooltip', ['Shot スタックマップを、計測値・推定値・残差（Overlay 補正なら2つの補正残差・推定による変化）の' ...
                '3列に並べて描きます（分け方の組ごとに1段。矢印の倍率と色の範囲はそろえる）。']);
            place(c.mapStackAll, 7, 1);
            label(side, sprintf('比べる条件（最大 %d。上の選択を追加）', app.MAX_COMPARE_PANELS), 8, 1);
            c.mapConditions = uilistbox(side, 'Items', {}, 'Multiselect', 'on');
            place(c.mapConditions, 9, 1);
            c.mapAddCondition = uibutton(side, 'Text', '上の条件を一覧に追加', ...
                'ButtonPushedFcn', @(~, ~) app.onAddMapCondition(), 'Tooltip', ['上で選んだ Wafer・平均、学習パターン、手法を' ...
                '一覧に足して、並べて描きます（Wafer どうし、手法どうし、学習パターンどうしを比べられます）。']);
            place(c.mapAddCondition, 10, 1);
            c.mapRemoveCondition = uibutton(side, 'Text', '選んだ条件を外す', ...
                'ButtonPushedFcn', @(~, ~) app.removeMapConditions(cell2mat(app.Controls.mapConditions.Value)));
            place(c.mapRemoveCondition, 11, 1);
            c.mapClearConditions = uibutton(side, 'Text', '一覧を空にする', ...
                'ButtonPushedFcn', @(~, ~) app.removeMapConditions(1:numel(app.MapConditions)));
            place(c.mapClearConditions, 12, 1);
            % 図の保存は右の列の一番下（上の欄の行に置くと、狭い窓で欄が詰まる・はみ出すため）
            c.saveMap = uibutton(side, 'Text', '図を画像で保存…', 'ButtonPushedFcn', @(~, ~) app.onSaveMap());
            place(c.saveMap, 13, 1);
            c.copyMap = uibutton(side, 'Text', '図をコピー', 'Tooltip', app.COPY_TOOLTIP, ...
                'ButtonPushedFcn', @(source, ~) app.onCopyFigure("map", source));
            place(c.copyMap, 14, 1);
            set([c.mapWafer, c.mapPlan, c.mapMethod, c.mapContent, c.mapMode, c.mapScale, c.mapMarkerSize, ...
                c.mapMarkerShape, c.mapEllipse, c.mapEllipseOnly, c.mapShotFrames, c.saveMap, c.copyMap, c.mapScanFrames, c.mapRings, ...
                c.mapView, c.mapCompareValue, c.mapConditions, c.mapAddCondition, c.mapRemoveCondition, ...
                c.mapClearConditions, c.mapStackBy, c.mapStackAll], 'Enable', 'off');
            c.mapInfo = uilabel(grid, 'WordWrap', 'on', 'Text', '「3. 実行」で評価すると、ここに Wafer ごとの図が出ます。');
            app.Controls = mergeStruct(app.Controls, c);
        end

        function drawMap(app)
            % 「5. Waferごとのマップ」を描く：1つの条件の 計測値・推定値・残差（または Overlay 補正の3つ）を並べるか、
            % 一覧の条件を同じ値の種類で並べて比べる
            if isempty(app.Results) || (isImportedResults(app.Results) && isempty(app.ImportedEstimates))
                return
            end
            c = app.Controls;
            spec = resultSpec(app);
            setModeChoices(c.mapMode, spec);
            if spec.scalar
                setChoices(c.mapContent, "推定（計測値・推定値・残差）", {'estimate'});
                set([c.mapEllipse, c.mapEllipseOnly], 'Enable', 'off');   % 楕円は X・Y の2成分が要る
                c.mapEllipse.Value = 0;
            end
            content = string(c.mapContent.Value);
            overlayContent = content == "overlay";
            names = ternary(overlayContent, ["実測値で補正した残差", "推定値で補正した残差", "推定による変化"], ...
                ["計測値", "推定値", "残差"]);
            if ~isequal(string(c.mapCompareValue.Items), names)
                c.mapCompareValue.Items = cellstr(names);   % ItemsData（1〜3）と選んだ番号はそのまま
            end
            rings = activeZoneEdges(app.Results.settings);
            c.mapRings.Enable = onOff(~isempty(rings));
            c.mapExtrasInfo.Text = ternary(isempty(rings), "（この評価では同心円の制約を使っていません）", ...
                "区切り：" + strjoin(string(rings), "・") + " mm");
            view = string(c.mapView.Value);
            c.mapStack.RowHeight = ternary(view ~= "single", {0, '1x'}, {'1x', 0});
            if view == "compare"
                drawComparison(app);
                return
            elseif view == "stack"
                drawShotStack(app);
                return
            end
            f = mapFields(app, c.mapWafer.Value, string(c.mapPlan.Value), c.mapMethod.Value, content);
            if ~f.ok
                c.mapInfo.Text = f.message;
                arrayfun(@(ax) cla(ax), c.mapAxes);
                return
            end
            [scale, limit, magnitudes] = mapScales(app, f.values, 1 + overlayContent, overlayContent);
            ranges = repmat({[NaN, NaN]}, 1, 3);
            limits = repmat(limit, 1, 3);
            if spec.scalar
                % 計測値と推定値は同じ値の範囲（最小〜最大）、残差は 0 を中心に自分の範囲
                ranges(1:2) = {valueRange([f.values{1}(:, 1); f.values{2}(:, 1)])};
                limits(3) = absoluteLimit(f.values{3}(:, 1));
            end
            for k = 1:3
                drawMapPanel(app, c.mapAxes(k), f, k, scale(k), limits(k), magnitudes(k), f.titles(k), true, ranges{k});
            end
            c.mapInfo.Text = f.info;
        end

        function drawComparison(app)
            % 一覧の条件を、選んだ値の種類で並べて描く（矢印の倍率・色の範囲・矢印の色の範囲はすべての図で共通）
            c = app.Controls;
            delete(c.comparePanel.Children);
            app.Controls.compareAxes = gobjects(1, 0);
            conditions = app.MapConditions;
            if isempty(conditions)
                c.mapInfo.Text = "比べる条件がありません。上で Wafer・平均、学習パターン、手法を選び、右の「上の条件を一覧に追加」を" + ...
                    "押してください。";
                return
            end
            content = string(c.mapContent.Value);
            valueIndex = c.mapCompareValue.Value;
            spec = resultSpec(app);
            nPanels = min(numel(conditions), app.MAX_COMPARE_PANELS);
            fieldsList = cell(1, nPanels);
            lines = strings(nPanels, 1);
            for k = 1:nPanels
                fieldsList{k} = mapFields(app, conditions(k).option, conditions(k).plan, conditions(k).method, content);
                lines(k) = conditions(k).label + "：" + ternary(fieldsList{k}.ok, sprintf("RMSE（%s）%.3f %s", ...
                    spec.combinedLabel, fieldsList{k}.rmse, spec.unit), fieldsList{k}.message);
            end
            usable = cellfun(@(f) f.ok, fieldsList);
            if ~any(usable)
                c.mapInfo.Text = strjoin(lines, "　／　");
                return
            end
            values = cellfun(@(f) f.values, fieldsList(usable), 'UniformOutput', false);
            stacked = cell2mat(cellfun(@(v) v{valueIndex}, values(:), 'UniformOutput', false));
            [scale, limit] = mapScales(app, {stacked, stacked, stacked}, 1, false);
            magnitude = max([0; hypot(stacked(:, 1), stacked(:, 2))], [], 'omitnan');
            range = [NaN, NaN];
            if spec.scalar && valueIndex < 3
                range = valueRange(stacked(:, 1));   % 1変数の計測値・推定値は値の範囲（すべての図で共通）
            end
            [nRows, nColumns] = tileShape(c.comparePanel, nPanels);
            layout = tiledlayout(c.comparePanel, nRows, nColumns, 'TileSpacing', 'compact', 'Padding', 'compact');
            axesList = gobjects(1, nPanels);
            for k = 1:nPanels
                ax = nexttile(layout);
                axesList(k) = ax;
                f = fieldsList{k};
                if ~f.ok
                    title(ax, conditions(k).label + newline + "（描けません）", 'Interpreter', 'none');
                    axis(ax, 'off');
                    styleAxes(app, ax, app.SMALL_AXES_FONT_SIZE);
                    continue
                end
                titleText = conditions(k).label + newline + f.titles(valueIndex) + sprintf("（RMSE %.3f %s）", f.rmse, ...
                    spec.unit);
                drawMapPanel(app, ax, f, valueIndex, scale(1), limit, magnitude, titleText, false, range);
                styleAxes(app, ax, app.SMALL_AXES_FONT_SIZE);
                if ~isempty(ax.Colorbar)
                    % 色の目盛りの名前は横に書く（並べた図では上に書くと題名と重なる）
                    ax.Colorbar.Label.String = ax.Colorbar.Title.String;
                    ax.Colorbar.Title.String = '';
                end
            end
            app.Controls.compareAxes = axesList;
            header = sprintf("並べて比べる：%s（%d 条件。矢印の倍率・色の範囲は共通。灰色の四角は学習に使った Mark）", ...
                string(c.mapCompareValue.Items{valueIndex}), nPanels);
            if numel(conditions) > nPanels
                header = header + sprintf("。一覧の %d 条件のうち、はじめの %d 条件を描きました", numel(conditions), nPanels);
            end
            c.mapInfo.Text = header + "｜" + strjoin(lines, "　／　") + filterNote(app);
        end

        function summary = drawShotStack(app)
            % Shot スタックマップ：上で選んだ条件の評価点を、Shot 内の座標で1つの Shot に重ねて描く（分け方は画面の選択）。
            % 図は Scan 方向・Shot 行の偶奇ごとに並べ、矢印の倍率と色の範囲はすべての図で共通にする。「計測値・推定値・
            % 残差を並べる」なら、3つの値を列に、分け方の組を段にして並べる（矢印の倍率・色の範囲は計測値に合わせる）。
            c = app.Controls;
            delete(c.comparePanel.Children);
            app.Controls.compareAxes = gobjects(1, 0);
            summary = {};
            content = string(c.mapContent.Value);
            f = mapFields(app, c.mapWafer.Value, string(c.mapPlan.Value), c.mapMethod.Value, content);
            if ~f.ok
                c.mapInfo.Text = f.message;
                return
            end
            if isempty(f.stack.local)
                c.mapInfo.Text = "⚠ Shot スタックマップは、このセッションで評価した結果で描けます（Excel から読み込んだ" + ...
                    "推定値には Shot 内の座標が無いため）。";
                return
            end
            valueNames = string(c.mapCompareValue.Items);
            valueIndices = c.mapCompareValue.Value;
            if c.mapStackAll.Value
                valueIndices = 1:3;
            end
            reference = f.stack.values{valueIndices(1)};   % 1つの値ならその値に合わせる
            if numel(valueIndices) > 1
                reference = f.stack.values{1 + (content == "overlay")};   % 3つ並べるときは「5. マップ」の3枚の図と同じ基準
            end
            [groups, names] = stackGroups(f.stack, string(c.mapStackBy.Value), scanStyle(app));
            spec = resultSpec(app);
            mode = string(c.mapMode.Value);
            if spec.scalar
                mode = "X";
            end
            scale = c.mapScale.Value;
            if scale <= 0
                % Shot の短い辺の 18% の矢印が、基準の値の大きさの95%点になる倍率（図をまたいで共通）
                scale = alignest.plot.vectorScale(reference) * min(f.sizeMm) * 0.18 / 12;
            end
            column = 1 + (mode == "Y");
            limit = absoluteLimit(reference(:, column));
            colorTitle = "";
            if spec.scalar
                colorTitle = spec.name + " [" + spec.unit + "]";
            end
            nGroups = numel(groups);
            nValues = numel(valueIndices);
            if nValues > 1
                layout = tiledlayout(c.comparePanel, nGroups, nValues, 'TileSpacing', 'compact', 'Padding', 'compact');
            else
                [nRows, nColumns] = tileShape(c.comparePanel, nGroups);
                layout = tiledlayout(c.comparePanel, nRows, nColumns, 'TileSpacing', 'compact', 'Padding', 'compact');
            end
            axesList = gobjects(1, nGroups * nValues);
            counts = zeros(1, nGroups);
            summary = cell(nGroups, nValues);
            for g = 1:nGroups
                rows = groups{g};
                counts(g) = nnz(rows);
                for v = 1:nValues
                    index = valueIndices(v);
                    values = f.stack.values{index};
                    range = [NaN, NaN];
                    panelLimit = limit;
                    if spec.scalar && index < 3
                        range = valueRange([f.stack.values{1}(:, 1); f.stack.values{2}(:, 1)]);
                    elseif spec.scalar
                        panelLimit = absoluteLimit(values(:, 1));   % 1変数の残差は 0 を中心に自分の範囲
                    end
                    ax = nexttile(layout);
                    axesList((g - 1) * nValues + v) = ax;
                    titleText = names(g) + sprintf("（%d 点）", counts(g));
                    if nValues > 1
                        titleText = names(g) + "｜" + valueNames(index);
                    end
                    summary{g, v} = alignest.plot.shotStackMap(ax, f.stack.local(rows, :), values(rows, :), mode=mode, ...
                        shotSizeMm=f.sizeMm, scaleMmPerNm=scale, colorLimit=panelLimit, colorRange=range, ...
                        colorTitle=colorTitle, titleText=titleText, markerSize=c.mapMarkerSize.Value, ...
                        showLegend=g == 1 && v == 1);
                    styleAxes(app, ax, ternary(nGroups * nValues > 1, app.SMALL_AXES_FONT_SIZE, app.AXES_FONT_SIZE));
                end
            end
            app.Controls.compareAxes = axesList;
            option = c.mapWafer.UserData(c.mapWafer.Value);
            valueText = strjoin(valueNames(valueIndices), "・");
            c.mapInfo.Text = sprintf(['Shot スタックマップ：%s｜%s｜%s｜%s を Shot 内の座標で重ねた（%s）。薄い矢印・点は' ...
                ' Shot ごと、濃い矢印・■ は Mark の位置ごとの平均。矢印の倍率と色の範囲は共通（%s に合わせる）。'], option.label, ...
                string(c.mapPlan.Value), app.Results.methods(c.mapMethod.Value).label, valueText, ...
                strjoin(names + " " + counts + " 点", "・"), ternary(numel(valueIndices) > 1, ...
                valueNames(1 + (content == "overlay")), valueNames(valueIndices(1)))) + filterNote(app);
            if nGroups * nValues > app.MAX_STACK_PANELS_NOTICE
                c.mapInfo.Text = c.mapInfo.Text + sprintf("（図が %d 枚と多いので、分け方を減らすと大きく見られます）", ...
                    nGroups * nValues);
            end
        end

        function drawMapPanel(app, ax, f, k, scale, limit, magnitude, titleText, showLegend, colorRange)
            % マップの1枚（mapFields の k 番目の値）を描く。Shot の枠・Scan 方向の色・同心円の区切りは画面の選択に従う。
            % colorRange（省略可）：1変数の計測値・推定値の色の範囲 [最小, 最大]（alignest.plot.waferMap）
            if nargin < 10
                colorRange = [NaN, NaN];
            end
            c = app.Controls;
            settings = app.Results.settings;
            spec = resultSpec(app);
            colorTitle = "";
            if spec.scalar
                colorTitle = spec.name + " [" + spec.unit + "]";
            end
            centers = zeros(0, 2);
            sizeMm = [NaN, NaN];
            directions = zeros(0, 1);
            if c.mapShotFrames.Value || c.mapScanFrames.Value
                centers = f.centers;
                sizeMm = f.sizeMm;
                if c.mapScanFrames.Value
                    directions = f.directions;
                end
            end
            rings = zeros(1, 0);
            if c.mapRings.Value
                rings = activeZoneEdges(settings);
            end
            ellipseSigma = c.mapEllipse.Value * f.isGroup;
            alignest.plot.waferMap(ax, f.points, f.values{k}, mode=string(c.mapMode.Value), scaleMmPerNm=scale, ...
                colorLimit=limit, trainPoints=f.trainPoints, outlierPoints=f.outlierPoints, titleText=titleText, ...
                waferRadiusMm=settings.data.waferRadiusMm, magnitudeLimit=magnitude, arrowColor=app.ARROW_COLORS(k, :), ...
                markerSize=c.mapMarkerSize.Value, markerShape=c.mapMarkerShape.Value, shotCenters=centers, ...
                shotSizeMm=sizeMm, shotDirections=directions, ringRadiiMm=rings, covariance=f.covariance{k}, scanStyle=scanStyle(app), ...
                ellipseSigma=ellipseSigma, showArrows=~(c.mapEllipseOnly.Value && ellipseSigma > 0), showLegend=showLegend, ...
                colorRange=colorRange, colorTitle=colorTitle);
            styleAxes(app, ax, app.AXES_FONT_SIZE);
        end

        function [scale, limit, magnitudes] = mapScales(app, values, referenceIndex, separateThird)
            % 矢印の倍率（0 = 自動なら基準の値から）・色の範囲（基準の値の最大の絶対値）・矢印の色の範囲。
            % separateThird（Overlay 補正）なら、3つ目（推定による変化）は小さいので自分の値で倍率を決める
            c = app.Controls;
            reference = values{referenceIndex};
            scale = repmat(c.mapScale.Value, 1, 3);
            if c.mapScale.Value <= 0
                scale(:) = alignest.plot.vectorScale(reference);
                if separateThird
                    scale(3) = alignest.plot.vectorScale(values{3});
                end
            end
            limit = max(abs(reference(isfinite(reference))), [], 'all');
            if isempty(limit) || limit <= 0
                limit = 1;
            end
            magnitudes = sharedMagnitudeLimits(values{1}, values{2});
        end

        function f = mapFields(app, optionIndex, planLabel, m, content)
            % 1つの条件（Wafer・平均 × 学習パターン × 手法）のマップの値。描けないときは f.ok = false、f.message に理由。
            % f.values{1〜3}：計測値・推定値・残差（content = "overlay" なら 実測値で補正した残差・推定値で補正した残差・
            % 推定による変化）。点数 × 2 [nm]、点の座標は f.points。平均（f.isGroup）では座標ごとの Wafer 間の平均と
            % 共分散（f.covariance）。評価点の絞り込みの条件に合う点だけを入れる。f.rmse は RMSE（X・Y）の値（平均なら
            % Wafer の平均）、f.info は図の下の説明
            c = app.Controls;
            results = app.Results;
            option = c.mapWafer.UserData(optionIndex);
            method = results.methods(m);
            f = struct("ok", false, "message", "", "points", zeros(0, 2), "values", {cell(1, 3)}, ...
                "covariance", {repmat({zeros(0, 3)}, 1, 3)}, "titles", strings(1, 3), "trainPoints", zeros(0, 2), ...
                "outlierPoints", zeros(0, 2), "centers", zeros(0, 2), "sizeMm", [NaN, NaN], "directions", zeros(0, 1), ...
                "isGroup", option.isGroup, "rmse", NaN, "info", "", "stack", struct("local", zeros(0, 2), ...
                "values", {cell(1, 3)}, "direction", zeros(0, 1), "parity", zeros(0, 1)));
            overlayContent = string(content) == "overlay";
            if overlayContent && option.isGroup
                f.titles = ["実測値で補正した残差の平均", "推定値で補正した残差の平均", "推定による変化の平均"];
            elseif overlayContent
                f.titles = ["実測値で補正した残差", "推定値で補正した残差", "推定による変化（推定値で補正 − 実測値で補正）"];
            elseif option.isGroup
                f.titles = ["計測値の平均（評価した Shot）", "推定値の平均", "残差（計測値 − 推定値）の平均"];
            else
                f.titles = ["計測値（評価した Shot）", "推定値", "残差（計測値 − 推定値）"];
            end
            try
                if isImportedResults(results)
                    f = importedMapFields(app, f, option, string(planLabel), method, m, overlayContent);
                else
                    f = computedMapFields(app, f, option, string(planLabel), method, m, overlayContent);
                end
            catch err
                f.ok = false;
                f.message = "⚠ " + string(err.message);
            end
            if f.ok
                f.info = f.info + filterNote(app);
            end
        end

        function f = computedMapFields(app, f, option, planLabel, method, m, overlayContent)
            % このセッションで評価した結果のマップの値（推定値は評価のときの値を使い回す。alignest.compactEstimate）
            results = app.Results;
            settings = results.settings;
            plans = results.plans;
            [~, ~, filterActive] = alignest.pointFilterMask(app.ResultFilter);
            if overlayContent
                choice = alignest.overlayChoice(settings);
            end
            pointsList = cell(1, 0);
            panelValues = {cell(1, 0), cell(1, 0), cell(1, 0)};
            stackParts = cell(3, 0);   % Shot スタックマップ用：Shot 内の座標・Scan 方向・Shot 行の偶奇（点ごと）
            firstUnit = [];
            skipped = 0;
            for u = option.unitIndex
                planIndex = find(string({plans.label}) == planLabel & [plans.unitIndex] == u, 1);
                if isempty(planIndex) || ~plans(planIndex).ok
                    if ~option.isGroup && isempty(planIndex)
                        f.message = "⚠ この Wafer はこの学習パターンを計算していません（途中で止めた場合など）。";
                        return
                    elseif ~option.isGroup
                        f.message = "⚠ この Wafer ではこの学習パターンを作れませんでした：" + plans(planIndex).message;
                        return
                    end
                    skipped = skipped + 1;
                    continue
                end
                try
                    out = cachedEstimate(app, u, planIndex, m);
                catch err
                    if ~option.isGroup
                        f.message = "⚠ この組み合わせでは推定できませんでした：" + string(err.message);
                        return
                    end
                    skipped = skipped + 1;
                    continue
                end
                unit = app.Data.units(u);
                marks = unit.marks;
                mask = true(numel(marks.x), 1);
                if filterActive
                    mask = alignest.unitPointFilter(unit, app.ResultFilter);
                end
                if overlayContent
                    correction = alignest.overlayCorrection(unit, out, ...
                        alignest.overlayProjector(unit, choice, settings.data.waferRadiusMm), mask);
                    usable = (marks.validX | marks.validY) & mask;
                    values = {correction.fields.residualActual, correction.fields.residualEstimated, correction.fields.change};
                else
                    measured = nan(numel(marks.x), 2);
                    estimate = nan(numel(marks.x), 2);
                    measured(out.testIndex.X, 1) = marks.measX(out.testIndex.X);
                    measured(out.testIndex.Y, 2) = marks.measY(out.testIndex.Y);
                    estimate(out.testIndex.X, 1) = out.estimate.X;
                    estimate(out.testIndex.Y, 2) = out.estimate.Y;
                    usable = any(isfinite(measured), 2) & mask;
                    values = {measured, estimate, measured - estimate};
                end
                pointsList{end + 1} = [marks.x(usable), marks.y(usable)]; %#ok<AGROW>
                for k = 1:3
                    panelValues{k}{end + 1} = values{k}(usable, :);
                end
                direction = nan(nnz(usable), 1);
                if unit.hasDirection
                    direction = marks.direction(usable);
                end
                stackParts(:, end + 1) = {[marks.markXmm(usable), marks.markYmm(usable)]; direction; ...
                    marks.shotRowParity(usable)}; %#ok<AGROW>
                if isempty(firstUnit)
                    % 学習 Shot の四角・異常値の × は最初の Wafer の位置（平均の図でも）
                    firstUnit = unit;
                    plan = plans(planIndex);
                    trainMarks = alignest.trainingMarks(unit, plan) & (marks.validX | marks.validY) & mask;
                    f.trainPoints = [marks.x(trainMarks), marks.y(trainMarks)];
                    if ~overlayContent && ~option.isGroup && isfield(out, "outlierIndex")
                        outlierIndex = out.outlierIndex(mask(out.outlierIndex));
                        f.outlierPoints = [marks.x(outlierIndex), marks.y(outlierIndex)];
                    end
                    firstOut = out;
                    firstMask = mask;
                    if overlayContent
                        firstCorrection = correction;
                    end
                end
            end
            if isempty(firstUnit)
                f.message = "⚠ この平均に使える Wafer がありません（学習パターンを作れなかった、または推定できなかった）。";
                return
            end
            if sum(cellfun(@(points) size(points, 1), pointsList)) == 0
                f.message = "⚠ 評価点の絞り込みの条件に合う点がありません（「解除」または条件を変えてください）。";
                return
            end
            shots = firstUnit.shots;
            f.centers = [shots.Xmm, shots.Ymm];
            f.sizeMm = firstUnit.shotSizeMm;
            f.stack = struct("local", vertcat(stackParts{1, :}), "values", ...
                {cellfun(@(parts) vertcat(parts{:}), panelValues, 'UniformOutput', false)}, ...
                "direction", vertcat(stackParts{2, :}), "parity", vertcat(stackParts{3, :}));
            f.directions = nan(numel(shots.Xmm), 1);
            if firstUnit.hasDirection
                f.directions = shots.direction;
            end
            table_ = results.table;
            if option.isGroup
                for k = 1:3
                    average = alignest.averageFields(pointsList, panelValues{k});
                    f.values{k} = average.mean;
                    f.covariance{k} = average.covariance;
                end
                f.points = average.points;
                rows = table_(ismember(table_.unitIndex, option.unitIndex) & table_.plan == planLabel & ...
                    table_.methodIndex == m, :);
                f.rmse = mean(rows.RMSE_XY, 'omitnan');
                f.info = sprintf(['%s｜%s｜%s｜平均した Wafer %d 枚%s｜座標ごとに Wafer 間で平均（楕円は Wafer 間の' ...
                    'ばらつき、色は X・Y の相関係数の絶対値 |r|）｜Wafer ごとの RMSE（X・Y）の平均 %.3f nm'], option.label, ...
                    planLabel, method.label, numel(pointsList), ternary(skipped > 0, sprintf("（使えなかった Wafer %d 枚）", ...
                    skipped), ""), f.rmse);
                f = addWorstValues(app, f, rows);
                f.ok = true;
                return
            end
            f.points = pointsList{1};
            f.values = cellfun(@(values) values{1}, panelValues, 'UniformOutput', false);
            if overlayContent
                metrics = firstCorrection.metrics;
                f.rmse = mean(table_.RMSE_XY(table_.unitIndex == option.unitIndex & table_.planIndex == planIndex & ...
                    table_.methodIndex == m));
                f.info = sprintf(['%s｜%s｜%s｜補正モデル：%s｜|平均|+3σ [nm]：実測値で補正 X %.3f・Y %.3f、' ...
                    '推定値で補正 X %.3f・Y %.3f、推定による変化 X %.3f・Y %.3f（増加 X %+.3f・Y %+.3f）'], firstUnit.label, ...
                    planLabel, method.label, choice.description, metrics.overlayActual_X, metrics.overlayActual_Y, ...
                    metrics.overlayEstimated_X, metrics.overlayEstimated_Y, metrics.overlayChange_X, metrics.overlayChange_Y, ...
                    metrics.overlayIncrease_X, metrics.overlayIncrease_Y);
                f = addWorstValues(app, f, rowsOf(table_, option, planLabel, m));
                f.ok = true;
                return
            end
            row = table_(table_.unitIndex == option.unitIndex & table_.planIndex == planIndex & table_.methodIndex == m, :);
            metricsText = "";
            if ~isempty(row)
                f.rmse = row.RMSE_XY;
                metricsText = sprintf("RMSE（X・Y）%.3f nm、X %.3f nm、Y %.3f nm｜R² %.3f｜MAE %.3f nm｜平均値に対する改善率 %.1f%%", ...
                    row.RMSE_XY, row.RMSE_X, row.RMSE_Y, row.R2_XY, row.MAE_XY, row.improveMeanPct_XY);
                spec = alignest.valueSpec(settings.data);
                if spec.scalar
                    metricsText = sprintf("RMSE（%s）%.3f %s｜R² %.3f｜MAE %.3f %s｜平均値に対する改善率 %.1f%%", spec.name, ...
                        row.RMSE_XY, spec.unit, row.R2_XY, row.MAE_XY, spec.unit, row.improveMeanPct_XY);
                end
            end
            outlierText = "";
            evaluation = settings.evaluation;
            if isfield(evaluation, "excludeOutliers") && evaluation.excludeOutliers
                outlierText = sprintf("｜学習から除いた異常値 %d 点（%gσ 超、×印）", size(f.outlierPoints, 1), ...
                    evaluation.outlierSigma);
            end
            plan = plans(planIndex);
            trainText = sprintf("学習 Shot %d（shotNo：%s）", plan.nShots, strjoin(string(plan.shotNos(:).'), " "));
            if ~isempty(plan.markIndex)
                trainText = sprintf("学習 Mark %d（%s）", numel(plan.markIndex), ...
                    markShotText(firstUnit, plan, nnz(firstUnit.shots.nValidX + firstUnit.shots.nValidY > 0)));
            end
            testText = sprintf("評価点 X %d・Y %d", nnz(firstMask(firstOut.testIndex.X)), nnz(firstMask(firstOut.testIndex.Y)));
            if alignest.valueSpec(settings.data).scalar
                testText = sprintf("評価点 %d", nnz(firstMask(firstOut.testIndex.X)));
            end
            f.info = sprintf("%s｜%s｜%s｜%s｜%s%s｜%s", firstUnit.label, plan.label, method.label, trainText, testText, ...
                outlierText, metricsText);
            f = addWorstValues(app, f, rowsOf(table_, option, planLabel, m));
            f.ok = true;
        end

        function f = importedMapFields(app, f, option, planLabel, method, m, overlayContent)
            % Excel から読み込んだ推定値のマップの値（Shot 中心の座標は Excel に無いので、Shot の枠は描かない）
            results = app.Results;
            if overlayContent
                source = app.ImportedEstimates.overlayPoints;
                columns = ["residualActual", "residualEstimated", "change"];
            else
                source = app.ImportedEstimates.estimates;
                source = source(source.role == "評価" | startsWith(source.role, "学習"), :);
                columns = ["meas", "estimate", "residual"];
            end
            [~, ~, filterActive] = alignest.pointFilterMask(app.ResultFilter);
            pointsList = cell(1, 0);
            panelValues = {cell(1, 0), cell(1, 0), cell(1, 0)};
            for u = option.unitIndex
                rows = source(source.Wafer == results.unitLabels(u) & source.plan == planLabel & ...
                    source.methodId == method.id, :);
                if height(rows) == 0
                    continue
                end
                mask = true(height(rows), 1);
                if filterActive
                    % Overlay 残差のシートには半径・Scan 方向の列が無いので、座標から半径を求める（Scan 方向は無し）
                    direction = nan(height(rows), 1);
                    if any(rows.Properties.VariableNames == "direction")
                        direction = rows.direction;
                    end
                    mask = alignest.pointFilterMask(app.ResultFilter, struct("r", hypot(rows.x, rows.y), ...
                        "shotNo", rows.shotNo, "direction", direction));
                end
                train = startsWith(rows.role, "学習");
                if isempty(pointsList)
                    f.trainPoints = [rows.x(train & mask), rows.y(train & mask)];   % 平均の図でも最初の Wafer の位置
                    outlier = rows.role == "学習（異常値として除外）" & mask;
                    f.outlierPoints = [rows.x(outlier), rows.y(outlier)];
                end
                keep = mask;
                if ~overlayContent
                    keep = mask & ~train;   % 計測値・推定値・残差は評価点だけ
                end
                rows = rows(keep, :);
                pointsList{end + 1} = [rows.x, rows.y]; %#ok<AGROW>
                for k = 1:3
                    panelValues{k}{end + 1} = [rows.(columns(k) + "X"), rows.(columns(k) + "Y")];
                end
            end
            if isempty(pointsList)
                f.message = "⚠ この Wafer・学習パターン・手法の推定値は、読み込んだ推定値の Excel にありません" + ...
                    "（書き出した範囲の外）。";
                return
            end
            if sum(cellfun(@(points) size(points, 1), pointsList)) == 0
                f.message = "⚠ 評価点の絞り込みの条件に合う点がありません（「解除」または条件を変えてください）。";
                return
            end
            if option.isGroup
                for k = 1:3
                    average = alignest.averageFields(pointsList, panelValues{k});
                    f.values{k} = average.mean;
                    f.covariance{k} = average.covariance;
                end
                f.points = average.points;
                f.outlierPoints = zeros(0, 2);
            else
                f.points = pointsList{1};
                f.values = cellfun(@(values) values{1}, panelValues, 'UniformOutput', false);
            end
            rows = rowsOf(results.table, option, planLabel, m);
            f.rmse = mean(rows.RMSE_XY, 'omitnan');
            f.info = sprintf("%s｜%s｜%s｜Excel から読み込んだ推定値（Wafer %d 枚）｜Wafer ごとの RMSE（X・Y）の平均 %.3f nm", ...
                option.label, planLabel, method.label, numel(pointsList), f.rmse);
            f = addWorstValues(app, f, rows);
            f.ok = true;
        end

        function refreshMapConditions(app)
            % 並べて比べる条件の一覧を画面に出す
            c = app.Controls;
            conditions = app.MapConditions;
            c.mapConditions.Items = cellstr(string({conditions.label}));
            c.mapConditions.ItemsData = num2cell(1:numel(conditions));
            c.mapConditions.Value = {};
        end

        function f = addWorstValues(app, f, rows)
            % マップの3枚目（残差・推定による変化）の点の大きさ |v| のワースト値と 95%値を題名に、X・Y 別の値と
            % （平均の図では）Wafer ごとの RMSE のワースト値・95%値を説明に足す（結果一覧の集計と同じ PERCENTILE.INC）
            values = f.values{3};
            spec = resultSpec(app);
            if spec.scalar
                % 1変数：残差の絶対値のワースト値・95%値
                magnitude = abs(values(:, 1));
                worst = max(magnitude, [], 'omitnan');
                if isempty(worst) || ~isfinite(worst)
                    return
                end
                f.titles(3) = f.titles(3) + newline + sprintf("|残差| のワースト %.3f %s・95%%値 %.3f %s", worst, ...
                    spec.unit, alignest.stats.percentile(magnitude, app.WORST_PERCENT), spec.unit);
                f.info = f.info + sprintf("｜残差：ワースト値 %.3f %s、95%%値 %.3f %s", worst, spec.unit, ...
                    alignest.stats.percentile(magnitude, app.WORST_PERCENT), spec.unit);
                if f.isGroup && height(rows) > 0
                    f.info = f.info + sprintf("｜Wafer ごとの RMSE：ワースト値 %.3f %s、95%%値 %.3f %s", ...
                        max(rows.RMSE_XY, [], 'omitnan'), spec.unit, ...
                        alignest.stats.percentile(rows.RMSE_XY, app.WORST_PERCENT), spec.unit);
                end
                return
            end
            magnitude = hypot(values(:, 1), values(:, 2));
            worst = max(magnitude, [], 'omitnan');
            if isempty(worst) || ~isfinite(worst)
                return
            end
            f.titles(3) = f.titles(3) + newline + sprintf("|v| のワースト %.2f nm・95%%値 %.2f nm", worst, ...
                alignest.stats.percentile(magnitude, app.WORST_PERCENT));
            f.info = f.info + sprintf("｜%s：ワースト値 X %.3f・Y %.3f nm、95%%値 X %.3f・Y %.3f nm", ...
                extractBefore(f.titles(3) + "（", "（"), max(abs(values(:, 1)), [], 'omitnan'), ...
                max(abs(values(:, 2)), [], 'omitnan'), alignest.stats.percentile(abs(values(:, 1)), app.WORST_PERCENT), ...
                alignest.stats.percentile(abs(values(:, 2)), app.WORST_PERCENT));
            if f.isGroup && height(rows) > 0
                f.info = f.info + sprintf("｜Wafer ごとの RMSE（X・Y）：ワースト値 %.3f nm、95%%値 %.3f nm", ...
                    max(rows.RMSE_XY, [], 'omitnan'), alignest.stats.percentile(rows.RMSE_XY, app.WORST_PERCENT));
            end
        end

        function onAddMapCondition(app)
            runWithAlert(app, @() app.addMapCondition(), "条件を追加できませんでした", ...
                "Wafer・平均、学習パターン、手法を選び直してください。");
        end

        function out = cachedEstimate(app, u, planIndex, m)
            % 推定結果を使い回す（マップ・散布図・推定値の書き出しで共通のキー）
            key = sprintf('%d|%d|%d', u, planIndex, m);
            if isKey(app.MapCache, key)
                out = app.MapCache(key);
                return
            end
            app.Figure.Pointer = 'watch';
            drawnow;
            restore = onCleanup(@() set(app.Figure, 'Pointer', 'arrow'));
            plan = app.Results.plans(planIndex);
            out = alignest.estimateWafer(app.Data.units(u), plan, app.Results.methods(m), app.Results.settings);
            app.MapCache(key) = out;
        end

        function units = mapUnits(app)
            % マップの「Wafer・平均」の選択肢を作る Wafer の並び（読み込んだ結果では、結果の表の Wafer・LotID・EqpId・Operation）
            if ~isImportedResults(app.Results)
                units = app.Data.units;
                return
            end
            results = app.Results;
            units = struct("label", {}, "lotId", {}, "eqpId", {}, "operation", {});
            for u = 1:numel(results.unitLabels)
                row = find(results.table.unitIndex == u, 1);
                units(u) = struct("label", results.unitLabels(u), "lotId", results.table.LotID(row), ...
                    "eqpId", results.table.EqpId(row), "operation", results.table.Operation(row));
            end
        end

        function onSaveMap(app)
            saveFigureWithDialog(app, "map", 'wafer_map.png');
        end
    end
end

% ================= このファイルだけで使う小さな関数 =================
function limits = sharedMagnitudeLimits(first, second)
% 矢印の色（長さ）の上限：はじめの2つの図（計測値と推定値、または2つの補正残差）はそろえて比べられるようにし、
% 3つ目（残差・推定による変化）は値が小さいので自分の最大（0 = 自動）にする
magnitude = [hypot(first(:, 1), first(:, 2)); hypot(second(:, 1), second(:, 2))];
top = max(magnitude(isfinite(magnitude)), [], 'all');
if isempty(top)
    top = 0;
end
limits = [top, top, 0];
end

function [groups, names] = stackGroups(stack, by, style)
% Shot スタックマップの分け方：点の選択（論理ベクトルの cell）と図の名前。点の無い組は描かない
n = size(stack.local, 1);
direction = stack.direction;
parity = stack.parity;
scanMasks = {direction == 1, direction == 2, ~ismember(direction, [1, 2])};
scanNames = [style.names, "Scan 方向なし"];
rowMasks = {parity == 1, parity == 2, ~ismember(parity, [1, 2])};
rowNames = ["奇数行", "偶数行", "行が不明"];
switch by
    case "scan"
        groups = scanMasks;
        names = scanNames;
    case "row"
        groups = rowMasks;
        names = rowNames;
    case "scanRow"
        groups = cell(1, 0);
        names = strings(1, 0);
        for s = 1:numel(scanMasks)
            for r = 1:numel(rowMasks)
                groups{end + 1} = scanMasks{s} & rowMasks{r}; %#ok<AGROW>
                names(end + 1) = scanNames(s) + "・" + rowNames(r); %#ok<AGROW>
            end
        end
    otherwise
        groups = {true(n, 1)};
        names = "すべての Shot";
end
used = cellfun(@any, groups);
groups = groups(used);
names = names(used);
if isempty(groups)
    groups = {true(n, 1)};
    names = "すべての Shot";
end
end

function rows = rowsOf(table_, option, planLabel, methodIndex)
% マップの条件（Wafer・平均 × 学習パターン × 手法）の、結果の表の行
rows = table_(ismember(table_.unitIndex, option.unitIndex) & table_.plan == planLabel & ...
    table_.methodIndex == methodIndex, :);
end

function limit = absoluteLimit(values)
% 0 を中心にした色の範囲 ±limit（残差など）
limit = max(abs(values(isfinite(values))), [], 'all');
if isempty(limit) || limit <= 0
    limit = 1;
end
end
