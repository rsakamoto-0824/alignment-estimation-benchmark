classdef TestMarkLayout < matlab.unittest.TestCase
    %TESTMARKLAYOUT 「8. Mark配置の最適化」：I 最適計画の配置（総当たりの最適と同じ・必ず計測する Mark）、乱数の Shot の形
    %   （同じ種なら同じ・飛び値の割合と大きさ）、制御残差（Shot ごとに当てはめたときと同じ・値の無い Mark）、候補の Mark・
    %   Excel・CSV の入力、最低数・最大数、画面（入力・必ず計測・計算・図・配置・表・書き出し・設定の読み込み）。

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
        function iOptimalMatchesExhaustiveSearch(testCase)
            % 小さな問題では、交換法の配置が総当たりで最も I の小さい配置と同じ。必ず計測する Mark はどの数にも入り、
            % すべての候補を計測したときの I 効率は 100%
            [gx, gy] = meshgrid(-2:2, -1:1);
            x = gx(:);
            y = gy(:);
            designs = {[ones(15, 1), x, y, x .^ 2], [ones(15, 1), x, y, y .^ 2, x .* y]};
            required = false(15, 1);
            required(8) = true;   % 中央
            layouts = alignest.iOptimalMarks(designs, required, 5:7, starts=3);
            testCase.verifyEqual(layouts.counts, (5:7).');
            testCase.verifyTrue(all(layouts.selected(8, :)), "必ず計測する Mark はどの数にも入る");
            testCase.verifyEqual(sum(layouts.selected, 1), 5:7);
            W = cellfun(@(F) F.' * F / 15, designs, 'UniformOutput', false);
            criterion = @(rows) trace((designs{1}(rows, :).' * designs{1}(rows, :)) \ W{1}) + ...
                trace((designs{2}(rows, :).' * designs{2}(rows, :)) \ W{2});
            for k = 1:3
                count = layouts.counts(k);
                others = setdiff(1:15, 8);
                combos = nchoosek(others, count - 1);
                best = Inf;
                for r = 1:size(combos, 1)
                    rows = [8, combos(r, :)];
                    M = designs{2}(rows, :).' * designs{2}(rows, :);
                    if rcond(M) > 1e-12 && rcond(designs{1}(rows, :).' * designs{1}(rows, :)) > 1e-12
                        best = min(best, criterion(rows));
                    end
                end
                testCase.verifyEqual(layouts.criterion(k), best, 'RelTol', 1e-6, sprintf("%d 点の配置が最適", count));
                testCase.verifyEqual(layouts.efficiency(k), 100 * (4 + 5) / 15 / best, 'RelTol', 1e-6);
            end
            all15 = alignest.iOptimalMarks(designs, required, 15);
            testCase.verifyEqual(all15.efficiency, 100, 'AbsTol', 1e-6);
            testCase.verifyError(@() alignest.iOptimalMarks(designs, true(15, 1), 5), 'alignest:markLayout', ...
                "必ず計測する Mark より少ない数");
        end

        function randomShapesAreReproducible(testCase)
            % 同じ種なら同じ形。飛び値の割合を変えても形とばらつきは同じ。飛び値は決めた数・大きさ（向きは乱数）
            [gx, gy] = meshgrid(linspace(-12, 12, 7), linspace(-15, 15, 11));
            x = gx(:);
            y = gy(:);
            a = alignest.randomShotShapes(x, y, shapes=20, seed=3, noiseNm=0.5);
            b = alignest.randomShotShapes(x, y, shapes=20, seed=3, noiseNm=0.5, outlierPercent=10, outlierNm=8);
            c = alignest.randomShotShapes(x, y, shapes=5, seed=3, noiseNm=0.5);
            testCase.verifyEqual(a.trueX, b.trueX);
            testCase.verifyEqual(c.trueY, a.trueY(:, 1:5), "形の数を変えても同じ番号の形は同じ");
            testCase.verifyEqual(sum(b.outlier, 1), repmat(round(77 * 0.1), 1, 20));
            jump = hypot(b.measuredX - a.measuredX, b.measuredY - a.measuredY);
            testCase.verifyEqual(jump(b.outlier), repmat(8, nnz(b.outlier), 1), 'AbsTol', 1e-9);
            testCase.verifyEqual(jump(~b.outlier), zeros(nnz(~b.outlier), 1), 'AbsTol', 1e-12);
            testCase.verifyEqual(a.halfSizeMm, [12, 15]);
            % 大きさ：1次だけ（u・v）なら、形は端で係数の大きさ
            d = alignest.randomShotShapes(x, y, shapes=200, seed=1, orderSigmaNm=[0, 2, 0, 0, 0, 0, 0, 0], noiseNm=0);
            corner = x == 12 & y == 15;
            testCase.verifyEqual(std(d.trueX(corner, :)), sqrt(5), 'RelTol', 0.15, "選ばれる項の数の平均は 1.25");
            testCase.verifyTrue(all(any(d.coefficientsX ~= 0, 1)), "どの形にも項がある");
            testCase.verifyTrue(all(d.coefficientsX(d.powers(:, 1) + d.powers(:, 2) ~= 1, :) == 0, 'all'), "大きさ 0 の次数は使わない");
            testCase.verifyTrue(any(sum(d.coefficientsX ~= 0, 1) == 1) && any(sum(d.coefficientsX ~= 0, 1) == 2), "項を乱数で選ぶ");
            [fieldX, ~] = alignest.randomShapeField(a, 3, x, y);
            testCase.verifyEqual(fieldX, a.trueX(:, 3), 'AbsTol', 1e-9, "ヒートマップは形と同じ値");
            seven = alignest.randomShotShapes(x, y, shapes=5, seed=1, orderSigmaNm=[0, 0, 0, 0, 0, 0, 0, 1]);
            testCase.verifyEqual(unique(sum(seven.powers, 2)).', 0:7, "7次まで");
            testCase.verifyEqual(d.measuredX, d.trueX);
        end

        function evaluationMatchesShotByShotFit(testCase)
            % 最小二乗のまとめた計算は Shot ごとに当てはめたときと同じ。値の無い Mark があって決まらない Shot は補正しない
            [gx, gy] = meshgrid(linspace(-12, 12, 5), linspace(-15, 15, 5));
            x = gx(:);
            y = gy(:);
            A = [ones(25, 1), x, y, x .* y];
            designs = {A, A};
            rng(4);
            values = randn(25, 6);
            values(3, 2) = NaN;              % 2つ目の Shot：Mark 3 の値が無い（ほかの Mark で当てはめる）
            values([1, 5, 21], 3) = NaN;     % 3つ目の Shot：角が足りず x·y が決まらない Mark の組がある
            selected = false(25, 2);
            selected([1, 5, 21, 25, 13], 1) = true;
            selected(:, 2) = true;
            data = struct("fitX", values, "fitY", values, "referenceX", values, "referenceY", values);
            penalized = {false(4, 1), false(4, 1)};
            evaluation = alignest.evaluateMarkLayouts(designs, selected, data, penalized, {'loss', "ols", ...
                'huberTuning', 1.345, 'lambda', 0, 'penalty', "l2"});
            testCase.verifyEqual(height(evaluation), 4);
            first = evaluation(evaluation.layout == 1 & evaluation.axis == "X", :);
            testCase.verifyEqual(first.skipped, 1, "3つ目の Shot は決まらない");
            residual = [];
            for s = [1, 2, 4, 5, 6]
                use = selected(:, 1) & isfinite(values(:, s));
                coefficients = A(use, :) \ values(use, s);
                r = values(:, s) - A * coefficients;
                residual = [residual; r(isfinite(r))]; %#ok<AGROW>
            end
            testCase.verifyEqual(first.meanPlus3Sigma, abs(mean(residual)) + 3 * std(residual), 'RelTol', 1e-9);
            testCase.verifyEqual(first.nPoints, numel(residual));
            % Huber でも求められる（すべての Mark を計測したときは、残差が当てはめた残差）
            robust = alignest.evaluateMarkLayouts(designs, selected, data, penalized, {'loss', "huber", ...
                'huberTuning', 1.345, 'lambda', 0, 'penalty', "l2"});
            testCase.verifyEqual(robust.nShots(robust.layout == 2 & robust.axis == "X"), 6);
            testCase.verifyTrue(all(isfinite(robust.meanPlus3Sigma)));
        end

        function candidatesAndFileInput(testCase)
            % 計測データの点から候補の Mark（上の行・左から番号。同じ位置はまとめる）と Shot ごとの値。Excel・CSV は座標だけの
            % 表も読め、Shot を分けられない表・X だけの値は誤り
            points = table([1; 1; 1; 2; 2; 2], [-1; 1; 1; -1; 1; 0], [0; 2; 2; 0; 2; 0], [5; 6; 8; NaN; 2; 3], ...
                [1; 1; 1; 1; 1; 1], 'VariableNames', ["shotNo", "localX", "localY", "valueX", "valueY"]);
            [candidates, shots] = alignest.markCandidates(struct("label", "W1", "points", points), zeros(0, 2), [1, 2]);
            testCase.verifyEqual([candidates.xMm, candidates.yMm], [1, 2; -1, 0; 0, 0]);
            testCase.verifyEqual(candidates.required.', [true, false, false]);
            testCase.verifyEqual(shots.label, ["W1 Shot 1"; "W1 Shot 2"]);
            testCase.verifyEqual(shots.valueX, [7, 2; 5, NaN; NaN, 3], "同じ位置は平均。値の無い点は NaN");
            testCase.verifyEqual(candidates.nShots.', [2, 2, 1]);
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's'));
            coordinatesFile = fullfile(folder, 'marks.csv');
            writetable(table([-10; 0; 10; 0], [0; 0; 0; 12], 'VariableNames', ["markX", "markY"]), coordinatesFile);
            [raw, info] = alignest.readHighOrderFile(coordinatesFile);
            [wafers, coordinates, dataInfo] = alignest.markLayoutFileData(raw, info.mapping);
            testCase.verifyEmpty(wafers);
            testCase.verifyEqual(coordinates, [-10, 0; 0, 0; 10, 0; 0, 12]);
            testCase.verifyFalse(dataInfo.hasValues);
            valueFile = fullfile(folder, 'values.csv');
            writetable(table(["A"; "A"; "A"; "A"], [1; 1; 2; 2], [-10; 10; -10; 10], [0; 0; 0; 0], [1; 2; 3; 4], ...
                [0; 0; 1; 1], 'VariableNames', ["Wafer", "shotNo", "markX", "markY", "dx", "dy"]), valueFile);
            [raw, info] = alignest.readHighOrderFile(valueFile);
            [wafers, ~, dataInfo] = alignest.markLayoutFileData(raw, info.mapping);
            testCase.verifyEqual([dataInfo.wafers, dataInfo.shots], [1, 2]);
            testCase.verifyEqual(wafers(1).points.valueX, [1; 2; 3; 4]);
            noShot = info.mapping;
            noShot.shotNo = "";
            testCase.verifyError(@() alignest.markLayoutFileData(raw, noShot), 'alignest:markLayoutFile', ...
                "Shot を分けられない");
            onlyX = info.mapping;
            onlyX.measY = "";
            testCase.verifyError(@() alignest.markLayoutFileData(raw, onlyX), 'alignest:markLayoutFile');
        end

        function studyChecksCountsAndValues(testCase)
            % 最低数は使う項・必ず計測する Mark の数より少なくしない（知らせる）。座標だけで実測値は使えない。設定の誤り
            [gx, gy] = meshgrid(linspace(-12, 12, 5), linspace(-15, 15, 5));
            [candidates, shots] = alignest.markCandidates([], [gx(:), gy(:)], [0, 0]);
            settings = alignest.defaultSettings();
            settings.markLayout = struct("maker", "canon", "loss", "ols", "regularization", "none", "minMarks", 3, ...
                "maxMarks", 10, "values", "random", "shapes", 10);
            study = alignest.markLayoutStudy(candidates, shots, settings);
            testCase.verifyEqual(study.nTerms, [8, 8]);
            testCase.verifyEqual(study.counts, (8:10).');
            testCase.verifyTrue(any(contains(study.messages, "最低数を 8 にしました")));
            testCase.verifyEqual(study.evaluation.count(end), 25, "最後はすべての Mark");
            testCase.verifyEqual(study.evaluation.efficiency(end), 100);
            testCase.verifyTrue(all(study.layouts.selected(candidates.xMm == 0 & candidates.yMm == 0, :)));
            settings.markLayout.values = "measured";
            testCase.verifyError(@() alignest.markLayoutStudy(candidates, shots, settings), 'alignest:markLayout');
            broken = alignest.defaultSettings();
            broken.markLayout.shapes = 1001;
            testCase.verifyError(@() alignest.markLayoutOptions(broken), 'alignest:markLayout');
            broken = alignest.defaultSettings();
            broken.markLayout.orderSigmaNm = [1, 2];
            testCase.verifyError(@() alignest.markLayoutOptions(broken), 'alignest:markLayout');
            % 候補が一直線では 2次元の項が決まらない
            [line, lineShots] = alignest.markCandidates([], [(-5:5).', zeros(11, 1)]);
            testCase.verifyError(@() alignest.markLayoutStudy(line, lineShots, settings), 'alignest:markLayout');
        end

        function screenOptimizesAndExports(testCase)
            % 画面：格子で置く・必ず計測・計算・図・配置・表・書き出し、計測データの入力、設定を変えた後の知らせ、設定の読み込み
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual(app.Tabs.markLayout.Title, '8. Mark配置の最適化');
            testCase.verifyFalse(isfield(app.Tabs, 'help'), "ヘルプはメニュー");
            testCase.verifyTrue(startsWith(string(c.markOptInputInfo.Text), "⚠"), "座標が無いと知らせる");
            candidates = app.makeMarkLayoutGrid([24, 30], [5, 7]);
            testCase.verifyEqual(height(candidates), 35);
            testCase.verifyEqual(string(c.markOptValues.Value), "random", "座標だけなら乱数の形");
            candidates = app.setMarkLayoutRequired([1, 18], true);
            testCase.verifyEqual(find(candidates.required).', [1, 18]);
            testCase.verifyEqual(c.markOptCandidateTable.Data{18, 5}, true);
            app.setMarkLayoutSettings(maker="canon", loss="ols", regularization="none", maxMarks=12, shapes=20, ...
                outlierPercent=5);
            testCase.verifyEqual(app.Settings.markLayout.outlierPercent, 5);
            testCase.verifyError(@() app.optimizeMarkLayout(), 'alignest:markLayoutShapes', "生成の前は計算しない");
            generated = app.generateMarkLayoutShapes();
            testCase.verifyEqual(c.markOptShapeIndex.Value, generated.representative);
            testCase.verifyEqual(c.markOptOutputs.SelectedTab, c.markOptShapeTab);
            testCase.verifyNotEmpty(findobj(c.markOptShapeAxes(2), 'Type', 'image'), "X 成分のヒートマップ");
            testCase.verifyNotEmpty(findobj(c.markOptShapeAxes(3), 'Type', 'image'), "Y 成分のヒートマップ");
            testCase.verifyNotEmpty(findobj(c.markOptShapeAxes(1), 'Type', 'quiver'), "ベクトル場");
            study = app.optimizeMarkLayout();
            testCase.verifyEqual(study.shapes.trueX, generated.trueX, "生成した形で評価する");
            testCase.verifyEqual(study.counts, (8:12).');
            testCase.verifyEqual(numel(findobj(c.markOptChartAxes, 'Type', 'line')), 4, "X・Y の線と ★ 2つ");
            testCase.verifyEqual(height(c.markOptResultTable.Data), 6);
            testCase.verifyTrue(startsWith(string(c.markOptCriterion.Value{1}), "採用した式：I(S) = Σ trace(M_S⁻¹ W)"), ...
                "配置を選んだ I 最適計画の式");
            testCase.verifyTrue(any(contains(string(c.markOptMessage.Value), "「I 最適の式」タブ")));
            testCase.verifyEqual(c.markOptMapCount.Value, 8);
            app.drawMarkLayoutMap(10);
            testCase.verifyTrue(startsWith(string(c.markOptMapInfo.Text), "計測する Mark："));
            testCase.verifyEqual(numel(findobj(c.markOptMapAxes, 'Type', 'scatter')), 3);
            data = app.drawMarkLayoutChart("p95", "unmeasured");
            testCase.verifyEqual(data.count, (8:12).');
            testCase.verifyGreaterThan(app.drawMarkLayoutShape(2).count, 1);
            file = [tempname, '.xlsx'];
            app.exportMarkLayoutTo(file);
            fileCleanup = onCleanup(@() delete(file));
            testCase.verifyEqual(string(sheetnames(file)).', ["説明", "制御残差", "配置", "候補のMark", "項とVIF"]);
            layout = readtable(file, 'Sheet', '配置', 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(height(layout), sum(8:12));
            explanation = readtable(file, 'Sheet', '説明', 'VariableNamingRule', 'preserve', 'TextType', 'string');
            testCase.verifyTrue(any(explanation.("項目") == "I 最適の式：採用した式"), "Excel にも I 最適計画の式");
            % 設定を変えた後は計算し直す知らせ
            app.setMarkLayoutSettings(maker="nikon");
            testCase.verifyTrue(startsWith(string(c.markOptChartInfo.Text), "⚠"));
            testCase.verifyTrue(any(startsWith(string(c.markOptMessage.Value), "⚠")));
            % VIF で選ぶ・すべての項を使う・項を外す
            app.selectMarkLayoutTermsByVif(2);
            testCase.verifyNotEmpty(app.Settings.markLayout.excludedTerms);
            app.useAllMarkLayoutTerms();
            app.setMarkLayoutTermUsed(13, false);
            testCase.verifyEqual(app.Settings.markLayout.excludedTerms, 13);
            testCase.verifyError(@() app.setMarkLayoutTermUsed(3, false), 'alignest:markLayout');
            % 計測データの入力（サンプルは Shot の角の 4 Mark）：VIF で決まる項にして、実測値で評価する
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            app.setMarkLayoutSource("data");
            input = app.MarkLayoutInput;
            testCase.verifyEqual(height(input.candidates), 4);
            testCase.verifyEqual(numel(input.shots.label), 99);
            app.setMarkLayoutSettings(maker="custom", values="measured", loss="huber", regularization="l2", ...
                maxMarks=0, minMarks=0);
            app.selectMarkLayoutTermsByVif(10);
            study = app.optimizeMarkLayout();
            testCase.verifyEqual(study.valueSource, "measured");
            testCase.verifyEqual(study.nShots, 99);
            testCase.verifyEqual(study.counts(end), 4);
            % 「7. の式を写す」・設定の読み込み
            app.setHighOrderSettings(maker="canon", lambda=0.3);
            app.copyHighOrderFormula();
            testCase.verifyEqual([string(c.markOptMaker.Value), app.Settings.markLayout.lambda], ["canon", "0.3"]);
            settings = alignest.loadSettings(string(jsonencode(struct("markLayout", struct("coordinateXmm", [0, 5], ...
                "coordinateYmm", [0, 5], "requiredXmm", 5, "requiredYmm", 5, "shapes", 30)))), "text");
            testCase.verifyEqual(settings.markLayout.coordinateXmm, [0; 5]);
            app.setSettings(settings);
            testCase.verifyEqual(c.markOptShapes.Value, 30);
            app.setMarkLayoutSource("manual");
            testCase.verifyEqual(app.MarkLayoutInput.candidates.required.', [true, false], "上の行（Y = 5）から番号");
        end

        function screenReadsFileAndOtherTabs(testCase)
            % 画面：このタブで読む Excel・CSV（値あり・座標だけ）、「7. Shot高次補正」の入力、配置の図のクリックで必ず計測
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            folder = tempname;
            mkdir(folder);
            folderCleanup = onCleanup(@() rmdir(folder, 's'));
            [gx, gy] = meshgrid(-10:10:10, -12:12:12);
            n = numel(gx);
            file = fullfile(folder, 'shots.csv');
            writetable(table(repelem([1; 2], n), repmat(gx(:), 2, 1), repmat(gy(:), 2, 1), (1:2 * n).', ...
                -(1:2 * n).', 'VariableNames', ["shotNo", "markX", "markY", "dx", "dy"]), file);
            app.loadMarkLayoutFile(string(file));
            testCase.verifyEqual(string(c.markOptSource.Value), "file");
            testCase.verifyEqual(height(app.MarkLayoutInput.candidates), 9);
            testCase.verifyEqual(numel(app.MarkLayoutInput.shots.label), 2);
            testCase.verifyTrue(contains(string(c.markOptMappingStatus.Text), "2 Shot"));
            app.applyMarkLayoutMapping(struct("measX", "", "measY", ""));
            testCase.verifyEmpty(app.MarkLayoutInput.shots.label, "値の列を外すと座標だけ");
            testCase.verifyEqual(string(c.markOptValues.Value), "random");
            testCase.verifyError(@() app.applyMarkLayoutMapping(struct("markXmm", "")), 'alignest:markLayoutFile');
            % 配置の図の Mark をクリックすると、必ず計測が切り替わる
            app.applyMarkLayoutMapping(struct("markXmm", "markX"));
            app.drawMarkLayoutMap();
            markers = findobj(c.markOptMapAxes, 'Type', 'scatter');
            markers(end).ButtonDownFcn(markers(end), struct("IntersectionPoint", [9.5, 11.6, 0]));
            required = app.MarkLayoutInput.candidates.required;
            testCase.verifyEqual(find(required), 3, "右上（10, 12）の Mark");
            markers = findobj(c.markOptMapAxes, 'Type', 'scatter');
            markers(1).ButtonDownFcn(markers(1), struct("IntersectionPoint", [10, 12, 0]));
            testCase.verifyFalse(any(app.MarkLayoutInput.candidates.required), "もう一度で外れる");
            % 「7. Shot高次補正」の入力
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            app.setHighOrderSource("data");
            c.highOrderWafer.Value = {1, 2};
            app.setMarkLayoutSource("highOrder");
            testCase.verifyTrue(startsWith(string(c.markOptInputInfo.Text), "「7. Shot高次補正」の入力のデータ（2 Wafer）"));
            testCase.verifyEqual(numel(app.MarkLayoutInput.shots.label), 2 * 99, "2 Wafer の Shot");
        end

        function randomSeedIsInSettingsMenu(testCase)
            % 乱数の種はメニュー「設定」→「乱数の種…」の1つ（学習 Shot の選び方と Mark 配置の最適化で共通。タブの欄は無い）
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual(c.settingsMenu.Text, '設定');
            testCase.verifyEqual(c.randomSeedItem.Parent, c.settingsMenu);
            testCase.verifyFalse(isfield(c, 'seed') || isfield(c, 'markOptSeed'), "タブに乱数の種の欄は無い");
            testCase.verifyFalse(isfield(app.Settings.markLayout, "seed"));
            app.makeMarkLayoutGrid([24, 30], [5, 7]);
            app.setMarkLayoutSettings(values="random", shapes=3, maker="canon", loss="ols", maxMarks=9);
            app.generateMarkLayoutShapes();
            study = app.optimizeMarkLayout();
            app.setRandomSeed(7);
            testCase.verifyEqual(app.Settings.sampling.seed, 7);
            testCase.verifyTrue(contains(string(c.randomSeedItem.Text), "7"));
            testCase.verifyTrue(startsWith(string(c.markOptChartInfo.Text), "⚠"), "種を変えたら計算し直す知らせ");
            testCase.verifyError(@() app.optimizeMarkLayout(), 'alignest:markLayoutShapes', "種を変えたら生成し直す");
            app.generateMarkLayoutShapes();
            shapes = app.drawMarkLayoutShape(2);
            expected = alignest.randomShotShapes(app.MarkLayoutInput.candidates.xMm, app.MarkLayoutInput.candidates.yMm, ...
                shapes=2, seed=7, noiseNm=app.Settings.markLayout.noiseNm);
            testCase.verifyEqual(shapes.trueX(:, 1:2), expected.trueX, "図の形も同じ種");
            again = app.optimizeMarkLayout();
            testCase.verifyEqual(again.options.seed, 7);
            testCase.verifyNotEqual(again.evaluation.meanPlus3Sigma, study.evaluation.meanPlus3Sigma);
            testCase.verifyError(@() app.setRandomSeed(-1), 'alignest:randomSeed');
            testCase.verifyError(@() app.setRandomSeed(1.5), 'alignest:randomSeed');
            % 設定ファイルの種はメニューに出る。以前の markLayout.seed は読み飛ばす
            settings = alignest.loadSettings(string(jsonencode(struct("sampling", struct("seed", 42), ...
                "markLayout", struct("seed", 5)))), "text");
            app.setSettings(settings);
            testCase.verifyTrue(contains(string(c.randomSeedItem.Text), "42"));
            testCase.verifyEqual(alignest.markLayoutOptions(settings).seed, 42);
        end

        function stoppingDuringSearchShowsLayouts(testCase)
            % 配置を選ぶ途中で止めても、選んだ配置は表・配置の図・書き出しに出る（制御残差は無い）
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            app.makeMarkLayoutGrid([24, 30], [5, 7]);
            app.setMarkLayoutSettings(maker="canon", loss="ols", regularization="none", maxMarks=12, shapes=5);
            app.generateMarkLayoutShapes();
            study = app.optimizeMarkLayout(@(~, ~) false);
            testCase.verifyTrue(study.cancelled);
            testCase.verifyEqual(study.counts, 8);
            testCase.verifyEqual(height(study.evaluation), 0);
            testCase.verifyEqual(height(c.markOptResultTable.Data), 1);
            testCase.verifyEqual(c.markOptOutputs.SelectedTab, c.markOptMapTab);
            testCase.verifyTrue(contains(string(c.markOptChartInfo.Text), "途中で止めた"));
            file = [tempname, '.xlsx'];
            app.exportMarkLayoutTo(file);
            fileCleanup = onCleanup(@() delete(file));
            testCase.verifyEqual(string(sheetnames(file)).', ["説明", "配置", "候補のMark", "項とVIF"]);
        end

        function markLayoutSettingsDoNotBlockResume(testCase)
            % 「8. Mark配置の最適化」の設定を変えても、評価の続きから再開できる
            settings = alignest.defaultSettings();
            changed = settings;
            changed.markLayout.maxMarks = 12;
            testCase.verifyTrue(alignest.sameRunSettings(settings, changed));
        end

        function wrongSeedInSettingsIsRejected(testCase)
            % 使えない乱数の種の設定は読まない（今の設定のまま）。既定の設定ファイルはエラーにして、アプリは初期設定で開く
            for seed = [1.5, 2 ^ 32]
                text = string(jsonencode(struct("sampling", struct("seed", seed))));
                testCase.verifyError(@() alignest.loadSettings(text, "text"), 'alignest:randomSeed');
            end
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.setMarkLayoutSettings(shapes=33);
            settings = alignest.defaultSettings();
            settings.sampling.seed = 1.5;
            testCase.verifyError(@() app.setSettings(settings), 'alignest:randomSeed');
            testCase.verifyEqual(app.Settings.sampling.seed, alignest.defaultSettings().sampling.seed);
            testCase.verifyEqual(app.Settings.markLayout.shapes, 33, "読めなかった種で Mark 配置の設定を消さない");
        end

        function settingsWithoutMarkLayoutUseDefaults(testCase)
            % markLayout の無い以前の設定でも、「8. Mark配置の最適化」は初期値で動く
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            settings = rmfield(alignest.defaultSettings(), "markLayout");
            app.setSettings(settings);
            testCase.verifyEqual(app.Settings.markLayout, alignest.defaultSettings().markLayout);
            testCase.verifyEqual(height(app.makeMarkLayoutGrid([24, 30], [3, 3])), 9);
        end

        function measuredValuesReturnAfterCoordinateInput(testCase)
            % 座標だけの入力で自動で乱数にしたときは、値のある入力に戻すと実測値に戻る。自分で選んだ乱数は戻さない
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            app.setMarkLayoutSource("data");
            testCase.verifyEqual(string(c.markOptValues.Value), "measured");
            app.makeMarkLayoutGrid([24, 30], [5, 7]);
            testCase.verifyEqual(string(c.markOptValues.Value), "random", "座標だけなら乱数の形");
            app.setMarkLayoutSource("data");
            testCase.verifyEqual(string(c.markOptValues.Value), "measured");
            testCase.verifyEqual(app.Settings.markLayout.values, "measured");
            app.setMarkLayoutSettings(values="random");
            app.makeMarkLayoutGrid([24, 30], [5, 7]);
            app.setMarkLayoutSource("data");
            testCase.verifyEqual(string(c.markOptValues.Value), "random", "自分で選んだ乱数のまま");
        end

        function changedMeasurementsMarkResultsOld(testCase)
            % 座標と設定が同じでも、実測値が変われば計算し直す知らせを出す（乱数の形で評価した結果は実測値に左右されない）
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            sample = fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv');
            app.loadFile(sample);
            app.applyMapping();
            app.setMarkLayoutSource("data");
            app.setMarkLayoutSettings(maker="custom", loss="ols", regularization="none", minMarks=0, maxMarks=0);
            app.selectMarkLayoutTermsByVif(10);
            app.optimizeMarkLayout();
            testCase.verifyFalse(any(startsWith(string(c.markOptMessage.Value), "⚠")));
            rows = readtable(sample, 'VariableNamingRule', 'preserve');
            rows.measX = rows.measX + 1;
            file = [tempname, '.csv'];
            writetable(rows, file);
            fileCleanup = onCleanup(@() delete(file));
            app.loadFile(file);
            app.applyMapping();
            app.setMarkLayoutSource("data");
            testCase.verifyTrue(any(startsWith(string(c.markOptMessage.Value), "⚠")), "実測値が変わった");
            testCase.verifyTrue(startsWith(string(c.markOptChartInfo.Text), "⚠"));
        end

        function marksWithoutValuesAreNotChosen(testCase)
            % 実測値で評価するときは、値の無い候補の Mark は選ばない（必ず計測する Mark は残す）。乱数の形なら候補のまま
            [gx, gy] = meshgrid(linspace(-12, 12, 5), linspace(-15, 15, 5));
            localX = repmat(gx(:), 3, 1);
            localY = repmat(gy(:), 3, 1);
            shotNo = reshape(repmat(1:3, numel(gx), 1), [], 1);
            valueX = 2 + 0.1 * localX + 0.01 * shotNo;
            valueY = -1 + 0.2 * localY;
            noValue = localX == 0 & localY == 0;
            valueX(noValue) = NaN;
            valueY(noValue) = NaN;
            wafer = struct("label", "W1", "points", table(localX, localY, shotNo, valueX, valueY));
            [candidates, shots] = alignest.markCandidates(wafer);
            center = find(candidates.nShots == 0);
            testCase.verifyEqual(numel(center), 1);
            settings = alignest.defaultSettings();
            settings.markLayout = struct("maker", "canon", "loss", "ols", "regularization", "none", "starts", 2, ...
                "values", "measured");
            study = alignest.markLayoutStudy(candidates, shots, settings);
            testCase.verifyEqual(size(study.layouts.selected, 1), 25);
            testCase.verifyFalse(any(study.layouts.selected(center, :)));
            testCase.verifyEqual(study.counts(end), 24);
            testCase.verifyEqual(study.evaluation.count(end), 24, "すべての Mark は選べる Mark すべて");
            testCase.verifyEqual(study.layouts.efficiency(end), 100, 'AbsTol', 1e-6);
            testCase.verifyTrue(any(contains(study.messages, "値の無い候補の Mark 1 点")));
            [required, requiredShots] = alignest.markCandidates(wafer, zeros(0, 2), [0, 0]);
            study = alignest.markLayoutStudy(required, requiredShots, settings);
            testCase.verifyTrue(all(study.layouts.selected(center, :)), "必ず計測する Mark は残す");
            settings.markLayout.values = "random";
            settings.markLayout.shapes = 3;
            study = alignest.markLayoutStudy(candidates, shots, settings);
            testCase.verifyEqual(study.counts(end), 25, "乱数の形なら候補のまま");
        end

        function reorderedTableForgetsSelectedRows(testCase)
            % 表を作り直して行が並び変わったら、前に選んだ行では消さない
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            app.makeMarkLayoutGrid([24, 30], [5, 7]);
            table_ = c.markOptCandidateTable;
            table_.CellSelectionCallback([], struct("Indices", [3, 1]));
            data = table_.Data;
            data{1, 3} = -99;
            table_.Data = data;
            table_.CellEditCallback([], struct("Indices", [1, 3], "NewData", -99));
            testCase.verifyEqual(table_.Data{35, 3}, -99, "下の行へ並び変わる");
            c.markOptDeleteRows.ButtonPushedFcn([], []);
            testCase.verifyEqual(size(table_.Data, 1), 35, "前の選択では消さない");
            table_.CellSelectionCallback([], struct("Indices", [3, 1]));
            c.markOptDeleteRows.ButtonPushedFcn([], []);
            testCase.verifyEqual(size(table_.Data, 1), 34);
        end

        function unmeasuredMarksAreEvaluatedButNotChosen(testCase)
            % 計測しない Mark は配置に選ばないが、残差の評価には使う。I 効率の 100% は計測できる Mark をすべて計測したとき
            [gx, gy] = meshgrid(linspace(-12, 12, 5), linspace(-15, 15, 5));
            [candidates, shots] = alignest.markCandidates([], [gx(:), gy(:)], [0, 0], [12, 15; -12, 15]);
            testCase.verifyEqual(nnz(candidates.excluded), 2);
            settings = alignest.defaultSettings();
            settings.markLayout = struct("maker", "canon", "loss", "ols", "regularization", "none", "values", "random", ...
                "shapes", 5, "starts", 2);
            study = alignest.markLayoutStudy(candidates, shots, settings);
            testCase.verifyFalse(any(study.layouts.selected(candidates.excluded, :), 'all'));
            testCase.verifyEqual(study.counts(end), 23);
            testCase.verifyEqual(study.layouts.efficiency(end), 100, 'AbsTol', 1e-6);
            testCase.verifyEqual(study.layouts.dEfficiency(end), 100, 'AbsTol', 1e-6);
            testCase.verifyEqual(study.evaluation.count(end), 23);
            testCase.verifyTrue(all(study.maps.count(candidates.excluded, :) > 0, 'all'), "残差の評価には使う");
            testCase.verifyTrue(any(contains(study.messages, "計測しない Mark 2 点")));
            testCase.verifyTrue(all(diff(study.layouts.dCriterion) < 0), "Mark を増やすと D 基準は下がる");
            % 必ず計測の指定が優先
            [both, ~] = alignest.markCandidates([], [gx(:), gy(:)], [0, 0], [0, 0]);
            testCase.verifyFalse(any(both.excluded));
            % 画面：表のチェック・図のクリック・右の図・表のチェックは片方だけ
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            app.makeMarkLayoutGrid([24, 30], [5, 5]);
            testCase.verifyEqual(string(c.markOptCandidateTable.ColumnName{4}), "計測済み|Shot 数");
            testCase.verifyEqual(string(c.markOptCandidateTable.Data{1, 4}), "—");
            testCase.verifyNotEmpty(findobj(c.markOptCandidateAxes, 'Type', 'scatter'), "右の図");
            app.setMarkLayoutRequired(3, true);
            app.setMarkLayoutExcluded([1, 3], true);
            input = app.MarkLayoutInput;
            testCase.verifyEqual(find(input.candidates.excluded).', [1, 3], "計測しないにすると必ず計測は外れる");
            testCase.verifyFalse(input.candidates.required(3));
            table_ = c.markOptCandidateTable;
            data = table_.Data;
            data{5, 5} = true;
            table_.Data = data;
            table_.CellEditCallback([], struct("Indices", [5, 5], "NewData", true));
            testCase.verifyTrue(app.MarkLayoutInput.candidates.required(5));
            data = table_.Data;
            data{5, 6} = true;
            table_.Data = data;
            table_.CellEditCallback([], struct("Indices", [5, 6], "NewData", true));
            candidates = app.MarkLayoutInput.candidates;
            testCase.verifyEqual([candidates.required(5), candidates.excluded(5)], [false, true], "両方は選べない");
            % クリックで 候補 → 必ず計測 → 計測しない → 候補
            click = struct("IntersectionPoint", [candidates.xMm(10), candidates.yMm(10), 0]);
            markers = findobj(c.markOptCandidateAxes, 'Type', 'scatter', 'DisplayName', '候補の Mark');
            markers.ButtonDownFcn([], click);
            testCase.verifyTrue(app.MarkLayoutInput.candidates.required(10));
            markers = findobj(c.markOptCandidateAxes, 'Type', 'scatter', 'DisplayName', '候補の Mark');
            markers.ButtonDownFcn([], click);
            testCase.verifyTrue(app.MarkLayoutInput.candidates.excluded(10));
            markers = findobj(c.markOptCandidateAxes, 'Type', 'scatter', 'DisplayName', '候補の Mark');
            markers.ButtonDownFcn([], click);
            testCase.verifyFalse(app.MarkLayoutInput.candidates.excluded(10));
            app.setMarkLayoutSettings(maker="canon", loss="ols", regularization="none", maxMarks=10, shapes=5);
            app.generateMarkLayoutShapes();
            study = app.optimizeMarkLayout();
            testCase.verifyEqual(height(study.candidates), 25);
            % 横軸を変える。配置の図の右に Shot スタックマップ。選んだ配置の書き出し
            for name = ["efficiency", "criterionI", "count", "efficiencyD", "criterionD"]
                data = app.drawMarkLayoutChart("rms", "all", name);
                testCase.verifyEqual(height(data), numel(study.counts));
            end
            testCase.verifyEqual(data.xValue, study.layouts.dCriterion);
            testCase.verifyEqual(string(c.markOptChartAxes.XLabel.String), "D 基準");
            app.drawMarkLayoutMap(9);
            testCase.verifyNotEmpty(findobj(c.markOptStackAxes, 'Type', 'quiver'));
            testCase.verifyNotEmpty(findobj(c.markOptStackAxes, 'Type', 'patch'), "共分散楕円");
            file = [tempname, '.xlsx'];
            app.exportMarkSelectionTo(file, 9);
            fileCleanup = onCleanup(@() delete(file));
            testCase.verifyEqual(string(sheetnames(file)).', ["配置", "説明"]);
            testCase.verifyEqual(height(readtable(file, 'Sheet', '配置', 'VariableNamingRule', 'preserve')), 9);
        end

        function regressionCanDifferByAxis(testCase)
            % X・Y で別の回帰。「7. の式を写す」も軸ごと
            [gx, gy] = meshgrid(linspace(-12, 12, 5), linspace(-15, 15, 5));
            [candidates, shots] = alignest.markCandidates([], [gx(:), gy(:)]);
            settings = alignest.defaultSettings();
            settings.markLayout = struct("maker", "canon", "loss", ["ols", "huber"], "regularization", ["none", "l2"], ...
                "lambda", [0, 0.2], "penaltyOrders", 2, "penaltyOrdersY", 2:3, "values", "random", "shapes", 5, ...
                "starts", 2, "maxMarks", 10);
            options = alignest.markLayoutOptions(settings);
            testCase.verifyEqual(options.loss, ["ols", "huber"]);
            testCase.verifyTrue(contains(options.description, "X は") && contains(options.description, "Y は"));
            study = alignest.markLayoutStudy(candidates, shots, settings);
            testCase.verifyNotEmpty(study.evaluation);
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            app.setHighOrderSettings(loss=["ols", "lad"], lambda=[0.1, 0.3], penaltyOrders=2:4, penaltyOrdersY=[3, 5]);
            testCase.verifyEqual(string({c.highOrderRegression.loss.Value}), ["ols", "lad"]);
            testCase.verifyEqual(app.Settings.highOrder.penaltyOrdersY, [3, 5]);
            app.copyHighOrderFormula();
            testCase.verifyEqual(app.Settings.markLayout.lambda, [0.1, 0.3]);
            testCase.verifyEqual(app.Settings.markLayout.penaltyOrdersY, [3, 5]);
            testCase.verifyEqual(string({c.markOptRegression.loss.Value}), ["ols", "lad"]);
        end
    end
end
