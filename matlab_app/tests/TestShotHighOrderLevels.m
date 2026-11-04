classdef TestShotHighOrderLevels < matlab.unittest.TestCase
    %TESTSHOTHIGHORDERLEVELS Shot 高次補正（「7. Shot高次補正」）の、点が足りない Shot の扱い（全体の項を減らす・その Shot だけ
    %   項を減らす・補正しない）、補正の段階（Wafer 高次補正だけ・Wafer 高次補正＋Shot 共通補正の残差と、Wafer 低次・高次・
    %   Shot 共通 低次・高次・Shot 毎 低次・高次の順の書き出し）、外れ値とみなした点、グリッドの刻みと倍率、画面（点が足りない
    %   Shot の欄・外周の式の使う項・Wafer の比較の dx・dy の棒・Shot 重ね合わせの5次・質的変数の交互作用の箱ひげ図）を確かめる。

    properties
        Root
        Grid      % 合成の Wafer の Shot 中心と Shot 内の点
    end

    methods (TestClassSetup)
        function addPath(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.Root);
            centers = zeros(0, 2);
            for cx = -130:26:130
                for cy = -132:33:132
                    if hypot(cx, cy) < 125
                        centers(end + 1, :) = [cx, cy]; %#ok<AGROW>
                    end
                end
            end
            [lx, ly] = meshgrid(linspace(-12, 12, 7), linspace(-15, 15, 11));   % 1 Shot 7 × 11 点
            testCase.Grid = struct("centers", centers, "local", [lx(:), ly(:)]);
        end
    end

    methods (Test)
        function shortageChoosesHowShortShotsAreCorrected(testCase)
            % Shot 1〜3 は四隅の4点だけ（x^2・y^2 の項が決まらない）。全体の項を減らすと、どの Shot も x^2・y^2 を使わない。
            % その Shot だけ減らすと、ほかの Shot はすべての項でちょうど合う。補正しないと Shot 1〜3 は空欄
            truth = struct("dx", [1, 0.5; 3, 0.02; 5, -0.01; 7, 0.001; 9, 0.0005], ...
                "dy", [2, -0.3; 4, 0.01; 6, 0.015; 8, -0.0008]);
            points = waferFrom(testCase, truth);
            short = 1:3;
            corners = abs(points.localX) == 12 & abs(points.localY) == 15;
            points = points(~ismember(points.shotNo, short) | corners, :);
            wafer = struct("label", "W1", "points", points);
            settings = alignest.defaultSettings();
            settings.highOrder = struct("maker", "custom", "excludedTerms", 13:38, "unit", "shot", "waferOrder", 0, ...
                "loss", "ols", "regularization", "none");
            full = ~ismember(points.shotNo, short);
            % 全体の項を減らす（初めの設定）
            reduceAll = alignest.shotHighOrder(wafer, settings);
            testCase.verifyEqual(sort([reduceAll.reduction.dropped]), [7, 8, 11, 12]);
            testCase.verifyGreaterThan(max(abs(reduceAll.points.residualX(full))), 1e-3, "x^2 を使えないので残る");
            testCase.verifyFalse(contains(reduceAll.description, "点が足りない組"), "初めの設定は説明に書かない");
            testCase.verifyEmpty(reduceAll.groupReductions);
            % その Shot だけ項を減らす
            settings.highOrder.shortage = "reduceGroup";
            reduceGroup = alignest.shotHighOrder(wafer, settings);
            testCase.verifyEmpty(reduceGroup.reduction);
            testCase.verifyLessThan(max(abs(reduceGroup.points.residualX(full))), 1e-8, "ほかの Shot はすべての項");
            testCase.verifyTrue(all(isfinite(reduceGroup.points.residualX)), "足りない Shot も補正する");
            testCase.verifyEqual(sortrows(reduceGroup.groupReductions(:, ["shotNo", "axis", "dropped"])), ...
                sortrows(table(repelem(short.', 2), repmat(["dx"; "dy"], 3, 1), repmat(["k7・k11"; "k8・k12"], 3, 1), ...
                'VariableNames', ["shotNo", "axis", "dropped"])));
            testCase.verifyTrue(contains(reduceGroup.description, "点が足りない組：その組だけ項を減らす"));
            testCase.verifyTrue(any(contains(reduceGroup.messages, "その点の配置で決められる項だけ")));
            shots = alignest.highOrderShotTable(reduceGroup);
            testCase.verifyTrue(all(contains(shots.("メモ")(short), "点が足りず項を減らした（dx：k7・k11")));
            testCase.verifyEqual(shots.("合計k7[nm/mm^2]")(short), zeros(3, 1), "使わない項の合計は 0");
            % その Shot は補正しない
            settings.highOrder.shortage = "skip";
            skip = alignest.shotHighOrder(wafer, settings);
            testCase.verifyTrue(all(isnan(skip.points.residualX(~full))));
            testCase.verifyLessThan(max(abs(skip.points.residualX(full))), 1e-8);
            total = skip.summary(skip.summary.wafer == "すべての Wafer", :);
            testCase.verifyEqual(total.skipped, [3; 3]);
            testCase.verifyTrue(any(contains(skip.messages, "「その Shot（組）だけ項を減らす」")));
            settings.highOrder.shortage = "none";
            testCase.verifyError(@() alignest.shotHighOrder(wafer, settings), 'alignest:highOrderShortage');
        end

        function shortageIsToldBeforeComputing(testCase)
            % 計算の前の確かめ：点の数が最も少ない Shot（四隅の4点）で決まらない項と、足りない Shot の数を、当てはめずに返す。
            % 「全体の項を減らす」で計算すると、確かめの項をちょうど外す。点が足りなければ知らせは空
            points = waferFrom(testCase, struct("dx", [1, 0.5; 7, 0.001], "dy", [2, -0.3]));
            corners = abs(points.localX) == 12 & abs(points.localY) == 15;
            points = points(~ismember(points.shotNo, 1:3) | corners, :);
            wafer = struct("label", "W1", "points", points);
            settings = alignest.defaultSettings();
            settings.highOrder = struct("maker", "custom", "excludedTerms", 13:38, "unit", "shot", "waferOrder", 0, ...
                "loss", "ols", "regularization", "none");
            check = alignest.shotHighOrder(wafer, settings, checkOnly=true);
            testCase.verifyEqual(sort(fieldnames(check)).', sort({'options', 'shortage', 'messages'}), "当てはめない");
            dx = check.shortage([check.shortage.axis] == "dx");
            testCase.verifyEqual(dx.dropped, [7, 11]);
            testCase.verifyEqual([dx.nPoints, dx.nUsed, dx.nShort, dx.nGroups, dx.nUnfit], ...
                [4, 6, 3, size(testCase.Grid.centers, 1), 0]);
            testCase.verifyTrue(contains(check.messages(1), "使う 6 項のうち 2 項（k7・k11）が決まりません"));
            testCase.verifyTrue(contains(check.messages(end), "すべての Shot で外して計算します"));
            result = alignest.shotHighOrder(wafer, settings);
            testCase.verifyEqual(result.reduction(1).dropped, dx.dropped, "計算で外す項は確かめと同じ");
            testCase.verifyEqual(result.shortage, check.shortage);
            % 点が足りれば知らせは無い
            full = alignest.shotHighOrder(struct("label", "W1", "points", waferFrom(testCase, ...
                struct("dx", [1, 0.5], "dy", [2, -0.3]))), settings, checkOnly=true);
            testCase.verifyEmpty(full.messages);
        end

        function levelsSplitWaferCommonAndShot(testCase)
            % 値 = Wafer 成分（0.01·Xc + 1e-5·Xc^2）+ Shot 共通（k3 = 0.02・k9 = 0.0005）+ Shot ごとの k9 の差（平均 0）：
            % 段階ごとに取り戻し、Shot 共通 + Shot 毎 がその Shot の k。Wafer 高次補正だけ・Wafer 高次補正＋Shot 共通補正の残差
            truth = struct("dx", [3, 0.02; 9, 0.0005], "dy", zeros(0, 2));
            points = waferFrom(testCase, truth);
            nShots = size(testCase.Grid.centers, 1);
            spread = 1e-4 * ((1:nShots).' - (nShots + 1) / 2) / nShots;   % Shot ごとの k9 の差（平均 0）
            points.valueX = points.valueX + 0.01 * points.Xc + 1e-5 * points.Xc .^ 2 + ...
                spread(points.shotNo) .* points.localX .* points.localY;
            wafer = struct("label", "W1", "points", points);
            settings = alignest.defaultSettings();
            settings.highOrder = struct("maker", "custom", "excludedTerms", 13:38, "unit", "shot", "waferOrder", 2, ...
                "loss", "ols", "regularization", "none");
            result = alignest.shotHighOrder(wafer, settings);
            levels = alignest.highOrderLevels(result);
            testCase.verifyEqual(unique(levels.level, 'stable').', ["Wafer 低次", "Wafer 高次", "Shot 共通 低次", ...
                "Shot 共通 高次", "Shot 毎 低次", "Shot 毎 高次"], "段階の順に並べる");
            dx = levels(levels.axis == "dx", :);
            testCase.verifyEqual(dx.value(dx.level == "Wafer 低次" & dx.term == "Xc"), 0.01, 'AbsTol', 1e-9);
            testCase.verifyEqual(dx.value(dx.level == "Wafer 高次" & dx.term == "Xc^2"), 1e-5, 'AbsTol', 1e-11);
            testCase.verifyEqual(dx.value(dx.level == "Shot 共通 低次" & dx.k == 3), 0.02, 'AbsTol', 1e-9);
            testCase.verifyEqual(dx.value(dx.level == "Shot 共通 高次" & dx.k == 9), 0.0005, 'AbsTol', 1e-10);
            each = dx(dx.level == "Shot 毎 高次" & dx.k == 9, :);
            testCase.verifyEqual(each.value, spread(each.shotNo), 'AbsTol', 1e-10);
            testCase.verifyEqual(dx.value(dx.level == "Shot 毎 低次" & dx.k == 3), zeros(nShots, 1), 'AbsTol', 1e-9);
            % 点ごとの残差：高次補正は 0、Wafer 高次補正＋Shot 共通補正は Shot ごとの差だけ、Wafer 高次補正だけは定数と
            % Xc・Yc の 2次までの多項式（最小二乗）を当てはめた残差
            testCase.verifyLessThan(max(abs(result.points.residualX)), 1e-8);
            testCase.verifyEqual(result.points.commonResidualX, spread(points.shotNo) .* points.localX .* points.localY, ...
                'AbsTol', 1e-8);
            design = [ones(height(points), 1), points.Xc, points.Yc, points.Xc .^ 2, points.Xc .* points.Yc, points.Yc .^ 2];
            expected = points.valueX - design * (design \ points.valueX);
            testCase.verifyEqual(result.points.waferResidualX, expected, 'AbsTol', 1e-8);
            % Wafer 内で共通：Wafer 高次補正＋Shot 共通補正は高次補正そのもの。Shot 毎は無い
            settings.highOrder.unit = "common";
            common = alignest.shotHighOrder(wafer, settings);
            testCase.verifyEqual(common.points.commonResidualX, common.points.residualX);
            testCase.verifyEmpty(common.commonCoefficients);
            testCase.verifyFalse(any(startsWith(alignest.highOrderLevels(common).level, "Shot 毎")));
            % Excel：「補正値」は段階の列、「点ごとの値」は2つの残差の列も書く
            workbook = [tempname, '.xlsx'];
            removeWorkbook = onCleanup(@() delete(workbook));
            alignest.exportHighOrder(workbook, result);
            sheet = readtable(workbook, 'Sheet', '補正値', 'VariableNamingRule', 'preserve', 'TextType', 'string');
            testCase.verifyEqual(sheet.("段階"), levels.level);
            pointSheet = readtable(workbook, 'Sheet', '点ごとの値', 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(pointSheet.("Wafer高次補正+Shot共通補正の残差X[nm]"), result.points.commonResidualX, ...
                'AbsTol', 1e-9);
        end

        function outliersAreStronglyDownweightedPoints(testCase)
            % 外れ値とみなす点は、重みが半分未満の点。雑音だけのデータでは Huber でもごく少なく（|残差| > 2.7 × 尺度）、
            % 外れ値を入れた点は数える
            testCase.verifyEqual(alignest.highOrderOutliers([1; 0.8; 0.5; 0.49; 0.1; NaN]), ...
                logical([0; 0; 0; 1; 1; 0]));
            truth = struct("dx", [1, 0.5; 3, 0.02], "dy", [2, -0.3; 4, 0.01]);
            points = waferFrom(testCase, truth);
            rng(7);
            points.valueX = points.valueX + 0.1 * randn(height(points), 1);
            points.valueY = points.valueY + 0.1 * randn(height(points), 1);
            settings = alignest.defaultSettings();
            settings.highOrder = struct("maker", "nikon", "unit", "common", "waferOrder", 0, "loss", "huber");
            clean = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            total = clean.summary(clean.summary.wafer == "すべての Wafer" & clean.summary.axis == "X", :);
            testCase.verifyLessThan(total.outliers / total.nCorrected, 0.02, "雑音だけなら 2% 未満");
            testCase.verifyGreaterThan(mean(clean.points.weightX < 1), 0.1, "重みが少し下がる点はもっと多い");
            outlierRows = 1:77:5 * 77;
            points.valueX(outlierRows) = points.valueX(outlierRows) + 20;
            dirty = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            testCase.verifyTrue(all(alignest.highOrderOutliers(dirty.points.weightX(outlierRows))));
            settings.highOrder.loss = "ols";
            ols = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            testCase.verifyEqual(ols.summary.outliers, zeros(height(ols.summary), 1), "最小二乗では 0");
        end

        function gridStepAndScaleAreChosen(testCase)
            % グリッドの刻み：Shot の中心から刻みごとの線と端の線。細かすぎる刻みは広げる。倍率は指定どおり
            figureHandle = figure('Visible', 'off');
            closeFigure = onCleanup(@() close(figureHandle));
            ax = axes(figureHandle);
            displacementOf = @(nShots) @(local) deal(repmat(0.01 * local(:, 1).', nShots, 1), ...
                repmat(0.02 * local(:, 2).', nShots, 1));
            summary = alignest.plot.shotGridMap(ax, [0, 0; 26, 0], [26, 33], displacementOf(2), gridStepMm=5, ...
                scaleMmPerNm=2);
            testCase.verifyEqual(summary.gridStepMm, 5);
            testCase.verifyEqual(summary.scaleMmPerNm, 2);
            lines = findobj(ax, 'Type', 'line', 'DisplayName', '変形させたグリッド（2 Shot）');
            % Shot ごとに、線の後ろと Shot の後ろに NaN の区切り。縦：0・±5・±10・±13、横：0・±5・±10・±15・±16.5
            testCase.verifyEqual(nnz(isnan(lines.XData)), 2 * (7 + 9 + 1));
            fine = alignest.plot.shotGridMap(ax, [0, 0], [26, 33], displacementOf(1), gridStepMm=0.001);
            testCase.verifyEqual(fine.gridStepMm, 33 / 100, 'AbsTol', 1e-12, "線が 101 本を超えないように広げる");
            automatic = alignest.plot.shotGridMap(ax, [0, 0], [26, 33], displacementOf(1));
            testCase.verifyEqual(automatic.gridStepMm, 26 / 4, 'AbsTol', 1e-12, "0 なら縦・横 5 本");
        end

        function screenChoosesShortageOuterTermsAndLevels(testCase)
            % 画面：Shot 重ね合わせの5次、交互作用の箱ひげ図、点が足りない Shot の欄、外周の式の使う項（表の範囲の列）、
            % 補正の評価の列の名前、Wafer の比較（dx・dy の残差を並べて5本の棒）、グリッドの刻みと倍率、書き出しの値、設定ファイル
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            testCase.verifyEqual(cell2mat(c.shotOverlayWaferOrder.ItemsData), 0:5);
            c.shotOverlayWaferOrder.Value = 5;
            overlay = app.drawShotOverlay(1, false);
            testCase.verifyEqual(overlay(1).waferOrder, 5);
            % 質的変数の交互作用は箱ひげ図（水準の組ごとの箱）
            pairs = c.interactionPair.ItemsData;
            c.interactionPair.Value = pairs{1};
            c.interactionPair.ValueChangedFcn(c.interactionPair, []);
            testCase.verifyNotEmpty(findall(c.interactionAxes, 'Type', 'boxchart'));
            % 点が足りない Shot の欄
            app.setHighOrderSource("data");
            testCase.verifyEqual(c.highOrderShortage.Value, 'reduceAll');
            % 計算の前に、点の数が最も少ない Shot で決まらない項を知らせる（右上のメッセージ・左の欄・表の赤い太字）
            app.setHighOrderSettings(unit="shot");
            testCase.verifyTrue(startsWith(string(c.highOrderMessage.Value{1}), "⚠ dx：点の数が最も少ない Shot"));
            testCase.verifyTrue(startsWith(string(c.highOrderTermInfo.Text), "⚠ 点の数が最も少ない Shot では決まらない項"));
            testCase.verifyTrue(any(contains(string(c.highOrderMessage.Value), "すべての Shot で外して計算します")));
            testCase.verifyNotEmpty(app.HighOrderCheck.shortage(1).dropped);
            app.setHighOrderSettings(unit="shot", shortage="reduceGroup", outerMaker="asml");
            testCase.verifyEqual(app.Settings.highOrder.shortage, "reduceGroup");
            % 外周の式を分けると、表に内周・外周の項を並べ、外周の項も選べる
            testCase.verifyEqual(c.highOrderTermTable.ColumnName{2}, '範囲');
            zones = string(c.highOrderTermTable.Data(:, 2));
            testCase.verifyEqual(unique(zones, 'stable').', ["内周", "外周"]);
            outerRow = find(zones == "外周" & string(c.highOrderTermTable.Data(:, 4)) == "k9", 1);
            c.highOrderTermTable.CellEditCallback(c.highOrderTermTable, struct("Indices", [outerRow, 1], ...
                "NewData", false));
            testCase.verifyEqual(app.Settings.highOrder.outerExcludedTerms, 9);
            testCase.verifyEqual(app.Settings.highOrder.excludedTerms, zeros(1, 0), "内周の式は変わらない");
            outerLabel = string(c.highOrderOuterFormula.Items(strcmp(c.highOrderOuterFormula.ItemsData, ...
                c.highOrderOuterFormula.Value)));
            testCase.verifyEqual(outerLabel, "ASML（1 項を外す）");
            testCase.verifyTrue(contains(string(c.highOrderTermInfo.Text), "外周 dx 9 / 10"));
            app.useAllHighOrderTerms();
            testCase.verifyEmpty(app.Settings.highOrder.outerExcludedTerms);
            app.setHighOrderSettings(outerMaker="none");
            testCase.verifyEqual(c.highOrderTermTable.ColumnName{2}, '式');
            testCase.verifyError(@() app.setHighOrderTermUsed(9, false, "outer"), 'alignest:highOrderTerms');
            result = app.computeHighOrder(1:2);
            testCase.verifyTrue(contains(result.description, "その組だけ項を減らす"));
            % 補正の評価：残差の列であることを名前に書く
            names = string(c.highOrderSummaryTable.Data.Properties.VariableNames);
            testCase.verifyEqual(names(3:6), ["補正前の値|｜平均｜+3σ [nm]", "Shot ごとの1次の残差|｜平均｜+3σ [nm]", ...
                "高次補正の残差|｜平均｜+3σ [nm]", "改善 [nm]|1次の残差 −|高次補正の残差"], "「|」は見出しの改行");
            testCase.verifyTrue(any(names == "外れ値と|みなした点"));
            % Wafer の比較：dx・dy の残差を左右に並べ、5本の棒
            residuals = app.drawHighOrderWaferComparison("residual");
            testCase.verifyEqual(height(residuals), 4, "2 Wafer × dx・dy");
            testCase.verifyEqual(numel(findobj(c.highOrderWaferAxes(2), 'Type', 'bar')), 5);
            testCase.verifyEqual(string(c.highOrderWaferAxis.Enable), "off");
            app.drawHighOrderWaferComparison("value", "dx");
            testCase.verifyEqual(string(c.highOrderWaferAxes(2).Visible), "off");
            testCase.verifyEqual(c.highOrderWaferAxesGrid.ColumnWidth, {'1x', 0});
            % グリッドの刻みと倍率（グリッドのときだけ選べる）
            c.highOrderGridStep.Value = 4;
            c.highOrderGridScale.Value = 1.5;
            grid = app.drawHighOrderMap(1, "wafer", "correction", "grid", "", "single");
            testCase.verifyEqual([grid.gridStepMm, grid.scaleMmPerNm], [4, 1.5]);
            testCase.verifyTrue(contains(string(c.highOrderMapInfo.Text), "刻み 4 mm"));
            testCase.verifyEqual(string(c.highOrderGridStep.Enable), "on");
            common = app.drawHighOrderMap(1, "wafer", "common", "vector", "", "single");
            testCase.verifyEqual(common.valueLabel, "Wafer 高次補正＋Shot 共通補正の残差");
            testCase.verifyEqual(string(c.highOrderGridStep.Enable), "off");
            % 書き出し：点ごとの Wafer 高次補正＋Shot 共通補正の残差
            values = app.exportHighOrderValues("points", "common");
            first = result.points(result.points.wafer == result.points.wafer(1), :);
            mine = values(values.Wafer == values.Wafer(1), :);
            testCase.verifyEqual(mine.measX, first.commonResidualX, 'AbsTol', 1e-12);
            % 設定ファイル
            settingsFile = [tempname, '.json'];
            alignest.saveSettings(app.Settings, settingsFile);
            loaded = alignest.loadSettings(settingsFile);
            delete(settingsFile);
            testCase.verifyEqual(loaded.highOrder.shortage, "reduceGroup");
            loaded.highOrder.shortage = "skip";
            app.setSettings(loaded);
            testCase.verifyEqual(c.highOrderShortage.Value, 'skip');
        end
    end
end

function points = waferFrom(testCase, terms)
% 合成の Wafer の点の表（alignest.highOrderUnitPoints の形）：Shot 内の座標の項（[k, 係数] の行。番号はカスタムの式と同じ）の和
centers = testCase.Grid.centers;
local = testCase.Grid.local;
nShots = size(centers, 1);
nMarks = size(local, 1);
Xc = repelem(centers(:, 1), nMarks, 1);
Yc = repelem(centers(:, 2), nMarks, 1);
L = repmat(local, nShots, 1);
custom = alignest.highOrderTerms("custom");
values = zeros(nShots * nMarks, 2);
axisNames = ["dx", "dy"];
for a = 1:2
    for row = 1:size(terms.(axisNames(a)), 1)
        term = custom(custom.k == terms.(axisNames(a))(row, 1), :);
        values(:, a) = values(:, a) + terms.(axisNames(a))(row, 2) * L(:, 1) .^ term.xPower .* L(:, 2) .^ term.yPower;
    end
end
points = table(repmat("計測値", nShots * nMarks, 1), strings(nShots * nMarks, 1), repelem((1:nShots).', nMarks, 1), Xc, ...
    Yc, L(:, 1), L(:, 2), Xc + L(:, 1), Yc + L(:, 2), values(:, 1), values(:, 2), 'VariableNames', ["source", "name", ...
    "shotNo", "Xc", "Yc", "localX", "localY", "x", "y", "valueX", "valueY"]);
end
