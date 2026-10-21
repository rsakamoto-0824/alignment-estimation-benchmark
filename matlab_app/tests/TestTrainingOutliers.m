classdef TestTrainingOutliers < matlab.unittest.TestCase
    %TESTTRAININGOUTLIERS 学習データの異常値（平均から nσ を超えて離れた Mark）を除いて推定することを確かめる。

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
        function outlierOnEitherAxisIsRemovedFromBoth(testCase)
            % 学習点 1〜22（X・Y とも −1 と 1 の繰り返し）に、X だけ外れた点 21・Y だけ外れた点 22 を入れる。
            % 23 は学習点でない大きな値（判定にも平均・σ にも入らない）、24 は X が無効な点
            measX = [repmat([-1; 1], 10, 1); 10; 0; 100; 1000];
            measY = [repmat([1; -1], 10, 1); 0; -10; 0; 0.5];
            marks = struct("measX", measX, "measY", measY, "validX", [true(23, 1); false], "validY", true(24, 1));
            inTrain = [true(22, 1); false; true];
            [outlier, stats] = alignest.trainingOutliers(marks, inTrain, 2);
            testCase.verifyEqual(find(outlier).', [21, 22]);
            testCase.verifyEqual(stats.outlierAxis([21, 22], :), [true, false; false, true]);
            useX = inTrain & marks.validX;
            testCase.verifyEqual(stats.mean(1), mean(measX(useX)), 'AbsTol', 1e-12);
            testCase.verifyEqual(stats.std(1), std(measX(useX)), 'AbsTol', 1e-12);
            testCase.verifyEqual(stats.count, [22, 23]);
            % n を大きくすると外れ値とみなさない（n は任意の正の値）
            testCase.verifyFalse(any(alignest.trainingOutliers(marks, inTrain, 4.5)));
            testCase.verifyError(@() alignest.trainingOutliers(marks, inTrain, 0), 'MATLAB:validators:mustBePositive');
        end

        function estimationExcludesOutliersOfThisWaferAndPlan(testCase)
            settings = alignest.defaultSettings();
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            method = alignest.buildMethodList(settings.methods);
            unit = testCase.Data.units(1);
            trainShots = (1:3:numel(unit.shots.shotNo)).';
            marks = unit.marks;
            inTrain = ismember(marks.shotIndex, trainShots);
            target = find(inTrain & marks.validX & marks.validY, 1);
            unit.marks.measX(target) = unit.marks.measX(target) + 500;   % X だけ大きく外れた学習点
            plain = alignest.estimateWafer(unit, trainShots, method(1), settings);
            testCase.verifyTrue(ismember(target, plain.trainIndex.X));
            settings.evaluation.excludeOutliers = true;
            settings.evaluation.outlierSigma = 3;
            cleaned = alignest.estimateWafer(unit, trainShots, method(1), settings);
            testCase.verifyTrue(ismember(target, cleaned.outlierIndex));
            testCase.verifyFalse(ismember(target, cleaned.trainIndex.X), "X の学習データから除く");
            testCase.verifyFalse(ismember(target, cleaned.trainIndex.Y), "Y は正常でも Y の学習データから除く");
            testCase.verifyEqual(cleaned.testIndex, plain.testIndex, "評価点は変わらない");
            % 除いた点は、この Wafer・この学習 Shot の組の平均と σ で判定したもの
            expected = alignest.trainingOutliers(unit.marks, inTrain, 3);
            testCase.verifyEqual(cleaned.outlierIndex, find(expected));
            % 外れた点を除くと、評価点の誤差が小さくなる
            measured = unit.marks.measX(plain.testIndex.X);
            testCase.verifyLessThan(rms(measured - cleaned.estimate.X), rms(measured - plain.estimate.X));
        end
    end
end
