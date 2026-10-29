classdef (Abstract) DataTab < appui.Core
    %DATATAB 「1. データの読み込み」タブ：ファイルの読み込み、列の対応・座標の単位、Wafer マップ・Shot レイアウト・Shot 重ね合わせ、質的変数の交互作用。
    %   AlignmentEstimationApp（画面の本体）の一部。画面の部品は Controls、データ・結果は Core のプロパティに持つ。
    %   ほかのタブの関数も同じように呼べる（どれも AlignmentEstimationApp の関数になる）。

    methods
        % ---- 画面の操作と同じことをするメソッド（ボタンからも自動テストからも呼ぶ）
        function loadFile(app, filePath, sheetName)
            %LOADFILE ファイルを読み、列の対応を推定して表に出す（まだ解析用には変換しない）。
            if nargin < 3
                sheetName = "";
            end
            [raw, sheets, sheetName] = alignest.readMeasurementFile(filePath, sheetName);
            app.RawTable = raw;
            app.FilePath = string(filePath);
            app.SheetName = sheetName;
            app.Data = [];
            clearResults(app);
            clearDataMaps(app);
            c = app.Controls;
            % 長いパスは切れて読めないので、ファイル名だけを出し、フォルダはマウスを重ねたときに出す
            [~, name, extension] = fileparts(app.FilePath);
            c.filePath.Text = name + extension;
            c.filePath.Tooltip = char(app.FilePath);
            if all(sheets == "")
                c.sheet.Items = {'（CSV にはシートがありません）'};
                c.sheet.Enable = 'off';
            else
                c.sheet.Items = cellstr(sheets);
                c.sheet.Value = char(sheetName);
                c.sheet.Enable = 'on';
            end
            refreshValueColumns(app);
            fillMappingTable(app, alignest.guessColumnMapping(raw.Properties.VariableNames));
            fillUnitTable(app);
            c.mappingStatus.Text = sprintf(['%d 行・%d 列を読みました。「ファイルの列」の対応と、右の「座標の単位」を' ...
                '確かめてから、「この対応で読み込む」を押してください。'], height(raw), width(raw));
            c.mappingStatus.FontColor = app.Palette.text;
            c.applyMapping.Enable = 'on';
            c.summary.Value = {''};
            c.dataTabs.SelectedTab = c.mappingTab;
            refreshRunSummary(app);
        end

        function applyMapping(app)
            %APPLYMAPPING 列の対応・座標の単位・行の除外・Scan 方向の付与に従って前処理し、Wafer ごとのデータにする。
            if isempty(app.RawTable) || width(app.RawTable) == 0
                error('alignest:noFile', '先に「ファイルを選ぶ…」で計測データを読み込んでください。');
            end
            mapping = currentMapping(app);
            options = currentDataOptions(app);
            invalidatePreparedData(app);
            app.Data = alignest.prepareData(app.RawTable, mapping, validRadiusMm=options.validRadiusMm, ...
                coordinateUnits=options.coordinateUnits, excludeZeroMeasurements=options.excludeZeroMeasurements, ...
                excludeUnmeasuredRecords=options.excludeUnmeasuredRecords, directionRule=options.directionRule, ...
                invertDirection=options.invertDirection, directionOverrideShots=options.directionOverrideShots, ...
                directionOverrideValues=options.directionOverrideValues, coordinateMode=options.coordinateMode, ...
                valueColumn=options.valueColumn);
            app.AppliedMapping = mapping;
            app.Settings.data = mergeStruct(app.Settings.data, options);
            summary = app.Data.summary;
            lines = [sprintf("Wafer（評価の単位）：%d 枚", summary.nUnits); ...
                "工程（Operation）：" + listOrNone(summary.operations); ...
                "装置（EqpId）：" + listOrNone(summary.eqpIds); ...
                "ロット（LotID）：" + listOrNone(summary.lotIds); ...
                sprintf("Shot 数：%d〜%d／Wafer、Mark 数：%d〜%d／Wafer", summary.nShotsRange, summary.nMarksRange); ...
                "Shot の大きさ（中心の間隔から推定）：" + shotSizeText(summary.shotSizeRangeMm); ...
                sprintf("Mark 番号の水準：%s", strjoin(string(summary.markLevels), "、")); ...
                "Scan 方向（Direction）：" + directionText(summary); ...
                "質的変数に選べるその他の列：" + listOrNone(summary.attributeNames); ...
                summary.messages(:)];
            app.Controls.summary.Value = cellstr(lines);
            labels = string({app.Data.units.label});
            app.Controls.layoutWafer.Items = cellstr(labels);
            app.Controls.layoutWafer.ItemsData = 1:numel(labels);
            app.Controls.layoutWafer.Value = 1;
            app.MeasurementCache = [];
            refreshMeasurementChoices(app);
            refreshPreviewGroupBy(app);
            app.Controls.mappingStatus.Text = sprintf(['読み込みました（%d 枚）。上の「Wafer マップ」「Shot レイアウト」で' ...
                'データを確かめ、「2. 評価の設定」で比べ方を決めてください。'], summary.nUnits);
            app.Controls.mappingStatus.FontColor = app.Palette.text;
            drawPreview(app);
            drawLayout(app);
            app.Controls.shotOverlayWafers.Items = cellstr(labels);
            app.Controls.shotOverlayWafers.ItemsData = num2cell(1:numel(labels));
            app.Controls.shotOverlayWafers.Value = num2cell(1:numel(labels));
            % Scan 方向があれば、はじめは Scan 方向で分けた図も並べる
            app.Controls.shotOverlayByScan.Value = any(arrayfun(@(unit) any(~isnan(unit.marks.direction)), app.Data.units));
            drawShotOverlay(app);
            % 質的変数の交互作用：Wafer はすべて、その他の列は質的変数に選んである列。読み込んだら一度調べる
            app.Controls.interactionWafers.Items = cellstr(labels);
            app.Controls.interactionWafers.ItemsData = num2cell(1:numel(labels));
            app.Controls.interactionWafers.Value = num2cell(1:numel(labels));
            attributeNames = string(app.Data.attributeNames);
            app.Controls.interactionColumns.Items = cellstr(attributeNames);
            app.Controls.interactionColumns.Value = cellstr(intersect(attributeNames, ...
                alignest.factorColumnsUsed(app.Settings), 'stable'));
            app.Controls.interactionRun.Enable = 'on';
            try
                analyzeFactorInteractions(app);
            catch err
                app.Interactions = [];
                app.Controls.interactionAdvice.Value = {['⚠ 調べられませんでした：' err.message]};
            end
            refreshFactorColumns(app);
            validateSettings(app);
            refreshRunSummary(app);
            refreshTargetChoices(app);
        end

        function overlay = drawShotOverlay(app, unitIndex, byScan)
            %DRAWSHOTOVERLAY 選んだ Wafer（unitIndex、省略時は画面の選択）のすべての Shot を Shot 内の座標で重ね合わせ、
            %   個々の Shot の矢印・Mark の位置ごとの平均・共分散楕円を「Shot 重ね合わせ」に描く。
            %   byScan（省略時は画面の選択）が true なら、Scan 方向ごとに重ねた図も右に並べる。
            %   overlay は描いた図ごとの alignest.shotOverlay の結果（1つ目がすべての Shot）。
            c = app.Controls;
            overlay = [];
            if isempty(app.Data)
                return
            end
            if alignest.valueSpec(app.Settings.data).scalar
                showOverlayPanels(app, 0);
                c.shotOverlayInfo.Value = {'Shot 重ね合わせは X・Y のベクトル場の図なので、1変数の推定では使いません。'};
                return
            end
            if nargin >= 2
                c.shotOverlayWafers.Value = num2cell(unitIndex);
            end
            if nargin >= 3
                c.shotOverlayByScan.Value = byScan;
            end
            selected = cell2mat(c.shotOverlayWafers.Value);
            if isempty(selected)
                showOverlayPanels(app, 0);
                c.shotOverlayInfo.Value = {'Wafer を1枚以上選んでください。'};
                return
            end
            % 図ごとの Scan 方向（NaN = すべて）。選んだ Wafer に Scan 方向が無ければ分けない
            directions = NaN;
            notes = strings(0, 1);
            if c.shotOverlayByScan.Value
                marks = [app.Data.units(selected).marks];
                levels = unique(vertcat(marks.direction));
                levels = levels(~isnan(levels)).';
                if isempty(levels)
                    notes(end + 1) = "選んだ Wafer に Scan 方向が無いため、Scan 方向で分けた図は描きません。";
                end
                directions = [NaN, levels(1:min(end, numel(c.shotOverlayAxes) - 1))];
            end
            showOverlayPanels(app, numel(directions));
            order = c.shotOverlayWaferOrder.Value;
            orderText = ternary(order > 0, sprintf("Wafer 成分 %d次を除く", order), "");
            scale = c.shotOverlayScale.Value;
            lines = strings(0, 1);
            for k = 1:numel(directions)
                part = alignest.shotOverlay(app.Data.units, selected, order, app.Settings.data.waferRadiusMm, ...
                    directions(k));
                if numel(directions) == 1
                    titleText = sprintf("Wafer %d 枚・%d Shot を重ね合わせ%s", part.nWafers, part.nShots, ...
                        ternary(order > 0, "、" + orderText, ""));
                    heading = "Mark の位置ごと（Shot 内の座標 [mm]）。σ と相関は Shot・Wafer 間。楕円の色は相関の絶対値 |r|。";
                elseif isnan(directions(k))
                    titleText = sprintf("すべての Shot（Wafer %d 枚・%d Shot）", part.nWafers, part.nShots);
                    heading = "【すべての Shot】Mark の位置ごと（Shot 内の座標 [mm]）。σ と相関は Shot・Wafer 間。" + ...
                        "楕円の色は相関の絶対値 |r|。";
                else
                    titleText = sprintf("Scan 方向 %g（%d Shot）", directions(k), part.nShots);
                    heading = sprintf("【Scan 方向 %g】", directions(k));
                end
                if numel(directions) > 1 && order > 0
                    titleText = titleText + newline + orderText;
                end
                % 並べる図は、1つ目（すべての Shot）と同じ矢印の倍率・色の範囲で描く
                if k == 1
                    values = vertcat(part.values{:});
                    magnitudeLimit = max([0; hypot(values(:, 1), values(:, 2))], [], 'omitnan');
                end
                scale = alignest.plot.shotOverlayMap(c.shotOverlayAxes(k), part, scaleMmPerNm=scale, ...
                    ellipseSigma=c.shotOverlayEllipse.Value, showIndividual=c.shotOverlayIndividual.Value, ...
                    titleText=titleText, magnitudeLimit=magnitudeLimit, ...
                    showArrows=~(c.shotOverlayEllipseOnly.Value && c.shotOverlayEllipse.Value > 0));
                c.shotOverlayAxes(k).Visible = 'on';
                styleAxes(app, c.shotOverlayAxes(k), app.AXES_FONT_SIZE);
                lines = [lines; heading; overlayLines(part)]; %#ok<AGROW>
                overlay = [overlay, part]; %#ok<AGROW>
            end
            c.shotOverlayInfo.Value = cellstr([notes; lines]);
        end

        function setScanDirection(app, shotNos, directions)
            %SETSCANDIRECTION shotNo の Scan 方向を directions（1・2。shotNos と同じ数、または1つ）に変える。
            %   すべての Wafer の同じ shotNo に当て、前処理をやり直す（評価の結果は消える）。shotNos が空なら変更をすべて戻す。
            %   変えた Scan 方向は設定（data.directionOverrideShots・directionOverrideValues）に残る。
            if isempty(app.RawTable) || width(app.RawTable) == 0
                error('alignest:noFile', '先に「ファイルを選ぶ…」で計測データを読み込んでください。');
            end
            shots = app.Settings.data.directionOverrideShots;
            values = app.Settings.data.directionOverrideValues;
            if isempty(shotNos)
                shots = zeros(1, 0);
                values = zeros(1, 0);
            else
                shotNos = reshape(double(shotNos), 1, []);
                directions = reshape(double(directions), 1, []);
                if isscalar(directions)
                    directions = repmat(directions, size(shotNos));
                end
                if numel(directions) ~= numel(shotNos) || any(~ismember(directions, [1, 2]))
                    error('alignest:directionOverride', 'Scan 方向は 1 か 2 を、shotNo と同じ数だけ指定してください。');
                end
                keep = ~ismember(shots, shotNos);
                shots = [shots(keep), shotNos];
                values = [values(keep), directions];
            end
            app.Settings.data.directionOverrideShots = shots;
            app.Settings.data.directionOverrideValues = values;
            shownWafer = app.Controls.layoutWafer.Value;
            selectedTab = app.Controls.dataTabs.SelectedTab;
            applyMapping(app);
            if isnumeric(shownWafer) && shownWafer <= numel(app.Data.units)
                app.Controls.layoutWafer.Value = shownWafer;
                drawLayout(app);
            end
            app.Controls.dataTabs.SelectedTab = selectedTab;
        end

        function onLayoutClicked(app, event)
            % Shot レイアウトの図のクリック：左クリックだけ Scan 方向を入れ替える（右クリックは凡例の位置のメニュー）
            if event.Button == 1
                onLayoutShotClicked(app, event.IntersectionPoint);
            end
        end

        function onLayoutShotClicked(app, point)
            %ONLAYOUTSHOTCLICKED Shot レイアウトの point [x, y]（mm）の Shot の Scan 方向を 1 ↔ 2 で入れ替える
            %   （方向が無ければ 1 にする。すべての Wafer の同じ shotNo。図のクリックから呼ぶ）。
            if isempty(app.Data)
                return
            end
            unit = app.Data.units(app.Controls.layoutWafer.Value);
            half = unit.shotSizeMm / 2;
            inside = find(abs(unit.shots.Xmm - point(1)) <= half(1) & abs(unit.shots.Ymm - point(2)) <= half(2), 1);
            if isempty(inside)
                return
            end
            current = unit.shots.direction(inside);
            next = 1;
            if current == 1
                next = 2;
            end
            runWithAlert(app, @() app.setScanDirection(unit.shots.shotNo(inside), next), ...
                "Scan 方向を変えられませんでした", "「1. データの読み込み」の設定を確かめてください。");
        end

        function changed = suggestCoordinateUnits(app)
            %SUGGESTCOORDINATEUNITS ファイルの値の大きさから、座標の列ごとの入力単位を推定して選ぶ（目安の外の列だけ）。
            checks = alignest.checkCoordinateUnits(app.RawTable, currentMapping(app), app.Settings.data.coordinateUnits);
            change = ~checks.ok & checks.suggested ~= "";
            units = app.Settings.data.coordinateUnits;
            for k = find(change).'
                units.(checks.name(k)) = checks.suggested(k);
            end
            changed = checks.name(change);
            app.Settings.data.coordinateUnits = alignest.coordinateUnits(units);
            fillUnitTable(app);
            status = app.Controls.unitStatus;
            if any(change)
                invalidatePreparedData(app);
                parts = checks.name(change) + "：" + displayUnit(checks.unit(change)) + " → " + ...
                    displayUnit(checks.suggested(change));
                status.Text = "値の大きさから単位を選びました（" + strjoin(parts, "、") + "）。「この対応で読み込む」を押してください。";
                status.FontColor = app.Palette.text;
            elseif all(checks.ok)
                status.Text = "すべての座標の大きさが目安の範囲内なので、単位は変えていません。";
                status.FontColor = app.Palette.text;
            else
                status.Text = "⚠ 目安に合う単位が見つからない列があります。列の対応が正しいか確かめてください。";
                status.FontColor = app.Palette.error;
            end
        end

        function analysis = analyzeFactorInteractions(app, unitIndex, trendOrder, columns)
            %ANALYZEFACTORINTERACTIONS 「1. データの読み込み」の「質的変数の交互作用」：読み込んだ計測値で、質的変数
            %   （Scan 方向・Mark 番号・Shot 行の奇偶・選んだその他の列）の主効果と2つずつの交互作用を調べ、表・図と、
            %   説明変数・カーネルの選び方の目安を出す（alignest.factorInteractions）。引数を省くと画面の選択。
            %   unitIndex：Wafer の番号、trendOrder：Wafer ごとに除く面内の傾向（XY 多項式の次数）、columns：その他の列。
            if isempty(app.Data)
                error('alignest:noData', '先に「この対応で読み込む」でデータを読み込んでください。');
            end
            c = app.Controls;
            if nargin >= 2
                c.interactionWafers.Value = num2cell(reshape(unitIndex, 1, []));
            end
            if nargin >= 3
                c.interactionTrendOrder.Value = trendOrder;
            end
            if nargin >= 4
                c.interactionColumns.Value = cellstr(string(columns));
            end
            selected = cell2mat(c.interactionWafers.Value);
            if isempty(selected)
                error('alignest:interactionWafers', 'Wafer を1枚以上選んでください。');
            end
            analysis = alignest.factorInteractions(app.Data, unitIndex=selected, trendOrder=c.interactionTrendOrder.Value, ...
                columns=string(c.interactionColumns.Value), waferRadiusMm=app.Settings.data.waferRadiusMm);
            app.Interactions = analysis;
            spec = alignest.valueSpec(app.Settings.data);
            main = analysis.main;
            rows = cell(height(main), 8);
            for k = 1:height(main)
                r = main(k, :);
                rows(k, :) = {char(axisLabel(spec, r.axis)), char(r.factor), sprintf('%d', r.nLevels), numberText(r.F, '%.2f'), ...
                    pValueText(r.p), numberText(r.etaSquared, '%.3f'), char(r.verdict), char(r.levelSummary)};
            end
            c.interactionMainTable.Data = rows;
            tests = analysis.tests;
            rows = cell(height(tests), 9);
            for k = 1:height(tests)
                r = tests(k, :);
                verdict = r.verdict;
                if r.note ~= ""
                    verdict = verdict + "：" + r.note;
                end
                rows(k, :) = {char(axisLabel(spec, r.axis)), char(r.factorA + " × " + r.factorB), sprintf('%d', r.n), ...
                    pValueText(r.pA), pValueText(r.pB), numberText(r.F, '%.2f'), pValueText(r.p), ...
                    numberText(r.partialEta2, '%.3f'), char(verdict)};
            end
            c.interactionTable.Data = rows;
            removeStyle(c.interactionTable);
            interacting = find(tests.verdict == "交互作用あり");
            if ~isempty(interacting)
                addStyle(c.interactionTable, uistyle('BackgroundColor', app.Palette.warning), 'row', interacting);
            end
            % 図にする組：交互作用ありの組を先にする
            pairs = unique(tests.factorA + " × " + tests.factorB, 'stable');
            if ~isempty(interacting)
                first = tests.factorA(interacting(1)) + " × " + tests.factorB(interacting(1));
                pairs = [first; pairs(pairs ~= first)];
            end
            if isempty(pairs)
                setChoices(c.interactionPair, "—（質的変数が2つ以上ありません）", {''});
            else
                setChoices(c.interactionPair, pairs, cellstr(pairs));
                c.interactionPair.Value = char(pairs(1));
            end
            setChoices(c.interactionAxis, axisLabel(spec, analysis.axes), cellstr(analysis.axes));
            set([c.interactionPair, c.interactionAxis], 'Enable', onOff(~isempty(pairs)));
            c.interactionAdvice.Value = cellstr(analysis.advice);
            c.interactionAdvice.FontColor = ternary(isempty(interacting), app.Palette.text, app.Palette.error);
            drawInteractionPlot(app);
        end
    end

    methods (Access = {?appui.Core})
        % ================= 1. データの読み込み =================
        function buildDataTab(app)
            grid = uigridlayout(app.Tabs.data, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 12, 'RowSpacing', 12);
            filePanel = uipanel(grid, 'Title', '計測データのファイル');
            fileGrid = uigridlayout(filePanel, [6, 4], 'ColumnWidth', {'fit', '1x', 260, 300}, ...
                'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit', 'fit'}, 'Padding', 10);
            help = uilabel(fileGrid, 'WordWrap', 'on', 'Text', ['Excel（.xlsx）または CSV。1行目に項目名、2行目からデータ。' ...
                '項目名がアライメント計測テーブルの標準（Operation, EqpId, LotID, Wafer, DateTime, shotNo, Direction, Xmm, Ymm, ' ...
                'Radius, markNo, markXmm, markYmm, measX, measY, StsX, StsY）なら自動で対応づけます。']);
            help.Layout.Row = 1;
            help.Layout.Column = [1, 4];
            label(fileGrid, 'ファイル', 2, [1, 2]);
            label(fileGrid, 'シート', 2, 3);
            label(fileGrid, '有効半径 [mm]（この半径以上の点は除く）', 2, 4);
            c.chooseFile = uibutton(fileGrid, 'Text', 'ファイルを選ぶ…', 'ButtonPushedFcn', @(~, ~) app.onChooseFile());
            c.chooseFile.Layout.Row = 3;
            c.chooseFile.Layout.Column = 1;
            c.filePath = uilabel(fileGrid, 'Text', 'まだ選んでいません', 'Tooltip', '');
            c.filePath.Layout.Row = 3;
            c.filePath.Layout.Column = 2;
            c.sheet = uidropdown(fileGrid, 'Items', {'—'}, 'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.onSheetChanged());
            c.sheet.Layout.Row = 3;
            c.sheet.Layout.Column = 3;
            c.validRadius = uieditfield(fileGrid, 'numeric', 'Value', app.Settings.data.validRadiusMm, 'Limits', [1, 1000], ...
                'ValueDisplayFormat', '%.1f', 'ValueChangedFcn', @(~, ~) app.invalidatePreparedData());
            c.validRadius.Layout.Row = 3;
            c.validRadius.Layout.Column = 4;
            onDataOption = @(~, ~) app.onDataOptionsChanged();
            c.excludeZeroMeasurements = uicheckbox(fileGrid, 'Text', '測定値 X・Y が両方 0 の行を除外', ...
                'Tooltip', 'measX = 0 かつ measY = 0 の入力行を、重複の平均前に除外します。', 'ValueChangedFcn', onDataOption);
            place(c.excludeZeroMeasurements, 4, [1, 2]);
            c.excludeUnmeasuredRecords = uicheckbox(fileGrid, 'Text', 'StsX または StsY が −1 の行を除外', ...
                'Tooltip', 'どちらかが−1なら行全体を除外します。オフの場合も、無効な軸の測定値は解析に使いません。', ...
                'ValueChangedFcn', onDataOption);
            place(c.excludeUnmeasuredRecords, 4, [3, 4]);
            label(fileGrid, 'Scan 方向（Direction）が無い行に付ける値', 5, 1);
            [ruleNames, ruleLabels] = alignest.directionRules();
            c.directionRule = uidropdown(fileGrid, 'Items', cellstr(ruleLabels), 'ItemsData', cellstr(ruleNames), ...
                'Tooltip', ['Direction の列が無いとき（または空の行）に、規則で Scan 方向 1・2 を付けます。' ...
                '行・列は Wafer ごとに Shot 中心の座標から数えます。付けた結果は「Shot レイアウト」で確かめられます。'], ...
                'ValueChangedFcn', onDataOption);
            place(c.directionRule, 5, 2);
            c.invertDirection = uicheckbox(fileGrid, 'Text', '付ける 1 と 2 を入れ替える', 'ValueChangedFcn', onDataOption);
            place(c.invertDirection, 5, 3);
            directionHelp = label(fileGrid, 'Direction の列に値がある行はそのまま使います。', 5, 4);
            directionHelp.FontColor = app.Palette.muted;
            % 座標の定義（Shot 中心＋Shot 内の位置、または絶対座標だけ）と、推定する値（X・Y 成分、または1つの列）
            label(fileGrid, '座標の定義', 6, 1);
            c.coordinateMode = uidropdown(fileGrid, 'Items', {'Shot 中心＋Shot 内の位置（Xmm・Ymm ＋ markXmm・markYmm）', ...
                'Wafer 上の絶対座標だけ（Xmm・Ymm が点の座標）'}, 'ItemsData', {'shotMark', 'absolute'}, ...
                'ValueChangedFcn', onDataOption, 'Tooltip', ['絶対座標だけ：Xmm・Ymm の項目に点の Wafer 上の座標の列を' ...
                '対応づけます。shotNo があれば同じ Shot の点の平均を Shot 中心に、markXmm・markYmm があれば' ...
                '点の座標 − markXmm を Shot 中心にします。どちらも無ければ点を1つずつ Shot として扱います。']);
            place(c.coordinateMode, 6, 2);
            valueGrid = uigridlayout(fileGrid, [1, 4], 'ColumnWidth', {'fit', '1x', 'fit', 70}, 'Padding', 0);
            place(valueGrid, 6, [3, 4]);
            label(valueGrid, '推定する値', 1, 1);
            c.valueColumn = uidropdown(valueGrid, 'Items', {'X・Y 成分（measX・measY）'}, 'ItemsData', {''}, ...
                'ValueChangedFcn', onDataOption, 'Tooltip', ['膜厚・線幅など、ファイルの1つの列を1変数として推定するときは' ...
                'その列を選びます（measX・measY は使いません。Overlay 補正の評価と RT モデルは使えません）。']);
            place(c.valueColumn, 1, 2);
            label(valueGrid, '単位', 1, 3);
            c.valueUnit = uieditfield(valueGrid, 'text', 'Value', char(app.Settings.data.valueUnit), ...
                'ValueChangedFcn', @(~, ~) app.onValueUnitChanged(), 'Tooltip', '1変数の単位（画面と Excel の表示だけ。換算はしません）');
            place(c.valueUnit, 1, 4);

            c.dataTabs = uitabgroup(grid);
            c.mappingTab = uitab(c.dataTabs, 'Title', '列の対応・座標の単位');
            lower = uigridlayout(c.mappingTab, [1, 2], 'ColumnWidth', {'1x', '1.1x'}, 'Padding', 8, 'ColumnSpacing', 12);
            mappingPanel = uipanel(lower, 'Title', '列の対応（標準の項目 ← ファイルの列）');
            mappingGrid = uigridlayout(mappingPanel, [3, 1], 'RowHeight', {'1x', 'fit', 'fit'}, 'Padding', 10);
            c.mapping = uitable(mappingGrid, 'ColumnName', {'標準の項目', '意味（変換後）', '必須', 'ファイルの列'}, ...
                'ColumnEditable', [false, false, false, true], 'RowName', {}, 'ColumnWidth', {100, 'auto', 50, 150}, ...
                'CellEditCallback', @(~, event) app.onMappingEdited(event));
            c.mappingStatus = uilabel(mappingGrid, 'WordWrap', 'on', ...
                'Text', '「ファイルを選ぶ…」で計測データを読み込んでください。');
            c.applyMapping = primaryButton(app, mappingGrid, 'この対応で読み込む', @(~, ~) app.onApplyMapping());
            c.applyMapping.Enable = 'off';

            right = uigridlayout(lower, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 0, 'RowSpacing', 12);
            unitPanel = uipanel(right, 'Title', '座標の単位（読み込むときに mm に変換する）');
            unitGrid = uigridlayout(unitPanel, [4, 3], 'RowHeight', {'fit', 'fit', 150, 'fit'}, ...
                'ColumnWidth', {'fit', 170, '1x'}, 'Padding', 8, 'RowSpacing', 4);
            unitHelp = label(unitGrid, ['mm でない列は「入力の単位」を選び直します（列名が Xmm でも中身が µm なら µm）。' ...
                '測定値 measX・measY は nm のまま変換しません。'], 1, [1, 3]);
            unitHelp.FontColor = app.Palette.muted;
            label(unitGrid, 'まとめて選ぶ', 2, 1);
            c.unitAll = uidropdown(unitGrid, 'Items', {'（列ごとに選ぶ）', 'すべて mm', 'すべて µm', 'すべて nm', 'すべて m'}, ...
                'ItemsData', {'', 'mm', 'um', 'nm', 'm'}, 'Value', '', 'ValueChangedFcn', @(~, ~) app.onUnitAll());
            place(c.unitAll, 2, 2);
            c.suggestUnits = uibutton(unitGrid, 'Text', '値の大きさから単位を推定', ...
                'Tooltip', 'Shot 中心は 10〜300 mm、Mark は 0.05〜50 mm に入る単位を選びます（目安の外の列だけ変えます）。', ...
                'ButtonPushedFcn', @(~, ~) app.onSuggestUnits());
            place(c.suggestUnits, 2, 3);
            c.unitTable = uitable(unitGrid, 'ColumnName', {'項目', '入力の単位', 'mm への倍率', 'ファイルの最大値', ...
                '変換後 [mm]', '確認'}, 'ColumnEditable', [false, true, false, false, false, false], 'RowName', {}, ...
                'ColumnWidth', {85, 95, 100, 120, 100, 'auto'}, 'CellEditCallback', @(~, ~) app.onUnitEdited());
            place(c.unitTable, 3, [1, 3]);
            c.unitStatus = uilabel(unitGrid, 'WordWrap', 'on', 'Text', '');
            place(c.unitStatus, 4, [1, 3]);
            resultPanel = uipanel(right, 'Title', '読み込み結果');
            resultGrid = uigridlayout(resultPanel, [1, 1], 'Padding', 10);
            c.summary = uitextarea(resultGrid, 'Editable', 'off', 'Value', {''});

            c.previewTab = uitab(c.dataTabs, 'Title', 'Wafer マップ（計測値）');
            previewGrid = uigridlayout(c.previewTab, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 8, 'RowSpacing', 8);
            previewControls = uigridlayout(previewGrid, [3, 11], 'ColumnWidth', {'fit', 260, 'fit', 170, 'fit', 80, 60, ...
                'fit', 'fit', 90, '1x'}, 'RowHeight', {'fit', 'fit', 'fit'}, 'Padding', 0);
            label(previewControls, '表示する Wafer・平均', 1, 1);
            c.previewWafer = uidropdown(previewControls, 'Items', {'—'}, 'ValueChangedFcn', @(~, ~) app.drawPreview());
            place(c.previewWafer, 1, 2);
            label(previewControls, '平均・楕円の単位', 1, 3);
            c.previewGroupBy = uidropdown(previewControls, 'Items', {'ALL（全 Wafer）'}, 'ItemsData', {'all'}, ...
                'ValueChangedFcn', @(~, ~) app.onPreviewGroupByChanged(), 'Tooltip', ['平均の図と共分散楕円を、どの単位で' ...
                '求めるか。ALL は全 Wafer、LotID・EqpId・Operation・その他の列は値ごと（その他の列は、その値の Mark だけを使う）。' ...
                '選ぶと「表示する Wafer・平均」に平均の選択肢が出ます。']);
            place(c.previewGroupBy, 1, 4);
            label(previewControls, '色の点', 1, 5);
            c.previewMarkerSize = markerSizeSpinner(app, previewControls, @(~, ~) app.drawPreview());
            place(c.previewMarkerSize, 1, 6);
            c.previewMarkerShape = markerShapeDropdown(previewControls, @(~, ~) app.drawPreview());
            place(c.previewMarkerShape, 1, 7);
            c.previewShotFrames = uicheckbox(previewControls, 'Text', 'Shot の枠', 'Value', true, ...
                'ValueChangedFcn', @(~, ~) app.drawPreview());
            place(c.previewShotFrames, 1, 8);
            label(previewControls, '共分散楕円', 1, 9);
            c.previewEllipse = ellipseDropdown(previewControls, @(~, ~) app.drawPreview());
            place(c.previewEllipse, 1, 10);
            c.previewEllipseOnly = ellipseOnlyCheckbox(previewControls, @(~, ~) app.drawPreview());
            place(c.previewEllipseOnly, 1, 11);
            c.previewScanFrames = uicheckbox(previewControls, 'Text', 'Shot の枠を Scan 方向で色分け（▲ 上・▼ 下の印つき）', ...
                'ValueChangedFcn', @(~, ~) app.drawPreview());
            place(c.previewScanFrames, 2, [1, 2]);
            c.previewRings = uicheckbox(previewControls, 'Text', '同心円の区切り（「2. 評価の設定」の制約）を描く', ...
                'ValueChangedFcn', @(~, ~) app.drawPreview(), 'Tooltip', ['I 最適・ランダムで同心円の制約を使うとき、' ...
                '区切りの半径（Shot 中心の半径 [mm]）を橙の一点鎖線で描きます。']);
            place(c.previewRings, 2, [3, 7]);
            c.previewInfo = uilabel(previewControls, 'WordWrap', 'on', 'Text', '');
            place(c.previewInfo, 3, [1, 11]);
            c.previewPanel = uipanel(previewGrid, 'BorderType', 'none');
            c.previewAxesGrid = uigridlayout(c.previewPanel, [1, 3], 'Padding', 0, 'ColumnSpacing', 8);
            c.previewAxes = [uiaxes(c.previewAxesGrid), uiaxes(c.previewAxesGrid), uiaxes(c.previewAxesGrid)];
            set(c.previewAxes, 'Visible', 'off');  % 読み込むまでは空の枠を出さない

            c.layoutTab = uitab(c.dataTabs, 'Title', 'Shot レイアウト');
            layoutGrid = uigridlayout(c.layoutTab, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 8, 'RowSpacing', 8);
            layoutControls = uigridlayout(layoutGrid, [2, 3], 'ColumnWidth', {'fit', 260, '1x'}, 'RowHeight', {'fit', 'fit'}, ...
                'Padding', 0);
            label(layoutControls, '表示する Wafer', 1, 1);
            c.layoutWafer = uidropdown(layoutControls, 'Items', {'—'}, 'ValueChangedFcn', @(~, ~) app.drawLayout());
            place(c.layoutWafer, 1, 2);
            c.layoutInfo = uilabel(layoutControls, 'WordWrap', 'on', 'Text', '');
            place(c.layoutInfo, 1, 3);
            c.resetScanDirections = uibutton(layoutControls, 'Text', 'Scan 方向の変更を元に戻す', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onResetScanDirections());
            place(c.resetScanDirections, 2, [1, 2]);
            c.scanEditInfo = uilabel(layoutControls, 'WordWrap', 'on', 'Text', ...
                '左の図の Shot をクリックすると、その shotNo の Scan 方向を 1 ↔ 2 で入れ替えます（すべての Wafer の同じ shotNo）。');
            place(c.scanEditInfo, 2, 3);
            c.layoutPanel = uipanel(layoutGrid, 'BorderType', 'none');
            layoutAxesGrid = uigridlayout(c.layoutPanel, [1, 2], 'ColumnWidth', {'1.25x', '1x'}, 'Padding', 0, ...
                'ColumnSpacing', 12);
            c.layoutAxes = [uiaxes(layoutAxesGrid), uiaxes(layoutAxesGrid)];
            set(c.layoutAxes, 'Visible', 'off');

            c.shotOverlayTab = uitab(c.dataTabs, 'Title', 'Shot 重ね合わせ');
            overlayGrid = uigridlayout(c.shotOverlayTab, [1, 2], 'ColumnWidth', {320, '1x'}, 'Padding', 8, 'ColumnSpacing', 12);
            registerResponsiveColumn(app, overlayGrid, 1);
            overlayControls = uigridlayout(overlayGrid, [13, 1], 'RowHeight', {'fit', 110, 'fit', 'fit', 'fit', 'fit', ...
                'fit', 'fit', 'fit', 'fit', 'fit', '1x', 0}, 'Padding', 0, 'RowSpacing', 4);
            onOverlay = @(~, ~) app.drawShotOverlay();
            label(overlayControls, 'Wafer（Ctrl・Shift で複数選ぶ）', 1, 1);
            c.shotOverlayWafers = uilistbox(overlayControls, 'Items', {}, 'Multiselect', 'on', 'ValueChangedFcn', onOverlay);
            place(c.shotOverlayWafers, 2, 1);
            label(overlayControls, 'Wafer 成分を除く（Shot 中心の多項式）', 3, 1);
            c.shotOverlayWaferOrder = uidropdown(overlayControls, 'Items', {'除かない', '1次（並進・倍率・回転・直交度）', ...
                '2次', '3次'}, 'ItemsData', {0, 1, 2, 3}, 'ValueChangedFcn', onOverlay, ...
                'Tooltip', 'Wafer ごとに Shot 中心の座標の多項式を最小二乗で当てはめて除き、Shot 内の成分だけを重ねます。');
            place(c.shotOverlayWaferOrder, 4, 1);
            label(overlayControls, '共分散楕円（Shot・Wafer 間のばらつき。色は |相関係数|）', 5, 1);
            c.shotOverlayEllipse = ellipseDropdown(overlayControls, onOverlay);
            place(c.shotOverlayEllipse, 6, 1);
            c.shotOverlayIndividual = uicheckbox(overlayControls, 'Text', '個々の Shot の矢印も描く', 'Value', true, ...
                'ValueChangedFcn', onOverlay);
            place(c.shotOverlayIndividual, 7, 1);
            c.shotOverlayEllipseOnly = ellipseOnlyCheckbox(overlayControls, onOverlay);
            place(c.shotOverlayEllipseOnly, 8, 1);
            c.shotOverlayByScan = uicheckbox(overlayControls, 'Text', 'Scan 方向で分けた図も並べる', 'Value', false, ...
                'ValueChangedFcn', onOverlay, 'Tooltip', ['すべての Shot の図の右に、Scan 方向 1・2 の Shot だけを重ねた図を' ...
                '同じ矢印の倍率で並べます（Scan 方向はデータの Direction、または取り込みで付けた値）。']);
            place(c.shotOverlayByScan, 9, 1);
            label(overlayControls, '矢印の倍率 [mm/nm]（0 = 自動）', 10, 1);
            c.shotOverlayScale = uieditfield(overlayControls, 'numeric', 'Value', 0, 'Limits', [0, Inf], ...
                'ValueChangedFcn', onOverlay);
            place(c.shotOverlayScale, 11, 1);
            c.shotOverlayInfo = uitextarea(overlayControls, 'Editable', 'off', 'Value', {''});
            place(c.shotOverlayInfo, [12, 13], 1);
            % すべての Shot の図と、Scan 方向で分けた図（使わない列は幅 0）
            c.shotOverlayAxesGrid = uigridlayout(overlayGrid, [1, 3], 'ColumnWidth', {'1x', 0, 0}, 'Padding', 0, ...
                'ColumnSpacing', 8);
            c.shotOverlayAxes = [uiaxes(c.shotOverlayAxesGrid), uiaxes(c.shotOverlayAxesGrid), ...
                uiaxes(c.shotOverlayAxesGrid)];
            set(c.shotOverlayAxes, 'Visible', 'off');

            % 質的変数の交互作用：読み込んだ計測値（面内の傾向を除いた値）で、質的変数の効果と2つずつの交互作用を調べる
            c.interactionTab = uitab(c.dataTabs, 'Title', '質的変数の交互作用');
            % 左：条件と目安（縦に長いので、欄の中でスクロールできる）、中：主効果・交互作用の表、右：交互作用の図
            interactionGrid = uigridlayout(c.interactionTab, [1, 3], 'ColumnWidth', {300, '1.25x', '1x'}, 'Padding', 8, ...
                'ColumnSpacing', 10);
            registerResponsiveColumn(app, interactionGrid, 1);
            interactionControls = uigridlayout(interactionGrid, [14, 1], 'RowHeight', {'fit', 130, 'fit', 72, 'fit', 'fit', ...
                'fit', 52, 'fit', 'fit', 'fit', 'fit', 0, 0}, 'Padding', [0, 0, 6, 0], 'RowSpacing', 4, 'Scrollable', 'on');
            label(interactionControls, '説明変数・カーネルの選び方の目安', 1, 1);
            c.interactionAdvice = uitextarea(interactionControls, 'Editable', 'off', 'Value', ...
                {'データを読み込むと、質的変数の効果と交互作用を調べて、ここに目安を出します。'});
            place(c.interactionAdvice, 2, 1);
            label(interactionControls, 'Wafer（Ctrl・Shift で複数選ぶ）', 3, 1);
            c.interactionWafers = uilistbox(interactionControls, 'Items', {}, 'Multiselect', 'on');
            place(c.interactionWafers, 4, 1);
            label(interactionControls, '除く面内の傾向（Wafer ごとの XY 多項式の次数）', 5, 1);
            c.interactionTrendOrder = uidropdown(interactionControls, 'Items', {'0（平均だけ）', '1次', '2次', '3次', ...
                '4次', '5次'}, 'ItemsData', {0, 1, 2, 3, 4, 5}, 'Value', app.INTERACTION_TREND_ORDER, 'Tooltip', ...
                ['Wafer ごと・X・Y 別に、計測値から面内の傾向（Wafer 上の座標の多項式）を除いてから調べます' ...
                '（面内の形の違いを質的変数の効果と見誤らないため）。']);
            place(c.interactionTrendOrder, 6, 1);
            label(interactionControls, 'その他の列（質的変数として加える。Ctrl・Shift）', 7, 1);
            c.interactionColumns = uilistbox(interactionControls, 'Items', {}, 'Multiselect', 'on', 'Value', {});
            place(c.interactionColumns, 8, 1);
            c.interactionRun = uibutton(interactionControls, 'Text', '評価する', ...
                'ButtonPushedFcn', @(~, ~) app.onAnalyzeInteractions(), 'Tooltip', ['Scan 方向・Mark 番号・Shot 行の奇偶と、' ...
                '選んだその他の列の主効果と、2つずつの組の交互作用（二元配置の分散分析）を調べます。読み込むと一度調べます。']);
            place(c.interactionRun, 9, 1);
            label(interactionControls, '図にする組・軸', 10, 1);
            c.interactionPair = uidropdown(interactionControls, 'Items', {'—'}, 'ItemsData', {''}, ...
                'ValueChangedFcn', @(~, ~) app.drawInteractionPlot());
            place(c.interactionPair, 11, 1);
            c.interactionAxis = uidropdown(interactionControls, 'Items', {'X', 'Y'}, 'ItemsData', {'X', 'Y'}, ...
                'ValueChangedFcn', @(~, ~) app.drawInteractionPlot());
            place(c.interactionAxis, 12, 1);
            interactionResults = uigridlayout(interactionGrid, [2, 1], 'RowHeight', {'1x', '1.2x'}, 'Padding', 0, ...
                'RowSpacing', 6);
            c.interactionMainTable = uitable(interactionResults, 'RowName', {}, 'ColumnName', {'軸', '質的変数', ...
                '水準の数', 'F', 'p 値', 'η²', '判定（主効果）', '水準ごとの平均 [nm]（点数）'}, ...
                'ColumnWidth', {40, 150, 70, 80, 80, 70, 150, 'auto'});
            c.interactionTable = uitable(interactionResults, 'RowName', {}, 'ColumnName', {'軸', '組', '点数', ...
                '主効果 1つ目：p', '主効果 2つ目：p', '交互作用 F', 'p 値', '偏 η²', '判定（交互作用）・メモ'}, ...
                'ColumnWidth', {40, 230, 60, 110, 110, 90, 80, 70, 'auto'});
            c.interactionAxes = uiaxes(interactionGrid);
            c.interactionAxes.Visible = 'off';
            set([c.interactionRun, c.interactionPair, c.interactionAxis], 'Enable', 'off');
            app.Controls = mergeStruct(app.Controls, c);
        end

        function drawInteractionPlot(app)
            % 選んだ組・軸の交互作用の図（線がほぼ平行なら交互作用は小さい）
            c = app.Controls;
            analysis = app.Interactions;
            pair = string(c.interactionPair.Value);
            if isempty(analysis) || pair == ""
                cla(c.interactionAxes, 'reset');
                c.interactionAxes.Visible = 'off';
                return
            end
            names = split(pair, " × ");
            axisName = string(c.interactionAxis.Value);
            row = analysis.tests(analysis.tests.axis == axisName & analysis.tests.factorA == names(1) & ...
                analysis.tests.factorB == names(2), :);
            spec = alignest.valueSpec(app.Settings.data);
            titleText = axisLabel(spec, axisName) + "：" + pair;
            if height(row) > 0 && isfinite(row.p(1))
                % 2行にする（図の幅が狭いので、1行だと題名が切れる）
                titleText = titleText + newline + sprintf("交互作用 F = %.2f、p = %s、偏 η² = %.3f", row.F(1), ...
                    pValueText(row.p(1)), row.partialEta2(1));
            end
            cells = analysis.cells(analysis.cells.axis == axisName, :);
            alignest.plot.interactionPlot(c.interactionAxes, cells, names(1), names(2), titleText, spec.unit);
            c.interactionAxes.Visible = 'on';
            styleAxes(app, c.interactionAxes, app.AXES_FONT_SIZE);
        end

        function onAnalyzeInteractions(app)
            runWithAlert(app, @() app.analyzeFactorInteractions(), "質的変数の交互作用を調べられませんでした", ...
                "Wafer を1枚以上選び、傾向の次数を下げてもう一度試してください。");
        end

        function onChooseFile(app)
            [fileName, folder] = uigetfile({'*.xlsx;*.xlsm;*.xls;*.csv', '計測データ (*.xlsx, *.xlsm, *.xls, *.csv)'}, ...
                '計測データのファイルを選ぶ');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.loadFile(fullfile(folder, fileName)), "ファイルを読み込めませんでした", ...
                "ファイルが Excel で開かれていないか、1行目が項目名になっているかを確かめてください。");
        end

        function onSheetChanged(app)
            runWithAlert(app, @() app.loadFile(app.FilePath, string(app.Controls.sheet.Value)), ...
                "シートを読み込めませんでした", "別のシートを選ぶか、ファイルの中身を確かめてください。");
        end

        function onApplyMapping(app)
            ok = runWithAlert(app, @() app.applyMapping(), "データを整理できませんでした", ...
                "「ファイルの列」と「座標の入力単位」を選び直してから、もう一度「この対応で読み込む」を押してください。");
            if ~ok
                app.Controls.mappingStatus.Text = "⚠ 読み込めませんでした。列の対応を確かめてください。";
                app.Controls.mappingStatus.FontColor = app.Palette.error;
            end
        end

        function fillMappingTable(app, mapping)
            % 必須・任意と項目の意味は、座標の定義と推定する値で変わる（alignest.standardColumns）
            columns = alignest.standardColumns(string(fieldOr(app.Settings.data, "coordinateMode", "shotMark")), ...
                string(fieldOr(app.Settings.data, "valueColumn", "")));
            options = [app.NONE_LABEL, string(app.RawTable.Properties.VariableNames)];
            data = cell(numel(columns), 4);
            for k = 1:numel(columns)
                data{k, 1} = columns(k).name;
                data{k, 2} = columns(k).meaning;
                data{k, 3} = char(ternary(columns(k).required, "必須", "任意"));
                value = mapping.(columns(k).name);
                if value == ""
                    value = app.NONE_LABEL;
                end
                data{k, 4} = char(value);
            end
            app.Controls.mapping.Data = data;
            app.Controls.mapping.ColumnFormat = {'char', 'char', 'char', cellstr(options)};
        end

        function fillUnitTable(app)
            % 座標の列ごとの入力単位・倍率・ファイルの値の大きさと、mm に直した値が目安に入るかを表に出す
            checks = alignest.checkCoordinateUnits(app.RawTable, currentMapping(app), app.Settings.data.coordinateUnits);
            data = cell(height(checks), 6);
            for k = 1:height(checks)
                data{k, 1} = char(checks.name(k));
                data{k, 2} = char(displayUnit(checks.unit(k)));
                data{k, 3} = sprintf('× %g', checks.scale(k));
                data{k, 4} = numberText(checks.maxInput(k));
                data{k, 5} = numberText(checks.maxMm(k));
                data{k, 6} = char(checks.message(k));
            end
            unitTable = app.Controls.unitTable;
            unitTable.Data = data;
            unitTable.ColumnFormat = {'char', app.UNIT_CHOICES, 'char', 'char', 'char', 'char'};
            removeStyle(unitTable);
            warnings = find(~checks.ok);
            status = app.Controls.unitStatus;
            if isempty(warnings)
                status.Text = "読み込むときに、選んだ単位から mm に変換します（ファイルは変更しません）。";
                status.FontColor = app.Palette.text;
            else
                addStyle(unitTable, uistyle('FontColor', app.Palette.error, 'FontWeight', 'bold'), 'cell', ...
                    [warnings, repmat(6, numel(warnings), 1)]);
                status.Text = "⚠ 大きさが目安の外の列があります。入力の単位を確かめてください（「値の大きさから単位を推定」で選べます）。";
                status.FontColor = app.Palette.error;
            end
        end

        function units = currentCoordinateUnits(app)
            units = app.Settings.data.coordinateUnits;
            values = app.Controls.unitTable.Data;
            for k = 1:size(values, 1)
                units.(values{k, 1}) = string(values{k, 2});
            end
            units = alignest.coordinateUnits(units);
        end

        function options = currentDataOptions(app)
            % 前処理を決める画面の値（変わったら読み込み直す）
            c = app.Controls;
            options = dataOptions(struct("validRadiusMm", c.validRadius.Value, "coordinateUnits", currentCoordinateUnits(app), ...
                "excludeZeroMeasurements", c.excludeZeroMeasurements.Value, ...
                "excludeUnmeasuredRecords", c.excludeUnmeasuredRecords.Value, ...
                "directionRule", string(c.directionRule.Value), "invertDirection", c.invertDirection.Value, ...
                "directionOverrideShots", app.Settings.data.directionOverrideShots, ...
                "directionOverrideValues", app.Settings.data.directionOverrideValues, ...
                "coordinateMode", string(c.coordinateMode.Value), "valueColumn", string(c.valueColumn.Value)));
        end

        function onMappingEdited(app, ~)
            fillUnitTable(app);  % 対応づける列が変わると、単位の確認に使う値も変わる
            invalidatePreparedData(app);
        end

        function onUnitEdited(app)
            app.Settings.data.coordinateUnits = currentCoordinateUnits(app);
            fillUnitTable(app);
            invalidatePreparedData(app);
        end

        function onUnitAll(app)
            unit = string(app.Controls.unitAll.Value);
            if unit == ""
                return
            end
            units = app.Settings.data.coordinateUnits;
            for name = string(fieldnames(units)).'
                units.(name) = unit;
            end
            app.Settings.data.coordinateUnits = alignest.coordinateUnits(units);
            app.Controls.unitAll.Value = '';  % 選んだ後は「列ごとに選ぶ」に戻す（個別に変えられるように）
            fillUnitTable(app);
            invalidatePreparedData(app);
        end

        function onSuggestUnits(app)
            runWithAlert(app, @() app.suggestCoordinateUnits(), "単位を推定できませんでした", ...
                "先にファイルを選び、列の対応を確かめてください。");
        end

        function invalidatePreparedData(app)
            app.Data = [];
            clearResults(app);
            clearTargetRun(app);
            app.Controls.summary.Value = {''};
            clearDataMaps(app);
            refreshFactorColumns(app);
            validateSettings(app);
            if ~isempty(app.RawTable)
                app.Controls.mappingStatus.Text = ['列の対応・座標の単位・有効半径・行の除外条件・Scan 方向の付与を確認し、' ...
                    '「この対応で読み込む」を押してください。'];
            end
            refreshRunSummary(app);
        end

        function onDataOptionsChanged(app)
            c = app.Controls;
            app.Settings.data.excludeZeroMeasurements = c.excludeZeroMeasurements.Value;
            app.Settings.data.excludeUnmeasuredRecords = c.excludeUnmeasuredRecords.Value;
            app.Settings.data.directionRule = string(c.directionRule.Value);
            app.Settings.data.invertDirection = c.invertDirection.Value;
            c.invertDirection.Enable = onOff(app.Settings.data.directionRule ~= "none");
            app.Settings.data.coordinateMode = string(c.coordinateMode.Value);
            app.Settings.data.valueColumn = string(c.valueColumn.Value);
            c.valueUnit.Enable = onOff(app.Settings.data.valueColumn ~= "");
            if ~isempty(app.RawTable) && width(app.RawTable) > 0
                fillMappingTable(app, currentMapping(app));   % 座標の定義・推定する値で必須の項目が変わる
            end
            invalidatePreparedData(app);
            updateEnabled(app);
        end

        function onValueUnitChanged(app)
            % 1変数の単位（表示だけ）。読み込み直す必要はないので、計測値の図だけ描き直す
            app.Settings.data.valueUnit = string(strtrim(app.Controls.valueUnit.Value));
            if ~isempty(app.Data)
                drawPreview(app);
            end
        end

        function refreshValueColumns(app)
            % 「推定する値」の選択肢：X・Y 成分と、ファイルの列（設定で選んである列がファイルに無くても残す）
            c = app.Controls;
            columns = strings(1, 0);
            if ~isempty(app.RawTable)
                columns = string(app.RawTable.Properties.VariableNames);
            end
            selected = string(fieldOr(app.Settings.data, "valueColumn", ""));
            if selected ~= "" && ~any(columns == selected)
                columns(end + 1) = selected;
            end
            c.valueColumn.Items = cellstr(["X・Y 成分（measX・measY）", "1変数：" + columns]);
            c.valueColumn.ItemsData = cellstr(["", columns]);
            c.valueColumn.Value = char(selected);
            c.valueUnit.Enable = onOff(selected ~= "");
        end

        function mapping = currentMapping(app)
            data = app.Controls.mapping.Data;
            mapping = struct();
            for k = 1:size(data, 1)
                value = string(data{k, 4});
                if value == app.NONE_LABEL
                    value = "";
                end
                mapping.(data{k, 1}) = value;
            end
        end

        function drawPreview(app)
            % 読み込んだ計測値：ベクトル（矢印）と、X・Y 成分ごとのヒートマップ（色）を並べる
            c = app.Controls;
            if isempty(app.Data)
                clearDataMaps(app);
                return
            end
            option = c.previewWafer.UserData(c.previewWafer.Value);
            pointsList = cell(1, numel(option.unitIndex));
            valuesList = cell(1, numel(option.unitIndex));
            for k = 1:numel(option.unitIndex)
                unit = app.Data.units(option.unitIndex(k));
                marks = unit.marks;
                values = [marks.measX, marks.measY];
                values(~marks.validX, 1) = NaN;
                values(~marks.validY, 2) = NaN;
                selected = true(size(marks.x));
                if option.column ~= ""
                    % その他の列の値ごとの平均：その値の Mark だけを使う
                    selected = marks.attributes(:, string(unit.attributeNames) == option.column) == option.level;
                end
                pointsList{k} = [marks.x(selected), marks.y(selected)];
                valuesList{k} = values(selected, :);
            end
            unit = app.Data.units(option.unitIndex(1));
            covariance = zeros(0, 3);
            if option.isGroup
                average = alignest.averageFields(pointsList, valuesList);
                points = average.points;
                values = average.mean;
                covariance = average.covariance;
            else
                points = pointsList{1};
                values = valuesList{1};
            end
            [centers, sizeMm] = shotFrameData(unit, c.previewShotFrames.Value || c.previewScanFrames.Value);
            directions = zeros(0, 1);
            if c.previewScanFrames.Value
                directions = nan(numel(unit.shots.Xmm), 1);
                if unit.hasDirection
                    directions = unit.shots.direction;
                end
            end
            rings = zeros(1, 0);
            if c.previewRings.Value
                rings = activeZoneEdges(app.Settings);
            end
            limit = colorLimitOf(values);
            radius = app.Settings.data.waferRadiusMm;
            ellipseSigma = c.previewEllipse.Value * option.isGroup;
            common = {'waferRadiusMm', radius, 'shotCenters', centers, 'shotSizeMm', sizeMm, 'showLegend', option.isGroup, ...
                'covariance', covariance, 'ellipseSigma', ellipseSigma, 'shotDirections', directions, 'ringRadiiMm', rings, ...
                'scanStyle', scanStyle(app)};
            spec = alignest.valueSpec(app.Settings.data);
            if spec.scalar
                % 1変数：値の色の図を1枚（色の範囲は値の最小〜最大）。X・Y のベクトル・楕円は描かない
                c.previewAxesGrid.ColumnWidth = {'1x', 0, 0};
                common{find(strcmp(common, 'ellipseSigma')) + 1} = 0;
                alignest.plot.waferMap(c.previewAxes(1), points, values, common{:}, mode="X", ...
                    colorRange=valueRange(values(:, 1)), colorTitle=spec.name + " [" + spec.unit + "]", ...
                    markerSize=c.previewMarkerSize.Value, markerShape=c.previewMarkerShape.Value, ...
                    titleText=ternary(option.isGroup, spec.name + " の平均", spec.name));
                set(c.previewAxes(1), 'Visible', 'on');
                styleAxes(app, c.previewAxes(1), app.AXES_FONT_SIZE);
                arrayfun(@(ax) cla(ax, 'reset'), c.previewAxes(2:3));
                set(c.previewAxes(2:3), 'Visible', 'off');
                c.previewInfo.Text = sprintf('%s（1変数）を色で描いています（単位 %s）。', spec.name, spec.unit);
                return
            end
            c.previewAxesGrid.ColumnWidth = {'1x', '1x', '1x'};
            % name=value の書き方は最後に置く決まりなので、共通の指定（common）を先に渡す
            alignest.plot.waferMap(c.previewAxes(1), points, values, common{:}, ...
                scaleMmPerNm=alignest.plot.vectorScale(values), titleText=ternary(option.isGroup, "計測値の平均（ベクトル）", ...
                "計測値（ベクトル）"), showArrows=~(c.previewEllipseOnly.Value && ellipseSigma > 0));
            alignest.plot.waferMap(c.previewAxes(2), points, values, common{:}, mode="X", colorLimit=limit, ...
                markerSize=c.previewMarkerSize.Value, markerShape=c.previewMarkerShape.Value, titleText="X 成分（色）");
            alignest.plot.waferMap(c.previewAxes(3), points, values, common{:}, mode="Y", colorLimit=limit, ...
                markerSize=c.previewMarkerSize.Value, markerShape=c.previewMarkerShape.Value, titleText="Y 成分（色）");
            set(c.previewAxes, 'Visible', 'on');
            styleAxes(app, c.previewAxes, app.AXES_FONT_SIZE);
            % 楕円と重ねる矢印は単色（色の目盛りは楕円の |r|）、楕円が無ければ矢印の色は長さ
            arrowText = ternary(ellipseSigma > 0, "矢印は単色（右の目盛りは楕円の |r|）", "矢印の色は長さ |v|");
            extras = "";
            if ~isempty(directions)
                extras = extras + "枠の色は Scan 方向（" + scanLegendText(app) + "）。";
            end
            if ~isempty(rings)
                extras = extras + "橙の一点鎖線は同心円の区切り（" + strjoin(string(rings), "・") + " mm）。";
            elseif c.previewRings.Value
                extras = extras + "同心円の制約は使っていません（「2. 評価の設定」で I 最適・ランダムと区切りを選ぶと描きます）。";
            end
            c.previewInfo.Text = sprintf("%s：%d 点。点線は半径 %g mm%s。%s。色の図の範囲は X・Y 共通で ±%.2f nm。%s", option.label, ...
                size(points, 1), radius, ternary(c.previewShotFrames.Value, "、灰色の枠は Shot", ""), arrowText, limit, ...
                ternary(option.isGroup, "座標ごとに Wafer 間で平均（楕円は Wafer 間のばらつき、色は X・Y の相関係数の絶対値 |r|）。", "")) + ...
                extras;
        end

        function refreshPreviewGroupBy(app)
            % 平均・楕円の単位の選択肢（ALL・LotID・EqpId・Operation・その他の列）と、表示する Wafer・平均の選択肢
            c = app.Controls;
            columns = string(app.Data.attributeNames);
            keys = ["all", "lotId", "eqpId", "operation", "slotParity", "col:" + columns];
            labels = ["ALL（全 Wafer）", "LotID", "EqpId", "Operation", "Slot の偶奇（Wafer ID のハイフンの後の番号）", ...
                "その他の列：" + columns];
            previous = string(c.previewGroupBy.Value);
            c.previewGroupBy.Items = cellstr(labels);
            c.previewGroupBy.ItemsData = cellstr(keys);
            if any(keys == previous)
                c.previewGroupBy.Value = char(previous);
            end
            setGroupItems(c.previewWafer, alignest.groupOptions(app.Data.units, string(c.previewGroupBy.Value)));
        end

        function onPreviewGroupByChanged(app)
            % 単位を変えたら、その単位の最初の平均を表示する
            if isempty(app.Data)
                return
            end
            refreshPreviewGroupBy(app);
            c = app.Controls;
            firstGroup = find([c.previewWafer.UserData.isGroup], 1);
            if ~isempty(firstGroup)
                c.previewWafer.Value = firstGroup;
            end
            drawPreview(app);
        end

        function drawLayout(app)
            % Shot の配置（枠・shotNo・Scan 方向）と、Shot 内の Mark の位置・番号
            c = app.Controls;
            if isempty(app.Data)
                return
            end
            unit = app.Data.units(c.layoutWafer.Value);
            alignest.plot.shotLayout(c.layoutAxes(1), unit, app.Settings.data.waferRadiusMm, scanStyle(app));
            alignest.plot.markLayout(c.layoutAxes(2), unit);
            set(c.layoutAxes, 'Visible', 'on');
            styleAxes(app, c.layoutAxes, app.AXES_FONT_SIZE);
            % Shot をクリックして Scan 方向を入れ替える（図の中の線・文字はクリックを図に通す）
            ax = c.layoutAxes(1);
            disableDefaultInteractivity(ax);
            set(ax.Children, 'HitTest', 'off');
            ax.ButtonDownFcn = @(~, event) app.onLayoutClicked(event);
            changed = numel(app.Settings.data.directionOverrideShots);
            c.resetScanDirections.Enable = onOff(changed > 0);
            c.scanEditInfo.Text = "左の図の Shot をクリックすると、その shotNo の Scan 方向を 1 ↔ 2 で入れ替えます" + ...
                "（すべての Wafer の同じ shotNo）。" + ternary(changed > 0, sprintf("変えた Shot：%s", ...
                strjoin(compose("%g→S%d", app.Settings.data.directionOverrideShots(:), ...
                app.Settings.data.directionOverrideValues(:)), "、")), "");
            c.layoutInfo.Text = sprintf(['%s：%d Shot・%d Mark、Shot の大きさ %.3f × %.3f mm、Scan 方向 %s。' ...
                '左の数字は shotNo、右は Shot 中心から見た Mark の位置（M の後が markNo）。'], unit.label, ...
                numel(unit.shots.Xmm), numel(unit.marks.x), unit.shotSizeMm, ...
                ternary(unit.hasDirection, "あり（S1・S2 で表示）", "なし"));
        end

        function showOverlayPanels(app, count)
            % Shot 重ね合わせの図を count 枚だけ見せる（残りは消して幅 0 にする）
            c = app.Controls;
            widths = repmat({0}, 1, numel(c.shotOverlayAxes));
            widths(1:count) = {'1x'};
            if count == 0
                widths{1} = '1x';
            end
            c.shotOverlayAxesGrid.ColumnWidth = widths;
            for k = count + 1:numel(c.shotOverlayAxes)
                ax = c.shotOverlayAxes(k);
                cla(ax, 'reset');
                colorbar(ax, 'off');
                legend(ax, 'off');
                ax.Visible = 'off';
            end
        end

        function clearDataMaps(app)
            c = app.Controls;
            if ~isfield(c, 'layoutAxes')
                return
            end
            for ax = [c.previewAxes, c.layoutAxes, c.shotOverlayAxes]
                cla(ax, 'reset');
                colorbar(ax, 'off');
                legend(ax, 'off');
                ax.Visible = 'off';
            end
            c.previewInfo.Text = '';
            c.layoutInfo.Text = '';
            c.shotOverlayInfo.Value = {''};
            % 質的変数の交互作用も、前のデータの結果を残さない（読み込み直すと調べ直す）
            app.Interactions = [];
            c.interactionMainTable.Data = {};
            c.interactionTable.Data = {};
            removeStyle(c.interactionTable);
            c.interactionAdvice.Value = {'データを読み込むと、質的変数の効果と交互作用を調べて、ここに目安を出します。'};
            c.interactionAdvice.FontColor = app.Palette.text;
            setChoices(c.interactionPair, "—", {''});
            cla(c.interactionAxes, 'reset');
            c.interactionAxes.Visible = 'off';
            set([c.interactionRun, c.interactionPair, c.interactionAxis], 'Enable', 'off');
            if isfield(c, 'measurePanel')
                clearMeasurePanel(app);
            end
        end
    end
end

% ================= このファイルだけで使う小さな関数 =================
function lines = overlayLines(overlay)
% Shot 重ね合わせの Mark の位置ごとの平均・σ・相関（Shot・Wafer 間）の説明
average = overlay.average;
lines = strings(size(average.points, 1), 1);
for k = 1:numel(lines)
    deviation = sqrt(average.covariance(k, 1:2));
    correlation = average.covariance(k, 3) / prod(deviation);
    lines(k) = sprintf("M%g（%.3f, %.3f）：平均 X %+.2f・Y %+.2f nm、σ X %.2f・Y %.2f nm、相関 %+.2f（%d 点）", ...
        overlay.markLabels(k), average.points(k, :), average.mean(k, :), deviation, correlation, ...
        min(average.count(k, :)));
end
end

function text = displayUnit(units)
text = replace(string(units), "um", "µm");
end

function text = listOrNone(values)
if isempty(values)
    text = "（列なし・空）";
else
    text = strjoin(string(values), "、");
end
end

function text = shotSizeText(rangeMm)
% rangeMm は [最小の幅, 最小の高さ; 最大の幅, 最大の高さ]
if isequal(rangeMm(1, :), rangeMm(2, :))
    text = sprintf("%.3f × %.3f mm", rangeMm(1, :));
else
    text = sprintf("%.3f × %.3f 〜 %.3f × %.3f mm（Wafer によって違う）", rangeMm(1, :), rangeMm(2, :));
end
end

function text = directionText(summary)
switch summary.directionSource
    case "なし"
        text = "なし（質的変数・制約に使わない。「Scan 方向が無い行に付ける値」で付けられます）";
    otherwise
        text = summary.directionSource + "（質的変数・制約に使う）";
end
end

function [centers, sizeMm] = shotFrameData(unit, show)
% Wafer マップに Shot の枠を描くための中心と大きさ（描かないときは空）
if show
    centers = [unit.shots.Xmm, unit.shots.Ymm];
    sizeMm = unit.shotSizeMm;
else
    centers = zeros(0, 2);
    sizeMm = [NaN, NaN];
end
end

function limit = colorLimitOf(values)
limit = max(abs(values(isfinite(values))), [], 'all');
if isempty(limit) || limit <= 0
    limit = 1;
end
end
