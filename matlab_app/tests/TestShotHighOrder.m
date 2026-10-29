classdef TestShotHighOrder < matlab.unittest.TestCase
    %TESTSHOTHIGHORDER Shot 高次補正の評価（「7. Shot高次補正」）：補正の式の項と VIF・VIF で選ぶ項、ロバスト回帰と高次項だけの
    %   L2 正則化、Wafer 内の Shot で共通・Shot ごとの補正、1点抜きの予測の誤差、入力（計測データ・未知の座標の推定値・
    %   Excel）、画面の流れ（計算・古い結果の知らせ・マップ・書き出し・設定ファイル）を確かめる。

    properties
        Root
        Grid      % 合成の Wafer の Shot 中心と Shot 内の点
    end

    methods (TestClassSetup)
        function addPath(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.Root);
            centers = zeros(0, 2);
            for cx = -130:26:130
                for cy = -132:33:132
                    if hypot(cx, cy) < 125
                        centers(end + 1, :) = [cx, cy]; %#ok<AGROW>
                    end
                end
            end
            [lx, ly] = meshgrid(linspace(-12, 12, 7), linspace(-15, 15, 11));   % 1 Shot 7 × 11 点（過去のシミュレーションと同じ）
            testCase.Grid = struct("centers", centers, "local", [lx(:), ly(:)]);
        end
    end

    methods (Test)
        function termsFollowTheMakerFormula(testCase)
            % 項は Overlay 計測ルールの式のまま（Nikon：dx 12 項・dy 15 項）。k1〜k6 は外せない
            terms = alignest.highOrderTerms("nikon", [7, 1, 55]);
            testCase.verifyEqual(nnz(terms.axis == "dx"), 12);
            testCase.verifyEqual(nnz(terms.axis == "dy"), 15);
            testCase.verifyEqual(terms.term(terms.k == 46), "x·y^5");
            testCase.verifyFalse(terms.used(terms.k == 7));
            testCase.verifyFalse(terms.used(terms.k == 55));
            testCase.verifyTrue(terms.used(terms.k == 1), "k1 は外さない");
            testCase.verifyEqual(terms.k(terms.protected).', [1, 3, 5, 2, 4, 6]);
            asml = alignest.highOrderTerms("asml");
            testCase.verifyEqual(asml.k(asml.axis == "dx").', [1, 3, 5, 7, 11, 13, 19]);
            testCase.verifyError(@() alignest.highOrderTerms("other"), 'alignest:highOrderModel');
        end

        function vifSelectionKeepsLowOrderTerms(testCase)
            % VIF は点の配置だけで決まる。決まらない項は ∞。「VIF で選ぶ」は高次の項から外し、k1〜k6 は外さない
            local = testCase.Grid.local;
            valid = true(size(local, 1), 2);
            terms = alignest.highOrderTerms("nikon");
            [checked, info] = alignest.highOrderVif(terms, local, valid, 10);
            testCase.verifyEqual(info.positions, [77, 77]);
            testCase.verifyEqual(checked.vifAll(checked.k == 7), 1, 'AbsTol', 1e-9, "対称な格子では x^2 はほかの項と無相関");
            removed = checked(isfinite(checked.removalOrder), :);
            testCase.verifyFalse(any(removed.protected));
            first = removed(removed.removalOrder == 1, :);
            testCase.verifyEqual(sort(first.order), [6; 6], "最初に外すのは各式の最も高い次数の項");
            kept = alignest.highOrderTerms("nikon", info.suggestedExcluded);
            again = alignest.highOrderVif(kept, local, valid);
            testCase.verifyLessThan(max(again.vifUsed(again.used)), 10, "外した後は、使う項の VIF がすべてしきい値より小さい");
            testCase.verifyTrue(all(isnan(again.vifUsed(~again.used))));
            % 4 点（Shot の四隅）では x^2 は定数と同じで決まらない
            corners = [-10, -12; 10, -12; -10, 12; 10, 12];
            [cornerTerms, cornerInfo] = alignest.highOrderVif(terms, corners, true(4, 2), 10);
            testCase.verifyEqual(cornerTerms.vifAll(cornerTerms.k == 7), Inf);
            testCase.verifyEqual(sort(alignest.highOrderTerms("nikon", cornerInfo.suggestedExcluded).k( ...
                alignest.highOrderTerms("nikon", cornerInfo.suggestedExcluded).used)).', [1, 2, 3, 4, 5, 6, 9, 10], ...
                "四隅の点で残るのは k1〜k6 と x·y（k9・k10）");
            % VIF の定義：1 / (1 − R^2)
            x = (1:10).';
            vif = alignest.varianceInflation([ones(10, 1), x, x + sin(x)], [true, false, false]);
            fitted = [ones(10, 1), x + sin(x)] * ([ones(10, 1), x + sin(x)] \ x);
            rSquared = 1 - sum((x - fitted) .^ 2) / sum((x - mean(x)) .^ 2);
            testCase.verifyEqual(vif(2), 1 / (1 - rSquared), 'RelTol', 1e-9);
            testCase.verifyTrue(isnan(vif(1)));
        end

        function robustRidgeFitShrinksOnlyHighOrderAndResistsOutliers(testCase)
            % L2 は2次以上の項だけを小さくする（1次は小さくしない）。Huber は外れ値の重みを下げ、最小二乗より真の値に近い
            rng(5);
            local = testCase.Grid.local;
            terms = alignest.highOrderTerms("asml");
            terms = terms(terms.axis == "dx", :);
            A = local(:, 1) .^ (terms.xPower.') .* local(:, 2) .^ (terms.yPower.');
            truth = [2; 0.3; -0.2; 0.004; -0.003; 2e-4; -1e-4];
            clean = A * truth;
            values = clean + 0.2 * randn(size(clean));
            outliers = [5, 30, 60];
            values(outliers) = values(outliers) + [15; -12; 18];
            isPenalized = terms.order >= 2;
            ols = alignest.robustRidgeFit(A, values, isPenalized, loss="ols");
            huber = alignest.robustRidgeFit(A, values, isPenalized, loss="huber");
            testCase.verifyTrue(huber.converged);
            testCase.verifyTrue(all(huber.weights(outliers) < 0.2), "外れ値の重みを下げる");
            testCase.verifyLessThan(rootMeanSquare(huber.fitted - clean), rootMeanSquare(ols.fitted - clean) / 3);
            exact = alignest.robustRidgeFit(A, clean, isPenalized, loss="ols");
            testCase.verifyEqual(exact.coefficients, truth, 'RelTol', 1e-8, "雑音が無ければ最小二乗で真の k に戻る");
            ridge = alignest.robustRidgeFit(A, clean, isPenalized, loss="ols", lambda=1);
            testCase.verifyLessThan(norm(ridge.coefficients(isPenalized) ./ truth(isPenalized)), ...
                norm(ones(nnz(isPenalized), 1)), "高次項は小さくなる");
            testCase.verifyGreaterThan(sum(abs(clean - ridge.fitted)), 0);
            % 1次の項だけなら L2 は何も変えない
            linear = alignest.robustRidgeFit(A(:, ~isPenalized), clean, false(3, 1), loss="ols", lambda=10);
            testCase.verifyEqual(linear.coefficients, A(:, ~isPenalized) \ clean, 'AbsTol', 1e-10);
            % 1点抜きの予測の誤差は、最小二乗では点を抜いて求め直したときと同じ
            for i = [1, 40, 77]
                keep = true(size(values));
                keep(i) = false;
                refit = alignest.robustRidgeFit(A(keep, :), values(keep), isPenalized, loss="ols");
                testCase.verifyEqual(ols.looResidual(i), values(i) - A(i, :) * refit.coefficients, 'AbsTol', 1e-9);
            end
            % 決まらない項：L2 をかけない列で前の列で表せる列は 0、L2 をかける値の変わらない列は 0（決まった扱い）
            withCopy = alignest.robustRidgeFit([A(:, 1:3), A(:, 2)], clean, false(4, 1), loss="ols");
            testCase.verifyEqual(withCopy.determined.', [true, true, true, false]);
            flat = alignest.robustRidgeFit([A(:, 1:3), 5 * ones(77, 1)], clean, [false; false; false; true], ...
                loss="huber", lambda=0.1);
            testCase.verifyTrue(all(flat.determined));
            testCase.verifyEqual(flat.constant.', [false, false, false, true]);
            testCase.verifyEqual(flat.coefficients(4), 0);
            testCase.verifyError(@() alignest.robustRidgeFit(A, values(1:5), isPenalized), 'alignest:fitSize');
        end

        function commonAndPerShotRecoverTheTruth(testCase)
            % 雑音の無い合成の Wafer：共通（Wafer 成分 1次）は真の k、Shot ごとは Shot ごとの k を取り戻す
            [points, truth] = syntheticWafer(testCase, true);
            settings = alignest.defaultSettings();
            settings.highOrder.maker = "nikon";
            settings.highOrder.loss = "ols";
            settings.highOrder.l2 = false;
            settings.highOrder.waferOrder = 1;
            result = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            coefficients = result.coefficients(result.coefficients.component == "Shot 高次補正", :);
            for axisName = ["dx", "dy"]
                testCase.verifyEqual(coefficients.value(coefficients.axis == axisName), truth.(axisName), ...
                    'AbsTol', 1e-9 * max(abs(truth.(axisName))));
            end
            wafer = result.coefficients(result.coefficients.component == "Wafer 成分", :);
            testCase.verifyEqual(wafer.value(wafer.axis == "dx" & wafer.term == "Xc"), 0.01, 'AbsTol', 1e-9);
            totals = result.summary(result.summary.wafer == "すべての Wafer", :);
            testCase.verifyLessThan(totals.highOrder, 1e-6);
            testCase.verifyGreaterThan(totals.linear, 1, "1次だけでは高次の形が残る");
            testCase.verifyEqual(totals.improvement, totals.linear - totals.highOrder);
            testCase.verifyEqual(totals.nCorrected, totals.n);
            % Shot ごと：Shot ごとに違う並進・倍率を足しても、Shot ごとの k で取り切れる
            shifted = points;
            shifted.valueX = shifted.valueX + 0.5 * shifted.shotNo + 0.01 * shifted.shotNo .* shifted.localX;
            settings.highOrder.unit = "shot";
            perShot = alignest.shotHighOrder(struct("label", "W1", "points", shifted), settings);
            k3 = perShot.coefficients(perShot.coefficients.k == 3, :);
            testCase.verifyEqual(k3.value - 0.01 * k3.shotNo, repmat(truth.dx(2), height(k3), 1), 'AbsTol', 1e-8);
            testCase.verifyLessThan(max(abs(perShot.points.residualX)), 1e-6);
            testCase.verifyEqual(numel(unique(perShot.coefficients.shotNo)), size(testCase.Grid.centers, 1));
        end

        function fewPointsAreReported(testCase)
            % 点が足りない Shot は補正しない（L2 なし）。L2 をかけると高次項は決まる。値の変わらない項は知らせる
            [points] = syntheticWafer(testCase, false);
            settings = alignest.defaultSettings();
            settings.highOrder.maker = "asml";
            settings.highOrder.unit = "shot";
            settings.highOrder.loss = "ols";
            settings.highOrder.l2 = false;
            few = points(ismember(points.localX, [-12, 12]) & ismember(points.localY, [-15, 15]), :);   % 1 Shot 4 点
            few.valueX = few.valueX + 0.3 * randn(height(few), 1);
            result = alignest.shotHighOrder(struct("label", "W1", "points", few), settings);
            testCase.verifyTrue(all(isnan(result.points.residualX)));
            testCase.verifyTrue(any(contains(result.messages, "補正しなかった Shot")));
            settings.highOrder.l2 = true;
            settings.highOrder.lambda = 0.1;
            result = alignest.shotHighOrder(struct("label", "W1", "points", few), settings);
            testCase.verifyTrue(all(isfinite(result.points.residualX)));
            testCase.verifyTrue(any(contains(result.messages, "値が変わらない")), "四隅では x^2 などが定数と同じ");
            testCase.verifyTrue(any(contains(result.coefficients.note, "値が変わらない")));
            totals = result.summary(result.summary.wafer == "すべての Wafer" & result.summary.axis == "X", :);
            testCase.verifyEqual(totals.looHighOrder, totals.looLinear, 'RelTol', 1e-6, ...
                "四隅の点では、ASML の dx の高次項は定数か1次と同じ形で、1次だけと同じ予測になる");
            % Shot の分からない点は使わない
            unknown = points(1:20, :);
            unknown.shotNo(:) = NaN;
            settings.highOrder.unit = "common";
            result = alignest.shotHighOrder(struct("label", "W1", "points", [points; unknown]), settings);
            testCase.verifyTrue(any(contains(result.messages, "Shot の分からない点 20 点")));
            testCase.verifyError(@() alignest.shotHighOrder(struct("label", {}, "points", {}), settings), ...
                'alignest:highOrderInput');
        end

        function optionsAreValidated(testCase)
            settings = alignest.defaultSettings();
            options = alignest.highOrderOptions(settings);
            testCase.verifyEqual(options.maker, "nikon");
            testCase.verifyTrue(contains(options.description, "Nikon の式（dx 12 / 12 項・dy 15 / 15 項）"));
            settings.highOrder.unit = "shot";
            testCase.verifyEqual(alignest.highOrderOptions(settings).waferOrder, 0, "Shot ごとのときは Wafer 成分を使わない");
            bad = {"maker", "x", 'alignest:highOrderModel'; "unit", "lot", 'alignest:highOrderUnit'; ...
                "waferOrder", 4, 'alignest:highOrderWafer'; "vifThreshold", 1, 'alignest:highOrderVif'; ...
                "loss", "l1", 'alignest:highOrderLoss'; "huberTuning", 0, 'alignest:highOrderHuber'; ...
                "lambda", -1, 'alignest:highOrderLambda'; "excludedTerms", 0.5, 'alignest:highOrderTerms'};
            for k = 1:size(bad, 1)
                broken = alignest.defaultSettings();
                broken.highOrder.(bad{k, 1}) = bad{k, 2};
                testCase.verifyError(@() alignest.highOrderOptions(broken), bad{k, 3});
            end
            old = rmfield(alignest.defaultSettings(), "highOrder");
            testCase.verifyEqual(alignest.highOrderOptions(old).maker, "nikon", "以前の設定は初期値");
            % 設定ファイルの読み書きで highOrder が残る。評価を続きから再開できるかの比較には使わない
            settings.highOrder.excludedTerms = [55, 41];
            file = [tempname, '.json'];
            alignest.saveSettings(settings, file);
            loaded = alignest.loadSettings(file);
            delete(file);
            testCase.verifyEqual(loaded.highOrder.excludedTerms, [55, 41]);
            testCase.verifyEqual(loaded.highOrder.unit, "shot");
            changed = settings;
            changed.highOrder.lambda = 5;
            testCase.verifyTrue(alignest.sameRunSettings(settings, changed));
        end

        function fileInputUsesStandardColumns(testCase)
            % Excel・CSV：標準の列（dx・dy の名前でもよい）。値がすべて空の任意の列は使わない。必須の列が無ければ知らせる
            [points] = syntheticWafer(testCase, false);
            rows = points(1:300, :);
            file = [tempname, '.csv'];
            writetable(table(repmat("W9", height(rows), 1), rows.shotNo, rows.Xc, rows.Yc, rows.localX, rows.localY, ...
                rows.valueX, rows.valueY, nan(height(rows), 1), 'VariableNames', ["Wafer", "shotNo", "Xmm", "Ymm", ...
                "markXmm", "markYmm", "dx", "dy", "markNo"]), file);
            cleanup = onCleanup(@() delete(file));
            [data, info] = alignest.readHighOrderFile(file);
            testCase.verifyEqual(numel(data.units), 1);
            testCase.verifyEqual(data.units.label, "W9");
            testCase.verifyEqual(info.mapping.measX, "dx");
            testCase.verifyEqual(info.mapping.markNo, "", "値がすべて空の markNo は使わない");
            unitPoints = alignest.highOrderUnitPoints(data.units);
            testCase.verifyEqual(sort(unitPoints.valueX), sort(rows.valueX), 'AbsTol', 1e-9);
            missing = [tempname, '.csv'];
            writetable(table(rows.Xc, rows.Yc, rows.valueX, 'VariableNames', ["Xmm", "Ymm", "measX"]), missing);
            cleanupMissing = onCleanup(@() delete(missing));
            testCase.verifyError(@() alignest.readHighOrderFile(missing), 'alignest:highOrderFile');
        end

        function appComputesFromEachInput(testCase)
            % 画面：タブの番号、計測データ・推定値・Excel からの計算、設定を変えた後の知らせ、マップ、書き出し、
            % データ・表を読み直すと、それを入力にした結果を消す、設定ファイルを読むと欄も変わる
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual(app.Tabs.highOrder.Title, '7. Shot高次補正');
            testCase.verifyEqual(app.Tabs.help.Title, '8. ヘルプ');
            testCase.verifyEqual(string(c.highOrderCompute.Enable), "off", "データが無いうちは計算できない");
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            app.setHighOrderSource("data");
            testCase.verifyEqual(numel(c.highOrderWafer.Items), 5);
            testCase.verifyEqual(size(c.highOrderTermTable.Data, 1), 27, "Nikon の dx 12 項・dy 15 項");
            result = app.computeHighOrder(0);
            testCase.verifyEqual(numel(result.points.wafer), 1980);
            testCase.verifyEqual(height(c.highOrderSummaryTable.Data), 12);
            testCase.verifyEqual(height(c.highOrderCoefficientTable.Data), 5, "Shot で共通：Wafer ごとに1行");
            testCase.verifyEqual(string(c.highOrderExport.Enable), "on");
            for value = ["residual", "linear", "loo", "correction", "value"]
                summary = app.drawHighOrderMap(2, "wafer", value, "vector");
                testCase.verifyEqual(summary.n, nnz(result.points.wafer == result.summary.wafer(2)));
            end
            summary = app.drawHighOrderMap(1, "stack", "residual", "X");
            testCase.verifyEqual(summary.positions, 4);
            % 項を外すと、前の結果が古いことを知らせる
            excluded = app.selectHighOrderTermsByVif(10);
            testCase.verifyNotEmpty(excluded);
            testCase.verifyTrue(startsWith(string(c.highOrderMessage.Value{1}), "⚠ 設定・入力を変えました"));
            testCase.verifyError(@() app.setHighOrderTermUsed(3, false), 'alignest:highOrderTerms');
            app.setHighOrderSettings(unit="shot", loss="lad");
            perShot = app.computeHighOrder(1);
            testCase.verifyEqual(perShot.options.loss, "lad");
            testCase.verifyEqual(string(c.highOrderCoefficientWafer.Enable), "on");
            testCase.verifyEqual(height(c.highOrderCoefficientTable.Data), 99, "Shot ごと：Shot ごとに1行");
            file = [tempname, '.xlsx'];
            app.exportHighOrderTo(file);
            sheets = string(sheetnames(file));
            delete(file);
            testCase.verifyEqual(sheets.', ["説明", "補正の評価", "補正値", "項とVIF", "点ごとの値"]);
            % 未知の座標の推定値（Wafer の外の点は使わない）と、学習に使った Mark の実測値
            app.addTargetPoints("shots", 6, 8, NaN);
            app.addTargetPoints("shots", -6, -8, NaN);
            app.addTargetPoints("row");
            app.Controls.targetTable.Data(end, 1:3) = {'外', '200', '0'};
            app.estimateTargets(1, "all", 1);
            app.setHighOrderSource("target");
            app.setHighOrderSettings(unit="common", loss="huber");
            fromTargets = app.computeHighOrder(1);
            testCase.verifyEqual(unique(fromTargets.points.source), "推定値（未知の座標）");
            testCase.verifyTrue(any(contains(fromTargets.messages, "Wafer の外の点 1 点")));
            app.setHighOrderSettings(measured=true);
            withMeasured = app.computeHighOrder(1);
            testCase.verifyEqual(sort(unique(withMeasured.points.source)), sort(["実測値（学習点）"; "推定値（未知の座標）"]));
            % データを読み直すと、推定値の結果も消える
            app.applyMapping();
            testCase.verifyEmpty(app.HighOrderRun);
            % Excel・CSV の表：読み込むと入力を表にして、すべての Wafer を選ぶ。読み直すと前の表の結果は消す
            unitPoints = alignest.highOrderUnitPoints(app.Data.units(1));
            file = [tempname, '.csv'];
            writetable(table(repmat("F1", height(unitPoints), 1), unitPoints.shotNo, unitPoints.Xc, unitPoints.Yc, ...
                unitPoints.localX, unitPoints.localY, unitPoints.valueX, unitPoints.valueY, 'VariableNames', ...
                ["Wafer", "shotNo", "Xmm", "Ymm", "markXmm", "markYmm", "measX", "measY"]), file);
            removeFile = onCleanup(@() delete(file));
            app.loadHighOrderFile(file);
            testCase.verifyEqual(c.highOrderSource.Value, 'file');
            fromFile = app.computeHighOrder();
            testCase.verifyEqual(fromFile.summary.n(1), nnz(isfinite(unitPoints.valueX)));
            app.loadHighOrderFile(file);
            testCase.verifyEmpty(app.HighOrderRun, "表を読み直すと、前の表で求めた結果は消す");
            % 設定ファイルを読むと、欄も変わる
            settings = app.Settings;
            settings.highOrder.maker = "canon";
            settings.highOrder.lambda = 0.4;
            app.setSettings(settings);
            testCase.verifyEqual(c.highOrderMaker.Value, 'canon');
            testCase.verifyEqual(c.highOrderLambda.Value, 0.4);
            testCase.verifyEqual(size(c.highOrderTermTable.Data, 1), 16, "Canon の dx 8 項・dy 8 項");
        end
    end
end

function [points, truth] = syntheticWafer(testCase, highOrder)
% 合成の Wafer：Shot 共通の Nikon の形（highOrder が false なら1次だけ）＋ Wafer の1次（dx に 0.01 × Xc）
rng(11);
centers = testCase.Grid.centers;
local = testCase.Grid.local;
nShots = size(centers, 1);
nMarks = size(local, 1);
Xc = repelem(centers(:, 1), nMarks, 1);
Yc = repelem(centers(:, 2), nMarks, 1);
L = repmat(local, nShots, 1);
terms = alignest.highOrderTerms("nikon");
values = zeros(nShots * nMarks, 2);
truth = struct();
axisNames = ["dx", "dy"];
for a = 1:2
    t = terms(terms.axis == axisNames(a), :);
    coefficient = randn(height(t), 1) ./ (13 .^ t.order);
    if ~highOrder
        coefficient(t.order >= 2) = 0;
    end
    truth.(axisNames(a)) = coefficient;
    values(:, a) = (L(:, 1) .^ (t.xPower.') .* L(:, 2) .^ (t.yPower.')) * coefficient;
end
values(:, 1) = values(:, 1) + 0.01 * Xc;
points = table(repmat("計測値", nShots * nMarks, 1), strings(nShots * nMarks, 1), repelem((1:nShots).', nMarks, 1), Xc, ...
    Yc, L(:, 1), L(:, 2), Xc + L(:, 1), Yc + L(:, 2), values(:, 1), values(:, 2), 'VariableNames', ["source", "name", ...
    "shotNo", "Xc", "Yc", "localX", "localY", "x", "y", "valueX", "valueY"]);
end

function value = rootMeanSquare(values)
value = sqrt(mean(values(:) .^ 2));
end
