classdef TestMeasurementPlan < matlab.unittest.TestCase
    %TESTMEASUREMENTPLAN 計測率による学習 Shot 数、必ず計測する Shot（指定・最外周）と拡張 I 最適計画、Sobol 列・
    %   ポアソンディスクの計画、計測点の選び方の単位（Shot 単位・Mark 単位）を確かめる。

    properties
        Data
    end

    methods (TestClassSetup)
        function loadSample(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            addpath(root);
            raw = alignest.readMeasurementFile(fullfile(root, 'sample_data', 'sample_alignment.csv'));
            testCase.Data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
        end
    end

    methods (Test)
        function measurementRatesSweepFromStartToEnd(testCase)
            testCase.verifyEqual(alignest.measurementRateList(10, 40, 10), [10, 20, 30, 40]);
            testCase.verifyEqual(alignest.measurementRateList(5, 12.5, 2.5), [5, 7.5, 10, 12.5]);
            testCase.verifyEqual(alignest.measurementRateList(10, 42, 10), [10, 20, 30, 40], "終了が刻みに乗らなければ手前まで");
            testCase.verifyEqual(alignest.measurementRateList(0.1, 0.3, 0.1), [0.1, 0.2, 0.3], "小数の刻みでも終了を含む");
            testCase.verifyError(@() alignest.measurementRateList(0, 20, 10), 'alignest:measurementRate');
            testCase.verifyError(@() alignest.measurementRateList(10, 100, 10), 'alignest:measurementRate');
            testCase.verifyError(@() alignest.measurementRateList(30, 10, 5), 'alignest:measurementRate');
            testCase.verifyError(@() alignest.measurementRateList(10, 20, 0), 'alignest:measurementRate');
            testCase.verifyError(@() alignest.measurementRateList(1, 99, 0.5), 'alignest:measurementRate');
        end

        function ratePlansUseShareOfCandidateShots(testCase)
            sampling = alignest.defaultSettings().sampling;
            sampling.countBy = "rate";
            sampling.rateStart = 10;
            sampling.rateEnd = 25;
            sampling.rateStep = 7.5;
            specs = alignest.buildPlanSpecs(sampling);
            testCase.verifyEqual(string({specs.label}), ["I最適 計測率 10%", "I最適 計測率 17.5%", "I最適 計測率 25%"]);
            testCase.verifyEqual(string({specs.group}), ["計測率 10%", "計測率 17.5%", "計測率 25%"]);
            testCase.verifyEqual([specs.rate], [10, 17.5, 25]);
            testCase.verifyTrue(all(isnan([specs.nShots])));
            unit = testCase.Data.units(1);
            nCandidates = nnz(unit.shots.nValidX + unit.shots.nValidY > 0);
            sampling.method = "random";
            sampling.randomRepeats = 2;
            randomSpecs = alignest.buildPlanSpecs(sampling);
            testCase.verifyEqual(randomSpecs(2).label, "ランダム 計測率 10% #2");
            plan = alignest.planTrainingShots(unit, randomSpecs(3), sampling, 150);
            testCase.verifyEqual(plan.nShots, round(0.175 * nCandidates));
            testCase.verifyEqual(plan.rate, 17.5);
            % 手動では計測率を使わない
            sampling.method = "manual";
            sampling.manualPlans = "1 2 3";
            testCase.verifyEqual(alignest.buildPlanSpecs(sampling).label, "手動1（3 Shot）");
        end

        function outerShotsHaveAMissingNeighbor(testCase)
            % 4 × 4 の格子から角を1つ除いても、内側の4 Shot は上下左右に隣があるので最外周ではない
            [column, row] = meshgrid(1:4, 1:4);
            keep = ~(row == 1 & column == 1);
            shots = struct("row", row(keep), "column", column(keep));
            outer = alignest.outerShots(shots);
            inner = ismember([shots.row, shots.column], [2, 2; 2, 3; 3, 2; 3, 3], 'rows');
            testCase.verifyEqual(outer, ~inner);
            % 5 × 5 の真ん中の Shot が無ければ、その上下左右の Shot も外周になる（隣が無い）
            [column, row] = meshgrid(1:5, 1:5);
            keep = ~(row == 3 & column == 3);
            shots = struct("row", row(keep), "column", column(keep));
            outer = alignest.outerShots(shots);
            testCase.verifyTrue(all(outer(ismember([shots.row, shots.column], [2, 3; 4, 3; 3, 2; 3, 4], 'rows'))));
            testCase.verifyFalse(any(outer(ismember([shots.row, shots.column], [2, 2; 4, 4], 'rows'))));
            % サンプルの Wafer：最外周は Shot の並びの外側の Shot で、内側の Shot は入らない
            unit = testCase.Data.units(1);
            outer = alignest.outerShots(unit.shots);
            testCase.verifyEqual(nnz(outer), 28);
            testCase.verifyTrue(all(ismember([1, 2, 3, 31, 43, 97, 98, 99], unit.shots.shotNo(outer))));
            testCase.verifyFalse(any(ismember([50, 37, 62], unit.shots.shotNo(outer))));
        end

        function requiredShotsCombineSpecifiedAndOuter(testCase)
            unit = testCase.Data.units(1);
            candidates = find(unit.shots.nValidX + unit.shots.nValidY > 0);
            sampling = struct("requiredShots", [50, 1, 999], "requireOuterShots", false);
            [index, details] = alignest.requiredShotIndex(unit.shots, candidates, sampling);
            testCase.verifyEqual(sort(unit.shots.shotNo(index)).', [1, 50]);
            testCase.verifyEqual(details.missingNos, 999);
            sampling.requireOuterShots = true;
            [index, details] = alignest.requiredShotIndex(unit.shots, candidates, sampling);
            testCase.verifyEqual(numel(index), 29, "最外周 28 と shotNo 50（shotNo 1 は最外周と重なる）");
            testCase.verifyEqual(numel(details.outer), 28);
        end

        function augmentedIOptimalKeepsRequiredShots(testCase)
            sampling = alignest.defaultSettings().sampling;
            sampling.exchangeStarts = 3;
            sampling.requiredShots = [1, 50, 99];
            unit = testCase.Data.units(1);
            spec = struct("type", "ioptimal", "nShots", 15, "repeat", 1, "label", "I最適 15 Shot", ...
                "group", "15 Shot", "shotNos", []);
            plan = alignest.planTrainingShots(unit, spec, sampling, 150);
            testCase.verifyTrue(plan.ok);
            testCase.verifyEqual(plan.nShots, 15);
            testCase.verifyTrue(all(ismember([1, 50, 99], plan.shotNos)));
            testCase.verifyEqual(sort(unit.shots.shotNo(plan.requiredShotIndex)).', [1, 50, 99]);
            % 必ず計測する Shot を入れたまま、残りを I 基準が小さくなるように選んでいる（ランダムに足すより良い）
            candidates = find(unit.shots.nValidX + unit.shots.nValidY > 0);
            free = setdiff(candidates, plan.requiredShotIndex);
            stream = RandStream('mt19937ar', 'Seed', 1);
            randomValues = zeros(20, 1);
            for k = 1:20
                added = free(randperm(stream, numel(free), 12));
                randomPlan = plan;
                randomPlan.shotIndex = sort([plan.requiredShotIndex; added(:)]);
                randomValues(k) = criterionOf(unit, randomPlan);
            end
            testCase.verifyLessThan(plan.criterionI, min(randomValues));
            % 必ず計測する Shot が学習 Shot 数より多いときは、それだけを使う
            sampling.requireOuterShots = true;
            plan = alignest.planTrainingShots(unit, spec, sampling, 150);
            testCase.verifyEqual(plan.nShots, 29);
            testCase.verifyTrue(contains(plan.message, "必ず計測する Shot が 29 個"));
            % ランダムでも必ず計測する Shot を入れる
            sampling.requireOuterShots = false;
            spec.type = "random";
            plan = alignest.planTrainingShots(unit, spec, sampling, 150);
            testCase.verifyEqual(plan.nShots, 15);
            testCase.verifyTrue(all(ismember([1, 50, 99], plan.shotNos)));
        end

        function sobolPlanSpreadsShotsEvenly(testCase)
            % Sobol 列：前から 2^k 点（先頭の (0, 0) を含む）で各軸の 2^k 等分の区間に1点ずつ。学習 Shot は Sobol 列の点に
            % 近い Shot（乱数を使わない）で、必ず計測する Shot を入れ、計測しない Shot は選ばない
            points = alignest.sobolSequence(7);
            testCase.verifyEqual(points, [0.5, 0.5; 0.75, 0.25; 0.25, 0.75; 0.375, 0.375; 0.875, 0.875; 0.625, 0.125; ...
                0.125, 0.625]);
            sixteen = [0, 0; alignest.sobolSequence(15)];
            testCase.verifyEqual(sort(floor(16 * sixteen(:, 1))).', 0:15, "1次元目：16 等分に1点ずつ");
            testCase.verifyEqual(sort(floor(16 * sixteen(:, 2))).', 0:15, "2次元目：16 等分に1点ずつ");
            cells = floor(4 * sixteen(:, 1)) * 4 + floor(4 * sixteen(:, 2));
            testCase.verifyEqual(sort(cells).', 0:15, "4 × 4 のマスに1点ずつ");
            sampling = alignest.defaultSettings().sampling;
            sampling.requiredShots = [1, 50];
            unit = testCase.Data.units(1);
            spec = struct("type", "sobol", "nShots", 20, "repeat", 1, "label", "Sobol 20 Shot", "group", "20 Shot", ...
                "shotNos", []);
            plan = alignest.planTrainingShots(unit, spec, sampling, 150);
            testCase.verifyTrue(plan.ok);
            testCase.verifyEqual(plan.nShots, 20);
            testCase.verifyEqual(numel(unique(plan.shotNos)), 20);
            testCase.verifyTrue(all(ismember([1, 50], plan.shotNos)), "必ず計測する Shot");
            sampling.seed = 99;
            testCase.verifyEqual(alignest.planTrainingShots(unit, spec, sampling, 150).shotNos, plan.shotNos, ...
                "乱数の種によらず同じ Shot");
            x = unit.shots.Xmm(plan.shotIndex);
            y = unit.shots.Ymm(plan.shotIndex);
            quadrants = [nnz(x > 0 & y >= 0), nnz(x <= 0 & y > 0), nnz(x < 0 & y <= 0), nnz(x >= 0 & y < 0)];
            testCase.verifyGreaterThanOrEqual(min(quadrants), 3, "4つの象限に散らばる");
            others = setdiff(plan.shotNos, [1, 50]);
            sampling.excludedShots = others(1:3).';
            excluded = alignest.planTrainingShots(unit, spec, sampling, 150);
            testCase.verifyEqual(excluded.nShots, 20);
            testCase.verifyFalse(any(ismember(others(1:3), excluded.shotNos)), "計測しない Shot は選ばない");
            % 選び方の一覧：Shot 数ごとに1つ（選び方を比べると名前に「Sobol」）
            sampling.method = ["ioptimal", "sobol"];
            sampling.nShots = [10, 20];
            specs = alignest.buildPlanSpecs(sampling);
            testCase.verifyEqual([specs([specs.type] == "sobol").label], ["Sobol 10 Shot", "Sobol 20 Shot"]);
            testCase.verifyEqual([specs([specs.type] == "sobol").group], ["Sobol 10 Shot", "Sobol 20 Shot"]);
            testCase.verifyError(@() alignest.sobolShots([0, 0; 1, 1], 3), 'alignest:sobolShots');
        end

        function poissonDiskPlanKeepsPointsApart(testCase)
            % ポアソンディスク：選んだ点どうしの距離が d 以上（乱数より近づきすぎない）。同じ乱数なら同じ点、必ず選ぶ点は先に。
            % Shot 単位（poisson）と Mark 単位（markpoisson）の学習パターン。どちらもランダムと同じく繰り返し回数だけ作る
            [gx, gy] = meshgrid(-140:10:140);
            points = [gx(:), gy(:)];
            points = points(hypot(points(:, 1), points(:, 2)) < 145, :);
            stream = @() RandStream('mt19937ar', 'Seed', 1);
            chosen = alignest.poissonDiskSelect(points, 30, false(size(points, 1), 1), stream());
            testCase.verifyEqual(numel(unique(chosen)), 30);
            testCase.verifyEqual(alignest.poissonDiskSelect(points, 30, [], stream()), chosen, "同じ乱数なら同じ点");
            random = randperm(stream(), size(points, 1), 30);
            testCase.verifyGreaterThan(minimumGap(points(chosen, :)), 2 * minimumGap(points(random, :)), ...
                "乱数で選ぶより点どうしが離れる");
            fixed = false(size(points, 1), 1);
            fixed([5, 9]) = true;
            withFixed = alignest.poissonDiskSelect(points, 10, fixed, stream());
            testCase.verifyEqual(withFixed(1:2), [5; 9], "必ず選ぶ点を先に入れる");
            testCase.verifyEqual(alignest.poissonDiskSelect(points, 2, fixed, stream()), [5; 9]);
            testCase.verifyError(@() alignest.poissonDiskSelect(points(1:3, :), 4), 'alignest:poissonDisk');
            % Shot 単位：必ず計測する Shot を入れ、計測しない Shot は選ばない
            unit = testCase.Data.units(1);
            sampling = alignest.defaultSettings().sampling;
            sampling.method = ["random", "poisson", "markpoisson"];
            sampling.nShots = 20;
            sampling.randomRepeats = 2;
            specs = alignest.buildPlanSpecs(sampling);
            testCase.verifyEqual(string({specs.label}), ["ランダム 20 Shot #1", "ランダム 20 Shot #2", ...
                "ポアソン 20 Shot #1", "ポアソン 20 Shot #2", "Markポアソン 1 点/Shot #1", "Markポアソン 1 点/Shot #2"]);
            sampling.requiredShots = 50;
            sampling.excludedShots = 1;
            plans = arrayfun(@(spec) alignest.planTrainingShots(unit, spec, sampling, 150), specs);
            testCase.verifyTrue(all([plans.ok]));
            poisson = plans(3);
            testCase.verifyEqual(poisson.nShots, 20);
            testCase.verifyTrue(ismember(50, poisson.shotNos) && ~ismember(1, poisson.shotNos));
            testCase.verifyNotEqual(plans(4).shotNos, poisson.shotNos, "繰り返しごとに別の配置");
            gap = @(plan) minimumGap([unit.shots.Xmm(plan.shotIndex), unit.shots.Ymm(plan.shotIndex)]);
            testCase.verifyGreaterThan(gap(poisson), gap(plans(1)), "ランダムより Shot どうしが離れる");
            % Mark 単位：Mark の数は 1 Shot あたりの数 × 選べる Mark のある Shot の数（計測しない Shot 1 を除く）、
            % Wafer 中心に最も近い Mark を必ず計測する
            markPlan = plans(5);
            candidates = nnz(unit.shots.nValidX + unit.shots.nValidY > 0);
            testCase.verifyEqual(markPlan.nMarks, candidates - 1);
            testCase.verifyEqual(markPlan.type, "markpoisson");
            fixedMarks = alignest.markPlanFixedMarks(unit, sampling);
            testCase.verifyTrue(all(ismember(fixedMarks, markPlan.markIndex)), "必ず計測する Mark");
            testCase.verifyFalse(any(unit.marks.shotNo(markPlan.markIndex) == 1), "計測しない Shot の Mark は選ばない");
            testCase.verifyTrue(ismember("markpoisson", alignest.markPlanTypes()));
        end

        function samplingUnitSelectsShotOrMarkMethods(testCase)
            % 計測点の選び方の単位：Shot 単位・Mark 単位で選べる選び方。設定の単位は選び方から決め、両方が混ざった以前の
            % 設定は単位（無ければ Shot 単位）の選び方だけを残す
            [shotMethods, shotNames] = alignest.samplingUnitMethods("shot");
            testCase.verifyEqual(shotMethods, ["ioptimal", "doptimal", "random", "sobol", "poisson", "excel"]);
            testCase.verifyEqual(shotNames(5), "ポアソンディスク");
            testCase.verifyEqual(alignest.samplingUnitMethods("mark"), ["mark", "markd", "markrandom", "markpoisson", "excel"]);
            normalized = alignest.normalizeSamplingUnit(struct("method", ["mark", "excel"]));
            testCase.verifyEqual([normalized.unit, normalized.method], ["mark", "mark", "excel"]);
            normalized = alignest.normalizeSamplingUnit(struct("unit", "mark", "method", ["ioptimal", "mark"]));
            testCase.verifyEqual([normalized.unit, normalized.method], ["mark", "mark"], "混ざっていたら単位の選び方だけ");
            normalized = alignest.normalizeSamplingUnit(struct("method", ["ioptimal", "mark"]));
            testCase.verifyEqual([normalized.unit, normalized.method], ["shot", "ioptimal"]);
            normalized = alignest.normalizeSamplingUnit(struct("unit", "mark", "method", "excel"));
            testCase.verifyEqual([normalized.unit, normalized.method], ["mark", "excel"], "Excel だけなら単位はそのまま");
            normalized = alignest.normalizeSamplingUnit(struct("unit", "mark", "method", strings(1, 0)));
            testCase.verifyEqual([normalized.unit, normalized.method], ["mark", "mark"], "空ならその単位の I 最適");
            % 画面：単位を変えると一覧が変わり、Excel で指定は選んだまま、別の単位の選び方しか無ければ I 最適
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual(string(c.samplingUnit.Value), "shot");
            testCase.verifyEqual(string(c.samplingMethod.ItemsData), shotMethods);
            c.samplingMethod.Value = {'poisson', 'excel'};
            c.samplingMethod.ValueChangedFcn([], []);
            testCase.verifyEqual(string(c.randomRepeats.Enable), "on", "ポアソンディスクは繰り返す");
            testCase.verifyEqual(string(c.zoneEdges.Enable), "off", "ポアソンディスクは同心円の制約を使わない");
            testCase.verifyEqual(string(c.requiredShots.Enable), "on");
            c.samplingUnit.Value = 'mark';
            c.samplingUnit.ValueChangedFcn([], []);
            testCase.verifyEqual(string(c.samplingMethod.Items), ["I 最適", "D 最適", "制約つきランダム", "ポアソンディスク", ...
                "Excel ファイルで指定"]);
            testCase.verifyEqual(app.Settings.sampling.unit, "mark");
            testCase.verifyEqual(app.Settings.sampling.method, ["mark", "excel"]);
            c.samplingMethod.Value = {'markpoisson'};
            c.samplingMethod.ValueChangedFcn([], []);
            testCase.verifyEqual(string({c.markBalance.Enable, c.markRequirePerShot.Enable, c.markPerShot.Enable, ...
                c.requiredMarks.Enable}), ["off", "off", "on", "on"], "Mark 単位のポアソンディスクは Mark 番号などの制約を使わない");
            settings = app.Settings;
            settings.sampling.method = ["ioptimal", "markrandom"];
            settings.sampling.unit = "mark";
            app.setSettings(settings);
            testCase.verifyEqual(string(c.samplingUnit.Value), "mark");
            testCase.verifyEqual(app.Settings.sampling.method, "markrandom", "画面に出せない選び方は設定からも外す");
        end

        function efficiencyIsRelativeToMeasuringEveryShot(testCase)
            % 全計測（候補の全 Mark）では情報行列が単位行列なので I 効率・D 効率は 1
            unit = testCase.Data.units(1);
            sampling = alignest.defaultSettings().sampling;
            candidates = find(unit.shots.nValidX + unit.shots.nValidY > 0);
            spec = struct("type", "manual", "nShots", numel(candidates), "repeat", 1, "label", "", "group", "", ...
                "shotNos", unit.shots.shotNo(candidates(1:end - 1)).');
            nearlyAll = alignest.planTrainingShots(unit, spec, sampling, 150);
            testCase.verifyGreaterThan(nearlyAll.efficiencyI, 0.9);
            testCase.verifyLessThan(nearlyAll.efficiencyI, 1);
            spec = struct("type", "ioptimal", "nShots", 20, "repeat", 1, "label", "", "group", "", "shotNos", []);
            sampling.exchangeStarts = 2;
            plan = alignest.planTrainingShots(unit, spec, sampling, 150);
            nTerms = size(alignest.basis.designPolynomial(0, 0, sampling.designOrder, sampling.designFeatures), 2);   % 基準モデルの項数
            testCase.verifyEqual(plan.efficiencyI, nTerms / plan.criterionI, 'RelTol', 1e-12);
            testCase.verifyEqual(plan.efficiencyD, 1 / plan.criterionD, 'RelTol', 1e-12);
            testCase.verifyTrue(plan.efficiencyI > 0 && plan.efficiencyI < nearlyAll.efficiencyI, ...
                "学習 Shot が少ないほど効率は小さい");
        end

        function exchangeNeverRemovesFixedShots(testCase)
            % 1次元の直線モデル：端の点が最も良いが、固定した真ん中の点は外さない
            positions = linspace(-1, 1, 11).';
            blocks = arrayfun(@(x) [1, x] / sqrt(11), positions, 'UniformOutput', false);
            fixed = false(11, 1);
            fixed(6) = true;
            stream = RandStream('mt19937ar', 'Seed', 3);
            selected = alignest.constrainedIOptimal(blocks, 3, zeros(11, 0), 1, stream, 3, 50, fixed);
            testCase.verifyEqual(sort(selected(:)).', [1, 6, 11]);
            stream = RandStream('mt19937ar', 'Seed', 3);
            [chosen, violation] = alignest.randomFeasibleShots(11, 4, zeros(11, 0), 1, stream, fixed);
            testCase.verifyTrue(chosen(6));
            testCase.verifyEqual(nnz(chosen), 4);
            testCase.verifyEqual(violation, 0);
        end
    end
end

function value = criterionOf(unit, plan)
% 学習 Shot の組の I 基準（planTrainingShots と同じ基準モデル）
sampling = alignest.defaultSettings().sampling;
sampling.method = "manual";
spec = struct("type", "manual", "nShots", numel(plan.shotIndex), "repeat", 1, "label", "", "group", "", ...
    "shotNos", unit.shots.shotNo(plan.shotIndex).');
value = alignest.planTrainingShots(unit, spec, sampling, 150).criterionI;
end

function gap = minimumGap(points)
% 点どうしの最も近い距離
distances = hypot(points(:, 1) - points(:, 1).', points(:, 2) - points(:, 2).');
distances(1:size(points, 1) + 1:end) = Inf;
gap = min(distances(:));
end
