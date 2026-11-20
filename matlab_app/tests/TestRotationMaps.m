classdef TestRotationMaps < matlab.unittest.TestCase
    %TESTROTATIONMAPS 計測マップのローテーション（「9. 計測マップのローテーション」）：Shot・Mark ごとのばらつき（3σ）、しきい値で
    %   分けた優先度とローテーションする計測マップ、FB 側・検証側に分けた補正残差（2. の Overlay 補正・7. の Shot 高次補正）、
    %   画面の流れ（入力・対象・目的変数・条件の比較・書き出しと読み直し）、しきい値の累積 %・外周を優先度 1・ランダムな
    %   振り分け・円の重ね描き、このタブで読み込む Excel・CSV（列を選ぶ）を確かめる。

    properties
        Root
    end

    methods (TestClassSetup)
        function addPath(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.Root);
        end
    end

    methods (Test)
        function variabilityAndMapsFollowTheDefinitions(testCase)
            % 3σ = 3 × Wafer 間の不偏標準偏差。ベクトルは 3√(σX²+σY²)、長さは Wafer ごとの |v| の 3σ。Shot ごとは Mark の
            % 最大・平均。優先度はしきい値以上ほど高く、間隔 n の点は n 枚のマップに順に振り分ける
            values = {[1, 0; 2, 1; 0, 0; 5, 5], [3, 0; 2, 3; 0, 1; 5, 5], [5, 0; 2, 5; 0, 2; 5, 5]};   % 4 点 × 3 Wafer
            target = [10; 20; 30; 40];
            wafers = struct("label", {}, "points", {});
            for w = 1:3
                wafers(w) = struct("label", "W" + w, "points", handPoints(values{w}, target + w));
            end
            v = alignest.markVariability(wafers);
            rows = v.table;
            x = cellfun(@(value) value(:, 1), values, 'UniformOutput', false);
            y = cellfun(@(value) value(:, 2), values, 'UniformOutput', false);
            sx = std([x{:}], 0, 2);
            sy = std([y{:}], 0, 2);
            [~, order] = ismember(rows.key, wafers(1).points.key);
            testCase.verifyEqual(rows.sigma3X, 3 * sx(order), 'AbsTol', 1e-12);
            testCase.verifyEqual(rows.sigma3Vector, 3 * sqrt(sx(order) .^ 2 + sy(order) .^ 2), 'AbsTol', 1e-12);
            lengths = hypot([x{:}], [y{:}]);
            testCase.verifyEqual(rows.sigma3Length, 3 * std(lengths(order, :), 0, 2), 'AbsTol', 1e-12);
            testCase.verifyEqual(rows.sigma3Target, repmat(3, 4, 1), 'AbsTol', 1e-12, "目的変数は Wafer ごとに 1 ずつ違う");
            testCase.verifyEqual(rows.nWafers, repmat(3, 4, 1));
            testCase.verifyTrue(v.hasTarget);
            shots = alignest.markVariability(wafers, level="shot", shotStatistic="max");
            testCase.verifyEqual(height(shots.table), 2);
            perShot = arrayfun(@(s) max(rows.sigma3X(rows.shotNo == s)), shots.table.shotNo);
            testCase.verifyEqual(shots.table.sigma3X, perShot, 'AbsTol', 1e-12);
            means = alignest.markVariability(wafers, level="shot", shotStatistic="mean");
            testCase.verifyEqual(means.table.sigma3X, arrayfun(@(s) mean(rows.sigma3X(rows.shotNo == s)), ...
                means.table.shotNo), 'AbsTol', 1e-12);
            % 優先度と計測マップ：しきい値 4（X の 3σ。6・0・0・0 → 優先度 1 は1点）、間隔 1・3 → 3 枚
            maps = alignest.rotationMaps(v, "sigma3X", 4, [1, 3]);
            testCase.verifyEqual(maps.nMaps, 3);
            testCase.verifyEqual(maps.table.rank.', double(maps.table.sigma3X.' < 4) + 1);
            first = maps.table.rank == 1;
            testCase.verifyTrue(all(maps.membership(first, :), 'all'), "優先度 1 は毎回");
            testCase.verifyEqual(sum(maps.membership(~first, :), 2), ones(nnz(~first), 1), "優先度 2 は 3 枚に1回");
            testCase.verifyEqual(maps.counts, [2, 2, 2]);
            testCase.verifyEqual(maps.averageRate, 0.5);
            testCase.verifyEqual(maps.rankNames(2), "優先度 2（4 未満・3 Lot に1回）");
            % しきい値は大きい順に並べ直す。3σ が分からない点は優先度 1。間隔の数の誤り・多すぎるマップは知らせる
            three = alignest.rotationMaps(v, "sigma3Y", [1, 5], [1, 2, 4]);
            testCase.verifyEqual(three.thresholds, [5, 1]);
            testCase.verifyEqual(three.nMaps, 4);
            v.table.sigma3X(1) = NaN;
            testCase.verifyEqual(alignest.rotationMaps(v, "sigma3X", 100, [1, 2]).table.rank(1), 1);
            testCase.verifyError(@() alignest.rotationMaps(v, "sigma3X", 4, 1), 'alignest:rotationMaps');
            testCase.verifyError(@() alignest.rotationMaps(v, "sigma3X", [4, 3], [1, 5, 7]), 'alignest:rotationMaps', ...
                "35 枚は多すぎる");
            testCase.verifyError(@() alignest.rotationMaps(v, "other", 4, [1, 2]), 'alignest:rotationMaps');
        end

        function mapOptionsChangePrioritiesAndAssignment(testCase)
            % しきい値の累積 %（PERCENTILE.INC と同じ値）・外周の半径以上を優先度 1・ランダムな振り分け（種で決まり、各マップの
            % 数はそろう）
            values = {[1, 0; 2, 1; 0, 0; 5, 5], [3, 0; 2, 3; 0, 1; 5, 5], [5, 0; 2, 5; 0, 2; 5, 5]};   % 4 点 × 3 Wafer
            wafers = struct("label", {}, "points", {});
            for w = 1:3
                wafers(w) = struct("label", "W" + w, "points", handPoints(values{w}, nan(4, 1)));
            end
            v = alignest.markVariability(wafers);   % X の 3σ：6・0・0・0、点の x：−30・−10・10・30 mm
            percent = alignest.rotationMaps(v, "sigma3X", 75, [1, 2], thresholdKind="percent");
            testCase.verifyEqual(percent.thresholds, alignest.stats.percentile(v.table.sigma3X, 75), 'AbsTol', 1e-12);
            testCase.verifyEqual(percent.thresholds, 1.5, 'AbsTol', 1e-12, "0・0・0・6 の累積 75% は 1.5");
            testCase.verifyEqual(percent.thresholdPercents, 75);
            testCase.verifyEqual(percent.table.rank.', [1, 2, 2, 2]);
            testCase.verifyTrue(contains(percent.rankNames(1), "累積 75%"));
            testCase.verifyError(@() alignest.rotationMaps(v, "sigma3X", 100, [1, 2], thresholdKind="percent"), ...
                'alignest:rotationMaps', "累積 % は 0〜100 の間");
            outer = alignest.rotationMaps(v, "sigma3X", 10, [1, 2], outerRadiusMm=25);
            testCase.verifyEqual(outer.table.rank.', [1, 2, 2, 1], "半径 30 mm の点は 3σ によらず優先度 1");
            testCase.verifyEqual(outer.table.outer.', [true, false, false, true]);
            testCase.verifyTrue(contains(outer.rankNames(1), "半径 25 mm 以上"));
            testCase.verifyError(@() alignest.rotationMaps(v, "sigma3X", 10, [1, 2], outerRadiusMm=-1), 'alignest:rotationMaps');
            % ランダムな振り分け：40 点を 4 枚に。同じ種なら同じ、各マップ 10 点、どの点も1回
            big = v;
            big.table = table((1:40).', zeros(40, 1), (1:40).' / 10, 'VariableNames', ["x", "y", "sigma3X"]);
            ordered = alignest.rotationMaps(big, "sigma3X", 100, [1, 4]);
            testCase.verifyEqual(find(ordered.membership(:, 1)).', 1:4:40, "表の順：1・5・9…点目が 1 枚目");
            random1 = alignest.rotationMaps(big, "sigma3X", 100, [1, 4], assignment="random", seed=1);
            random2 = alignest.rotationMaps(big, "sigma3X", 100, [1, 4], assignment="random", seed=1);
            random3 = alignest.rotationMaps(big, "sigma3X", 100, [1, 4], assignment="random", seed=2);
            testCase.verifyEqual(random1.membership, random2.membership, "同じ種なら同じ振り分け");
            testCase.verifyNotEqual(random1.membership, random3.membership);
            testCase.verifyNotEqual(random1.membership, ordered.membership);
            testCase.verifyEqual(random1.counts, [10, 10, 10, 10]);
            testCase.verifyEqual(sum(random1.membership, 2), ones(40, 1));
            testCase.verifyEqual(random1.assignment, "random");
        end

        function excelInputInThisTab(testCase)
            % このタブで Excel・CSV を読み込み（見出しが違う列は表で選ぶ）、「1. データ読込」を使わずにばらつき・計測マップ・
            % 検証ができる。しきい値の累積 %・外周・ランダム・重ねる円を画面から使える
            raw = readtable(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'), 'TextType', 'string');
            raw = renamevars(raw, ["measX", "measY"], ["OVL_X", "OVL_Y"]);   % 見出しから推定できない列
            raw.Thickness = 100 + 0.01 * raw.OVL_X;
            file = [tempname, '.csv'];
            writetable(raw, file);
            cleanupFile = onCleanup(@() delete(file));
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            data = app.loadRotationFile(file);
            testCase.verifyEmpty(data, "必須の列が足りなければ、表で選ぶまで読み込まない");
            testCase.verifyEqual(string(c.rotationOutputs.SelectedTab.Title), "Excel・CSV の列");
            testCase.verifyEqual(string(c.rotationSource.Value), "file");
            testCase.verifyEqual(string(c.rotationComputeVariability.Enable), "off");
            mappingTable = c.rotationMappingTable.Data;
            testCase.verifyEqual(string(mappingTable{string(mappingTable(:, 1)) == "LotID", 4}), "LotID", "見出しから推定");
            data = app.applyRotationMapping(struct("measX", "OVL_X", "measY", "OVL_Y"));
            nUnits = numel(unique(raw.Operation + "|" + raw.EqpId + "|" + raw.LotID + "|" + raw.Wafer + "|" + string(raw.DateTime)));
            testCase.verifyEqual(numel(data.units), nUnits, "計測（Operation × EqpId × LotID × Wafer × DateTime）ごと");
            testCase.verifyEmpty(app.Data, "「1. データ読込」のデータは変えない");
            testCase.verifyEqual(string(c.rotationComputeVariability.Enable), "on");
            testCase.verifyTrue(any(string(c.rotationTarget.Items) == "Thickness"), "選ばなかった数値の列は目的変数");
            testCase.verifyTrue(any(string(c.rotationGroup.Items) == "装置：EXP02"));
            testCase.verifyTrue(contains(string(c.rotationInputInfo.Text), nUnits + " Wafer"));
            variability = app.computeRotationVariability("mark", "max", "Thickness");
            testCase.verifyEqual(variability.nWafers, nUnits);
            testCase.verifyTrue(contains(variability.description, "Excel・CSV"));
            % しきい値の決め方を変えると初期値も変わる（累積 % は 75、3σ の値は累積 75% の値）
            c.rotationThresholdKind.Value = 'percent';
            c.rotationThresholdKind.ValueChangedFcn(c.rotationThresholdKind, []);
            testCase.verifyEqual(string(c.rotationThresholds.Value), "75");
            c.rotationThresholdKind.Value = 'value';
            c.rotationThresholdKind.ValueChangedFcn(c.rotationThresholdKind, []);
            expected = alignest.stats.percentile(variability.table.sigma3Vector, 75);
            testCase.verifyEqual(str2double(c.rotationThresholds.Value), round(expected, 2, 'significant'));
            c.rotationCircles.Value = '120 140';
            maps = app.makeRotationMaps("sigma3Vector", 80, [1, 2], thresholdKind="percent", outerRadiusMm=135, ...
                assignment="random");
            testCase.verifyEqual(maps.thresholdKind, "percent");
            testCase.verifyEqual(maps.outerRadiusMm, 135);
            testCase.verifyEqual(maps.seed, app.Settings.sampling.seed, "メニューの乱数の種");
            testCase.verifyTrue(all(maps.table.rank(hypot(maps.table.x, maps.table.y) >= 135) == 1));
            testCase.verifyNotEmpty(findobj(c.rotationMapAxes(1), 'Type', 'line', 'DisplayName', '半径 120 mm'));
            testCase.verifyNotEmpty(findobj(c.rotationSpreadAxes(1), 'Type', 'line', 'DisplayName', '半径 140 mm'));
            testCase.verifyTrue(contains(string(c.rotationMapInfo.Text), "乱数"));
            result = app.runRotationFeedback(splitKind="count", splitValue=3, compareFull=false);
            testCase.verifyEqual(nnz(result.assignment.role == "検証"), nUnits - 3);
            testCase.verifyTrue(contains(app.RotationHistory(end).description, "累積 80%"));
            testCase.verifyTrue(contains(app.RotationHistory(end).description, "半径 135 mm"));
            % 「1. データ読込」で読み込んでも、Excel・CSV の入力の結果は消さない
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            testCase.verifyNotEmpty(app.RotationMaps);
            testCase.verifyEqual(string(c.rotationSource.Value), "file");
        end

        function radiusViewShowsCumulativeRadius(testCase)
            % 半径と指標の図：横軸に半径、縦軸に指標の 3σ。累積は半径 0 を 0% として外へ指標を足し（全体 = 100%）、
            % 累積率の半径は線の折れ点の間を直線でつないで求める
            cumulative = alignest.radialCumulative([30; 10; 20; 40; NaN], [1; 1; 2; 0; 5], [0, 25, 50, 75, 100, 120]);
            testCase.verifyEqual(cumulative.radiusMm.', [0, 10, 20, 30, 40]);
            testCase.verifyEqual(cumulative.percent.', [0, 25, 75, 100, 100], 'AbsTol', 1e-12);
            testCase.verifyEqual(cumulative.rateRadiiMm, [0, 10, 15, 20, 30, NaN], 'AbsTol', 1e-12);
            testCase.verifyEqual(cumulative.nPoints, 4, "値の無い点は使わない");
            testCase.verifyError(@() alignest.radialCumulative(1:2, 1), 'alignest:radialCumulative');
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            c = app.Controls;
            variability = app.computeRotationVariability("mark", "max", "");
            testCase.verifyEqual(string(c.rotationCumulative.Enable), "off", "はじめは分布の図");
            shown = app.setRotationSpreadView("radius", true, [50, 80]);
            ax = c.rotationSpreadAxes(2);
            testCase.verifyEqual(numel(ax.YAxis), 2, "左に 3σ、右に累積 [%]");
            testCase.verifyEqual(string(ax.XLabel.String), "Wafer 中心からの半径 [mm]");
            radius = hypot(variability.table.x, variability.table.y);
            expected = alignest.radialCumulative(radius, variability.table.sigma3Vector, [50, 80]);
            testCase.verifyEqual(shown.rateRadiiMm, expected.rateRadiiMm, 'AbsTol', 1e-9);
            testCase.verifyTrue(all(shown.rateRadiiMm > 0 & shown.rateRadiiMm < 150));
            testCase.verifyLessThan(shown.rateRadiiMm(1), shown.rateRadiiMm(2));
            yyaxis(ax, 'right');   % 累積率の文字は右の目盛りの側に描いている
            labels = string(get(findobj(ax, 'Type', 'text'), 'String'));
            yyaxis(ax, 'left');
            testCase.verifyTrue(any(startsWith(labels, "累積 50%：")) && any(startsWith(labels, "累積 80%：")));
            testCase.verifyEqual(string(c.rotationCumulativeRates.Enable), "on");
            c.rotationCumulativeRates.Value = 'abc';
            c.rotationCumulativeRates.ValueChangedFcn([], []);
            testCase.verifyTrue(contains(string(c.rotationError.Text), "累積率"), "数でなければ理由を出す");
            testCase.verifyEmpty(app.setRotationSpreadView("radius", false), "累積を重ねない");
            testCase.verifyEqual(string(c.rotationCumulativeRates.Enable), "off");
            app.setRotationSpreadView("histogram");
            testCase.verifyEqual(numel(ax.YAxis), 1, "分布の図に戻す");
            testCase.verifyNotEmpty(findobj(ax, 'Type', 'histogram'));
        end

        function feedbackUsesOlderWafersAndRotatesMaps(testCase)
            % どの Wafer も同じ値なら、計測マップで FB しても（どの点もどこかの Wafer で計測すれば）補正残差は全計測と同じ。
            % 日時の古い Wafer を FB 側にし、Lot ごとにローテーションする。FB 側で一度も計測しない点は補正しない
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            unit = app.Data.units(1);
            base = alignest.rotationPoints(alignest.highOrderUnitPoints(unit), unit.marks.markNo);
            nWafers = 6;
            wafers = struct("label", {}, "points", {}, "lot", {}, "dateTime", {}, "operation", {}, "eqpId", {});
            for w = 1:nWafers
                % 読み込みの順は日時の新しい順（並べ直して古い方を FB 側にすること）
                wafers(w) = struct("label", "W" + w, "points", base, "lot", "L" + ceil((nWafers + 1 - w) / 2), ...
                    "dateTime", sprintf("2026/11/%02d 09:00:00", nWafers + 1 - w), "operation", "", "eqpId", "");
            end
            variability = alignest.markVariability(wafers);
            variability.table.sigma3Vector = (1:height(variability.table)).';   % 優先度を分けるための値
            maps = alignest.rotationMaps(variability, "sigma3Vector", height(variability.table) - 10, [1, 2]);
            full = alignest.feedbackSimulation(wafers, [], settings, splitKind="count", splitValue=4, fullMeasurement=true);
            rotated = alignest.feedbackSimulation(wafers, maps, settings, splitKind="count", splitValue=4, rotationLots=1);
            testCase.verifyEqual(rotated.assignment.wafer(1:4).', ["W6", "W5", "W4", "W3"], "日時の古い順");
            testCase.verifyEqual(rotated.assignment.role.', [repmat("FB", 1, 4), "検証", "検証"]);
            testCase.verifyTrue(rotated.byLot);
            testCase.verifyEqual(rotated.assignment.map(1:4).', [1, 1, 2, 2], "同じ Lot は同じマップ");
            testCase.verifyEqual(rotated.summary.residual, full.summary.residual, 'AbsTol', 1e-9);
            testCase.verifyEqual(rotated.summary.nCorrected, full.summary.nCorrected);
            testCase.verifyLessThan(rotated.measurementRate, 1);
            testCase.verifyEqual(full.measurementRate, 1);
            testCase.verifyEqual(rotated.summary.wafer(end), "すべての検証 Wafer");
            % 2 Lot ごとにローテーションすると、FB 側の 2 Lot はどれもマップ 1：マップ 2 だけの点は補正しない
            slow = alignest.feedbackSimulation(wafers, maps, settings, splitKind="count", splitValue=4, rotationLots=2);
            testCase.verifyEqual(slow.assignment.map(1:4).', [1, 1, 1, 1]);
            testCase.verifyLessThan(slow.summary.nCorrected(1), full.summary.nCorrected(1));
            testCase.verifyTrue(any(contains(slow.messages, "一度も計測していない")));
            % 割合・読み込みの順・7. の Shot 高次補正（同じ値なら FB の補正値は検証側でも同じ残差）
            ratio = alignest.feedbackSimulation(wafers, maps, settings, order="input", splitKind="ratio", splitValue=0.5);
            testCase.verifyEqual(ratio.assignment.wafer(1:3).', ["W1", "W2", "W3"]);
            testCase.verifyEqual(nnz(ratio.assignment.role == "FB"), 3);
            settings.highOrder.maker = "linear";
            high = alignest.feedbackSimulation(wafers, [], settings, splitKind="count", splitValue=4, model="highOrder", ...
                fullMeasurement=true);
            own = alignest.shotHighOrder(struct("label", "W1", "points", base), settings);
            spread = @(values) abs(mean(values(isfinite(values)))) + 3 * std(values(isfinite(values)));
            ownTotal = [spread(own.points.residualX); spread(own.points.residualY)];   % 補正できた点すべてで
            firstVerify = high.summary(high.summary.wafer == high.summary.wafer(1), :);   % 検証側の1枚（X・Y の行）
            testCase.verifyEqual(firstVerify.residual, ownTotal, 'AbsTol', 1e-6, "自分の補正と同じ残差");
            testCase.verifyError(@() alignest.feedbackSimulation(wafers, maps, settings, splitKind="count", splitValue=6), ...
                'alignest:feedbackSimulation', "検証側が 0 枚");
            testCase.verifyError(@() alignest.feedbackSimulation(wafers(1), maps, settings), 'alignest:feedbackSimulation');
        end

        function screenFlowFromInputToExport(testCase)
            % 画面：計測データ（目的変数・対象の装置）→ ばらつき → 計測マップ → 検証（全計測とも）→ 条件の比較 → 書き出し
            % （Excel 取込として読み直せる）。評価の推定値・未知の座標の推定値も入力にできる
            raw = readtable(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'), 'TextType', 'string');
            raw.Thickness = 100 + 0.01 * raw.measX;   % 目的変数にする数値の列
            file = [tempname, '.csv'];
            writetable(raw, file);
            cleanupFile = onCleanup(@() delete(file));
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(file);
            app.applyMapping();
            c = app.Controls;
            app.TabGroup.SelectedTab = app.Tabs.rotation;
            app.TabGroup.SelectionChangedFcn(app.TabGroup, struct("NewValue", app.Tabs.rotation));
            testCase.verifyTrue(any(string(c.rotationTarget.Items) == "Thickness"), "数値の列を目的変数に選べる");
            testCase.verifyTrue(all(ismember(["装置：EXP01", "装置：EXP02", "Operation：OP-M1-ALIGN"], ...
                string(c.rotationGroup.Items))));
            variability = app.computeRotationVariability("mark", "max", "Thickness");
            testCase.verifyTrue(variability.hasTarget);
            testCase.verifyTrue(all(isfinite(variability.table.sigma3Target)));
            testCase.verifyNotEmpty(c.rotationThresholds.Value, "しきい値の初期値");
            testCase.verifyEqual(height(c.rotationSpreadTable.Data), height(variability.table));
            maps = app.makeRotationMaps("sigma3Vector", str2double(c.rotationThresholds.Value), [1, 3]);
            testCase.verifyEqual(maps.nMaps, 3);
            testCase.verifyEqual(numel(c.rotationMapList.Value), 3);
            testCase.verifyNotEmpty(c.rotationMapAxes(1).Children);
            testCase.verifyEqual(height(c.rotationMapTable.Data), 3);
            result = app.runRotationFeedback(splitKind="count", splitValue=3, compareFull=true);
            testCase.verifyEqual([app.RotationHistory.kind], ["全計測", "計測マップ"]);
            testCase.verifyEqual(height(c.rotationRunTable.Data), height(result.summary));
            testCase.verifyEqual(string(c.rotationOutputs.SelectedTab.Title), "FB の検証");
            data = app.compareRotationConditions([]);
            testCase.verifyEqual(data.number.', [1, 2]);
            testCase.verifyEqual(data.rate(1), 100);
            testCase.verifyEqual(numel(findobj(c.rotationCompareAxes(1), 'Type', 'bar')), 2, "X・Y の棒");
            exported = [tempname, '.xlsx'];
            cleanupExport = onCleanup(@() delete(exported));
            app.exportRotationMapsTo(exported, [1, 3]);
            testCase.verifyEqual(sort(string(sheetnames(exported))).', sort(["計測マップ_Mark", "ばらつき", "説明"]));
            layouts = alignest.readLayoutPlans(string(exported));
            testCase.verifyTrue(layouts.markLevel);
            testCase.verifyEqual([layouts.plans.name], ["計測マップ1", "計測マップ3"]);
            % 対象を装置で分ける・Shot ごと
            app.setRotationInput("data", [], "", "eqp:EXP01");
            testCase.verifyEmpty(app.RotationVariability, "入力を変えると前のばらつきは消す");
            byTool = app.computeRotationVariability("shot", "mean", "");
            testCase.verifyEqual(byTool.nWafers, nnz(string({app.Data.units.eqpId}) == "EXP01"));
            testCase.verifyEqual(byTool.level, "shot");
            app.removeRotationConditions(1);
            testCase.verifyEqual([app.RotationHistory.number], 2);
            % 評価の推定値・未知の座標の推定値
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.sampling.nShots = 20;
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(20, 20, 10);
            app.setSettings(settings);
            app.runEvaluationNow(false);
            plan = app.Results.plans(1).label;
            app.setRotationInput("estimate", 1, plan, "all");
            estimated = app.computeRotationVariability("mark", "max", "");
            testCase.verifyEqual(estimated.nWafers, numel(app.Data.units));
            testCase.verifyTrue(contains(estimated.description, "評価の推定値"));
            app.setTargetPoints(alignest.targetGrid(50, 140));
            app.estimateTargets([1, 2], "all", 1);
            app.setRotationInput("target", [], "", "all");
            targets = app.computeRotationVariability("mark", "max", "");
            testCase.verifyEqual(targets.nWafers, 2);
            testCase.verifyTrue(contains(targets.description, "未知の座標"));
        end
    end
end

function points = handPoints(values, target)
% 手で決めた値の点の表：Shot 2 つ × Mark 2 つ（Shot 内の座標 ±10 mm）
shotNo = [1; 1; 2; 2];
localX = [-10; 10; -10; 10];
Xc = [-20; -20; 20; 20];
points = table(repmat("計測値", 4, 1), strings(4, 1), shotNo, Xc, zeros(4, 1), localX, zeros(4, 1), Xc + localX, ...
    zeros(4, 1), values(:, 1), values(:, 2), nan(4, 1), ones(4, 1), 'VariableNames', ["source", "name", "shotNo", ...
    "Xc", "Yc", "localX", "localY", "x", "y", "valueX", "valueY", "direction", "rowParity"]);
points = alignest.rotationPoints(points, [1; 2; 1; 2], target);
end
