classdef TestPlanTimeAndRadius < matlab.unittest.TestCase
    %TESTPLANTIMEANDRADIUS 計測マップの表示の切り替え（描いた図だけ描き直す）、時間の目安に学習パターンを作る時間を含める、
    %   Mark 単位の計画の必ず計測する Shot・Mark（設定タブの欄）と同心円の区切り（Mark の半径のバランス）、
    %   「8. Mark配置の最適化」の採用した I 最適計画の式。

    properties
        Data
        Root
    end

    methods (TestClassSetup)
        function loadSample(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.Root);
            raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            testCase.Data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
        end
    end

    methods (Test)
        function checkboxesRedrawOnlyDrawnMap(testCase)
            % 「Scan 方向を色で示す」「同心円の区切りを描く」は、計測マップを作っていなければ何もしない（学習パターンも
            % 作らない）。描いてあれば描き直す
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            settings.sampling.nShots = 20;
            settings.sampling.exchangeStarts = 2;
            app.setSettings(settings);
            c = app.Controls;
            c.measureScan.Value = false;
            c.measureScan.ValueChangedFcn([], []);
            c.measureRings.Value = false;
            c.measureRings.ValueChangedFcn([], []);
            testCase.verifyEmpty(app.Controls.measureAxes, "ボタンを押すまで計測マップは作らない");
            testCase.verifyTrue(isempty(app.MeasurementCache) || app.MeasurementCache.Count == 0, "学習パターンも作らない");
            app.drawMeasurementMap(1);
            ax = app.Controls.measureAxes(1);
            testCase.verifyEmpty(findall(ax, 'Type', 'line', 'LineStyle', '-.'), "区切りを描かない");
            c.measureRings.Value = true;
            c.measureRings.ValueChangedFcn([], []);
            ax = app.Controls.measureAxes(1);
            testCase.verifyNotEmpty(findall(ax, 'Type', 'line', 'LineStyle', '-.'), "描いた図を区切り付きで描き直す");
        end

        function estimateIncludesPlanTime(testCase)
            % 時間の目安 = 推定の時間 + 学習パターンを作る時間（交換法の I 最適・D 最適。配置の種類ごとに1回）
            units = testCase.Data.units;
            settings = alignest.defaultSettings();
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.sampling.method = "mark";
            settings.sampling.exchangeStarts = 4;
            [seconds, detail] = alignest.estimateRunSeconds(units, settings);
            keys = arrayfun(@(unit) string(alignest.planLayoutKey(unit)), units);
            testCase.verifyEqual(detail.nLayouts, numel(unique(keys)));
            shots = units(1).shots;
            candidateShots = find(shots.nValidX + shots.nValidY > 0);
            nCandidateMarks = nnz(ismember(units(1).marks.shotIndex, candidateShots) & ...
                (units(1).marks.validX | units(1).marks.validY));
            nMarks = round(settings.sampling.markPerShot(1) * numel(candidateShots));
            testCase.verifyEqual(detail.planSecondsEach(1), 0.013 * nMarks * 4 * nCandidateMarks / 396, 'AbsTol', 1e-9, ...
                "Mark 単位：初期配置 1 つ・Mark 1 点あたり約 0.013 秒");
            testCase.verifyEqual(seconds, detail.estimateSeconds + detail.planSeconds, 'AbsTol', 1e-9);
            testCase.verifyGreaterThan(detail.planSeconds, 0);
            % 値の無い Mark が違う Wafer は、学習パターンを作り直すので時間が増える
            changed = units;
            changed(2).marks.validX(3) = false;
            changed(2).marks.validY(3) = false;
            [~, more] = alignest.estimateRunSeconds(changed, settings);
            testCase.verifyEqual(more.nLayouts, detail.nLayouts + 1);
            testCase.verifyGreaterThan(more.planSeconds, detail.planSeconds);
            % Shot 単位の I 最適は exchangeSecondsGuide、ランダムは 0
            settings.sampling.method = ["ioptimal", "random"];
            settings.sampling.nShots = 20;
            [~, shotDetail] = alignest.estimateRunSeconds(units, settings);
            testCase.verifyEqual(shotDetail.planSecondsEach(1), ...
                alignest.exchangeSecondsGuide(20, 4, numel(candidateShots)), 'AbsTol', 1e-12);
            testCase.verifyEqual(shotDetail.planSecondsEach(2:end), zeros(1, numel(shotDetail.planSecondsEach) - 1));
        end

        function markPlanRequiredShotsAndRadiusZones(testCase)
            % Mark 単位の計画：必ず計測する Shot の Mark はすべて計測する。同心円の区切りで、区画（Mark の半径）ごとの数を
            % 割合 × Mark の数 ± 許容幅にそろえる
            unit = testCase.Data.units(1);
            sampling = alignest.defaultSettings().sampling;
            sampling.method = "mark";
            sampling.exchangeStarts = 2;
            sampling.requiredShots = 40;
            sampling.requiredMarks = "50-2";
            spec = alignest.buildPlanSpecs(sampling);
            plan = alignest.planTrainingShots(unit, spec, sampling, 150);
            marks = unit.marks;
            shot40 = find(marks.shotNo == 40 & (marks.validX | marks.validY));
            testCase.verifyTrue(all(ismember(shot40, plan.markIndex)), "Shot 40 の Mark すべて");
            testCase.verifyEqual(unit.shots.shotNo(plan.requiredShotIndex), 40);
            testCase.verifyEqual(plan.violation, 0);
            edges = alignest.zoneEdgesMm(sampling, 150);
            radius = hypot(marks.x, marks.y);
            zoneOf = 1 + sum(radius >= edges, 2);
            candidates = find(marks.validX | marks.validY);
            share = accumarray(zoneOf(candidates), 1, [numel(edges) + 1, 1]) / numel(candidates);
            counts = accumarray(zoneOf(plan.markIndex), 1, [numel(edges) + 1, 1]);
            testCase.verifyLessThanOrEqual(abs(counts - share * plan.nMarks), sampling.constraints.slack + 1, ...
                "区画ごとの数は 割合 × Mark の数 ± 許容幅（丸めの分 1）");
            % Mark 番号ごとの数を均等にするときも、同心円の区画と一緒にそろえる
            sampling.constraints.markEqual = true;
            plan = alignest.planTrainingShots(unit, spec, sampling, 150);
            testCase.verifyEqual(plan.violation, 0);
            perMarkNo = accumarray(marks.markNo(plan.markIndex), 1);
            perMarkNo = perMarkNo(perMarkNo > 0);
            testCase.verifyLessThanOrEqual(max(perMarkNo) - min(perMarkNo), 1, "Mark 番号ごとの数の差は1以下");
            counts = accumarray(zoneOf(plan.markIndex), 1, [numel(edges) + 1, 1]);
            testCase.verifyLessThanOrEqual(abs(counts - share * plan.nMarks), sampling.constraints.slack + 1);
            % 最外周の Shot を必ず計測：その Mark をすべて必ず計測する。計測しない Shot は除く
            sampling.requireOuterShots = true;
            sampling.excludedShots = 40;
            [fixedMarks, details] = alignest.markPlanFixedMarks(unit, sampling);
            outer = find(alignest.outerShots(unit.shots));
            testCase.verifyFalse(ismember(find(unit.shots.shotNo == 40), details.requiredShots));
            outerMarks = find(ismember(marks.shotIndex, setdiff(outer, find(unit.shots.shotNo == 40))) & ...
                (marks.validX | marks.validY));
            testCase.verifyTrue(all(ismember(outerMarks, fixedMarks)));
            testCase.verifyTrue(ismember(details.center, fixedMarks), "Wafer 中心に最も近い Mark");
        end

        function settingsTabMarkSelections(testCase)
            % 設定タブ：Mark 単位の計画を選ぶと、必ず計測する Shot・Mark、計測しない Mark、同心円の区切りの欄が使える
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            settings = app.Settings;
            settings.sampling.method = "mark";
            settings.sampling.exchangeStarts = 2;
            app.setSettings(settings);
            c = app.Controls;
            testCase.verifyEqual(string({c.requiredShots.Enable, c.requireOuter.Enable, c.requiredMarks.Enable, ...
                c.excludedMarks.Enable, c.zoneEdges.Enable, c.quadrants.Enable}), ["on", "on", "on", "on", "on", "off"]);
            c.requiredMarks.Value = '12-3 ４０－１, 12-3';
            c.requiredMarks.ValueChangedFcn([], []);
            testCase.verifyEqual(app.Settings.sampling.requiredMarks, ["12-3", "40-1"], "全角・重なりも読む");
            testCase.verifyTrue(contains(string(c.requiredInfo.Text), "Mark 単位の計画では Mark"));
            c.excludedMarks.Value = '12_3';
            c.excludedMarks.ValueChangedFcn([], []);
            testCase.verifyTrue(contains(string(c.requiredError.Text), "shotNo-markNo"));
            testCase.verifyEmpty(app.Settings.sampling.excludedMarks, "正しくないときは前の値のまま");
            c.excludedMarks.Value = '';
            c.excludedMarks.ValueChangedFcn([], []);
            % 計測マップのクリックで指定した Mark は設定タブの欄にも出る
            app.setMeasurementSelection("mark", "60-1", "excluded");
            testCase.verifyEqual(string(c.excludedMarks.Value), "60-1");
            % 時間の目安に学習パターンを作る時間が入る
            testCase.verifyTrue(contains(string(c.countLabel.Text), "うち学習パターンを作る時間"));
            testCase.verifyTrue(contains(string(c.exchangeInfo.Text), "学習パターン1つ"));
            settings = app.Settings;
            settings.sampling.method = "ioptimal";
            app.setSettings(settings);
            testCase.verifyEqual(string({c.requiredMarks.Enable, c.quadrants.Enable}), ["off", "on"]);
        end

        function markLayoutCriterionShowsFormula(testCase)
            % 「8. Mark配置の最適化」：配置を選んだ I 最適計画の式と、F の列に使った項・点の数
            [gx, gy] = meshgrid(linspace(-12, 12, 5), linspace(-15, 15, 5));
            [candidates, shots] = alignest.markCandidates([], [gx(:), gy(:)], [0, 0]);
            settings = alignest.defaultSettings();
            settings.markLayout = struct("maker", "canon", "loss", "ols", "regularization", "none", "minMarks", 8, ...
                "maxMarks", 9, "values", "random", "shapes", 5);
            study = alignest.markLayoutStudy(candidates, shots, settings);
            rows = alignest.markLayoutCriterion(study);
            testCase.verifyEqual(size(rows, 2), 2);
            testCase.verifyTrue(contains(rows(1, 2), "I(S) = Σ trace(M_S⁻¹ W)"));
            testCase.verifyTrue(contains(rows(rows(:, 1) == "W", 2), "N = 25"));
            dxRow = rows(rows(:, 1) == "F の列（dx の式）", 2);
            testCase.verifyTrue(startsWith(dxRow, "8 項：k1（1）"));
            testCase.verifyTrue(contains(rows(rows(:, 1) == "必ず計測・計測しない", 2), "必ず計測する Mark 1 点"));
        end
    end
end
