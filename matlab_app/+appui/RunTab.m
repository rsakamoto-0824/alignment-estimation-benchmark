classdef (Abstract) RunTab < appui.Core
    %RUNTAB 「3. 実行」タブ：評価の実行・中断・再開・条件の追加と、計測マップ。
    %   AlignmentEstimationApp（画面の本体）の一部。画面の部品は Controls、データ・結果は Core のプロパティに持つ。
    %   ほかのタブの関数も同じように呼べる（どれも AlignmentEstimationApp の関数になる）。

    methods
        function results = runEvaluationNow(app, showProgress, pauseAfter)
            %RUNEVALUATIONNOW 評価を最初から実行して結果の画面を更新する。進み具合の画面の「一時中断」で止められ、
            %   止めたときは途中までの結果を出す（resumeEvaluation で続きから再開できる）。
            %   pauseAfter（省略可）を渡すと、その件数を計算したところで一時中断する（動作確認・説明資料用）。
            if nargin < 2
                showProgress = true;
            end
            if nargin < 3
                pauseAfter = Inf;
            end
            prepareEvaluation(app);
            results = evaluate(app, showProgress, [], pauseAfter);
        end

        function results = resumeEvaluation(app, showProgress)
            %RESUMEEVALUATION 一時中断した評価を、続きから再開する（済んだ組み合わせは計算しない）。
            %   中断した後に設定やデータを変えたときは再開できない（「評価を始める」で最初から計算する）。
            if nargin < 2
                showProgress = true;
            end
            previous = app.BaseResults;
            if isempty(previous) || ~previous.cancelled || ~isfield(previous, "resume") || isempty(previous.resume)
                error('alignest:resume', '続きから再開できる評価がありません。「評価を始める」で計算してください。');
            end
            prepareEvaluation(app);
            runSettings = previous.settings;
            if isfield(previous, "runSettings")
                runSettings = previous.runSettings;   % 条件を足した評価では、合わせた設定ではなく最後に実行した設定と比べる
            end
            if ~alignest.sameRunSettings(runSettings, app.Settings)
                error('alignest:resume', ['一時中断した後に評価の設定が変わったので、続きから再開できません。' ...
                    '設定を戻すか、「評価を始める」で最初から計算してください。']);
            end
            results = evaluate(app, showProgress, previous, Inf, "resume");
        end

        function results = extendEvaluation(app, showProgress)
            %EXTENDEVALUATION 評価済みの結果に、「2. 評価の設定」で増やした手法・学習パターン（学習 Shot 数・計測率など）を
            %   足して評価する。済んだ組み合わせ（Wafer × 学習パターン × 手法）は計算せず、無いものだけを計算して結果に
            %   加える（alignest.runEvaluation の "extend"）。推定の結果を変える設定（データ・質的変数・制約・評価の条件・
            %   Overlay 補正など。alignest.extensionConflicts）を変えたときは追加できない（「評価を始める」で計算し直す）。
            if nargin < 2
                showProgress = true;
            end
            prepareEvaluation(app);
            previous = app.BaseResults;
            if isempty(previous) || isImportedResults(previous)
                error('alignest:extend', ['条件を追加できる評価の結果がありません。先に「評価を始める」で評価してください' ...
                    '（Excel から読み込んだ結果には追加できません）。']);
            end
            results = evaluate(app, showProgress, previous, Inf, "extend");
        end

        function [plans, components] = drawMeasurementMap(app, unitIndex, planLabels)
            %DRAWMEASUREMENTMAP 選んだ Wafer・学習パターン（省略時は画面の選択。どちらも複数可）の計測マップを「3. 実行」に
            %   並べて描く（Wafer × 学習パターン、最大 MAX_MEASURE_PANELS 枚）。学習に使う（計測する）Shot・必ず計測する Shot・
            %   計測しない Shot を塗り分け、選べば Scan 方向（Shot の内側の色の枠と ▲・▼）と同心円の制約の区切りも描く。
            %   評価の前に使える。学習パターンは評価と同じ作り方なので、同じ設定なら評価でも同じ Shot を使う。
            %   plans は描いた学習パターン（Wafer ごとに学習パターンの順）。components は、図ごとの「全計測との成分の差」
            %   （計測配置の点だけで求めた Overlay 補正の Wafer 線形・高次、Shot 共通 低次・高次の成分と、全計測で求めた成分の差。
            %   alignest.planComponentDifference の結果の配列。図の右下の表にも出す）。
            c = app.Controls;
            if isempty(app.Data)
                error('alignest:noData', '先に「1. データの読み込み」でデータを読み込んでください。');
            end
            controlsToSettings(app);
            settingsErrors = validateSettings(app);
            if ~isempty(settingsErrors)
                error('alignest:settings', '%s', strjoin(settingsErrors, newline));
            end
            refreshMeasurementChoices(app);
            if nargin >= 2
                c.measureWafer.Value = num2cell(unitIndex);
            end
            if nargin >= 3
                planLabels = string(planLabels);
                unknown = planLabels(~ismember(planLabels, string(c.measurePlan.Items)));
                if ~isempty(unknown)
                    error('alignest:measurementPlan', '学習パターン「%s」はありません（「2. 評価の設定」を確かめてください）。', ...
                        unknown(1));
                end
                c.measurePlan.Value = cellstr(planLabels);
            end
            specs = alignest.buildPlanSpecs(app.Settings.sampling);
            units = cell2mat(c.measureWafer.Value);
            labels = string(c.measurePlan.Value);
            if isempty(units) || isempty(labels)
                error('alignest:measurementPlan', 'Wafer と学習パターンを1つ以上選んでください。');
            end
            [unitGrid, labelGrid] = ndgrid(1:numel(units), 1:numel(labels));
            pairs = [reshape(units(unitGrid.'), [], 1), reshape(labelGrid.', [], 1)];   % Wafer ごとに学習パターンの順
            nPanels = min(size(pairs, 1), app.MAX_MEASURE_PANELS);
            dialog = [];
            if app.Figure.Visible == "on"
                dialog = uiprogressdlg(app.Figure, 'Title', '計測マップ', 'Indeterminate', 'on', 'Message', '');
            end
            cleanup = onCleanup(@() closeDialog(dialog));
            if app.Figure.Visible == "on" && app.TabGroup.SelectedTab ~= app.Tabs.run
                % 並べ方は枠の大きさで決めるので、枠が画面に出ている状態で描く
                app.TabGroup.SelectedTab = app.Tabs.run;
                drawnow;
            end
            layout = resetMeasurePanel(app, nPanels);
            rings = zeros(1, 0);
            if c.measureRings.Value
                rings = activeZoneEdges(app.Settings);
            end
            plans = repmat(alignest.planTemplate(), 0, 1);
            lines = strings(0, 1);
            axesList = gobjects(1, nPanels);
            components = struct("summary", {}, "coefficients", {}, "nPoints", {}, "description", {}, "messages", {});
            componentRows = cell(nPanels, 1);
            statisticRows = cell(nPanels, 1);
            % 成分の差の表の1列目：図どうしで違うもの（Wafer が1つなら学習パターン、学習パターンが1つなら Wafer）
            oneWafer = isscalar(unique(pairs(1:nPanels, 1)));
            onePlan = isscalar(unique(pairs(1:nPanels, 2)));
            panelHeader = ternary(oneWafer, "学習パターン", ternary(onePlan, "Wafer", "Wafer｜学習パターン"));
            for k = 1:nPanels
                unit = app.Data.units(pairs(k, 1));
                spec = specs(string({specs.label}) == labels(pairs(k, 2)));
                plan = measurementPlan(app, pairs(k, 1), spec(1), dialog);
                ax = nexttile(layout);
                [excludedShots, requiredMarks, excludedMarks] = selectionMarks(app, unit, plan);
                alignest.plot.measurementMap(ax, unit, plan, app.Settings.data.waferRadiusMm, ...
                    unit.label + "｜" + plan.label, showScan=c.measureScan.Value, ringRadiiMm=rings, ...
                    showLegend=nPanels == 1, allCategories=k == 1 && nPanels > 1, scanStyle=scanStyle(app), ...
                    excludedShots=excludedShots, requiredMarks=requiredMarks, excludedMarks=excludedMarks);
                % クリックで Shot（Mark 単位の学習パターンでは Mark）を必ず計測・計測しないに指定する
                ax.ButtonDownFcn = @(source, event) app.onMeasureMapClicked(source, event, pairs(k, 1), ...
                    any(spec(1).type == ["mark", "markd"]) || ~isempty(plan.markIndex));
                axesList(k) = ax;
                plans(end + 1, 1) = orderfields(plan, alignest.planTemplate()); %#ok<AGROW>
                lines = [lines; measurementLines(app, unit, plan)]; %#ok<AGROW>
                components(end + 1, 1) = alignest.planComponentDifference(unit, plan, app.Settings); %#ok<AGROW>
                panelLabel = ternary(oneWafer, plan.label, ternary(onePlan, unit.label, unit.label + "｜" + plan.label));
                componentRows{k} = componentTableRows(panelLabel, components(end).summary);
                statisticRows{k} = statisticTableRows(panelLabel, alignest.planStatisticsDifference(unit, plan).table);
                if ~isempty(components(end).messages)
                    lines = [lines; "成分の差：" + strjoin(components(end).messages, " ")]; %#ok<AGROW>
                end
            end
            showMeasureComponents(app, vertcat(componentRows{:}), components, panelHeader);
            statistics = vertcat(statisticRows{:});
            if isempty(statistics)
                statistics = cell(0, 8);
            end
            c.measureStatistics.Data = statistics;
            names = reshape(cellstr(c.measureStatistics.ColumnName), 1, []);
            names{1} = char(panelHeader);
            c.measureStatistics.ColumnName = names;
            refreshMeasureSelectionInfo(app);
            if nPanels > 1
                % 並べるときは凡例を1つだけ右に、短い名前で出す（区分の数は図ごとに違うので、数は下の欄に書く）
                items = flipud(findobj(axesList(1), '-regexp', 'DisplayName', '.+'));
                names = regexprep(string(get(items, 'DisplayName')), '（\d+）$', '');
                names = replace(names, ["必ず計測する Shot（指定・最外周など）", "選んで計測する Shot", ...
                    "計測しない Shot（評価に使う）", "計測値の無い Shot"], ["必ず計測", "選んで計測", "計測しない（評価）", ...
                    "計測値なし"]);
                shown = legend(axesList(1), items, cellstr(names), 'Box', 'off', 'FontSize', app.SMALL_AXES_FONT_SIZE);
                shown.Layout.Tile = 'east';
            end
            styleAxes(app, axesList, ternary(nPanels > 1, app.SMALL_AXES_FONT_SIZE, app.AXES_FONT_SIZE));
            app.Controls.measureAxes = axesList;
            if size(pairs, 1) > nPanels
                lines = [sprintf("選んだ %d 通りのうち、はじめの %d 通りを描きました（Wafer・学習パターンを減らしてください）。", ...
                    size(pairs, 1), nPanels); lines];
            end
            c.measureInfo.Value = cellstr(lines);
        end

        function sheet = exportMeasurementMap(app, filePath)
            %EXPORTMEASUREMENTMAP 選んだ Wafer（複数選んだときは1枚目）の計測マップを、すべての学習パターンについて
            %   Excel に書き出す。
            %   「計測マップ」シート：Shot ごとの座標・行・列・最外周・指定の有無と、学習パターンごとの 1（計測する）／0（しない）。
            %   「学習パターン」シート：学習パターンごとの Shot 数・計測率・必ず計測した数・I 基準・D 基準・shotNo・メモ。
            %   「成分の差」シート：学習パターン・成分ごとの、全計測で求めた成分の大きさと、計測配置の点で求めた成分との差
            %   （|平均|+3σ と最大 [nm]。alignest.planComponentDifference）。「成分の係数」シート：項ごとの係数（全計測・
            %   計測配置の点・差）。
            if isempty(app.Data)
                error('alignest:noData', '先に「1. データの読み込み」でデータを読み込んでください。');
            end
            controlsToSettings(app);
            settingsErrors = validateSettings(app);
            if ~isempty(settingsErrors)
                error('alignest:settings', '%s', strjoin(settingsErrors, newline));
            end
            refreshMeasurementChoices(app);
            selected = cell2mat(app.Controls.measureWafer.Value);
            if isempty(selected)
                error('alignest:measurementPlan', '書き出す Wafer を選んでください。');
            end
            unitIndex = selected(1);
            unit = app.Data.units(unitIndex);
            shots = unit.shots;
            specs = alignest.buildPlanSpecs(app.Settings.sampling);
            dialog = [];
            if app.Figure.Visible == "on"
                dialog = appui.ProgressWindow(app.Figure, "計測マップ", "", app.Palette, app.FontSize, "");
            end
            cleanup = onCleanup(@() closeDialog(dialog));
            candidates = find(shots.nValidX + shots.nValidY > 0);
            [~, required] = alignest.requiredShotIndex(shots, candidates, app.Settings.sampling);
            sheet = table(shots.shotNo, shots.Xmm, shots.Ymm, shots.row, shots.column, shots.direction, ...
                double(ismember((1:numel(shots.shotNo)).', candidates)), double(alignest.outerShots(shots)), ...
                double(ismember((1:numel(shots.shotNo)).', required.specified)), 'VariableNames', ["shotNo", "Xmm", ...
                "Ymm", "行（上から）", "列（左から）", "Scan方向", "計測値あり", "最外周", "指定で必ず計測"]);
            summary = cell(numel(specs), 11);
            marks = unit.marks;
            markSheet = table(marks.shotNo, marks.markNo, marks.x, marks.y, 'VariableNames', ["shotNo", "markNo", "Xmm", "Ymm"]);
            hasMarkPlans = false;
            [componentParts, coefficientParts, statisticParts] = deal(cell(numel(specs), 1));
            componentText = "";
            for k = 1:numel(specs)
                if ~isempty(dialog)
                    dialog.Value = (k - 1) / numel(specs);
                end
                plan = measurementPlan(app, unitIndex, specs(k), dialog);
                sheet.(char(plan.label)) = double(ismember((1:numel(shots.shotNo)).', plan.shotIndex));
                markSheet.(char(plan.label)) = double(alignest.trainingMarks(unit, plan) & plan.ok);
                hasMarkPlans = hasMarkPlans || ~isempty(plan.markIndex);
                summary(k, :) = {plan.label, plan.rate, plan.nShots, numel(plan.requiredShotIndex), plan.criterionI, ...
                    plan.criterionD, plan.efficiencyI, plan.efficiencyD, plan.violation, ...
                    strjoin(string(plan.shotNos(:).'), " "), plan.message};
                difference = alignest.planComponentDifference(unit, plan, app.Settings);
                componentText = difference.description;
                parts = difference.summary;
                componentParts{k} = [table(repmat(plan.label, height(parts), 1), 'VariableNames', "学習パターン"), ...
                    renamevars(parts, parts.Properties.VariableNames, ["成分", "全計測の成分X[nm]", "全計測の成分Y[nm]", ...
                    "差X[nm]", "差Y[nm]", "差の最大X[nm]", "差の最大Y[nm]"])];
                parts = difference.coefficients;
                coefficientParts{k} = [table(repmat(plan.label, height(parts), 1), 'VariableNames', "学習パターン"), ...
                    renamevars(parts, parts.Properties.VariableNames, ["式", "成分", "補正モデルの成分", "項", "全計測", ...
                    "計測配置の点", "差", "単位", "メモ"])];
                parts = alignest.planStatisticsDifference(unit, plan).table;
                statisticParts{k} = [table(repmat(plan.label, height(parts), 1), 'VariableNames', "学習パターン"), ...
                    renamevars(parts, parts.Properties.VariableNames, ["統計量", "全計測X", "全計測Y", "計測配置の点X", ...
                    "計測配置の点Y", "差X", "差Y"])];
            end
            planSheet = cell2table(summary, 'VariableNames', ["学習パターン", "計測率[%]", "学習Shot数", ...
                "必ず計測したShot数", "I基準tr(M⁻¹)", "D基準det(M)^(-1/p)", "I効率(全計測に対する)", ...
                "D効率(全計測に対する)", "制約の違反量", "計測するshotNo", "メモ"]);
            if isfile(filePath)
                delete(filePath);
            end
            writetable(sheet, filePath, 'Sheet', '計測マップ');
            if hasMarkPlans
                % Mark 単位の計画があるときは、Mark ごとの 1（計測する）・0（しない）も書く
                writetable(markSheet, filePath, 'Sheet', '計測マップ_Mark');
            end
            writetable(planSheet, filePath, 'Sheet', '学習パターン');
            writetable(vertcat(componentParts{:}), filePath, 'Sheet', '成分の差');
            writetable(vertcat(coefficientParts{:}), filePath, 'Sheet', '成分の係数');
            writetable(vertcat(statisticParts{:}), filePath, 'Sheet', '統計量の差');
            notes = table(["Wafer"; "学習 Shot の選び方"; "見方"; "成分の差"], [unit.label; ...
                strjoin(string(app.Controls.samplingMethod.Items(ismember(app.Controls.samplingMethod.ItemsData, ...
                app.Controls.samplingMethod.Value))), "、"); "学習パターンの列は 1 = 計測する（学習に使う）、0 = 計測しない（評価に使う）。" + ...
                "最外周・指定で必ず計測は 1 = そうである。"; "「2. 評価の設定」の Overlay 補正（" + componentText + "）を、" + ...
                "全計測と計測配置の点（計測する Mark）だけで X・Y 別に最小二乗で当てはめ、成分（Wafer 線形・Wafer 高次・" + ...
                "Shot 共通 低次・Shot 共通 高次・合計）の補正量を全計測の Mark の位置で比べた。全計測の成分は全計測で求めた" + ...
                "補正量の |平均|+3σ、差は 計測配置の点で求めた補正量 − 全計測で求めた補正量 の |平均|+3σ と絶対値の最大 [nm]。" + ...
                "重なる項・決まらない項は前の項に含めて 0（成分の係数のメモ）。"], 'VariableNames', ["項目", "内容"]);
            writetable(notes, filePath, 'Sheet', '説明');
        end

        function setMeasurementSelection(app, kind, target, mode)
            %SETMEASUREMENTSELECTION 計測マップの指定（画面で Shot・Mark をクリックするのと同じ）。
            %   kind："shot"（target は shotNo）・"mark"（target は "shotNo-markNo"）。mode："required"（必ず計測する）・
            %   "excluded"（計測しない。学習に使わず評価に使う）・"clear"（指定を外す）。設定 sampling.requiredShots・
            %   excludedShots・requiredMarks・excludedMarks を変え、計測マップを描いてあれば作り直す。
            sampling = app.Settings.sampling;
            if string(kind) == "shot"
                target = double(target);
                required = reshape(double(fieldOr(sampling, "requiredShots", zeros(1, 0))), 1, []);
                excluded = reshape(double(fieldOr(sampling, "excludedShots", zeros(1, 0))), 1, []);
                [required, excluded] = applySelection(required, excluded, target, string(mode));
                app.Settings.sampling.requiredShots = unique(required);
                app.Settings.sampling.excludedShots = unique(excluded);
            elseif string(kind) == "mark"
                target = string(target);
                alignest.parseMarkKeys(target);   % 形を確かめる
                required = reshape(string(fieldOr(sampling, "requiredMarks", strings(1, 0))), 1, []);
                excluded = reshape(string(fieldOr(sampling, "excludedMarks", strings(1, 0))), 1, []);
                [required, excluded] = applySelection(required, excluded, target, string(mode));
                app.Settings.sampling.requiredMarks = unique(required, 'stable');
                app.Settings.sampling.excludedMarks = unique(excluded, 'stable');
            else
                error('alignest:measurementSelection', '指定の対象は shot・mark のどちらかです: %s', string(kind));
            end
            selectionChanged(app);
        end

        function showRunLog(app)
            %SHOWRUNLOG 評価の記録（データの確認・学習パターン・推定できなかった組み合わせなど）の全文を別の窓で見る。
            lines = app.RunLog;
            if isempty(lines)
                lines = "まだ記録はありません（評価の後や、既定の設定ファイルを読んだときに残ります）。";
            end
            window = uifigure('Name', '記録', 'Position', [200, 200, 760, 480], 'Visible', app.Figure.Visible);
            grid = uigridlayout(window, [1, 1], 'Padding', 10);
            uitextarea(grid, 'Editable', 'off', 'Value', cellstr(lines), 'FontSize', app.FontSize);
            app.LogWindow = window;
        end
    end

    methods (Access = {?appui.Core})
        % ================= 3. 実行 =================
        function buildRunTab(app)
            grid = uigridlayout(app.Tabs.run, [3, 1], 'RowHeight', {'fit', 'fit', '1x'}, 'Padding', 12, ...
                'RowSpacing', 10);
            c.runSummary = uilabel(grid, 'WordWrap', 'on', 'Text', '');
            buttonGrid = uigridlayout(grid, [1, 5], 'ColumnWidth', {240, 200, 280, 'fit', '1x'}, 'Padding', 0);
            c.run = primaryButton(app, buttonGrid, '評価を始める', @(~, ~) app.onRun());
            c.resumeRun = uibutton(buttonGrid, 'Text', '続きから再開', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onResumeRun(), 'Tooltip', ['「一時中断」で止めた評価の残りを計算します' ...
                '（中断の後に設定を変えると再開できません）。']);
            c.extendRun = uibutton(buttonGrid, 'Text', '条件を追加して評価', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onExtendRun(), 'Tooltip', ['評価の後に「2. 評価の設定」で手法や学習 Shot 数' ...
                '（計測率）を増やしてから押すと、増えた組み合わせだけを計算して今の結果に加えます。データ・質的変数・制約・' ...
                '評価の条件などを変えたときは追加できません（「評価を始める」で計算し直してください）。']);
            c.viewLog = uibutton(buttonGrid, 'Text', '記録を見る…', 'ButtonPushedFcn', @(~, ~) app.showRunLog(), ...
                'Tooltip', ['データの確認・学習パターン・推定できなかった組み合わせなどの知らせの全文を、別の窓で見ます' ...
                '（要点は右に出します）。']);
            c.runStatus = uilabel(buttonGrid, 'WordWrap', 'on', 'Text', '');
            lower = uigridlayout(grid, [1, 2], 'ColumnWidth', {'0.8x', '2.6x'}, 'Padding', 0, 'ColumnSpacing', 12);
            % 計測の指定：計測マップのクリックで、必ず計測する・計測しない Shot・Mark を指定する
            selectPanel = uipanel(lower, 'Title', '計測の指定');
            selectGrid = uigridlayout(selectPanel, [5, 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit'}, 'Padding', 8, ...
                'RowSpacing', 6);
            modeGrid = uigridlayout(selectGrid, [1, 2], 'ColumnWidth', {'fit', '1x'}, 'Padding', 0);
            label(modeGrid, 'クリックで', 1, 1);
            c.measureClickMode = uidropdown(modeGrid, 'Items', {'見るだけ', '必ず計測にする', '計測しないにする', '指定を外す'}, ...
                'ItemsData', {'none', 'required', 'excluded', 'clear'}, 'Tooltip', ['計測マップの Shot（Mark 単位の学習パターンの' ...
                '図では Mark）をクリックしたときにすること。計測しない Shot・Mark は学習に使わず、評価には使います。']);
            place(c.measureClickMode, 1, 2);
            c.measureSelectNote = uilabel(selectGrid, 'WordWrap', 'on', 'FontColor', app.Palette.muted, 'UserData', "muted", ...
                'Text', ['Shot の図では Shot、Mark 単位の図では Mark を指定します。Mark の指定は Mark 単位の計画だけに効きます' ...
                '（必ず計測する Shot は、Mark 単位ではその Shot の Mark すべて）。「2. 評価の設定」の欄でも指定できます。']);
            label(selectGrid, '指定した Shot・Mark');
            c.measureSelectionInfo = uitextarea(selectGrid, 'Editable', 'off', 'Value', {'（なし）'});
            c.clearMeasureSelections = uibutton(selectGrid, 'Text', '指定をすべて外す', ...
                'ButtonPushedFcn', @(~, ~) app.onClearMeasureSelections());
            % 計測マップ：評価の前に、学習に使う（計測する）Shot を Wafer 上で確かめる
            mapPanel = uipanel(lower, 'Title', '計測マップ');
            mapGrid = uigridlayout(mapPanel, [4, 1], 'RowHeight', {'fit', 'fit', '1x', 160}, 'Padding', 8, 'RowSpacing', 6);
            choose = uigridlayout(mapGrid, [2, 4], 'ColumnWidth', {'fit', '1x', 'fit', '1.4x'}, 'RowHeight', {66, 'fit'}, ...
                'Padding', 0);
            label(choose, 'Wafer', 1, 1);
            onMeasure = @(~, ~) app.onDrawMeasurementMap();
            onMeasureDisplay = @(~, ~) app.onMeasureDisplayChanged();   % 表示の切り替えでは、描いた図を描き直すだけ
            multiTip = 'Ctrl・Shift で複数選ぶと、Wafer × 学習パターンの図を並べます（最大 6 枚）。';
            c.measureWafer = uilistbox(choose, 'Items', {'—'}, 'ItemsData', {1}, 'Multiselect', 'on', 'Tooltip', multiTip);
            place(c.measureWafer, 1, 2);
            label(choose, '学習パターン', 1, 3);
            c.measurePlan = uilistbox(choose, 'Items', {'—'}, 'Multiselect', 'on', 'Tooltip', multiTip);
            place(c.measurePlan, 1, 4);
            c.measureScan = uicheckbox(choose, 'Text', 'Scan 方向を色で示す', 'Value', true, ...
                'ValueChangedFcn', onMeasureDisplay, 'Tooltip', ['Shot の内側の枠の色と ▲・▼ で Scan 方向を示します' ...
                '（Scan 方向の制約で Shot 数がそろっているかを確かめる）。色と向きは「2. 評価の設定」の表示で変えられます。']);
            place(c.measureScan, 2, [1, 2]);
            c.measureRings = uicheckbox(choose, 'Text', '同心円の区切りを描く', 'Value', true, ...
                'ValueChangedFcn', onMeasureDisplay, 'Tooltip', ['同心円の制約を使うとき、区切りの半径（Shot 単位の計画は' ...
                ' Shot 中心、Mark 単位の計画は Mark の半径で区画を分ける）を橙の一点鎖線で描きます。']);
            place(c.measureRings, 2, [3, 4]);
            buttons = uigridlayout(mapGrid, [1, 4], 'ColumnWidth', {'fit', 'fit', 'fit', 'fit'}, 'Padding', 0);
            c.drawMeasure = uibutton(buttons, 'Text', '計測マップを作る', 'ButtonPushedFcn', onMeasure);
            c.saveMeasure = uibutton(buttons, 'Text', '図を画像で保存…', 'ButtonPushedFcn', @(~, ~) app.onSaveMeasurementMap());
            c.copyMeasure = uibutton(buttons, 'Text', '図をコピー', 'Tooltip', app.COPY_TOOLTIP, ...
                'ButtonPushedFcn', @(source, ~) app.onCopyFigure("measure", source));
            c.exportMeasure = uibutton(buttons, 'Text', '計測マップを Excel に書き出す…', ...
                'ButtonPushedFcn', @(~, ~) app.onExportMeasurementMap(), 'Tooltip', ['選んだ Wafer の Shot ごとに、' ...
                'すべての学習パターンで計測するか（1）しないか（0）を書き出します。']);
            % 図は専用の枠に、並べる数に合わせて tiledlayout で作る（凡例を1つにまとめて右に置くため）
            c.measurePanel = uipanel(mapGrid, 'BorderType', 'none');
            c.measureAxes = gobjects(1, 0);
            infoGrid = uigridlayout(mapGrid, [1, 2], 'ColumnWidth', {'0.75x', '1.6x'}, 'Padding', 0, 'ColumnSpacing', 6);
            c.measureInfo = uitextarea(infoGrid, 'Editable', 'off', 'Value', ...
                {'「2. 評価の設定」で学習 Shot の選び方を決め、Wafer と学習パターンを選んで「計測マップを作る」を押してください。'});
            % 全計測との差：成分（Overlay 補正）と統計量をタブで切り替える
            infoTabs = uitabgroup(infoGrid);
            componentTab = uitab(infoTabs, 'Title', '成分の差');
            statisticTab = uitab(infoTabs, 'Title', '統計量の差');
            componentGrid = uigridlayout(componentTab, [1, 1], 'Padding', 0);
            statisticGrid = uigridlayout(statisticTab, [1, 1], 'Padding', 0);
            c.measureStatistics = uitable(statisticGrid, 'RowName', {}, 'ColumnName', {'学習パターン', '統計量', ...
                '全計測|X', '全計測|Y', '計測配置|X', '計測配置|Y', '差|X', '差|Y'}, 'ColumnWidth', ...
                {150, 64, 58, 58, 64, 64, 58, 58}, 'Data', cell(0, 8), 'Tooltip', ['全計測との統計量の差：計測配置の点（計測する' ...
                ' Mark）の計測値の平均・中央値・分散（不偏分散）・最大・最小を、全計測（有効なすべての Mark）と比べます。' ...
                '差 = 計測配置の点 − 全計測。単位は計測値と同じ（分散は単位の2乗）。']);
            c.measureComponents = uitable(componentGrid, 'RowName', {}, 'ColumnName', {'Wafer｜学習パターン', '成分', ...
                '全計測|X [nm]', '全計測|Y [nm]', '差|X [nm]', '差|Y [nm]'}, 'ColumnWidth', {170, 118, 54, 54, 54, 54}, ...
                'Data', cell(0, 6), 'Tooltip', ['全計測との成分の差：「2. 評価の設定」の Overlay 補正の Wafer 成分・Shot 共通成分を、' ...
                '全計測と計測配置の点だけで当てはめ、成分ごとの補正量を全計測の Mark の位置で比べます。全計測：全計測で求めた成分の' ...
                '補正量の |平均|+3σ。差：計測配置の点で求めた成分 − 全計測で求めた成分 の |平均|+3σ（Shot ごとの成分は使いません。' ...
                '詳しくは「ヘルプ」）。']);
            app.Controls = mergeStruct(app.Controls, c);
        end

        function style = scanStyle(app)
            % Scan 方向の色と向き（「設定」→「Scan 方向の向きと色」。設定 display。alignest.plot.scanStyle）
            style = alignest.plot.scanStyle(fieldOr(app.Settings, "display", struct()));
        end

        function text = scanLegendText(app)
            % 説明の文に入れる Scan 方向の印（例：「Scan 1 ▲ 上・Scan 2 ▼ 下」）
            style = scanStyle(app);
            text = strjoin("Scan " + (1:2) + " " + style.symbols + " " + style.words, "・");
        end

        function onResetScanDirections(app)
            runWithAlert(app, @() app.setScanDirection([], []), "Scan 方向を元に戻せませんでした", ...
                "「1. データの読み込み」の設定を確かめてください。");
        end

        function prepareEvaluation(app)
            % 評価の前に、読み込みの条件と設定を確かめる
            if ~isempty(app.Data) && (~isequal(currentMapping(app), app.AppliedMapping) || ...
                    ~isequal(currentDataOptions(app), dataOptions(app.Data)))
                invalidatePreparedData(app);
            end
            if isempty(app.Data)
                error('alignest:noData', '先に「1. データの読み込み」でデータを読み込んでください。');
            end
            controlsToSettings(app);
            settingsErrors = validateSettings(app);
            if ~isempty(settingsErrors)
                error('alignest:settings', '%s', strjoin(settingsErrors, newline));
            end
        end

        function results = evaluate(app, showProgress, previous, pauseAfter, mode)
            % 評価を実行して（previous があれば続きから、mode = "extend" なら条件を足して）結果の画面を更新する。
            % pauseAfter 件で一時中断する
            if nargin < 5
                mode = "resume";
            end
            c = app.Controls;
            set([c.run, c.resumeRun, c.extendRun], 'Enable', 'off');
            restore = onCleanup(@() set(c.run, 'Enable', 'on'));
            c.runStatus.Text = "計算中…";
            c.runStatus.FontColor = app.Palette.text;
            dialog = [];
            if showProgress
                % 知らせの文（組み合わせの名前）が長くても見切れないように、文の行数に合わせて高さを変える窓にする
                dialog = appui.ProgressWindow(app.Figure, "評価中", "学習パターンを作っています…", app.Palette, ...
                    app.FontSize, "一時中断");
            end
            timer = tic;
            lastUpdate = -Inf;
            startDone = 0;
            if ~isempty(previous)
                startDone = height(previous.table);
            end
            progressFcn = @(done, total, message) reportProgress(done, total, message);
            try
                results = alignest.runEvaluation(app.Data, app.Settings, progressFcn, previous, mode);
            catch err
                closeDialog(dialog);
                c.runStatus.Text = "⚠ 評価を実行できませんでした。";
                c.runStatus.FontColor = app.Palette.error;
                c.extendRun.Enable = onOff(~isempty(app.BaseResults) && ~isImportedResults(app.BaseResults));
                c.resumeRun.Enable = onOff(~isempty(app.BaseResults) && app.BaseResults.cancelled && ...
                    ~isImportedResults(app.BaseResults));
                rethrow(err);
            end
            closeDialog(dialog);
            app.BaseResults = results;
            app.Results = alignest.filterResults(results, app.Data, app.ResultFilter);
            app.MapCache = estimateCache(results);
            nFailed = nnz(results.table.note ~= "");
            if results.cancelled
                status = sprintf(['一時中断しました：%d / %d 件を計算済み（%.0f 秒）。結果一覧には途中までの結果が' ...
                    '出ています。「続きから再開」で残りを計算します。'], height(results.table), results.nTotal, ...
                    results.elapsedSeconds);
            elseif mode == "extend"
                status = sprintf("追加の評価が完了：新たに %d 件を計算し、評価済みの %d 件と合わせて %d 件になりました" + ...
                    "（計算時間は合計 %.0f 秒）。", height(results.table) - height(previous.table), height(previous.table), ...
                    height(results.table), results.elapsedSeconds);
            else
                status = sprintf("完了：%d 件を %.0f 秒で計算しました%s。", height(results.table), results.elapsedSeconds, ...
                    ternary(isempty(previous), "", "（一時中断の前と後の合計）"));
            end
            if nFailed > 0
                status = status + sprintf(" うち %d 件は推定できませんでした（理由は「記録を見る…」）。", nFailed);
            end
            % 要点はボタンの右に、全文は記録（「記録を見る…」で別の窓）に残す
            app.RunLog = reshape(string([status; results.additions(:); results.log(:)]), [], 1);
            c.runStatus.Text = status;
            c.runStatus.FontColor = ternary(nFailed > 0, app.Palette.error, app.Palette.text);
            refreshResultControls(app);
            c.resumeRun.Enable = onOff(results.cancelled);
            c.extendRun.Enable = 'on';
            app.TabGroup.SelectedTab = app.Tabs.results;

            function continueRun = reportProgress(done, total, message)
                continueRun = done < pauseAfter;
                if isempty(dialog) || ~continueRun
                    return
                end
                elapsed = toc(timer);
                if elapsed - lastUpdate < app.PROGRESS_INTERVAL_SECONDS && done < total
                    continueRun = ~dialog.CancelRequested;
                    return
                end
                lastUpdate = elapsed;
                done = double(done);
                total = double(total);
                remaining = elapsed / max(done - startDone, 1) * (total - done);
                dialog.Value = done / total;
                dialog.Message = sprintf('%d / %d 件（残り 約 %s）\n%s', done, total, durationText(remaining), message);
                drawnow;
                continueRun = ~dialog.CancelRequested;
            end
        end

        function onResumeRun(app)
            runWithAlert(app, @() app.resumeEvaluation(true), "続きから再開できませんでした", ...
                "「評価を始める」で最初から計算してください。");
        end

        function onExtendRun(app)
            runWithAlert(app, @() app.extendEvaluation(true), "条件を追加して評価できませんでした", ...
                "「2. 評価の設定」で変えたのが手法・説明変数の組・質的変数・学習 Shot 数（計測率）だけか確かめてください。" + ...
                "ほかの設定を変えたときは「評価を始める」で最初から計算してください。");
        end

        function onCompareDistributions(app)
            runWithAlert(app, @() app.compareDistributions(), "分布を比べられませんでした", ...
                "手法・学習パターン・Wafer を選び直して、もう一度試してください。");
        end

        function drawDistributionHistograms(app)
            % 「分布の比較」のヒストグラム（選んだ軸）：左は全面・学習・予測対象、右は予測対象の実測値と推定値
            c = app.Controls;
            if isempty(app.Distribution)
                return
            end
            spec = resultSpec(app);
            setChoices(c.distributionAxis, spec.labels, cellstr(spec.components));   % 1変数は X 成分（値の名前）だけ
            part = app.Distribution.(string(c.distributionAxis.Value));
            axisLabel = string(c.distributionAxis.Items{strcmp(c.distributionAxis.ItemsData, c.distributionAxis.Value)});
            alignest.plot.distributionHistograms(c.distributionAxes(1), part.samples(1:3), part.names(1:3), part.edges, ...
                axisLabel + " の計測値：全面・学習・予測対象", spec.unit);
            alignest.plot.distributionHistograms(c.distributionAxes(2), part.samples([3, 4]), part.names([3, 4]), part.edges, ...
                axisLabel + "：予測対象の実測値と推定値", spec.unit);
            set(c.distributionAxes, 'Visible', 'on');
            styleAxes(app, c.distributionAxes, app.AXES_FONT_SIZE);
            note = "";
            if isfield(app.Distribution, "note") && app.Distribution.note ~= ""
                note = "｜⚠ " + app.Distribution.note;
            end
            c.distributionInfo.Text = app.Distribution.title + note;
        end

        function onDrawMeasurementMap(app)
            runWithAlert(app, @() app.drawMeasurementMap(), "計測マップを作れませんでした", ...
                "「1. データの読み込み」と「2. 評価の設定」を確かめてから、もう一度試してください。");
        end

        function onMeasureDisplayChanged(app)
            % 「Scan 方向を色で示す」「同心円の区切りを描く」を切り替えたとき：計測マップを描いてあるときだけ描き直す
            % （まだ作っていなければ何もしない。学習パターンを作るのは「計測マップを作る」を押したときだけ）
            if hasMeasurementMap(app)
                onDrawMeasurementMap(app);
            end
        end

        function drawn = hasMeasurementMap(app)
            % 計測マップを描いてあるか（設定を直すと図は消える）
            axesList = app.Controls.measureAxes;
            drawn = ~isempty(axesList) && all(isvalid(axesList));
        end

        function onSaveMeasurementMap(app)
            saveFigureWithDialog(app, "measure", 'measurement_map.png');
        end

        function onExportMeasurementMap(app)
            [fileName, folder] = uiputfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, '計測マップを書き出す', 'measurement_map.xlsx');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            if runWithAlert(app, @() app.exportMeasurementMap(target), "計測マップを書き出せませんでした", ...
                    "同じ名前の Excel を開いていれば閉じて、もう一度試してください。")
                uialert(app.Figure, sprintf('計測マップを書き出しました：%s', target), '書き出しました', 'Icon', 'success');
            end
        end

        function plan = measurementPlan(app, unitIndex, spec, dialog)
            % 計測マップ用の学習パターン（評価と同じ作り方。同じ配置の Wafer・同じ設定では使い回す）
            if ~isa(app.MeasurementCache, 'containers.Map')
                app.MeasurementCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
            end
            if ~isempty(dialog)
                dialog.Message = sprintf("%s の「%s」を作っています…", app.Data.units(unitIndex).label, spec.label);
            end
            plan = alignest.cachedTrainingPlan(app.Data.units(unitIndex), spec, app.Settings, app.MeasurementCache);
        end

        function text = rateExample(app, rates)
            % 計測率から決まる Shot 数の例（最初の Wafer の候補 Shot 数で）
            text = "";
            if isempty(app.Data)
                return
            end
            unit = app.Data.units(1);
            nCandidates = nnz(unit.shots.nValidX + unit.shots.nValidY > 0);
            counts = max(1, round(rates / 100 * nCandidates));
            text = sprintf("。%s（候補 %d Shot）では %s Shot", unit.label, nCandidates, ...
                previewList(counts, app.LIST_PREVIEW_COUNT));
        end

        function text = exchangeText(~, detail)
            % 交換法で学習パターンを作る時間の目安（I 最適・D 最適・Mark 単位の I 最適・D 最適。最初の Wafer の配置で。
            % alignest.planSecondsGuide）。配置の違う Wafer があれば、その数だけ作り直す時間も書く
            text = "";
            each = detail.planSecondsEach(detail.planSecondsEach > 0);
            if isempty(each)
                return
            end
            range = durationText(min(each));
            if durationText(max(each)) ~= range
                range = range + "〜" + durationText(max(each));
            end
            text = sprintf("→ 目安：学習パターン1つ 約 %s", range);
            if numel(each) > 1
                text = text + sprintf("、全 %d 個で 約 %s", numel(each), durationText(sum(each)));
            end
            if detail.nLayouts > 1
                text = text + sprintf("。配置（値の無い Mark）の違う Wafer が %d 種類あり、合わせて 約 %s", ...
                    detail.nLayouts, durationText(detail.planSeconds));
            end
        end

        function text = requiredText(app)
            % 必ず計測する Shot の数（最初の Wafer で。画面の入力から数える）。Mark 単位の計画では必ず計測する Mark の数も
            c = app.Controls;
            text = "";
            [values, ok] = parseNumbers(c.requiredShots.Value);
            if ~ok || isempty(app.Data)
                return
            end
            sampling = struct("requiredShots", values, "requireOuterShots", c.requireOuter.Value);
            unit = app.Data.units(1);
            candidates = find(unit.shots.nValidX + unit.shots.nValidY > 0);
            [index, details] = alignest.requiredShotIndex(unit.shots, candidates, sampling);
            if isempty(index) && isempty(details.missingNos)
                text = "→ 必ず計測する Shot はありません";
            else
                text = sprintf("→ %s では %d Shot を必ず計測（指定 %d・最外周 %d", unit.label, numel(index), ...
                    numel(details.specified), numel(details.outer));
                overlap = numel(details.specified) + numel(details.outer) - numel(index);
                text = text + ternary(overlap > 0, sprintf("、重なり %d）", overlap), "）");
                if ~isempty(details.missingNos)
                    text = text + "。この Wafer に無い、または計測値の無い shotNo：" + strjoin(string(details.missingNos.'), " ");
                end
            end
            if any(ismember(string(c.samplingMethod.Value), ["mark", "markd"]))
                % Mark 単位の計画で必ず計測する Mark（Wafer 中心に最も近い Mark・必ず計測する Shot の Mark・指定した Mark）
                [requiredMarks, okRequired] = parseMarkText(c.requiredMarks.Value);
                [excludedMarks, okExcluded] = parseMarkText(c.excludedMarks.Value);
                [excludedShots, okShots] = parseNumbers(c.excludedShots.Value);
                if okRequired && okExcluded && okShots
                    sampling.requiredMarks = requiredMarks;
                    sampling.excludedMarks = excludedMarks;
                    sampling.excludedShots = excludedShots;
                    fixedMarks = alignest.markPlanFixedMarks(unit, sampling);
                    text = text + sprintf("。Mark 単位の計画では Mark %d 点を必ず計測（中心に最も近い Mark・必ず計測する" + ...
                        " Shot の Mark・指定した Mark）", numel(fixedMarks));
                end
            end
            text = text + "。「3. 実行」の計測マップで確かめられます。";
        end

        function onRun(app)
            runWithAlert(app, @() app.runEvaluationNow(true), "評価を実行できませんでした", ...
                "「1. データの読み込み」と「2. 評価の設定」を確かめてから、もう一度実行してください。");
        end

        function refreshRunSummary(app)
            c = app.Controls;
            if ~isfield(c, 'runSummary')
                return
            end
            try
                methods = alignest.activeMethods(app.Settings);   % 質的変数を1つずつ使う手法も数える
            catch
                % 手法の設定が正しくないとき（欄の下に理由が出る）は数えない
                methods = struct("id", {}, "family", {});
            end
            try
                specs = alignest.buildPlanSpecs(app.Settings.sampling);
                nPlans = numel(specs);
            catch
                nPlans = 0;
            end
            nUnits = 0;
            if ~isempty(app.Data)
                nUnits = numel(app.Data.units);
            end
            total = numel(methods) * nPlans * nUnits;
            seconds = 0;
            detail = struct("nMaternNuMethods", 0, "maternNuFactor", 1, "secondsPerRun", 2, "planSeconds", 0, ...
                "nLayouts", 0, "planSecondsEach", zeros(1, 0));
            if nUnits > 0 && nPlans > 0
                try
                    [seconds, detail] = alignest.estimateRunSeconds(app.Data.units, app.Settings);
                catch
                    % 設定が正しくないときは目安を出さない（「2. 評価の設定」に理由が出る）
                end
            end
            nuText = "";
            if detail.nMaternNuMethods > 0
                % ν を指定した Matérn は ν ごとに手法が増え、1条件の時間も長いので、目安に含めたことを示す
                nuText = sprintf("。うち ν を指定した Matérn の手法 %d 種類は 1条件 %g 秒で見積もり", ...
                    detail.nMaternNuMethods, detail.secondsPerRun * detail.maternNuFactor);
            end
            planText = "";
            if detail.planSeconds > 0
                % 交換法の学習パターン（とくに Mark 単位）は作るのに時間がかかるので、目安に含めたことと1枚あたりを示す
                planText = sprintf("。うち学習パターンを作る時間 約 %s（配置 %d 種類）、1枚あたり 約 %s", ...
                    durationText(detail.planSeconds), detail.nLayouts, durationText(seconds / nUnits));
            end
            text = sprintf("手法 %d 種類 × 学習パターン %d × Wafer %d 枚 = %d 回の推定（目安 %s%s%s）", ...
                numel(methods), nPlans, nUnits, total, durationText(seconds), planText, nuText);
            c.countLabel.Text = text;
            if isfield(c, 'exchangeInfo')
                c.exchangeInfo.Text = exchangeText(app, detail);
            end
            if nUnits == 0
                c.runSummary.Text = "データがまだ読み込まれていません。「1. データの読み込み」から始めてください。";
            elseif isempty(methods)
                c.runSummary.Text = "比べる手法が選ばれていません。「2. 評価の設定」で手法を選んでください。";
            else
                c.runSummary.Text = "これから計算する組み合わせ：" + text + "。";
            end
            refreshMeasurementChoices(app);
        end

        function refreshMeasurementChoices(app)
            % 計測マップの Wafer・学習パターンの選択肢を、データと設定に合わせる。設定が変わったら描いた図を消す
            c = app.Controls;
            if ~isfield(c, 'measurePlan')
                return
            end
            labels = "—";
            try
                specs = alignest.buildPlanSpecs(app.Settings.sampling);
                labels = unique(string({specs.label}), 'stable');
            catch
                % 設定が正しくないときは選べない（「2. 評価の設定」に理由が出る）
            end
            if ~isequal(string(c.measurePlan.Items), labels)
                previous = string(c.measurePlan.Value);
                c.measurePlan.Items = cellstr(labels);
                kept = previous(ismember(previous, labels));
                if isempty(kept)
                    kept = labels(1);
                end
                c.measurePlan.Value = cellstr(kept);
            end
            units = "—";
            if ~isempty(app.Data)
                units = string({app.Data.units.label});
            end
            if ~isequal(string(c.measureWafer.Items), units)
                c.measureWafer.Items = cellstr(units);
                c.measureWafer.ItemsData = num2cell(1:numel(units));
                c.measureWafer.Value = {1};
            end
            signature = {app.Settings.sampling, app.Settings.data.waferRadiusMm, numel(app.Data)};
            if ~isequaln(signature, c.measurePanel.UserData)
                app.MeasurementCache = [];
                if ~isempty(c.measurePanel.Children)
                    clearMeasurePanel(app);
                    c.measureInfo.Value = {'設定またはデータが変わりました。「計測マップを作る」で作り直してください。'};
                end
                c.measurePanel.UserData = signature;
            end
            overlayNow = fieldOr(app.Settings, "overlay", struct());
            if ~isempty(c.measureComponents.Data) && ~isequaln(c.measureComponents.UserData, overlayNow)
                c.measureComponents.Data = cell(0, 6);   % Overlay 補正の設定を変えた：成分の差は作り直す
            end
        end

        function lines = measurementLines(app, unit, plan)
            % 計測マップの説明（Shot 数・計測率・必ず計測した数・I 基準・D 基準・shotNo・メモ）
            nCandidates = nnz(unit.shots.nValidX + unit.shots.nValidY > 0);
            if ~isempty(plan.markIndex)
                % Mark 単位の計画：計測する Mark の数と、Mark 番号ごとの数（全計測での割合と比べる）
                marks = unit.marks;
                candidateMarks = ismember(marks.shotIndex, find(unit.shots.nValidX + unit.shots.nValidY > 0)) & ...
                    (marks.validX | marks.validY);
                levels = unique(marks.markNo(candidateMarks)).';
                shares = string(arrayfun(@(level) sprintf("M%d %d（全計測 %.0f%%）", level, ...
                    nnz(marks.markNo(plan.markIndex) == level), 100 * nnz(marks.markNo(candidateMarks) == level) / ...
                    nnz(candidateMarks)), levels, 'UniformOutput', false));
                lines = sprintf(['%s｜%s｜計測 %d / 候補 %d Mark（計測率 %.1f%%）｜%s｜I 基準 %.4g・' ...
                    'D 基準 %.4g｜全計測に対する I 効率 %.1f%%・D 効率 %.1f%%｜制約の違反量 %d'], unit.label, plan.label, ...
                    numel(plan.markIndex), nnz(candidateMarks), 100 * numel(plan.markIndex) / max(nnz(candidateMarks), 1), ...
                    markShotText(unit, plan, nCandidates), plan.criterionI, plan.criterionD, 100 * plan.efficiencyI, ...
                    100 * plan.efficiencyD, plan.violation);
                lines = [lines; "Mark 番号ごとの計測数：" + strjoin(shares, "、")];
                if plan.message ~= ""
                    lines = [lines; "メモ：" + plan.message];
                end
                return
            end
            lines = sprintf(['%s｜%s｜計測 %d / 候補 %d Shot（計測率 %.1f%%）｜必ず計測 %d Shot｜I 基準 %.4g・D 基準 %.4g' ...
                '｜全計測に対する I 効率 %.1f%%・D 効率 %.1f%%'], unit.label, plan.label, plan.nShots, nCandidates, ...
                100 * plan.nShots / max(nCandidates, 1), numel(plan.requiredShotIndex), plan.criterionI, plan.criterionD, ...
                100 * plan.efficiencyI, 100 * plan.efficiencyD);
            if any(plan.type == ["ioptimal", "doptimal", "random"])
                lines = lines + sprintf("｜制約の違反量 %d", plan.violation);
            end
            lines = [lines; "計測する shotNo：" + strjoin(string(plan.shotNos(:).'), " ")];
            if plan.message ~= ""
                lines = [lines; "メモ：" + plan.message];
            end
        end

        function layout = resetMeasurePanel(app, nPanels)
            % 計測マップの枠を空にし、nPanels 枚を並べる tiledlayout を作る（枠の縦横に合わせ、1枚が最も大きくなる並べ方）
            clearMeasurePanel(app);
            [nRows, nColumns] = tileShape(app.Controls.measurePanel, nPanels);
            layout = tiledlayout(app.Controls.measurePanel, nRows, nColumns, 'TileSpacing', 'compact', 'Padding', 'compact');
        end

        function clearMeasurePanel(app)
            % 描いた計測マップを消す（枠の中の tiledlayout と図）と、全計測との成分・統計量の差の表を空にする
            delete(app.Controls.measurePanel.Children);
            app.Controls.measureAxes = gobjects(1, 0);
            app.Controls.measureComponents.Data = cell(0, 6);
            app.Controls.measureStatistics.Data = cell(0, 8);
        end

        function [excludedShots, requiredMarks, excludedMarks] = selectionMarks(app, unit, plan)
            % 計測マップに描く指定：計測しない Shot・Mark と、必ず計測する Mark（Mark 単位の学習パターンでは、Wafer 中心に
            % 最も近い Mark・必ず計測する Shot の Mark も。alignest.markPlanFixedMarks）。unit.shots・unit.marks の何番目か
            excludedShots = zeros(0, 1);
            requiredMarks = zeros(0, 1);
            excludedMarks = zeros(0, 1);
            try
                [fixedMarks, fixedInfo] = alignest.markPlanFixedMarks(unit, app.Settings.sampling);
            catch
                return   % 指定の文字が正しくないときは描かない（「2. 評価の設定」の欄の下に理由）
            end
            selection = fixedInfo.selection;
            excludedShots = selection.excludedShots;
            if isempty(plan.markIndex)
                return
            end
            excludedMarks = setdiff(selection.excludedMarks, find(ismember(unit.marks.shotIndex, excludedShots)));
            requiredMarks = fixedMarks(:);
            excludedMarks = excludedMarks(:);
        end

        function onMeasureMapClicked(app, ~, event, unitIndex, markLevel)
            % 計測マップのクリック：「クリックで」の指定で、クリックした Shot（Mark 単位の図では最も近い Mark）を
            % 必ず計測・計測しない・指定を外すにして、計測マップを作り直す
            mode = string(app.Controls.measureClickMode.Value);
            if mode == "none" || isempty(event)
                return
            end
            unit = app.Data.units(unitIndex);
            point = event.IntersectionPoint(1:2);
            if markLevel
                marks = unit.marks;
                [distance, nearest] = min(hypot(marks.x - point(1), marks.y - point(2)));
                if distance > max(unit.shotSizeMm) / 2
                    return   % Mark から離れた所（Wafer の外など）
                end
                key = sprintf("%d-%d", marks.shotNo(nearest), marks.markNo(nearest));
                runWithAlert(app, @() app.setMeasurementSelection("mark", key, mode), "指定できませんでした", ...
                    "「2. 評価の設定」の学習 Shot の選び方を確かめてください。");
            else
                shots = unit.shots;
                inside = abs(shots.Xmm - point(1)) <= unit.shotSizeMm(1) / 2 & abs(shots.Ymm - point(2)) <= unit.shotSizeMm(2) / 2;
                if ~any(inside)
                    return
                end
                runWithAlert(app, @() app.setMeasurementSelection("shot", shots.shotNo(find(inside, 1)), mode), ...
                    "指定できませんでした", "「2. 評価の設定」の学習 Shot の選び方を確かめてください。");
            end
        end

        function onClearMeasureSelections(app)
            % 計測マップで指定した Shot・Mark（必ず計測・計測しない）をすべて外す
            app.Settings.sampling.requiredShots = zeros(1, 0);
            app.Settings.sampling.excludedShots = zeros(1, 0);
            app.Settings.sampling.requiredMarks = strings(1, 0);
            app.Settings.sampling.excludedMarks = strings(1, 0);
            selectionChanged(app);
        end

        function selectionChanged(app)
            % 指定を変えた後：「2. 評価の設定」の欄と指定の一覧を直し、計測マップを描いてあれば作り直す
            c = app.Controls;
            hadMap = hasMeasurementMap(app);   % 設定を直すと図は消えるので、先に覚える
            c.requiredShots.Value = char(strjoin(string(app.Settings.sampling.requiredShots), " "));
            c.excludedShots.Value = char(strjoin(string(app.Settings.sampling.excludedShots), " "));
            c.requiredMarks.Value = char(strjoin(string(app.Settings.sampling.requiredMarks), " "));
            c.excludedMarks.Value = char(strjoin(string(app.Settings.sampling.excludedMarks), " "));
            validateSettings(app);
            updateEnabled(app);
            refreshRunSummary(app);
            refreshMeasureSelectionInfo(app);
            if hadMap
                drawMeasurementMap(app);
            end
        end

        function refreshMeasureSelectionInfo(app)
            % 計測の指定の一覧（必ず計測する Shot・計測しない Shot・必ず計測する Mark・計測しない Mark）
            sampling = app.Settings.sampling;
            items = ["必ず計測する Shot", "計測しない Shot", "必ず計測する Mark", "計測しない Mark"];
            values = {string(fieldOr(sampling, "requiredShots", zeros(1, 0))), ...
                string(fieldOr(sampling, "excludedShots", zeros(1, 0))), ...
                string(fieldOr(sampling, "requiredMarks", strings(1, 0))), ...
                string(fieldOr(sampling, "excludedMarks", strings(1, 0)))};
            lines = strings(0, 1);
            for k = 1:numel(items)
                if ~isempty(values{k})
                    lines(end + 1, 1) = sprintf("%s（%d）：%s", items(k), numel(values{k}), strjoin(values{k}, " ")); %#ok<AGROW>
                end
            end
            if isempty(lines)
                lines = "（なし）";
            end
            app.Controls.measureSelectionInfo.Value = cellstr(lines);
        end

        function showMeasureComponents(app, rows, components, panelHeader)
            % 全計測との成分の差の表（図ごとに、項のある成分と合計の行。1列目の見出しは panelHeader）。使った Overlay 補正の
            % 設定を覚えておき、変えたら空にする
            c = app.Controls;
            if isempty(rows)
                rows = cell(0, 6);
            end
            names = reshape(cellstr(c.measureComponents.ColumnName), 1, []);
            names{1} = char(panelHeader);
            c.measureComponents.ColumnName = names;
            c.measureComponents.Data = rows;
            c.measureComponents.UserData = fieldOr(app.Settings, "overlay", struct());
            if ~isempty(components)
                c.measureComponents.Tooltip = ['全計測との成分の差（補正モデル：' char(components(1).description) '）。' ...
                    '全計測：全計測で求めた成分の補正量の |平均|+3σ。差：計測配置の点で求めた成分 − 全計測で求めた成分 の ' ...
                    '|平均|+3σ。どちらも全計測の Mark の位置で求めます（詳しくは「ヘルプ」）。'];
            end
        end
    end
end

% ================= このファイルだけで使う小さな関数 =================
function text = durationText(seconds)
if ~isfinite(seconds)
    text = "—";
elseif seconds < 60
    text = sprintf("%.0f 秒", max(seconds, 1));
elseif seconds < 3600
    text = sprintf("%.0f 分", seconds / 60);
else
    text = sprintf("%.1f 時間", seconds / 3600);
end
end

function [required, excluded] = applySelection(required, excluded, target, mode)
% 指定の一覧を変える：必ず計測（計測しないから外す）・計測しない（必ず計測から外す）・外す（どちらからも外す）
required = required(required ~= target);
excluded = excluded(excluded ~= target);
switch mode
    case "required"
        required(end + 1) = target;
    case "excluded"
        excluded(end + 1) = target;
    case "clear"
    otherwise
        error('alignest:measurementSelection', '指定は required・excluded・clear のいずれかです: %s', mode);
end
end

function rows = statisticTableRows(panelLabel, statistics)
% 全計測との統計量の差の表の行（統計量ごと。値は有効数字3桁の文字）
n = height(statistics);
rows = cell(n, 8);
format = '%.3g';
for r = 1:n
    rows(r, :) = {char(panelLabel), char(statistics.statistic(r)), numberText(statistics.fullX(r), format), ...
        numberText(statistics.fullY(r), format), numberText(statistics.planX(r), format), ...
        numberText(statistics.planY(r), format), numberText(statistics.differenceX(r), format), ...
        numberText(statistics.differenceY(r), format)};
end
end

function rows = componentTableRows(panelLabel, summary)
% 全計測との成分の差の表の行（項のある成分と合計。値は有効数字3桁の文字）
present = ~(isnan(summary.sizeX) & isnan(summary.sizeY));
summary = summary(present, :);
n = height(summary);
rows = cell(n, 6);
for r = 1:n
    rows(r, :) = {char(panelLabel), char(summary.component(r)), numberText(summary.sizeX(r), '%.3g'), ...
        numberText(summary.sizeY(r), '%.3g'), numberText(summary.differenceX(r), '%.3g'), ...
        numberText(summary.differenceY(r), '%.3g')};
end
end

function cache = estimateCache(results)
% 評価で求めた評価点の推定値（results.pointEstimates）を、マップ・散布図・推定値の表で使い回す記憶に入れる
% （キーは 'Wafer|学習パターン|手法' の番号。推定をやり直さずに描ける）
cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
if ~isfield(results, "pointEstimates")
    return
end
table_ = results.table;
for k = 1:height(table_)
    if ~isempty(results.pointEstimates{k})
        cache(sprintf('%d|%d|%d', table_.unitIndex(k), table_.planIndex(k), table_.methodIndex(k))) = ...
            results.pointEstimates{k};
    end
end
end
