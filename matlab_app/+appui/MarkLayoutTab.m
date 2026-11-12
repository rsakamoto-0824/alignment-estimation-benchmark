classdef (Abstract) MarkLayoutTab < appui.Core
    %MARKLAYOUTTAB 「8. Mark配置の最適化」タブ：Shot 高次補正の計測 Mark の配置を、Mark の数ごとに I 最適計画で選び、選んだ
    %   配置で補正した制御残差を I 効率と比べる（alignest.markLayoutStudy）。
    %   入力：「1. データ読込」の計測データ・「7. Shot高次補正」の入力のデータ・このタブで読み込む Excel・CSV（列は読んだ後で
    %   選ぶ。座標だけの表も読める）・画面で入力する座標（格子で置ける）。候補の Mark の表で、必ず計測する Mark を選ぶ（配置の
    %   図をクリックしても選べる）。補正の式（ASML・Canon・Nikon・カスタム、保存した項の組み合わせ。VIF で項を選ぶ）と回帰
    %   （ロバスト回帰・正則化）は「7. Shot高次補正」と同じ。実測値の無い座標は、乱数の Shot の形（最大 1000 通り。次数ごとの
    %   大きさ・計測のばらつき・飛び値）で評価する。
    %   AlignmentEstimationApp（画面の本体）の一部。画面の部品は Controls、データ・結果は Core のプロパティに持つ。

    properties (Constant, Access = {?appui.Core})
        MARK_GRID_SPAN_MM = [24, 30]   % 「格子で置く」の、端の Mark どうしの幅・高さ [mm] の初期値
        MARK_GRID_COUNTS = [7, 11]     % 「格子で置く」の列・行の数の初期値
        MARK_MAX_LABELS = 16           % 制御残差推移の図で、点に Mark の数を書く数の上限（多いときは間引く）
        MARK_SET_PREFIX = "set:"       % 補正の式の選択肢で、保存した項の組み合わせを選ぶ値の頭
        MARK_Y_COLOR = [0.85, 0.40, 0.10]   % 制御残差推移の図の Y の線の色（X は PRIMARY_COLOR）
        MARK_REQUIRED_COLOR = [0.80, 0.10, 0.10]  % 必ず計測する Mark・飛び値の色
        MARK_ABSENT_COLOR = [0.65, 0.65, 0.65]    % 「使う項と VIF」の表で、その式に無い項のチェック欄の色
        MARK_CRITERION_EMPTY = '「配置を最適化する」を押すと、配置を選んだ I 最適計画の式と使った項が出ます。'
    end

    methods
        function setMarkLayoutSource(app, source)
            %SETMARKLAYOUTSOURCE 入力を選ぶ："manual"（画面で入力する座標）・"data"（「1. データ読込」の計測データ）・
            %   "highOrder"（「7. Shot高次補正」で選んでいる入力のデータと Wafer）・"file"（このタブで読み込んだ Excel・CSV）。
            app.Controls.markOptSource.Value = char(source);
            onMarkLayoutSourceChanged(app);
        end

        function setMarkLayoutSettings(app, options)
            %SETMARKLAYOUTSETTINGS 補正の式・回帰・配置の選び方・乱数の形の欄を変える（画面で選ぶのと同じ）。名前と値の組で渡す：
            %   maker（"asml"・"canon"・"nikon"・"custom"）・termSet（保存した項の組み合わせの名前）・vifThreshold・loss
            %   （"ols"・"huber"・"lad"）・huberTuning・regularization（"none"・"l2"・"l1"）・lambda（1つなら X・Y 両方、[X, Y] なら
            %   軸ごと）・penaltyOrders（1〜6 の並び。X・Y 両方）・penaltyOrdersY（Y だけ）・minMarks・maxMarks（0 = 使う項の数・
            %   すべての候補）・starts・values（"measured"・"random"）・shapes・
            %   orderSigmaNm（0〜7次の8つ）・noiseNm・outlierPercent・outlierNm。乱数の種は setRandomSeed（メニュー「設定」→
            %   「乱数の種…」。学習 Shot の選び方と共通）。
            %   例：app.setMarkLayoutSettings(maker="canon", values="random", shapes=500, outlierPercent=5)
            arguments
                app
                options.maker (1, 1) string
                options.termSet (1, 1) string
                options.vifThreshold (1, 1) double
                options.loss (1, :) string
                options.huberTuning (1, :) double
                options.regularization (1, :) string
                options.penaltyOrders double
                options.penaltyOrdersY double
                options.lambda (1, :) double
                options.minMarks (1, 1) double
                options.maxMarks (1, 1) double
                options.starts (1, 1) double
                options.values (1, 1) string
                options.shapes (1, 1) double
                options.orderSigmaNm (1, 8) double
                options.noiseNm (1, 1) double
                options.outlierPercent (1, 1) double
                options.outlierNm (1, 1) double
            end
            c = app.Controls;
            if isfield(options, "termSet")
                value = char(app.MARK_SET_PREFIX + options.termSet);
                if ~any(strcmp(c.markOptMaker.ItemsData, value))
                    error('alignest:markLayout', '保存した項の組み合わせ「%s」がありません。', options.termSet);
                end
                c.markOptMaker.Value = value;
            end
            options = setRegressionControls(c.markOptRegression, options);
            fields = struct("maker", c.markOptMaker, "vifThreshold", c.markOptVifThreshold, ...
                "minMarks", c.markOptMinMarks, "maxMarks", c.markOptMaxMarks, "starts", c.markOptStarts, ...
                "values", c.markOptValues, "shapes", c.markOptShapes, "noiseNm", c.markOptNoise, ...
                "outlierPercent", c.markOptOutlierPercent, "outlierNm", c.markOptOutlierSize);
            if isfield(options, "values")
                app.MarkLayoutValuesAuto = false;
            end
            for name = string(fieldnames(options)).'
                if isfield(fields, name)
                    control = fields.(name);
                    if isa(control, 'matlab.ui.control.DropDown')
                        if ~any(strcmp(control.ItemsData, char(options.(name))))
                            error('alignest:markLayout', '%s に「%s」は選べません。', name, options.(name));
                        end
                        control.Value = char(options.(name));
                    else
                        control.Value = options.(name);
                    end
                end
            end
            if isfield(options, "orderSigmaNm")
                for order = 1:numel(c.markOptOrderSigma)
                    c.markOptOrderSigma(order).Value = options.orderSigmaNm(order);
                end
            end
            onMarkLayoutSettingsChanged(app);
        end

        function candidates = setMarkLayoutCoordinates(app, coordinates, required)
            %SETMARKLAYOUTCOORDINATES 画面で入力する候補の Mark の座標（点の数 × 2 [mm]。Shot 中心から）を決め、入力を「画面で
            %   入力する座標」にする。required（省略可）：必ず計測する Mark（点の数 × 1 の logical。これまでの指定と置き換える）。
            %   candidates は候補の Mark の表（同じ位置はまとめ、上の行・左から番号を付ける）。
            if size(coordinates, 2) ~= 2 || any(~isfinite(coordinates(:)))
                error('alignest:markLayout', '座標は X・Y の2列の数にしてください。');
            end
            app.Settings.markLayout.coordinateXmm = reshape(coordinates(:, 1), [], 1);
            app.Settings.markLayout.coordinateYmm = reshape(coordinates(:, 2), [], 1);
            if nargin >= 3
                required = logical(reshape(required, [], 1));
                app.Settings.markLayout.requiredXmm = reshape(coordinates(required, 1), [], 1);
                app.Settings.markLayout.requiredYmm = reshape(coordinates(required, 2), [], 1);
            end
            app.Controls.markOptSource.Value = 'manual';
            onMarkLayoutSourceChanged(app);
            candidates = app.MarkLayoutInput.candidates;
        end

        function candidates = makeMarkLayoutGrid(app, spanMm, counts)
            %MAKEMARKLAYOUTGRID 「格子で置く」：候補の Mark を、Shot 中心を真ん中にした格子に置く（画面で入力する座標にする）。
            %   spanMm：[幅, 高さ]（端の Mark どうしの間 [mm]）、counts：[列の数, 行の数]（省略すると画面の欄）。
            c = app.Controls;
            if nargin >= 2
                c.markOptGridWidth.Value = spanMm(1);
                c.markOptGridHeight.Value = spanMm(2);
            end
            if nargin >= 3
                c.markOptGridColumns.Value = counts(1);
                c.markOptGridRows.Value = counts(2);
            end
            columns = c.markOptGridColumns.Value;
            rows = c.markOptGridRows.Value;
            x = linspace(-c.markOptGridWidth.Value / 2, c.markOptGridWidth.Value / 2, columns);
            y = linspace(-c.markOptGridHeight.Value / 2, c.markOptGridHeight.Value / 2, rows);
            if columns == 1
                x = 0;
            end
            if rows == 1
                y = 0;
            end
            [gridX, gridY] = meshgrid(x, y);
            candidates = setMarkLayoutCoordinates(app, [gridX(:), gridY(:)]);
        end

        function candidates = setMarkLayoutRequired(app, markNumbers, required)
            %SETMARKLAYOUTREQUIRED 候補の Mark の番号（「候補の Mark」の表の No）を、必ず計測する（required = true）・しない
            %   （false）にする。どの数の配置にも必ず入る。candidates は候補の Mark の表。
            input = app.MarkLayoutInput;
            if isempty(input)
                error('alignest:markLayout', '先に入力を選んでください（候補の Mark がありません）。');
            end
            rows = ismember(input.candidates.no, markNumbers);
            if nnz(rows) ~= numel(unique(markNumbers))
                error('alignest:markLayout', '候補の Mark の番号は 1〜%d です。', height(input.candidates));
            end
            changeMarkState(app, [input.candidates.xMm(rows), input.candidates.yMm(rows)], ternary(required, "required", "none"));
            candidates = app.MarkLayoutInput.candidates;
        end

        function candidates = setMarkLayoutExcluded(app, markNumbers, excluded)
            %SETMARKLAYOUTEXCLUDED 候補の Mark の番号を、計測しない（excluded = true）・戻す（false）にする。計測しない Mark は
            %   配置に選ばないが、残差の評価には使う（必ず計測する指定は外れる）。candidates は候補の Mark の表。
            input = app.MarkLayoutInput;
            if isempty(input)
                error('alignest:markLayout', '先に入力を選んでください（候補の Mark がありません）。');
            end
            rows = ismember(input.candidates.no, markNumbers);
            if nnz(rows) ~= numel(unique(markNumbers))
                error('alignest:markLayout', '候補の Mark の番号は 1〜%d です。', height(input.candidates));
            end
            changeMarkState(app, [input.candidates.xMm(rows), input.candidates.yMm(rows)], ternary(excluded, "excluded", "none"));
            candidates = app.MarkLayoutInput.candidates;
        end

        function shapes = generateMarkLayoutShapes(app)
            %GENERATEMARKLAYOUTSHAPES 「乱数で Shot を生成する」：今の候補の Mark と項の大きさ・ばらつき・飛び値で乱数の Shot の形を
            %   作り（alignest.randomShotShapes）、代表の形を図に出す。評価に使う値が乱数の形のときは、この形で評価する。
            c = app.Controls;
            readMarkLayoutControls(app);
            options = alignest.markLayoutOptions(app.Settings);
            refreshMarkLayoutInput(app);
            input = app.MarkLayoutInput;
            if isempty(input)
                error('alignest:markLayout', '%s', c.markOptInputInfo.Text);
            end
            shapes = alignest.randomShotShapes(input.candidates.xMm, input.candidates.yMm, shapes=options.shapes, ...
                seed=options.seed, orderSigmaNm=options.orderSigmaNm, noiseNm=options.noiseNm, ...
                outlierPercent=options.outlierPercent, outlierNm=options.outlierNm);
            app.MarkLayoutShapes = struct("shapes", shapes, "key", markLayoutShapeKey(app));
            c.markOptShapeIndex.Value = shapes.representative;
            c.markOptOutputs.SelectedTab = c.markOptShapeTab;
            drawMarkLayoutShape(app);
            showMarkLayoutMessages(app);
        end

        function data = loadMarkLayoutFile(app, filePath, sheetName)
            %LOADMARKLAYOUTFILE 入力にする Excel・CSV を読み（列の名前は自由）、項目に合う列を見出しから推定して「Excel・CSV の
            %   列」の表に出す（alignest.readHighOrderFile）。Shot 内の座標の列が見つかれば、その列で入力にする
            %   （applyMarkLayoutMapping）。X・Y の値の列が無い表は、候補の Mark の座標だけとして読む。
            if nargin < 3
                sheetName = "";
            end
            [raw, info] = alignest.readHighOrderFile(filePath, sheetName);
            app.MarkLayoutFile = struct("raw", raw, "info", info, "mapping", info.mapping, "wafers", [], ...
                "coordinates", zeros(0, 2), "dataInfo", []);
            c = app.Controls;
            showMarkLayoutMapping(app, info.mapping);
            c.markOptOutputs.SelectedTab = c.markOptColumnTab;
            data = [];
            if info.mapping.markXmm ~= "" && info.mapping.markYmm ~= ""
                try
                    data = applyMarkLayoutMapping(app);
                    c.markOptMappingStatus.Text = char("見出しから列を推定して読み込みました（" + markLayoutFileText(app) + ...
                        "）。違っていれば列を選び直し、「この列で使う」を押してください。");
                    c.markOptMappingStatus.FontColor = app.Palette.text;
                catch err
                    c.markOptMappingStatus.Text = ['⚠ 推定した列では読み込めませんでした：' err.message ...
                        ' 列を選び直し、「この列で使う」を押してください。'];
                    c.markOptMappingStatus.FontColor = app.Palette.error;
                end
            else
                c.markOptMappingStatus.Text = sprintf(['%d 行・%d 列を読みました。Shot 内の座標（必須）と、使う項目に' ...
                    'ファイルのどの列を使うかを選び、「この列で使う」を押してください。'], info.rows, numel(info.columns));
                c.markOptMappingStatus.FontColor = app.Palette.text;
            end
            c.markOptSource.Value = 'file';
            onMarkLayoutSourceChanged(app);
        end

        function data = applyMarkLayoutMapping(app, columns)
            %APPLYMARKLAYOUTMAPPING 「この列で使う」：「Excel・CSV の列」の表で選んだ列で、読み込んだ表を入力にする
            %   （alignest.markLayoutFileData。すべての Wafer を選ぶ）。columns（省略可）：表の選択を変える項目と列の名前の
            %   構造体（例：struct("measX", "OVL_X")。"" は列なし）。data は Wafer ごとの点（値が無い表は座標）。
            if isempty(app.MarkLayoutFile)
                error('alignest:markLayoutFile', '先に「Excel・CSV を読み込む…」で表を読み込んでください。');
            end
            mapping = currentMarkLayoutMapping(app);
            if nargin >= 2
                for name = string(fieldnames(columns)).'
                    mapping.(name) = string(columns.(name));
                end
            end
            showMarkLayoutMapping(app, mapping);
            [wafers, coordinates, info] = alignest.markLayoutFileData(app.MarkLayoutFile.raw, mapping);
            app.MarkLayoutFile.mapping = mapping;
            app.MarkLayoutFile.wafers = wafers;
            app.MarkLayoutFile.coordinates = coordinates;
            app.MarkLayoutFile.dataInfo = info;
            data = wafers;
            if isempty(wafers)
                data = coordinates;
            end
            c = app.Controls;
            c.markOptSource.Value = 'file';
            refreshMarkLayoutChoices(app);
            if ~isempty(wafers)
                c.markOptWafer.Value = num2cell(1:numel(wafers));   % 読み込んだ Wafer をすべて選ぶ
            end
            onMarkLayoutSourceChanged(app);
            c.markOptMappingStatus.Text = char("この列で読み込みました（" + markLayoutFileText(app) + "）。");
            c.markOptMappingStatus.FontColor = app.Palette.text;
        end

        function excluded = selectMarkLayoutTermsByVif(app, threshold)
            %SELECTMARKLAYOUTTERMSBYVIF 「VIF で選ぶ」：式のすべての項から始めて、候補の Mark の位置で求めた VIF がしきい値以上の
            %   高次項を外す（alignest.highOrderVif。k1〜k6 は外さない）。threshold を省略すると画面のしきい値。外した k の番号。
            c = app.Controls;
            if nargin >= 2
                c.markOptVifThreshold.Value = threshold;
            end
            readMarkLayoutControls(app);
            input = app.MarkLayoutInput;
            if isempty(input)
                error('alignest:markLayout', '先に入力を選んでください（VIF は候補の Mark の位置で求めます）。');
            end
            options = alignest.markLayoutOptions(app.Settings);
            local = [input.candidates.xMm, input.candidates.yMm];
            [~, info] = alignest.highOrderVif(alignest.highOrderTerms(options.maker), local, true(size(local)), ...
                options.vifThreshold);
            excluded = info.suggestedExcluded;
            app.Settings.markLayout.excludedTerms = excluded;
            refreshMarkLayoutTerms(app);
            showMarkLayoutMessages(app);
        end

        function useAllMarkLayoutTerms(app)
            %USEALLMARKLAYOUTTERMS 「すべての項を使う」：外した項を戻す
            app.Settings.markLayout.excludedTerms = zeros(1, 0);
            refreshMarkLayoutTerms(app);
            showMarkLayoutMessages(app);
        end

        function setMarkLayoutTermUsed(app, k, used)
            %SETMARKLAYOUTTERMUSED k の番号の項を使う（used = true）・使わない（false）にする（表のチェックと同じ）。
            %   k1〜k6（定数・1次）は外せない。
            if k <= 6 && ~used
                error('alignest:markLayout', 'k1〜k6（並進・倍率・回転）は補正の土台なので外せません。');
            end
            excluded = reshape(app.Settings.markLayout.excludedTerms, 1, []);
            if used
                excluded = excluded(excluded ~= k);
            else
                excluded = unique([excluded, k]);
            end
            app.Settings.markLayout.excludedTerms = excluded;
            refreshMarkLayoutTerms(app);
            showMarkLayoutMessages(app);
        end

        function copyHighOrderFormula(app)
            %COPYHIGHORDERFORMULA 「7. の式を写す」：「7. Shot高次補正」の補正の式（内周の式）・使う項・VIF のしきい値・回帰の
            %   設定を、このタブの設定にする。
            readHighOrderControls(app);
            source = alignest.highOrderOptions(app.Settings);
            for name = ["maker", "excludedTerms", "vifThreshold", "loss", "huberTuning", "regularization", ...
                    "penaltyOrders", "penaltyOrdersY", "lambda"]
                app.Settings.markLayout.(name) = source.(name);
            end
            markLayoutSettingsToControls(app);
            readMarkLayoutControls(app);
            showMarkLayoutMessages(app);
        end

        function study = optimizeMarkLayout(app, progressFcn)
            %OPTIMIZEMARKLAYOUT 「配置を最適化する」：今の入力・補正の式・回帰・配置の選び方で、Mark の数ごとに I 最適計画の配置を
            %   選び、制御残差を求めて、図・配置・表に出す（alignest.markLayoutStudy）。study は結果。progressFcn（省略可）：
            %   progressFcn(割合 0〜1, 説明) が false なら止める（進み具合の窓を出さずに動かすとき）。
            hasProgressFcn = nargin >= 2;
            readMarkLayoutControls(app);
            alignest.markLayoutOptions(app.Settings);   % 設定の誤りを先に知らせる
            refreshMarkLayoutInput(app);
            input = app.MarkLayoutInput;
            if isempty(input)
                error('alignest:markLayout', '%s', app.Controls.markOptInputInfo.Text);
            end
            dialog = [];
            if app.Figure.Visible == "on"
                dialog = appui.ProgressWindow(app.Figure, "Mark配置の最適化", "計算を始めています…", app.Palette, ...
                    app.FontSize, "止める");
            end
            cleanup = onCleanup(@() closeDialog(dialog));
            started = tic;
            shapes = [];
            if string(app.Settings.markLayout.values) == "random"
                if ~markLayoutShapesCurrent(app)
                    error('alignest:markLayoutShapes', ['先に「乱数 Shot 生成」の「乱数で Shot を生成する」を押して、' ...
                        '形を確かめてください。']);
                end
                shapes = app.MarkLayoutShapes.shapes;
            end
            study = alignest.markLayoutStudy(input.candidates, input.shots, app.Settings, ...
                @(fraction, message) reportProgress(fraction, message), shapes=shapes);
            study.seconds = toc(started);
            study.sourceText = input.text;
            study.snapshot = markLayoutSnapshot(app);
            app.MarkLayoutStudy = study;
            showMarkLayoutStudy(app);
            c = app.Controls;
            c.markOptOutputs.SelectedTab = c.markOptChartTab;
            if height(study.evaluation) == 0
                c.markOptOutputs.SelectedTab = c.markOptMapTab;   % 配置を選ぶ途中で止めた：制御残差の図はまだ無い
            end

            function continueRun = reportProgress(fraction, message)
                continueRun = ~hasProgressFcn || progressFcn(fraction, message);
                if isempty(dialog) || ~isvalid(dialog)
                    return
                end
                elapsed = toc(started);
                remaining = "";
                if fraction > 0.02
                    remaining = sprintf("。残り 約 %.0f 秒", elapsed / fraction * (1 - fraction));
                end
                dialog.Value = fraction;
                dialog.Message = char(message + remaining);
                drawnow;
                continueRun = continueRun && ~dialog.CancelRequested;
            end
        end

        function data = drawMarkLayoutChart(app, statistic, points, xAxis)
            %DRAWMARKLAYOUTCHART 制御残差推移の図：横軸は I 効率 [%]（計測できる Mark をすべて計測したとき 100%）など、縦軸は
            %   制御残差。X・Y の線に、Mark の数ごとの配置の点（数を書く）と、すべての Mark を計測したとき（★）。
            %   statistic："meanPlus3Sigma"・"p95"・"median"・"rms"、points："all"（すべての Mark の制御残差）・"unmeasured"
            %   （計測しなかった Mark だけ）、xAxis："efficiency"（I 効率）・"criterionI"（I 基準）・"count"（Mark の数）・
            %   "efficiencyD"（D 効率）・"criterionD"（D 基準）。省略すると画面の選択。data は図の値（Mark の数・I 効率・横軸の値
            %   xValue・X・Y）。
            c = app.Controls;
            if nargin >= 2 && strlength(string(statistic)) > 0
                c.markOptChartStatistic.Value = char(statistic);
            end
            if nargin >= 3
                c.markOptChartPoints.Value = char(points);
            end
            if nargin >= 4
                c.markOptChartAxis.Value = char(xAxis);
            end
            ax = c.markOptChartAxes;
            cla(ax, 'reset');
            legend(ax, 'off');
            data = table();
            study = app.MarkLayoutStudy;
            if isempty(study)
                c.markOptChartInfo.Text = c.markOptChartInfo.UserData;
                return
            end
            if height(study.evaluation) == 0
                c.markOptChartInfo.Text = '途中で止めたので、制御残差はありません。';
                return
            end
            [column, statisticLabel] = chartColumn(string(c.markOptChartStatistic.Value), ...
                string(c.markOptChartPoints.Value));
            evaluation = study.evaluation;
            xName = string(c.markOptChartAxis.Value);
            xLabelText = markChartAxisLabel(xName);
            optimal = evaluation(evaluation.layoutType == "I 最適", :);
            everything = evaluation(evaluation.layoutType ~= "I 最適", :);
            x = optimal(optimal.axis == "X", :);
            y = optimal(optimal.axis == "Y", :);
            colors = [app.PRIMARY_COLOR; app.MARK_Y_COLOR];
            hold(ax, 'on');
            plot(ax, x.(xName), x.(column), '-o', 'Color', colors(1, :), 'MarkerFaceColor', colors(1, :), ...
                'MarkerSize', 5, 'LineWidth', 1.2, 'DisplayName', 'X（dx の式）');
            plot(ax, y.(xName), y.(column), '-s', 'Color', colors(2, :), 'MarkerFaceColor', colors(2, :), ...
                'MarkerSize', 5, 'LineWidth', 1.2, 'DisplayName', 'Y（dy の式）');
            axisNames = ["X", "Y"];
            for k = 1:2
                mine = everything(everything.axis == axisNames(k), :);
                value = mine.(column);
                if ~isempty(value) && isfinite(value)
                    plot(ax, mine.(xName), value, 'p', 'MarkerSize', 14, 'MarkerFaceColor', colors(k, :), ...
                        'MarkerEdgeColor', app.Palette.text, 'DisplayName', sprintf('すべての Mark（%s）', axisNames(k)));
                end
            end
            % 点に Mark の数を書く（多いときは間引く。最初と最後は必ず）
            step = max(1, ceil(height(x) / app.MARK_MAX_LABELS));
            labelled = unique([1:step:height(x), height(x)]);
            top = max(x.(column), y.(column));
            for k = labelled
                if isfinite(top(k))
                    text(ax, x.(xName)(k), top(k), sprintf(' %d', x.count(k)), 'VerticalAlignment', 'bottom', ...
                        'HorizontalAlignment', 'left', 'FontSize', 9, 'Color', app.Palette.text, ...
                        'HandleVisibility', 'off');
                end
            end
            hold(ax, 'off');
            if any(xName == ["efficiency", "efficiencyD"])
                xlim(ax, [0, 105]);
            end
            xlabel(ax, xLabelText);
            ylabel(ax, "制御残差 " + statisticLabel + " [nm]");
            title(ax, sprintf('Mark の数ごとの I 最適な配置（%d〜%d 点）', study.counts(1), study.counts(end)), ...
                'Interpreter', 'none');
            grid(ax, 'on');
            box(ax, 'on');
            legend(ax, 'Location', 'northeast', 'Interpreter', 'none');
            styleAxes(app, ax, app.AXES_FONT_SIZE);
            data = table(x.count, x.efficiency, x.(xName), x.(column), y.(column), 'VariableNames', ...
                ["count", "efficiency", "xValue", "X", "Y"]);
            info = sprintf("%d 通りの Mark の数を %.0f 秒で計算しました。", numel(study.counts), study.seconds);
            if c.markOptChartYManual.Value
                % 縦軸の範囲を指定したとき（下限が上限以上なら自動のまま知らせる）
                limits = [c.markOptChartYMin.Value, c.markOptChartYMax.Value];
                if limits(1) < limits(2)
                    ylim(ax, limits);
                else
                    info = "⚠ 縦軸の下限は上限より小さくしてください（自動の範囲で描きました）。" + info;
                end
            end
            if ~isequaln(study.snapshot, markLayoutSnapshot(app))
                info = "⚠ 計算の後に入力・候補の Mark・設定を変えました。「配置を最適化する」で計算し直してください" + ...
                    "（下は前の結果）。" + info;
            end
            c.markOptChartInfo.Text = char(info);
        end

        function drawMarkLayoutMap(app, count)
            %DRAWMARKLAYOUTMAP 配置の図：候補の Mark（○）・選んだ配置で計測する Mark（●）・必ず計測する Mark（赤い ◇）・計測しない
            %   Mark（×）を Shot 内の座標で描き、右にその配置の制御残差の Shot スタックマップ（平均の矢印と共分散楕円）を描く。
            %   count：Mark の数（省略すると画面の選択。計算の前は候補の Mark だけ）。図の Mark をクリックすると、必ず計測 → 計測
            %   しない → 候補 が切り替わる。
            c = app.Controls;
            study = app.MarkLayoutStudy;
            if nargin >= 2 && ~isempty(study)
                if ~any(study.counts == count)
                    error('alignest:markLayout', 'Mark の数 %d の配置はありません（%d〜%d 点）。', count, ...
                        study.counts(1), study.counts(end));
                end
                c.markOptMapCount.Value = count;
            end
            ax = c.markOptMapAxes;
            stackAx = c.markOptStackAxes;
            cla(stackAx, 'reset');
            legend(stackAx, 'off');
            colorbar(stackAx, 'off');
            input = app.MarkLayoutInput;
            if isempty(input)
                cla(ax, 'reset');
                legend(ax, 'off');
                c.markOptMapInfo.Text = '';
                return
            end
            candidates = input.candidates;
            selected = false(height(candidates), 1);
            titleText = sprintf('候補の Mark %d 点（必ず計測 %d 点）', height(candidates), nnz(candidates.required));
            sameCandidates = ~isempty(study) && isequal([study.candidates.xMm, study.candidates.yMm], ...
                [candidates.xMm, candidates.yMm]);
            k = [];
            if sameCandidates
                k = find(study.counts == c.markOptMapCount.Value, 1);
                if isempty(k)
                    k = 1;
                end
                selected = study.layouts.selected(:, k);
                titleText = sprintf('Mark %d 点の配置（I 効率 %.1f%%）', study.counts(k), study.layouts.efficiency(k));
            end
            drawMarkPositions(app, ax, candidates, selected, titleText);
            info = "Mark をクリック：必ず計測 → 計測しない → 候補";
            if sameCandidates
                info = sprintf("計測する Mark：%s。", strjoin(string(candidates.no(selected)), "・")) + info;
                if ~isempty(study.maps) && k <= size(study.maps.meanX, 2)
                    maps = study.maps;
                    alignest.plot.positionMap(stackAx, [candidates.xMm, candidates.yMm], [maps.meanX(:, k), maps.meanY(:, k)], ...
                        [maps.varX(:, k), maps.varY(:, k), maps.covXY(:, k)], measured=selected, ...
                        shotSizeMm=markShotSize(candidates), ellipseSigma=c.markOptStackEllipse.Value, arrowColor=app.Palette.text, ...
                        titleText=sprintf("制御残差（Mark %d 点）", study.counts(k)));
                    styleAxes(app, stackAx, app.AXES_FONT_SIZE);
                end
            end
            c.markOptMapInfo.Text = char(info);
        end

        function drawMarkCandidates(app)
            %DRAWMARKCANDIDATES 「候補の Mark」の右の図：候補の Mark が Shot のどこにあるかと、必ず計測・計測しない Mark を描く。
            input = app.MarkLayoutInput;
            ax = app.Controls.markOptCandidateAxes;
            if isempty(input)
                cla(ax, 'reset');
                legend(ax, 'off');
                return
            end
            drawMarkPositions(app, ax, input.candidates, false(height(input.candidates), 1), '');
        end

        function shapes = drawMarkLayoutShape(app, index)
            %DRAWMARKLAYOUTSHAPE 乱数の Shot の形の図：生成した形のうち index 番目（省略すると画面の欄）の、ベクトル場（計測した値 =
            %   形 + 計測のばらつき + 飛び値。飛び値の点は赤）と、X 成分・Y 成分のヒートマップ（形）を並べる。shapes は生成した形
            %   （alignest.randomShotShapes）。生成していなければ [] で、図は空。
            HEAT_POINTS = 61;   % ヒートマップの縦・横の点の数
            c = app.Controls;
            if nargin >= 2
                c.markOptShapeIndex.Value = index;
            end
            axesList = c.markOptShapeAxes;
            for ax = axesList
                cla(ax, 'reset');
                legend(ax, 'off');
                colorbar(ax, 'off');
            end
            shapes = [];
            input = app.MarkLayoutInput;
            if isempty(input) || isempty(app.MarkLayoutShapes)
                c.markOptShapeInfo.Text = '「乱数で Shot を生成する」で形を作ります。';
                return
            end
            readMarkLayoutControls(app);
            shapes = app.MarkLayoutShapes.shapes;
            candidates = input.candidates;
            if numel(candidates.xMm) ~= size(shapes.trueX, 1)
                c.markOptShapeInfo.Text = '⚠ 候補の Mark を変えました。生成し直してください。';
                shapes = [];
                return
            end
            index = min(c.markOptShapeIndex.Value, shapes.count);
            dx = shapes.measuredX(:, index);
            dy = shapes.measuredY(:, index);
            outlier = shapes.outlier(:, index);
            magnitude = hypot(dx, dy);
            pitch = markPitch(candidates);
            scale = 0.8 * pitch / max(alignest.stats.percentile(magnitude, 95), eps);
            ax = axesList(1);
            hold(ax, 'on');
            quiver(ax, candidates.xMm(~outlier), candidates.yMm(~outlier), scale * dx(~outlier), scale * dy(~outlier), 0, ...
                'Color', app.PRIMARY_COLOR, 'LineWidth', 1.1, 'MaxHeadSize', 0.4, 'DisplayName', '計測した値');
            if any(outlier)
                quiver(ax, candidates.xMm(outlier), candidates.yMm(outlier), scale * dx(outlier), scale * dy(outlier), 0, ...
                    'Color', app.MARK_REQUIRED_COLOR, 'LineWidth', 1.4, 'MaxHeadSize', 0.4, 'DisplayName', '飛び値の点');
            end
            sizeMm = markShotSize(candidates);
            alignest.plot.referenceArrow(ax, [sizeMm(1) / 4, -sizeMm(2) / 2 - pitch / 2], scale, sizeMm(1) / 4, ...
                app.MARK_REQUIRED_COLOR);
            hold(ax, 'off');
            axis(ax, 'equal');
            xlim(ax, [-1, 1] * (sizeMm(1) / 2 + pitch));
            ylim(ax, [-1, 1] * (sizeMm(2) / 2 + pitch));
            xlabel(ax, 'Shot 内の X [mm]');
            ylabel(ax, 'Shot 内の Y [mm]');
            title(ax, sprintf('形 %d / %d：ベクトル場', index, shapes.count), 'Interpreter', 'none');
            grid(ax, 'on');
            box(ax, 'on');
            % X 成分・Y 成分のヒートマップ（色の範囲をそろえる）
            xGrid = linspace(-sizeMm(1) / 2, sizeMm(1) / 2, HEAT_POINTS);
            yGrid = linspace(-sizeMm(2) / 2, sizeMm(2) / 2, HEAT_POINTS);
            [gridX, gridY] = meshgrid(xGrid, yGrid);
            [fieldX, fieldY] = alignest.randomShapeField(shapes, index, gridX, gridY);
            limit = max([abs(fieldX(:)); abs(fieldY(:)); eps]);
            names = ["X 成分", "Y 成分"];
            fields = {fieldX, fieldY};
            for k = 1:2
                ax = axesList(k + 1);
                imagesc(ax, xGrid, yGrid, fields{k});
                ax.YDir = 'normal';
                hold(ax, 'on');
                plot(ax, candidates.xMm, candidates.yMm, '.', 'Color', [0.2, 0.2, 0.2], 'MarkerSize', 5, 'HandleVisibility', 'off');
                hold(ax, 'off');
                axis(ax, 'equal');
                axis(ax, 'tight');
                colormap(ax, alignest.plot.divergingColormap());
                clim(ax, [-limit, limit]);
                bar = colorbar(ax);
                bar.Title.String = 'nm';
                xlabel(ax, 'Shot 内の X [mm]');
                title(ax, names(k), 'Interpreter', 'none');
                box(ax, 'on');
            end
            styleAxes(app, axesList, app.AXES_FONT_SIZE);
            representative = ternary(index == shapes.representative, "（代表の形）", "");
            text = sprintf("形 %d%s：|値| の 95%% 点 %.2f nm・最大 %.2f nm（飛び値 %d 点）。", index, representative, ...
                alignest.stats.percentile(magnitude, 95), max(magnitude), nnz(outlier));
            if ~markLayoutShapesCurrent(app)
                text = "⚠ 生成の後に設定を変えました。生成し直してください。" + text;
            end
            c.markOptShapeInfo.Text = char(text);
        end

        function exportMarkSelectionTo(app, filePath, count)
            %EXPORTMARKSELECTIONTO 選んだ配置（Mark の数 count。省略すると画面の選択）を Excel（.xlsx）に書き出す
            %   （alignest.exportMarkSelection）。
            study = app.MarkLayoutStudy;
            if isempty(study)
                error('alignest:markLayout', '先に「配置を最適化する」を押してください。');
            end
            if nargin < 3
                count = app.Controls.markOptMapCount.Value;
            end
            alignest.exportMarkSelection(string(filePath), study, count);
        end

        function exportMarkLayoutTo(app, filePath)
            %EXPORTMARKLAYOUTTO 結果を Excel（.xlsx）に書き出す（alignest.exportMarkLayouts。説明・制御残差・配置・候補の Mark・
            %   項と VIF のシート）。
            study = app.MarkLayoutStudy;
            if isempty(study)
                error('alignest:markLayout', '先に「配置を最適化する」を押してください。');
            end
            notes = ["入力", study.sourceText];
            if ~isequaln(study.snapshot, markLayoutSnapshot(app))
                notes(end + 1, :) = ["注意", "計算の後に入力・候補の Mark・設定を変えています（書き出したのは計算したときの結果）"];
            end
            alignest.exportMarkLayouts(filePath, study, notes);
        end
    end

    methods (Access = {?appui.Core})
        function buildMarkLayoutTab(app)
            RANDOM_ORDERS = 8;       % 乱数の形の項の次数の数（0〜7次）
            grid = uigridlayout(app.Tabs.markLayout, [1, 1], 'Padding', 12);
            body = uigridlayout(grid, [1, 2], 'ColumnWidth', {600, '1x'}, 'Padding', 0, 'ColumnSpacing', 14);
            registerResponsiveColumn(app, body, 1);
            left = uigridlayout(body, [10, 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit', 'fit', 'fit', 'fit', ...
                'fit', 'fit'}, 'Padding', 0, 'RowSpacing', 6);
            place(uilabel(left, 'Text', '① 入力', 'FontWeight', 'bold'), 1, 1);
            inputGrid = uigridlayout(left, [1, 3], 'ColumnWidth', {'fit', '1x', 'fit'}, 'Padding', 0);
            place(inputGrid, 2, 1);
            label(inputGrid, '入力', 1, 1);
            c.markOptSource = uidropdown(inputGrid, 'Items', {'画面で入力する座標', '1. データ読込の計測データ', ...
                '7. Shot高次補正の入力のデータ', 'Excel・CSV から読み込んだデータ'}, 'ItemsData', {'manual', 'data', ...
                'highOrder', 'file'}, 'Value', 'manual', 'ValueChangedFcn', @(~, ~) app.onMarkLayoutSourceChanged(), ...
                'Tooltip', ['画面で入力する座標：右の「候補の Mark」で座標を入れる（格子で置ける）。実測値が無いので、乱数の ' ...
                'Shot の形で評価します。計測データ：「1. データ読込」の計測値。7. の入力：「7. Shot高次補正」で選んでいる' ...
                '入力のデータと Wafer。Excel・CSV：右のボタンで読み込んだ表（座標だけの表も読めます）。']);
            place(c.markOptSource, 1, 2);
            c.markOptLoad = uibutton(inputGrid, 'Text', 'Excel・CSV を読み込む…', ...
                'ButtonPushedFcn', @(~, ~) app.onLoadMarkLayoutFile(), 'Tooltip', ['1行目が見出しの表（列の名前は自由）。' ...
                '読んだ後で、右の「Excel・CSV の列」で Shot 内の座標 [mm]（必須）と、X・Y の値 [nm]・Wafer・shotNo など' ...
                '（任意）の列を選びます。X・Y の値が無い表は、候補の Mark の座標だけとして読みます。']);
            place(c.markOptLoad, 1, 3);
            c.markOptInputInfo = uilabel(left, 'WordWrap', 'on', 'FontColor', app.Palette.muted, 'UserData', "muted", ...
                'Text', '');
            place(c.markOptInputInfo, 3, 1);
            c.markOptWafer = uilistbox(left, 'Items', {'—'}, 'ItemsData', {1}, 'Multiselect', 'on', 'Value', {1}, ...
                'ValueChangedFcn', @(~, ~) app.onMarkLayoutWaferChanged(), 'Tooltip', ['候補の Mark と実測値に使う Wafer' ...
                '（計測データ・Excel・CSV のとき）。Ctrl・Shift を押しながらクリックで複数。']);
            place(c.markOptWafer, 4, 1);

            place(uilabel(left, 'Text', '② 補正の式', 'FontWeight', 'bold'), 5, 1);
            onSetting = @(~, ~) app.onMarkLayoutSettingsChanged();
            modelGrid = uigridlayout(left, [2, 4], 'ColumnWidth', {'fit', '1x', 'fit', 90}, 'RowHeight', {'fit', 'fit'}, ...
                'Padding', 0);
            place(modelGrid, 6, 1);
            label(modelGrid, '補正の式', 1, 1);
            c.markOptMaker = uidropdown(modelGrid, 'Items', {'ASML', 'Canon', 'Nikon', 'カスタム'}, ...
                'ItemsData', {'asml', 'canon', 'nikon', 'custom'}, 'ValueChangedFcn', onSetting, 'Tooltip', ['Overlay 計測' ...
                'ルールの Shot 高次補正の式（「7. Shot高次補正」と同じ）。カスタム：k1〜k38 から使う項を右の「使う項と VIF」で' ...
                '選びます。「7. Shot高次補正」で保存した項の組み合わせも選べます。式は「ヘルプ」。']);
            place(c.markOptMaker, 1, 2);
            label(modelGrid, 'VIF のしきい値', 1, 3);
            c.markOptVifThreshold = uieditfield(modelGrid, 'numeric', 'Limits', [1, Inf], 'LowerLimitInclusive', 'off', ...
                'ValueChangedFcn', onSetting, 'Tooltip', ['「VIF で選ぶ」で、候補の Mark の位置で求めた VIF がこの値以上の' ...
                '高次項を外します（よく使う値は 5〜10）。']);
            place(c.markOptVifThreshold, 1, 4);
            termButtons = uigridlayout(modelGrid, [1, 4], 'ColumnWidth', {'fit', 'fit', 'fit', '1x'}, 'Padding', 0);
            place(termButtons, 2, [1, 4]);
            c.markOptVifSelect = uibutton(termButtons, 'Text', 'VIF で選ぶ', 'ButtonPushedFcn', ...
                @(~, ~) app.onMarkLayoutVifSelect(), 'Tooltip', ['式のすべての項から始めて、VIF がしきい値以上の高次項を' ...
                '次数の高い項から1つずつ外します（k1〜k6 は外しません）。']);
            c.markOptAllTerms = uibutton(termButtons, 'Text', 'すべての項を使う', 'ButtonPushedFcn', ...
                @(~, ~) app.useAllMarkLayoutTerms());
            c.markOptCopyFormula = uibutton(termButtons, 'Text', '7. の式を写す', 'ButtonPushedFcn', ...
                @(~, ~) app.onCopyHighOrderFormula(), 'Tooltip', ['「7. Shot高次補正」の補正の式（内周の式）・使う項・' ...
                'VIF のしきい値・回帰の設定を、このタブに写します。']);
            c.markOptTermInfo = uilabel(left, 'WordWrap', 'on', 'FontColor', app.Palette.muted, 'UserData', "muted", ...
                'Text', '');
            place(c.markOptTermInfo, 7, 1);

            c.markOptRegression = regressionControls(left, onSetting);
            place(c.markOptRegression.grid, 8, 1);

            design = uigridlayout(left, [3, 6], 'ColumnWidth', {'fit', 70, 'fit', 70, 'fit', 70}, 'RowHeight', ...
                {'fit', 'fit', 'fit'}, 'Padding', 0);
            place(design, 9, 1);
            designHeading = label(design, '④ 配置の選び方と評価', 1, [1, 6]);
            designHeading.FontWeight = 'bold';
            label(design, '最低数', 2, 1);
            c.markOptMinMarks = uieditfield(design, 'numeric', 'Limits', [0, Inf], 'RoundFractionalValues', 'on', ...
                'ValueChangedFcn', onSetting, 'Tooltip', ['計測する Mark の数の最低数（0 = 使う項の数）。最低数から1点ずつ' ...
                '増やした数ごとに、I 最適な配置を解き直します。使う項の数・必ず計測する Mark の数より少なくはしません。']);
            place(c.markOptMinMarks, 2, 2);
            label(design, '最大数', 2, 3);
            c.markOptMaxMarks = uieditfield(design, 'numeric', 'Limits', [0, Inf], 'RoundFractionalValues', 'on', ...
                'ValueChangedFcn', onSetting, 'Tooltip', '計測する Mark の数の最大数（0 = すべての候補の Mark）。');
            place(c.markOptMaxMarks, 2, 4);
            label(design, '探す回数', 2, 5);
            c.markOptStarts = uieditfield(design, 'numeric', 'Limits', [1, 50], 'RoundFractionalValues', 'on', ...
                'ValueChangedFcn', onSetting, 'Tooltip', ['Mark の数ごとに、配置を探す始め方の数（1つ前の数の配置・Mark を' ...
                '1つずつ足した配置・乱数で選んだ配置から交換法で解き、最もよい配置を使う）。多いほどよい配置が見つかり' ...
                'やすくなりますが、時間がかかります。']);
            place(c.markOptStarts, 2, 6);
            label(design, '評価に使う値', 3, 1);
            c.markOptValues = uidropdown(design, 'Items', {'実測値', '乱数 Shot'}, ...
                'ItemsData', {'measured', 'random'}, 'ValueChangedFcn', @(~, ~) app.onMarkLayoutValuesChanged(), ...
                'Tooltip', ['実測値：Shot ごとに、選んだ' ...
                'Mark の実測値で補正し、値のあるすべての Mark の制御残差（実測値 − 補正量）を求めます。乱数 Shot：' ...
                '形に計測のばらつきと飛び値を足した値で補正し、足す前の形との差を制御残差にします（座標だけの入力はこちら）。']);
            place(c.markOptValues, 3, [2, 6]);
            actions = uigridlayout(left, [2, 2], 'ColumnWidth', {180, 'fit'}, 'RowHeight', {'fit', 'fit'}, 'Padding', 0);
            place(actions, 10, 1);
            c.markOptRun = primaryButton(app, actions, '配置を最適化する', @(~, ~) app.onOptimizeMarkLayout());
            c.markOptExport = uibutton(actions, 'Text', '結果を Excel に書き出す…', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onExportMarkLayout());
            c.markOptError = errorLabel(app, actions, 2, [1, 2]);

            % 右：メッセージと、Excel・CSV の列・候補の Mark・使う項と VIF・乱数の Shot の形・結果（中のタブで切り替える）
            right = uigridlayout(body, [2, 1], 'RowHeight', {app.TARGET_MESSAGE_HEIGHT, '1x'}, 'Padding', 0, 'RowSpacing', 6);
            c.markOptMessage = uitextarea(right, 'Editable', 'off', 'Value', {''});
            place(c.markOptMessage, 1, 1);
            outputs = uitabgroup(right);
            place(outputs, 2, 1);
            c.markOptOutputs = outputs;
            % Excel・CSV の列
            columnTab = uitab(outputs, 'Title', 'Excel・CSV の列');
            c.markOptColumnTab = columnTab;
            columnGrid = uigridlayout(columnTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            columnControls = uigridlayout(columnGrid, [1, 3], 'ColumnWidth', {'fit', '1x', 'fit'}, 'Padding', 0);
            label(columnControls, 'シート', 1, 1);
            c.markOptSheet = uidropdown(columnControls, 'Items', {'—'}, 'Enable', 'off', ...
                'ValueChangedFcn', @(~, ~) app.onMarkLayoutSheetChanged());
            place(c.markOptSheet, 1, 2);
            c.markOptApplyMapping = uibutton(columnControls, 'Text', 'この列で使う', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onApplyMarkLayoutMapping());
            place(c.markOptApplyMapping, 1, 3);
            c.markOptMappingTable = uitable(columnGrid, 'ColumnName', {'項目', '意味', '必須', 'ファイルの列'}, ...
                'RowName', {}, 'ColumnEditable', [false, false, false, true], 'ColumnWidth', {90, 'auto', 50, 180}, ...
                'Data', cell(0, 4), 'Tooltip', '「ファイルの列」をクリックして、項目に使う列を選びます（使わない項目は「（なし）」）。');
            place(c.markOptMappingTable, 2, 1);
            c.markOptMappingStatus = uilabel(columnGrid, 'WordWrap', 'on', 'Text', '「Excel・CSV を読み込む…」で表を選んでください。');
            place(c.markOptMappingStatus, 3, 1);
            % 候補の Mark
            candidateTab = uitab(outputs, 'Title', '候補の Mark');
            c.markOptCandidateTab = candidateTab;
            candidateGrid = uigridlayout(candidateTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, ...
                'RowSpacing', 4);
            % 表は以前の2倍の幅（列の幅も2倍）。図は残りの幅
            candidateBody = uigridlayout(candidateGrid, [1, 2], 'ColumnWidth', {'2.6x', '1x'}, 'Padding', 0, 'ColumnSpacing', 6);
            place(candidateBody, 2, 1);
            gridControls = uigridlayout(candidateGrid, [2, 9], 'ColumnWidth', {'fit', 64, 'fit', 64, 'fit', 50, 'fit', ...
                50, '1x'}, 'RowHeight', {'fit', 'fit'}, 'Padding', 0);
            place(gridControls, 1, 1);
            label(gridControls, '幅 [mm]', 1, 1);
            c.markOptGridWidth = uieditfield(gridControls, 'numeric', 'Value', app.MARK_GRID_SPAN_MM(1), ...
                'Limits', [0, Inf], 'Tooltip', '格子の端の Mark どうしの X の間 [mm]（Shot 中心を真ん中にする）。');
            place(c.markOptGridWidth, 1, 2);
            label(gridControls, '高さ [mm]', 1, 3);
            c.markOptGridHeight = uieditfield(gridControls, 'numeric', 'Value', app.MARK_GRID_SPAN_MM(2), ...
                'Limits', [0, Inf], 'Tooltip', '格子の端の Mark どうしの Y の間 [mm]。');
            place(c.markOptGridHeight, 1, 4);
            label(gridControls, '列', 1, 5);
            c.markOptGridColumns = uieditfield(gridControls, 'numeric', 'Value', app.MARK_GRID_COUNTS(1), ...
                'Limits', [1, 101], 'RoundFractionalValues', 'on');
            place(c.markOptGridColumns, 1, 6);
            label(gridControls, '行', 1, 7);
            c.markOptGridRows = uieditfield(gridControls, 'numeric', 'Value', app.MARK_GRID_COUNTS(2), ...
                'Limits', [1, 101], 'RoundFractionalValues', 'on');
            place(c.markOptGridRows, 1, 8);
            c.markOptMakeGrid = uibutton(gridControls, 'Text', '格子で置く', 'ButtonPushedFcn', ...
                @(~, ~) app.onMakeMarkLayoutGrid(), 'Tooltip', ['入力を「画面で入力する座標」にして、候補の Mark を格子に' ...
                '置きます（今の座標と置き換えます）。']);
            place(c.markOptMakeGrid, 1, 9);
            rowButtons = uigridlayout(gridControls, [1, 4], 'ColumnWidth', {'fit', 'fit', 'fit', '1x'}, 'Padding', 0);
            place(rowButtons, 2, [1, 9]);
            c.markOptAddRow = uibutton(rowButtons, 'Text', '行を足す', 'ButtonPushedFcn', @(~, ~) app.onAddMarkLayoutRow(), ...
                'Tooltip', '画面で入力する座標に行を足します（X・Y を入れると候補の Mark になります）。');
            c.markOptDeleteRows = uibutton(rowButtons, 'Text', '選んだ行を消す', 'ButtonPushedFcn', ...
                @(~, ~) app.onDeleteMarkLayoutRows());
            c.markOptClearRequired = uibutton(rowButtons, 'Text', '指定をすべて外す', 'ButtonPushedFcn', ...
                @(~, ~) app.onClearMarkLayoutRequired(), 'Tooltip', '必ず計測・計測しないの指定をすべて外します。');
            c.markOptCandidateTable = uitable(candidateBody, 'ColumnName', {'No', 'X [mm]', 'Y [mm]', '計測済み|Shot 数', ...
                '必ず|計測', '計測|しない'}, 'ColumnFormat', {'numeric', 'numeric', 'numeric', 'char', 'logical', 'logical'}, ...
                'RowName', {}, 'ColumnWidth', {68, 116, 116, 132, 100, 100}, 'Data', cell(0, 6), ...
                'CellEditCallback', @(~, event) app.onMarkLayoutCandidateEdited(event), ...
                'CellSelectionCallback', @(~, event) app.onMarkLayoutCandidateSelected(event), 'Tooltip', ...
                ['計測済み Shot 数：この位置を実測した Shot の数（座標だけの入力は —）。必ず計測：どの配置にも入れます。計測しない：' ...
                '配置に選びませんが、残差の評価には使います。']);
            place(c.markOptCandidateTable, 1, 1);
            candidatePanel = uipanel(candidateBody, 'BorderType', 'none');
            place(candidatePanel, 1, 2);
            c.markOptCandidateAxes = uiaxes(uigridlayout(candidatePanel, [1, 1], 'Padding', 0));
            c.markOptCandidateInfo = label(candidateGrid, '', 3, 1);
            c.markOptCandidateInfo.FontColor = app.Palette.muted;
            c.markOptCandidateInfo.UserData = "muted";
            % 使う項と VIF
            termTab = uitab(outputs, 'Title', '使う項と VIF');
            c.markOptTermTab = termTab;
            termGrid = uigridlayout(termTab, [2, 1], 'RowHeight', {'1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            c.markOptTermTable = uitable(termGrid, 'ColumnName', {'使う', '式', 'k', '項', '次数', 'VIF（全項）', ...
                'VIF（使う項）'}, 'ColumnFormat', {'logical', 'char', 'char', 'char', 'numeric', 'char', 'char'}, ...
                'ColumnEditable', [true, false(1, 6)], 'RowName', {}, 'ColumnWidth', {50, 50, 56, 90, 56, 130, 130}, ...
                'Data', cell(0, 7), 'CellEditCallback', @(~, event) app.onMarkLayoutTermEdited(event), 'Tooltip', ...
                ['VIF は候補の Mark の位置（それぞれ1点）で求めます。VIF（全項）：式のすべての項、VIF（使う項）：「使う」の項' ...
                'だけ。∞ は候補の Mark の位置では決まらない項。']);
            c.markOptVifInfo = label(termGrid, '', 2, 1);
            c.markOptVifInfo.FontColor = app.Palette.muted;
            c.markOptVifInfo.UserData = "muted";
            % 乱数 Shot 生成：項の大きさ・形の数・ばらつき・飛び値を決めて生成し、代表の形を確かめてから評価に使う
            shapeTab = uitab(outputs, 'Title', '乱数 Shot 生成');
            c.markOptShapeTab = shapeTab;
            shapeGrid = uigridlayout(shapeTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            % 項の大きさ（0〜7次を4つずつ2行）、形の数・ばらつき・飛び値、生成するボタンと見る形・保存（行ごとに別の格子にして、
            % 文字の長さで列の幅が変わらないようにする）
            shapeControls = uigridlayout(shapeGrid, [3, 1], 'RowHeight', {'fit', 'fit', 'fit'}, 'Padding', 0, 'RowSpacing', 3);
            onShape = @(~, ~) app.onMarkLayoutShapeChanged();
            sizeGrid = uigridlayout(shapeControls, [2, 9], 'ColumnWidth', {'fit', 'fit', '1x', 'fit', '1x', 'fit', '1x', 'fit', '1x'}, ...
                'RowHeight', {'fit', 'fit'}, 'Padding', 0, 'RowSpacing', 3);
            place(sizeGrid, 1, 1);
            label(sizeGrid, '項の大きさ [nm]', 1, 1);
            c.markOptOrderSigma = gobjects(1, RANDOM_ORDERS);
            for order = 0:RANDOM_ORDERS - 1
                row = 1 + floor(order / 4);
                column = 2 + 2 * mod(order, 4);
                label(sizeGrid, sprintf('%d次', order), row, column);
                c.markOptOrderSigma(order + 1) = uieditfield(sizeGrid, 'numeric', 'Limits', [0, Inf], ...
                    'ValueChangedFcn', onShape, 'Tooltip', sprintf(['%d次の項の重みの大きさ（Shot の端での標準偏差 [nm]）。0 の' ...
                    '次数は使いません。形ごとに、使う次数の項を乱数で選び、乱数の重みを付けます。'], order));
                place(c.markOptOrderSigma(order + 1), row, column + 1);
            end
            noiseGrid = uigridlayout(shapeControls, [1, 8], 'ColumnWidth', {'fit', '1x', 'fit', '1x', 'fit', '1x', 'fit', '1x'}, 'Padding', 0);
            place(noiseGrid, 2, 1);
            label(noiseGrid, '形の数', 1, 1);
            c.markOptShapes = uieditfield(noiseGrid, 'numeric', 'Limits', [1, 1000], 'RoundFractionalValues', 'on', ...
                'ValueChangedFcn', onShape, 'Tooltip', ['評価に使う乱数の Shot の形の数（1〜1000）。多いほど結果のばらつきが' ...
                '小さくなりますが、時間がかかります（ロバスト回帰・L1 では特に）。']);
            place(c.markOptShapes, 1, 2);
            label(noiseGrid, 'ばらつき [nm]', 1, 3);
            c.markOptNoise = uieditfield(noiseGrid, 'numeric', 'Limits', [0, Inf], 'ValueChangedFcn', onShape, ...
                'Tooltip', '計測のばらつき：各点に足す正規乱数の標準偏差 [nm]。');
            place(c.markOptNoise, 1, 4);
            label(noiseGrid, '飛び値 [%]', 1, 5);
            c.markOptOutlierPercent = uieditfield(noiseGrid, 'numeric', 'Limits', [0, 50], 'ValueChangedFcn', onShape, ...
                'Tooltip', ['点ごとの飛び値にする点の割合 [%]（Shot ごとに、候補の数 × 割合 の点を乱数で選びます）。' ...
                'ロバスト回帰の効き目を見るときに使います。']);
            place(c.markOptOutlierPercent, 1, 6);
            label(noiseGrid, '大きさ [nm]', 1, 7);
            c.markOptOutlierSize = uieditfield(noiseGrid, 'numeric', 'Limits', [0, Inf], 'ValueChangedFcn', onShape, ...
                'Tooltip', '飛び値の大きさ [nm]（向きは乱数。X・Y の両方に足します）。');
            place(c.markOptOutlierSize, 1, 8);
            actionGrid = uigridlayout(shapeControls, [1, 4], 'ColumnWidth', {'fit', 'fit', 70, 'fit'}, 'Padding', 0);
            place(actionGrid, 3, 1);
            c.markOptGenerate = primaryButton(app, actionGrid, '乱数で Shot を生成する', @(~, ~) app.onGenerateMarkLayoutShapes());
            place(c.markOptGenerate, 1, 1);
            label(actionGrid, '見る形', 1, 2);
            c.markOptShapeIndex = uieditfield(actionGrid, 'numeric', 'Value', 1, 'Limits', [1, 1000], ...
                'RoundFractionalValues', 'on', 'ValueChangedFcn', @(~, ~) app.drawMarkLayoutShape(), ...
                'Tooltip', '図に描く形の番号。生成すると、代表の形（|形| の 95% 点が中央値に近い形）を選びます。');
            place(c.markOptShapeIndex, 1, 3);
            c.markOptSaveShape = uibutton(actionGrid, 'Text', '図を画像で保存…', 'ButtonPushedFcn', ...
                @(~, ~) app.saveFigureWithDialog("markLayoutShape", 'random_shot_shape.png'));
            place(c.markOptSaveShape, 1, 4);
            shapePanel = uipanel(shapeGrid, 'BorderType', 'none');
            place(shapePanel, 2, 1);
            shapeAxes = uigridlayout(shapePanel, [1, 3], 'Padding', 0, 'ColumnSpacing', 4);
            c.markOptShapeAxes = [uiaxes(shapeAxes), uiaxes(shapeAxes), uiaxes(shapeAxes)];
            c.markOptShapeInfo = label(shapeGrid, '', 3, 1);
            % 制御残差推移（Mark の数ごとの配置の制御残差を、I 効率などの横軸で並べる）
            chartTab = uitab(outputs, 'Title', '制御残差推移');
            c.markOptChartTab = chartTab;
            chartGrid = uigridlayout(chartTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            chartControls = uigridlayout(chartGrid, [3, 4], 'ColumnWidth', {'fit', '1x', 'fit', '1x'}, ...
                'RowHeight', {'fit', 'fit', 'fit'}, 'Padding', 0, 'RowSpacing', 3);
            onChart = @(~, ~) app.drawMarkLayoutChart();
            label(chartControls, '図の値', 1, 1);
            c.markOptChartStatistic = uidropdown(chartControls, 'Items', {'|平均|+3σ', '|制御残差| 95% 点', ...
                '|制御残差| 中央値', 'RMS'}, 'ItemsData', {'meanPlus3Sigma', 'p95', 'median', 'rms'}, ...
                'ValueChangedFcn', onChart);
            place(c.markOptChartStatistic, 1, 2);
            label(chartControls, '制御残差の点', 1, 3);
            c.markOptChartPoints = uidropdown(chartControls, 'Items', {'すべての Mark', '計測しなかった Mark だけ'}, ...
                'ItemsData', {'all', 'unmeasured'}, 'ValueChangedFcn', onChart, 'Tooltip', ['すべての Mark：計測した Mark も' ...
                '含めた、すべての候補の Mark の制御残差。計測しなかった Mark だけ：補正の式で予測した Mark の制御残差。']);
            place(c.markOptChartPoints, 1, 4);
            label(chartControls, '横軸', 2, 1);
            c.markOptChartAxis = uidropdown(chartControls, 'Items', {'I 効率', 'I 基準', 'Mark の数', 'D 効率', 'D 基準'}, ...
                'ItemsData', {'efficiency', 'criterionI', 'count', 'efficiencyD', 'criterionD'}, 'ValueChangedFcn', onChart);
            place(c.markOptChartAxis, 2, 2);
            chartButtons = uigridlayout(chartControls, [1, 2], 'ColumnWidth', {'fit', 'fit'}, 'Padding', 0);
            place(chartButtons, 2, [3, 4]);
            c.markOptSaveChart = uibutton(chartButtons, 'Text', '図を画像で保存…', 'ButtonPushedFcn', ...
                @(~, ~) app.saveFigureWithDialog("markLayoutChart", 'mark_layout_efficiency.png'));
            c.markOptCopyChart = uibutton(chartButtons, 'Text', '図をコピー', 'Tooltip', app.COPY_TOOLTIP, ...
                'ButtonPushedFcn', @(source, ~) app.onCopyFigure("markLayoutChart", source));
            % 縦軸の範囲：オフなら自動、オンなら下限〜上限 [nm]
            label(chartControls, '縦軸', 3, 1);
            yLimitGrid = uigridlayout(chartControls, [1, 5], 'ColumnWidth', {'fit', 'fit', 90, 'fit', 90}, 'Padding', 0);
            place(yLimitGrid, 3, [2, 4]);
            c.markOptChartYManual = uicheckbox(yLimitGrid, 'Text', '範囲を指定する', 'Value', false, ...
                'ValueChangedFcn', onChart, 'Tooltip', 'オフなら縦軸の範囲は自動。オンなら下限〜上限 [nm] で描きます。');
            label(yLimitGrid, '下限', 1, 2);
            c.markOptChartYMin = uieditfield(yLimitGrid, 'numeric', 'Value', 0, 'ValueChangedFcn', onChart);
            place(c.markOptChartYMin, 1, 3);
            label(yLimitGrid, '上限', 1, 4);
            c.markOptChartYMax = uieditfield(yLimitGrid, 'numeric', 'Value', 10, 'ValueChangedFcn', onChart);
            place(c.markOptChartYMax, 1, 5);
            c.markOptChartAxes = axesInPanel(chartGrid, 2);
            chartEmpty = '「配置を最適化する」で描きます。';
            c.markOptChartInfo = uilabel(chartGrid, 'WordWrap', 'on', 'Text', chartEmpty, 'UserData', chartEmpty);
            place(c.markOptChartInfo, 3, 1);
            % 配置
            mapTab = uitab(outputs, 'Title', '配置');
            c.markOptMapTab = mapTab;
            mapGrid = uigridlayout(mapTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 6, 'RowSpacing', 4);
            mapControls = uigridlayout(mapGrid, [2, 4], 'ColumnWidth', {'fit', '1x', 'fit', 76}, 'RowHeight', {'fit', 'fit'}, ...
                'Padding', 0, 'RowSpacing', 3);
            label(mapControls, 'Mark の数', 1, 1);
            c.markOptMapCount = uidropdown(mapControls, 'Items', {'—'}, 'ItemsData', {0}, 'Enable', 'off', ...
                'ValueChangedFcn', @(~, ~) app.drawMarkLayoutMap());
            place(c.markOptMapCount, 1, 2);
            label(mapControls, '楕円', 1, 3);
            c.markOptStackEllipse = ellipseDropdown(mapControls, @(~, ~) app.drawMarkLayoutMap());
            c.markOptStackEllipse.Tooltip = ['右の図の、Mark の位置ごとの Shot（形）間の制御残差のばらつきの共分散楕円を、平均の矢印の先に' ...
                '矢印と同じ倍率で描きます。色は X・Y の相関係数の絶対値 |r|。'];
            place(c.markOptStackEllipse, 1, 4);
            mapButtons = uigridlayout(mapControls, [1, 3], 'ColumnWidth', {'fit', 'fit', 'fit'}, 'Padding', 0);
            place(mapButtons, 2, [1, 4]);
            c.markOptExportSelection = uibutton(mapButtons, 'Text', 'この配置を Excel に書き出す…', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onExportMarkSelection());
            c.markOptSaveMap = uibutton(mapButtons, 'Text', '図を画像で保存…', 'ButtonPushedFcn', ...
                @(~, ~) app.saveFigureWithDialog("markLayoutMap", 'mark_layout_map.png'));
            c.markOptCopyMap = uibutton(mapButtons, 'Text', '図をコピー', 'Tooltip', app.COPY_TOOLTIP, ...
                'ButtonPushedFcn', @(source, ~) app.onCopyFigure("markLayoutMap", source));
            mapPanel = uipanel(mapGrid, 'BorderType', 'none');
            place(mapPanel, 2, 1);
            mapAxes = uigridlayout(mapPanel, [1, 2], 'Padding', 0, 'ColumnSpacing', 6);
            c.markOptMapAxes = uiaxes(mapAxes);
            c.markOptStackAxes = uiaxes(mapAxes);
            c.markOptMapInfo = uilabel(mapGrid, 'WordWrap', 'on', 'Text', '');
            place(c.markOptMapInfo, 3, 1);
            % 表
            tableTab = uitab(outputs, 'Title', '表');
            c.markOptTableTab = tableTab;
            tableGrid = uigridlayout(tableTab, [1, 1], 'Padding', 6);
            c.markOptResultTable = uitable(tableGrid, 'RowName', {}, 'Data', table());
            place(c.markOptResultTable, 1, 1);
            % 配置を選んだ I 最適計画の式（採用した演算式と、F の列に使った項）
            criterionTab = uitab(outputs, 'Title', 'I 最適の式');
            c.markOptCriterionTab = criterionTab;
            criterionGrid = uigridlayout(criterionTab, [1, 1], 'Padding', 6);
            c.markOptCriterion = uitextarea(criterionGrid, 'Editable', 'off', 'Value', {app.MARK_CRITERION_EMPTY});
            place(c.markOptCriterion, 1, 1);
            outputs.SelectedTab = candidateTab;
            app.Controls = mergeStruct(app.Controls, c);
            refreshMarkLayoutChoices(app);
            markLayoutSettingsToControls(app);   % 候補の Mark も作る（refreshMarkLayoutInput）
        end

        function markLayoutSettingsToControls(app)
            % 設定（settings.markLayout）を画面の欄に写す（設定ファイルを読んだ・初期設定に戻したときも呼ぶ）
            c = app.Controls;
            if ~isfield(c, 'markOptMaker')
                return
            end
            try
                options = alignest.markLayoutOptions(app.Settings);
            catch
                app.Settings.markLayout = alignest.defaultSettings().markLayout;   % 読めない値は初期値にする
                options = alignest.markLayoutOptions(app.Settings);
            end
            refreshMarkLayoutFormulaChoices(app);
            c.markOptMaker.Value = char(options.maker);
            c.markOptVifThreshold.Value = options.vifThreshold;
            regressionToControls(c.markOptRegression, options);
            c.markOptMinMarks.Value = options.minMarks;
            c.markOptMaxMarks.Value = options.maxMarks;
            c.markOptStarts.Value = options.starts;
            c.markOptValues.Value = char(options.values);
            c.markOptShapes.Value = options.shapes;
            for order = 1:numel(c.markOptOrderSigma)
                c.markOptOrderSigma(order).Value = options.orderSigmaNm(order);
            end
            c.markOptNoise.Value = options.noiseNm;
            c.markOptOutlierPercent.Value = options.outlierPercent;
            c.markOptOutlierSize.Value = options.outlierNm;
            app.MarkLayoutValuesAuto = false;
            updateMarkLayoutEnabled(app);
            refreshMarkLayoutInput(app);
        end

        function readMarkLayoutControls(app)
            % 画面の欄を設定（settings.markLayout）に移す（使う項・座標・必ず計測する Mark は表の操作で変える）
            c = app.Controls;
            maker = string(c.markOptMaker.Value);
            if startsWith(maker, app.MARK_SET_PREFIX)
                % 保存した項の組み合わせ：式と使う項にして、選択肢は式の名前に戻す
                sets = termSetTable(fieldOr(app.Settings.highOrder, "termSets", strings(0, 1)));
                row = find(sets.name == extractAfter(maker, strlength(app.MARK_SET_PREFIX)), 1);
                if ~isempty(row)
                    app.Settings.markLayout.maker = sets.maker(row);
                    app.Settings.markLayout.excludedTerms = excludedFor(sets.maker(row), sets.terms{row});
                    c.markOptMaker.Value = char(sets.maker(row));
                end
            elseif maker ~= string(app.Settings.markLayout.maker)
                app.Settings.markLayout.maker = maker;
                app.Settings.markLayout.excludedTerms = zeros(1, 0);   % 式を変えたら、外した項は戻す
            end
            app.Settings.markLayout.vifThreshold = c.markOptVifThreshold.Value;
            app.Settings.markLayout = mergeStruct(app.Settings.markLayout, regressionFromControls(c.markOptRegression));
            app.Settings.markLayout.minMarks = c.markOptMinMarks.Value;
            app.Settings.markLayout.maxMarks = c.markOptMaxMarks.Value;
            app.Settings.markLayout.starts = c.markOptStarts.Value;
            app.Settings.markLayout.values = string(c.markOptValues.Value);
            app.Settings.markLayout.shapes = c.markOptShapes.Value;
            app.Settings.markLayout.orderSigmaNm = [c.markOptOrderSigma.Value];
            app.Settings.markLayout.noiseNm = c.markOptNoise.Value;
            app.Settings.markLayout.outlierPercent = c.markOptOutlierPercent.Value;
            app.Settings.markLayout.outlierNm = c.markOptOutlierSize.Value;
        end

        function updateMarkLayoutEnabled(app)
            c = app.Controls;
            updateRegressionEnabled(c.markOptRegression);
            source = string(c.markOptSource.Value);
            c.markOptWafer.Enable = onOff(any(source == ["data", "file"]) && ~isempty(c.markOptWafer.ItemsData) && ...
                ~isequal(c.markOptWafer.ItemsData, {0}));
            manual = source == "manual";
            set([c.markOptAddRow, c.markOptDeleteRows], 'Enable', onOff(manual));
            editable = [false, manual, manual, false, true, true];
            c.markOptCandidateTable.ColumnEditable = editable;
        end

        function refreshMarkLayoutFormulaChoices(app)
            % 補正の式の選択肢：ASML・Canon・Nikon・カスタムと、「7. Shot高次補正」で保存した項の組み合わせ
            c = app.Controls;
            sets = termSetTable(fieldOr(app.Settings.highOrder, "termSets", strings(0, 1)));
            items = ["ASML", "Canon", "Nikon", "カスタム", ...
                reshape("組み合わせ：" + sets.name + "（" + sets.makerLabel + "・" + sets.count + " 項）", 1, [])];
            values = ["asml", "canon", "nikon", "custom", reshape(app.MARK_SET_PREFIX + sets.name, 1, [])];
            setChoices(c.markOptMaker, items, cellstr(values));
        end

        function refreshMarkLayoutChoices(app)
            % 入力の Wafer の一覧（計測データ・Excel・CSV）と補正の式の選択肢を、今のデータ・保存した組み合わせに合わせる
            c = app.Controls;
            if ~isfield(c, 'markOptWafer')
                return
            end
            source = string(c.markOptSource.Value);
            labels = strings(1, 0);
            switch source
                case "data"
                    if ~isempty(app.Data)
                        labels = string({app.Data.units.label});
                    end
                case "file"
                    if ~isempty(app.MarkLayoutFile) && ~isempty(app.MarkLayoutFile.wafers)
                        labels = string({app.MarkLayoutFile.wafers.label});
                    end
            end
            if isempty(labels)
                setListChoices(c.markOptWafer, "—", {0});
            else
                setListChoices(c.markOptWafer, labels, num2cell(1:numel(labels)));
            end
            refreshMarkLayoutFormulaChoices(app);
            updateMarkLayoutEnabled(app);
        end

        function refreshMarkLayoutInput(app)
            % 選んだ入力から候補の Mark と Shot ごとの値を作り直し、候補の表・項の表（VIF）・配置の図・知らせを更新する
            c = app.Controls;
            if ~isfield(c, 'markOptCandidateTable')
                return
            end
            app.MarkLayoutInput = [];
            try
                app.MarkLayoutInput = buildMarkLayoutInput(app);
                input = app.MarkLayoutInput;
                text = input.text + sprintf("：候補の Mark %d 点", height(input.candidates));
                if isempty(input.shots.label)
                    text = text + "（実測値なし）";
                else
                    text = text + sprintf("・実測値 %d Shot", numel(input.shots.label));
                end
                c.markOptInputInfo.Text = char(text + "。");
                c.markOptInputInfo.FontColor = app.Palette.muted;
                matchMarkLayoutValues(app, ~isempty(input.shots.label));
            catch err
                c.markOptInputInfo.Text = char("⚠ " + err.message);
                c.markOptInputInfo.FontColor = app.Palette.error;
            end
            showMarkLayoutCandidates(app);
            refreshMarkLayoutTerms(app);
            drawMarkLayoutMap(app);
            drawMarkLayoutShape(app);
            if ~isempty(app.MarkLayoutStudy)
                drawMarkLayoutChart(app);   % 計算の後に変えたときの知らせ
            end
            showMarkLayoutMessages(app);
        end

        function matchMarkLayoutValues(app, hasValues)
            % 座標だけの入力は乱数の形で評価する。値のある入力に戻したら、自動で変えたときだけ実測値に戻す
            c = app.Controls;
            target = "";
            if ~hasValues && string(c.markOptValues.Value) == "measured"
                target = "random";
            elseif hasValues && app.MarkLayoutValuesAuto
                target = "measured";
            end
            if target ~= ""
                c.markOptValues.Value = char(target);
                app.Settings.markLayout.values = target;
                app.MarkLayoutValuesAuto = target == "random";
            end
        end

        function input = buildMarkLayoutInput(app)
            % 入力の候補の Mark（alignest.markCandidates）と、入力の説明
            c = app.Controls;
            settings = app.Settings.markLayout;
            required = [reshape(settings.requiredXmm, [], 1), reshape(settings.requiredYmm, [], 1)];
            excluded = [reshape(settings.excludedXmm, [], 1), reshape(settings.excludedYmm, [], 1)];
            source = string(c.markOptSource.Value);
            switch source
                case "manual"
                    coordinates = [reshape(settings.coordinateXmm, [], 1), reshape(settings.coordinateYmm, [], 1)];
                    if isempty(coordinates)
                        error('alignest:markLayout', '候補の Mark がありません。「候補の Mark」で座標を入れてください。');
                    end
                    [candidates, shots] = alignest.markCandidates([], coordinates, required, excluded);
                    text = "画面で入力した座標";
                case "data"
                    if isempty(app.Data)
                        error('alignest:noData', '先に「1. データ読込」で計測データを読み込んでください。');
                    end
                    if alignest.valueSpec(app.Settings.data).scalar
                        error('alignest:markLayout', ['Shot 高次補正は X・Y の2成分が要ります（1変数の推定のデータでは' ...
                            '使えません）。']);
                    end
                    selection = selectedWafers(c.markOptWafer);
                    wafers = struct("label", {}, "points", {});
                    for k = selection
                        unit = app.Data.units(k);
                        wafers(end + 1) = struct("label", unit.label, "points", alignest.highOrderUnitPoints(unit)); %#ok<AGROW>
                    end
                    [candidates, shots] = alignest.markCandidates(wafers, zeros(0, 2), required, excluded);
                    text = sprintf("「1. データ読込」の計測データ（%d Wafer）", numel(wafers));
                case "highOrder"
                    wafers = highOrderWafers(app);
                    [candidates, shots] = alignest.markCandidates(wafers, zeros(0, 2), required, excluded);
                    text = sprintf("「7. Shot高次補正」の入力のデータ（%d Wafer）", numel(wafers));
                otherwise
                    file = app.MarkLayoutFile;
                    if isempty(file)
                        error('alignest:markLayoutFile', '先に「Excel・CSV を読み込む…」で表を読み込んでください。');
                    end
                    if isempty(file.dataInfo)
                        error('alignest:markLayoutFile', ['右の「Excel・CSV の列」で列を選び、「この列で使う」を押して' ...
                            'ください。']);
                    end
                    if isempty(file.wafers)
                        [candidates, shots] = alignest.markCandidates([], file.coordinates, required, excluded);
                        text = "Excel・CSV（" + file.info.file + "）の座標";
                    else
                        selection = selectedWafers(c.markOptWafer);
                        [candidates, shots] = alignest.markCandidates(file.wafers(selection), zeros(0, 2), required, excluded);
                        text = "Excel・CSV（" + file.info.file + sprintf("、%d Wafer）", numel(selection));
                    end
            end
            input = struct("candidates", candidates, "shots", shots, "source", source, "text", text);
        end

        function showMarkLayoutCandidates(app)
            % 「候補の Mark」の表（番号・座標・値のある Shot の数・必ず計測）
            c = app.Controls;
            input = app.MarkLayoutInput;
            table_ = c.markOptCandidateTable;
            removeStyle(table_);
            table_.Selection = [];
            app.MarkLayoutSelection = zeros(0, 1);   % 表を作り直すと行が並び変わるので、前の選択は使わない
            drawMarkCandidates(app);
            if isempty(input)
                table_.Data = cell(0, 6);
                c.markOptCandidateInfo.Text = '';
                return
            end
            candidates = input.candidates;
            measuredShots = cellstr(string(candidates.nShots));
            if isempty(input.shots.label)
                measuredShots(:) = {'—'};
            end
            table_.Data = [num2cell(candidates.no), num2cell(candidates.xMm), num2cell(candidates.yMm), ...
                measuredShots, num2cell(candidates.required), num2cell(candidates.excluded)];
            if any(candidates.required)
                addStyle(table_, uistyle('FontColor', app.MARK_REQUIRED_COLOR, 'FontWeight', 'bold'), 'row', ...
                    find(candidates.required));
            end
            if any(candidates.excluded)
                addStyle(table_, uistyle('FontColor', app.Palette.muted), 'row', find(candidates.excluded));
            end
            c.markOptCandidateInfo.Text = sprintf('候補の Mark %d 点（必ず計測 %d 点・計測しない %d 点）', height(candidates), ...
                nnz(candidates.required), nnz(candidates.excluded));
            updateMarkLayoutEnabled(app);
        end

        function refreshMarkLayoutTerms(app)
            % 「使う項と VIF」の表（使うか・候補の Mark の位置で求めた VIF）と、使う項の数
            c = app.Controls;
            if ~isfield(c, 'markOptTermTable')
                return
            end
            try
                options = alignest.markLayoutOptions(app.Settings);
            catch err
                c.markOptTermInfo.Text = char("⚠ " + err.message);
                return
            end
            terms = alignest.highOrderTerms(options.maker, options.excludedTerms);
            input = app.MarkLayoutInput;
            vifText_ = "";
            if isempty(input)
                [terms.vifAll, terms.vifUsed] = deal(nan(height(terms), 1));
            else
                local = [input.candidates.xMm, input.candidates.yMm];
                [terms, info] = alignest.highOrderVif(terms, local, true(size(local)), options.vifThreshold);
                vifText_ = sprintf("VIF は候補の Mark %d 点の位置で求めました。", height(input.candidates));
                if isempty(info.suggestedExcluded)
                    vifText_ = vifText_ + "「VIF で選ぶ」で外れる項はありません。";
                else
                    vifText_ = vifText_ + "「VIF で選ぶ」で外れる項：" + strjoin("k" + string(info.suggestedExcluded), "・") + "。";
                end
            end
            n = height(terms);
            data = cell(n, 7);
            for k = 1:n
                data(k, :) = {terms.used(k), char(terms.axis(k)), sprintf('k%d', terms.k(k)), char(terms.term(k)), ...
                    terms.order(k), vifCell(terms.vifAll(k)), vifCell(terms.vifUsed(k))};
            end
            table_ = c.markOptTermTable;
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
            nX = nnz(terms.used & terms.axis == "dx");
            nY = nnz(terms.used & terms.axis == "dy");
            text = sprintf("使う項：dx %d / %d・dy %d / %d（最低数 %d 点）", nX, nnz(terms.axis == "dx"), nY, ...
                nnz(terms.axis == "dy"), max(nX, nY));
            c.markOptTermInfo.Text = char(text);
            c.markOptVifInfo.Text = char(vifText_);
        end

        function showMarkLayoutMapping(app, mapping)
            % 「Excel・CSV の列」の表とシートの一覧を、読み込んだ表と対応（項目 → ファイルの列）に合わせて作る
            c = app.Controls;
            file = app.MarkLayoutFile;
            columns = alignest.markLayoutColumns();
            data = cell(numel(columns), 4);
            for k = 1:numel(columns)
                value = "";
                if isfield(mapping, columns(k).name)
                    value = string(mapping.(columns(k).name));
                end
                if value == ""
                    value = app.NONE_LABEL;
                end
                data(k, :) = {columns(k).name, columns(k).meaning, char(ternary(columns(k).required, "必須", "任意")), ...
                    char(value)};
            end
            c.markOptMappingTable.Data = data;
            c.markOptMappingTable.ColumnFormat = {'char', 'char', 'char', cellstr([app.NONE_LABEL, file.info.columns])};
            removeStyle(c.markOptMappingTable);
            missing = find([columns.required].' & string(data(:, 4)) == app.NONE_LABEL);
            if ~isempty(missing)
                addStyle(c.markOptMappingTable, uistyle('BackgroundColor', app.Palette.warning), 'row', missing);
            end
            if all(file.info.sheets == "")
                setChoices(c.markOptSheet, "（CSV にはシートがありません）", {''});
                c.markOptSheet.Enable = 'off';
            else
                setChoices(c.markOptSheet, file.info.sheets, cellstr(file.info.sheets));
                c.markOptSheet.Value = char(file.info.sheet);
                c.markOptSheet.Enable = 'on';
            end
            c.markOptApplyMapping.Enable = 'on';
        end

        function mapping = currentMarkLayoutMapping(app)
            % 「Excel・CSV の列」の表で選んでいる対応（項目 → ファイルの列。「（なし）」は ""）
            data = app.Controls.markOptMappingTable.Data;
            mapping = struct();
            for k = 1:size(data, 1)
                value = string(data{k, 4});
                if value == app.NONE_LABEL
                    value = "";
                end
                mapping.(data{k, 1}) = value;
            end
        end

        function text = markLayoutFileText(app)
            % 読み込んだ表の説明（ファイル・シート・Wafer と Shot・行の数）
            file = app.MarkLayoutFile;
            text = file.info.file;
            if file.info.sheet ~= ""
                text = text + "（シート「" + file.info.sheet + "」）";
            end
            info = file.dataInfo;
            if isempty(info)
                return
            end
            if info.hasValues
                text = text + sprintf("：%d 行・%d Wafer・%d Shot", info.rows, info.wafers, info.shots);
            else
                text = text + sprintf("：%d 行（座標だけ）", info.rows);
            end
        end

        function snapshot = markLayoutSnapshot(app)
            % 計算の後に変えたかを見る入力・設定（設定・入力・Wafer・候補の Mark の位置。実測値で評価するときは Shot ごとの値も）
            input = app.MarkLayoutInput;
            positions = [];
            values = [];
            if ~isempty(input)
                positions = [input.candidates.xMm, input.candidates.yMm, input.candidates.required, input.candidates.excluded];
                if string(app.Settings.markLayout.values) == "measured"
                    values = struct("label", input.shots.label, "x", input.shots.valueX, "y", input.shots.valueY);
                end
            end
            snapshot = struct("settings", app.Settings.markLayout, "seed", app.Settings.sampling.seed, "source", ...
                string(app.Controls.markOptSource.Value), "selection", {app.Controls.markOptWafer.Value}, "positions", positions, ...
                "values", values);
        end

        function showMarkLayoutStudy(app)
            % 結果の図・配置の選択肢・表・知らせを出す
            c = app.Controls;
            study = app.MarkLayoutStudy;
            items = compose("%d 点（I 効率 %.1f%%）", study.counts, study.layouts.efficiency);
            setChoices(c.markOptMapCount, items, num2cell(study.counts));
            c.markOptMapCount.Enable = 'on';
            c.markOptExport.Enable = 'on';
            c.markOptExportSelection.Enable = 'on';
            c.markOptResultTable.Data = resultTable(study);
            rows = alignest.markLayoutCriterion(study);
            c.markOptCriterion.Value = cellstr(rows(:, 1) + "：" + rows(:, 2));
            drawMarkLayoutChart(app);
            drawMarkLayoutMap(app);
            showMarkLayoutMessages(app);
        end

        function showMarkLayoutMessages(app)
            % 右上のメッセージ：入力の説明・計算の知らせ・計算の後に変えたときの知らせ
            c = app.Controls;
            lines = reshape(string(c.markOptInputInfo.Text), [], 1);
            study = app.MarkLayoutStudy;
            if isempty(study)
                lines(end + 1, 1) = "入力と補正の式・回帰・配置の選び方を決め、「配置を最適化する」を押してください。";
                if string(c.markOptValues.Value) == "random" && ~markLayoutShapesCurrent(app)
                    lines(end, 1) = "「乱数 Shot 生成」で形を生成して確かめてから、「配置を最適化する」を押してください。";
                end
            else
                if ~isequaln(study.snapshot, markLayoutSnapshot(app))
                    lines(end + 1, 1) = "⚠ 計算の後に入力・候補の Mark・設定を変えました。「配置を最適化する」で計算し直してください" + ...
                        "（図と表は前の結果）。";
                end
                lines = [lines; reshape(study.messages, [], 1)];
                lines(end + 1, 1) = sprintf("配置は I(S) = Σ trace(M_S⁻¹ W) で選びました（dx %d 項・dy %d 項。" + ...
                    "式と項は「I 最適の式」タブ）。", study.nTerms(1), study.nTerms(2));
            end
            c.markOptMessage.Value = cellstr(lines);
        end

        function changeMarkState(app, positions, state)
            % Mark（Shot 内の座標）の指定を変える。state："required"（必ず計測）・"excluded"（計測しない）・"none"（指定なし）
            DIGITS = 4;   % 同じ位置とみなす桁（alignest.markCandidates と同じ）
            settings = app.Settings.markLayout;
            required = [reshape(settings.requiredXmm, [], 1), reshape(settings.requiredYmm, [], 1)];
            excluded = [reshape(settings.excludedXmm, [], 1), reshape(settings.excludedYmm, [], 1)];
            required = required(~ismember(round(required, DIGITS), round(positions, DIGITS), 'rows'), :);
            excluded = excluded(~ismember(round(excluded, DIGITS), round(positions, DIGITS), 'rows'), :);
            if state == "required"
                required = [required; positions];
            elseif state == "excluded"
                excluded = [excluded; positions];
            end
            app.Settings.markLayout.requiredXmm = required(:, 1);
            app.Settings.markLayout.requiredYmm = required(:, 2);
            app.Settings.markLayout.excludedXmm = excluded(:, 1);
            app.Settings.markLayout.excludedYmm = excluded(:, 2);
            refreshMarkLayoutInput(app);
        end

        function key = markLayoutShapeKey(app)
            % 乱数の形を作り直す条件（候補の Mark の位置・形の数・項の大きさ・ばらつき・飛び値・種）
            input = app.MarkLayoutInput;
            settings = app.Settings.markLayout;
            positions = [];
            if ~isempty(input)
                positions = [input.candidates.xMm, input.candidates.yMm];
            end
            key = struct("positions", positions, "shapes", settings.shapes, "orderSigmaNm", ...
                reshape(settings.orderSigmaNm, 1, []), "noiseNm", settings.noiseNm, "outlierPercent", settings.outlierPercent, ...
                "outlierNm", settings.outlierNm, "seed", app.Settings.sampling.seed);
        end

        function current = markLayoutShapesCurrent(app)
            % 生成した乱数の形が、今の候補の Mark と設定のものか
            current = ~isempty(app.MarkLayoutShapes) && isequaln(app.MarkLayoutShapes.key, markLayoutShapeKey(app));
        end

        function drawMarkPositions(app, ax, candidates, selected, titleText)
            % 候補の Mark（○）・計測する Mark（●）・必ず計測する Mark（赤い ◇）・計測しない Mark（×）を Shot 内の座標で描く
            cla(ax, 'reset');
            legend(ax, 'off');
            hold(ax, 'on');
            span = [min(candidates.xMm), max(candidates.xMm), min(candidates.yMm), max(candidates.yMm)];
            plot(ax, span([1, 2, 2, 1, 1]), span([3, 3, 4, 4, 3]), ':', 'Color', app.Palette.muted, ...
                'HandleVisibility', 'off');
            onClick = @(~, event) app.onMarkLayoutMapClicked(event);
            markers = scatter(ax, candidates.xMm, candidates.yMm, 60, app.Palette.muted, 'LineWidth', 1, ...
                'DisplayName', '候補の Mark');
            markers.ButtonDownFcn = onClick;
            if any(selected)
                chosen = scatter(ax, candidates.xMm(selected), candidates.yMm(selected), 60, app.PRIMARY_COLOR, 'filled', ...
                    'DisplayName', '計測する Mark');
                chosen.ButtonDownFcn = onClick;
            end
            if any(candidates.required)
                must = scatter(ax, candidates.xMm(candidates.required), candidates.yMm(candidates.required), 140, ...
                    app.MARK_REQUIRED_COLOR, 'd', 'LineWidth', 1.6, 'DisplayName', '必ず計測する Mark');
                must.ButtonDownFcn = onClick;
            end
            if any(candidates.excluded)
                never = scatter(ax, candidates.xMm(candidates.excluded), candidates.yMm(candidates.excluded), 80, ...
                    app.Palette.text, 'x', 'LineWidth', 1.4, 'DisplayName', '計測しない Mark');
                never.ButtonDownFcn = onClick;
            end
            hold(ax, 'off');
            axis(ax, 'equal');
            margin = 0.08 * max([span(2) - span(1), span(4) - span(3), 1]);
            xlim(ax, span(1:2) + [-margin, margin]);
            ylim(ax, span(3:4) + [-margin, margin]);
            xlabel(ax, 'Shot 内の X [mm]');
            ylabel(ax, 'Shot 内の Y [mm]');
            title(ax, titleText, 'Interpreter', 'none');
            grid(ax, 'on');
            box(ax, 'on');
            legend(ax, 'Location', 'southoutside', 'Orientation', 'horizontal', 'Interpreter', 'none', 'NumColumns', 2);
            styleAxes(app, ax, app.AXES_FONT_SIZE);
        end

        function storeMarkLayoutTable(app)
            % 画面で入力する座標の表（X・Y・必ず計測）を設定に移す（X・Y のどちらかが空の行は、まだ入れていない行として残す）
            data = app.Controls.markOptCandidateTable.Data;
            if isempty(data)
                coordinates = zeros(0, 2);
                [required, excluded] = deal(false(0, 1));
            else
                coordinates = cell2mat(data(:, 2:3));
                required = logical(cell2mat(data(:, 5)));
                excluded = logical(cell2mat(data(:, 6)));
            end
            complete = all(isfinite(coordinates), 2);
            if ~all(complete)
                return   % 入れ終わっていない行があるときは、表のまま待つ
            end
            app.Settings.markLayout.coordinateXmm = coordinates(:, 1);
            app.Settings.markLayout.coordinateYmm = coordinates(:, 2);
            app.Settings.markLayout.requiredXmm = coordinates(required, 1);
            app.Settings.markLayout.requiredYmm = coordinates(required, 2);
            app.Settings.markLayout.excludedXmm = coordinates(excluded, 1);
            app.Settings.markLayout.excludedYmm = coordinates(excluded, 2);
            refreshMarkLayoutInput(app);
        end

        % ----- 画面の操作 -----
        function onMarkLayoutSourceChanged(app)
            refreshMarkLayoutChoices(app);
            refreshMarkLayoutInput(app);
        end

        function onMarkLayoutWaferChanged(app)
            refreshMarkLayoutInput(app);
        end

        function onMarkLayoutSettingsChanged(app)
            c = app.Controls;
            maker = string(c.markOptMaker.Value);
            readMarkLayoutControls(app);
            updateMarkLayoutEnabled(app);
            try
                alignest.markLayoutOptions(app.Settings);
                c.markOptError.Text = '';
            catch err
                c.markOptError.Text = char(err.message);
            end
            refreshMarkLayoutTerms(app);
            if startsWith(maker, app.MARK_SET_PREFIX)
                c.markOptTermInfo.Text = char("保存した項の組み合わせ「" + extractAfter(maker, strlength(app.MARK_SET_PREFIX)) + ...
                    "」の式と項にしました。" + string(c.markOptTermInfo.Text));
            end
            drawMarkLayoutShape(app);
            if ~isempty(app.MarkLayoutStudy)
                drawMarkLayoutChart(app);
            end
            showMarkLayoutMessages(app);
        end

        function onMarkLayoutValuesChanged(app)
            app.MarkLayoutValuesAuto = false;   % 自分で選んだ値は、入力を変えても戻さない
            onMarkLayoutSettingsChanged(app);
        end

        function onMarkLayoutShapeChanged(app)
            onMarkLayoutSettingsChanged(app);   % 乱数の形の図も描き直す
        end

        function onMarkLayoutCandidateEdited(app, event)
            % 候補の表：必ず計測・計測しないを変えたら設定に移す（両方は選べない）。画面で入力する座標は X・Y も
            input = app.MarkLayoutInput;
            table_ = app.Controls.markOptCandidateTable;
            row = event.Indices(1);
            column = event.Indices(2);
            if any(column == [5, 6]) && logical(event.NewData)
                table_.Data{row, 11 - column} = false;   % もう一方の指定を外す
            end
            if string(app.Controls.markOptSource.Value) == "manual"
                storeMarkLayoutTable(app);
                return
            end
            if isempty(input) || row > height(input.candidates) || ~any(column == [5, 6])
                return
            end
            state = "none";
            if logical(event.NewData)
                state = ternary(column == 5, "required", "excluded");
            end
            changeMarkState(app, [input.candidates.xMm(row), input.candidates.yMm(row)], state);
        end

        function onMarkLayoutCandidateSelected(app, event)
            app.MarkLayoutSelection = unique(event.Indices(:, 1));
        end

        function onAddMarkLayoutRow(app)
            % 画面で入力する座標に、空の行を足す（X・Y を入れると候補の Mark になる）
            table_ = app.Controls.markOptCandidateTable;
            data = table_.Data;
            data(end + 1, :) = {size(data, 1) + 1, NaN, NaN, '—', false, false};
            table_.Data = data;
            scroll(table_, 'row', size(data, 1));
        end

        function onDeleteMarkLayoutRows(app)
            rows = app.MarkLayoutSelection;
            table_ = app.Controls.markOptCandidateTable;
            rows = rows(rows <= size(table_.Data, 1));
            if isempty(rows)
                uialert(app.Figure, '消す行を表で選んでください（セルをクリック。Shift・Ctrl で複数）。', '行を消す', ...
                    'Icon', 'info');
                return
            end
            table_.Data(rows, :) = [];
            app.MarkLayoutSelection = zeros(0, 1);
            storeMarkLayoutTable(app);
        end

        function onClearMarkLayoutRequired(app)
            app.Settings.markLayout.requiredXmm = zeros(0, 1);
            app.Settings.markLayout.requiredYmm = zeros(0, 1);
            app.Settings.markLayout.excludedXmm = zeros(0, 1);
            app.Settings.markLayout.excludedYmm = zeros(0, 1);
            refreshMarkLayoutInput(app);
        end

        function onMakeMarkLayoutGrid(app)
            runWithAlert(app, @() app.makeMarkLayoutGrid(), "格子で置けませんでした", ...
                "幅・高さ（0 以上）と列・行の数（1 以上）を確かめてください。");
        end

        function onMarkLayoutMapClicked(app, event)
            % 図の Mark をクリック：いちばん近い候補の Mark を、必ず計測 → 計測しない → 候補 の順に切り替える
            input = app.MarkLayoutInput;
            if isempty(input) || isempty(event)
                return
            end
            try
                point = event.IntersectionPoint(1:2);
            catch
                return   % クリックした位置が分からない
            end
            [~, row] = min(hypot(input.candidates.xMm - point(1), input.candidates.yMm - point(2)));
            state = "required";
            if input.candidates.required(row)
                state = "excluded";
            elseif input.candidates.excluded(row)
                state = "none";
            end
            changeMarkState(app, [input.candidates.xMm(row), input.candidates.yMm(row)], state);
        end

        function onMarkLayoutTermEdited(app, event)
            terms = app.Controls.markOptTermTable.UserData;
            row = event.Indices(1);
            if isempty(terms) || row > height(terms)
                return
            end
            if terms.protected(row) && ~event.NewData
                refreshMarkLayoutTerms(app);
                app.Controls.markOptTermInfo.Text = 'k1〜k6（並進・倍率・回転）は補正の土台なので外せません。';
                return
            end
            setMarkLayoutTermUsed(app, terms.k(row), logical(event.NewData));
        end

        function onMarkLayoutVifSelect(app)
            runWithAlert(app, @() app.selectMarkLayoutTermsByVif(), "VIF で選べませんでした", ...
                "入力を選んでください（VIF は候補の Mark の位置で求めます）。");
        end

        function onCopyHighOrderFormula(app)
            runWithAlert(app, @() app.copyHighOrderFormula(), "7. の式を写せませんでした", ...
                "「7. Shot高次補正」の補正の式・回帰の欄を確かめてください。");
        end

        function onOptimizeMarkLayout(app)
            c = app.Controls;
            c.markOptError.Text = '';
            try
                app.Figure.Pointer = 'watch';
                drawnow;
                optimizeMarkLayout(app);
                app.Figure.Pointer = 'arrow';
            catch err
                app.Figure.Pointer = 'arrow';
                c.markOptError.Text = char(err.message);
                if app.Figure.Visible == "on"
                    uialert(app.Figure, sprintf(['配置を最適化できませんでした。\n\n理由：%s\n\n次にすること：入力・' ...
                        '補正の式・最低数と最大数を確かめてください。'], err.message), '配置を最適化できませんでした', ...
                        'Icon', 'error');
                end
            end
        end

        function onExportMarkLayout(app)
            [fileName, folder] = uiputfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, '結果を書き出す', 'mark_layout.xlsx');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            if runWithAlert(app, @() app.exportMarkLayoutTo(target), "書き出せませんでした", ...
                    "保存先のフォルダを変えるか、同じ名前のファイルを Excel で開いていれば閉じてください。")
                uialert(app.Figure, sprintf('書き出しました：%s', target), '書き出しました', 'Icon', 'success');
            end
        end

        function onGenerateMarkLayoutShapes(app)
            runWithAlert(app, @() app.generateMarkLayoutShapes(), "乱数で Shot を生成できませんでした", ...
                "入力の候補の Mark と、項の大きさ・形の数を確かめてください。");
        end

        function onExportMarkSelection(app)
            count = app.Controls.markOptMapCount.Value;
            [fileName, folder] = uiputfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, 'この配置を書き出す', ...
                sprintf('mark_layout_%d_marks.xlsx', count));
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            if runWithAlert(app, @() app.exportMarkSelectionTo(target), "書き出せませんでした", ...
                    "保存先のフォルダを変えるか、同じ名前のファイルを Excel で開いていれば閉じてください。")
                uialert(app.Figure, sprintf('書き出しました：%s', target), '書き出しました', 'Icon', 'success');
            end
        end

        function onLoadMarkLayoutFile(app)
            [fileName, folder] = uigetfile({'*.xlsx;*.xls;*.xlsm;*.csv', 'Excel・CSV (*.xlsx, *.xls, *.xlsm, *.csv)'}, ...
                '入力の Excel・CSV を選ぶ');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.loadMarkLayoutFile(string(fullfile(folder, fileName))), "読み込めませんでした", ...
                "1行目が見出しの Excel・CSV か確かめてください。");
        end

        function onApplyMarkLayoutMapping(app)
            runWithAlert(app, @() app.applyMarkLayoutMapping(), "この列では使えませんでした", ...
                "Shot 内の座標の列（必須）と、X・Y の値の列（両方か、どちらも「（なし）」）を選び直してください。");
        end

        function onMarkLayoutSheetChanged(app)
            file = app.MarkLayoutFile;
            if isempty(file)
                return
            end
            runWithAlert(app, @() app.loadMarkLayoutFile(file.info.path, string(app.Controls.markOptSheet.Value)), ...
                "シートを読み込めませんでした", "1行目が見出しのシートか確かめてください。");
        end
    end
end

% ================= このファイルだけで使う小さな関数 =================
function text = markChartAxisLabel(name)
% 図の横軸の名前
labels = struct("efficiency", "I 効率 [%]", "criterionI", "I 基準", "count", "計測する Mark の数", "efficiencyD", ...
    "D 効率 [%]", "criterionD", "D 基準");
text = labels.(name);
end

function sizeMm = markShotSize(candidates)
% 候補の Mark が入る Shot の大きさ [mm]（Shot 中心を真ん中にした、候補の |x|・|y| の最大の2倍）
sizeMm = 2 * [max(abs(candidates.xMm)), max(abs(candidates.yMm))];
sizeMm(sizeMm == 0) = 1;
end

function ax = axesInPanel(parent, row)
% 図を枠（uipanel）に入れて格子の row 行目に置く（格子に直に置くと、下の行の説明が長くなったときに図の大きさが
% 遅れて変わり、説明と重なることがあるため。「7. Shot高次補正」のマップと同じ）
panel = uipanel(parent, 'BorderType', 'none');
place(panel, row, 1);
ax = uiaxes(uigridlayout(panel, [1, 1], 'Padding', 0));
end

function selection = selectedWafers(listbox)
% 一覧で選んでいる Wafer の番号（行ベクトル。選んでいなければ誤り）
selection = cell2mat(listbox.Value);
selection = reshape(selection(selection > 0), 1, []);
if isempty(selection)
    error('alignest:markLayout', 'Wafer を1つ以上選んでください。');
end
end

function [column, labelText] = chartColumn(statistic, points)
% 図の値の列の名前と説明
names = ["meanPlus3Sigma", "p95", "median", "rms"];
labels = ["|平均|+3σ", "|制御残差| 95% 点", "|制御残差| 中央値", "RMS"];
labelText = labels(names == statistic);
column = statistic;
if points == "unmeasured"
    column = "unmeasured" + upper(extractBefore(statistic, 2)) + extractAfter(statistic, 1);
    labelText = labelText + "（計測しなかった Mark）";
end
end

function text = vifCell(value)
% VIF の表示（求めていなければ空欄、決まらない項は ∞）
if isnan(value)
    text = '';
elseif isinf(value)
    text = '∞';
else
    text = sprintf('%.2f', value);
end
end

function pitch = markPitch(candidates)
% 候補の Mark の間隔の目安 [mm]（いちばん近い Mark までの距離の中央値。1点なら Shot の大きさ）
points = [candidates.xMm, candidates.yMm];
n = size(points, 1);
if n < 2
    pitch = 1;
    return
end
nearest = inf(n, 1);
for i = 1:n
    distance = hypot(points(:, 1) - points(i, 1), points(:, 2) - points(i, 2));
    distance(i) = Inf;
    nearest(i) = min(distance);
end
pitch = median(nearest);
end

function data = resultTable(study)
% 結果の表：配置ごとの I 効率・制御残差（X・Y）・補正しなかった Shot・入れ替えた Mark・計測する Mark
evaluation = study.evaluation;
if height(evaluation) == 0
    data = layoutOnlyTable(study);
    return
end
layouts = evaluation.layout(evaluation.axis == "X");
x = evaluation(evaluation.axis == "X", :);
y = evaluation(evaluation.axis == "Y", :);
nLayouts = numel(layouts);
changed = nan(nLayouts, 1);
marks = strings(nLayouts, 1);
for j = 1:nLayouts
    k = layouts(j);
    if k <= numel(study.counts)
        changed(j) = study.layouts.changed(k);
        marks(j) = strjoin(string(study.candidates.no(study.layouts.selected(:, k))), "・");
    else
        marks(j) = "すべて";
    end
end
changed(1) = NaN;   % 最初の数は比べる配置が無い
data = table(x.layoutType, x.count, round(x.efficiency, 1), round(x.meanPlus3Sigma, 3), round(y.meanPlus3Sigma, 3), ...
    round(x.p95, 3), round(y.p95, 3), round(x.unmeasuredMeanPlus3Sigma, 3), round(y.unmeasuredMeanPlus3Sigma, 3), ...
    max(x.skipped, y.skipped), changed, marks, 'VariableNames', ["配置", "Mark の数", "I 効率 [%]", ...
    "X ｜平均｜+3σ [nm]", "Y ｜平均｜+3σ [nm]", "X 95% 点 [nm]", "Y 95% 点 [nm]", ...
    "計測しなかった Mark の|X ｜平均｜+3σ [nm]", "計測しなかった Mark の|Y ｜平均｜+3σ [nm]", "補正しなかった|Shot", ...
    "入れ替えた|Mark", "計測する Mark の番号"]);
end

function data = layoutOnlyTable(study)
% 配置を選ぶ途中で止めたときの表：選んだ配置だけ（制御残差は求めていない）
nLayouts = numel(study.counts);
changed = study.layouts.changed;
changed(1) = NaN;   % 最初の数は比べる配置が無い
marks = strings(nLayouts, 1);
for k = 1:nLayouts
    marks(k) = strjoin(string(study.candidates.no(study.layouts.selected(:, k))), "・");
end
data = table(repmat("I 最適", nLayouts, 1), study.counts, round(study.layouts.efficiency, 1), changed, marks, ...
    'VariableNames', ["配置", "Mark の数", "I 効率 [%]", "入れ替えた|Mark", "計測する Mark の番号"]);
end
