classdef (Abstract) ResultsTab < appui.Core
    %RESULTSTAB 「4. 結果一覧」タブ：表・グラフ・基準の手法との比較・計測配置の比較・推定値と誤差の分布・箱ひげ図・散布図・残差と説明変数・分布の比較・処理時間の内訳と、評価点の絞り込み・結果の書き出しと読み込み。
    %   AlignmentEstimationApp（画面の本体）の一部。画面の部品は Controls、データ・結果は Core のプロパティに持つ。
    %   ほかのタブの関数も同じように呼べる（どれも AlignmentEstimationApp の関数になる）。

    methods
        function results = applyResultFilter(app, filter)
            %APPLYRESULTFILTER 評価点を半径・Shot の条件で絞り込み、結果一覧の表・グラフ・基準の手法との比較と、
            %   Wafer ごとのマップを描き直す（指標は alignest.filterResults で計算し直す。推定はやり直さない）。
            %   filter（alignest.defaultPointFilter と同じ形）を省くと、絞り込みを解除する。推定値と誤差の分布・箱ひげ図・
            %   散布図・分布の比較・推定値の書き出しは、次に計算するときに同じ条件で評価点を絞り込む。
            %   Excel から読み込んだ結果では表・グラフは計算し直せない（読み込んだ推定値を使う図だけを絞り込む）。
            if nargin < 2
                filter = alignest.defaultPointFilter();
            end
            if isempty(app.BaseResults)
                error('alignest:noResults', '先に「3. 実行」で評価してください。');
            end
            validateFilter(filter);
            if isImportedResults(app.BaseResults)
                results = app.BaseResults;
                results.filter = filter;
                [~, results.filterText] = alignest.pointFilterMask(filter);
            else
                results = alignest.filterResults(app.BaseResults, app.Data, filter);
            end
            app.ResultFilter = filter;
            app.Results = results;
            clearPointViews(app);
            showFilter(app);
            refreshResults(app);
            drawMap(app);
        end

        function exportResultsTo(app, filePath)
            %EXPORTRESULTSTO 結果を Excel に書き出す。
            if isempty(app.Results)
                error('alignest:noResults', '先に「3. 実行」で評価してください。');
            end
            if isImportedResults(app.Results)
                error('alignest:importedResults', ['Excel から読み込んだ結果は書き出せません（読み込んだファイル「%s」を' ...
                    'そのまま使ってください）。'], app.Results.imported);
            end
            alignest.exportResults(app.Results, filePath, app.FilePath);
        end

        function results = importResultsFrom(app, filePath)
            %IMPORTRESULTSFROM 「結果を Excel に書き出す」で書き出したファイルを読み込み、結果の画面に出す。
            %   表・グラフ・基準の手法との比較を見られる。推定値は Excel に無いので、Wafer マップ・推定値と誤差の分布・
            %   散布図・分布の比較は使えない（計測ファイルを読み込んで「3. 実行」で評価し直すと使える）。
            results = alignest.importResults(filePath);
            clearResults(app);
            app.Results = results;
            app.BaseResults = results;
            refreshResultControls(app);
            app.TabGroup.SelectedTab = app.Tabs.results;
        end

        function imported = importEstimatesFrom(app, filePath)
            %IMPORTESTIMATESFROM 「推定値を Excel に書き出す」で書き出したファイルを読み込み、Excel から読み込んだ評価結果と
            %   組にする。Wafer マップ・推定値と誤差の分布・散布図・分布の比較を、推定値の Excel にある手法・学習パターン・
            %   Wafer の範囲で描ける（計測ファイルは要らない）。先に importResultsFrom で評価結果を読み込んでおく。
            if ~isImportedResults(app.Results)
                error('alignest:importEstimates', ['先に「結果を読み込む…」で評価結果の Excel を読み込んでください' ...
                    '（推定値の Excel は、同じ評価から書き出した評価結果と組で使います）。']);
            end
            imported = alignest.importEstimates(filePath);
            results = app.Results;
            known = @(points) ismember(points.methodId, string({results.methods.id})) & ...
                ismember(points.group, results.groups) & ismember(points.Wafer, results.unitLabels);
            matched = known(imported.estimates);
            if ~any(matched)
                error('alignest:importEstimates', ['推定値の Excel の手法・学習パターン・Wafer が、読み込んだ評価結果に' ...
                    'ありません。同じ評価から書き出した2つのファイルを選んでください。']);
            end
            imported.estimates = imported.estimates(matched, :);
            imported.nIgnored = nnz(~matched);
            if height(imported.overlayPoints) > 0
                imported.overlayPoints = imported.overlayPoints(known(imported.overlayPoints), :);
            end
            app.ImportedEstimates = imported;
            app.Analysis = [];
            app.Distribution = [];
            refreshResultControls(app);
        end

        function analysis = analyzeResiduals(app, methodIndex, group, unitIndex)
            %ANALYZERESIDUALS 選んだ手法（複数可）・学習パターンの列・Wafer（0 = すべて）の評価点の残差を、
            %   ヒストグラム・正規性検定・質的変数の ANOVA で調べて「推定値と誤差の分布」に出す。手法を複数選ぶと、
            %   手法ごとに並べて比べる（ヒストグラムを重ね、表は手法ごとの行、箱ひげ図は手法を色分け）。
            requireEstimates(app);
            c = app.Controls;
            if nargin >= 2
                c.analysisMethod.Value = num2cell(reshape(methodIndex, 1, []));
                c.analysisGroup.Value = char(group);
                c.analysisWafer.Value = unitIndex;
            end
            selection = analysisSelection(app);
            [estimates, messages] = collectWithProgress(app, selection, app.MapCache, Inf, "残差を計算しています");
            if height(estimates) == 0
                error('alignest:noEstimates', '評価点がありません（この組み合わせは推定できませんでした）。%s', ...
                    strjoin(messages, newline));
            end
            analysis = alignest.residualAnalysis(estimates);
            app.Analysis = struct("estimates", estimates, "analysis", analysis, "selection", selection, ...
                "messages", messages);
            showAnalysis(app);
            % 同じ残差の箱ひげ図（質的変数は前の選択があればそのまま、無ければ最初の変数）
            names = string({alignest.residualFactors(estimates).name});
            c.boxFactor.Enable = onOff(~isempty(names));
            if isempty(names)
                c.boxFactor.Items = {'—'};
                c.boxInfo.Text = '質的変数に値が無いため、箱ひげ図は描けません。';
                return
            end
            previous = string(c.boxFactor.Value);
            c.boxFactor.Items = cellstr(names);
            c.boxFactor.Value = char(ternary(any(names == previous), previous, names(1)));
            drawResidualBoxplot(app);
        end

        function summary = drawResidualBoxplot(app, factorName)
            %DRAWRESIDUALBOXPLOT 最後に分析した残差（「推定値と誤差の分布」の「分析する」）を、質的変数の水準ごとの
            %   箱ひげ図で X・Y 別に「残差の箱ひげ図（ANOVA）」に描く。題名に一元配置の ANOVA の F・p 値・η² を書く。
            %   factorName（省略時は画面の選択）は alignest.residualFactors の変数の名前（例："Scan 方向"・"Mark 番号"）。
            %   summary は X・Y の水準ごとの点数・平均・中央値（alignest.plot.residualBoxplot）。
            c = app.Controls;
            if isempty(app.Analysis)
                error('alignest:noAnalysis', '先に「推定値と誤差の分布」で「分析する」を押してください。');
            end
            factors = alignest.residualFactors(app.Analysis.estimates);
            names = string({factors.name});
            if nargin >= 2
                if ~any(names == string(factorName))
                    error('alignest:boxFactor', '質的変数「%s」はこの分析にありません（%s）。', factorName, strjoin(names, "、"));
                end
                c.boxFactor.Items = cellstr(names);
                c.boxFactor.Value = char(factorName);
            end
            factor = factors(names == string(c.boxFactor.Value));
            anova = app.Analysis.analysis.anova;
            methodLabels = string(app.Analysis.estimates.methodLabel);
            methodNames = unique(methodLabels, 'stable');
            compareMethods = numel(methodNames) >= 2;   % 手法を比べるときは色分けし、検定の結果は下の文に手法ごとに書く
            notes = strings(1, 2);
            axisNames = ["X", "Y"];
            for k = 1:2
                titleText = axisNames(k) + " の残差：" + factor.name;
                rows = table();
                if height(anova) > 0
                    rows = anova(anova.axis == axisNames(k) & anova.factor == factor.name, :);
                end
                tested = height(rows) > 0 && any(isfinite(rows.F));
                if compareMethods
                    titleText = titleText + "（手法ごと）";
                    parts = strings(0, 1);
                    for r = 1:height(rows)
                        if isfinite(rows.F(r))
                            parts(end + 1) = sprintf("%s F = %.2f・p = %s（%s）", rows.methodLabel(r), rows.F(r), ...
                                pValueText(rows.p(r)), judgementWithNote(rows.judgement(r), rows.note(r))); %#ok<AGROW>
                        end
                    end
                    notes(k) = axisNames(k) + "：" + ternary(isempty(parts), "検定できません（水準が1つ、または点が少ない）", ...
                        strjoin(parts, "／"));
                elseif tested
                    titleText = titleText + sprintf("（一元配置 F = %.2f、p = %s、η² = %.3f）", rows.F(1), ...
                        pValueText(rows.p(1)), rows.etaSquared(1));
                    notes(k) = axisNames(k) + "：" + judgementWithNote(rows.judgement(1), rows.note(1));
                else
                    notes(k) = axisNames(k) + "：検定できません（水準が1つ、または点が少ない）";
                end
                part = alignest.plot.residualBoxplot(c.boxAxes(k), factor.levels, ...
                    app.Analysis.estimates.("residual" + axisNames(k)), titleText, methodLabels);
                summary(k) = struct("axis", axisNames(k), "levels", part); %#ok<AGROW>
            end
            set(c.boxAxes, 'Visible', 'on');
            styleAxes(app, c.boxAxes, app.AXES_FONT_SIZE);
            results = app.Results;
            selection = app.Analysis.selection;
            c.boxInfo.Text = sprintf("%s｜%s｜Wafer %d 枚｜判定（5%%）：%s", methodScopeText(results, selection), ...
                selection.groups, numel(selection.unitIndex), strjoin(notes, "、")) + filterNote(app);
        end

        function breakdown = measureTiming(app, unitIndex, planLabel, methodIndex, nRepeats)
            %MEASURETIMING 選んだ Wafer・学習パターン・手法（複数可）の処理時間を段階ごとに測り、「処理時間の内訳」に
            %   積み上げ横棒（秒・割合）と表で出す（alignest.timingBreakdown。評価の結果は変えない）。引数を省くと画面の選択。
            c = app.Controls;
            if isempty(app.BaseResults) || isImportedResults(app.BaseResults) || isempty(app.Data)
                error('alignest:noResults', ['処理時間は、計測データを読み込んで評価した結果で測れます' ...
                    '（Excel から読み込んだ結果では測れません）。']);
            end
            if nargin >= 2
                c.timingWafer.Value = unitIndex;
                c.timingPlan.Value = char(planLabel);
                c.timingMethods.Value = num2cell(methodIndex);
            end
            if nargin >= 5
                c.timingRepeats.Value = nRepeats;
            end
            results = app.BaseResults;
            methodIndex = cell2mat(c.timingMethods.Value);
            if isempty(methodIndex)
                error('alignest:timingBreakdown', '手法を1つ以上選んでください。');
            end
            runSettings = results.settings;
            if isfield(results, "runSettings")
                runSettings = results.runSettings;
            end
            if isfield(results, "specs")
                specs = results.specs;
            else
                specs = alignest.buildPlanSpecs(runSettings.sampling);
            end
            spec = specs(string({specs.label}) == string(c.timingPlan.Value));
            if isempty(spec)
                error('alignest:timingBreakdown', '学習パターン「%s」がありません。', c.timingPlan.Value);
            end
            dialog = [];
            if app.Figure.Visible == "on"
                dialog = uiprogressdlg(app.Figure, 'Title', '処理時間の内訳', 'Indeterminate', 'on', ...
                    'Message', '同じ計算をくり返して時間を測っています…');
            end
            cleanup = onCleanup(@() closeDialog(dialog));
            unit = app.Data.units(c.timingWafer.Value);
            breakdown = alignest.timingBreakdown(unit, spec(1), results.methods(methodIndex), runSettings, ...
                c.timingRepeats.Value);
            app.Timing = breakdown;
            alignest.plot.timingBars(c.timingAxes(1), c.timingAxes(2), breakdown);
            set(c.timingAxes, 'Visible', 'on');
            styleAxes(app, c.timingAxes, app.AXES_FONT_SIZE);
            values = breakdown.table{:, cellstr(breakdown.stages)};
            rows = cell(height(breakdown.table), numel(breakdown.stages) + 2);
            for m = 1:height(breakdown.table)
                total = breakdown.table.total(m);
                rows{m, 1} = char(breakdown.table.methodLabel(m));
                rows{m, 2} = sprintf('%.3f', total);
                for k = 1:numel(breakdown.stages)
                    rows{m, k + 2} = sprintf('%.4f（%.0f%%）', values(m, k), 100 * values(m, k) / max(total, eps));
                end
            end
            c.timingTable.Data = rows;
            c.timingTable.ColumnName = cellstr(["手法", "合計 [秒]", breakdown.labels + " [秒]"]);
            c.timingTable.ColumnWidth = [{scaledPixels(app, app.METHOD_COLUMN_WIDTH), scaledPixels(app, 90)}, ...
                repmat({'auto'}, 1, numel(breakdown.stages))];
            c.timingInfo.Text = sprintf("%s｜%s｜学習点 X %d・Y %d、評価点 X %d・Y %d｜", unit.label, spec(1).label, ...
                breakdown.nTrain, breakdown.nTest) + c.timingInfo.UserData;
        end

        function summary = drawScatter(app, methodIndex, group, unitIndex, colorBy)
            %DRAWSCATTER 選んだ手法・学習パターンの列・Wafer（0 = すべて）の評価点で、実測値と推定値の散布図を X・Y 別に描く。
            %   colorBy は色分けの項目（none・wafer・lot・eqp・operation・scan・mark・row・col:<列名>）。
            requireEstimates(app);
            c = app.Controls;
            if nargin >= 2
                c.scatterMethod.Value = methodIndex;
                c.scatterGroup.Value = char(group);
                c.scatterWafer.Value = unitIndex;
                c.scatterColor.Value = char(colorBy);
            end
            unitIndex = c.scatterWafer.Value;
            if unitIndex == 0
                unitIndex = 1:numel(app.Results.unitLabels);
            end
            selection = struct("methodIndex", c.scatterMethod.Value, "groups", string(c.scatterGroup.Value), ...
                "unitIndex", unitIndex);
            estimates = collectWithProgress(app, selection, app.MapCache, Inf, "散布図の推定値を計算しています");
            if height(estimates) == 0
                error('alignest:noEstimates', '評価点がありません（この組み合わせは推定できませんでした）。');
            end
            categories = scatterCategories(app, estimates, string(c.scatterColor.Value));
            spec = resultSpec(app);
            summary = alignest.plot.estimateScatter(c.scatterAxes(1), estimates.measX, estimates.estimateX, categories, ...
                spec.labels(1), spec.unit);
            if spec.scalar
                c.scatterAxesGrid.ColumnWidth = {'1x', 0};   % 1変数は Y 成分が無い
                cla(c.scatterAxes(2), 'reset');
                c.scatterAxes(2).Visible = 'off';
            else
                c.scatterAxesGrid.ColumnWidth = {'1x', '1x'};
                c.scatterAxes(2).Visible = 'on';
                summary(2) = alignest.plot.estimateScatter(c.scatterAxes(2), estimates.measY, estimates.estimateY, ...
                    categories, "Y");
            end
            styleAxes(app, c.scatterAxes, app.AXES_FONT_SIZE);
            c.scatterInfo.Text = sprintf(['%s｜%s｜Wafer %d 枚｜色：%s。破線は y = x、赤い線は回帰直線' ...
                '（推定値 = a + b·実測値）、r は相関係数。'], app.Results.methods(selection.methodIndex).label, ...
                selection.groups, numel(unitIndex), string(c.scatterColor.Items{strcmp(c.scatterColor.ItemsData, ...
                c.scatterColor.Value)})) + filterNote(app);
        end

        function summary = drawResidualVariables(app, methodIndex, group, unitIndex, variable)
            %DRAWRESIDUALVARIABLES 「残差と説明変数」：選んだ手法・学習パターンの列・Wafer（0 = すべて）の評価点の残差と、
            %   説明変数（variable：x・y・r・theta・markX・markY・shotX・shotY。alignest.explanatoryValues）の散布図を X・Y 別に
            %   描き、すべての説明変数と残差の相関係数・p 値を表に出す。引数を省くと画面の選択。
            %   summary は X・Y の alignest.stats.correlationTest の結果（1変数は X だけ）と、表（table）。
            c = app.Controls;
            if isempty(app.Results)
                error('alignest:noResults', '先に「3. 実行」で評価してください。');
            end
            if nargin >= 2
                c.residualVariableMethod.Value = methodIndex;
                c.residualVariableGroup.Value = char(group);
                c.residualVariableWafer.Value = unitIndex;
            end
            if nargin >= 5
                c.residualVariableName.Value = char(variable);
            end
            unitIndex = c.residualVariableWafer.Value;
            if unitIndex == 0
                unitIndex = 1:numel(app.Results.unitLabels);
            end
            selection = struct("methodIndex", c.residualVariableMethod.Value, "groups", ...
                string(c.residualVariableGroup.Value), "unitIndex", unitIndex);
            estimates = collectWithProgress(app, selection, app.MapCache, Inf, "残差を計算しています");
            if height(estimates) == 0
                error('alignest:noEstimates', '評価点がありません（この組み合わせは推定できませんでした）。');
            end
            units = [];
            if ~isImportedResults(app.Results) && ~isempty(app.Data)
                units = app.Data.units;
            end
            [values, keys, labels] = alignest.explanatoryValues(estimates, units, app.Results.unitLabels);
            key = string(c.residualVariableName.Value);
            variableLabel = labels(keys == key);
            spec = resultSpec(app);
            summary = struct("X", [], "Y", [], "table", table());
            summary.X = alignest.plot.residualVsVariable(c.residualVariableAxes(1), values.(key), estimates.residualX, ...
                variableLabel, spec.labels(1) + " の残差", spec.unit);
            if spec.scalar
                c.residualVariableAxesGrid.ColumnWidth = {'1x', 0};   % 1変数は Y 成分が無い
                cla(c.residualVariableAxes(2), 'reset');
                c.residualVariableAxes(2).Visible = 'off';
            else
                c.residualVariableAxesGrid.ColumnWidth = {'1x', '1x'};
                c.residualVariableAxes(2).Visible = 'on';
                summary.Y = alignest.plot.residualVsVariable(c.residualVariableAxes(2), values.(key), estimates.residualY, ...
                    variableLabel, "Y の残差");
            end
            c.residualVariableAxes(1).Visible = 'on';
            styleAxes(app, c.residualVariableAxes, app.AXES_FONT_SIZE);
            % すべての説明変数と残差の相関（値の無い説明変数は「—」）
            rows = cell(numel(keys), 6);
            [rX, pX, rY, pY, counts] = deal(nan(numel(keys), 1));
            for k = 1:numel(keys)
                testX = alignest.stats.correlationTest(values.(keys(k)), estimates.residualX);
                testY = alignest.stats.correlationTest(values.(keys(k)), estimates.residualY);
                [rX(k), pX(k), rY(k), pY(k), counts(k)] = deal(testX.r, testX.p, testY.r, testY.p, testX.n);
                rows(k, :) = {char(labels(k)), numberText(rX(k), '%+.3f'), pValueText(pX(k)), numberText(rY(k), '%+.3f'), ...
                    pValueText(pY(k)), sprintf('%d', counts(k))};
            end
            c.residualVariableTable.Data = rows;
            c.residualVariableTable.ColumnName = cellstr(["説明変数", spec.labels(1) + " の残差：r", "p 値", ...
                "Y の残差：r", "p 値", "点数"]);
            summary.table = table(labels(:), rX, pX, rY, pY, counts, 'VariableNames', ["variable", "rX", "pX", "rY", ...
                "pY", "n"]);
            removeStyle(c.residualVariableTable);
            strong = find(max(abs(rX), abs(rY)) >= app.RESIDUAL_CORRELATION_NOTICE);
            if ~isempty(strong)
                addStyle(c.residualVariableTable, uistyle('BackgroundColor', app.Palette.warning), 'row', strong);
            end
            scopeText = sprintf("%s｜%s｜Wafer %d 枚", app.Results.methods(selection.methodIndex).label, selection.groups, ...
                numel(unitIndex));
            note = scopeText + filterNote(app) + "。" + c.residualVariableInfo.UserData;
            if ~isempty(strong)
                note = note + sprintf(" ⚠ |r| ≥ %.1f の説明変数（表の色付きの行）は、残差に傾向が残っています（その" + ...
                    "説明変数を加える・手法を変えることを検討）。", app.RESIDUAL_CORRELATION_NOTICE);
            end
            c.residualVariableInfo.Text = char(note);
        end

        function comparison = compareDistributions(app, methodIndex, group, unitIndex)
            %COMPAREDISTRIBUTIONS 選んだ手法・学習パターンの列・Wafer（0 = すべて）で、Wafer 全面・学習データ・予測対象の
            %   計測値の分布と、予測対象の実測値と推定値の分布を、ヒストグラム・代表統計値・JS ダイバージェンスで比べる
            %   （alignest.distributionComparison）。引数を省くと画面の選択を使う。
            requireEstimates(app);
            c = app.Controls;
            if nargin >= 2
                c.distributionMethod.Value = methodIndex;
                c.distributionGroup.Value = char(group);
                c.distributionWafer.Value = unitIndex;
            end
            unitIndex = c.distributionWafer.Value;
            if unitIndex == 0
                unitIndex = 1:numel(app.Results.unitLabels);
            end
            selection = struct("methodIndex", c.distributionMethod.Value, "groups", string(c.distributionGroup.Value), ...
                "unitIndex", unitIndex);
            % 読み込んだ推定値では、Wafer 全面・学習の分布を学習データの行から作る（計測ファイルが無いので）
            imported = isImportedResults(app.Results);
            [estimates, messages] = collectWithProgress(app, selection, app.MapCache, Inf, "分布を比べる推定値を計算しています", ...
                imported);
            if nnz(estimates.role == "評価") == 0
                error('alignest:noEstimates', '評価点がありません（この組み合わせは推定できませんでした）。%s', ...
                    strjoin(messages, newline));
            end
            data = app.Data;
            if imported
                data = [];
            end
            comparison = alignest.distributionComparison(data, app.Results, selection, estimates);
            comparison.title = sprintf("%s｜%s｜Wafer %d 枚", app.Results.methods(selection.methodIndex).label, ...
                selection.groups, comparison.nWafers) + filterNote(app);
            app.Distribution = comparison;
            statsRows = cell(0, 9);
            jsRows = cell(0, 4);
            for axisName = ["X", "Y"]
                stats = comparison.(axisName).stats;
                for k = 1:height(stats)
                    statsRows(end + 1, :) = {char(axisName), char(stats.name(k)), stats.n(k), round4(stats.mean(k)), ...
                        round4(stats.std(k)), round4(stats.median(k)), round4(stats.min(k)), round4(stats.max(k)), ...
                        round4(stats.meanPlus3Sigma(k))}; %#ok<AGROW>
                end
                js = comparison.(axisName).js;
                for k = 1:height(js)
                    jsRows(end + 1, :) = {char(axisName), char(js.pair(k)), round4(js.js(k)), char(js.meaning(k))}; %#ok<AGROW>
                end
            end
            c.distributionTable.Data = statsRows;
            c.jsTable.Data = jsRows;
            drawDistributionHistograms(app);
        end

        function exportEstimatesTo(app, filePath, scope)
            %EXPORTESTIMATESTO 推定値（Mark ごとの計測値・推定値・残差）と残差の検定結果を Excel に書き出す。
            %   学習データの Mark も書き出し、その推定値・残差は空欄にする（「区分」の列で見分ける）。
            %   scope = "selected"：「推定値と誤差の分布」で選んだ手法・学習パターン・Wafer
            %           "all"     ：すべての手法・学習パターン・Wafer（評価で求めた推定値を使う。行が多いと書き出しに時間がかかる）
            requireEstimates(app);
            if isImportedResults(app.Results)
                error('alignest:importedResults', ['Excel から読み込んだ推定値は書き出せません（読み込んだファイル「%s」を' ...
                    'そのまま使ってください）。'], app.ImportedEstimates.file);
            end
            if nargin < 3
                scope = string(app.Controls.estimateScope.Value);
            end
            results = app.Results;
            if scope == "all"
                selection = struct("methodIndex", 1:numel(results.methods), "groups", results.groups, ...
                    "unitIndex", 1:numel(results.unitLabels));
                scopeText = "すべての手法・学習パターン・Wafer";
            else
                selection = analysisSelection(app);
                scopeText = "選んだ手法・学習パターン・Wafer";
            end
            % 評価で求めた推定値は記憶（app.MapCache）にあるので、推定し直さずに使う
            [estimates, messages, overlayPoints] = collectWithProgress(app, selection, app.MapCache, app.EXCEL_MAX_DATA_ROWS, ...
                "推定値を計算しています", true);
            analysis = alignest.residualAnalysis(estimates(estimates.role == "評価", :));
            notes = ["読み込んだファイル", app.FilePath; "書き出した範囲", scopeText; ...
                "手法", strjoin(string({results.methods(selection.methodIndex).label}), "、"); ...
                "学習パターンの列", strjoin(selection.groups, "、"); ...
                "Wafer", strjoin(results.unitLabels(selection.unitIndex), "、")];
            spec = resultSpec(app);
            if spec.scalar
                notes = [notes; "推定した値", "1変数：列「" + spec.name + "」（単位 " + spec.unit + "）。計測値・推定値・" + ...
                    "残差は X の列（Y の列は空欄）"];
            end
            if ~isempty(messages)
                notes = [notes; [repmat("推定できなかった組み合わせ", numel(messages), 1), messages(:)]];
            end
            if isfield(results, "overlayEvaluated") && results.overlayEvaluated
                notes = [notes; "Overlay 補正のモデル", results.overlayDescription];
            end
            [~, filterText, filterActive] = alignest.pointFilterMask(app.ResultFilter);
            if filterActive
                notes = [notes; "評価点の絞り込み", filterText + "（「推定値」シートの評価の行と検定。Overlay 残差のシートは" + ...
                    "絞り込まない）"];
            end
            alignest.exportEstimates(estimates, analysis, filePath, notes, overlayPoints=overlayPoints);
        end

        function comparison = drawLayoutComparison(app, methodIndex, xAxis, errorBar)
            %DRAWLAYOUTCOMPARISON 「計測配置の比較」：1つの手法について、選び方（I 最適・D 最適・ランダム・優先順・
            %   Mark 単位）ごとに、横軸（計測する Mark の数・学習 Shot 数・D 効率・I 効率）に対する指標の線を描き、
            %   人の選択・手動は点で描く（alignest.layoutComparison。指標と Wafer の集計は結果一覧の上の選択）。
            %   errorBar（alignest.errorBarKinds）を選ぶと、評価点ごとに Wafer のばらつきのエラーバーを描く。
            %   引数を省くと画面の選択。
            c = app.Controls;
            comparison = table();
            if isempty(app.Results)
                return
            end
            if nargin >= 2
                c.compareLayoutMethod.Value = methodIndex;
            end
            if nargin >= 3
                c.compareLayoutXAxis.Value = char(xAxis);
            end
            if nargin >= 4
                c.compareLayoutErrorBar.Value = char(errorBar);
            end
            metric = string(c.metric.Value);
            statistic = string(c.statistic.Value);
            comparison = alignest.layoutComparison(app.Results, c.compareLayoutMethod.Value, metric, statistic);
            xChoice = string(c.compareLayoutXAxis.Value);
            [x, axisLabel, fallbackNote] = layoutAxisValues(comparison, xChoice);
            [lowerBar, upperBar, errorLabel] = alignest.layoutErrorBars(comparison, string(c.compareLayoutErrorBar.Value));
            drawBars = string(c.compareLayoutErrorBar.Value) ~= "none";
            ax = c.compareLayoutAxes;
            cla(ax, 'reset');
            legend(ax, 'off');
            hold(ax, 'on');
            markers = {'o', 's', 'd', '^', 'v', 'p'};
            types = unique(comparison.type, 'stable');
            for k = 1:numel(types)
                rows = find(comparison.type == types(k) & isfinite(x) & isfinite(comparison.value));
                if isempty(rows)
                    continue
                end
                [~, order] = sort(x(rows));
                rows = rows(order);
                name = comparison.typeLabel(rows(1));
                marker = markers{mod(k - 1, numel(markers)) + 1};
                if types(k) == "manual"
                    % 人の選択・手動はパターンごとに点を描き、名前を添える
                    points = plotWithBars(x(rows), comparison.value(rows), lowerBar(rows), upperBar(rows), marker, 'none', 9);
                    text(ax, x(rows), comparison.value(rows), "  " + comparison.group(rows), 'FontSize', 10, ...
                        'Color', points.Color, 'VerticalAlignment', 'bottom', 'Interpreter', 'none', 'HandleVisibility', 'off');
                else
                    points = plotWithBars(x(rows), comparison.value(rows), lowerBar(rows), upperBar(rows), marker, '-', 7);
                end
                points.DisplayName = name;
            end
            hold(ax, 'off');
            grid(ax, 'on');
            box(ax, 'on');
            [names, labels] = alignest.metricNames(true, true, resultSpec(app));
            xlabel(ax, axisLabel);
            ylabel(ax, labels(names == metric));
            title(ax, sprintf("選び方の比較：%s（Wafer の%s）", comparison.Properties.UserData.methodLabel, ...
                statisticLabel(statistic)), 'Interpreter', 'none');
            if ~isempty(ax.Children)
                legend(ax, 'Location', 'best', 'Box', 'off', 'FontSize', 10);
            end
            styleAxes(app, ax, app.AXES_FONT_SIZE);
            rows = cell(height(comparison), 10);
            for k = 1:height(comparison)
                rows(k, :) = {char(comparison.typeLabel(k)), char(comparison.group(k)), numberText(comparison.nShots(k), '%.1f'), ...
                    numberText(comparison.nMarks(k), '%.1f'), numberText(comparison.value(k), '%.3f'), ...
                    numberText(comparison.sd(k), '%.3f'), numberText(comparison.criterionI(k), '%.4g'), ...
                    numberText(comparison.criterionD(k), '%.4g'), numberText(100 * comparison.efficiencyI(k), '%.1f%%'), ...
                    numberText(100 * comparison.efficiencyD(k), '%.1f%%')};
            end
            c.compareLayoutTable.Data = rows;
            c.compareLayoutTable.ColumnName = cellstr(["選び方", "列", "学習 Shot 数", "計測 Mark 数", labels(names == metric), ...
                "標準偏差", "I 基準", "D 基準", "I 効率", "D 効率"]);
            note = string(c.compareLayoutInfo.UserData);
            if comparison.Properties.UserData.nTypes < 2
                note = "⚠ この評価の選び方は1つです。" + note;
            end
            note = note + fallbackNote;
            if drawBars
                note = note + "　エラーバー：" + errorLabel + "（Wafer ごとの値から）。";
                if string(c.compareLayoutErrorBar.Value) == "ci95" && statistic ~= "mean"
                    note = note + "集計が平均ではないので、信頼区間の幅は目安です。";
                end
            end
            c.compareLayoutInfo.Text = note + filterNote(app);

            function line = plotWithBars(xValues, yValues, lower, upper, marker, lineStyle, markerSize)
                % エラーバーを選んだときは errorbar（縦の線と線・点を一緒に描く）、選ばないときは plot
                if drawBars
                    lower(~isfinite(lower)) = 0;   % Wafer が1枚の列などは縦の線を描かない
                    upper(~isfinite(upper)) = 0;
                    line = errorbar(ax, xValues, yValues, lower, upper, 'Marker', marker, 'LineStyle', lineStyle, ...
                        'MarkerSize', markerSize, 'LineWidth', 1.5, 'CapSize', 8);
                else
                    line = plot(ax, xValues, yValues, 'Marker', marker, 'LineStyle', lineStyle, 'MarkerSize', markerSize, ...
                        'LineWidth', 1.5);
                end
            end
        end
    end

    methods (Access = {?appui.Core})
        % ================= 4. 結果一覧 =================
        function buildResultsTab(app)
            grid = uigridlayout(app.Tabs.results, [3, 1], 'RowHeight', {'fit', 'fit', '1x'}, 'Padding', 12, 'RowSpacing', 8);
            % ボタンは右に 2 × 2 でまとめる（横に並べると、狭い窓で基準の手法の欄が無くなり、見出しが縦に長く折り返すため）
            controls = uigridlayout(grid, [3, 4], 'ColumnWidth', {260, 160, '1x', 'fit'}, 'Padding', 0, ...
                'RowHeight', {'fit', 'fit', 0});
            registerResponsiveColumn(app, controls, 1);
            registerResponsiveColumn(app, controls, 2);
            label(controls, '指標', 1, 1);
            label(controls, '集計（Wafer 間）', 1, 2);
            label(controls, '基準の手法（「基準の手法との比較」で比べる相手）', 1, 3);
            [names, labels] = alignest.metricNames();
            onChange = @(~, ~) app.refreshResults();
            c.metric = uidropdown(controls, 'Items', cellstr(labels), 'ItemsData', cellstr(names), 'Value', 'RMSE_XY', ...
                'ValueChangedFcn', onChange);
            place(c.metric, 2, 1);
            [statistics, statisticLabels] = alignest.statisticNames();
            c.statistic = uidropdown(controls, 'Items', cellstr(statisticLabels), 'ItemsData', cellstr(statistics), ...
                'Tooltip', ['ワースト値：最も悪い Wafer の値（誤差は最大、R² は最小）。' ...
                '95%値：95% の Wafer がこの値より良い（誤差は 95 パーセント点、R² は 5 パーセント点）。'], ...
                'ValueChangedFcn', onChange);
            place(c.statistic, 2, 2);
            c.reference = uidropdown(controls, 'Items', {'—'}, 'ValueChangedFcn', onChange);
            place(c.reference, 2, 3);
            buttons = uigridlayout(controls, [2, 3], 'ColumnWidth', {'fit', 'fit', 'fit'}, 'RowHeight', {'fit', 'fit'}, ...
                'Padding', 0, 'RowSpacing', 4);
            buttons.Layout.Row = [1, 2];
            buttons.Layout.Column = 4;
            c.export = primaryButton(app, buttons, '結果を Excel に書き出す…', @(~, ~) app.onExport());
            place(c.export, 1, 1);
            c.saveChart = uibutton(buttons, 'Text', 'グラフを画像で保存…', 'ButtonPushedFcn', @(~, ~) app.onSaveChart());
            place(c.saveChart, 1, 2);
            c.copyChart = uibutton(buttons, 'Text', 'グラフをコピー', 'Tooltip', app.COPY_TOOLTIP, ...
                'ButtonPushedFcn', @(source, ~) app.onCopyFigure("chart", source));
            place(c.copyChart, 1, 3);
            set([c.export, c.saveChart, c.copyChart], 'Enable', 'off');
            c.importResults = uibutton(buttons, 'Text', '結果を読み込む…', 'ButtonPushedFcn', @(~, ~) app.onImportResults(), ...
                'Tooltip', '「結果を Excel に書き出す」で書き出したファイルを読み込み、表・グラフ・基準の手法との比較を見ます。');
            place(c.importResults, 2, 1);
            c.importEstimates = uibutton(buttons, 'Text', '推定値の Excel を読み込む…', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onImportEstimates(), 'Tooltip', ['「推定値を Excel に書き出す」で書き出した' ...
                'ファイルを読み込むと、Excel から読み込んだ結果でも Wafer マップ・推定値と誤差の分布・散布図・分布の比較を' ...
                '描けます（書き出した範囲だけ）。先に「結果を読み込む…」で評価結果を読み込んでください。']);
            place(c.importEstimates, 2, 2);
            c.resultSource = uilabel(controls, 'WordWrap', 'on', 'Text', '');
            c.resultSource.Layout.Row = 3;
            c.resultSource.Layout.Column = [1, 4];
            c.resultControls = controls;
            c.filterResults = buildFilterControls(app, grid, "results");

            % 表・グラフ・比較・誤差の分布は、それぞれ画面の幅いっぱいに出す（手法の名前が切れないように）
            c.resultTabs = uitabgroup(grid, 'SelectionChangedFcn', @(~, event) app.onResultTabChanged(event));
            tableTab = uitab(c.resultTabs, 'Title', '表（手法 × 学習パターン）');
            tableGrid = uigridlayout(tableTab, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 8);
            c.tableNote = uilabel(tableGrid, 'WordWrap', 'on', ...
                'Text', ['各列で最も良い手法に「★」を付け、背景も色づけしています。集計の「ワースト値」は最も悪い Wafer の値、' ...
                '「95%値」は 95% の Wafer がそれより良い値（誤差は大きい側、R²・改善率は小さい側）です。']);
            c.summaryTable = uitable(tableGrid, 'RowName', {}, 'ColumnName', {'手法'});
            c.chartTab = uitab(c.resultTabs, 'Title', 'グラフ');
            chartGrid = uigridlayout(c.chartTab, [2, 2], 'RowHeight', {'fit', '1x'}, 'ColumnWidth', {'1x', 380}, 'Padding', 8);
            registerResponsiveColumn(app, chartGrid, 2);
            chartControls = uigridlayout(chartGrid, [1, 5], 'ColumnWidth', {'fit', 380, 'fit', 190, 'fit'}, 'Padding', 0);
            place(chartControls, 1, 1);
            label(chartControls, '横軸', 1, 1);
            c.chartXAxis = uidropdown(chartControls, 'Items', {'学習 Shot 数（学習パターン）', ...
                'I 基準と D 基準（I 最適計画の評価指標。2つ並べる）'}, 'ItemsData', {'plan', 'criteria'}, ...
                'Tooltip', ['学習 Shot の組の I 基準 tr(M⁻¹) と D 基準 det(M)^(−1/p)（XY 多項式の基準モデル）に対する推定誤差。' ...
                '点は学習パターンの列ごとの Wafer の集計。基準は Wafer の平均。'], 'ValueChangedFcn', @(~, ~) app.drawChart());
            place(c.chartXAxis, 1, 2);
            label(chartControls, 'エラーバー', 1, 3);
            c.chartErrorBars = uidropdown(chartControls, 'Items', {'なし', '±1σ（Wafer 間）', '95% 区間（平均）'}, ...
                'ItemsData', {'none', 'sd', 'ci'}, 'ValueChangedFcn', @(~, ~) app.drawChart(), ...
                'Tooltip', ['±1σ：Wafer ごとの値（ランダムのくり返しは平均）の標準偏差。95% 区間：Wafer の平均の区間' ...
                '（± 1.96σ/√Wafer 数）。点の値（平均・中央値など、上の「集計」）を中心に描きます。']);
            place(c.chartErrorBars, 1, 4);
            c.chartPoints = uicheckbox(chartControls, 'Text', 'Wafer ごとの点（I・D 基準）', ...
                'ValueChangedFcn', @(~, ~) app.drawChart());
            place(c.chartPoints, 1, 5);
            c.chartPanel = uipanel(chartGrid, 'BorderType', 'none');
            place(c.chartPanel, 2, 1);
            c.chartAxesGrid = uigridlayout(c.chartPanel, [1, 2], 'ColumnWidth', {'1x', 0}, 'Padding', 0, 'ColumnSpacing', 8);
            c.chartAxes = uiaxes(c.chartAxesGrid);
            c.chartAxes2 = uiaxes(c.chartAxesGrid, 'Visible', 'off');
            label(chartGrid, 'グラフに描く手法（Ctrl・Shift で複数選ぶ）', 1, 2);
            c.chartMethods = uilistbox(chartGrid, 'Items', {}, 'Multiselect', 'on', 'ValueChangedFcn', @(~, ~) app.drawChart());
            place(c.chartMethods, 2, 2);
            compareTab = uitab(c.resultTabs, 'Title', '基準の手法との比較');
            compareGrid = uigridlayout(compareTab, [2, 1], 'RowHeight', {'fit', '1x'}, 'Padding', 8);
            c.comparisonNote = uilabel(compareGrid, 'WordWrap', 'on', 'Text', '');
            c.comparisonTable = uitable(compareGrid, 'RowName', {}, ...
                'ColumnName', {'手法', '列', '基準との差', '95% 区間', '基準より良かった割合', 'Wafer 数'});
            % 計測配置の比較：選び方（I 最適・D 最適・人の選択など）ごとに、学習点の数に対する指標を比べる
            c.layoutCompareTab = uitab(c.resultTabs, 'Title', '計測配置の比較');
            layoutGrid = uigridlayout(c.layoutCompareTab, [3, 2], 'RowHeight', {'fit', '1x', 'fit'}, ...
                'ColumnWidth', {'1.2x', '1x'}, 'Padding', 8, 'ColumnSpacing', 12);
            layoutControls = uigridlayout(layoutGrid, [1, 6], 'ColumnWidth', {'fit', '1x', 'fit', 220, 'fit', 280}, ...
                'Padding', 0);
            place(layoutControls, 1, [1, 2]);
            label(layoutControls, '手法', 1, 1);
            c.compareLayoutMethod = uidropdown(layoutControls, 'Items', {'—'}, 'Enable', 'off', ...
                'ValueChangedFcn', @(~, ~) app.drawLayoutComparison());
            place(c.compareLayoutMethod, 1, 2);
            label(layoutControls, '横軸', 1, 3);
            c.compareLayoutXAxis = uidropdown(layoutControls, 'Items', {'計測する Mark の数', '学習 Shot 数', ...
                'D 効率（全計測に対する）', 'I 効率（全計測に対する）'}, 'ItemsData', {'marks', 'shots', 'efficiencyD', ...
                'efficiencyI'}, 'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.drawLayoutComparison(), ...
                'Tooltip', ['計測する Mark の数：Shot 単位と Mark 単位の計画を同じ計測の手間で比べる。学習 Shot 数：Shot 単位の' ...
                '計画どうしを比べる（Mark 単位の計画は全 Shot を計測するので右端に寄る）。D 効率・I 効率：全計測に対する' ...
                '計画の良さ（%。100% なら全計測と同じ）で比べる（効率が同じなら誤差も同じくらいか確かめられる）。']);
            place(c.compareLayoutXAxis, 1, 4);
            label(layoutControls, 'エラーバー', 1, 5);
            [errorKinds, errorLabels] = alignest.errorBarKinds();
            c.compareLayoutErrorBar = uidropdown(layoutControls, 'Items', cellstr(errorLabels), ...
                'ItemsData', cellstr(errorKinds), 'Enable', 'off', 'ValueChangedFcn', @(~, ~) app.drawLayoutComparison(), ...
                'Tooltip', ['評価点ごとに、Wafer ごとの値のばらつきを縦の線で描きます。標準偏差：Wafer 間のばらつき。' ...
                '95% 信頼区間：平均の確からしさ（正規近似。集計が平均以外のときも同じ幅を目安として描く）。' ...
                '最小〜最大：Wafer の値の範囲。Wafer が1枚の列は、標準偏差・信頼区間を描きません。']);
            place(c.compareLayoutErrorBar, 1, 6);
            c.compareLayoutAxes = uiaxes(layoutGrid);
            place(c.compareLayoutAxes, 2, 1);
            c.compareLayoutTable = uitable(layoutGrid, 'RowName', {}, 'ColumnName', {'選び方', '列', '学習 Shot 数', ...
                '計測 Mark 数', '指標', '標準偏差', 'I 基準', 'D 基準', 'I 効率', 'D 効率'}, ...
                'ColumnWidth', {110, 140, 75, 75, 'auto', 70, 65, 65, 60, 60});
            place(c.compareLayoutTable, 2, 2);
            layoutNote = ['「2. 評価の設定」の選び方を2つ以上選んで評価すると、選び方ごとの線（人の選択・手動は点）で比べられます' ...
                '（指標と Wafer の集計は上の「指標」「集計」）。I 基準・D 基準は小さいほど良い計画（Wafer の平均）。'];
            c.compareLayoutInfo = uilabel(layoutGrid, 'WordWrap', 'on', 'Text', layoutNote, 'UserData', string(layoutNote));
            place(c.compareLayoutInfo, 3, [1, 2]);

            analysisTab = uitab(c.resultTabs, 'Title', '推定値と誤差の分布');
            analysisGrid = uigridlayout(analysisTab, [5, 1], 'RowHeight', {'fit', '3x', 96, '1x', 'fit'}, ...
                'Padding', 8, 'RowSpacing', 8);
            analysisControls = uigridlayout(analysisGrid, [2, 6], 'ColumnWidth', {'1x', 150, 220, 'fit', 300, 'fit'}, ...
                'RowHeight', {'fit', app.ANALYSIS_METHOD_LIST_HEIGHT}, 'Padding', 0);
            arrayfun(@(column) registerResponsiveColumn(app, analysisControls, column), [2, 3, 5]);
            label(analysisControls, '手法（複数選ぶと並べて比べる）', 1, 1);
            label(analysisControls, '学習パターン（列）', 1, 2);
            label(analysisControls, 'Wafer', 1, 3);
            label(analysisControls, 'Excel に書き出す範囲', 1, 5);
            c.analysisMethod = uilistbox(analysisControls, 'Items', {'—'}, 'Multiselect', 'on', 'Tooltip', ...
                ['比べる手法（Ctrl・Shift を押しながらクリックで複数）。複数選ぶと、ヒストグラム・正規性検定・ANOVA の表と' ...
                '「残差の箱ひげ図（ANOVA）」で手法を並べて比べます。']);
            place(c.analysisMethod, 2, 1);
            c.analysisGroup = uidropdown(analysisControls, 'Items', {'—'});
            place(c.analysisGroup, 2, 2);
            c.analysisWafer = uidropdown(analysisControls, 'Items', {'—'});
            place(c.analysisWafer, 2, 3);
            c.analyze = uibutton(analysisControls, 'Text', '分析する', 'ButtonPushedFcn', @(~, ~) app.onAnalyze());
            place(c.analyze, 2, 4);
            c.estimateScope = uidropdown(analysisControls, 'Items', {'左で選んだ手法・学習パターン・Wafer', ...
                'すべての手法・学習パターン・Wafer（行が多い）'}, 'ItemsData', {'selected', 'all'});
            place(c.estimateScope, 2, 5);
            c.exportEstimates = uibutton(analysisControls, 'Text', '推定値を Excel に書き出す…', ...
                'ButtonPushedFcn', @(~, ~) app.onExportEstimates());
            place(c.exportEstimates, 2, 6);
            c.histogramGrid = uigridlayout(analysisGrid, [1, 2], 'Padding', 0, 'ColumnSpacing', 12);
            c.histogramAxes = [uiaxes(c.histogramGrid), uiaxes(c.histogramGrid)];
            c.normalityTable = uitable(analysisGrid, 'RowName', {}, 'ColumnName', {'手法', '軸', '点数', '平均 [nm]', ...
                '標準偏差 [nm]', '歪度', '尖度（過剰）', 'Shapiro–Wilk W', 'p 値', 'Anderson–Darling A²', 'p 値', ...
                'Jarque–Bera', 'p 値', '判定（5%）'}, ...
                'ColumnWidth', {150, 40, 60, 80, 105, 60, 90, 170, 70, 170, 70, 100, 70, 'auto'});
            c.anovaTable = uitable(analysisGrid, 'RowName', {}, 'ColumnName', {'手法', '軸', '質的変数', ...
                '水準ごとの平均残差 [nm]（点数）', 'F（一元配置）', 'p 値', 'η²', 'F（ほかの変数で調整）', 'p 値', ...
                '判定（一元配置、5%）・メモ'}, 'ColumnWidth', {150, 40, 125, 340, 100, 70, 55, 150, 70, 'auto'});
            noteText = ['残差 = 計測値 − 推定値（評価点）。p 値 < 0.05 なら、正規分布から外れている（ANOVA は水準で残差の' ...
                '平均が違う）と判断。点数が多いと小さなずれでも p 値が小さくなるので、ヒストグラムと合わせて見てください。'];
            c.analysisNote = uilabel(analysisGrid, 'WordWrap', 'on', 'Text', noteText, 'UserData', string(noteText), ...
                'Tooltip', ['評価点は学習しなかった Shot の有効な Mark。選んだ Wafer の評価点をまとめて検定します。' ...
                'Shapiro–Wilk は 3〜5000 点のときだけ計算し、判定に使います（超えるときは Anderson–Darling）。' ...
                '計算しなかったときは、表の W の欄に理由（点数など）を出します。' ...
                '「ほかの変数で調整」は、ほかの質的変数の効果を差し引いた主効果（交互作用なし、Type II）の検定です。']);
            % 残差の箱ひげ図：「推定値と誤差の分布」で分析した残差を、質的変数の水準ごとに X・Y 別に描く（ANOVA の中身を見る）
            c.boxTab = uitab(c.resultTabs, 'Title', '残差の箱ひげ図（ANOVA）');
            boxGrid = uigridlayout(c.boxTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 8, 'RowSpacing', 8);
            boxControls = uigridlayout(boxGrid, [1, 3], 'ColumnWidth', {'fit', 260, '1x'}, 'Padding', 0);
            label(boxControls, '質的変数', 1, 1);
            c.boxFactor = uidropdown(boxControls, 'Items', {'—'}, 'Enable', 'off', ...
                'ValueChangedFcn', @(~, ~) app.onDrawResidualBoxplot(), 'Tooltip', ['「推定値と誤差の分布」の ANOVA と同じ' ...
                '質的変数（Scan 方向・Mark 番号・Shot 行の奇偶・工程・装置・ロット・その他の列）。']);
            place(c.boxFactor, 1, 2);
            boxHelp = label(boxControls, ['「推定値と誤差の分布」で「分析する」を押した残差を描きます。箱は四分位範囲、中の線は' ...
                '中央値、ひげは箱から 1.5 × 四分位範囲まで、外の点は外れ値、◆ は平均（ANOVA は水準の平均の違いを調べる）。'], 1, 3);
            boxHelp.FontColor = app.Palette.muted;
            boxAxesGrid = uigridlayout(boxGrid, [1, 2], 'Padding', 0, 'ColumnSpacing', 12);
            c.boxAxes = [uiaxes(boxAxesGrid), uiaxes(boxAxesGrid)];
            set(c.boxAxes, 'Visible', 'off');
            c.boxInfo = uilabel(boxGrid, 'WordWrap', 'on', 'Text', '');
            c.scatterTab = uitab(c.resultTabs, 'Title', '推定値と実測値の散布図');
            scatterGrid = uigridlayout(c.scatterTab, [3, 1], 'RowHeight', {'fit', '1x', 'fit'}, 'Padding', 8, 'RowSpacing', 8);
            scatterControls = uigridlayout(scatterGrid, [2, 5], 'ColumnWidth', {'1x', 150, 220, 240, 'fit'}, ...
                'RowHeight', {'fit', 'fit'}, 'Padding', 0);
            label(scatterControls, '手法', 1, 1);
            label(scatterControls, '学習パターン（列）', 1, 2);
            label(scatterControls, 'Wafer', 1, 3);
            label(scatterControls, '色分け', 1, 4);
            c.scatterMethod = uidropdown(scatterControls, 'Items', {'—'});
            place(c.scatterMethod, 2, 1);
            c.scatterGroup = uidropdown(scatterControls, 'Items', {'—'});
            place(c.scatterGroup, 2, 2);
            c.scatterWafer = uidropdown(scatterControls, 'Items', {'—'});
            place(c.scatterWafer, 2, 3);
            c.scatterColor = uidropdown(scatterControls, 'Items', {'—'}, ...
                'Tooltip', ['点の色を分ける項目（LotID・EqpId・Operation・Scan 方向・Mark 番号・Shot 行・外周と内側' ...
                '（「2. 評価の設定」の外周の半径）・象限・ファイルのその他の列）']);
            place(c.scatterColor, 2, 4);
            c.drawScatterButton = uibutton(scatterControls, 'Text', '描く', 'ButtonPushedFcn', @(~, ~) app.onDrawScatter());
            place(c.drawScatterButton, 2, 5);
            c.scatterAxesGrid = uigridlayout(scatterGrid, [1, 2], 'Padding', 0, 'ColumnSpacing', 12);
            c.scatterAxes = [uiaxes(c.scatterAxesGrid), uiaxes(c.scatterAxesGrid)];
            c.scatterInfo = uilabel(scatterGrid, 'WordWrap', 'on', 'Text', ['評価点（学習しなかった Shot の有効な Mark）の' ...
                '実測値と推定値。破線は y = x、赤い線は回帰直線（推定値 = a + b·実測値）。r は相関係数。']);
            % 残差と説明変数：評価点の残差に、説明変数（座標・半径・方位角・Shot 内の位置）の傾向が残っていないかを見る
            c.residualVariableTab = uitab(c.resultTabs, 'Title', '残差と説明変数');
            variableGrid = uigridlayout(c.residualVariableTab, [4, 1], 'RowHeight', {'fit', '1x', 118, 'fit'}, ...
                'Padding', 8, 'RowSpacing', 8);
            variableControls = uigridlayout(variableGrid, [2, 5], 'ColumnWidth', {'1x', 150, 220, 250, 'fit'}, ...
                'RowHeight', {'fit', 'fit'}, 'Padding', 0);
            label(variableControls, '手法', 1, 1);
            label(variableControls, '学習パターン（列）', 1, 2);
            label(variableControls, 'Wafer', 1, 3);
            label(variableControls, '説明変数（横軸）', 1, 4);
            c.residualVariableMethod = uidropdown(variableControls, 'Items', {'—'});
            place(c.residualVariableMethod, 2, 1);
            c.residualVariableGroup = uidropdown(variableControls, 'Items', {'—'});
            place(c.residualVariableGroup, 2, 2);
            c.residualVariableWafer = uidropdown(variableControls, 'Items', {'—'});
            place(c.residualVariableWafer, 2, 3);
            [~, variableKeys, variableLabels] = alignest.explanatoryValues(table(zeros(0, 1), zeros(0, 1), ...
                'VariableNames', ["x", "y"]));
            c.residualVariableName = uidropdown(variableControls, 'Items', cellstr(variableLabels), ...
                'ItemsData', cellstr(variableKeys), 'ValueChangedFcn', @(~, ~) app.onDrawResidualVariables(true), ...
                'Tooltip', ['横軸にする説明変数。下の表には、すべての説明変数と残差の相関係数を出します' ...
                '（Shot 内・Shot 中心の座標は、このセッションで評価した結果で使えます）。']);
            place(c.residualVariableName, 2, 4);
            c.drawResidualVariableButton = uibutton(variableControls, 'Text', '描く', ...
                'ButtonPushedFcn', @(~, ~) app.onDrawResidualVariables(false));
            place(c.drawResidualVariableButton, 2, 5);
            c.residualVariableAxesGrid = uigridlayout(variableGrid, [1, 2], 'Padding', 0, 'ColumnSpacing', 12);
            c.residualVariableAxes = [uiaxes(c.residualVariableAxesGrid), uiaxes(c.residualVariableAxesGrid)];
            set(c.residualVariableAxes, 'Visible', 'off');
            c.residualVariableTable = uitable(variableGrid, 'RowName', {}, 'ColumnName', {'説明変数', 'X の残差：r', ...
                'p 値', 'Y の残差：r', 'p 値', '点数'}, 'ColumnWidth', {220, 110, 90, 110, 90, 'auto'});
            variableNote = ['評価点の残差（計測値 − 推定値）と説明変数の散布図。赤い線は回帰直線、黒い線は区間ごとの平均' ...
                '（曲がった傾向）。r は相関係数（0 に近いほど、その説明変数の傾向は残っていない）、p 値 < 0.05 なら相関がある' ...
                'と判断。点が多いと小さな相関でも p 値が小さくなるので、r の大きさと図を合わせて見てください。'];
            c.residualVariableInfo = uilabel(variableGrid, 'WordWrap', 'on', 'Text', variableNote, ...
                'UserData', string(variableNote));
            % 分布の比較：Wafer 全面・学習データ・予測対象の計測値と、予測対象の実測値と推定値
            c.distributionTab = uitab(c.resultTabs, 'Title', '分布の比較');
            distributionGrid = uigridlayout(c.distributionTab, [4, 1], 'RowHeight', {'fit', '1.5x', '1x', 'fit'}, ...
                'Padding', 8, 'RowSpacing', 8);
            distributionControls = uigridlayout(distributionGrid, [2, 5], 'ColumnWidth', {'1x', 150, 220, 90, 'fit'}, ...
                'RowHeight', {'fit', 'fit'}, 'Padding', 0);
            label(distributionControls, '手法', 1, 1);
            label(distributionControls, '学習パターン（列）', 1, 2);
            label(distributionControls, 'Wafer', 1, 3);
            label(distributionControls, '軸', 1, 4);
            c.distributionMethod = uidropdown(distributionControls, 'Items', {'—'});
            place(c.distributionMethod, 2, 1);
            c.distributionGroup = uidropdown(distributionControls, 'Items', {'—'});
            place(c.distributionGroup, 2, 2);
            c.distributionWafer = uidropdown(distributionControls, 'Items', {'—'});
            place(c.distributionWafer, 2, 3);
            c.distributionAxis = uidropdown(distributionControls, 'Items', {'X', 'Y'}, 'ItemsData', {'X', 'Y'}, ...
                'ValueChangedFcn', @(~, ~) app.drawDistributionHistograms());
            place(c.distributionAxis, 2, 4);
            c.compareDistributionsButton = uibutton(distributionControls, 'Text', '比べる', ...
                'ButtonPushedFcn', @(~, ~) app.onCompareDistributions());
            place(c.compareDistributionsButton, 2, 5);
            distributionAxesGrid = uigridlayout(distributionGrid, [1, 2], 'Padding', 0, 'ColumnSpacing', 12);
            c.distributionAxes = [uiaxes(distributionAxesGrid), uiaxes(distributionAxesGrid)];
            set(c.distributionAxes, 'Visible', 'off');
            tableGrid = uigridlayout(distributionGrid, [1, 2], 'ColumnWidth', {'1.4x', '1x'}, 'Padding', 0, 'ColumnSpacing', 12);
            c.distributionTable = uitable(tableGrid, 'RowName', {}, 'ColumnName', {'軸', '分布', '点数', '平均 [nm]', ...
                '標準偏差 [nm]', '中央値 [nm]', '最小 [nm]', '最大 [nm]', '|平均|+3σ [nm]'}, ...
                'ColumnWidth', {35, 150, 55, 80, 100, 85, 80, 80, 'auto'});
            c.jsTable = uitable(tableGrid, 'RowName', {}, 'ColumnName', {'軸', '比べる分布', 'JS ダイバージェンス', ...
                '見ること'}, 'ColumnWidth', {35, 270, 120, 'auto'});
            distributionNote = ['左：Wafer 全面・学習データ・予測対象（学習しなかった Shot の有効な Mark）の計測値。' ...
                '右：予測対象の実測値と推定値。ヒストグラムは4つに共通の区間の割合。JS ダイバージェンス（Jensen–Shannon、' ...
                '底 2）は分布の一致性で、0 なら同じ、1 なら重なりなし（同じ区間で求める）。'];
            c.distributionInfo = uilabel(distributionGrid, 'WordWrap', 'on', 'Text', distributionNote, ...
                'UserData', string(distributionNote));
            % 処理時間の内訳：1つの条件の処理を段階（学習パターンの作成・異常値の判定・学習・推論など）に分けて測る
            c.timingTab = uitab(c.resultTabs, 'Title', '処理時間の内訳');
            timingGrid = uigridlayout(c.timingTab, [4, 1], 'RowHeight', {'fit', '1x', 120, 'fit'}, 'Padding', 8, ...
                'RowSpacing', 8);
            timingControls = uigridlayout(timingGrid, [2, 5], 'ColumnWidth', {220, 220, '1x', 110, 'fit'}, ...
                'RowHeight', {'fit', 66}, 'Padding', 0);
            label(timingControls, 'Wafer', 1, 1);
            label(timingControls, '学習パターン', 1, 2);
            label(timingControls, '手法（Ctrl・Shift で複数選ぶ）', 1, 3);
            label(timingControls, '測る回数', 1, 4);
            c.timingWafer = uidropdown(timingControls, 'Items', {'—'}, 'Enable', 'off');
            place(c.timingWafer, 2, 1);
            c.timingPlan = uidropdown(timingControls, 'Items', {'—'}, 'Enable', 'off');
            place(c.timingPlan, 2, 2);
            c.timingMethods = uilistbox(timingControls, 'Items', {}, 'Multiselect', 'on', 'Enable', 'off');
            place(c.timingMethods, 2, 3);
            c.timingRepeats = uispinner(timingControls, 'Limits', app.TIMING_REPEAT_LIMITS, 'Value', 3, ...
                'RoundFractionalValues', 'on', 'Enable', 'off', 'Tooltip', '同じ計算を何回測って中央値をとるか（多いほど安定するが遅い）。');
            place(c.timingRepeats, 2, 4);
            c.measureTimingButton = uibutton(timingControls, 'Text', '測る', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onMeasureTiming());
            place(c.measureTimingButton, 2, 5);
            timingAxesGrid = uigridlayout(timingGrid, [1, 2], 'ColumnWidth', {'1x', '1.2x'}, 'Padding', 0, 'ColumnSpacing', 12);
            c.timingAxes = [uiaxes(timingAxesGrid), uiaxes(timingAxesGrid)];
            set(c.timingAxes, 'Visible', 'off');
            c.timingTable = uitable(timingGrid, 'RowName', {}, 'ColumnName', {'手法'});
            timingNote = ['選んだ Wafer・学習パターン・手法の1回分の処理（学習パターンの作成 → 異常値の判定 → 推定の準備 → ' ...
                '学習 → 推論 → 評価指標・Overlay 補正の評価）を、評価と同じ関数で測ります（評価の結果は変えません）。' ...
                '学習と推論は、全評価点を推定した時間と評価点を1点にした時間の差を推論としています。評価では学習パターンを' ...
                '同じ配置の Wafer・手法で使い回すので、評価全体に占める作成の割合はこれより小さくなります。'];
            c.timingInfo = uilabel(timingGrid, 'WordWrap', 'on', 'Text', timingNote, 'UserData', string(timingNote));
            app.Controls = mergeStruct(app.Controls, c);
        end

        function f = buildFilterControls(app, parent, source)
            % 評価点の絞り込みの欄。「4. 結果一覧」と「5. Waferごとのマップ」に同じものを置き、どちらで変えても両方をそろえる
            f.grid = uigridlayout(parent, [2, 14], 'ColumnWidth', {'fit', 64, 'fit', 64, 'fit', 175, 110, 'fit', 80, 'fit', ...
                160, 'fit', 'fit', '1x'}, 'RowHeight', {'fit', 'fit'}, 'Padding', 0, 'ColumnSpacing', 4, 'RowSpacing', 2);
            arrayfun(@(column) registerResponsiveColumn(app, f.grid, column), [2, 4, 6, 7, 11]);
            filterTip = ['評価点（学習しなかった Shot の Mark）を、Mark の半径・Shot の条件で絞り込み、指標を計算し直して' ...
                '表・グラフ・比較・マップを描き直します（推定はやり直しません）。'];
            title_ = label(f.grid, '評価点の絞り込み：半径 [mm]', 1, 1);
            title_.FontWeight = 'bold';
            title_.Tooltip = filterTip;
            f.radiusMin = uieditfield(f.grid, 'numeric', 'Limits', [0, Inf], 'Value', 0, 'ValueDisplayFormat', '%g', ...
                'Tooltip', 'Mark の半径の下限 [mm]（この値以上）');
            place(f.radiusMin, 1, 2);
            label(f.grid, '〜', 1, 3);
            f.radiusMax = uieditfield(f.grid, 'numeric', 'Limits', [0, Inf], 'Value', Inf, 'ValueDisplayFormat', '%g', ...
                'Tooltip', 'Mark の半径の上限 [mm]（この値未満。Inf なら上限なし）');
            place(f.radiusMax, 1, 4);
            label(f.grid, 'Shot', 1, 5);
            f.shotMode = uidropdown(f.grid, 'Items', {'すべて', '右の shotNo だけ', '右の shotNo を除く'}, ...
                'ItemsData', {'all', 'include', 'exclude'});
            place(f.shotMode, 1, 6);
            f.shotNos = uieditfield(f.grid, 'text', 'Placeholder', '例：1 5 12', ...
                'Tooltip', 'shotNo を空白またはカンマで区切って入れます。');
            place(f.shotNos, 1, 7);
            label(f.grid, 'Scan', 1, 8);
            f.scan = uidropdown(f.grid, 'Items', {'すべて', '1', '2'}, 'ItemsData', {0, 1, 2});
            place(f.scan, 1, 9);
            label(f.grid, '最外周', 1, 10);
            f.outer = uidropdown(f.grid, 'Items', {'含める', '最外周の Shot だけ', '最外周の Shot を除く'}, ...
                'ItemsData', {'all', 'only', 'exclude'}, 'Tooltip', '最外周の Shot：上下左右のどこかに隣の Shot が無い Shot');
            place(f.outer, 1, 11);
            f.apply = uibutton(f.grid, 'Text', '絞り込んで再計算', 'Enable', 'off', 'Tooltip', filterTip, ...
                'ButtonPushedFcn', @(~, ~) app.onApplyFilter(source));
            place(f.apply, 1, 12);
            f.clear = uibutton(f.grid, 'Text', '解除', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.onClearFilter());
            place(f.clear, 1, 13);
            f.status = uilabel(f.grid, 'WordWrap', 'on', 'Text', '絞り込みなし');
            place(f.status, 2, [1, 14]);
        end

        function onApplyFilter(app, source)
            % 押した側（結果一覧・マップ）の欄から条件を読んで絞り込む
            controls = app.Controls.(ternary(source == "map", "filterMap", "filterResults"));
            runWithAlert(app, @() app.applyResultFilter(readFilterControls(controls)), "絞り込めませんでした", ...
                "半径は 下限 < 上限 にし、shotNo を使うときは整数を空白で区切って入れてください。");
        end

        function onClearFilter(app)
            runWithAlert(app, @() app.applyResultFilter(), "絞り込みを解除できませんでした", ...
                "もう一度「解除」を押してください。");
        end

        function showFilter(app)
            % 絞り込みの条件を、結果一覧とマップの両方の欄と説明に出す
            filter = app.ResultFilter;
            [~, text, active] = alignest.pointFilterMask(filter);
            status = "絞り込みなし";
            if active && ~isempty(app.Results)
                if isImportedResults(app.Results)
                    status = "絞り込み中：" + text + "（Excel から読み込んだ結果の表・グラフは計算し直せません。" + ...
                        "読み込んだ推定値の図・分布・散布図だけに使います）";
                else
                    base = app.BaseResults.table;
                    shown = app.Results.table;
                    status = sprintf("絞り込み中：%s（評価点 %d / %d 点。X・Y の合計、全行）", text, ...
                        sum(shown.nTest_X + shown.nTest_Y), sum(base.nTest_X + base.nTest_Y));
                end
            elseif active
                status = "絞り込みの条件：" + text;
            end
            for name = ["filterResults", "filterMap"]
                if ~isfield(app.Controls, name)
                    continue
                end
                f = app.Controls.(name);
                f.radiusMin.Value = filter.radiusMinMm;
                f.radiusMax.Value = filter.radiusMaxMm;
                f.shotMode.Value = char(filter.shotMode);
                f.shotNos.Value = char(strjoin(string(filter.shotNos), " "));
                f.scan.Value = filter.scan;
                f.outer.Value = char(filter.outer);
                f.status.Text = status;
                f.status.FontColor = ternary(active, app.Palette.accent, app.Palette.text);
                f.clear.Enable = onOff(active && ~isempty(app.Results));
            end
        end

        function clearPointViews(app)
            % 絞り込みを変えたら、評価点から描いた図・表（分布・箱ひげ図・散布図・分布の比較）を消す（古い点のままにしない）
            c = app.Controls;
            app.Analysis = [];
            app.Distribution = [];
            c.normalityTable.Data = {};
            c.anovaTable.Data = {};
            c.distributionTable.Data = {};
            c.jsTable.Data = {};
            for ax = [c.histogramAxes, c.scatterAxes, c.boxAxes, c.distributionAxes, c.residualVariableAxes]
                cla(ax, 'reset');
                legend(ax, 'off');
            end
            set([c.boxAxes, c.distributionAxes, c.residualVariableAxes], 'Visible', 'off');
            c.residualVariableTable.Data = {};
            c.residualVariableInfo.Text = c.residualVariableInfo.UserData;
            c.boxFactor.Items = {'—'};
            c.boxFactor.Enable = 'off';
            c.boxInfo.Text = '';
            c.analysisNote.Text = c.analysisNote.UserData;
        end

        function onDrawResidualBoxplot(app)
            runWithAlert(app, @() app.drawResidualBoxplot(), "箱ひげ図を描けませんでした", ...
                "「推定値と誤差の分布」で「分析する」を押してから、質的変数を選び直してください。");
        end

        function onMeasureTiming(app)
            runWithAlert(app, @() app.measureTiming(), "処理時間を測れませんでした", ...
                "Wafer・学習パターン・手法を選び直してから、もう一度「測る」を押してください。");
        end

        function refreshResultControls(app)
            c = app.Controls;
            results = app.Results;
            labels = string({results.methods.label});
            ids = string({results.methods.id});
            [metricList, metricLabels] = alignest.metricNames(isfield(results, "timingRecorded") && results.timingRecorded, ...
                isfield(results, "overlayEvaluated") && results.overlayEvaluated, resultSpec(app));
            current = string(c.metric.Value);
            c.metric.Items = cellstr(metricLabels);
            c.metric.ItemsData = cellstr(metricList);
            c.metric.Value = char(ternary(any(metricList == current), current, "RMSE_XY"));
            c.reference.Items = cellstr(labels);
            c.reference.ItemsData = cellstr(ids);
            preferred = find(ids == "GPR_matern52_XYR_basis", 1);
            if isempty(preferred)
                preferred = 1;
            end
            c.reference.Value = char(ids(preferred));
            c.chartMethods.Items = cellstr(labels);
            c.chartMethods.ItemsData = num2cell(1:numel(labels));
            summary = alignest.summarizeResults(results, "RMSE_XY", "mean");
            [~, order] = sort(mean(summary.values, 2, 'omitnan'));
            c.chartMethods.Value = num2cell(sort(order(1:min(app.MAX_CURVES, numel(order)))).');
            % 計測配置の比較（初めは推定値と誤差の分布と同じ手法）
            c.compareLayoutMethod.Items = cellstr(labels);
            c.compareLayoutMethod.ItemsData = 1:numel(labels);
            c.compareLayoutMethod.Value = order(1);
            set([c.compareLayoutMethod, c.compareLayoutXAxis, c.compareLayoutErrorBar], 'Enable', 'on');
            set([c.export, c.saveChart, c.copyChart], 'Enable', 'on');
            imported = isImportedResults(results);
            c.importEstimates.Enable = onOff(imported);
            if imported
                % Excel から読み込んだ結果：表・グラフ・比較。推定値の Excel も読み込めば、推定値を使う画面も（その範囲で）
                c.export.Enable = 'off';
                c.resultControls.RowHeight{3} = 'fit';
                sourceText = string(sprintf('Excel から読み込んだ結果：%s（%s に作成）。', results.imported, results.createdAt));
                if isempty(app.ImportedEstimates)
                    c.resultSource.Text = sourceText + "表・グラフ・基準の手法との比較を見られます。" + ...
                        "Wafer マップ・推定値と誤差の分布・散布図・分布の比較は、「推定値の Excel を読み込む…」で" + ...
                        "推定値の Excel も読み込むと使えます（または計測ファイルを読み込んで「3. 実行」で評価し直す）。";
                    c.mapInfo.Text = "Excel から読み込んだ結果で Wafer ごとの図を描くには、「4. 結果一覧」の" + ...
                        "「推定値の Excel を読み込む…」で推定値の Excel も読み込んでください。";
                    refreshResults(app);
                    return
                end
                estimates = app.ImportedEstimates.estimates;
                c.resultSource.Text = sourceText + sprintf(['推定値：%s（手法 %d・学習パターンの列 %d・Wafer %d 枚）。' ...
                    'Wafer マップ・推定値と誤差の分布・散布図・分布の比較は、この推定値の範囲で描けます（Shot の枠・' ...
                    '推定値の書き出しは使えません）。'], app.ImportedEstimates.file, numel(unique(estimates.methodId)), ...
                    numel(unique(estimates.group)), numel(unique(estimates.Wafer)));
            else
                c.resultSource.Text = '';
                c.resultControls.RowHeight{3} = 0;
            end
            % マップの選択肢
            setGroupItems(c.mapWafer, alignest.groupOptions(mapUnits(app)));
            planLabels = unique(string({results.plans.label}), 'stable');
            c.mapPlan.Items = cellstr(planLabels);
            c.mapMethod.Items = cellstr(labels);
            c.mapMethod.ItemsData = 1:numel(labels);
            set([c.mapWafer, c.mapPlan, c.mapMethod, c.mapMode, c.mapScale, c.mapMarkerSize, c.mapMarkerShape, c.mapEllipse, ...
                c.mapEllipseOnly, c.mapShotFrames, c.saveMap, c.copyMap, c.mapScanFrames, c.mapRings, c.mapView, c.mapCompareValue, ...
                c.mapConditions, c.mapAddCondition, c.mapRemoveCondition, c.mapClearConditions, c.mapStackBy, ...
                c.mapStackAll], 'Enable', 'on');
            app.MapConditions = app.MapConditions([]);   % 結果が変わると Wafer・手法の番号が変わるので、一覧は空にする
            refreshMapConditions(app);
            c.mapView.Value = 'single';
            c.mapContent.Enable = onOff(isfield(results, "overlayEvaluated") && results.overlayEvaluated && ...
                (~imported || height(app.ImportedEstimates.overlayPoints) > 0));
            set([c.mapShotFrames, c.mapScanFrames], 'Enable', onOff(~imported));   % 読み込んだ推定値には Shot 中心の座標が無い
            if c.mapContent.Enable == "off"
                c.mapContent.Value = 'estimate';
            end
            % 推定値と誤差の分布の選択肢（初めは最も RMSE の小さい手法・最も多い学習 Shot 数）
            c.analysisMethod.Items = cellstr(labels);
            c.analysisMethod.ItemsData = num2cell(1:numel(labels));
            c.analysisMethod.Value = {order(1)};
            c.analysisGroup.Items = cellstr(results.groups);
            c.analysisGroup.Value = char(results.groups(end));
            c.analysisWafer.Items = cellstr(["すべての Wafer"; results.unitLabels(:)]);
            c.analysisWafer.ItemsData = 0:numel(results.unitLabels);
            c.analysisWafer.Value = 0;
            set([c.analysisMethod, c.analysisGroup, c.analysisWafer, c.analyze, c.estimateScope, c.exportEstimates], ...
                'Enable', 'on');
            set([c.estimateScope, c.exportEstimates], 'Enable', onOff(~imported));
            % 散布図の選択肢（初めは推定値と誤差の分布と同じ手法・学習パターン）
            c.scatterMethod.Items = cellstr(labels);
            c.scatterMethod.ItemsData = 1:numel(labels);
            c.scatterMethod.Value = order(1);
            c.scatterGroup.Items = c.analysisGroup.Items;
            c.scatterGroup.Value = c.analysisGroup.Value;
            c.scatterWafer.Items = c.analysisWafer.Items;
            c.scatterWafer.ItemsData = c.analysisWafer.ItemsData;
            c.scatterWafer.Value = 0;
            if imported
                [colorKeys, colorLabels] = scatterColorChoices(app.ImportedEstimates.estimates, results.settings);
            else
                [colorKeys, colorLabels] = scatterColorChoices(app.Data, results.settings);
            end
            c.scatterColor.Items = cellstr(colorLabels);
            c.scatterColor.ItemsData = cellstr(colorKeys);
            c.scatterColor.Value = 'none';
            set([c.scatterMethod, c.scatterGroup, c.scatterWafer, c.scatterColor, c.drawScatterButton], 'Enable', 'on');
            % 残差と説明変数の選択肢（初めは散布図と同じ手法・学習パターン）
            c.residualVariableMethod.Items = cellstr(labels);
            c.residualVariableMethod.ItemsData = 1:numel(labels);
            c.residualVariableMethod.Value = order(1);
            c.residualVariableGroup.Items = cellstr(results.groups);
            c.residualVariableGroup.Value = char(results.groups(end));
            c.residualVariableWafer.Items = c.analysisWafer.Items;
            c.residualVariableWafer.ItemsData = c.analysisWafer.ItemsData;
            c.residualVariableWafer.Value = 0;
            set([c.residualVariableMethod, c.residualVariableGroup, c.residualVariableWafer, c.residualVariableName, ...
                c.drawResidualVariableButton], 'Enable', 'on');
            c.distributionMethod.Items = cellstr(labels);
            c.distributionMethod.ItemsData = 1:numel(labels);
            c.distributionMethod.Value = order(1);
            c.distributionGroup.Items = c.analysisGroup.Items;
            c.distributionGroup.Value = c.analysisGroup.Value;
            c.distributionWafer.Items = c.analysisWafer.Items;
            c.distributionWafer.ItemsData = c.analysisWafer.ItemsData;
            c.distributionWafer.Value = 0;
            set([c.distributionMethod, c.distributionGroup, c.distributionWafer, c.distributionAxis, ...
                c.compareDistributionsButton], 'Enable', 'on');
            % 処理時間の内訳（計測データを読み込んで評価した結果だけ。初めは推定値と誤差の分布と同じ手法・最も多い学習 Shot 数）
            c.timingWafer.Items = cellstr(results.unitLabels);
            c.timingWafer.ItemsData = 1:numel(results.unitLabels);
            c.timingWafer.Value = 1;
            c.timingPlan.Items = cellstr(planLabels);
            c.timingPlan.Value = char(planLabels(end));
            c.timingMethods.Items = cellstr(labels);
            c.timingMethods.ItemsData = num2cell(1:numel(labels));
            c.timingMethods.Value = {order(1)};
            set([c.timingWafer, c.timingPlan, c.timingMethods, c.timingRepeats, c.measureTimingButton], ...
                'Enable', onOff(~imported && ~isempty(app.Data)));
            set([c.filterResults.apply, c.filterMap.apply], 'Enable', 'on');
            showFilter(app);
            refreshResults(app);
            drawMap(app);
        end

        function refreshResults(app)
            if isempty(app.Results)
                return
            end
            c = app.Controls;
            metric = string(c.metric.Value);
            summary = alignest.summarizeResults(app.Results, metric, string(c.statistic.Value));
            data = cell(numel(summary.methodLabels), numel(summary.groups) + 1);
            data(:, 1) = cellstr(summary.methodLabels);
            removeStyle(c.summaryTable);
            for g = 1:numel(summary.groups)
                column = summary.values(:, g);
                if summary.lowerIsBetter
                    [~, best] = min(column);
                else
                    [~, best] = max(column);
                end
                for m = 1:numel(column)
                    text = sprintf('%.3f', column(m));
                    if m == best && ~isnan(column(m))
                        text = [text, ' ★']; %#ok<AGROW>
                    end
                    data{m, g + 1} = text;
                end
                if ~all(isnan(column))
                    addStyle(c.summaryTable, uistyle('BackgroundColor', app.Palette.best, 'FontWeight', 'bold'), 'cell', [best, g + 1]);
                end
            end
            c.summaryTable.Data = data;
            c.summaryTable.ColumnName = cellstr(["手法", summary.groups]);
            c.summaryTable.ColumnWidth = [{scaledPixels(app, app.METHOD_COLUMN_WIDTH)}, ...
                repmat({scaledPixels(app, app.VALUE_COLUMN_WIDTH)}, 1, numel(summary.groups))];
            comparison = alignest.pairedComparison(app.Results, string(c.reference.Value), metric);
            unitText = ternary(comparison.Properties.UserData.lowerIsBetter, "%", "");
            rows = cell(height(comparison), 6);
            for k = 1:height(comparison)
                rows{k, 1} = char(comparison.method(k));
                rows{k, 2} = char(comparison.group(k));
                rows{k, 3} = sprintf('%+.2f%s', comparison.difference(k), unitText);
                rows{k, 4} = sprintf('%+.2f 〜 %+.2f', comparison.lower95(k), comparison.upper95(k));
                rows{k, 5} = sprintf('%.0f%%', 100 * comparison.winRate(k));
                rows{k, 6} = sprintf('%d', comparison.nWafers(k));
            end
            c.comparisonTable.Data = rows;
            c.comparisonTable.ColumnName = {'手法', '列', ...
                char("基準との差（" + ternary(unitText == "%", "割合", "差") + "）"), '95% 区間', '基準より良かった割合', 'Wafer 数'};
            c.comparisonTable.ColumnWidth = num2cell(scaledPixels(app, [app.METHOD_COLUMN_WIDTH, 120, 200, 230, 210, 100]));
            c.comparisonNote.Text = sprintf(['基準の手法：%s。同じ Wafer・同じ学習パターンどうしで比べた差の平均（%s）、' ...
                'その 95%% 区間、基準より良かった Wafer の割合。'], comparison.Properties.UserData.referenceLabel, ...
                ternary(unitText == "%", "誤差の差の割合。負なら基準より良い", "差。正なら基準より良い"));
            drawChart(app);
            drawLayoutComparison(app);
        end

        function drawChart(app)
            if isempty(app.Results)
                return
            end
            c = app.Controls;
            if string(c.chartXAxis.Value) == "criteria"
                c.chartAxesGrid.ColumnWidth = {'1x', '1x'};
                drawCriteriaChart(app);
                return
            end
            c.chartAxesGrid.ColumnWidth = {'1x', 0};
            cla(c.chartAxes2, 'reset');
            legend(c.chartAxes2, 'off');
            c.chartAxes2.Visible = 'off';
            ax = c.chartAxes;
            metric = string(c.metric.Value);
            summary = alignest.summarizeResults(app.Results, metric, string(c.statistic.Value));
            selected = cell2mat(c.chartMethods.Value);
            cla(ax, 'reset');
            hold(ax, 'on');
            positions = groupPositions(summary.groups);
            markers = {'o', 's', 'd', '^', 'v', '>', '<', 'p', 'h', 'x'};
            halfWidth = errorBarHalfWidth(app.Results, metric, string(c.chartErrorBars.Value));
            for k = 1:numel(selected)
                m = selected(k);
                style = ['-', markers{mod(k - 1, numel(markers)) + 1}];
                if isempty(halfWidth)
                    plot(ax, positions, summary.values(m, :), style, 'LineWidth', 1.5, 'MarkerSize', 7, ...
                        'DisplayName', summary.methodLabels(m));
                else
                    errorbar(ax, positions, summary.values(m, :), halfWidth(m, :), style, 'LineWidth', 1.5, ...
                        'MarkerSize', 7, 'CapSize', 6, 'DisplayName', summary.methodLabels(m));
                end
            end
            hold(ax, 'off');
            ax.XTick = positions;
            [numbers, axisLabel] = groupNumbers(summary.groups);
            if all(isfinite(numbers))
                ax.XTickLabel = cellstr(string(numbers));
                xlabel(ax, axisLabel);
            else
                ax.XTickLabel = cellstr(summary.groups);
                xlabel(ax, '学習パターン');
            end
            [names, labels] = alignest.metricNames(true, true, resultSpec(app));
            ylabel(ax, labels(names == metric));
            title(ax, "Wafer の" + statisticLabel(string(c.statistic.Value)) + errorBarCaption(string(c.chartErrorBars.Value)));
            grid(ax, 'on');
            if ~isempty(selected)
                legend(ax, 'Location', 'southoutside', 'NumColumns', 1, 'Interpreter', 'none', 'FontSize', 10, 'Box', 'off');
            end
            styleAxes(app, ax, app.AXES_FONT_SIZE);
        end

        function drawCriteriaChart(app)
            % I 基準・D 基準（学習 Shot の組の評価指標）を横軸に、推定誤差の集計値を描く。学習パターンの列ごとに1点。
            c = app.Controls;
            metric = string(c.metric.Value);
            statistic = string(c.statistic.Value);
            summary = alignest.summarizeResults(app.Results, metric, statistic);
            selected = cell2mat(c.chartMethods.Value);
            [names, labels] = alignest.metricNames(true, true, resultSpec(app));
            criteria = ["criterionI", "criterionD"];
            criteriaLabels = ["I 基準 tr(M^{-1})", "D 基準 det(M)^{-1/p}"];
            criteriaNames = ["I 基準", "D 基準"];
            markers = {'o', 's', 'd', '^', 'v', '>', '<', 'p', 'h', 'x'};
            groupNames = string(summary.groups);
            shortNames = extractBefore(groupNames, " Shot");
            shortNames(ismissing(shortNames)) = groupNames(ismissing(shortNames));
            axesList = [c.chartAxes, c.chartAxes2];
            halfWidth = errorBarHalfWidth(app.Results, metric, string(c.chartErrorBars.Value));
            for a = 1:2
                ax = axesList(a);
                cla(ax, 'reset');
                hold(ax, 'on');
                perUnit = alignest.perUnitValues(app.Results, criteria(a));
                for k = 1:numel(selected)
                    m = selected(k);
                    x = cellfun(@(values) mean(values, 'omitnan'), perUnit(m, :));
                    y = summary.values(m, :);
                    valid = find(isfinite(x) & isfinite(y) & x > 0);
                    [xs, order] = sort(x(valid));
                    ys = y(valid(order));
                    style = ['-', markers{mod(k - 1, numel(markers)) + 1}];
                    if isempty(halfWidth)
                        curve = plot(ax, xs, ys, style, 'LineWidth', 1.5, 'MarkerSize', 7, ...
                            'DisplayName', summary.methodLabels(m));
                    else
                        bars = halfWidth(m, valid(order));
                        curve = errorbar(ax, xs, ys, bars, style, 'LineWidth', 1.5, 'MarkerSize', 7, 'CapSize', 6, ...
                            'DisplayName', summary.methodLabels(m));
                    end
                    if k == 1
                        text(ax, xs, ys, "  " + shortNames(valid(order)), 'FontSize', 10, 'Color', curve.Color, ...
                            'VerticalAlignment', 'bottom', 'HandleVisibility', 'off');
                    end
                    if c.chartPoints.Value
                        rows = app.Results.table(app.Results.table.methodIndex == m, :);
                        scatter(ax, rows.(criteria(a)), rows.(metric), 14, curve.Color, 'filled', ...
                            'MarkerFaceAlpha', 0.25, 'HandleVisibility', 'off');
                    end
                end
                hold(ax, 'off');
                ax.XScale = 'log';
                xlabel(ax, criteriaLabels(a) + "（対数目盛、小さいほど良い計画）");
                ylabel(ax, labels(names == metric));
                title(ax, sprintf("%s と推定誤差（Wafer の%s%s）", criteriaNames(a), statisticLabel(statistic), ...
                    errorBarCaption(string(c.chartErrorBars.Value))));
                grid(ax, 'on');
                ax.Visible = 'on';
            end
            if ~isempty(selected)
                legend(c.chartAxes, 'Location', 'southoutside', 'NumColumns', 1, 'Interpreter', 'none', 'FontSize', 10, ...
                    'Box', 'off');
            end
            styleAxes(app, axesList, app.AXES_FONT_SIZE);
        end

        function onExport(app)
            [fileName, folder] = uiputfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, '結果を書き出す', 'alignment_estimation_results.xlsx');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            ok = runWithAlert(app, @() app.exportResultsTo(target), "書き出せませんでした", ...
                "同じ名前のファイルを Excel で開いていれば閉じてから、もう一度試してください。");
            if ok
                uialert(app.Figure, sprintf('書き出しました：%s', target), '書き出しました', 'Icon', 'success');
            end
        end

        function onImportResults(app)
            [fileName, folder] = uigetfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, '結果を読み込む');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.importResultsFrom(fullfile(folder, fileName)), "結果を読み込めませんでした", ...
                "このアプリの「結果を Excel に書き出す」で書き出したファイル（.xlsx）を選んでください。");
        end

        function onImportEstimates(app)
            [fileName, folder] = uigetfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, '推定値の Excel を読み込む');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.importEstimatesFrom(fullfile(folder, fileName)), "推定値を読み込めませんでした", ...
                "このアプリの「推定値を Excel に書き出す…」で、読み込んだ評価結果と同じ評価から書き出したファイルを選んでください。");
        end

        function onSaveChart(app)
            app.Controls.resultTabs.SelectedTab = app.Controls.chartTab;   % 保存するグラフを見せる
            saveFigureWithDialog(app, "chart", 'metric_by_plan.png');
        end

        function selection = analysisSelection(app)
            c = app.Controls;
            unitIndex = c.analysisWafer.Value;
            if unitIndex == 0
                unitIndex = 1:numel(app.Results.unitLabels);
            end
            methodIndex = cell2mat(c.analysisMethod.Value);
            if isempty(methodIndex)
                error('alignest:analysisMethod', '手法を1つ以上選んでください。');
            end
            selection = struct("methodIndex", reshape(methodIndex, 1, []), "groups", string(c.analysisGroup.Value), ...
                "unitIndex", unitIndex);
        end

        function [estimates, messages, overlayPoints] = collectWithProgress(app, selection, cache, maxRows, titleText, ...
                includeTraining)
            % 推定値を集める（画面が出ているときは進み具合を出し、「止める」で中止できる）
            if nargin < 6
                includeTraining = false;
            end
            if isImportedResults(app.Results)
                [estimates, messages, overlayPoints] = importedEstimates(app, selection, includeTraining);
                estimates = filterEstimates(app, estimates);
                return
            end
            dialog = [];
            if app.Figure.Visible == "on"
                dialog = uiprogressdlg(app.Figure, 'Title', titleText, 'Message', '推定値を計算しています…', ...
                    'Cancelable', 'on', 'CancelText', '止める', 'ShowPercentage', 'on');
            end
            cleanup = onCleanup(@() closeDialog(dialog));
            if nargin < 6
                includeTraining = false;
            end
            [estimates, messages, cancelled, overlayPoints] = alignest.collectEstimates(app.Data, app.Results, selection, cache=cache, ...
                maxRows=maxRows, progressFcn=@(done, total) reportCollectProgress(dialog, done, total), ...
                includeTraining=includeTraining);
            if cancelled
                error('alignest:cancelled', '途中で止めました。');
            end
            estimates = filterEstimates(app, estimates);
        end

        function estimates = filterEstimates(app, estimates)
            % 評価点の絞り込み（結果一覧・マップと同じ条件）に合わない評価の行を除く（学習の行はそのまま）
            [~, ~, active] = alignest.pointFilterMask(app.ResultFilter);
            if ~active || height(estimates) == 0
                return
            end
            if isImportedResults(app.Results)
                mask = alignest.pointFilterMask(app.ResultFilter, estimates);
            else
                mask = true(height(estimates), 1);
                [~, unitOfRow] = ismember(estimates.Wafer, app.Results.unitLabels);
                for u = unique(unitOfRow(unitOfRow > 0)).'
                    unitMask = alignest.unitPointFilter(app.Data.units(u), app.ResultFilter);
                    rows = unitOfRow == u;
                    mask(rows) = unitMask(estimates.markIndex(rows));
                end
            end
            estimates = estimates(estimates.role ~= "評価" | mask, :);
        end

        function text = filterNote(app)
            % 説明の文の後ろに付ける、絞り込みの条件（絞り込んでいなければ空）
            [~, description, active] = alignest.pointFilterMask(app.ResultFilter);
            text = "";
            if active
                text = "｜評価点の絞り込み：" + description;
            end
        end

        function showAnalysis(app)
            c = app.Controls;
            estimates = app.Analysis.estimates;
            spec = resultSpec(app);
            % 手法ごとの残差（手法が1つなら従来どおり棒と正規分布の曲線、複数なら輪郭を重ねる）
            [methodNames, ~, methodOfRow] = unique(string(estimates.methodLabel), 'stable');
            c.histogramAxes(1).Visible = 'on';   % Y と同じく毎回表示にする（X の図だけ描き直されないことがないように）
            alignest.plot.residualHistogram(c.histogramAxes(1), splitByGroup(estimates.residualX, methodOfRow), ...
                spec.labels(1) + " の残差", spec.unit, methodNames);
            if spec.scalar
                c.histogramGrid.ColumnWidth = {'1x', 0};   % 1変数は Y 成分が無い
                cla(c.histogramAxes(2), 'reset');
                c.histogramAxes(2).Visible = 'off';
            else
                c.histogramGrid.ColumnWidth = {'1x', '1x'};
                c.histogramAxes(2).Visible = 'on';
                alignest.plot.residualHistogram(c.histogramAxes(2), splitByGroup(estimates.residualY, methodOfRow), ...
                    "Y の残差", "nm", methodNames);
            end
            styleAxes(app, c.histogramAxes, app.AXES_FONT_SIZE);
            normality = app.Analysis.analysis.normality;
            rows = cell(height(normality), 14);
            for k = 1:height(normality)
                r = normality(k, :);
                rows(k, :) = {char(r.methodLabel), char(r.axis), sprintf('%d', r.n), numberText(r.mean, '%.3f'), ...
                    numberText(r.std, '%.3f'), numberText(r.skewness, '%.3f'), numberText(r.excessKurtosis, '%.3f'), ...
                    skippedText(r.swW, r.swNote, '%.4f'), pValueText(r.swP), skippedText(r.adA2, r.adNote, '%.3f'), ...
                    pValueText(r.adP), numberText(r.jb, '%.2f'), pValueText(r.jbP), char(r.judgement)};
            end
            c.normalityTable.Data = rows;
            anova = app.Analysis.analysis.anova;
            rows = cell(height(anova), 10);
            for k = 1:height(anova)
                r = anova(k, :);
                rows(k, :) = {char(r.methodLabel), char(r.axis), char(r.factor), char(r.levelSummary), ...
                    numberText(r.F, '%.2f'), pValueText(r.p), numberText(r.etaSquared, '%.3f'), ...
                    numberText(r.adjustedF, '%.2f'), pValueText(r.adjustedP), char(judgementWithNote(r.judgement, r.note))};
            end
            c.anovaTable.Data = rows;
            results = app.Results;
            selection = app.Analysis.selection;
            scopeText = sprintf("%s｜%s｜Wafer %d 枚", methodScopeText(results, selection), selection.groups, ...
                numel(selection.unitIndex));
            note = "分析した範囲：" + scopeText + filterNote(app) + "。" + c.analysisNote.UserData;
            if height(normality) > 0 && any(~isfinite(normality.swW))
                % Shapiro–Wilk が空欄になる理由（点数は選んだ Wafer の評価点の合計なので、Wafer を絞ると計算できることがある）
                note = note + " Shapiro–Wilk W が「—」の行は、近似が使える 3〜5000 点の範囲外（または値がすべて同じ）" + ...
                    "のため計算していません（W の欄に点数）。そのときは Anderson–Darling の p 値で判定します。" + ...
                    "点数は選んだ Wafer の評価点の合計なので、Wafer を1枚に絞ると計算できることがあります。";
            end
            if ~isempty(app.Analysis.messages)
                note = note + " ⚠ 推定できなかった組み合わせ：" + strjoin(app.Analysis.messages, "／");
            end
            c.analysisNote.Text = note;
        end

        function onDrawResidualVariables(app, onlyWhenDrawn)
            % 「描く」、または説明変数を選び直したとき（もう描いてあれば描き直す）
            if onlyWhenDrawn && app.Controls.residualVariableAxes(1).Visible == "off"
                return
            end
            runWithAlert(app, @() app.drawResidualVariables(), "残差と説明変数の図を描けませんでした", ...
                "手法・学習パターン・Wafer を選び直してから、もう一度「描く」を押してください。");
        end

        function onDrawScatter(app)
            runWithAlert(app, @() app.drawScatter(), "散布図を描けませんでした", ...
                "手法・学習パターン・Wafer を選び直してから、もう一度「描く」を押してください。");
        end

        function categories = scatterCategories(app, estimates, colorBy)
            % 散布図の点ごとの色分けの水準（文字列）
            n = height(estimates);
            switch colorBy
                case "none"
                    categories = strings(n, 1);
                case "wafer"
                    categories = string(estimates.Wafer);
                case "lot"
                    categories = string(estimates.LotID);
                case "eqp"
                    categories = string(estimates.EqpId);
                case "operation"
                    categories = string(estimates.Operation);
                case "scan"
                    categories = "Scan " + string(estimates.direction);
                    categories(isnan(estimates.direction)) = "Scan なし";
                case "mark"
                    categories = "Mark " + string(estimates.markNo);
                case "row"
                    categories = repmat("偶数行", n, 1);
                    categories(estimates.shotRowParity == 1) = "奇数行";
                case "slot"
                    % Wafer ID のハイフンの後の番号（Slot）の奇数・偶数。読めない Wafer は「Slot 不明」
                    [~, parity] = alignest.waferSlot(estimates.Wafer);
                    names = ["Slot 奇数", "Slot 偶数", "Slot 不明"];
                    labels_ = repmat(names(3), n, 1);
                    labels_(parity == "奇数") = names(1);
                    labels_(parity == "偶数") = names(2);
                    categories = categorical(labels_, names);
                    return
                case "outer"
                    % 外周の RMSE と同じ境目（Mark の半径が外周の半径以上なら外周）。凡例は 内側 → 外周 の順
                    outerMm = alignest.upgradeRadiusSettings(app.Results.settings).evaluation.outerRadiusMm;
                    names = [sprintf("内側（半径 %g mm 未満）", outerMm), sprintf("外周（半径 %g mm 以上）", outerMm)];
                    categories = categorical(names(1 + (estimates.r >= outerMm)).', names);
                    return
                case "quadrant"
                    % I 最適の4象限の制約と同じ分け方（偏角で数え、軸の上は反時計回りに次の象限）。Mark の座標で分ける
                    names = ["第1象限（x > 0, y > 0）", "第2象限（x < 0, y > 0）", "第3象限（x < 0, y < 0）", ...
                        "第4象限（x > 0, y < 0）"];
                    angle = mod(atan2(estimates.y, estimates.x), 2 * pi);
                    categories = categorical(names(mod(floor(angle / (pi / 2)), 4) + 1).', names);
                    return
                otherwise
                    column = extractAfter(colorBy, "col:");
                    categories = repmat("（空）", n, 1);
                    if any(string(estimates.Properties.VariableNames) == "質的変数:" + column)
                        categories = string(estimates.("質的変数:" + column));   % 推定値の表にある列（読み込んだ推定値など）
                        categories(categories == "") = "（空）";
                        return
                    end
                    [~, unitOfPoint] = ismember(string(estimates.Wafer), app.Results.unitLabels);
                    for u = unique(unitOfPoint(unitOfPoint > 0)).'
                        unit = app.Data.units(u);
                        position = find(unit.attributeNames == column, 1);
                        if isempty(position)
                            continue
                        end
                        rows = unitOfPoint == u;
                        values = unit.marks.attributes(estimates.markIndex(rows), position);
                        values(values == "") = "（空）";
                        categories(rows) = values;
                    end
            end
            categories(categories == "") = "（空）";
            if colorBy == "none"
                categories(:) = "";
            end
        end

        function onAnalyze(app)
            runWithAlert(app, @() app.analyzeResiduals(), "分析できませんでした", ...
                "手法・学習パターン・Wafer を選び直してから、もう一度「分析する」を押してください。");
        end

        function onExportEstimates(app)
            [fileName, folder] = uiputfile({'*.xlsx', 'Excel ブック (*.xlsx)'}, '推定値を書き出す', ...
                'alignment_estimates.xlsx');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            target = fullfile(folder, fileName);
            ok = runWithAlert(app, @() app.exportEstimatesTo(target), "推定値を書き出せませんでした", ...
                "同じ名前のファイルを Excel で開いていれば閉じてから、または書き出す範囲を絞ってから、もう一度試してください。");
            if ok
                uialert(app.Figure, sprintf('書き出しました：%s', target), '書き出しました', 'Icon', 'success');
            end
        end
    end
end

% ================= このファイルだけで使う小さな関数 =================
function value = round4(value)
% 表に出す数値（有効数字 4 桁）
value = round(value, 4, 'significant');
end

function positions = groupPositions(groups)
% 「20 Shot」のような列は Shot 数、「計測率 20%」は計測率を横軸の位置に、それ以外（手動）は 1, 2, … にする
[numbers, ~] = groupNumbers(groups);
if all(isfinite(numbers))
    positions = numbers;
else
    positions = 1:numel(groups);
end
end

function [numbers, axisLabel] = groupNumbers(groups)
% 学習パターンの列の名前から、横軸の数（Shot 数または計測率 [%]）と軸の名前を読む
groups = string(groups);
if all(startsWith(groups, "計測率 ") & endsWith(groups, "%"))
    numbers = str2double(extractBetween(groups, "計測率 ", "%"));
    axisLabel = "計測率 [%]";
else
    numbers = str2double(extractBefore(groups, " Shot"));
    axisLabel = "学習 Shot 数";
end
numbers = reshape(numbers, 1, []);
end

function [keys, labels] = scatterColorChoices(source, settings)
% 散布図の色分けの選択肢（ファイルのその他の列も加える）。source は読み込んだデータ、または推定値の表
% （読み込んだ推定値の Excel。その他の列は「質的変数:<列名>」の列だけ）。settings は評価の設定（外周の半径）
outerMm = alignest.upgradeRadiusSettings(settings).evaluation.outerRadiusMm;
keys = ["none", "wafer", "lot", "eqp", "operation", "slot", "scan", "mark", "row", "outer", "quadrant"];
labels = ["なし（1色）", "Wafer", "LotID", "EqpId", "Operation", "Slot の偶奇（Wafer ID のハイフンの後の番号）", ...
    "Scan 方向", "Mark 番号", "Shot 行の奇偶", sprintf("外周・内側（Mark の半径 %g mm で分ける）", outerMm), ...
    "象限（Mark の位置、第1〜第4象限）"];
columns = strings(1, 0);
if istable(source)
    names = string(source.Properties.VariableNames);
    columns = extractAfter(names(startsWith(names, "質的変数:")), "質的変数:");
elseif ~isempty(source) && isfield(source, "attributeNames")
    columns = reshape(string(source.attributeNames), 1, []);
end
keys = [keys, "col:" + columns];
labels = [labels, "列：" + columns];
end

function [x, axisLabel, note] = layoutAxisValues(comparison, choice)
% 「計測配置の比較」の横軸の値と名前。計測する Mark の数・効率が無い結果（以前の版・読み込んだ結果）では
% 学習 Shot 数で描き、その旨を note に返す
x = comparison.nShots;
axisLabel = "学習 Shot 数（Wafer の平均）";
note = "";
switch choice
    case "marks"
        if any(isfinite(comparison.nMarks))
            x = comparison.nMarks;
            axisLabel = "計測する Mark の数（Wafer の平均）";
        else
            note = "（この結果には計測する Mark の数が無いので、学習 Shot 数で描きました）";
        end
    case {"efficiencyD", "efficiencyI"}
        if any(isfinite(comparison.(choice)))
            x = 100 * comparison.(choice);
            axisLabel = extractAfter(choice, "efficiency") + " 効率 [%]（全計測に対する。Wafer の平均）";
        else
            note = "（この結果には効率が無いので、学習 Shot 数で描きました）";
        end
end
end

function text = methodScopeText(results, selection)
% 分析した手法の説明：1つなら名前、複数なら数（名前は表の「手法」の列にある。説明の文が長くならないように）
labels = string({results.methods(selection.methodIndex).label});
if isscalar(labels)
    text = labels;
else
    text = sprintf("手法 %d 個（名前は表・凡例）", numel(labels));
end
end

function parts = splitByGroup(values, groupIndex)
% 値を組の番号ごとの cell に分ける（組の番号は 1 から）
parts = arrayfun(@(k) values(groupIndex == k), 1:max(groupIndex), 'UniformOutput', false);
end

function text = skippedText(value, reason, format)
% 検定の値。計算しなかったときは「— 理由」（例：「— 6000 点（5000 点超）」）
if isfinite(value) || string(reason) == ""
    text = numberText(value, format);
else
    text = char("— " + string(reason));
end
end

function text = judgementWithNote(judgement, note)
% 判定とメモを1つの欄にまとめる（判定できないときはメモだけ）
if judgement == "—" && note ~= ""
    text = note;
elseif note ~= ""
    text = judgement + "（" + note + "）";
else
    text = judgement;
end
end

function halfWidth = errorBarHalfWidth(results, metric, kind)
% エラーバーの片側の長さ（手法 × 学習パターンの列）。なしなら空
halfWidth = [];
if kind == "none"
    return
end
[deviation, count] = alignest.waferSpread(results, metric);
halfWidth = deviation;
if kind == "ci"
    halfWidth = 1.96 * deviation ./ sqrt(count);
end
end

function text = errorBarCaption(kind)
switch kind
    case "sd"
        text = "、エラーバーは ±1σ（Wafer 間）";
    case "ci"
        text = "、エラーバーは平均の 95% 区間";
    otherwise
        text = "";
end
end

function text = statisticLabel(statistic)
[names, labels] = alignest.statisticNames();
text = labels(names == statistic);
end

function continueRun = reportCollectProgress(dialog, done, total)
continueRun = true;
if isempty(dialog) || ~isvalid(dialog)
    return
end
dialog.Value = done / total;
dialog.Message = sprintf('%d / %d 組み合わせ（Wafer × 学習パターン × 手法）', done, total);
drawnow limitrate;
continueRun = ~dialog.CancelRequested;
end

function filter = readFilterControls(controls)
% 評価点の絞り込みの欄（buildFilterControls）から条件を作る
filter = alignest.defaultPointFilter();
filter.radiusMinMm = controls.radiusMin.Value;
filter.radiusMaxMm = controls.radiusMax.Value;
filter.shotMode = string(controls.shotMode.Value);
[values, ok] = parseNumbers(controls.shotNos.Value);
if ~ok || any(values ~= round(values))
    error('alignest:pointFilter', 'shotNo は整数を空白またはカンマで区切って入れてください。');
end
filter.shotNos = reshape(unique(values), 1, []);
filter.scan = controls.scan.Value;
filter.outer = string(controls.outer.Value);
end

function validateFilter(filter)
% 絞り込みの条件を確かめる（範囲が逆・shotNo が空など）
if ~(filter.radiusMinMm >= 0) || ~(filter.radiusMaxMm > filter.radiusMinMm)
    error('alignest:pointFilter', '半径は 0 以上で、下限 < 上限 にしてください（上限なしは Inf）。');
end
if filter.shotMode ~= "all" && isempty(filter.shotNos)
    error('alignest:pointFilter', 'shotNo で絞り込むときは、右の欄に shotNo を入れてください。');
end
end
