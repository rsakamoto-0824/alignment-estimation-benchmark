classdef (Abstract) TargetTab < appui.Core
    %TARGETTAB 「5. 未知の座標の推定」タブ：推定する点の表、推定、重ね合わせ補正値、補正残差のマップ、書き出し。
    %   AlignmentEstimationApp（画面の本体）の一部。画面の部品は Controls、データ・結果は Core のプロパティに持つ。
    %   ほかのタブの関数も同じように呼べる（どれも AlignmentEstimationApp の関数になる）。

    methods
        function targets = setTargetPoints(app, targets)
            %SETTARGETPOINTS 「5. 未知の座標の推定」の表を targets（alignest.targetTemplate の形）にする。
            ensureTab(app, "target");   % まだ作っていないタブなら作る（画面の操作と同じに使えるように）
            app.Controls.targetTable.Data = targetCells(targets);
            app.TargetSelection = zeros(0, 1);
            onTargetEdited(app);
        end

        function targets = loadTargetPoints(app, filePath, sheetName)
            %LOADTARGETPOINTS 未知の座標の表（Excel・CSV）を読み、推定する点の表を置き換える（alignest.readTargetPoints）。
            ensureTab(app, "target");   % まだ作っていないタブなら作る（画面の操作と同じに使えるように）
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
            ensureTab(app, "target");   % まだ作っていないタブなら作る（画面の操作と同じに使えるように）
            c = app.Controls;
            existing = size(c.targetTable.Data, 1);
            switch string(kind)
                case "shots"
                    if isempty(app.Data)
                        error('alignest:noData', '先に「1. データ読込」で計測データを読み込んでください（Shot の並びを使います）。');
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
            %ESTIMATETARGETS 「5. 未知の座標の推定」：表の点の推定値を、選んだ Wafer × 学習データの組み合わせごとに
            %   まとめて求め、表・図・メッセージに出す。
            %   unitChoice：Wafer の番号（複数可。0 = すべての Wafer）、trainingChoice："all"（計測値のある全 Mark）または
            %   評価の学習パターンの名前（複数可）、methodIndex：手法の番号（alignest.activeMethods(app.Settings) の何番目か）。
            %   省略すると画面で選んでいるもの。推定は alignest.predictTargets（評価と同じ推定、条件は今の設定）。
            %   300 mm Wafer の外の点は推定の対象外（推定値は X・Y とも 0。図には描かない）。
            ensureTab(app, "target");   % まだ作っていないタブなら作る（画面の操作と同じに使えるように）
            if isempty(app.Data)
                error('alignest:noData', '先に「1. データ読込」で計測データを読み込んでください。');
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
                error('alignest:noMethods', '手法がありません。「2. 面内推定の設定」で比べる手法を選んでください。');
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
                "overlayModel", [], "targets", targets, "comparison", {cell(1, nCombinations)});
            showTargetRun(app);
            highOrderInputChanged(app, "target");   % 前の推定値で求めた Shot 高次補正は消す
            run = app.TargetRun;
        end

        function overlay = computeTargetOverlay(app)
            %COMPUTETARGETOVERLAY 最後に推定した未知の座標の推定値を使って、組み合わせ（Wafer × 学習データ）ごとに
            %   重ね合わせ（Overlay）補正値を求め、「重ね合わせ補正」のタブに出す（alignest.targetOverlayCorrection）。
            %   補正に使う点は、元の実測値（学習点）・学習しなかった Mark の推定値・未知の座標の推定値（Wafer の外の点を
            %   除く）。補正モデルはこのタブの「補正のモデル」（settings.targetCorrection。alignest.targetCorrectionChoice）。
            %   overlay は組み合わせごとの結果の cell。
            ensureTab(app, "target");   % まだ作っていないタブなら作る（画面の操作と同じに使えるように）
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
            choice = alignest.targetCorrectionChoice(app.Settings);
            overlay = cell(1, numel(run.results));
            for k = 1:numel(run.results)
                unitIndex = run.unitIndex(k);
                plan = targetTraining(app, unitIndex, run.training(k));
                overlay{k} = alignest.targetOverlayCorrection(app.Data.units(unitIndex), plan, run.method, app.Settings, ...
                    run.results{k}.table, choice);
            end
            app.TargetRun.overlay = overlay;
            app.TargetRun.overlayModel = app.Settings.targetCorrection;   % 後でモデルを変えたら、計算し直すよう知らせる
            showTargetOverlay(app);
        end

        function summary = drawTargetCorrectionMap(app, value, source, mode, arrange, view)
            %DRAWTARGETCORRECTIONMAP 「補正残差のマップ」：選んだ組み合わせの重ね合わせ補正の補正後の残差（または補正量・
            %   補正前の値）を、Wafer 上のベクトル・色（alignest.plot.correctionMap）か Shot スタックマップ（全 Shot を Shot 内の
            %   座標で重ねる。alignest.plot.shotStackMap）で描く。
            %   value："residual"・"correction"・"value"、source："all"・"target"・"measured"・"estimated"、
            %   mode："vector"・"X"・"Y"、arrange："single"（1つの図）・"side"（補正前の値・補正量・補正後の残差を並べる。矢印の
            %   倍率・色の範囲をそろえる）、view："wafer"（Wafer 上）・"stack"（Shot スタックマップ）。省略すると画面の選択。
            %   Wafer 上の図には「重ねる円」の半径 [mm] の円を重ねる。summary は描いた図ごとの点の数と |平均| + 3σ（補正値が
            %   無ければ []）。
            ensureTab(app, "target");   % まだ作っていないタブなら作る（画面の操作と同じに使えるように）
            c = app.Controls;
            controls = {c.targetResidualValue, c.targetResidualSource, c.targetResidualMode, c.targetResidualArrange, ...
                c.targetResidualView};
            given = {};
            if nargin >= 2, given{1} = value; end
            if nargin >= 3, given{2} = source; end
            if nargin >= 4, given{3} = mode; end
            if nargin >= 5, given{4} = arrange; end
            if nargin >= 6, given{5} = view; end
            for k = 1:numel(given)
                controls{k}.Value = char(given{k});
            end
            summary = [];
            run = app.TargetRun;
            correction = [];
            if ~isempty(run) && isfield(run, 'overlay')
                position = min(max(c.targetCombination.Value, 1), numel(run.results));
                correction = run.overlay{position};
            end
            axesList = c.targetResidualAxesList;
            side = string(c.targetResidualArrange.Value) == "side";
            c.targetResidualValue.Enable = onOff(~side);   % 並べるときは補正前の値・補正量・残差で決まっている
            if isempty(correction)
                showTargetResidualPanels(app, 1);
                axesPlaceholder(app, axesList, '「重ね合わせ補正値を計算する」を押すと、ここに補正残差の図が出ます。');
                set([c.targetResidualSave, c.targetResidualCopy], 'Enable', 'off');
                c.targetResidualInfo.Text = '「重ね合わせ補正値を計算する」で残差を描きます。';
                return
            end
            unit = app.Data.units(run.unitIndex(position));
            sourceName = string(c.targetResidualSource.Value);
            mode = string(c.targetResidualMode.Value);
            stack = string(c.targetResidualView.Value) == "stack";
            if side
                valueNames = ["value", "correction", "residual"];
            else
                valueNames = string(c.targetResidualValue.Value);
            end
            showTargetResidualPanels(app, numel(valueNames));
            % 並べる図の矢印の倍率・色の範囲をそろえる（描く点の値すべてで決める）
            points = targetResidualPoints(correction, sourceName);
            values = cell(1, numel(valueNames));
            for k = 1:numel(valueNames)
                values{k} = [points.(valueNames(k) + "X"), points.(valueNames(k) + "Y")];
            end
            together = vertcat(values{:});
            column = 1 + (mode == "Y");
            colorLimit = max([abs(together(isfinite(together(:, column)), column)); eps]);
            magnitudeLimit = max([hypot(together(:, 1), together(:, 2)); 0], [], 'omitnan');
            if stack
                scale = 0;   % Shot スタックマップは Shot の大きさから自動で決める（図ごとに同じ値の大きさなので、どれも同じ）
                if mode == "vector"
                    scale = stackArrowScale(together, unit.shotSizeMm);
                end
            else
                scale = alignest.plot.vectorScale(together);
            end
            radii = targetCircleRadii(c.targetResidualCircles);
            summary = struct("valueLabel", {}, "n", {}, "meanPlus3SigmaX", {}, "meanPlus3SigmaY", {});
            for k = 1:numel(valueNames)
                ax = axesList(k);
                cla(ax, 'reset');   % 空のときの案内を消し、目盛りの枠を出す
                ax.Visible = 'on';
                label = targetValueLabel(valueNames(k));
                panelTitle = ternary(side, label, unit.label);
                if stack
                    alignest.plot.shotStackMap(ax, [points.localX, points.localY], values{k}, mode=mode, ...
                        shotSizeMm=unit.shotSizeMm, scaleMmPerNm=scale, colorLimit=colorLimit, titleText=panelTitle, ...
                        showLegend=~side);
                    picked = values{k};
                    summary(k) = struct("valueLabel", label, "n", nnz(any(isfinite(picked), 2)), ...
                        "meanPlus3SigmaX", meanPlus3Sigma(picked(:, 1)), "meanPlus3SigmaY", meanPlus3Sigma(picked(:, 2)));
                else
                    % 題名は短く（|平均|+3σ は下の欄に出す。題名が長いと色の目盛りの名前と重なる）
                    drawn = alignest.plot.correctionMap(ax, correction, unit, value=valueNames(k), source=sourceName, ...
                        mode=mode, titleText=panelTitle, showStatistics=false, ...
                        legendLocation=ternary(side, "none", "eastoutside"), waferRadiusMm=app.Settings.data.waferRadiusMm, ...
                        scaleMmPerNm=scale, colorLimit=colorLimit, magnitudeLimit=magnitudeLimit);
                    summary(k) = struct("valueLabel", drawn.valueLabel, "n", drawn.n, ...
                        "meanPlus3SigmaX", drawn.meanPlus3SigmaX, "meanPlus3SigmaY", drawn.meanPlus3SigmaY);
                    if ~isempty(radii)
                        hold(ax, 'on');
                        alignest.plot.radiusCircles(ax, radii);
                        hold(ax, 'off');
                    end
                end
                % 描く関数の中の cla(ax, 'reset') で、しまっていた図（並べる2つ目・3つ目）が隠れたままになるので出し直す
                ax.Visible = 'on';
            end
            styleAxes(app, axesList(1:numel(valueNames)), app.AXES_FONT_SIZE);
            set([c.targetResidualSave, c.targetResidualCopy], 'Enable', 'on');
            parts = strings(1, numel(summary));
            for k = 1:numel(summary)
                parts(k) = summary(k).valueLabel + sprintf("：%d 点、|平均|+3σ X %.3f nm・Y %.3f nm", summary(k).n, ...
                    summary(k).meanPlus3SigmaX, summary(k).meanPlus3SigmaY);
            end
            info = run.labels(position) + "｜" + strjoin(parts, "　") + ternary(stack, "（全 Shot を Shot 内の座標で重ねた図）", ...
                "（四角は実測値の点、◇ は未知の座標の点）");
            c.targetResidualInfo.Tooltip = char("補正モデル：" + correction.description);
            c.targetResidualInfo.Text = char(staleOverlayText(app) + info);
        end

        function setTargetCorrection(app, options)
            %SETTARGETCORRECTION 「補正のモデル」の式を選ぶ（画面で選ぶのと同じ）。名前と値の組：waferOrder（0〜5）・
            %   shotCommon（"none"・"linear"・"quadratic"・"asml"・"canon"・"nikon"・"custom"）・perShot（"none"・
            %   "translation"・"linear"）。式に無くなった項のチェックは外したまま残さない。
            arguments
                app
                options.waferOrder (1, 1) double
                options.shotCommon (1, 1) string
                options.perShot (1, 1) string
            end
            ensureTab(app, "target");
            c = app.Controls;
            if isfield(options, "waferOrder"), c.targetCorrectionWafer.Value = options.waferOrder; end
            if isfield(options, "shotCommon"), c.targetCorrectionShotCommon.Value = char(options.shotCommon); end
            if isfield(options, "perShot"), c.targetCorrectionPerShot.Value = char(options.perShot); end
            onTargetCorrectionModelChanged(app);
        end

        function terms = setTargetCorrectionTermUsed(app, key, used)
            %SETTARGETCORRECTIONTERMUSED 「補正のモデル」の項を使う・使わない（表の「使う」のチェック）。key は項の文字
            %   （alignest.targetCorrectionTerms の key）。0次・1次の項は外せない（alignest:targetCorrection）。
            ensureTab(app, "target");
            terms = alignest.targetCorrectionTerms(app.Settings);
            row = find(terms.key == string(key), 1);
            if isempty(row)
                error('alignest:targetCorrection', '補正のモデルに項「%s」がありません。', key);
            end
            if terms.required(row) && ~used
                error('alignest:targetCorrection', '0次・1次の項（%s の %s）は補正の土台なので外せません。', ...
                    terms.componentLabel(row), terms.name(row));
            end
            excluded = setdiff(reshape(string(app.Settings.targetCorrection.excludedTerms), 1, []), string(key), 'stable');
            if ~used
                excluded = [excluded, string(key)];
            end
            app.Settings.targetCorrection.excludedTerms = excluded;
            terms = refreshTargetCorrectionTerms(app);
            showTargetOverlay(app);   % 計算した補正値が前のモデルなら、その旨を出す
        end

        function setTargetCorrectionTerms(app, which)
            %SETTARGETCORRECTIONTERMS which = "all"：「補正のモデル」のすべての項を使う（「すべての項を使う」）
            arguments
                app
                which (1, 1) string {mustBeMember(which, "all")} = "all"
            end
            ensureTab(app, "target");
            app.Settings.targetCorrection.excludedTerms = strings(1, 0);
            refreshTargetCorrectionTerms(app);
            showTargetOverlay(app);
        end

        function comparison = compareTargetCorrection(app)
            %COMPARETARGETCORRECTION 「補正の比較」の「全計測と比べる」：選んだ組み合わせの Wafer で、全計測・一部計測＋面内推定
            %   （学習パターン）のそれぞれを、基準の補正（「2. 面内推定の設定」の Overlay 補正）と、未知の座標の推定値を足した
            %   このタブの補正（「補正のモデル」）で補正し、計測値のある Mark の補正後の |平均|+3σ を比べる
            %   （alignest.targetCorrectionComparison）。学習データが「計測値のある全 Mark」なら、全計測の2つだけ。
            ensureTab(app, "target");
            run = app.TargetRun;
            if isempty(run)
                error('alignest:noTargets', '先に「推定する」を押して、未知の座標を推定してください。');
            end
            if alignest.valueSpec(app.Settings.data).scalar
                error('alignest:overlayScalar', '重ね合わせ補正は X・Y の2成分が要ります（1変数の推定では比べられません）。');
            end
            c = app.Controls;
            position = min(max(c.targetCombination.Value, 1), numel(run.results));
            unitIndex = run.unitIndex(position);
            unit = app.Data.units(unitIndex);
            app.Figure.Pointer = 'watch';
            drawnow;
            restore = onCleanup(@() set(app.Figure, 'Pointer', 'arrow'));
            targetsPlan = run.results{position}.table;
            if run.training(position) == app.TARGET_ALL_TRAINING
                plan = [];
                targetsAll = targetsPlan;
            else
                plan = targetTraining(app, unitIndex, run.training(position));
                % 全 Mark で推定した未知の座標：同じ Wafer の組み合わせにあれば使い、無ければ同じ点・同じ手法で求める
                same = find(run.unitIndex == unitIndex & run.training == app.TARGET_ALL_TRAINING, 1);
                if ~isempty(same)
                    targetsAll = run.results{same}.table;
                else
                    allShots = targetTraining(app, unitIndex, app.TARGET_ALL_TRAINING);
                    targetsAll = alignest.predictTargets(unit, allShots, run.method, app.Settings, run.targets).table;
                end
            end
            comparison = alignest.targetCorrectionComparison(unit, plan, run.method, app.Settings, targetsPlan, targetsAll);
            comparison.label = run.labels(position);
            comparison.unitIndex = unitIndex;
            comparison.model = app.Settings.targetCorrection;
            comparison.baselineModel = app.Settings.overlay;
            app.TargetRun.comparison{position} = comparison;
            showTargetComparison(app);
        end

        function exportTargetsTo(app, filePath)
            %EXPORTTARGETSTO 最後に推定した未知の座標の推定値を Excel に書き出す（alignest.exportTargetEstimates）。
            %   重ね合わせ補正値（補正値（係数）・補正の残差・補正に使った点のシートと、「推定値」シートの点ごとの補正量・
            %   補正後の残差）も書く。まだ計算していない、または計算した後に補正モデルを変えたときは、書き出す前に今の
            %   補正モデルで計算する（補正モデルが「なし」・1変数・式の誤りのときは補正値を書かず、「説明」に理由を書く）。
            ensureTab(app, "target");   % まだ作っていないタブなら作る（画面の操作と同じに使えるように）
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
        % ================= 5. 未知の座標の推定 =================
        function buildTargetTab(app)
            % 左：推定する点（未知の座標）の表と、その作り方。右：推定の条件・メッセージ・図・推定値の表
            grid = uigridlayout(app.Tabs.target, [1, 1], 'Padding', 12);
            % 左の幅は狭めない（点を作るボタン・欄が横に並んでいて、狭めると右の方が隠れるため）
            body = uigridlayout(grid, [1, 2], 'ColumnWidth', {610, '1x'}, 'Padding', 0, 'ColumnSpacing', 14);
            left = uigridlayout(body, [6, 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit', 'fit'}, ...
                'Padding', 0, 'RowSpacing', 6);
            place(uilabel(left, 'Text', '① 推定する点', 'FontWeight', 'bold'), 1, 1);
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
                'ColumnWidth', app.TARGET_COLUMN_WIDTHS, ...
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
            label(controls, 'Wafer', 1, 1);
            label(controls, '学習データ', 1, 2);
            label(controls, '手法', 1, 3);
            c.targetWafer = uilistbox(controls, 'Items', {'—'}, 'ItemsData', {1}, 'Multiselect', 'on', 'Value', {1}, ...
                'Tooltip', ['推定する Wafer（Ctrl・Shift を押しながらクリックで複数。Ctrl + A ですべて）。' ...
                '選んだ Wafer × 学習データの組み合わせごとに、まとめて推定します。']);
            place(c.targetWafer, 2, 1);
            c.targetTraining = uilistbox(controls, 'Items', {'全 Mark'}, ...
                'ItemsData', {char(app.TARGET_ALL_TRAINING)}, 'Multiselect', 'on', 'Value', {char(app.TARGET_ALL_TRAINING)}, ...
                'Tooltip', ['計測値のある全 Mark：読み込んだ計測値をすべて学習に使います。学習パターン：評価で選んだ ' ...
                'Shot（Mark）だけを学習に使います（「2. 面内推定の設定」で評価した後に選べます）。複数選ぶと、まとめて推定します。']);
            place(c.targetTraining, 2, 2);
            methodGrid = uigridlayout(controls, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 0);
            place(methodGrid, 2, 3);
            c.targetMethod = uidropdown(methodGrid, 'Items', {'—'}, 'ItemsData', {1}, ...
                'Tooltip', '「2. 面内推定の設定」で選んだ手法から選びます。推定の条件（1次を除く・異常値の除外）も今の設定のとおりです。');
            place(c.targetMethod, 1, 1);
            actions = uigridlayout(controls, [1, 3], 'ColumnWidth', {160, 'fit', 'fit'}, 'Padding', 0);
            place(actions, 3, [1, 3]);
            c.targetRun = primaryButton(app, actions, '推定する', @(~, ~) app.onEstimateTargets());
            c.targetOverlayButton = uibutton(actions, 'Text', '重ね合わせ補正値を計算する', ...
                'ButtonPushedFcn', @(~, ~) app.onTargetOverlay(), 'Tooltip', ['推定した後に、元の実測値（学習点）・' ...
                '学習しなかった Mark の推定値・未知の座標の推定値をまとめて、「2. 面内推定の設定」の Overlay 補正の' ...
                'モデル（Wafer 成分・Shot 共通成分・Shot ごとの成分）を当てはめ、補正値（係数）と補正後の残差を求めます。']);
            c.targetExport = uibutton(actions, 'Text', '推定値を Excel に書き出す…', ...
                'ButtonPushedFcn', @(~, ~) app.onExportTargets());
            % メッセージは高さを決めた欄に出す（組み合わせが多くて長くなっても、下の図の場所を取らないように）
            c.targetMessage = uitextarea(right, 'Editable', 'off', 'FontWeight', 'bold', 'Value', ...
                {'「1. データ読込」で計測データを読み込み、左の表に推定する点を決めてから「推定する」を押してください。'});
            place(c.targetMessage, 3, 1);
            combinationGrid = uigridlayout(right, [1, 2], 'ColumnWidth', {'fit', '1x'}, 'Padding', 0);
            place(combinationGrid, 4, 1);
            label(combinationGrid, '図・補正に出す組み合わせ', 1, 1);
            c.targetCombination = uidropdown(combinationGrid, 'Items', {'—'}, 'ItemsData', {1}, ...
                'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.showTargetCombination(), ...
                'Tooltip', '推定した Wafer × 学習データの組み合わせ。図と「重ね合わせ補正」のタブに、選んだ組み合わせを出します。');
            place(c.targetCombination, 1, 2);
            outputs = uitabgroup(right);
            place(outputs, 5, 1);
            figureTab = uitab(outputs, 'Title', '図');
            figureGrid = uigridlayout(figureTab, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 6, 'RowSpacing', 4);
            figureControls = uigridlayout(figureGrid, [1, 6], 'ColumnWidth', {'fit', 140, 'fit', 90, 'fit', 'fit'}, 'Padding', 0);
            label(figureControls, '表示', 1, 1);
            c.targetMode = uidropdown(figureControls, 'Items', {'ベクトル', 'X（色）', 'Y（色）', 'X の分散（色・GPR）', ...
                'Y の分散（色・GPR）'}, 'ItemsData', {'vector', 'X', 'Y', 'varianceX', 'varianceY'}, ...
                'ValueChangedFcn', @(~, ~) app.drawTargetMap(), 'Tooltip', ['分散：GPR の推定の分散（予測分散。計測のばらつきは' ...
                '含めない）を色で描きます。学習点から離れるほど大きくなります。GPR 以外の手法には分散がありません。']);
            place(c.targetMode, 1, 2);
            label(figureControls, '重ねる円 [mm]', 1, 3);
            c.targetCircles = uieditfield(figureControls, 'text', 'Value', '', 'ValueChangedFcn', @(~, ~) app.drawTargetMap(), ...
                'Tooltip', 'Wafer 中心を中心とする円の半径 [mm]（空白区切りでいくつでも。例：100 135）。');
            place(c.targetCircles, 1, 4);
            c.targetSaveFigure = uibutton(figureControls, 'Text', '図を画像で保存…', ...
                'ButtonPushedFcn', @(~, ~) app.onSaveTargetFigure());
            place(c.targetSaveFigure, 1, 5);
            c.targetCopyFigure = uibutton(figureControls, 'Text', '図をコピー', 'Tooltip', app.COPY_TOOLTIP, ...
                'ButtonPushedFcn', @(source, ~) app.onCopyFigure("target", source));
            place(c.targetCopyFigure, 1, 6);
            c.targetPanel = uipanel(figureGrid, 'BorderType', 'none');
            place(c.targetPanel, 2, 1);
            c.targetAxes = uiaxes(uigridlayout(c.targetPanel, [1, 1], 'Padding', 0));
            axesPlaceholder(app, c.targetAxes, '左の表に点を決めて「推定する」を押すと、ここに推定値の図が出ます。');
            tableTab = uitab(outputs, 'Title', '推定値の表');
            c.targetResultTable = uitable(uigridlayout(tableTab, [1, 1], 'Padding', 6), 'RowName', {}, 'Data', table());
            % 補正のモデル：このタブの補正の式（基準の補正＝「2. 面内推定の設定」の Overlay 補正とは別）。未知の座標の推定値で
            % Shot 内の点が増えるので、高次の式（Shot 高次補正の式）で補正できる。項はチェックで選ぶ（0次・1次は外さない）
            modelTab = uitab(outputs, 'Title', '補正のモデル');
            modelGrid = uigridlayout(modelTab, [5, 4], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit'}, ...
                'ColumnWidth', {'1x', '1x', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            label(modelGrid, 'Wafer 成分', 1, 1);
            label(modelGrid, 'Shot 共通成分', 1, 2);
            label(modelGrid, 'Shot ごとの成分', 1, 3);
            onModel = @(~, ~) app.onTargetCorrectionModelChanged();
            c.targetCorrectionWafer = uidropdown(modelGrid, 'Items', {'なし', '1次', '2次', '3次', '4次', '5次'}, ...
                'ItemsData', {0, 1, 2, 3, 4, 5}, 'ValueChangedFcn', onModel, 'Tooltip', ['Shot 中心の座標の多項式' ...
                '（1次は並進・倍率・回転・直交度）。']);
            place(c.targetCorrectionWafer, 2, 1);
            c.targetCorrectionShotCommon = uidropdown(modelGrid, 'Items', {'なし', '1次（k1〜k6）', '2次（k1〜k12）', ...
                'ASML', 'Canon', 'Nikon', 'カスタム（k1〜k38）'}, 'ItemsData', {'none', 'linear', 'quadratic', 'asml', ...
                'canon', 'nikon', 'custom'}, 'ValueChangedFcn', onModel, 'Tooltip', ['全 Shot で同じ係数の Shot 内の補正式' ...
                '（「6. Shot高次補正」と同じ式。Canon・Nikon はルールの式のまま）。未知の座標の推定値で Shot 内の点を' ...
                '増やすと、高次の項も決まります。']);
            place(c.targetCorrectionShotCommon, 2, 2);
            c.targetCorrectionPerShot = uidropdown(modelGrid, 'Items', {'なし', '並進（k1・k2）', '1次（k1〜k6）'}, ...
                'ItemsData', {'none', 'translation', 'linear'}, 'ValueChangedFcn', onModel, 'Tooltip', ...
                'Shot ごとに別の係数で求める補正（x・y は Shot 内の座標）。');
            place(c.targetCorrectionPerShot, 2, 3);
            c.targetCorrectionAllTerms = uibutton(modelGrid, 'Text', 'すべての項を使う', ...
                'ButtonPushedFcn', @(~, ~) app.setTargetCorrectionTerms("all"));
            place(c.targetCorrectionAllTerms, 2, 4);
            c.targetCorrectionInfo = uilabel(modelGrid, 'WordWrap', 'on', 'Text', '');
            place(c.targetCorrectionInfo, 3, [1, 4]);
            c.targetCorrectionTable = uitable(modelGrid, 'RowName', {}, 'ColumnName', {'成分', '軸', '項', '次数', '使う'}, ...
                'ColumnEditable', [false, false, false, false, true], 'ColumnWidth', {140, 50, 160, 60, 60}, ...
                'CellEditCallback', @(~, event) app.onTargetCorrectionTermEdited(event));
            place(c.targetCorrectionTable, 4, [1, 4]);
            c.targetOverlayRecompute = uibutton(modelGrid, 'Text', 'このモデルで重ね合わせ補正値を計算する', ...
                'ButtonPushedFcn', @(~, ~) app.onTargetOverlay());
            place(c.targetOverlayRecompute, 5, [1, 2]);
            % 補正値：選んだ組み合わせの補正値（係数）と、点の種類ごとの補正後の残差
            overlayTab = uitab(outputs, 'Title', '補正値');
            overlayGrid = uigridlayout(overlayTab, [3, 1], 'RowHeight', {'fit', '1x', '1.4x'}, 'Padding', 6, 'RowSpacing', 6);
            overlayHeader = uigridlayout(overlayGrid, [1, 2], 'ColumnWidth', {'1x', 'fit'}, 'Padding', 0);
            c.targetOverlayInfo = uilabel(overlayHeader, 'WordWrap', 'on', 'Text', '「重ね合わせ補正値を計算する」で補正値と残差を出します。');
            c.targetOverlayExport = uibutton(overlayHeader, 'Text', '補正値を Excel に書き出す…', ...
                'ButtonPushedFcn', @(~, ~) app.onExportTargets(), 'Tooltip', ['推定値と、すべての組み合わせの重ね合わせ' ...
                '補正値（係数・補正の残差・補正に使った点、推定値の表の補正量・補正後の残差）を1つの Excel に書き出します' ...
                '（「推定値を Excel に書き出す…」と同じファイル）。']);
            c.targetOverlaySummary = uitable(overlayGrid, 'RowName', {}, 'Data', table());
            c.targetOverlayTable = uitable(overlayGrid, 'RowName', {}, 'Data', table());
            % 補正残差のマップ：補正後の残差（または補正量・補正前の値）を Wafer 上のベクトル・色で描く
            residualTab = uitab(outputs, 'Title', '補正残差のマップ');
            residualGrid = uigridlayout(residualTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            residualControls = uigridlayout(residualGrid, [2, 8], 'ColumnWidth', {'fit', 140, 'fit', 165, 'fit', 120, 'fit', ...
                'fit'}, 'RowHeight', {'fit', 'fit'}, 'Padding', 0);
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
            c.targetResidualMode = uidropdown(residualControls, 'Items', {'ベクトル', 'X（色）', 'Y（色）'}, ...
                'ItemsData', {'vector', 'X', 'Y'}, 'ValueChangedFcn', onResidual);
            place(c.targetResidualMode, 1, 6);
            c.targetResidualSave = uibutton(residualControls, 'Text', '画像で保存…', ...
                'ButtonPushedFcn', @(~, ~) app.onSaveTargetResidualFigure());
            place(c.targetResidualSave, 1, 7);
            c.targetResidualCopy = uibutton(residualControls, 'Text', 'コピー', 'Tooltip', app.COPY_TOOLTIP, ...
                'ButtonPushedFcn', @(source, ~) app.onCopyFigure("targetResidual", source));
            place(c.targetResidualCopy, 1, 8);
            label(residualControls, '並べ方', 2, 1);
            c.targetResidualArrange = uidropdown(residualControls, 'Items', {'1つの図', '補正前・補正量・残差を並べる'}, ...
                'ItemsData', {'single', 'side'}, 'ValueChangedFcn', onResidual, 'Tooltip', ['並べる：補正前の値・補正量・' ...
                '補正後の残差を、矢印の倍率と色の範囲をそろえて横に並べます。']);
            place(c.targetResidualArrange, 2, 2);
            label(residualControls, '図', 2, 3);
            c.targetResidualView = uidropdown(residualControls, 'Items', {'Wafer 上', 'Shot スタックマップ'}, ...
                'ItemsData', {'wafer', 'stack'}, 'ValueChangedFcn', onResidual, 'Tooltip', ['Shot スタックマップ：全 Shot の' ...
                '点を Shot 内の座標で1つの Shot に重ね、位置ごとの平均を濃い矢印で描きます。']);
            place(c.targetResidualView, 2, 4);
            label(residualControls, '重ねる円 [mm]', 2, 5);
            c.targetResidualCircles = uieditfield(residualControls, 'text', 'Value', '', 'ValueChangedFcn', onResidual, ...
                'Tooltip', 'Wafer 上の図に重ねる円の半径 [mm]（空白区切りでいくつでも。例：100 135）。');
            place(c.targetResidualCircles, 2, 6);
            c.targetResidualPanel = uipanel(residualGrid, 'BorderType', 'none');
            place(c.targetResidualPanel, 2, 1);
            c.targetResidualGrid = uigridlayout(c.targetResidualPanel, [1, 3], 'ColumnWidth', {'1x', 0, 0}, 'Padding', 0, ...
                'ColumnSpacing', 6);
            c.targetResidualAxesList = [uiaxes(c.targetResidualGrid), uiaxes(c.targetResidualGrid), uiaxes(c.targetResidualGrid)];
            c.targetResidualAxes = c.targetResidualAxesList(1);
            axesPlaceholder(app, c.targetResidualAxesList, '「重ね合わせ補正値を計算する」を押すと、ここに補正残差の図が出ます。');
            c.targetResidualInfo = uilabel(residualGrid, 'WordWrap', 'on', 'Text', '「重ね合わせ補正値を計算する」で残差を描きます。');
            place(c.targetResidualInfo, 3, 1);
            % 補正の比較：全計測・一部計測＋面内推定のそれぞれで、基準の補正（2. の条件）と、未知の座標の推定値を足した
            % このタブの補正を、計測値のある Mark の補正後の |平均|+3σ で比べる（alignest.targetCorrectionComparison）
            compareTab = uitab(outputs, 'Title', '補正の比較');
            % 左に表（補正ごとに1行）と説明、右に棒と残差の図を中のタブで切り替える（窓が小さくても図が潰れないように、
            % 表と図を縦に重ねない）
            compareGrid = uigridlayout(compareTab, [2, 2], 'RowHeight', {'fit', '1x'}, 'ColumnWidth', {'1.3x', '1x'}, ...
                'Padding', 6, 'RowSpacing', 6, 'ColumnSpacing', 8);
            compareHeader = uigridlayout(compareGrid, [1, 6], 'ColumnWidth', {'fit', '1x', 'fit', 230, 'fit', 'fit'}, 'Padding', 0);
            place(compareHeader, 1, [1, 2]);
            c.targetCompareButton = primaryButton(app, compareHeader, '全計測と比べる', @(~, ~) app.onCompareTargetCorrection());
            c.targetCompareButton.Tooltip = ['選んだ組み合わせの Wafer で、全計測と一部計測＋面内推定（学習パターン）の' ...
                'それぞれを、基準の補正（2. の条件）と、未知の座標の推定値を足したこのタブの補正で補正し、計測値のある' ...
                ' Mark の補正後の |平均|+3σ を比べます。'];
            place(c.targetCompareButton, 1, 1);
            c.targetCompareInfo = uilabel(compareHeader, 'WordWrap', 'on', 'Text', '');
            place(c.targetCompareInfo, 1, 2);
            label(compareHeader, '図の補正', 1, 3);
            c.targetCompareScenario = uidropdown(compareHeader, 'Items', {'—'}, 'ItemsData', {1}, 'Enable', 'off', ...
                'ValueChangedFcn', @(~, ~) app.showTargetComparison(), 'Tooltip', '「残差のマップ」のタブに描く補正（補正後の残差のベクトル）。');
            place(c.targetCompareScenario, 1, 4);
            c.targetCompareSave = uibutton(compareHeader, 'Text', '画像で保存…', ...
                'ButtonPushedFcn', @(~, ~) saveFigureWithDialog(app, "targetCompare", 'target_correction_compare.png'));
            place(c.targetCompareSave, 1, 5);
            c.targetCompareCopy = uibutton(compareHeader, 'Text', 'コピー', 'Tooltip', app.COPY_TOOLTIP, ...
                'ButtonPushedFcn', @(source, ~) app.onCopyFigure("targetCompare", source));
            place(c.targetCompareCopy, 1, 6);
            compareLeft = uigridlayout(compareGrid, [2, 1], 'RowHeight', {app.TARGET_COMPARE_TABLE_HEIGHT, '1x'}, ...
                'Padding', 0, 'RowSpacing', 6);
            place(compareLeft, 2, 1);
            c.targetCompareTable = uitable(compareLeft, 'RowName', {}, 'Data', table(), 'Tooltip', ['補正後の値は計測値のある' ...
                ' Mark の |平均|+3σ [nm]。① 全計測・② 一部計測＋面内推定は「2. 面内推定の設定」の Overlay 補正（基準）、' ...
                '③ 全計測・④ 一部計測＋面内推定は未知の座標の推定値を足して「補正のモデル」の式で補正し、補正量を計測値の' ...
                'ある Mark に当てた「計測値 − 補正量」で比べます。']);
            place(c.targetCompareTable, 1, 1);
            c.targetCompareDetail = uilabel(compareLeft, 'WordWrap', 'on', 'VerticalAlignment', 'top', 'Text', '', ...
                'FontColor', app.Palette.muted, 'UserData', "muted");
            place(c.targetCompareDetail, 2, 1);
            compareViews = uitabgroup(compareGrid);
            place(compareViews, 2, 2);
            c.targetCompareBarAxes = uiaxes(uigridlayout(uitab(compareViews, 'Title', '棒グラフ'), [1, 1], 'Padding', 4));
            c.targetCompareMapAxes = uiaxes(uigridlayout(uitab(compareViews, 'Title', '残差のマップ'), [1, 1], 'Padding', 4));
            for ax = [c.targetCompareBarAxes, c.targetCompareMapAxes]   % 中のタブごとに案内を出す
                axesPlaceholder(app, ax, '推定して「全計測と比べる」を押すと、ここに補正後の重ね合わせの比較が出ます。');
            end
            set([c.targetRun, c.targetExport, c.targetSaveFigure, c.targetCopyFigure, c.targetAddShots, c.targetOverlayButton, ...
                c.targetOverlayRecompute, c.targetResidualSave, c.targetResidualCopy, c.targetOverlayExport, ...
                c.targetCompareButton, c.targetCompareSave, c.targetCompareCopy], 'Enable', 'off');
            app.Controls = mergeStruct(app.Controls, c);
            targetCorrectionSettingsToControls(app);
            onTargetEdited(app);
        end

        function onTabChanged(app, event)
            % 「5. 未知の座標の推定」を開いたら、選択肢（Wafer・学習データ・手法）を今のデータ・結果・設定に合わせる。
            % 「6. Shot高次補正」を開いたら、入力のデータの一覧を今のデータ・推定値に合わせる。
            % 「2. 面内推定の設定」を開いたら、計測マップの選択肢をそろえる（描くのは「計測マップを作る」を押したとき）
            % 「3. 結果一覧」から後のタブは、初めて開いたときに中身を作る（ensureTab）
            ensureTab(app, tabName(app, event.NewValue));
            if event.NewValue == app.Tabs.settings
                prepareMeasurementChoices(app);
            elseif event.NewValue == app.Tabs.target
                refreshTargetChoices(app);
            elseif event.NewValue == app.Tabs.highOrder
                refreshHighOrderChoices(app);
            elseif event.NewValue == app.Tabs.markLayout
                refreshMarkLayoutChoices(app);   % データ・「6. Shot高次補正」の入力・保存した項の組み合わせが変わっていれば合わせる
                refreshMarkLayoutInput(app);
            elseif event.NewValue == app.Tabs.rotation
                refreshRotationChoices(app);   % データ・評価の結果・未知の座標の推定が変わっていれば合わせる
                updateRotationEnabled(app);
            end
            redrawShownResizedCharts(app);   % 窓の大きさを変えたあと、まだ描き直していない図
        end

        function refreshTargetChoices(app)
            % 推定の条件の選択肢を作り直す（前に選んでいたものが残っていれば、そのまま選ぶ）
            c = app.Controls;
            if ~isfield(c, 'targetWafer')
                return   % タブをまだ作っていない（作るときに合わせる）
            end
            hasData = ~isempty(app.Data);
            if hasData
                labels = string({app.Data.units.label});
                setListChoices(c.targetWafer, labels, num2cell(1:numel(labels)));
            else
                setListChoices(c.targetWafer, "—（データを読み込んでください）", {1});
            end
            trainingItems = "全 Mark";
            trainingData = {char(app.TARGET_ALL_TRAINING)};
            if ~isempty(app.Results) && ~isImportedResults(app.Results) && isfield(app.Results, 'plans')
                planLabels = unique(string({app.Results.plans.label}), 'stable');
                trainingItems = [trainingItems, "学習パターン：" + planLabels];
                trainingData = [trainingData, cellstr(planLabels)];
            end
            setListChoices(c.targetTraining, trainingItems, trainingData);
            setModeChoices(c.targetMode, alignest.valueSpec(app.Settings.data), true);   % GPR の推定の分散も選べる
            methods = alignest.activeMethods(app.Settings);   % 1変数では RT モデルを除く
            if isempty(methods)
                setChoices(c.targetMethod, "—（「2. 面内推定の設定」で手法を選んでください）", {1});
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
            c.targetInfo.Text = sprintf('%d 点', n);
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
                "「2. 面内推定の設定」の Overlay 補正で補正モデル（Wafer 成分・Shot 共通成分・Shot ごとの成分）を選んでください。");
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
                text = "全 Mark";
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
            if any(string(e.Properties.VariableNames) == "varianceX") && any(isfinite([e.varianceX; e.varianceY]))
                % GPR：推定の分散の列を推定値の右に足す
                shown = addvars(shown, round(e.varianceX, 4), round(e.varianceY, 4), 'After', "推定値 Y [nm]", ...
                    'NewVariableNames', ["分散 X [nm²]", "分散 Y [nm²]"]);
                if spec.scalar
                    shown = removevars(shown, "分散 Y [nm²]");
                    shown.Properties.VariableNames{'分散 X [nm²]'} = char("分散 [" + spec.unit + "²]");
                end
            end
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
            set([c.targetOverlayButton, c.targetOverlayRecompute, c.targetCompareButton], 'Enable', onOff(~spec.scalar));   % 補正は X・Y の2成分が要る
            setChoices(c.targetCombination, run.labels, num2cell(1:numel(run.labels)));
            c.targetCombination.Enable = 'on';
            showTargetCombination(app);
        end

        function showTargetCombination(app)
            % 選んだ組み合わせ（Wafer × 学習データ）の図と重ね合わせ補正を出す
            drawTargetMap(app);
            showTargetOverlay(app);
            showTargetComparison(app);
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
            cla(c.targetAxes, 'reset');   % 空のときの案内を消し、目盛りの枠を出す
            alignest.plot.targetMap(c.targetAxes, run.results{position}, unit, mode=string(c.targetMode.Value), ...
                titleText=titleText, waferRadiusMm=app.Settings.data.waferRadiusMm, spec=alignest.valueSpec(app.Settings.data));
            radii = targetCircleRadii(c.targetCircles);   % 「重ねる円」の半径 [mm]
            if ~isempty(radii)
                hold(c.targetAxes, 'on');
                alignest.plot.radiusCircles(c.targetAxes, radii);
                hold(c.targetAxes, 'off');
            end
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
                choice = alignest.targetCorrectionChoice(app.Settings);
            catch err
                note = "補正モデルに誤りがあるので、重ね合わせ補正値は書き出していない：" + string(err.message);
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
                    ~isequaln(run.overlayModel, app.Settings.targetCorrection)
                text = "⚠ 補正モデルを変えました。「重ね合わせ補正値を計算する」で計算し直してください（下は前のモデルの値）。";
            end
        end

        function onTargetCorrectionModelChanged(app)
            % 「補正のモデル」の式を変えた：設定に入れ、項の表を作り直す（式に無くなった項のチェックは捨てる）
            c = app.Controls;
            app.Settings.targetCorrection.waferOrder = c.targetCorrectionWafer.Value;
            app.Settings.targetCorrection.shotCommon = string(c.targetCorrectionShotCommon.Value);
            app.Settings.targetCorrection.perShot = string(c.targetCorrectionPerShot.Value);
            keys = alignest.targetCorrectionTerms(app.Settings).key;
            app.Settings.targetCorrection.excludedTerms = intersect(reshape(string( ...
                app.Settings.targetCorrection.excludedTerms), 1, []), keys, 'stable');
            refreshTargetCorrectionTerms(app);
            showTargetOverlay(app);   % 計算した補正値が前のモデルなら、その旨を出す
        end

        function targetCorrectionSettingsToControls(app)
            % 設定（settings.targetCorrection）を「補正のモデル」の欄に写す（設定ファイルを読んだ・初期設定に戻したときも呼ぶ）
            c = app.Controls;
            if ~isfield(c, 'targetCorrectionWafer')
                return
            end
            try
                choice = alignest.targetCorrectionChoice(app.Settings);
            catch
                app.Settings.targetCorrection = alignest.defaultSettings().targetCorrection;   % 読めない値は初期値にする
                choice = alignest.targetCorrectionChoice(app.Settings);
            end
            app.Settings.targetCorrection.excludedTerms = choice.excludedTerms;
            c.targetCorrectionWafer.Value = choice.waferOrder;
            c.targetCorrectionShotCommon.Value = char(choice.shotCommon);
            c.targetCorrectionPerShot.Value = char(choice.perShot);
            refreshTargetCorrectionTerms(app);
        end

        function terms = refreshTargetCorrectionTerms(app)
            % 「補正のモデル」の項の表（成分・軸・項・次数・使う）と説明。0次・1次の項は外せないので薄い色にする
            c = app.Controls;
            terms = alignest.targetCorrectionTerms(app.Settings);
            c.targetCorrectionTable.Data = table(terms.componentLabel, terms.axis, terms.name, terms.order, terms.used, ...
                'VariableNames', ["成分", "軸", "項", "次数", "使う"]);
            removeStyle(c.targetCorrectionTable);
            if any(terms.required)
                addStyle(c.targetCorrectionTable, uistyle('FontColor', app.Palette.muted), 'row', find(terms.required));
            end
            choice = alignest.targetCorrectionChoice(app.Settings);
            baseline = "（式に誤りがあります）";
            try
                baseline = alignest.overlayChoice(app.Settings).description;
            catch
            end
            c.targetCorrectionInfo.Text = char("このタブの補正：" + choice.description + "　｜　基準の補正（「2. 面内推定の設定」）：" + ...
                baseline + "。項は「使う」で選びます（0次・1次は外せません）。");
            c.targetOverlayRecompute.Enable = onOff(~isempty(app.TargetRun) && choice.enabled);
        end

        function onTargetCorrectionTermEdited(app, event)
            % 項の表の「使う」を変えた（0次・1次の項は戻して知らせる）
            terms = alignest.targetCorrectionTerms(app.Settings);
            row = event.Indices(1);
            if row > height(terms)
                return
            end
            if ~runWithAlert(app, @() app.setTargetCorrectionTermUsed(terms.key(row), logical(event.NewData)), ...
                    "項を外せませんでした", "0次・1次の項は補正の土台なので、使ったままにしてください。")
                refreshTargetCorrectionTerms(app);
            end
        end

        function showTargetResidualPanels(app, count)
            % 補正残差のマップの図の数（1つ・3つ並べる）。使わない図はしまう
            c = app.Controls;
            c.targetResidualGrid.ColumnWidth = [repmat({'1x'}, 1, count), repmat({0}, 1, 3 - count)];
            for k = count + 1:3
                ax = c.targetResidualAxesList(k);
                cla(ax, 'reset');
                legend(ax, 'off');
                colorbar(ax, 'off');
                ax.Visible = 'off';
            end
        end

        function onCompareTargetCorrection(app)
            runWithAlert(app, @() app.compareTargetCorrection(), "比べられませんでした", ...
                "「推定する」で推定し、補正のモデルと「2. 面内推定の設定」の Overlay 補正を確かめてから、もう一度試してください。");
        end

        function showTargetComparison(app)
            % 「補正の比較」：選んだ組み合わせの比較の表・棒（補正後の |平均|+3σ。X・Y）と、補正ごとの補正後の残差の図
            c = app.Controls;
            run = app.TargetRun;
            comparison = [];
            if ~isempty(run) && isfield(run, 'comparison')
                position = min(max(c.targetCombination.Value, 1), numel(run.results));
                comparison = run.comparison{position};
            end
            set([c.targetCompareButton], 'Enable', onOff(~isempty(run)));
            if isempty(comparison)
                c.targetCompareTable.Data = table();
                setChoices(c.targetCompareScenario, "—", {1});
                c.targetCompareScenario.Enable = 'off';
                c.targetCompareInfo.Text = '推定して、補正のモデルを選んでから「全計測と比べる」を押してください。';
                c.targetCompareDetail.Text = '';
                for ax = [c.targetCompareBarAxes, c.targetCompareMapAxes]
                    axesPlaceholder(app, ax, '推定して「全計測と比べる」を押すと、ここに補正後の重ね合わせの比較が出ます。');
                end
                set([c.targetCompareSave, c.targetCompareCopy], 'Enable', 'off');
                return
            end
            t = comparison.table;
            % 表は補正ごとに1行（X・Y を横に並べる。補正の名前は「｜」の前だけ。後ろの補正の種類は「図の補正」の欄とヘルプ）
            scenarios = unique(t.scenario, 'stable');
            [values, before] = deal(nan(numel(scenarios), 2));
            targetCount = zeros(numel(scenarios), 1);
            for k = 1:numel(scenarios)
                rowX = t.scenario == scenarios(k) & t.axis == "X";
                rowY = t.scenario == scenarios(k) & t.axis == "Y";
                values(k, :) = [t.residual(rowX), t.residual(rowY)];
                before(k, :) = [t.before(rowX), t.before(rowY)];
                targetCount(k) = t.targets(find(rowX, 1));
            end
            c.targetCompareTable.Data = table(extractBefore(scenarios, "｜"), round(values(:, 1), 3), ...
                round(values(:, 2), 3), 'VariableNames', ["補正", "X [nm]", "Y [nm]"]);
            c.targetCompareTable.ColumnWidth = {'auto', 80, 80};
            used = targetCount > 0;
            first = t.scenario == scenarios(1);
            c.targetCompareDetail.Text = char(sprintf(['補正後の |平均|+3σ。比べた Mark は X %d 点・Y %d 点、補正前は' ...
                ' X %.3f nm・Y %.3f nm。③④ は未知の座標の点 %d 点を足して補正。'], t.n(first & t.axis == "X"), ...
                t.n(first & t.axis == "Y"), before(1, 1), before(1, 2), max([targetCount(used); 0])));
            % 棒：補正ごとに X・Y の補正後の |平均|+3σ（横軸は補正の番号 ①〜④。名前は表）
            ax = c.targetCompareBarAxes;
            cla(ax, 'reset');
            ax.Visible = 'on';
            bars = bar(ax, values);
            set(bars(1), 'DisplayName', 'X');
            set(bars(2), 'DisplayName', 'Y');
            xticks(ax, 1:numel(scenarios));
            xticklabels(ax, cellstr(extractBefore(scenarios, 2)));
            ylabel(ax, '補正後の |平均|+3σ [nm]');
            title(ax, '補正後の重ね合わせ（計測値のある Mark）', 'Interpreter', 'none');
            grid(ax, 'on');
            legend(ax, 'Location', 'northwest', 'Box', 'off');
            % 選んだ補正の補正後の残差（計測値のある Mark）
            names = [comparison.maps.scenario];
            chosen = c.targetCompareScenario.Value;
            setChoices(c.targetCompareScenario, names, num2cell(1:numel(names)));
            c.targetCompareScenario.Value = min(max(chosen, 1), numel(names));
            c.targetCompareScenario.Enable = 'on';
            k = c.targetCompareScenario.Value;
            unit = app.Data.units(comparison.unitIndex);
            mapAx = c.targetCompareMapAxes;
            cla(mapAx, 'reset');
            legend(mapAx, 'off');
            colorbar(mapAx, 'off');
            mapAx.Visible = 'on';
            alignest.plot.correctionMap(mapAx, comparisonCorrection(unit, comparison.maps(k).residual), unit, ...
                value="residual", mode="vector", titleText=extractBefore(names(k), "｜"), showStatistics=true, ...
                legendLocation="none", waferRadiusMm=app.Settings.data.waferRadiusMm, markMeasured=false, ...
                valueLabel="補正後の残差");
            styleAxes(app, [ax, mapAx], app.AXES_FONT_SIZE);
            set([c.targetCompareSave, c.targetCompareCopy], 'Enable', 'on');
            stale = "";
            if ~isequaln(comparison.model, app.Settings.targetCorrection) || ~isequaln(comparison.baselineModel, app.Settings.overlay)
                stale = "⚠ 補正のモデルを変えました。「全計測と比べる」で比べ直してください（下は前のモデルの値）。";
            end
            c.targetCompareInfo.Text = char(stale + comparison.label);
            c.targetCompareInfo.Tooltip = char("基準の補正：" + comparison.baseline + "。このタブの補正：" + ...
                alignest.targetCorrectionChoice(struct("targetCorrection", comparison.model)).description + "。");
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
                c.targetOverlayInfo.Text = '「重ね合わせ補正値を計算する」で補正値と残差を出します。';
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
            highOrderInputChanged(app, "target");
            c = app.Controls;
            if ~isfield(c, 'targetResultTable')
                return
            end
            c.targetResultTable.Data = table();
            removeStyle(c.targetResultTable);
            axesPlaceholder(app, c.targetAxes, '左の表に点を決めて「推定する」を押すと、ここに推定値の図が出ます。');
            set([c.targetExport, c.targetSaveFigure, c.targetCopyFigure, c.targetOverlayButton, c.targetOverlayRecompute, c.targetCombination, ...
                c.targetResidualSave, c.targetResidualCopy, c.targetOverlayExport], 'Enable', 'off');
            showTargetResidualPanels(app, 1);
            axesPlaceholder(app, c.targetResidualAxesList, '「重ね合わせ補正値を計算する」を押すと、ここに補正残差の図が出ます。');
            c.targetResidualInfo.Text = '「重ね合わせ補正値を計算する」で残差を描きます。';
            showTargetComparison(app);
            setChoices(c.targetCombination, "—", {1});
            c.targetOverlaySummary.Data = table();
            c.targetOverlayTable.Data = table();
            c.targetOverlayInfo.Text = '「重ね合わせ補正値を計算する」で補正値と残差を出します。';
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

function points = targetResidualPoints(correction, source)
% 補正残差のマップに描く点（点の種類で絞る。alignest.plot.correctionMap と同じ種類の名前）
SOURCE_NAMES = struct("target", "推定値（未知の座標）", "measured", "実測値（学習点）", ...
    "estimated", "推定値（学習しなかった Mark）");
points = correction.points;
if source ~= "all"
    points = points(points.source == SOURCE_NAMES.(source), :);
end
end

function text = targetValueLabel(name)
% 補正残差のマップの値の名前
labels = struct("value", "補正前の値", "correction", "補正量", "residual", "補正後の残差");
text = string(labels.(name));
end

function radii = targetCircleRadii(field)
% 「重ねる円」の半径 [mm]（空白区切り。数でない・0 以下・Wafer の直径より大きい値は使わない）
MAX_RADIUS_MM = 300;
values = str2double(split(strtrim(string(field.Value))));
radii = reshape(unique(values(isfinite(values) & values > 0 & values <= MAX_RADIUS_MM)), 1, []);
end

function value = meanPlus3Sigma(values)
% |平均| + 3σ（σ は不偏標準偏差）。点が2点未満なら NaN
values = values(isfinite(values));
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end

function correction = comparisonCorrection(unit, residual)
% 補正の比較の図に描く点（計測値のある Mark の補正後の残差。alignest.plot.correctionMap の correction の形）
marks = unit.marks;
rows = find(any(isfinite(residual), 2));
n = numel(rows);
shotNo = nan(n, 1);
inShot = marks.shotIndex(rows) >= 1;
shotNo(inShot) = unit.shots.shotNo(marks.shotIndex(rows(inShot)));
correction.points = table(repmat("実測値（学習点）", n, 1), strings(n, 1), shotNo, marks.x(rows), marks.y(rows), ...
    nan(n, 1), nan(n, 1), nan(n, 1), nan(n, 1), residual(rows, 1), residual(rows, 2), marks.markXmm(rows), ...
    marks.markYmm(rows), 'VariableNames', ["source", "name", "shotNo", "x", "y", "valueX", "valueY", "correctionX", ...
    "correctionY", "residualX", "residualY", "localX", "localY"]);
correction.description = "";
end
