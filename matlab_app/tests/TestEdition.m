classdef TestEdition < matlab.unittest.TestCase
    %TESTEDITION 通常版（比べる手法・計測点の選び方・Overlay の式を絞った版）と Pro 版の違いを確かめる。

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
        function standardSettingsDropProOptions(testCase)
            % 通常版：Pro 版だけの手法・計測点の選び方・Overlay の式を外し、外した項目を返す。Pro 版はそのまま
            settings = alignest.defaultSettings();
            settings.methods = alignest.recommendedMethods("all");
            settings.methods.gam.enabled = true;
            settings.methods.kriging.ordinary = true;
            settings.sampling.method = ["ioptimal", "doptimal", "sobol", "random", "excel"];
            settings.overlay.waferUseFormula = true;
            settings.overlay.shotCommon = "formula";
            settings.overlay.perShot = "formula";
            [pro, proChanges] = alignest.editionSettings(settings, "pro");
            testCase.verifyEqual(pro, settings);
            testCase.verifyEmpty(proChanges);
            [standard, changes] = alignest.editionSettings(settings, "standard");
            m = standard.methods;
            testCase.verifyFalse(any([m.rbf.enabled, m.kriging.ordinary, m.kriging.universal, m.gam.enabled, ...
                m.rt.enabled, m.zernike.enabled]), "Pro 版だけの手法は使わない");
            testCase.verifyTrue(all([m.gpr.enabled, m.tps.enabled, m.polynomial.enabled]), "GPR・TPS・XY 多項式はそのまま");
            testCase.verifyEqual(m.gpr.kernels, settings.methods.gpr.kernels);
            testCase.verifyEqual(standard.sampling.method, ["ioptimal", "random"]);
            testCase.verifyEqual(standard.sampling.unit, "shot");
            testCase.verifyEmpty(standard.sampling.layoutPlans);
            testCase.verifyFalse(standard.overlay.waferUseFormula);
            testCase.verifyEqual([standard.overlay.shotCommon, standard.overlay.perShot], ["none", "linear"]);
            testCase.verifyEqual(numel(changes), 3, "手法・計測点の選び方・Overlay の式");
            testCase.verifyTrue(contains(changes(2), "D 最適") && contains(changes(2), "Excel 取込"));
            testCase.verifyEqual(alignest.editionSettings(standard, "standard"), standard, "直した設定はそのまま");
            % Mark 単位は同じアルゴリズムの Shot 単位にし、残らなければ I 最適
            settings.sampling.unit = "mark";
            settings.sampling.method = ["markrandom", "markd"];
            [standard, changes] = alignest.editionSettings(settings, "standard");
            testCase.verifyEqual(standard.sampling.method, "random");
            testCase.verifyTrue(any(contains(changes, "Mark 単位 → Shot 単位")));
            settings.sampling.method = "sobol";
            testCase.verifyEqual(alignest.editionSettings(settings, "standard").sampling.method, "ioptimal");
        end

        function standardAppBuildsFewerSettings(testCase)
            % 通常版の画面：Pro 版だけの手法の欄を作らず、選べる計測点の選び方・Overlay の成分も絞る。評価はそのまま使える
            pro = AlignmentEstimationApp(false, true);
            cleanupPro = onCleanup(@() delete(pro));
            app = AlignmentEstimationApp(false, false, "standard");
            cleanup = onCleanup(@() delete(app));
            testCase.verifyEqual(app.Edition, "standard");
            testCase.verifyEqual(pro.Edition, "pro", "版を指定しなければ Pro 版");
            testCase.verifyTrue(contains(string(app.Figure.Name), "通常版"));
            c = app.Controls;
            testCase.verifyFalse(any(isfield(c, ["rbf", "gam", "gamShapeChecks", "ordinaryKriging", "universalKriging", ...
                "variograms", "rt", "zernike"])), "Pro 版だけの手法の欄は作らない");
            testCase.verifyTrue(all(isfield(pro.Controls, ["rbf", "gam", "ordinaryKriging", "rt", "zernike"])));
            testCase.verifyLessThan(numel(findall(app.Tabs.settings)), numel(findall(pro.Tabs.settings)), ...
                "設定のタブの部品が少ない（起動が速い）");
            testCase.verifyEqual(string(c.samplingMethod.ItemsData), ["ioptimal", "random"]);
            testCase.verifyEqual(string(c.samplingUnit.ItemsData), "shot");
            for item = [c.overlayWafer, c.overlayShotCommon, c.overlayPerShot, c.targetOverlayWafer, ...
                    c.targetOverlayShotCommon, c.targetOverlayPerShot]
                testCase.verifyFalse(any(strcmp(item.Items, '式を入力')), "Overlay の式は Pro 版だけ");
            end
            % Pro 版の設定を読み込むと、使える設定に直して知らせる
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("all");
            settings.sampling.method = ["ioptimal", "poisson"];
            changes = app.setSettings(settings);
            testCase.verifyNotEmpty(changes);
            testCase.verifyFalse(app.Settings.methods.rbf.enabled);
            testCase.verifyEqual(app.Settings.sampling.method, "ioptimal");
            testCase.verifyEqual(string(c.samplingMethod.Value), "ioptimal");
            testCase.verifyError(@() app.loadLayoutPlans(fullfile(testCase.Root, 'sample_data', 'sample_targets.xlsx')), ...
                'alignest:edition', "Excel 取込は Pro 版だけ");
            % 評価はそのまま使える（GPR・TPS・XY 多項式とランダム）
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.sampling.method = "random";
            settings.sampling.nShots = 20;
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(20, 20, 5);
            testCase.verifyEmpty(app.setSettings(settings), "通常版で使える設定は直さない");
            results = app.runEvaluationNow(false);
            testCase.verifyEqual(string({results.methods.family}), "XY", "XY 多項式");
            testCase.verifyNotEmpty(app.Controls.summaryTable.Data);
            testCase.verifyError(@() AlignmentEstimationApp(false, false, "lite"), 'alignest:edition');
        end
    end
end
