classdef TestMeasurementPlan < matlab.unittest.TestCase
    %TESTMEASUREMENTPLAN 計測率による学習 Shot 数、必ず計測する Shot（指定・最外周）と拡張 I 最適計画を確かめる。

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
            nTerms = (sampling.designOrder + 1) * (sampling.designOrder + 2) / 2;
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
