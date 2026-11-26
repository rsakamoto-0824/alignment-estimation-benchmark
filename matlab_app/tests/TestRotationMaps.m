classdef TestRotationMaps < matlab.unittest.TestCase
    %TESTROTATIONMAPS 計測マップのローテーション（「8. 計測Mapローテ」）：Shot・Mark ごとのばらつき（3σ）、しきい値で
    %   分けた優先度とローテーションする計測マップ、FB 側・検証側に分けた補正残差（2. の Overlay 補正・6. の Shot 高次補正）、
    %   画面の流れ（入力・対象・目的変数・条件の比較・書き出しと読み直し）、しきい値の累積 %・外周を優先度 1・指定した
    %   Shot を優先度 1（欄と図のクリック）・ランダムな振り分け・円の重ね描き、このタブで読み込む Excel・CSV（列を選ぶ）を
    %   確かめる。

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
            % 優先度と計測マップ：しきい値 4（X の 3σ。6・0・0・0 → 優先度 1 は1点）、計測マップ 3 枚（優先度 1 は毎回、
            % 2 は 3 枚に1回）
            maps = alignest.rotationMaps(v, "sigma3X", 4, 3);
            testCase.verifyEqual(maps.nMaps, 3);
            testCase.verifyEqual(maps.table.rank.', double(maps.table.sigma3X.' < 4) + 1);
            first = maps.table.rank == 1;
            testCase.verifyTrue(all(maps.membership(first, :), 'all'), "優先度 1 は毎回");
            testCase.verifyEqual(sum(maps.membership(~first, :), 2), ones(nnz(~first), 1), "優先度 2 は 3 枚に1回");
            testCase.verifyEqual(maps.counts, [2, 2, 2]);
            testCase.verifyEqual(maps.averageRate, 0.5);
            testCase.verifyEqual(maps.rankNames(2), "優先度 2（4 未満・3 枚に1回）");
            testCase.verifyEqual(maps.intervals, [1, 3]);
            % しきい値は大きい順に並べ直す。3段以上の間の優先度は、マップの数の約数で 1 と枚数の間（等比）に近い頻度
            three = alignest.rotationMaps(v, "sigma3Y", [1, 5], 4);
            testCase.verifyEqual(three.thresholds, [5, 1]);
            testCase.verifyEqual(three.nMaps, 4);
            testCase.verifyEqual(three.intervals, [1, 2, 4]);
            testCase.verifyEqual(alignest.rotationMaps(v, "sigma3Y", [1, 3, 5], 8).intervals, [1, 2, 4, 8]);
            testCase.verifyEqual(alignest.rotationMaps(v, "sigma3Y", [1, 5], 6).intervals, [1, 2, 6]);
            testCase.verifyEqual(alignest.rotationMaps(v, "sigma3Y", [1, 5], 5).intervals, [1, 1, 5], ...
                "約数が 1 と 5 だけなら、近い方の 1");
            one = alignest.rotationMaps(v, "sigma3X", 4, 1);
            testCase.verifyTrue(all(one.membership), "1 枚ならすべて毎回");
            none = alignest.rotationMaps(v, "sigma3X", [], 3);
            testCase.verifyEqual(none.nMaps, 3);
            testCase.verifyTrue(all(none.membership, 'all'), "しきい値が無ければすべて優先度 1（毎回）");
            % 3σ が分からない点は優先度 1。マップの数の誤り（0・小数・2つ以上・多すぎる）は知らせる
            v.table.sigma3X(1) = NaN;
            testCase.verifyEqual(alignest.rotationMaps(v, "sigma3X", 100, 2).table.rank(1), 1);
            testCase.verifyError(@() alignest.rotationMaps(v, "sigma3X", 4, 0), 'alignest:rotationMaps');
            testCase.verifyError(@() alignest.rotationMaps(v, "sigma3X", 4, 2.5), 'alignest:rotationMaps');
            testCase.verifyError(@() alignest.rotationMaps(v, "sigma3X", 4, [1, 3]), 'alignest:rotationMaps');
            testCase.verifyError(@() alignest.rotationMaps(v, "sigma3X", [4, 3], 25), 'alignest:rotationMaps', ...
                "25 枚は多すぎる");
            testCase.verifyError(@() alignest.rotationMaps(v, "other", 4, 2), 'alignest:rotationMaps');
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
            percent = alignest.rotationMaps(v, "sigma3X", 75, 2, thresholdKind="percent");
            testCase.verifyEqual(percent.thresholds, alignest.stats.percentile(v.table.sigma3X, 75), 'AbsTol', 1e-12);
            testCase.verifyEqual(percent.thresholds, 1.5, 'AbsTol', 1e-12, "0・0・0・6 の累積 75% は 1.5");
            testCase.verifyEqual(percent.thresholdPercents, 75);
            testCase.verifyEqual(percent.table.rank.', [1, 2, 2, 2]);
            testCase.verifyTrue(contains(percent.rankNames(1), "累積 75%"));
            testCase.verifyError(@() alignest.rotationMaps(v, "sigma3X", 100, 2, thresholdKind="percent"), ...
                'alignest:rotationMaps', "累積 % は 0〜100 の間");
            outer = alignest.rotationMaps(v, "sigma3X", 10, 2, outerRadiusMm=25);
            testCase.verifyEqual(outer.table.rank.', [1, 2, 2, 1], "半径 30 mm の点は 3σ によらず優先度 1");
            testCase.verifyEqual(outer.table.outer.', [true, false, false, true]);
            testCase.verifyTrue(contains(outer.rankNames(1), "半径 25 mm 以上"));
            testCase.verifyError(@() alignest.rotationMaps(v, "sigma3X", 10, 2, outerRadiusMm=-1), 'alignest:rotationMaps');
            % shotNo の指定：その Shot のすべての Mark を 3σ によらず優先度 1。表に無い shotNo は missingShotNos に返す
            specified = alignest.rotationMaps(v, "sigma3X", 10, 2, priorityShotNos=[2, 9]);
            testCase.verifyEqual(specified.table.rank.', [2, 2, 1, 1], "Shot 2 の Mark（3・4 点目）は優先度 1");
            testCase.verifyEqual(specified.table.specified.', [false, false, true, true]);
            testCase.verifyEqual(specified.priorityShotNos, [2, 9]);
            testCase.verifyEqual(specified.missingShotNos, 9);
            testCase.verifyTrue(contains(specified.rankNames(1), "指定した Shot"));
            testCase.verifyEqual(specified.membership(3:4, :), true(2, 2), "優先度 1 は毎回計測");
            testCase.verifyError(@() alignest.rotationMaps(v, "sigma3X", 10, 2, priorityShotNos=1.5), ...
                'alignest:rotationMaps', "shotNo は整数");
            % ランダムな振り分け：40 点を 4 枚に。同じ種なら同じ、各マップ 10 点、どの点も1回
            big = v;
            big.table = table((1:40).', zeros(40, 1), (1:40).' / 10, 'VariableNames', ["x", "y", "sigma3X"]);
            ordered = alignest.rotationMaps(big, "sigma3X", 100, 4);
            testCase.verifyEqual(find(ordered.membership(:, 1)).', 1:4:40, "表の順：1・5・9…点目が 1 枚目");
            random1 = alignest.rotationMaps(big, "sigma3X", 100, 4, assignment="random", seed=1);
            random2 = alignest.rotationMaps(big, "sigma3X", 100, 4, assignment="random", seed=1);
            random3 = alignest.rotationMaps(big, "sigma3X", 100, 4, assignment="random", seed=2);
            testCase.verifyEqual(random1.membership, random2.membership, "同じ種なら同じ振り分け");
            testCase.verifyNotEqual(random1.membership, random3.membership);
            testCase.verifyNotEqual(random1.membership, ordered.membership);
            testCase.verifyEqual(random1.counts, [10, 10, 10, 10]);
            testCase.verifyEqual(sum(random1.membership, 2), ones(40, 1));
            testCase.verifyEqual(random1.assignment, "random");
            % ポアソンディスク：各マップの数はそろい（差は 1 以内）、どの点も1回、同じ種なら同じ。同じマップの点どうしは
            % ランダムより離れる（最も近い同じマップの点までの距離の平均）
            stream = RandStream('mt19937ar', 'Seed', 3);
            scattered = v;
            scattered.table = table(rand(stream, 201, 1) * 100, rand(stream, 201, 1) * 100, zeros(201, 1), ...
                'VariableNames', ["x", "y", "sigma3X"]);
            poisson1 = alignest.rotationMaps(scattered, "sigma3X", 100, 2, assignment="poisson", seed=1);
            poisson2 = alignest.rotationMaps(scattered, "sigma3X", 100, 2, assignment="poisson", seed=1);
            spreadRandom = alignest.rotationMaps(scattered, "sigma3X", 100, 2, assignment="random", seed=1);
            testCase.verifyEqual(poisson1.membership, poisson2.membership, "同じ種なら同じ振り分け");
            testCase.verifyEqual(sort(poisson1.counts), [100, 101]);
            testCase.verifyEqual(sum(poisson1.membership, 2), ones(201, 1));
            testCase.verifyGreaterThan(meanNearest(scattered.table, poisson1.membership), ...
                1.2 * meanNearest(scattered.table, spreadRandom.membership), "同じマップの点が離れる");
            testCase.verifyError(@() alignest.rotationMaps(big, "sigma3X", 100, 4, priorityShotNos=1), ...
                'alignest:rotationMaps', "shotNo の無い表では指定できない");
        end

        function assignmentMethodsAndComparison(testCase)
            % I 最適・D 最適（ポアソンディスクから始めて、マップごとの基準の和を小さくする）の振り分けと、振り分けの比較の指標（マップ間・全体との KL、最大の空白、I 基準・D 基準）
            stream = RandStream('mt19937ar', 'Seed', 5);
            nPoints = 120;
            radius = 100 * sqrt(rand(stream, nPoints, 1));
            angle = 2 * pi * rand(stream, nPoints, 1);
            v = struct("metrics", "sigma3X", "metricLabels", "X の 3σ", "level", "mark");
            v.table = table(radius .* cos(angle), radius .* sin(angle), rand(stream, nPoints, 1), ...
                'VariableNames', ["x", "y", "sigma3X"]);
            model = {"waferRadiusMm", 100, "designOrder", 2, "designFeatures", "XY"};   % 6 項（1・x・y・x²・xy・y²）
            poisson = alignest.rotationMaps(v, "sigma3X", 0.8, 3, model{:}, assignment="poisson", seed=1);
            low = poisson.table.rank == 2;
            testCase.verifyError(@() alignest.rotationMaps(v, "sigma3X", 0.8, 3, assignment="sobol"), ...
                'MATLAB:validators:mustBeMember', "Sobol 列の振り分けは無い");
            ioptimal = alignest.rotationMaps(v, "sigma3X", 0.8, 3, model{:}, assignment="ioptimal", seed=1);
            doptimal = alignest.rotationMaps(v, "sigma3X", 0.8, 3, model{:}, assignment="doptimal", seed=1);
            metricsP = alignest.rotationMapMetrics(poisson, model{:});
            metricsI = alignest.rotationMapMetrics(ioptimal, model{:});
            metricsD = alignest.rotationMapMetrics(doptimal, model{:});
            testCase.verifyLessThan(sum(metricsI.criterionI), sum(metricsP.criterionI), "I 最適は I 基準の和を小さくする");
            testCase.verifyLessThan(sum(metricsD.criterionD), sum(metricsP.criterionD), "D 最適は D 基準の和を小さくする");
            testCase.verifyEqual(sum(ioptimal.membership, 1), sum(poisson.membership, 1), "入れ替えでマップの数は変わらない");
            testCase.verifyTrue(all(ioptimal.membership(~low, :), 'all'), "優先度 1 は毎回");
            % 指標：同じマップばかり（しきい値なし＝すべて毎回）なら KL・空白は 0、基準は全計測の値（I = 項の数、D = 1）
            same = alignest.rotationMaps(v, "sigma3X", [], 3, model{:});
            metricsSame = alignest.rotationMapMetrics(same, model{:});
            testCase.verifyEqual([metricsSame.klBetween, metricsSame.klWhole, metricsSame.fillDistanceMm], [0, 0, 0], ...
                'AbsTol', 1e-12);
            testCase.verifyEqual(metricsSame.criterionI, repmat(6, 1, 3), 'RelTol', 1e-9);
            testCase.verifyEqual(metricsSame.criterionD, ones(1, 3), 'RelTol', 1e-9);
            testCase.verifyGreaterThan(metricsP.klBetween, 0);
            % 比べる：6 つの振り分けを同じ条件で（同じ種なら、それぞれで作ったマップと同じ指標）
            comparison = alignest.compareRotationAssignments(v, "sigma3X", 0.8, 3, model{:}, seed=1);
            testCase.verifyEqual(comparison.table.("振り分け").', ["I 最適", "D 最適", "ポアソンディスク", "ランダム", "表の順"]);
            testCase.verifyEqual(comparison.table.("I 基準（平均）")(1), metricsI.meanI, 'RelTol', 1e-9);
            testCase.verifyEqual(comparison.table.("マップ間の KL")(3), metricsP.klBetween, 'RelTol', 1e-9);
            testCase.verifyEmpty(comparison.messages);
            % 点が基準モデルの項の数より少ないと I 最適・D 最適は作れない（理由を残し、ほかの振り分けは比べる）
            small = v;
            small.table = table([0; 10; 20; 30], [0; 0; 10; 10], [0.1; 0.2; 0.9; 0.3], 'VariableNames', ["x", "y", "sigma3X"]);
            fewer = alignest.compareRotationAssignments(small, "sigma3X", 0.8, 2, model{:}, seed=1);
            testCase.verifyEqual(numel(fewer.messages), 2);
            testCase.verifyTrue(all(isnan(fewer.table.("マップ間の KL")(1:2))));
            testCase.verifyTrue(all(isfinite(fewer.table.("マップ間の KL")(3:5))));
        end

        function assignmentComparisonOnScreen(testCase)
            % 画面：振り分けの選択肢（I 最適・D 最適・ポアソンディスク・ランダム・表の順）と「振り分けの比較」の
            % タブ（すべての振り分けの指標の表と、選んだ指標の棒。最も良い棒は橙。計測マップのタブのマップは変えない）
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            c = app.Controls;
            app.TabGroup.SelectedTab = app.Tabs.rotation;
            app.TabGroup.SelectionChangedFcn(app.TabGroup, struct("NewValue", app.Tabs.rotation));
            testCase.verifyEqual(string(c.rotationAssignment.ItemsData), alignest.rotationAssignments());
            testCase.verifyEqual(string(c.rotationCompareAssignButton.Enable), "off", "ばらつきを求めるまで押せない");
            app.computeRotationVariability("shot", "max", "");
            testCase.verifyEqual(string(c.rotationCompareAssignButton.Enable), "on");
            maps = app.makeRotationMaps(assignment="doptimal");
            testCase.verifyEqual(maps.assignment, "doptimal");
            testCase.verifyTrue(contains(string(c.rotationMapInfo.Text), "振り分けは D 最適"));
            comparison = app.compareRotationAssignments();
            testCase.verifyEqual(height(c.rotationAssignTable.Data), 5);
            testCase.verifyEqual(c.rotationOutputs.SelectedTab, c.rotationAssignTab);
            testCase.verifyEqual(app.RotationMaps.assignment, "doptimal", "計測マップのタブのマップは変えない");
            bars = findobj(c.rotationAssignAxes, 'Type', 'bar');
            values = comparison.table.("マップ間の KL");
            testCase.verifyEqual(bars.YData(:), values);
            [~, best] = min(values);
            testCase.verifyEqual(bars.CData(best, :), [0.93, 0.49, 0.13], "最も小さい棒は橙");
            c.rotationAssignMetric.Value = 'I 基準（平均）';
            c.rotationAssignMetric.ValueChangedFcn(c.rotationAssignMetric, []);
            bars = findobj(c.rotationAssignAxes, 'Type', 'bar');
            testCase.verifyEqual(bars.YData(:), comparison.table.("I 基準（平均）"));
            app.computeRotationVariability("shot", "max", "");
            testCase.verifyEmpty(c.rotationAssignTable.Data, "ばらつきを求め直すと比較は消す");
        end

        function shotNumbersOverlay(testCase)
            % 「shotNo を重ねる」：取り込んだデータに shotNo の列があれば選べて、「ばらつき」と「計測マップ」の図の Shot に
            % shotNo を重ねる（Shot ごとの図は点と重ならないよう Shot の中で上へずらす）。列が無ければ選べない
            % （shotNo の文字は凡例に出さないので HandleVisibility = off。findall で探す）
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            c = app.Controls;
            app.TabGroup.SelectedTab = app.Tabs.rotation;
            app.TabGroup.SelectionChangedFcn(app.TabGroup, struct("NewValue", app.Tabs.rotation));
            variability = app.computeRotationVariability("shot", "max", "");
            app.makeRotationMaps();
            testCase.verifyEqual(string(c.rotationShotNumbers.Enable), "on", "データに shotNo の列がある");
            testCase.verifyEmpty(findall(c.rotationMapAxes(1), 'Type', 'text', 'Tag', 'keepColor'), "初めは重ねない");
            c.rotationShotNumbers.Value = true;
            c.rotationShotNumbers.ValueChangedFcn(c.rotationShotNumbers, []);
            shots = app.Data.units(1).shots;
            for ax = [c.rotationSpreadAxes(1), c.rotationMapAxes(1)]
                labels = findall(ax, 'Type', 'text', 'Tag', 'keepColor');
                testCase.verifyEqual(sort(str2double(string(get(labels, 'String')))), sort(shots.shotNo(:)));
            end
            labels = findall(c.rotationMapAxes(1), 'Type', 'text', 'Tag', 'keepColor');
            first = labels(str2double(string(get(labels, 'String'))) == shots.shotNo(1));
            testCase.verifyEqual(first.Position(1:2), [shots.Xmm(1), shots.Ymm(1) + 0.3 * variability.shotSizeMm(2)], ...
                'AbsTol', 1e-9, "Shot ごとの図は Shot の中で上へずらす");
            % shotNo の列が無い Excel・CSV（座標から番号を付ける）では選べず、重ねない
            raw = readtable(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'), 'TextType', 'string');
            raw.shotNo = [];
            file = [tempname, '.csv'];
            writetable(raw, file);
            cleanupFile = onCleanup(@() delete(file));
            app.loadRotationFile(file);
            app.applyRotationMapping();
            testCase.verifyEqual(string(c.rotationShotNumbers.Enable), "off");
            app.computeRotationVariability("shot", "max", "");
            testCase.verifyEmpty(findall(c.rotationSpreadAxes(1), 'Type', 'text', 'Tag', 'keepColor'));
        end

        function priorityShotsFromFieldAndClick(testCase)
            % 画面：「優先度 1 の Shot」の欄と図のクリックで指定した Shot は、3σ によらず優先度 1（Mark ごとはその Shot の
            % すべての Mark）。計測マップを作ってあれば作り直し（見ている結果のタブはそのまま）、図に枠を描く。書き出しの
            % 「説明」にも出す
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            c = app.Controls;
            app.TabGroup.SelectedTab = app.Tabs.rotation;
            app.TabGroup.SelectionChangedFcn(app.TabGroup, struct("NewValue", app.Tabs.rotation));
            variability = app.computeRotationVariability("mark", "max", "");
            testCase.verifyEqual(c.rotationMapCount.Value, 2, "計測マップの数の初期値は 2");
            testCase.verifyEqual(string(c.rotationAssignment.Value), "poisson", "振り分けの初期値はポアソンディスク");
            before = app.makeRotationMaps("sigma3Length", str2double(c.rotationThresholds.Value), 3);
            rows = before.table;
            shotNos = unique(rows.shotNo(rows.rank == 2));
            lowShots = shotNos(arrayfun(@(no) all(rows.rank(rows.shotNo == no) == 2), shotNos));   % 3σ では優先度 2 の Shot
            first = lowShots(1);
            second = lowShots(2);
            testCase.verifyEmpty(c.rotationMapAxes(1).Legend, "マップには凡例を付けない（どのマップも同じ大きさ）");
            legendNames = string(c.rotationMapLegendAxes.Legend.String);
            testCase.verifyTrue(all(ismember(["計測しない", "優先度 1", "優先度 2"], legendNames)), ...
                "凡例はマップの右に1つ（数は名前に入れない）");
            % 欄で指定する（表に無い shotNo は知らせる）
            c.rotationOutputs.SelectedTab = c.rotationVariabilityTab;
            c.rotationPriorityShots.Value = char(sprintf("%d 9999", first));
            c.rotationPriorityShots.ValueChangedFcn([], []);
            maps = app.RotationMaps;
            testCase.verifyTrue(all(maps.table.rank(maps.table.shotNo == first) == 1), "指定した Shot の Mark はすべて優先度 1");
            testCase.verifyEqual(maps.missingShotNos, 9999);
            testCase.verifyTrue(contains(string(c.rotationMapInfo.Text), "9999"));
            testCase.verifyEqual(c.rotationOutputs.SelectedTab, c.rotationVariabilityTab, "見ている結果のタブはそのまま");
            testCase.verifyNotEmpty(findobj(c.rotationSpreadAxes(1), 'DisplayName', "優先度 1 に指定（1）"));
            testCase.verifyNotEmpty(findobj(c.rotationMapAxes(1), 'DisplayName', "優先度 1 に指定（1）"));
            % 図のクリックで足す・外す（オンの間は図の点や線がクリックを図に渡す）
            c.rotationPriorityClick.Value = true;
            c.rotationPriorityClick.ValueChangedFcn([], []);
            ax = c.rotationSpreadAxes(1);
            testCase.verifyTrue(all(string(get(ax.Children, 'HitTest')) == "off"));
            center = [rows.Xc(find(rows.shotNo == second, 1)), rows.Yc(find(rows.shotNo == second, 1))];
            ax.ButtonDownFcn(ax, struct("IntersectionPoint", [center, 0]));
            testCase.verifyEqual(string(c.rotationPriorityShots.Value), sprintf("%d 9999 %d", first, second));
            testCase.verifyTrue(all(app.RotationMaps.table.rank(app.RotationMaps.table.shotNo == second) == 1));
            mapAxes = c.rotationMapAxes(1);
            mapAxes.ButtonDownFcn(mapAxes, struct("IntersectionPoint", [center, 0]));
            testCase.verifyEqual(string(c.rotationPriorityShots.Value), sprintf("%d 9999", first), "もう一度で外す");
            testCase.verifyTrue(all(app.RotationMaps.table.rank(app.RotationMaps.table.shotNo == second) == 2));
            ax = c.rotationSpreadAxes(1);
            ax.ButtonDownFcn(ax, struct("IntersectionPoint", [500, 500, 0]));
            testCase.verifyEqual(string(c.rotationPriorityShots.Value), sprintf("%d 9999", first), "Shot の外は何もしない");
            % 整数でない指定は知らせ、計測マップは変えない
            c.rotationPriorityShots.Value = 'abc';
            c.rotationPriorityShots.ValueChangedFcn([], []);
            testCase.verifyTrue(startsWith(string(c.rotationError.Text), "優先度 1 の Shot は shotNo（整数）"));
            testCase.verifyEqual(app.RotationMaps.priorityShotNos, [first, 9999]);
            % 書き出しの「説明」
            maps = app.makeRotationMaps(priorityShotNos=first);
            testCase.verifyEmpty(c.rotationError.Text);
            exported = [tempname, '.xlsx'];
            cleanupExport = onCleanup(@() delete(exported));
            app.exportRotationMapsTo(exported);
            notes = readtable(exported, 'Sheet', '説明', 'VariableNamingRule', 'preserve', 'TextType', 'string');
            testCase.verifyEqual(notes.("内容")(notes.("項目") == "優先度 1 に指定した shotNo"), string(first));
            testCase.verifyEqual(maps.priorityShotNos, first);
            % Shot ごと：指定した Shot は優先度 1
            app.computeRotationVariability("shot", "max", "");
            testCase.verifyNotEmpty(findobj(c.rotationSpreadAxes(1), 'DisplayName', "優先度 1 に指定（1）"), ...
                "ばらつきを求め直しても指定は残る");
            shotMaps = app.makeRotationMaps("sigma3Length", max(variability.table.sigma3Length) * 10, 2);
            testCase.verifyEqual(shotMaps.table.rank(shotMaps.table.shotNo == first), 1);
            testCase.verifyTrue(all(shotMaps.table.rank(shotMaps.table.shotNo ~= first) == 2));
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
            expected = alignest.stats.percentile(variability.table.sigma3Length, 75);   % 指標の初期値は長さ |v| の 3σ
            testCase.verifyEqual(str2double(c.rotationThresholds.Value), round(expected, 2, 'significant'));
            [c.rotationSpreadCircles.Value, c.rotationMapCircles.Value] = deal('120 140');   % 円は右のタブごとに指定
            maps = app.makeRotationMaps("sigma3Length", 80, 2, thresholdKind="percent", outerRadiusMm=135, ...
                assignment="random");
            testCase.verifyEqual(maps.thresholdKind, "percent");
            testCase.verifyEqual(maps.outerRadiusMm, 135);
            testCase.verifyEqual(maps.seed, app.Settings.sampling.seed, "メニューの乱数の種");
            testCase.verifyTrue(all(maps.table.rank(hypot(maps.table.x, maps.table.y) >= 135) == 1));
            testCase.verifyNotEmpty(findobj(c.rotationMapAxes(1), 'Type', 'line', 'DisplayName', '半径 120 mm'));
            testCase.verifyNotEmpty(findobj(c.rotationSpreadAxes(1), 'Type', 'line', 'DisplayName', '半径 140 mm'));
            testCase.verifyTrue(contains(string(c.rotationMapInfo.Text), "振り分けはランダム"));
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
            expected = alignest.radialCumulative(radius, variability.table.sigma3Length, [50, 80]);
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
            maps = alignest.rotationMaps(variability, "sigma3Vector", height(variability.table) - 10, 2);
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
            % 割合・読み込みの順・6. の Shot 高次補正（同じ値なら FB の補正値は検証側でも同じ残差）
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
            testCase.verifyEqual(string(c.rotationMetric.ItemsData), ["sigma3X", "sigma3Y", "sigma3Length"], ...
                "優先度の指標は X・Y・長さ |v| の 3σ");
            maps = app.makeRotationMaps("sigma3Length", str2double(c.rotationThresholds.Value), 3);
            testCase.verifyEqual(maps.nMaps, 3);
            testCase.verifyEqual(c.rotationMapCount.Value, 3, "計測マップの数の欄");
            testCase.verifyError(@() app.makeRotationMaps("sigma3Length", [], 25), 'alignest:rotationMaps');
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

function value = meanNearest(rows, membership)
% マップごとに、同じマップの点の中で最も近い点までの距離を求め、すべての点で平均する
distances = zeros(0, 1);
for m = 1:size(membership, 2)
    p = [rows.x(membership(:, m)), rows.y(membership(:, m))];
    gap = hypot(p(:, 1) - p(:, 1).', p(:, 2) - p(:, 2).');
    gap(1:size(gap, 1) + 1:end) = Inf;
    distances = [distances; min(gap, [], 2)]; %#ok<AGROW>
end
value = mean(distances);
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
