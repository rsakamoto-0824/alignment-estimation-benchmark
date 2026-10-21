classdef TestModelOptions < matlab.unittest.TestCase
    %TESTMODELOPTIONS 追加したモデルの選択肢：Kriging の spherical バリオグラム、ν を指定する Matérn カーネル、
    %   GAM の形状関数（スプライン・ガウス過程回帰）を確かめる。

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
        function sphericalVariogramFollowsPyKrige(testCase)
            params = [0.8; 0.6; 0.1];
            distance = [0; 0.3; 0.6; 0.9];
            expected = [0.1; 0.8 * (1.5 * 0.5 - 0.5 * 0.5 ^ 3) + 0.1; 0.9; 0.9];
            testCase.verifyEqual(alignest.models.krigingVariogram("spherical", params, distance), expected, 'AbsTol', 1e-14);
            % ノイズの無い経験バリオグラムからは、元のパラメータに戻る（微分が正しくないと止まる位置がずれる）
            lags = linspace(0.05, 1, 8).';
            semivariance = alignest.models.krigingVariogram("spherical", params, lags);
            fitted = alignest.models.krigingFitVariogram("spherical", lags, semivariance);
            testCase.verifyEqual(fitted, params, 'AbsTol', 1e-4);
            % 学習点の距離がすべて range より遠くても（形の列が定数）警告を出さずに当てはめる
            testCase.verifyWarningFree(@() alignest.models.krigingFitVariogram("spherical", [2; 3; 4], [1; 1.1; 0.9]));
            features = alignest.basis.distanceFeatures(testCase.Data.units(1).marks.x(1:200), ...
                testCase.Data.units(1).marks.y(1:200), 'XYR', 150);
            model = alignest.models.krigingSetup(features(1:150, :), features(151:end, :), "ordinary", "spherical");
            result = alignest.models.krigingFitPredict(model, testCase.Data.units(1).marks.measY(1:150));
            testCase.verifyTrue(all(isfinite(result.prediction)));
            testCase.verifyError(@() alignest.models.krigingVariogram("cubic", params, distance), 'alignest:variogram');
        end

        function maternNuMatchesClosedFormsAndGradient(testCase)
            features = [sin(1:60).', cos(1.3 * (1:60)).', mod((1:60).', 7) / 7];
            groups = [1, 2, 3];
            pairs = ["matern_nu0.5", "exponential"; "matern_nu1.5", "matern32"; "matern_nu2.5", "matern52"; ...
                "ardmatern_nu1.5", "ardmatern32"; "ardmatern_nu2.5", "ardmatern52"];
            for k = 1:size(pairs, 1)
                general = alignest.models.gprSetup(features, features(1:10, :), groups, pairs(k, 1));
                closed = alignest.models.gprSetup(features, features(1:10, :), groups, pairs(k, 2));
                lengths = log([0.3; 0.5; 0.7]);
                params = [lengths(1:general.nLength); log(1.3); log(0.2)];
                [kernel, grads] = alignest.models.gprKernel(general, params);
                [kernelClosed, gradsClosed] = alignest.models.gprKernel(closed, params);
                testCase.verifyEqual(kernel, kernelClosed, 'AbsTol', 1e-12, pairs(k, 1));
                testCase.verifyEqual(grads, gradsClosed, 'AbsTol', 1e-12, pairs(k, 1));
                testCase.verifyEqual(alignest.models.gprKernel(general, params, "cross"), ...
                    alignest.models.gprKernel(closed, params, "cross"), 'AbsTol', 1e-12, pairs(k, 1));
            end
            % ν が半整数でないときも、目的関数の勾配が数値微分と合う
            y = sin(3 * features(:, 1)) + features(:, 2) .^ 2;
            for name = ["matern_nu1.2", "ardmatern_nu0.8", "matern_nu3.3", "ardmatern_nu7"]
                gp = alignest.models.gprSetup(features, features(1:10, :), groups, name);
                start = alignest.models.gprInitialParams(gp, y);
                [~, gradient] = alignest.models.gprObjective(gp, start, y, ones(60, 1));
                numeric = zeros(size(gradient));
                step = 1e-6;
                for i = 1:numel(start)
                    shift = zeros(size(start));
                    shift(i) = step;
                    numeric(i) = (alignest.models.gprObjective(gp, start + shift, y, ones(60, 1)) - ...
                        alignest.models.gprObjective(gp, start - shift, y, ones(60, 1))) / (2 * step);
                end
                testCase.verifyLessThan(max(abs(numeric - gradient)) / max(abs(gradient)), 1e-6, name);
            end
            testCase.verifyError(@() alignest.models.gprSetup(features, features, groups, "matern_nu0"), 'alignest:maternNu');
            testCase.verifyError(@() alignest.models.gprSetup(features, features, groups, "matern_nu60"), 'alignest:maternNu');
            testCase.verifyError(@() alignest.models.gprSetup(features, features, groups, "maternx"), 'alignest:kernel');
        end

        function methodListExpandsNuAndGamShapes(testCase)
            config = alignest.recommendedMethods("none");
            config.gpr.enabled = true;
            config.gpr.kernels = ["matern52", "matern", "ardmatern"];
            config.gpr.maternNu = [0.75, 2];
            config.gpr.factorModes = "basis";
            config.kriging.ordinary = true;
            config.kriging.variograms = "spherical";
            config.gam.enabled = true;
            config.gam.shapes.xy = "gp";
            config.featureSets = ["XY", "XYR"];
            methods = alignest.buildMethodList(config);
            ids = string({methods.id});
            testCase.verifyTrue(all(ismember(["GPR_matern_nu0.75_XY_basis", "GPR_ardmatern_nu2_XYR_basis", ...
                "OK_spherical_XY", "GAM_XY_gp-xy", "GAM_XYR_gp-xy"], ids)));
            testCase.verifyEqual(nnz(startsWith(ids, "GPR_")), 2 * 5);
            gpr = methods(ids == "GPR_matern_nu0.75_XY_basis");
            testCase.verifyTrue(contains(gpr.label, "ν=0.75"));
            gam = methods(ids == "GAM_XYR_gp-xy");
            testCase.verifyEqual(gam.variant, "gp:xy");
            testCase.verifyTrue(contains(gam.label, "ガウス過程：X・Y"));
            % 半径の項は XY には無いので、XY の GAM の id には入らない
            config.gam.shapes.r = "gp";
            ids = string({alignest.buildMethodList(config).id});
            testCase.verifyTrue(all(ismember(["GAM_XY_gp-xy", "GAM_XYR_gp-xy-r"], ids)));
            config.gpr.maternNu = [];
            testCase.verifyError(@() alignest.buildMethodList(config), 'alignest:maternNu');
            config.gpr.maternNu = 2;
            config.gam.shapes.r = "kriging";
            testCase.verifyError(@() alignest.buildMethodList(config), 'alignest:gamShape');
            % 以前の設定（ν・形状関数が無い）には初期値を補う
            legacy = alignest.recommendedMethods();
            legacy.gpr = rmfield(legacy.gpr, "maternNu");
            legacy.gam = rmfield(legacy.gam, "shapes");
            completed = alignest.completeMethodSettings(legacy);
            testCase.verifyEqual(completed.gpr.maternNu, 2);
            testCase.verifyEqual(completed.gam.shapes.r, "spline");
            testCase.verifyEqual(string({alignest.buildMethodList(legacy).id}), ...
                string({alignest.buildMethodList(alignest.recommendedMethods()).id}));
            allIds = string({alignest.buildMethodList(alignest.recommendedMethods("all")).id});
            testCase.verifyTrue(all(ismember(["GPR_ardmatern_nu2_XYR_mixed_int", "UK_spherical_XYR_backfit"], allIds)));
            testCase.verifyFalse(any(contains(allIds, "XYRT")));
            % 以前の設定の XYRT（方位角 T）は除き、何も残らなければ X,Y,半径 にする
            legacy.featureSets = ["XY", "XYRT"];
            testCase.verifyEqual(alignest.completeMethodSettings(legacy).featureSets, "XY");
            legacy.featureSets = "XYRT";
            testCase.verifyEqual(alignest.completeMethodSettings(legacy).featureSets, "XYR");
            testCase.verifyError(@() alignest.basis.distanceFeatures(1, 1, 'XYRT', 150), 'alignest:featureSet');
        end

        function gamShapesSelectSplineOrGaussianProcess(testCase)
            unit = testCase.Data.units(1);
            marks = unit.marks;
            points = struct("x", marks.x / 150, "y", marks.y / 150, "r", marks.r / 150);
            train = (1:2:numel(marks.x)).';
            test = (2:2:numel(marks.x)).';
            pick = @(index) structfun(@(values) values(index), points, 'UniformOutput', false);
            nBasis = struct("axis", 8, "radius", 8);
            % 滑らかな関数（X・Y の項と半径の項）にガウス過程の形状関数を当てはめる
            truth = @(p) 3 * sin(2 * p.x) .* cos(1.5 * p.y) + 4 * p.r .^ 2;
            y = truth(pick(train));
            empty = zeros(numel(train), 0);
            emptyTest = zeros(numel(test), 0);
            setup = @(scales) alignest.models.gamSetup(pick(train), pick(test), "XYR", empty, emptyTest, nBasis, ...
                shapes=struct("xy", "gp", "r", "gp"), lengthScales=scales);
            candidates = [0.15, 0.3, 0.6];
            result = alignest.models.gamShapeFit(setup, ["xy", "r"], candidates, y);
            testCase.verifyLessThan(sqrt(mean((result.prediction - truth(pick(test))) .^ 2)), 0.05);
            testCase.verifyEqual(result.nFits, 1 + 2 * 2);
            testCase.verifyTrue(all(ismember(cell2mat(struct2cell(result.lengthScales)), candidates)));
            model = setup(result.lengthScales);
            testCase.verifyEqual(model.shapes, ["gp", "gp"]);
            testCase.verifyTrue(isfinite(model.logPseudoDetPenalty));
            % ガウス過程の項が無ければ、スプラインだけの GAM と同じ結果
            splineSetup = @(~) alignest.models.gamSetup(pick(train), pick(test), "XYR", empty, emptyTest, nBasis);
            plain = alignest.models.gamFitPredict(splineSetup([]), y);
            viaShapes = alignest.models.gamShapeFit(splineSetup, strings(1, 0), candidates, y);
            testCase.verifyEqual(viaShapes.prediction, plain.prediction);
            testCase.verifyEqual(viaShapes.nFits, 1);
            testCase.verifyError(@() alignest.models.gamSetup(pick(train), pick(test), "XY", empty, emptyTest, nBasis, ...
                shapes=struct("xy", "kriging")), 'alignest:gamShape');
            % 推定の流れでも使え、選んだ長さスケールが超パラメータに残る
            settings = alignest.defaultSettings();
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.gam.enabled = true;
            settings.methods.gam.shapes.r = "gp";
            method = alignest.buildMethodList(settings.methods);
            testCase.verifyEqual(method.id, "GAM_XYR_gp-r");
            out = alignest.estimateWafer(unit, 1:3:numel(unit.shots.shotNo), method, settings);
            testCase.verifyTrue(all(isfinite([out.estimate.X; out.estimate.Y])));
            testCase.verifyTrue(all(isfield(out.extra, ["gpLength_r_X", "gpLength_r_Y"])));
        end
    end
end
