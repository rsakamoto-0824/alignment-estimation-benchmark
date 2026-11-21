classdef TestMeasurementCandidates < matlab.unittest.TestCase
    %TESTMEASUREMENTCANDIDATES 計測を足す場所（alignest.measurementCandidates）：推定誤差・GPR の推定の分散の大きい上位 n の
    %   場所（Shot・Mark）と閾値より大きい場所、平均・最大、軸、除く場所、学習の行を使わないこと。評価の推定値の表の推定の分散の列。
    %   「3. 結果一覧」の「計測を足す場所」と、「足す」にチェックを入れた候補だけを必ず計測する Shot・Mark の欄に入れること。

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
        function ranksLocationsByErrorOrVariance(testCase)
            estimates = syntheticEstimates();
            % Mark ごと：場所 1-1 は2枚の Wafer の |残差| の平均 (3 + 5) / 2 = 4、1-2 は 1、2-1 は 6、2-2 は X だけで大きさは無い
            top = alignest.measurementCandidates(estimates, "error", "mark", 2);
            testCase.verifyEqual(top.key.', ["2-1", "1-1"]);
            testCase.verifyEqual(top.value.', [6, 4], 'AbsTol', 1e-12);
            testCase.verifyEqual(top.nWafers.', [1, 2]);
            testCase.verifyEqual(top.rank.', [1, 2]);
            % 最大で比べる：1-1 は 5、2-1 は 6
            byMax = alignest.measurementCandidates(estimates, "error", "mark", 3, statistic="max");
            testCase.verifyEqual(byMax.value.', [6, 5, 1], 'AbsTol', 1e-12);
            % X だけ：2-2 の X（10）が一番大きい
            byX = alignest.measurementCandidates(estimates, "error", "mark", 1, axis="X");
            testCase.verifyEqual(byX.key, "2-2");
            % Shot ごと：Shot 1 は点 3・5・1 の平均 3、Shot 2 は 6（2-2 は大きさが無いので使わない）
            shots = alignest.measurementCandidates(estimates, "error", "shot", 5);
            testCase.verifyEqual(shots.shotNo.', [2, 1]);
            testCase.verifyEqual(shots.value.', [6, 3], 'AbsTol', 1e-12);
            testCase.verifyTrue(all(isnan(shots.markNo)));
            % 除く場所（既に必ず計測・計測しないにした場所）
            testCase.verifyEqual(alignest.measurementCandidates(estimates, "error", "shot", 5, exclude=2).shotNo, 1);
            testCase.verifyEqual(alignest.measurementCandidates(estimates, "error", "mark", 1, exclude="2-1").key, "1-1");
            % 閾値より大きい場所すべて（上位の数は使わない。閾値と同じ値は入れない）
            byThreshold = alignest.measurementCandidates(estimates, "error", "mark", 1, threshold=3);
            testCase.verifyEqual(byThreshold.key.', ["2-1", "1-1"]);
            testCase.verifyEqual(byThreshold.rank.', [1, 2]);
            testCase.verifyEmpty(alignest.measurementCandidates(estimates, "error", "mark", 5, threshold=6));
            testCase.verifyEqual(height(alignest.measurementCandidates(estimates, "error", "mark", 1, threshold=0)), 3);
            testCase.verifyEqual(alignest.measurementCandidates(estimates, "error", "mark", 1, threshold=3, ...
                exclude="2-1").key, "1-1");
            testCase.verifyEqual(alignest.measurementCandidates(estimates, "error", "shot", 1, threshold=2).shotNo.', [2, 1]);
            % 推定の分散：X + Y の大きい順。学習の行（分散 100）は使わない
            variance = alignest.measurementCandidates(estimates, "variance", "mark", 2);
            testCase.verifyEqual(variance.key.', ["1-2", "1-1"]);
            testCase.verifyEqual(variance.value(1), 9, 'AbsTol', 1e-12);
            % 推定の分散の列の無い表（以前の推定値の Excel）は候補なし
            old = removevars(estimates, ["varianceX", "varianceY"]);
            testCase.verifyEmpty(alignest.measurementCandidates(old, "variance", "mark", 3));
        end

        function estimatesCarryGprVariance(testCase)
            % 評価の推定値の表に GPR の推定の分散（評価点の数だけ。ほかの手法は NaN）
            raw = alignest.readMeasurementFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            results = alignest.runEvaluation(data, smallSettings(alignest.defaultSettings()));
            gpr = find(string({results.methods.family}) == "GPR", 1);
            polynomial = find(string({results.methods.family}) == "XY", 1);
            selection = struct("methodIndex", [gpr, polynomial], "groups", results.groups(1), "unitIndex", 1);
            estimates = alignest.collectEstimates(data, results, selection);
            mine = estimates(estimates.methodId == results.methods(gpr).id, :);
            others = estimates(estimates.methodId == results.methods(polynomial).id, :);
            testCase.verifyTrue(all(isfinite(mine.varianceX(isfinite(mine.estimateX)))));
            testCase.verifyTrue(all(mine.varianceX >= 0 | isnan(mine.varianceX)));
            testCase.verifyTrue(all(isnan(others.varianceX)), "GPR 以外は空");
            % 推定値の Excel にも列があり、読み直せる
            file = [tempname, '.xlsx'];
            cleanup = onCleanup(@() delete(file));
            alignest.exportEstimates(estimates, struct("normality", table(), "anova", table()), file);
            sheet = readtable(file, 'Sheet', '推定値', 'VariableNamingRule', 'preserve');
            testCase.verifyTrue(all(ismember(["推定の分散X[nm2]", "推定の分散Y[nm2]"], string(sheet.Properties.VariableNames))));
        end

        function screenFindsAndAddsCandidates(testCase)
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual(string(c.findCandidatesButton.Enable), "off", "結果が無いうちは使わない");
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            app.setSettings(smallSettings(app.Settings));
            results = app.runEvaluationNow(false);
            gpr = find(string({results.methods.family}) == "GPR", 1);
            testCase.verifyEqual(c.candidateMethod.Value, gpr, "初めは GPR の手法");
            % 推定誤差の大きい Shot の上位 5
            top = app.findMeasurementCandidates(criterion="error", level="shot", count=5);
            testCase.verifyEqual(height(top), 5);
            testCase.verifyTrue(issorted(top.value, 'descend'));
            testCase.verifyEqual(size(c.candidateTable.Data, 1), 5);
            testCase.verifyEqual(string(c.addCandidatesButton.Enable), "on");
            testCase.verifyNotEmpty(findobj(c.candidateAxes, 'DisplayName', '計測を足す候補（Shot の点の中心）'));
            testCase.verifyNotEmpty(findall(c.candidateAxes, 'Type', 'image'), "値のヒートマップ");
            testCase.verifyTrue(contains(string(c.candidateAxes.Colorbar.Label.String), "推定誤差"));
            added = app.addMeasurementCandidates();
            testCase.verifyEqual(sort(added), sort(top.shotNo.'));
            testCase.verifyTrue(all(ismember(top.shotNo, app.Settings.sampling.requiredShots)), "必ず計測する shotNo に入る");
            testCase.verifyTrue(contains(string(c.requiredShots.Value), string(top.shotNo(1))), "2. 評価の設定と実行の欄にも出る");
            testCase.verifyTrue(contains(string(c.candidateInfo.Text), "5 個を足しました"));
            % 足した場所は次の候補に出ない
            next = app.findMeasurementCandidates();
            testCase.verifyEmpty(intersect(next.shotNo, top.shotNo));
            % GPR の推定の分散の大きい Mark。GPR 以外の手法では分散が無いと知らせる
            marks = app.findMeasurementCandidates(criterion="variance", level="mark", count=4, wafer=1);
            testCase.verifyEqual(height(marks), 4);
            testCase.verifyTrue(all(contains(marks.key, "-")));
            testCase.verifyEqual(c.candidateTable.Data(:, 1), num2cell(true(4, 1)), "初めはすべての候補にチェック");
            % 表の「足す」のチェックを外した候補は足さない（図では灰色）
            c.candidateTable.Data{2, 1} = false;
            c.candidateTable.CellEditCallback(c.candidateTable, struct("Indices", [2, 1], "NewData", false));
            testCase.verifyNotEmpty(findobj(c.candidateAxes, 'DisplayName', '外した候補'));
            testCase.verifyTrue(contains(string(c.candidateInfo.Text), "チェックを入れた 3 個"));
            added = app.addMeasurementCandidates();
            testCase.verifyEqual(added, marks.key([1, 3, 4]).');
            testCase.verifyTrue(all(ismember(marks.key([1, 3, 4]), app.Settings.sampling.requiredMarks)), ...
                "必ず計測する Mark に入る");
            testCase.verifyFalse(ismember(marks.key(2), app.Settings.sampling.requiredMarks), "外した候補は入れない");
            % すべて外すと足せない。key で選ぶこともできる
            c.clearCandidatesButton.ButtonPushedFcn([], []);
            testCase.verifyEqual(c.candidateTable.Data(:, 1), num2cell(false(4, 1)));
            testCase.verifyEqual(string(c.addCandidatesButton.Enable), "off");
            testCase.verifyError(@() app.addMeasurementCandidates(), 'alignest:noCandidates');
            app.selectMeasurementCandidates(marks.key(2));
            testCase.verifyEqual(c.candidateTable.Data(:, 1), num2cell([false; true; false; false]));
            testCase.verifyEqual(app.addMeasurementCandidates(), marks.key(2));
            c.selectAllCandidatesButton.ButtonPushedFcn([], []);
            testCase.verifyEqual(c.candidateTable.Data(:, 1), num2cell(true(4, 1)));
            polynomial = find(string({results.methods.family}) == "XY", 1);
            testCase.verifyError(@() app.findMeasurementCandidates(method=polynomial, criterion="variance"), ...
                'alignest:candidateVariance');
            % 閾値より大きい場所：上位 n の欄は使わず、閾値の欄を使う。閾値より大きい場所がすべて出る
            testCase.verifyEqual(string(c.candidateThreshold.Enable), "off", "初めは上位 n");
            reference = app.findMeasurementCandidates(method=gpr, criterion="error", level="shot", wafer=0, mode="top", ...
                count=8);
            threshold = reference.value(4);
            byThreshold = app.findMeasurementCandidates(mode="threshold", threshold=threshold);
            testCase.verifyEqual(byThreshold.key, reference.key(reference.value > threshold));
            testCase.verifyEqual(string(c.candidateCount.Enable), "off");
            testCase.verifyEqual(string(c.candidateThreshold.Enable), "on");
            testCase.verifyTrue(contains(string(c.candidateInfo.Text), "より大きい " + height(byThreshold) + " 個の場所"));
            testCase.verifyTrue(contains(string(c.candidateAxes.Title.String), "閾値"));
            % 閾値より大きい場所が無いときは、いちばん大きい場所の値を知らせる
            none = app.findMeasurementCandidates(threshold=1e9);
            testCase.verifyEmpty(none);
            testCase.verifyEqual(string(c.addCandidatesButton.Enable), "off");
            testCase.verifyTrue(contains(string(c.candidateInfo.Text), "より大きい場所はありません"));
            testCase.verifyTrue(contains(string(c.candidateInfo.Text), sprintf("%.3f", reference.value(1))));
            % 上位 n に戻すと、上位 n の欄を使う
            c.candidateMode.Value = 'top';
            c.candidateMode.ValueChangedFcn([], []);
            testCase.verifyEqual(string(c.candidateCount.Enable), "on");
            testCase.verifyEqual(string(c.candidateThreshold.Enable), "off");
        end
    end
end

function estimates = syntheticEstimates()
% 2 Shot × 2 Mark、Wafer 2枚。最後の行は学習の行（推定誤差・分散を使わない）
Wafer = ["W1"; "W2"; "W1"; "W1"; "W1"; "W2"];
shotNo = [1; 1; 1; 2; 2; 1];
markNo = [1; 1; 2; 1; 2; 2];
residualX = [3; 0; 1; 0; 10; NaN];
residualY = [0; 5; 0; 6; NaN; NaN];
varianceX = [1; 2; 4; 0.5; 0.5; 100];
varianceY = [1; 2; 5; 0.5; NaN; 100];
x = [10; 10; 12; 30; 32; 12];
y = [5; 5; 5; 5; 5; 5];
role = ["評価"; "評価"; "評価"; "評価"; "評価"; "学習"];
estimates = table(Wafer, shotNo, markNo, x, y, role, residualX, residualY, varianceX, varianceY);
end

function settings = smallSettings(settings)
% 速く終わる評価（GPR matern52（質的変数なし）と XY 5次多項式、学習 Shot 20）
settings.methods = alignest.recommendedMethods("none");
settings.methods.gpr.enabled = true;
settings.methods.gpr.kernels = "matern52";
settings.methods.gpr.factorModes = "none";
settings.methods.polynomial.enabled = true;
settings.sampling.nShots = 20;
settings.sampling.nShotsStart = 20;
settings.sampling.nShotsEnd = 20;
settings.sampling.nShotsStep = 5;
settings.sampling.exchangeStarts = 2;
end
