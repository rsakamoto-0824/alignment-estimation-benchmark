classdef TestFactorDesign < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addAppPath(~)
            addpath(fileparts(fileparts(mfilename('fullpath'))));
        end
    end

    methods (Test)
        function rowMainEffectAndPairInteractionsAreIncluded(testCase)
            [scan, mark, row] = ndgrid(1:2, 1:3, 1:2);
            factors = struct("scanTrain", scan(:), "scanTest", scan(:), ...
                "markTrain", mark(:), "markTest", mark(:), "rowTrain", row(:), "rowTest", row(:));
            features = [(1:numel(scan)).', zeros(numel(scan), 1)];
            for mode = alignest.models.gprFactorModes()
                [gp, basis, ~, codes] = alignest.models.gprModeSetup(features, features, [1, 2], ...
                    "matern52", mode, factors);
                testCase.verifyEqual(size(codes, 2), 4);
                switch mode
                    case {"none", "backfit", "additive", "additive_int"}
                        testCase.verifyEqual(size(basis, 2), 1);
                    case "basis"
                        testCase.verifyEqual(size(basis, 2), 5);
                    case "basis_int"
                        testCase.verifyEqual(size(basis, 2), 10);
                    case {"mixed", "mixed_int"}
                        testCase.verifyEqual(size(basis, 2), 3);
                end
                if mode == "additive_int"
                    testCase.verifyEqual(string({gp.categorical.name}), ...
                        ["scan", "mark", "row", "scan_mark", "scan_row", "mark_row"]);
                    expected = double(mark(:) == mark(:).' & row(:) == row(:).');
                    testCase.verifyEqual(gp.categorical(6).trainSame, expected);
                elseif mode == "mixed_int"
                    testCase.verifyEqual(string({gp.categorical.name}), ["mark", "scan_mark", "scan_row", "mark_row"]);
                end
            end
        end

        function singleObservedRowLevelAddsNoEstimableEffect(testCase)
            features = [(1:4).', zeros(4, 1)];
            factors = struct("markTrain", [1; 2; 1; 2], "markTest", [1; 2; 1; 2], ...
                "rowTrain", ones(4, 1), "rowTest", 2 * ones(4, 1));
            for mode = alignest.models.gprFactorModes()
                [with, basisWith, testWith] = alignest.models.gprModeSetup(features, features, [1, 2], ...
                    "matern52", mode, factors);
                withoutFactors = rmfield(factors, {'rowTrain', 'rowTest'});
                [without, basisWithout, testWithout] = alignest.models.gprModeSetup(features, features, [1, 2], ...
                    "matern52", mode, withoutFactors);
                testCase.verifyEqual(with.categorical, without.categorical);
                testCase.verifyEqual(basisWith, basisWithout);
                testCase.verifyEqual(testWith, testWithout);
            end
        end
    end
end
