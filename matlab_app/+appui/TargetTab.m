classdef (Abstract) TargetTab < appui.Core
    %TARGETTAB 「6. 未知の座標の推定」タブ：推定する点の表、推定、重ね合わせ補正値、補正残差のマップ、書き出し。
    %   AlignmentEstimationApp（画面の本体）の一部。画面の部品は Controls、データ・結果は Core のプロパティに持つ。
    %   ほかのタブの関数も同じように呼べる（どれも AlignmentEstimationApp の関数になる）。

    methods
        function targets = setTargetPoints(app, targets)
            %SETTARGETPOINTS 「6. 未知の座標の推定」の表を targets（alignest.targetTemplate の形）にする。
            app.Controls.targetTable.Data = targetCells(targets);
            app.TargetSelection = zeros(0, 1);
            onTargetEdited(app);
        end

        function targets = loadTargetPoints(app, filePath, sheetName)
            %LOADTARGETPOINTS 未知の座標の表（Excel・CSV）を読み、推定する点の表を置き換える（alignest.readTargetPoints）。
            if nargin < 3
                sheetName = "";
            end
            [targets, info] = alignest.readTargetPoints(filePath, sheetName);
            setTargetPoints(app, targets);
            sheetText = "";
            if info.sheet ~= ""
                sheetText = "（シート「" + info.sheet + "」）";
            end
            app.Controls.targetInfo.Text = sprintf('%s%s から %d 点を読み込みました。', info.file, sheetText, height(targets)) + ...
                " " + app.Controls.targetInfo.Text;
        end

        function targets = addTargetPoints(app, kind, varargin)
            %ADDTARGETPOINTS 推定する点の表に点を足す。
            %   addTargetPoints(app, "shots", markXmm, markYmm, markNo)  % 全 Shot の同じ位置（Shot は「Wafer」で選んだ
            %                                                           % Wafer、複数なら最初の Wafer の並び）
            %   addTargetPoints(app, "grid", pitchMm, radiusMm)         % Wafer 上の格子
            %   addTargetPoints(app, "row")                             % 空の1行（画面で書き込む）
            c = app.Controls;
            existing = size(c.targetTable.Data, 1);
            switch string(kind)
                case "shots"
                    if isempty(app.Data)
                        error('alignest:noData', '先に「1. データの読み込み」で計測データを読み込んでください（Shot の並びを使います）。');
                    end
                    selected = cell2mat(c.targetWafer.Value);
                    if isempty(selected)
                        selected = 1;
                    end
                    added = alignest.targetsAtShots(app.Data.units(selected(1)), varargin{:});
                case "grid"
                    added = alignest.targetGrid(varargin{:});
                case "row"
                    added = alignest.targetTemplate(1);
                    added.name = "P" + string(existing + 1);
                otherwise
                    error('alignest:targetKind', '点の足し方は shots・grid・row のどれかです: %s', kind);
            end
            c.targetTable.Data = [c.targetTable.Data; targetCells(added)];
            onTargetEdited(app);
            targets = added;
        end

        function run = estimateTargets(app, unitChoice, trainingChoice, methodIndex)
            %ESTIMATETARGETS 「6. 未知の座標の推定」：表の点の推定値を、選んだ Wafer × 学習データの組み合わせごとに
            %   まとめて求め、表・図・メッセージに出す。
            %   unitChoice：Wafer の番号（複数可。0 = すべての Wafer）、trainingChoice："all"（計測値のある全 Mark）または
            %   評価の学習パターンの名前（複数可）、methodIndex：手法の番号（alignest.activeMethods(app.Settings) の何番目か）。
            %   省略すると画面で選んでいるもの。推定は alignest.predictTargets（評価と同じ推定、条件は今の設定）。
            %   300 mm Wafer の外の点は推定の対象外（推定値は X・Y とも 0。図には描かない）。
            if isempty(app.Data)
                error('alignest:noData', '先に「1. データの読み込み」で計測データを読み込んでください。');
            end
            refreshTargetChoices(app);
            c = app.Controls;
            if nargin >= 2
                if isequal(unitChoice, 0)
                    unitChoice = 1:numel(app.Data.units);
                end
                c.targetWafer.Value = num2cell(reshape(unitChoice, 1, []));
            end
            if nargin >= 3
                c.targetTraining.Value = cellstr(string(trainingChoice));
            end
            if nargin >= 4
                c.targetMethod.Value = methodIndex;
            end
            targets = currentTargets(app);
            methods = alignest.activeMethods(app.Settings);
            if isempty(methods)
                error('alignest:noMethods', '手法がありません。「2. 評価の設定」で比べる手法を選んでください。');
            end
            method = methods(c.targetMethod.Value);
            units = cell2mat(c.targetWafer.Value);
            trainings = string(c.targetTraining.Value);
            if isempty(units) || isempty(trainings)
                error('alignest:targetChoice', 'Wafer と学習データを1つ以上選んでください。');
            end
            app.Figure.Pointer = 'watch';
            drawnow;
            restore = onCleanup(@() set(app.Figure, 'Pointer', 'arrow'));
            nCombinations = numel(units) * numel(trainings);
            parts = cell(nCombinations, 1);
            results = cell(1, nCombinations);
            [unitIndex, trainingTexts, labels] = deal(zeros(1, nCombinations), strings(1, nCombinations), ...
                strings(1, nCombinations));
            trainingKeys = strings(1, nCombinations);
            combination = 0;
            for u = 1:numel(units)
                unit = app.Data.units(units(u));
                for t = 1:numel(trainings)
                    combination = combination + 1;
                    [plan, trainingText] = targetTraining(app, units(u), trainings(t));
                    results{combination} = alignest.predictTargets(unit, plan, method, app.Settings, targets);
                    rows = results{combination}.table;
                    rows = addvars(rows, repmat(unit.label, height(rows), 1), repmat(trainingText, height(rows), 1), ...
                        repmat(combination, height(rows), 1), 'Before', 1, ...
                        'NewVariableNames', ["wafer", "training", "combination"]);
                    parts{combination} = rows;
                    unitIndex(combination) = units(u);
                    trainingKeys(combination) = trainings(t);
                    trainingTexts(combination) = trainingText;
                    labels(combination) = unit.label + "｜" + trainingText;
                end
            end
            estimates = vertcat(parts{:});
            app.TargetRun = struct("estimates", estimates, "results", {results}, "unitIndex", unitIndex, ...
                "training", trainingKeys, "trainingTexts", trainingTexts, "labels", labels, "method", method, ...
                "messages", targetMessages(results, estimates, labels), "stale", false, "overlay", {cell(1, nCombinations)}, ...
                "overlayModel", []);
            showTargetRun(app);
            run = app.TargetRun;
        end

        function overlay = computeTargetOverlay(app)
            %COMPUTETARGETOVERLAY 最後に推定した未知の座標の推定値を使って、組み合わせ（Wafer × 学習データ）ごとに
            %   重ね合わせ（Overlay）補正値を求め、「重ね合わせ補正」のタブに出す（alignest.targetOverlayCorrection）。
            %   補正に使う点は、元の実測値（学習点）・学習しなかった Mark の推定値・未知の座標の推定値（Wafer の外の点を
            %   除く）。補正モデルは今の設定（「2. 評価の設定」の Overlay 補正）。overlay は組み合わせごとの結果の cell。
            run = app.TargetRun;
            if isempty(run)
                error('alignest:noTargets', '先に「推定する」を押して、未知の座標を推定してください。');
            end
            if alignest.valueSpec(app.Settings.data).scalar
                error('alignest:overlayScalar', '重ね合わせ補正は X・Y の2成分が要ります（1変数の推定では計算できません）。');
            end
            app.Figure.Pointer = 'watch';
            drawnow;
            restore = onCleanup(@() set(app.Figure, 'Pointer', 'arrow'));
            overlay = cell(1, numel(run.results));
            for k = 1:numel(run.results)
                unitIndex = run.unitIndex(k);
                plan = targetTraining(app, unitIndex, run.training(k));
                overlay{k} = alignest.targetOverlayCorrection(app.Data.units(unitIndex), plan, run.method, app.Settings, ...
                    run.results{k}.table);
            end
            app.TargetRun.overlay = overlay;
            app.TargetRun.overlayModel = app.Settings.overlay;   % 後でモデルを変えたら、計算し直すよう知らせる
            showTargetOverlay(app);
        end

        function summary = drawTargetCorrectionMap(app, value, source, mode)
            %DRAWTARGETCORRECTIONMAP 「補正残差のマップ」：選んだ組み合わせの重ね合わせ補正の補正後の残差（または補正量・
            %   補正前の値）を Wafer 上のベクトル・色で描く（alignest.plot.correctionMap）。
            %   value："residual"・"correction"・"value"、source："all"・"target"・"measured"・"estimated"、
            %   mode："vector"・"X"・"Y"。省略すると画面の選択。summary は描いた点の数と |平均| + 3σ（補正値が無ければ []）。
            c = app.Controls;
            if nargin >= 2
                c.targetResidualValue.Value = char(value);
            end
            if nargin >= 3
                c.targetResidualSource.Value = char(source);
            end
            if nargin >= 4
                c.targetResidualMode.Value = char(mode);
            end
            summary = [];
            run = app.TargetRun;
            correction = [];
            if ~isempty(run) && isfield(run, 'overlay')
                position = min(max(c.targetCombination.Value, 1), numel(run.results));
                correction = run.overlay{position};
            end
            if isempty(correction)
                cla(c.targetResidualAxes, 'reset');
                legend(c.targetResidualAxes, 'off');
                set([c.targetResidualSave, c.targetResidualCopy], 'Enable', 'off');
                c.targetResidualInfo.Text = ['推定した後に「重ね合わせ補正値を計算する」を押すと、補正後の残差を Wafer 上の' ...
                    'ベクトルで描きます（四角は実測値の点、◇ は未知の座標の点）。'];
                return
            end
            unit = app.Data.units(run.unitIndex(position));
            % 題名は短く（|平均|+3σ は下の欄に出す。題名が長いと色の目盛りの名前と重なる）
            summary = alignest.plot.correctionMap(c.targetResidualAxes, correction, unit, ...
                value=string(c.targetResidualValue.Value), source=string(c.targetResidualSource.Value), ...
                mode=string(c.targetResidualMode.Value), titleText=unit.label, showStatistics=false, ...
                legendLocation="eastoutside", ...
                waferRadiusMm=app.Settings.data.waferRadiusMm);
            styleAxes(app, c.targetResidualAxes, app.AXES_FONT_SIZE);
            set([c.targetResidualSave, c.targetResidualCopy], 'Enable', 'on');
            info = run.labels(position) + "｜" + summary.valueLabel + sprintf("：%d 点、|平均|+3σ X %.3f nm・Y %.3f nm", ...
                summary.n, summary.meanPlus3SigmaX, summary.meanPlus3SigmaY) + "（四角は実測値の点、◇ は未知の座標の点）";
            c.targetResidualInfo.Tooltip = char("補正モデル：" + correction.description);
            c.targetResidualInfo.Text = char(staleOverlayText(app) + info);
        end

        function exportTargetsTo(app, filePath)
            %EXPORTTARGETSTO 最後に推定した未知の座標の推定値を Excel に書き出す（alignest.exportTargetEstimates）。
            %   重ね合わせ補正値（補正値（係数）・補正の残差・補正に使った点のシートと、「推定値」シートの点ごとの補正量・
            %   補正後の残差）も書く。まだ計算していない、または計算した後に補正モデルを変えたときは、書き出す前に今の
            %   補正モデルで計算する（補正モデルが「なし」・1変数・式の誤りのときは補正値を書かず、「説明」に理由を書く）。
            if isempty(app.TargetRun)
                error('alignest:noTargets', '書き出す推定値がありません。先に「推定する」を押してください。');
            end
            overlayNote = targetOverlayForExport(app);
            run = app.TargetRun;
            labels = unique(string({app.Data.units(run.unitIndex).label}), 'stable');
            evaluation = app.Settings.evaluation;
            conditions = sprintf('XY 1次を除く：%s、学習データの異常値の除外：%s', onOffText(evaluation.removeLinear), ...
                onOffText(evaluation.excludeOutliers));
            notes = ["Wafer", strjoin(labels, "・"); "学習データ", strjoin(unique(run.trainingTexts, 'stable'), "・"); ...
                "手法", run.method.label + "（" + run.method.id + "）"; "推定の条件", conditions; ...
                "画面のメッセージ", strjoin(run.messages, " "); "重ね合わせ補正", overlayNote];
            overlay = struct("labels", run.labels, "results", {run.overlay});
            alignest.exportTargetEstimates(filePath, run.estimates, notes, alignest.valueSpec(app.Settings.data), overlay);
        end
    end

    methods (Access = {?appui.Core})
        % ================= 6. 未知の座標の推定 =================
        function buildTargetTab(app)
            % 左：推定する点（未知の座標）の表と、その作り方。右：推定の条件・メッセージ・図・推定値の表
            grid = uigridlayout(app.Tabs.target, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 12, 'RowSpacing', 8);
            label(grid, ['学習データ（計測値）から、計測していない座標（新しい Mark の位置・Wafer 上の任意の点）の値を推定します。' ...
                '左の表で点を決め（Excel・CSV から読み込むか、画面で入力・作成）、右で Wafer・学習データ・手法を選んで' ...
                '「推定する」を押します。学習点の範囲の外（外挿）になる点は、右のメッセージと表・図で知らせます。'], 1, 1);
            % 左の幅は狭めない（点を作るボタン・欄が横に並んでいて、狭めると右の方が隠れるため）
            body = uigridlayout(grid, [1, 2], 'ColumnWidth', {610, '1x'}, 'Padding', 0, 'ColumnSpacing', 14);
            left = uigridlayout(body, [6, 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit', 'fit'}, ...
                'Padding', 0, 'RowSpacing', 6);
            place(uilabel(left, 'Text', '① 推定する点（未知の座標）', 'FontWeight', 'bold'), 1, 1);
            buttons = uigridlayout(left, [1, 4], 'ColumnWidth', {'fit', 'fit', 'fit', 'fit'}, 'Padding', 0);
            c.targetLoad = uibutton(buttons, 'Text', 'Excel・CSV から読み込む…', 'ButtonPushedFcn', @(~, ~) app.onLoadTargets(), ...
                'Tooltip', ['1行目が見出し（Xmm・Ymm は必須。markXmm・markYmm・markNo・shotNo・Direction・名前 は任意）の表を' ...
                '読み、下の表を置き換えます。「未知の座標」シートがあればそれを読みます。']);
            c.targetAddRow = uibutton(buttons, 'Text', '行を追加', 'ButtonPushedFcn', @(~, ~) app.onAddTargets("row"));
            c.targetDeleteRows = uibutton(buttons, 'Text', '選んだ行を削除', 'ButtonPushedFcn', @(~, ~) app.onDeleteTargetRows());
            c.targetClear = uibutton(buttons, 'Text', 'すべて消す', 'ButtonPushedFcn', @(~, ~) app.setTargetPoints( ...
                alignest.targetTemplate()));
            % 点の作り方：全 Shot の同じ位置（新しい Mark の位置など）・Wafer 上の格子（Wafer 全面）
            makers = uigridlayout(left, [2, 8], 'ColumnWidth', {'fit', 'fit', 55, 'fit', 55, 'fit', 45, 'fit'}, ...
                'RowHeight', {'fit', 'fit'}, 'Padding', 0, 'ColumnSpacing', 8);
            label(makers, '全 Shot に置く [mm]', 1, 1);
            label(makers, 'X', 1, 2);
            c.targetShotX = uieditfield(makers, 'numeric', 'Value', 0, 'Tooltip', 'Shot 中心から見た X [mm]（markXmm）');
            place(c.targetShotX, 1, 3);
            label(makers, 'Y', 1, 4);
            c.targetShotY = uieditfield(makers, 'numeric', 'Value', 0, 'Tooltip', 'Shot 中心から見た Y [mm]（markYmm）');
            place(c.targetShotY, 1, 5);
            label(makers, 'Mark 番号', 1, 6);
            c.targetShotMark = uieditfield(makers, 'text', 'Value', '', 'Tooltip', ['空欄でもよい（Mark 番号の効果は平均）。' ...
                '学習データに無い番号でもよい（新しい Mark）。']);
            place(c.targetShotMark, 1, 7);
            c.targetAddShots = uibutton(makers, 'Text', '表に追加', 'ButtonPushedFcn', @(~, ~) app.onAddTargets("shots"), ...
                'Tooltip', '右で選んだ Wafer（すべてなら最初の Wafer）の全 Shot の、同じ位置に点を置きます。');
            place(c.targetAddShots, 1, 8);
            label(makers, '格子で置く [mm]', 2, 1);
            label(makers, '間隔', 2, 2);
            c.targetPitch = uieditfield(makers, 'numeric', 'Value', app.TARGET_GRID_PITCH_MM, 'Limits', [0, Inf], ...
                'LowerLimitInclusive', 'off', 'Tooltip', '格子の点の間隔 [mm]');
            place(c.targetPitch, 2, 3);
            label(makers, '半径', 2, 4);
            c.targetRadius = uieditfield(makers, 'numeric', 'Value', app.TARGET_GRID_RADIUS_MM, 'Limits', [0, Inf], ...
                'LowerLimitInclusive', 'off', 'Tooltip', 'Wafer の中心からこの半径 [mm] 以内に置く');
            place(c.targetRadius, 2, 5);
            c.targetAddGrid = uibutton(makers, 'Text', '表に追加', 'ButtonPushedFcn', @(~, ~) app.onAddTargets("grid"), ...
                'Tooltip', 'Wafer の中心から半径以内に、間隔ごとの格子の点を置きます（Wafer 全面の推定値を見るとき）。');
            place(c.targetAddGrid, 2, 8);
            c.targetTable = uitable(left, 'ColumnName', app.TARGET_COLUMNS, 'ColumnEditable', true, 'RowName', 'numbered', ...
                'Data', cell(0, numel(app.TARGET_COLUMNS)), 'ColumnFormat', repmat({'char'}, 1, numel(app.TARGET_COLUMNS)), ...
                'ColumnWidth', [{76}, repmat({66}, 1, numel(app.TARGET_COLUMNS) - 1)], ...
                'CellEditCallback', @(~, ~) app.onTargetEdited(), ...
                'CellSelectionCallback', @(~, event) app.onTargetSelected(event));
            place(c.targetTable, 4, 1);
            c.targetInfo = uilabel(left, 'WordWrap', 'on', 'FontColor', app.Palette.muted, 'Text', '');
            place(c.targetInfo, 5, 1);
            c.targetError = errorLabel(app, left, 6, 1);

            % 右：条件（Wafer・学習データは複数選べる・手法）、メッセージ、結果（図・推定値の表・重ね合わせ補正を中のタブで
            % 切り替える。Wafer × 学習データの組み合わせごとに推定し、図と補正は「組み合わせ」で選んだものを出す）
            right = uigridlayout(body, [5, 1], 'RowHeight', {'fit', 'fit', app.TARGET_MESSAGE_HEIGHT, 'fit', '1x'}, ...
                'Padding', 0, 'RowSpacing', 6);
            place(uilabel(right, 'Text', '② 推定の条件と結果', 'FontWeight', 'bold'), 1, 1);
            controls = uigridlayout(right, [3, 3], 'ColumnWidth', {'1x', '1.2x', '1.6x'}, ...
                'RowHeight', {'fit', app.TARGET_LIST_HEIGHT, 'fit'}, 'Padding', 0);
            label(controls, 'Wafer（複数選べる）', 1, 1);
            label(controls, '学習データ（複数選べる）', 1, 2);
            label(controls, '手法', 1, 3);
            c.targetWafer = uilistbox(controls, 'Items', {'—'}, 'ItemsData', {1}, 'Multiselect', 'on', 'Value', {1}, ...
                'Tooltip', ['推定する Wafer（Ctrl・Shift を押しながらクリックで複数。Ctrl + A ですべて）。' ...
                '選んだ Wafer × 学習データの組み合わせごとに、まとめて推定します。']);
            place(c.targetWafer, 2, 1);
            c.targetTraining = uilistbox(controls, 'Items', {'計測値のある全 Mark（全 Shot）'}, ...
                'ItemsData', {char(app.TARGET_ALL_TRAINING)}, 'Multiselect', 'on', 'Value', {char(app.TARGET_ALL_TRAINING)}, ...
                'Tooltip', ['計測値のある全 Mark：読み込んだ計測値をすべて学習に使います。学習パターン：評価で選んだ ' ...
                'Shot（Mark）だけを学習に使います（「3. 実行」で評価した後に選べます）。複数選ぶと、まとめて推定します。']);
            place(c.targetTraining, 2, 2);
            methodGrid = uigridlayout(controls, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 0);
            place(methodGrid, 2, 3);
            c.targetMethod = uidropdown(methodGrid, 'Items', {'—'}, 'ItemsData', {1}, ...
                'Tooltip', '「2. 評価の設定」で選んだ手法から選びます。推定の条件（1次を除く・異常値の除外）も今の設定のとおりです。');
            place(c.targetMethod, 1, 1);
            actions = uigridlayout(controls, [1, 3], 'ColumnWidth', {160, 'fit', 'fit'}, 'Padding', 0);
            place(actions, 3, [1, 3]);
            c.targetRun = primaryButton(app, actions, '推定する', @(~, ~) app.onEstimateTargets());
            c.targetOverlayButton = uibutton(actions, 'Text', '重ね合わせ補正値を計算する', ...
                'ButtonPushedFcn', @(~, ~) app.onTargetOverlay(), 'Tooltip', ['推定した後に、元の実測値（学習点）・' ...
                '学習しなかった Mark の推定値・未知の座標の推定値をまとめて、「2. 評価の設定」の Overlay 補正の' ...
                'モデル（Wafer 成分・Shot 共通成分・Shot ごとの成分）を当てはめ、補正値（係数）と補正後の残差を求めます。']);
            c.targetExport = uibutton(actions, 'Text', '推定値を Excel に書き出す…', ...
                'ButtonPushedFcn', @(~, ~) app.onExportTargets());
            % メッセージは高さを決めた欄に出す（組み合わせが多くて長くなっても、下の図の場所を取らないように）
            c.targetMessage = uitextarea(right, 'Editable', 'off', 'FontWeight', 'bold', 'Value', ...
                {'「1. データの読み込み」で計測データを読み込み、左の表に推定する点を決めてから「推定する」を押してください。'});
            place(c.targetMessage, 3, 1);
            combinationGrid = uigridlayout(right, [1, 2], 'ColumnWidth', {'fit', '1x'}, 'Padding', 0);
            place(combinationGrid, 4, 1);
            label(combinationGrid, '図・補正に出す組み合わせ', 1, 1);
            c.targetCombination = uidropdown(combinationGrid, 'Items', {'—（推定すると選べます）'}, 'ItemsData', {1}, ...
                'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.showTargetCombination(), ...
                'Tooltip', '推定した Wafer × 学習データの組み合わせ。図と「重ね合わせ補正」のタブに、選んだ組み合わせを出します。');
            place(c.targetCombination, 1, 2);
            outputs = uitabgroup(right);
            place(outputs, 5, 1);
            figureTab = uitab(outputs, 'Title', '図');
            figureGrid = uigridlayout(figureTab, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 6, 'RowSpacing', 4);
            figureControls = uigridlayout(figureGrid, [1, 4], 'ColumnWidth', {'fit', 140, 'fit', 'fit'}, 'Padding', 0);
            label(figureControls, '表示', 1, 1);
            c.targetMode = uidropdown(figureControls, 'Items', {'ベクトル（矢印）', 'X（色）', 'Y（色）'}, ...
                'ItemsData', {'vector', 'X', 'Y'}, 'ValueChangedFcn', @(~, ~) app.drawTargetMap());
            place(c.targetMode, 1, 2);
            c.targetSaveFigure = uibutton(figureControls, 'Text', '図を画像で保存…', ...
                'ButtonPushedFcn', @(~, ~) app.onSaveTargetFigure());
            place(c.targetSaveFigure, 1, 3);
            c.targetCopyFigure = uibutton(figureControls, 'Text', '図をコピー', 'Tooltip', app.COPY_TOOLTIP, ...
                'ButtonPushedFcn', @(source, ~) app.onCopyFigure("target", source));
            place(c.targetCopyFigure, 1, 4);
            c.targetPanel = uipanel(figureGrid, 'BorderType', 'none');
            place(c.targetPanel, 2, 1);
            c.targetAxes = uiaxes(uigridlayout(c.targetPanel, [1, 1], 'Padding', 0));
            tableTab = uitab(outputs, 'Title', '推定値の表');
            c.targetResultTable = uitable(uigridlayout(tableTab, [1, 1], 'Padding', 6), 'RowName', {}, 'Data', table());
            % 補正のモデル：「2. 評価の設定」の Overlay 補正と同じ設定を、ここでも変えられる（どちらで変えても同じ）
            modelTab = uitab(outputs, 'Title', '補正のモデル');
            modelGrid = uigridlayout(modelTab, [6, 3], 'RowHeight', repmat({'fit'}, 1, 6), 'ColumnWidth', {'1x', '1x', '1x'}, ...
                'Padding', 6, 'RowSpacing', 4);
            modelNote = label(modelGrid, ['重ね合わせ補正値を求める補正モデル（Wafer 成分 + Shot 共通成分 + Shot ごとの成分）。' ...
                '「2. 評価の設定」の Overlay 補正と同じ設定です（どちらで変えても同じ。評価の Overlay 補正の評価にも使う）。' ...
                '式の書き方は「7. ヘルプ」。'], 1, [1, 3]);
            modelNote.FontColor = app.Palette.muted;
            modelNote.UserData = "muted";
            label(modelGrid, 'Wafer 成分', 2, 1);
            label(modelGrid, 'Shot 共通成分', 2, 2);
            label(modelGrid, 'Shot ごとの成分', 2, 3);
            onModel = @(~, ~) app.onTargetOverlayModelChanged();
            source = app.Controls;   % 「2. 評価の設定」の欄と同じ選択肢にする
            c.targetOverlayWafer = uidropdown(modelGrid, 'Items', source.overlayWafer.Items, ...
                'ItemsData', source.overlayWafer.ItemsData, 'ValueChangedFcn', onModel);
            place(c.targetOverlayWafer, 3, 1);
            c.targetOverlayShotCommon = uidropdown(modelGrid, 'Items', source.overlayShotCommon.Items, ...
                'ItemsData', source.overlayShotCommon.ItemsData, 'ValueChangedFcn', onModel, ...
                'Tooltip', source.overlayShotCommon.Tooltip);
            place(c.targetOverlayShotCommon, 3, 2);
            c.targetOverlayPerShot = uidropdown(modelGrid, 'Items', source.overlayPerShot.Items, ...
                'ItemsData', source.overlayPerShot.ItemsData, 'ValueChangedFcn', onModel, 'Tooltip', source.overlayPerShot.Tooltip);
            place(c.targetOverlayPerShot, 3, 3);
            [c.targetOverlayWaferDx, c.targetOverlayWaferDy] = formulaFields(modelGrid, 4, 1, onModel, ...
                source.overlayWaferDx.Tooltip);
            [c.targetOverlayShotDx, c.targetOverlayShotDy] = formulaFields(modelGrid, 4, 2, onModel, ...
                source.overlayShotDx.Tooltip);
            [c.targetOverlayPerShotDx, c.targetOverlayPerShotDy] = formulaFields(modelGrid, 4, 3, onModel, ...
                source.overlayPerShotDx.Tooltip);
            c.targetOverlayError = errorLabel(app, modelGrid, 5, [1, 3]);
            c.targetOverlayRecompute = uibutton(modelGrid, 'Text', 'このモデルで重ね合わせ補正値を計算する', ...
                'ButtonPushedFcn', @(~, ~) app.onTargetOverlay());
            place(c.targetOverlayRecompute, 6, [1, 2]);
            % 補正値：選んだ組み合わせの補正値（係数）と、点の種類ごとの補正後の残差
            overlayTab = uitab(outputs, 'Title', '補正値');
            overlayGrid = uigridlayout(overlayTab, [3, 1], 'RowHeight', {'fit', '1x', '1.4x'}, 'Padding', 6, 'RowSpacing', 6);
            overlayHeader = uigridlayout(overlayGrid, [1, 2], 'ColumnWidth', {'1x', 'fit'}, 'Padding', 0);
            c.targetOverlayInfo = uilabel(overlayHeader, 'WordWrap', 'on', 'Text', ['推定した後に「重ね合わせ補正値を計算する」を' ...
                '押すと、選んだ組み合わせの補正値（係数）と補正後の残差を出します。']);
            c.targetOverlayExport = uibutton(overlayHeader, 'Text', '補正値を Excel に書き出す…', ...
                'ButtonPushedFcn', @(~, ~) app.onExportTargets(), 'Tooltip', ['推定値と、すべての組み合わせの重ね合わせ' ...
                '補正値（係数・補正の残差・補正に使った点、推定値の表の補正量・補正後の残差）を1つの Excel に書き出します' ...
                '（「推定値を Excel に書き出す…」と同じファイル）。']);
            c.targetOverlaySummary = uitable(overlayGrid, 'RowName', {}, 'Data', table());
            c.targetOverlayTable = uitable(overlayGrid, 'RowName', {}, 'Data', table());
            % 補正残差のマップ：補正後の残差（または補正量・補正前の値）を Wafer 上のベクトル・色で描く
            residualTab = uitab(outputs, 'Title', '補正残差のマップ');
            residualGrid = uigridlayout(residualTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            residualControls = uigridlayout(residualGrid, [1, 8], 'ColumnWidth', {'fit', 120, 'fit', 165, 'fit', 105, 'fit', ...
                'fit'}, ...
                'Padding', 0);
            onResidual = @(~, ~) app.drawTargetCorrectionMap();
            label(residualControls, '値', 1, 1);
            c.targetResidualValue = uidropdown(residualControls, 'Items', {'補正後の残差', '補正量', '補正前の値'}, ...
                'ItemsData', {'residual', 'correction', 'value'}, 'ValueChangedFcn', onResidual, 'Tooltip', ...
                ['補正後の残差 = 値 − 補正量（値は実測値、または推定値）。補正量は補正モデルを当てはめた値、' ...
                '補正前の値は補正に使った値（実測値・推定値）。']);
            place(c.targetResidualValue, 1, 2);
            label(residualControls, '点', 1, 3);
            c.targetResidualSource = uidropdown(residualControls, 'Items', {'すべての点', '未知の座標だけ', ...
                '実測値（学習点）だけ', '学習しなかった Mark の推定値だけ'}, 'ItemsData', {'all', 'target', 'measured', ...
                'estimated'}, 'ValueChangedFcn', onResidual);
            place(c.targetResidualSource, 1, 4);
            label(residualControls, '表示', 1, 5);
            c.targetResidualMode = uidropdown(residualControls, 'Items', {'ベクトル（矢印）', 'X（色）', 'Y（色）'}, ...
                'ItemsData', {'vector', 'X', 'Y'}, 'ValueChangedFcn', onResidual);
            place(c.targetResidualMode, 1, 6);
            c.targetResidualSave = uibutton(residualControls, 'Text', '画像で保存…', ...
                'ButtonPushedFcn', @(~, ~) app.onSaveTargetResidualFigure());
            place(c.targetResidualSave, 1, 7);
            c.targetResidualCopy = uibutton(residualControls, 'Text', 'コピー', 'Tooltip', app.COPY_TOOLTIP, ...
                'ButtonPushedFcn', @(source, ~) app.onCopyFigure("targetResidual", source));
            place(c.targetResidualCopy, 1, 8);
            c.targetResidualPanel = uipanel(residualGrid, 'BorderType', 'none');
            place(c.targetResidualPanel, 2, 1);
            c.targetResidualAxes = uiaxes(uigridlayout(c.targetResidualPanel, [1, 1], 'Padding', 0));
            c.targetResidualInfo = uilabel(residualGrid, 'WordWrap', 'on', 'Text', ['推定した後に「重ね合わせ補正値を計算する」を' ...
                '押すと、補正後の残差を Wafer 上のベクトルで描きます（四角は実測値の点、◇ は未知の座標の点）。']);
            place(c.targetResidualInfo, 3, 1);
            set([c.targetRun, c.targetExport, c.targetSaveFigure, c.targetCopyFigure, c.targetAddShots, c.targetOverlayButton, ...
                c.targetOverlayRecompute, c.targetResidualSave, c.targetResidualCopy, c.targetOverlayExport], 'Enable', 'off');
            app.Controls = mergeStruct(app.Controls, c);
            syncTargetOverlayControls(app);
            onTargetEdited(app);
        end

        function onTabChanged(app, event)
            % 「6. 未知の座標の推定」を開いたら、選択肢（Wafer・学習データ・手法）を今のデータ・結果・設定に合わせる
            if event.NewValue == app.Tabs.target
                refreshTargetChoices(app);
            end
        end

        function refreshTargetChoices(app)
            % 推定の条件の選択肢を作り直す（前に選んでいたものが残っていれば、そのまま選ぶ）
            c = app.Controls;
            hasData = ~isempty(app.Data);
            if hasData
                labels = string({app.Data.units.label});
                setListChoices(c.targetWafer, labels, num2cell(1:numel(labels)));
            else
                setListChoices(c.targetWafer, "—（データを読み込んでください）", {1});
            end
            trainingItems = "計測値のある全 Mark（全 Shot）";
            trainingData = {char(app.TARGET_ALL_TRAINING)};
            if ~isempty(app.Results) && ~isImportedResults(app.Results) && isfield(app.Results, 'plans')
                planLabels = unique(string({app.Results.plans.label}), 'stable');
                trainingItems = [trainingItems, "学習パターン：" + planLabels];
                trainingData = [trainingData, cellstr(planLabels)];
            end
            setListChoices(c.targetTraining, trainingItems, trainingData);
            setModeChoices(c.targetMode, alignest.valueSpec(app.Settings.data));
            methods = alignest.activeMethods(app.Settings);   % 1変数では RT モデルを除く
            if isempty(methods)
                setChoices(c.targetMethod, "—（「2. 評価の設定」で手法を選んでください）", {1});
            else
                setChoices(c.targetMethod, string({methods.label}), num2cell(1:numel(methods)));
            end
            c.targetAddShots.Enable = onOff(hasData);   % 「全 Shot に置く」は読み込んだ Wafer の Shot の並びを使う
            c.targetRun.Enable = onOff(hasData && ~isempty(methods));
        end

        function targets = currentTargets(app)
            % 表（画面）の点を alignest.targetTemplate の形にする。数でない欄は行の番号を出して止める
            data = app.Controls.targetTable.Data;
            n = size(data, 1);
            if n == 0
                error('alignest:noTargets', '推定する点がありません。左の表に点を読み込むか、足してください。');
            end
            text = strings(size(data));
            for k = 1:numel(data)
                if ~isempty(data{k})
                    text(k) = strtrim(alignest.normalizeNumberText(string(data{k})));
                end
            end
            numbers = str2double(text(:, 2:end));
            targets = alignest.targetTemplate(n);
            targets.name = text(:, 1);
            unnamed = targets.name == "";
            targets.name(unnamed) = "P" + string(find(unnamed));
            names = ["Xmm", "Ymm", "markXmm", "markYmm", "markNo", "shotNo", "direction"];
            for k = 1:numel(names)
                column = numbers(:, k);
                unreadable = isnan(column) & text(:, k + 1) ~= "";
                if any(unreadable)
                    error('alignest:targetTable', '%s 列に数でない値があります（表の %s 行目）。', app.TARGET_COLUMNS{k + 1}, ...
                        strjoin(string(find(unreadable).'), "・"));
                end
                targets.(names(k)) = column;
            end
            missing = isnan(targets.Xmm) | isnan(targets.Ymm);
            if any(missing)
                error('alignest:targetTable', 'Xmm・Ymm が空欄の行があります（表の %s 行目）。', ...
                    strjoin(string(find(missing).'), "・"));
            end
            badDirection = ~isnan(targets.direction) & ~ismember(targets.direction, [1, 2]);
            if any(badDirection)
                error('alignest:targetTable', 'Direction（Scan 方向）は 1 か 2 にしてください（表の %s 行目）。', ...
                    strjoin(string(find(badDirection).'), "・"));
            end
            targets.markXmm(isnan(targets.markXmm)) = 0;   % 空欄は Shot 中心（Xmm・Ymm がそのまま点の座標）
            targets.markYmm(isnan(targets.markYmm)) = 0;
        end

        function onTargetEdited(app)
            % 表を変えたら、点の数と入力の誤りを出す（前の推定値は残すが、推定し直すよう伝える）
            c = app.Controls;
            n = size(c.targetTable.Data, 1);
            c.targetInfo.Text = sprintf(['%d 点。Xmm・Ymm：Shot 中心の Wafer 上の座標 [mm]（markXmm・markYmm が 0 なら点そのもの）、' ...
                'markXmm・markYmm：Shot 中心から見た位置 [mm]。markNo・shotNo・Direction は空欄でもよい' ...
                '（推定のとき、点を含む Shot から Scan 方向を補います）。'], n);
            c.targetError.Text = '';
            if n > 0
                try
                    currentTargets(app);
                catch err
                    c.targetError.Text = ['⚠ ', err.message];
                end
            end
            if ~isempty(app.TargetRun) && ~app.TargetRun.stale
                app.TargetRun.stale = true;
                c.targetMessage.Value = cellstr(["表の点を変えました。「推定する」を押すと、今の点で推定し直します。"; ...
                    app.TargetRun.messages(:)]);
            end
        end

        function onTargetSelected(app, event)
            app.TargetSelection = unique(event.Indices(:, 1));
        end

        function onDeleteTargetRows(app)
            rows = app.TargetSelection;
            data = app.Controls.targetTable.Data;
            rows = rows(rows >= 1 & rows <= size(data, 1));
            if isempty(rows)
                uialert(app.Figure, '削除する行を表で選んでください（Ctrl・Shift で複数選べます）。', '行を選んでください', ...
                    'Icon', 'info');
                return
            end
            data(rows, :) = [];
            app.Controls.targetTable.Data = data;
            app.TargetSelection = zeros(0, 1);
            onTargetEdited(app);
        end

        function onAddTargets(app, kind)
            c = app.Controls;
            switch kind
                case "shots"
                    markNo = str2double(alignest.normalizeNumberText(c.targetShotMark.Value));
                    if strtrim(c.targetShotMark.Value) ~= "" && isnan(markNo)
                        uialert(app.Figure, 'Mark 番号は数にしてください（空欄でもよい）。', 'Mark 番号', 'Icon', 'warning');
                        return
                    end
                    runWithAlert(app, @() app.addTargetPoints("shots", c.targetShotX.Value, c.targetShotY.Value, markNo), ...
                        "点を足せませんでした", "Shot 内の位置と Mark 番号を確かめてください。");
                case "grid"
                    runWithAlert(app, @() app.addTargetPoints("grid", c.targetPitch.Value, c.targetRadius.Value), ...
                        "点を足せませんでした", "間隔を広げるか、半径を小さくしてください。");
                otherwise
                    app.addTargetPoints("row");
                    scroll(c.targetTable, 'bottom');
            end
        end

        function onLoadTargets(app)
            [fileName, folder] = uigetfile({'*.xlsx;*.xls;*.csv', 'Excel・CSV (*.xlsx, *.xls, *.csv)'}, ...
                '未知の座標（推定する点）の表を選ぶ');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.loadTargetPoints(fullfile(folder, fileName)), "点を読み込めませんでした", ...
                "1行目に Xmm・Ymm の見出しがあるか、数の欄に文字が入っていないかを確かめてください。");
        end

        function onEstimateTargets(app)
            runWithAlert(app, @() app.estimateTargets(), "推定できませんでした", ...
                "左の表の点・学習データ・手法を確かめてください。学習点が少ないときは学習データを「計測値のある全 Mark」にしてください。");
        end

        function onTargetOverlay(app)
            runWithAlert(app, @() app.computeTargetOverlay(), "重ね合わせ補正値を計算できませんでした", ...
                "「2. 評価の設定」の Overlay 補正で補正モデル（Wafer 成分・Shot 共通成分・Shot ごとの成分）を選んでください。");
        end

        function onExportTargets(app)
            [fileName, folder] = uiputfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, '推定値を書き出す', 'target_estimates.xlsx');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            if runWithAlert(app, @() app.exportTargetsTo(target), "書き出せませんでした", ...
                    "同じ名前のファイルを Excel で開いていれば閉じて、もう一度試してください。")
                uialert(app.Figure, sprintf('書き出しました：%s', target), '書き出しました', 'Icon', 'success');
            end
        end

        function onSaveTargetFigure(app)
            saveFigureWithDialog(app, "target", 'target_map.png');
        end

        function [plan, text] = targetTraining(app, unitIndex, training)
            % 学習データ：計測値のある全 Mark（全 Shot）、または評価の学習パターン（その Wafer のもの）
            if training == app.TARGET_ALL_TRAINING
                plan = 1:numel(app.Data.units(unitIndex).shots.shotNo);
                text = "計測値のある全 Mark（全 Shot）";
                return
            end
            plans = app.Results.plans;
            position = find(string({plans.label}) == training & [plans.unitIndex] == unitIndex, 1);
            if isempty(position)
                error('alignest:targetTraining', 'Wafer「%s」には学習パターン「%s」がありません。', ...
                    app.Data.units(unitIndex).label, training);
            end
            plan = plans(position);
            text = "学習パターン：" + training;
        end

        function showTargetRun(app)
            % 推定値の表・メッセージ・図を出す（外挿・Wafer の外の行は色を付け、メッセージは目立つ色にする）
            run = app.TargetRun;
            c = app.Controls;
            e = run.estimates;
            mark = strings(height(e), 1);
            mark(e.extrapolated) = "外挿";
            mark(e.outsideWafer) = "Wafer の外（対象外）";
            spec = alignest.valueSpec(app.Settings.data);
            shown = table(e.wafer, e.training, e.name, round(e.x, 3), round(e.y, 3), e.markNo, e.shotNo, ...
                round(e.estimateX, 3), round(e.estimateY, 3), mark, round(e.outsideMm, 1), e.note, 'VariableNames', ...
                ["Wafer", "学習データ", "名前", "x [mm]", "y [mm]", "markNo", "shotNo", "推定値 X [nm]", "推定値 Y [nm]", ...
                "外挿・対象外", "範囲の外 [mm]", "メモ"]);
            if spec.scalar
                % 1変数：推定値は1列（値の名前と単位）
                shown = removevars(shown, "推定値 Y [nm]");
                shown.Properties.VariableNames{'推定値 X [nm]'} = char("推定値 " + spec.name + " [" + spec.unit + "]");
            end
            c.targetResultTable.Data = shown;
            removeStyle(c.targetResultTable);
            flagged = e.extrapolated | e.outsideWafer;
            if any(flagged)
                addStyle(c.targetResultTable, uistyle('BackgroundColor', app.Palette.warning), 'row', find(flagged));
            end
            warn = any(flagged) || any(e.unseenMark);
            c.targetMessage.Value = cellstr(run.messages(:));
            c.targetMessage.FontColor = ternary(warn, app.Palette.error, app.Palette.text);
            set([c.targetExport, c.targetSaveFigure, c.targetCopyFigure, c.targetOverlayExport], 'Enable', 'on');
            set([c.targetOverlayButton, c.targetOverlayRecompute], 'Enable', onOff(~spec.scalar));   % 補正は X・Y の2成分が要る
            setChoices(c.targetCombination, run.labels, num2cell(1:numel(run.labels)));
            c.targetCombination.Enable = 'on';
            showTargetCombination(app);
        end

        function showTargetCombination(app)
            % 選んだ組み合わせ（Wafer × 学習データ）の図と重ね合わせ補正を出す
            drawTargetMap(app);
            showTargetOverlay(app);
        end

        function drawTargetMap(app)
            % 選んだ組み合わせ（Wafer × 学習データ）の図を描く
            run = app.TargetRun;
            c = app.Controls;
            if isempty(run)
                return
            end
            position = min(max(c.targetCombination.Value, 1), numel(run.results));
            unit = app.Data.units(run.unitIndex(position));
            titleText = unit.label + " の推定値";   % 手法・学習データは上の欄に出ている（題名が長いと色の目盛りの名前と重なる）
            if numel(unique(run.training)) > 1
                % 学習データも題名に入れる（2行にして、色の目盛りの名前と重ならない幅にする）
                titleText = unit.label + newline + ternary(run.training(position) == app.TARGET_ALL_TRAINING, ...
                    "計測値のある全 Mark", run.training(position));
            end
            alignest.plot.targetMap(c.targetAxes, run.results{position}, unit, mode=string(c.targetMode.Value), ...
                titleText=titleText, waferRadiusMm=app.Settings.data.waferRadiusMm, spec=alignest.valueSpec(app.Settings.data));
            styleAxes(app, c.targetAxes, app.AXES_FONT_SIZE);
        end

        function note = targetOverlayForExport(app)
            % 書き出す前に、重ね合わせ補正値を今の補正モデルで用意する（計算していない・モデルを変えた組み合わせがあれば
            % 計算し直す）。note は「説明」シートに書く文
            run = app.TargetRun;
            if alignest.valueSpec(app.Settings.data).scalar
                note = "1変数の推定なので、重ね合わせ補正値は書き出していない（X・Y の2成分が要る）。";
                return
            end
            try
                choice = alignest.overlayChoice(app.Settings);
            catch err
                note = "補正モデルの式に誤りがあるので、重ね合わせ補正値は書き出していない：" + string(err.message);
                return
            end
            if ~choice.enabled
                note = "補正モデルがすべて「なし」なので、重ね合わせ補正値は書き出していない。";
                return
            end
            missing = any(cellfun(@isempty, run.overlay)) || staleOverlayText(app) ~= "";
            if missing
                computeTargetOverlay(app);
            end
            note = "補正モデル：" + choice.description + ternary(missing, "（書き出すときに計算した）", "") + ...
                "。シート「補正値」「補正の残差」「補正に使った点」と、「推定値」シートの補正量・補正後の残差の列。";
        end

        function text = staleOverlayText(app)
            % 補正値を計算した後に補正モデルを変えていれば、その知らせ（変えていなければ ""）
            run = app.TargetRun;
            text = "";
            if ~isempty(run) && isfield(run, 'overlayModel') && ~isempty(run.overlayModel) && ...
                    ~isequaln(run.overlayModel, app.Settings.overlay)
                text = "⚠ 補正モデルを変えました。「重ね合わせ補正値を計算する」で計算し直してください（下は前のモデルの値）。";
            end
        end

        function onTargetOverlayModelChanged(app)
            % 「補正のモデル」で変えた補正モデルを「2. 評価の設定」の Overlay 補正の欄に写し、設定を更新する（同じ設定。
            % 確かめ・設定への反映・欄の有効／無効は「2. 評価の設定」と同じ処理で、こちらの欄にも写し戻す）
            pairs = targetOverlayPairs(app.Controls);
            for k = 1:size(pairs, 1)
                pairs{k, 1}.Value = pairs{k, 2}.Value;
            end
            onSettingsChanged(app);
            showTargetOverlay(app);   % 計算した補正値が前のモデルなら、その旨を出す
        end

        function syncTargetOverlayControls(app)
            % 「補正のモデル」の欄を「2. 評価の設定」の Overlay 補正の欄（値・有効／無効・式の誤り）に合わせる
            c = app.Controls;
            if ~isfield(c, 'targetOverlayWafer')
                return
            end
            pairs = targetOverlayPairs(c);
            for k = 1:size(pairs, 1)
                pairs{k, 2}.Value = pairs{k, 1}.Value;
                pairs{k, 2}.Enable = pairs{k, 1}.Enable;
            end
            c.targetOverlayError.Text = c.overlayFormulaError.Text;
        end

        function onSaveTargetResidualFigure(app)
            saveFigureWithDialog(app, "targetResidual", 'target_correction_map.png');
        end

        function showTargetOverlay(app)
            % 「補正値」「補正残差のマップ」のタブ：選んだ組み合わせの補正値（係数）・点の種類ごとの補正後の残差と、その図
            run = app.TargetRun;
            c = app.Controls;
            if isempty(run) || ~isfield(run, 'overlay')
                return
            end
            position = min(max(c.targetCombination.Value, 1), numel(run.results));
            correction = run.overlay{position};
            drawTargetCorrectionMap(app);
            if isempty(correction)
                c.targetOverlaySummary.Data = table();
                c.targetOverlayTable.Data = table();
                c.targetOverlayInfo.Text = '「重ね合わせ補正値を計算する」を押すと、この組み合わせの補正値（係数）と補正後の残差を出します。';
                return
            end
            summary = correction.summary;
            c.targetOverlaySummary.Data = table(summary.axis, summary.source, summary.n, round(summary.valueMean3Sigma, 3), ...
                round(summary.residualMean3Sigma, 3), 'VariableNames', ["軸", "点の種類", "点数", ...
                "補正前 |平均|+3σ [nm]", "補正後の残差 |平均|+3σ [nm]"]);
            coefficients = correction.coefficients;
            c.targetOverlayTable.Data = table(coefficients.axis, coefficients.componentLabel, coefficients.shotNo, ...
                coefficients.term, coefficients.value, coefficients.unit, coefficients.note, 'VariableNames', ...
                ["軸", "成分", "shotNo", "項", "補正値（係数）", "単位", "メモ"]);
            % 1つ目の文（点の数と補正モデル）を出し、ほかの注意は欄に重ねたときに出す（下の表の場所を取らないように）
            c.targetOverlayInfo.Text = char(staleOverlayText(app) + run.labels(position) + "：" + correction.messages(1));
            c.targetOverlayInfo.Tooltip = char(strjoin([reshape(correction.messages(2:end), [], 1); "補正値は mm の座標での係数（x・y は " + ...
                "Wafer 成分では Shot 中心、Shot の成分では Shot 内の座標）。重なる項は係数の表の「メモ」。"], " "));
        end

        function clearTargetRun(app)
            app.TargetRun = [];
            c = app.Controls;
            if ~isfield(c, 'targetResultTable')
                return
            end
            c.targetResultTable.Data = table();
            removeStyle(c.targetResultTable);
            cla(c.targetAxes, 'reset');
            legend(c.targetAxes, 'off');
            set([c.targetExport, c.targetSaveFigure, c.targetCopyFigure, c.targetOverlayButton, c.targetOverlayRecompute, c.targetCombination, ...
                c.targetResidualSave, c.targetResidualCopy, c.targetOverlayExport], 'Enable', 'off');
            cla(c.targetResidualAxes, 'reset');
            legend(c.targetResidualAxes, 'off');
            c.targetResidualInfo.Text = ['推定した後に「重ね合わせ補正値を計算する」を押すと、補正後の残差を Wafer 上の' ...
                'ベクトルで描きます（四角は実測値の点、◇ は未知の座標の点）。'];
            setChoices(c.targetCombination, "—（推定すると選べます）", {1});
            c.targetOverlaySummary.Data = table();
            c.targetOverlayTable.Data = table();
            c.targetOverlayInfo.Text = '推定した後に「重ね合わせ補正値を計算する」を押すと、補正値（係数）と補正後の残差を出します。';
            c.targetMessage.Value = {'左の表に推定する点を決めてから「推定する」を押してください。'};
            c.targetMessage.FontColor = app.Palette.text;
        end

        function spec = resultSpec(app)
            % 結果を表示するときの推定する値（評価した設定の data。結果が無ければ今の設定）
            source = app.Settings.data;
            if ~isempty(app.Results) && isfield(app.Results, 'settings') && isfield(app.Results.settings, 'data')
                source = app.Results.settings.data;
            end
            spec = alignest.valueSpec(source);
        end
    end
end

% ================= このファイルだけで使う小さな関数 =================
function pairs = targetOverlayPairs(c)
% 「2. 評価の設定」の Overlay 補正の欄と、「6. 未知の座標の推定」の「補正のモデル」の欄の組（同じ設定を2か所で変える）
pairs = {c.overlayWafer, c.targetOverlayWafer; c.overlayWaferDx, c.targetOverlayWaferDx; ...
    c.overlayWaferDy, c.targetOverlayWaferDy; c.overlayShotCommon, c.targetOverlayShotCommon; ...
    c.overlayShotDx, c.targetOverlayShotDx; c.overlayShotDy, c.targetOverlayShotDy; ...
    c.overlayPerShot, c.targetOverlayPerShot; c.overlayPerShotDx, c.targetOverlayPerShotDx; ...
    c.overlayPerShotDy, c.targetOverlayPerShotDy};
end

function cells = targetCells(targets)
% 推定する点（alignest.targetTemplate の形）を、画面の表の文字の欄にする（NaN は空欄）
columns = {targets.name, targets.Xmm, targets.Ymm, targets.markXmm, targets.markYmm, targets.markNo, targets.shotNo, ...
    targets.direction};
cells = cell(height(targets), numel(columns));
for k = 1:numel(columns)
    text = string(columns{k});
    text(ismissing(text)) = "";
    cells(:, k) = cellstr(text);
end
end

function messages = targetMessages(results, estimates, labels)
% 画面に出すメッセージ。組み合わせ（Wafer × 学習データ）が1つならその結果のまま、複数なら外挿の数をまとめ、
% ほかの注意は重ねずに並べる
if isscalar(results)
    messages = results{1}.messages;
    return
end
estimated = ~estimates.outsideWafer;
n = nnz(estimated);
nOutside = nnz(estimates.extrapolated);
if nOutside > 0
    messages = sprintf(['⚠ 外挿：%d 個の組み合わせ（Wafer × 学習データ）の計 %d / %d 点が学習点の範囲（学習点を囲む' ...
        '凸包）の外にあります（最大 %.1f mm 外）。学習点から離れるほど推定値は信頼できません（表の「外挿・対象外」、' ...
        '図の × 印）。'], numel(labels), nOutside, n, max(estimates.outsideMm(estimates.extrapolated)));
else
    messages = sprintf('外挿なし：%d 個の組み合わせ（Wafer × 学習データ）の計 %d 点すべてが学習点の範囲（学習点を囲む凸包）の中です。', ...
        numel(labels), n);
end
others = strings(0, 1);
for k = 1:numel(results)
    others = [others; reshape(results{k}.messages(2:end), [], 1)]; %#ok<AGROW>   % 1つだけのときは 1×0 になるので縦にそろえる
end
messages = [string(messages); unique(others, 'stable')];
end

function text = onOffText(value)
text = "しない";
if value
    text = "する";
end
end

function setListChoices(listbox, items, itemsData)
% 複数選べる一覧の選択肢を変える（前に選んでいた値のうち残っているものは選んだまま。無ければ最初の1つを選ぶ）
previous = listbox.Value;
listbox.Items = cellstr(items);
listbox.ItemsData = itemsData;
kept = previous(cellfun(@(value) any(cellfun(@(item) isequal(item, value), itemsData)), previous));
if isempty(kept)
    kept = itemsData(1);
end
listbox.Value = kept;
end
