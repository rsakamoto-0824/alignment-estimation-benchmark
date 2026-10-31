classdef TestShotHighOrderZones < matlab.unittest.TestCase
    %TESTSHOTHIGHORDERZONES Shot 高次補正（「7. Shot高次補正」）の追加の評価：外周の Shot だけ別の式（半径で分ける）と内周・
    %   外周に分けた評価、Wafer 成分（最大5次）を先に引いてから Shot ごとに補正、2つの条件の Shot ごとの比較（ロバスト回帰が
    %   最小二乗よりよかった Shot）、残差の成分分解（Wafer 線形・Shot 共通・Shot・残り）、ヒストグラムを重ねる区間、画面の流れ
    %   （外周の式の選択・内周外周の表・2つの条件を並べる・ヒストグラム・成分分解・書き出し・設定ファイル）を確かめる。

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
        function outerShotsUseTheirOwnFormula(testCase)
            % 外周（Shot 中心の半径 100 mm 以上）の Shot だけに x^2·y（k15。ASML の式にあり Nikon の dx の式に無い項）を足した
            % 合成の Wafer：外周を ASML の式に分けると、内周は Nikon、外周は ASML の k を取り戻す。分けないと外周に残る
            truth = struct("dx", [1, 0.5; 3, 0.02; 5, -0.01; 7, 0.001; 9, 0.0005; 13, 1e-5], ...
                "dy", [2, -0.3; 4, 0.01; 6, 0.015; 8, -0.0008; 10, 0.0004]);
            points = waferFrom(testCase, truth);
            outer = hypot(points.Xc, points.Yc) >= 100;
            points.valueX(outer) = points.valueX(outer) + 0.002 * points.localX(outer) .^ 2 .* points.localY(outer);
            settings = alignest.defaultSettings();
            settings.highOrder = struct("maker", "nikon", "unit", "common", "waferOrder", 1, "loss", "ols", "l2", false, ...
                "outerRadiusMm", 100, "outerMaker", "asml");
            wafer = struct("label", "W1", "points", points);
            result = alignest.shotHighOrder(wafer, settings);
            testCase.verifyLessThan(max(abs([result.points.residualX; result.points.residualY])), 1e-8);
            testCase.verifyEqual(result.points.zone == "外周", outer, "Shot 中心の半径で内周・外周に分ける");
            testCase.verifyEqual(unique(result.terms.zone).', ["内周", "外周"]);
            coefficients = result.coefficients(result.coefficients.component == "Shot 高次補正", :);
            k15 = coefficients(coefficients.k == 15, :);
            testCase.verifyEqual(k15.group, "外周", "k15 は外周の式（ASML）にだけある");
            testCase.verifyEqual(k15.value, 0.002, 'AbsTol', 1e-9);
            inner = coefficients(coefficients.group == "内周" & coefficients.axis == "dx", :);
            [~, row] = ismember(truth.dx(:, 1), inner.k);
            testCase.verifyEqual(inner.value(row), truth.dx(:, 2), 'AbsTol', 1e-9);
            testCase.verifyEqual(unique(coefficients.zone(coefficients.group == "外周")), "外周");
            testCase.verifyTrue(contains(result.description, "外周（Shot 中心の半径 100 mm 以上）は ASML の式"));
            testCase.verifyTrue(any(contains(result.messages, "外周の Shot（Shot 中心の半径 100 mm 以上）")));
            testCase.verifyEqual(numel(result.reduction), 4, "内周・外周 × dx・dy");
            testCase.verifyEqual(string({result.reduction.zone}), ["内周", "内周", "外周", "外周"]);
            % 内周・外周に分けた評価（点の数・k の組の数）
            regions = result.regionSummary(result.regionSummary.wafer == "W1" & result.regionSummary.axis == "X", :);
            testCase.verifyEqual(regions.region.', ["内周", "外周"]);
            testCase.verifyEqual(regions.n.', [nnz(~outer), nnz(outer)]);
            testCase.verifyEqual(regions.kSets.', [1, 1], "外周の式を分けると、組は内周・外周に分かれる");
            testCase.verifyEqual(result.summary.region, repmat("すべて", 4, 1));
            % 分けないと、外周の Shot に k15 の形が残る（組が内周と外周にまたがるので、範囲の行の組の数は数えない）
            settings.highOrder.outerMaker = "none";
            shared = alignest.shotHighOrder(wafer, settings);
            testCase.verifyGreaterThan(max(abs(shared.points.residualX(outer))), 1e-3);
            sharedRegions = shared.regionSummary(shared.regionSummary.wafer == "W1", :);
            testCase.verifyTrue(all(isnan(sharedRegions.kSets)));
            outerRow = sharedRegions(sharedRegions.region == "外周" & sharedRegions.axis == "X", :);
            testCase.verifyGreaterThan(outerRow.highOrder, regions.highOrder(2));
            % Shot ごと：外周の Shot は外周の式の k を持つ
            settings.highOrder.outerMaker = "asml";
            settings.highOrder.unit = "shot";
            perShot = alignest.shotHighOrder(wafer, settings);
            withK15 = unique(perShot.coefficients.shotNo(perShot.coefficients.k == 15));
            testCase.verifyEqual(withK15, unique(points.shotNo(outer)));
            testCase.verifyLessThan(max(abs(perShot.points.residualX)), 1e-8);
            % 設定の誤り
            bad = {"outerRadiusMm", 0, 'alignest:highOrderOuter'; "outerMaker", "x", 'alignest:highOrderModel'; ...
                "outerExcludedTerms", 0.5, 'alignest:highOrderTerms'; "waferOrder", 6, 'alignest:highOrderWafer'};
            for k = 1:size(bad, 1)
                broken = alignest.defaultSettings();
                broken.highOrder.(bad{k, 1}) = bad{k, 2};
                testCase.verifyError(@() alignest.highOrderOptions(broken), bad{k, 3});
            end
        end

        function waferComponentIsRemovedBeforePerShot(testCase)
            % Shot ごと + Wafer 成分：Wafer 成分を先に引くので、補正量・残差は Wafer 成分なしと同じで、Shot ごとの k1 が
            % Wafer 成分（dx に 0.01 × Xc）を除いた値になる。Wafer 成分は5次まで選べる
            truth = struct("dx", [1, 0.5; 3, 0.02; 5, -0.01; 9, 0.0005], "dy", [2, -0.3; 4, 0.01; 6, 0.015]);
            points = waferFrom(testCase, truth);
            points.valueX = points.valueX + 0.01 * points.Xc;
            settings = alignest.defaultSettings();
            settings.highOrder = struct("maker", "nikon", "unit", "shot", "waferOrder", 0, "loss", "ols", "l2", false);
            wafer = struct("label", "W1", "points", points);
            without = alignest.shotHighOrder(wafer, settings);
            settings.highOrder.waferOrder = 1;
            with = alignest.shotHighOrder(wafer, settings);
            testCase.verifyEqual(with.points.residualX, without.points.residualX, 'AbsTol', 1e-9);
            testCase.verifyEqual(with.points.correctionY, without.points.correctionY, 'AbsTol', 1e-9);
            waferTerms = with.coefficients(with.coefficients.component == "Wafer 成分", :);
            testCase.verifyEqual(waferTerms.value(waferTerms.axis == "dx" & waferTerms.term == "Xc"), 0.01, 'AbsTol', 1e-9);
            k1With = with.coefficients.value(with.coefficients.k == 1);
            k1Without = without.coefficients.value(without.coefficients.k == 1);
            testCase.verifyLessThan(std(k1With), 1e-8, "Wafer 成分を除いた k1 は Shot によらない");
            testCase.verifyGreaterThan(std(k1Without), 0.1);
            testCase.verifyTrue(contains(with.description, "Wafer 成分 1 次を先に求めて引く"));
            testCase.verifyTrue(any(contains(with.messages, "補正量・残差は Wafer 成分なしと同じ")));
            % 求めた式（Shot ごとの k と Wafer 成分）で、点の補正量を再現できる（Shot の形のグリッドと同じ求め方）
            shotRows = with.points(with.points.shotNo == 3, :);
            shots = table(3, shotRows.x(1) - shotRows.localX(1), shotRows.y(1) - shotRows.localY(1), shotRows.group(1), ...
                'VariableNames', ["shotNo", "Xc", "Yc", "group"]);
            [dx, ~] = alignest.highOrderModelAt(with.coefficients, "shot", "W1", shots, ...
                [shotRows.localX, shotRows.localY]);
            testCase.verifyEqual(dx(:), shotRows.correctionX, 'AbsTol', 1e-9);
            settings.highOrder.waferOrder = 5;
            fifth = alignest.shotHighOrder(wafer, settings);
            testCase.verifyEqual(nnz(fifth.coefficients.component == "Wafer 成分" & fifth.coefficients.axis == "dx"), 20, ...
                "5次：定数を除く 2 + 3 + 4 + 5 + 6 項");
            testCase.verifyEqual(fifth.points.residualX, without.points.residualX, 'AbsTol', 1e-8);
            settings.highOrder.unit = "common";
            common = alignest.shotHighOrder(wafer, settings);
            testCase.verifyTrue(contains(common.description, "Wafer 成分 5 次も一緒に求める"));
        end

        function robustWinsAreFoundShotByShot(testCase)
            % 外れ値（1点 +20 nm）を入れた Shot では、|残差| の中央値で比べるとロバスト回帰（Huber）が最小二乗より改善し、
            % その Shot には重みを下げた点がある。RMS で比べると、外れ値の点の残差が効いて最小二乗の方がよい
            truth = struct("dx", [1, 0.5; 3, 0.02; 5, -0.01], "dy", [2, -0.3; 4, 0.01; 6, 0.015]);
            points = waferFrom(testCase, truth);
            rng(5);
            points.valueX = points.valueX + 0.1 * randn(height(points), 1);
            points.valueY = points.valueY + 0.1 * randn(height(points), 1);
            outlierShots = 1:5;
            for shot = outlierShots
                row = find(points.shotNo == shot, 1) + 3;
                points.valueX(row) = points.valueX(row) + 20;
            end
            settings = alignest.defaultSettings();
            settings.highOrder = struct("maker", "nikon", "unit", "shot", "waferOrder", 0, "loss", "ols", "l2", false);
            wafer = struct("label", "W1", "points", points);
            ols = alignest.shotHighOrder(wafer, settings);
            settings.highOrder.loss = "huber";
            huber = alignest.shotHighOrder(wafer, settings);
            shots = alignest.compareHighOrderShots(ols.points, huber.points, axis="X", statistic="median", ...
                toleranceNm=0.01);
            testCase.verifyEqual(height(shots), size(testCase.Grid.centers, 1));
            testCase.verifyEqual(shots.difference, shots.reference - shots.other);
            mine = shots(ismember(shots.shotNo, outlierShots), :);
            testCase.verifyEqual(mine.verdict, repmat("改善", numel(outlierShots), 1));
            testCase.verifyTrue(all(mine.downweightedOther > 0) && all(mine.downweightedReference == 0));
            testCase.verifyEqual(unique(shots.zone).', ["内周", "外周"]);
            byRms = alignest.compareHighOrderShots(ols.points, huber.points, axis="X", statistic="rms", toleranceNm=0.01);
            testCase.verifyEqual(byRms.verdict(ismember(byRms.shotNo, outlierShots)), ...
                repmat("悪化", numel(outlierShots), 1), "RMS は外れ値の点も効くので最小二乗が小さい");
            both = alignest.compareHighOrderShots(ols.points, huber.points);
            testCase.verifyEqual(both.nCompared, repmat(77, height(both), 1), "X・Y の両方を補正した点");
            testCase.verifyError(@() alignest.compareHighOrderShots(ols.points(1:end - 1, :), huber.points), ...
                'alignest:highOrderShots');
            % 補正の比較の条件ごとの結果も返す（2つの条件を並べるときに使う）
            conditions = struct("label", {"最小二乗", "Huber"}, "highOrder", {struct("loss", "ols"), ...
                struct("loss", "huber")});
            [comparison, results] = alignest.compareHighOrderConditions(wafer, settings, conditions);
            testCase.verifyEqual(numel(results), 2);
            testCase.verifyEqual(results{2}.points.residualX, huber.points.residualX, 'AbsTol', 1e-12);
            testCase.verifyTrue(all(isfinite(comparison.highOrderInner) & isfinite(comparison.highOrderOuter)));
        end

        function residualDecompositionAddsUp(testCase)
            % 残差 = Wafer 線形（0.5 + 0.004·Xc）+ Shot 共通（0.003·x·y）+ Shot ごとの並進 + 雑音：成分と項の分を取り戻し、
            % 成分を足すと残差、二乗和の割合を足すと 100%
            points = waferFrom(testCase, struct("dx", zeros(0, 2), "dy", zeros(0, 2)));
            points.wafer = repmat("W1", height(points), 1);
            Xc = points.Xc;
            clean = 0.5 + 0.004 * Xc + 0.003 * points.localX .* points.localY;
            points.residualX = clean;
            points.residualY = 0.002 * points.localY;
            decomposition = alignest.decomposeHighOrderResidual(points);
            terms = decomposition.terms(decomposition.terms.wafer == "W1" & decomposition.terms.axis == "X", :);
            coefficient = @(level, k) terms.coefficient(terms.level == level & terms.k == k);
            testCase.verifyEqual(coefficient("Wafer 線形", 1), 0.5, 'AbsTol', 1e-9);
            testCase.verifyEqual(coefficient("Wafer 線形", 3), 0.004, 'AbsTol', 1e-12);
            testCase.verifyEqual(coefficient("Shot 共通", 9), 0.003, 'AbsTol', 1e-12);
            levels = decomposition.levels(decomposition.levels.wafer == "W1" & decomposition.levels.axis == "X", :);
            testCase.verifyEqual(levels.level.', ["Wafer 線形", "Shot 共通", "Shot", "残り"]);
            testCase.verifyEqual(sum(levels.share), 100, 'AbsTol', 1e-9);
            testCase.verifyLessThan(levels.share(3) + levels.share(4), 1e-9);
            yTerms = decomposition.terms(decomposition.terms.wafer == "W1" & decomposition.terms.axis == "Y" & ...
                decomposition.terms.level == "Shot 共通", :);
            testCase.verifyEqual(yTerms.share(yTerms.k == 4), 100, 'AbsTol', 1e-9, "dy の k4（y）");
            % Shot ごとの並進と雑音：Shot 成分は k1、残りは雑音
            rng(3);
            shift = randn(max(points.shotNo), 1);
            points.residualX = clean + shift(points.shotNo) + 0.05 * randn(height(points), 1);
            noisy = alignest.decomposeHighOrderResidual(points);
            components = noisy.components;
            total = components.waferLinear + components.common + components.shot + components.rest;
            testCase.verifyEqual(total(:, 1), points.residualX, 'AbsTol', 1e-9);
            shotTerms = noisy.terms(noisy.terms.axis == "X" & noisy.terms.level == "Shot" & noisy.terms.wafer == "W1", :);
            testCase.verifyEqual(shotTerms.k.', [1, 3, 5], "Shot 成分の項は k1〜k6（dx は k1・k3・k5）");
            [~, largest] = max(shotTerms.share);
            testCase.verifyEqual(shotTerms.k(largest), 1);
            noisyLevels = noisy.levels(noisy.levels.wafer == "W1" & noisy.levels.axis == "X", :);
            testCase.verifyEqual(noisyLevels.rms(4), 0.05, 'RelTol', 0.15, "残りは雑音の大きさ");
            testCase.verifyTrue(startsWith(shotTerms.largest(largest), "Shot "));
            % 「すべての Wafer」は Wafer ごとの二乗和の合計
            two = [points; points];
            two.wafer(height(points) + 1:end) = "W2";
            pair = alignest.decomposeHighOrderResidual(two);
            all_ = pair.levels(pair.levels.wafer == "すべての Wafer" & pair.levels.axis == "X", :);
            testCase.verifyEqual(all_.ss, 2 * noisyLevels.ss, 'RelTol', 1e-9);
            % Shot 成分の項は Shot の点の数より少なくする（4点の Shot では 3項まで。残りが残る）
            four = points(ismember(points.localX, [-12, 12]) & ismember(points.localY, [-15, 15]), :);
            limited = alignest.decomposeHighOrderResidual(four, shotTerms="same");
            used = limited.terms(limited.terms.wafer == "W1" & limited.terms.level == "Shot" & ...
                limited.terms.axis == "X" & limited.terms.nUnits > 0, :);
            testCase.verifyLessThanOrEqual(height(used), 3);
            fourLevels = limited.levels(limited.levels.wafer == "W1" & limited.levels.axis == "X", :);
            testCase.verifyGreaterThan(fourLevels.share(4), 0);
        end

        function overlaidHistogramsKeepTheNarrowShape(testCase)
            % 広がりの違う値を重ねるとき、区間の幅を最も狭い分布に合わせる（狭い分布の形がつぶれない）。横軸の名前・題名
            figureHandle = figure('Visible', 'off');
            closeFigure = onCleanup(@() close(figureHandle));
            ax = axes(figureHandle);
            rng(2);
            wide = 8 * randn(2000, 1);
            narrow = 0.5 * randn(2000, 1);
            alignest.plot.residualHistogram(ax, {wide, narrow}, "X", "nm", ["補正前の値", "残差"], ...
                xLabelText="値 [nm]", seriesWord="値", finestBins=true);
            series = findobj(ax, 'Type', 'histogram');
            fineWidth = series(1).BinWidth;
            [~, edges] = histcounts(narrow);
            together = [wide; narrow];
            maxBins = 400;   % 区間の数の上限（alignest.plot.residualHistogram の MAX_BINS）
            testCase.verifyEqual(fineWidth, max(edges(2) - edges(1), (max(together) - min(together)) / maxBins), ...
                'RelTol', 1e-9, "狭い分布だけで決めた幅（区間が多すぎるときは上限の数の幅）");
            testCase.verifyEqual(string(ax.XLabel.String), "値 [nm]");
            testCase.verifyTrue(contains(string(ax.Title.String), "値 2 個"));
            alignest.plot.residualHistogram(ax, {wide, narrow}, "X", "nm", ["補正前の値", "残差"]);
            coarse = findobj(ax, 'Type', 'histogram');
            testCase.verifyGreaterThan(coarse(1).BinWidth, fineWidth, "既定はすべての値で決めた幅");
            alignest.plot.residualHistogram(ax, {narrow}, "X", "nm", "高次補正の残差", xLabelText="値 [nm]");
            single = findobj(ax, 'Type', 'histogram');
            testCase.verifyEqual(string(single.DisplayName), "高次補正の残差");
        end

        function appShowsZonesPairsHistogramsAndDecomposition(testCase)
            % 画面：外周の式（式の全項・保存した項の組み合わせ）、Wafer 成分5次と Shot ごと、内周・外周に分けた表、くくりの選択、
            % 残差の成分のマップと外周の境界の円、ヒストグラム、残差の成分分解、3つの回帰の条件、2つの条件を並べる（一覧で
            % 2つ選ぶ）、書き出し、設定ファイル
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            app.setHighOrderSource("data");
            testCase.verifyEqual(string(c.highOrderOuterFormula.Items(1:4)), ["分けない", "ASML（全項）", ...
                "Canon（全項）", "Nikon（全項）"]);
            testCase.verifyEqual(c.highOrderWaferOrder.ItemsData{end}, 5);
            app.setHighOrderSettings(unit="shot");
            testCase.verifyEqual(string(c.highOrderWaferOrder.Enable), "on", "Shot ごとでも Wafer 成分を選べる");
            app.setHighOrderSettings(unit="common", outerMaker="asml", outerRadiusMm=120, waferOrder=5);
            result = app.computeHighOrder(0);
            testCase.verifyEqual(result.options.outerMaker, "asml");
            testCase.verifyTrue(any(string({result.reduction.zone}) == "外周"));
            testCase.verifyEqual(height(c.highOrderSummaryTable.Data), 12, "分けなければ Wafer・軸ごと");
            split = app.showHighOrderSummary(true);
            testCase.verifyEqual(height(split), 36, "Wafer（すべてを含む 6）× 軸 × すべて・内周・外周");
            testCase.verifyEqual(string(split.Properties.VariableNames(3)), "範囲");
            testCase.verifyTrue(contains(string(c.highOrderSummaryZoneInfo.Text), "120 mm"));
            testCase.verifyEqual(height(c.highOrderCoefficientTable.Data), 10, "Wafer × 内周・外周");
            testCase.verifyEqual(string(c.highOrderMapGroup.Items), ["すべての点", "内周", "外周"]);
            summary = app.drawHighOrderMap(1, "wafer", "decompShot", "vector", "", "single");
            testCase.verifyGreaterThan(summary.n, 0);
            testCase.verifyNotEmpty(findall(c.highOrderAxes, 'Type', 'line', 'LineStyle', '-.'), "外周の境界の円");
            testCase.verifyTrue(contains(string(c.highOrderMapInfo.Text), "外周の境界"));
            % ヒストグラム：外周の Shot の補正前の値・Shot ごとの1次・高次補正の残差（どちらの補正もできた点）
            histogram_ = app.drawHighOrderHistogram("run", "X", 0, "外周");
            outerPoints = result.points(result.points.zone == "外周", :);
            testCase.verifyEqual(histogram_.n, repmat(nnz(isfinite(outerPoints.residualX + ...
                outerPoints.linearResidualX)), 3, 1));
            testCase.verifyEqual(histogram_.name.', ["補正前の値", "Shot ごとの1次の残差", "高次補正の残差"]);
            one = app.drawHighOrderHistogram("run", "Y", 2, "all", 3);
            testCase.verifyEqual(height(one), 1);
            % 残差の成分分解
            decomposition = app.showHighOrderDecomposition(0, "dx", "custom", "linear");
            testCase.verifyNotEmpty(decomposition);
            testCase.verifyEqual(string(c.highOrderDecompositionTable.Data{1, 1}), "Wafer 線形（計）");
            testCase.verifyNotEmpty(c.highOrderDecompositionAxes.Children);
            formula = app.showHighOrderDecomposition(1, "dy", "formula", "same");
            testCase.verifyNotEmpty(formula.terms);
            % Shot ごと + Wafer 成分（先に引く）
            app.setHighOrderSettings(unit="shot", waferOrder=2, outerMaker="none");
            perShot = app.computeHighOrder(1);
            testCase.verifyTrue(any(contains(perShot.messages, "Wafer 成分（2 次）を先に")));
            testCase.verifyTrue(any(perShot.coefficients.component == "Wafer 成分"));
            testCase.verifyEqual(string(c.highOrderCoefficientTable.Data.Properties.VariableNames(1:2)), ["shotNo", "範囲"]);
            % 保存した項の組み合わせを外周の式にする
            app.setHighOrderSettings(maker="custom", unit="common", waferOrder=1);
            app.useAllHighOrderTerms();
            app.saveHighOrderTermSet("外周用");
            app.setHighOrderSettings(maker="nikon", outerTermSet="外周用");
            testCase.verifyEqual(app.Settings.highOrder.outerMaker, "custom");
            testCase.verifyEqual(app.Settings.highOrder.outerName, "外周用");
            testCase.verifyTrue(any(startsWith(string(c.highOrderOuterFormula.Items), "組み合わせ：外周用")));
            testCase.verifyError(@() app.setHighOrderSettings(outerTermSet="無い名前"), 'alignest:highOrderTermSet');
            % 補正の比較：3つの回帰（外周の式の名前も付く）と、2つの条件を並べる
            app.addHighOrderConditions("loss");
            labels = string({app.HighOrderConditions.label});
            testCase.verifyEqual(numel(labels), 3);
            testCase.verifyTrue(all(contains(labels, "＋外周 「外周用」")));
            testCase.verifyTrue(startsWith(labels(1), "回帰：最小二乗"));
            comparison = app.compareHighOrderConditionsNow(0);
            testCase.verifyTrue(all(isfinite(comparison.highOrderOuter)));
            testCase.verifyTrue(any(string(c.highOrderCompareTable.Data.Properties.VariableNames) == "外周 |平均|+3σ [nm]"));
            shots = app.drawHighOrderPair(1, 2, 1, "xy", "median", 0.1);
            testCase.verifyEqual(height(shots), 495, "5 Wafer × 99 Shot");
            testCase.verifyEqual(height(c.highOrderPairTable.Data), 99, "選んだ Wafer の Shot");
            testCase.verifyTrue(issorted(c.highOrderPairTable.Data{:, 5}, 'descend'), "改善の大きい順");
            testCase.verifyTrue(contains(string(c.highOrderPairInfo.Text), "改善"));
            testCase.verifyNotEmpty(c.highOrderPairAxes2.Children);
            app.drawHighOrderPair(2, 2);
            testCase.verifyTrue(contains(string(c.highOrderPairInfo.Text), "違う条件"));
            c.highOrderConditionList.Value = {3, 2};
            c.highOrderConditionList.ValueChangedFcn(c.highOrderConditionList, []);   % 一覧で選んだときと同じ
            testCase.verifyEqual([c.highOrderPairReference.Value, c.highOrderPairOther.Value], [2, 3], ...
                "一覧で2つ選ぶと、番号の小さい方が基準");
            fromConditions = app.drawHighOrderHistogram("comparison", "X", 0, "all");
            testCase.verifyEqual(height(fromConditions), 3);
            file = [tempname, '.xlsx'];
            app.exportHighOrderTo(file);
            sheets = string(sheetnames(file));
            delete(file);
            testCase.verifyEqual(sheets.', ["説明", "補正の評価", "補正の比較", "Shotごとの比較", "補正値", "項とVIF", ...
                "残差の成分", "残差の成分の項", "点ごとの値"]);
            % 設定ファイル：外周の設定が残り、読むと欄も変わる。組み合わせを消しても外周の式の設定は残す
            settingsFile = [tempname, '.json'];
            alignest.saveSettings(app.Settings, settingsFile);
            loaded = alignest.loadSettings(settingsFile);
            delete(settingsFile);
            testCase.verifyEqual(loaded.highOrder.outerName, "外周用");
            testCase.verifyEqual(loaded.highOrder.outerRadiusMm, 120);
            loaded.highOrder.outerRadiusMm = 110;
            app.setSettings(loaded);
            testCase.verifyEqual(c.highOrderOuterRadius.Value, 110);
            testCase.verifyEqual(c.highOrderOuterFormula.Value, 'set:外周用');
            app.deleteHighOrderTermSet("外周用");
            testCase.verifyTrue(any(contains(string(c.highOrderOuterFormula.Items), "保存から消した")));
            testCase.verifyEqual(app.Settings.highOrder.outerMaker, "custom");
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
