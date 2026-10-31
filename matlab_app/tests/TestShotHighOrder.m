classdef TestShotHighOrder < matlab.unittest.TestCase
    %TESTSHOTHIGHORDER Shot 高次補正の評価（「7. Shot高次補正」）：補正の式の項（カスタムの k1〜k38 を含む）と VIF・VIF で
    %   選ぶ項、点の数で項を絞る（k の小さい順）、ロバスト回帰と高次項だけの L2 正則化（組ごとの項を一緒に解く）、k の組の
    %   くくり（Wafer 内で共通・Scan 方向ごと・行の偶奇ごと・Shot ごと）、Shot ごとの1次（k1〜k6）で補正した残差、|残差| の
    %   95% 点・中央値、補正の比較（くくり・λ のスイープ・項の組み合わせ）、Shot の形のグリッド、入力（計測データ・未知の
    %   座標の推定値・Excel（列は読んだ後で選ぶ））、画面の流れ（計算・古い結果の知らせ・マップ・並べて表示・Wafer の比較・
    %   項の組み合わせの保存・書き出し・設定ファイル）を確かめる。

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
            testCase.verifyEqual(asml.k(asml.axis == "dx").', [1, 3, 5, 7, 9, 11, 13, 15, 17, 19], "ASML は k1〜k19 の全項");
            testCase.verifyEqual(asml.k(asml.axis == "dy").', [2, 4, 6, 8, 10, 12, 14, 16, 18]);
            testCase.verifyError(@() alignest.highOrderTerms("other"), 'alignest:highOrderModel');
            % カスタム：Nikon・Canon と同じ番号の付け方の k1〜k38（dx は奇数の k、dy は偶数の k。各 19 項）
            custom = alignest.highOrderTerms("custom");
            testCase.verifyEqual(custom.k(custom.axis == "dx").', 1:2:37);
            testCase.verifyEqual(custom.k(custom.axis == "dy").', 2:2:38);
            power = @(k) [custom.xPower(custom.k == k), custom.yPower(custom.k == k)];
            testCase.verifyEqual(power(7), [2, 0], "k7 = x^2（Nikon と同じ）");
            testCase.verifyEqual(power(21), [4, 0]);
            testCase.verifyEqual(power(29), [0, 4]);
            testCase.verifyEqual(power(37), [2, 3]);
            testCase.verifyEqual(power(38), [3, 2]);
            nikon = alignest.highOrderTerms("nikon");
            same = intersect(nikon.k, custom.k);
            [~, inNikon] = ismember(same, nikon.k);
            [~, inCustom] = ismember(same, custom.k);
            testCase.verifyEqual([custom.xPower(inCustom), custom.yPower(inCustom)], ...
                [nikon.xPower(inNikon), nikon.yPower(inNikon)], "同じ k は Nikon と同じ項");
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
            terms = terms(terms.axis == "dx" & ismember(terms.k, [1, 3, 5, 7, 11, 13, 19]), :);   % x^2・y^2・x^3・y^3 まで
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

        function groupedFitEqualsSeparateFits(testCase)
            % 組ごとの項を一緒に解く（rowGroup・columnGroup）：最小二乗なら L2 があっても組ごとに別に解いたのと同じ。
            % 組が1つなら組なしと同じ
            rng(8);
            local = testCase.Grid.local;
            terms = alignest.highOrderTerms("nikon");
            terms = terms(terms.axis == "dy", :);
            A1 = local(:, 1) .^ (terms.xPower.') .* local(:, 2) .^ (terms.yPower.');
            A2 = A1(1:50, :) + 0.2 * randn(50, height(terms)) .* (terms.order.' >= 1);
            A = [A1; A2];
            values = randn(size(A, 1), 1);
            group = [ones(size(A1, 1), 1); 2 * ones(50, 1)];
            isPenalized = terms.order >= 2;
            p = height(terms);
            joint = alignest.robustRidgeFit([A .* (group == 1), A .* (group == 2)], values, [isPenalized; isPenalized], ...
                loss="ols", lambda=0.1, rowGroup=group, columnGroup=[ones(p, 1); 2 * ones(p, 1)]);
            first = alignest.robustRidgeFit(A1, values(group == 1), isPenalized, loss="ols", lambda=0.1);
            second = alignest.robustRidgeFit(A2, values(group == 2), isPenalized, loss="ols", lambda=0.1);
            testCase.verifyEqual(joint.coefficients, [first.coefficients; second.coefficients], 'AbsTol', 1e-10);
            testCase.verifyEqual(joint.looResidual, [first.looResidual; second.looResidual], 'AbsTol', 1e-10);
            one = alignest.robustRidgeFit(A1, values(group == 1), isPenalized, loss="huber", lambda=0.1, ...
                rowGroup=ones(size(A1, 1), 1), columnGroup=ones(p, 1));
            none = alignest.robustRidgeFit(A1, values(group == 1), isPenalized, loss="huber", lambda=0.1);
            testCase.verifyEqual(one.coefficients, none.coefficients, 'AbsTol', 1e-12);
            testCase.verifyError(@() alignest.robustRidgeFit(A1, values(group == 1), isPenalized, rowGroup=1), ...
                'alignest:fitSize');
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
            testCase.verifyGreaterThan(totals.linear, 1, "Shot ごとの1次では高次の形が残る");
            testCase.verifyEqual(totals.improvement, totals.linear - totals.highOrder);
            testCase.verifyEqual(totals.nCorrected, totals.n);
            % |残差| の 95% 点・中央値：高次補正と Shot ごとの1次の両方ができた点の残差の大きさ
            noisy = points;
            noisy.valueX = noisy.valueX + 0.3 * randn(height(noisy), 1);
            noisyResult = alignest.shotHighOrder(struct("label", "W1", "points", noisy), settings);
            x = noisyResult.summary(noisyResult.summary.wafer == "W1" & noisyResult.summary.axis == "X", :);
            residual = noisyResult.points.residualX;
            testCase.verifyEqual(x.highOrderP95, alignest.stats.percentile(abs(residual), 95), 'AbsTol', 1e-12);
            testCase.verifyEqual(x.highOrderMedian, median(abs(residual)), 'AbsTol', 1e-12);
            testCase.verifyLessThan(x.highOrderMedian, x.highOrderP95);
            % Shot ごとの1次：Shot ごとに違う並進・倍率は、くくりによらず Shot ごとの k1〜k6 で取り切れる
            [linearPoints] = syntheticWafer(testCase, false);
            linearPoints.valueX = linearPoints.valueX + 0.5 * linearPoints.shotNo + 0.01 * linearPoints.shotNo .* ...
                linearPoints.localX;
            linearResult = alignest.shotHighOrder(struct("label", "W1", "points", linearPoints), settings);
            testCase.verifyLessThan(max(abs(linearResult.points.linearResidualX)), 1e-8);
            testCase.verifyGreaterThan(max(abs(linearResult.points.residualX)), 1, "Wafer 内で共通の k では残る");
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

        function scanAndRowGroupsRecoverTheirOwnK(testCase)
            % Scan 方向ごと・行の偶奇ごと：組ごとに違う k を足した合成の Wafer で、それぞれの組の k と、Wafer で共通の
            % Wafer 成分を取り戻す。共通の1組では残る。補正の比較では、正しいくくりの残差が小さい
            [points, truth] = syntheticWafer(testCase, true);
            points.direction = 1 + mod(points.shotNo, 2);   % Shot ごとに交互（一筆書きのように）
            terms = alignest.highOrderTerms("nikon");
            other = struct();
            for axisName = ["dx", "dy"]
                t = terms(terms.axis == axisName, :);
                rng(21);
                other.(axisName) = randn(height(t), 1) ./ (13 .^ t.order);
                shift = (points.localX .^ (t.xPower.') .* points.localY .^ (t.yPower.')) * (other.(axisName) - truth.(axisName));
                column = "valueX";
                if axisName == "dy"
                    column = "valueY";
                end
                points.(column) = points.(column) + (points.direction == 2) .* shift;   % Scan 方向 2 の Shot は other の k
            end
            settings = alignest.defaultSettings();
            settings.highOrder.loss = "ols";
            settings.highOrder.l2 = false;
            settings.highOrder.unit = "scan";
            result = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            coefficients = result.coefficients;
            for axisName = ["dx", "dy"]
                rows = coefficients.axis == axisName & coefficients.component == "Shot 高次補正";
                testCase.verifyEqual(coefficients.value(rows & coefficients.group == "Scan 方向 1"), truth.(axisName), ...
                    'AbsTol', 1e-9 * max(abs(truth.(axisName))));
                testCase.verifyEqual(coefficients.value(rows & coefficients.group == "Scan 方向 2"), other.(axisName), ...
                    'AbsTol', 1e-9 * max(abs(other.(axisName))));
            end
            wafer = coefficients(coefficients.component == "Wafer 成分", :);
            testCase.verifyEqual(unique(wafer.group), "Wafer で共通");
            testCase.verifyEqual(wafer.value(wafer.axis == "dx" & wafer.term == "Xc"), 0.01, 'AbsTol', 1e-9);
            totals = result.summary(result.summary.wafer == "すべての Wafer", :);
            testCase.verifyEqual(totals.kSets, [2; 2]);
            testCase.verifyLessThan(totals.highOrder, 1e-6);
            testCase.verifyEqual(sort(unique(result.points.group)), ["Scan 方向 1"; "Scan 方向 2"]);
            settings.highOrder.unit = "common";
            common = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            testCase.verifyGreaterThan(min(common.summary.highOrder), 0.1, "共通の1組では組の違いが残る");
            % 行の偶奇：Shot 中心の Y の行を上から数える（rowParity の列が無ければ Yc から求める）
            [rowPoints, rowTruth] = syntheticWafer(testCase, true);
            [~, row] = ismember(rowPoints.Yc, sort(unique(rowPoints.Yc), 'descend'));
            rowPoints.valueX = rowPoints.valueX + (mod(row, 2) == 0) .* 0.002 .* rowPoints.localX .^ 2;   % 偶数行だけ x^2 を足す
            settings.highOrder.unit = "row";
            rows = alignest.shotHighOrder(struct("label", "W1", "points", rowPoints), settings);
            k7 = rows.coefficients(rows.coefficients.k == 7, :);
            testCase.verifyEqual(k7.group, ["奇数行"; "偶数行"]);
            dxTerms = terms(terms.axis == "dx", :);
            testCase.verifyEqual(k7.value, rowTruth.dx(dxTerms.k == 7) + [0; 0.002], 'AbsTol', 1e-9);
            % Scan 方向が分からなければ Scan 方向ごとには求めない。補正の比較では、その行を空欄にする
            settings.highOrder.unit = "scan";
            testCase.verifyError(@() alignest.shotHighOrder(struct("label", "W1", "points", rowPoints), settings), ...
                'alignest:highOrderDirection');
            units = ["common", "scan", "row", "shot"];
            conditions = struct("label", {}, "highOrder", {});
            for unit = units
                conditions(end + 1) = struct("label", unit, "highOrder", struct("unit", unit)); %#ok<AGROW>
            end
            comparison = alignest.compareHighOrderConditions(struct("label", "W1", "points", rowPoints), settings, ...
                conditions);
            testCase.verifyEqual(comparison.label.', [units, units]);
            testCase.verifyEqual(comparison.axis.', ["X", "X", "X", "X", "Y", "Y", "Y", "Y"]);
            scan = comparison(comparison.unit == "scan", :);
            testCase.verifyTrue(all(isnan(scan.highOrder)));
            testCase.verifyTrue(all(contains(scan.note, "Scan 方向")));
            testCase.verifyTrue(all(contains(comparison.description(comparison.unit == "common"), "Wafer 成分 1 次")));
            comparison = alignest.compareHighOrderConditions(struct("label", "W1", "points", points), settings, ...
                conditions);
            x = comparison(comparison.axis == "X", :);
            testCase.verifyLessThan(x.highOrder(x.unit == "scan"), x.highOrder(x.unit == "common"));
            testCase.verifyEqual(x.kSets(x.unit == "shot"), size(testCase.Grid.centers, 1));
            testCase.verifyEqual(x.nTerms(x.unit == "common"), 12, "Nikon の dx 12 項");
            testCase.verifyEmpty(alignest.compareHighOrderConditions(struct("label", "W1", "points", points), settings, ...
                struct("label", {}, "highOrder", {})));
        end

        function fewPointsAreReported(testCase)
            % 点の数が最も少ない k の組で求められない項は、k の小さい順に決められる項だけにして知らせる（k1〜k6 は外さない）。
            % 基準より点の配置の悪い組は補正しない（L2 なし）。L2 をかけると決まり、値の変わらない項は知らせる
            [points] = syntheticWafer(testCase, false);
            settings = alignest.defaultSettings();
            settings.highOrder.maker = "custom";
            settings.highOrder.unit = "shot";
            settings.highOrder.loss = "ols";
            settings.highOrder.l2 = false;
            corners = ismember(points.localX, [-12, 12]) & ismember(points.localY, [-15, 15]);
            few = points(corners, :);   % 1 Shot 4 点（四隅）
            few.valueX = few.valueX + 0.3 * randn(height(few), 1);
            result = alignest.shotHighOrder(struct("label", "W1", "points", few), settings);
            dx = result.reduction(1);
            testCase.verifyEqual(dx.nPoints, 4);
            testCase.verifyTrue(contains(dx.reference, "Shot"));
            kept = result.terms.k(result.terms.axis == "dx" & result.terms.used).';
            testCase.verifyEqual(kept, [1, 3, 5, 9], "四隅で決まるのは k1〜k6 と x·y（k9）だけ");
            testCase.verifyEqual(sort([kept, dx.dropped]), 1:2:37);
            testCase.verifyTrue(any(startsWith(result.messages, "⚠ dx：") & contains(result.messages, "k の小さい順")));
            testCase.verifyTrue(all(isfinite(result.points.residualX)), "絞った項なら、どの Shot も求められる");
            testCase.verifyEqual(result.options.excludedTerms(ismember(result.options.excludedTerms, 1:2:37)), dx.dropped);
            % k の小さい順：x·y を外すと、四隅で x·y と同じ形の項のうち k の最も小さい x^3·y（k23）を使う（x·y^3 の k27 は外す）
            settings.highOrder.excludedTerms = 9;
            result = alignest.shotHighOrder(struct("label", "W1", "points", few), settings);
            kept = result.terms.k(result.terms.axis == "dx" & result.terms.used).';
            testCase.verifyEqual(kept, [1, 3, 5, 23]);
            testCase.verifyTrue(ismember(27, result.reduction(1).dropped));
            % 基準（点の数が最も少ない Shot：四隅と中心の 5 点）で決まる x^2 も、四隅だけ（同じ点を2回）の Shot では決まらない
            settings.highOrder.excludedTerms = zeros(1, 0);
            centre = points(points.localX == 0 & points.localY == 0 & points.shotNo == 1, :);
            others = few(few.shotNo ~= 1, :);
            mixed = [few; centre; others];
            result = alignest.shotHighOrder(struct("label", "W1", "points", mixed), settings);
            testCase.verifyEqual(result.reduction(1).nPoints, 5);
            testCase.verifyTrue(contains(result.reduction(1).reference, "Shot 1"));
            testCase.verifyTrue(result.terms.used(result.terms.k == 7), "x^2 は基準の5点で決まる");
            first = result.points.shotNo == 1;
            testCase.verifyTrue(all(isfinite(result.points.residualX(first))));
            testCase.verifyTrue(all(isnan(result.points.residualX(~first))));
            testCase.verifyTrue(any(contains(result.messages, "補正しなかった Shot")));
            settings.highOrder.l2 = true;
            settings.highOrder.lambda = 0.1;
            result = alignest.shotHighOrder(struct("label", "W1", "points", mixed), settings);
            testCase.verifyTrue(all(isfinite(result.points.residualX)));
            testCase.verifyTrue(any(contains(result.messages, "値が変わらない")), "四隅では x^2 が定数と同じ");
            testCase.verifyTrue(any(contains(result.coefficients.note, "値が変わらない")));
            % k1〜k6 も決められない Shot（2点）は基準にせず、補正しない
            two = [few(few.shotNo ~= 2, :); few(find(few.shotNo == 2, 2), :)];
            settings.highOrder.l2 = false;
            result = alignest.shotHighOrder(struct("label", "W1", "points", two), settings);
            testCase.verifyEqual(result.reduction(1).nPoints, 4);
            testCase.verifyTrue(all(isnan(result.points.residualX(result.points.shotNo == 2))));
            % Shot の分からない点は使わない
            unknown = points(1:20, :);
            unknown.shotNo(:) = NaN;
            settings.highOrder.unit = "common";
            result = alignest.shotHighOrder(struct("label", "W1", "points", [points; unknown]), settings);
            testCase.verifyTrue(any(contains(result.messages, "Shot の分からない点 20 点")));
            testCase.verifyError(@() alignest.shotHighOrder(struct("label", {}, "points", {}), settings), ...
                'alignest:highOrderInput');
        end

        function gridFollowsTheFittedFormula(testCase)
            % Shot の形のグリッド：求めた式を Shot 内の好きな位置で求めた値（alignest.highOrderModelAt）は、点の補正量と同じ。
            % 2次以上の項だけの値は、1次の項を除いた分。グリッドを描ける
            [points] = syntheticWafer(testCase, true);
            settings = alignest.defaultSettings();
            settings.highOrder.loss = "ols";
            settings.highOrder.l2 = false;
            settings.highOrder.waferOrder = 1;
            result = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            shots = table((1:size(testCase.Grid.centers, 1)).', testCase.Grid.centers(:, 1), testCase.Grid.centers(:, 2), ...
                repmat(result.points.group(1), size(testCase.Grid.centers, 1), 1), 'VariableNames', ...
                ["shotNo", "Xc", "Yc", "group"]);
            local = testCase.Grid.local;
            [dx, dy] = alignest.highOrderModelAt(result.coefficients, "common", "W1", shots, local);
            first = result.points(result.points.shotNo == 3, :);
            testCase.verifyEqual(dx(3, :).', first.correctionX, 'AbsTol', 1e-9);
            testCase.verifyEqual(dy(3, :).', first.correctionY, 'AbsTol', 1e-9);
            [highX] = alignest.highOrderModelAt(result.coefficients, "common", "W1", shots, local, "highOrder");
            linear = result.coefficients(result.coefficients.axis == "dx" & result.coefficients.component == ...
                "Shot 高次補正" & result.coefficients.xPower + result.coefficients.yPower <= 1, :);
            wafer = result.coefficients(result.coefficients.axis == "dx" & result.coefficients.component == "Wafer 成分", :);
            low = local(:, 1) .^ (linear.xPower.') .* local(:, 2) .^ (linear.yPower.') * linear.value + ...
                sum(wafer.value .* shots.Xc(3) .^ wafer.xPower .* shots.Yc(3) .^ wafer.yPower);
            testCase.verifyEqual(highX(3, :).', dx(3, :).' - low, 'AbsTol', 1e-9);
            figure_ = uifigure('Visible', 'off');
            closeFigure = onCleanup(@() delete(figure_));
            ax = uiaxes(figure_);
            summary = alignest.plot.shotGridMap(ax, [shots.Xc, shots.Yc], [24, 30], @(at) alignest.highOrderModelAt( ...
                result.coefficients, "common", "W1", shots, at));
            testCase.verifyEqual(summary.n, height(shots));
            testCase.verifyGreaterThan(summary.maxNm, 0);
            stacked = alignest.plot.shotGridMap(ax, [shots.Xc, shots.Yc], [24, 30], @(at) alignest.highOrderModelAt( ...
                result.coefficients, "common", "W1", shots, at, "highOrder"), stack=true);
            testCase.verifyEqual(stacked.n, height(shots));
        end

        function optionsAreValidated(testCase)
            settings = alignest.defaultSettings();
            options = alignest.highOrderOptions(settings);
            testCase.verifyEqual(options.maker, "nikon");
            testCase.verifyTrue(contains(options.description, "Nikon の式（dx 12 / 12 項・dy 15 / 15 項）"));
            settings.highOrder.unit = "shot";
            testCase.verifyEqual(alignest.highOrderOptions(settings).waferOrder, 0, "Shot ごとのときは Wafer 成分を使わない");
            for unit = ["scan", "row"]
                settings.highOrder.unit = unit;
                options = alignest.highOrderOptions(settings);
                testCase.verifyEqual(options.waferOrder, 1, "Scan 方向ごと・行の偶奇ごとは Wafer 成分を使う");
                testCase.verifyTrue(contains(options.description, "Wafer で共通にして一緒に求める"));
            end
            settings.highOrder.unit = "shot";
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

        function fileInputUsesChosenColumns(testCase)
            % Excel・CSV：見出しから列を推定する（標準の名前・dx・dy など。値がすべて空の任意の列は推定しない）。列の名前が
            % 自由でも、項目ごとに選んだ列で Wafer ごとのデータにする。必須の項目が無い・同じ列を2回選ぶと知らせる
            [points] = syntheticWafer(testCase, false);
            rows = points(1:300, :);
            file = [tempname, '.csv'];
            writetable(table(repmat("W9", height(rows), 1), rows.shotNo, rows.Xc, rows.Yc, rows.localX, rows.localY, ...
                rows.valueX, rows.valueY, nan(height(rows), 1), 'VariableNames', ["Wafer", "shotNo", "Xmm", "Ymm", ...
                "markXmm", "markYmm", "dx", "dy", "Direction"]), file);
            cleanup = onCleanup(@() delete(file));
            [raw, info] = alignest.readHighOrderFile(file);
            testCase.verifyEqual(info.mapping.measX, "dx");
            testCase.verifyEqual(info.mapping.Direction, "", "値がすべて空の Direction は推定しない");
            data = alignest.prepareHighOrderData(raw, info.mapping);
            testCase.verifyEqual(numel(data.units), 1);
            testCase.verifyEqual(data.units.label, "W9");
            unitPoints = alignest.highOrderUnitPoints(data.units);
            testCase.verifyEqual(sort(unitPoints.valueX), sort(rows.valueX), 'AbsTol', 1e-9);
            testCase.verifyEqual(unique(unitPoints.rowParity).', [1, 2]);
            % 自由な列名：推定できない列は選ぶ。Scan 方向の列も選べる
            free = [tempname, '.csv'];
            writetable(table(rows.Xc, rows.Yc, rows.localX, rows.localY, rows.valueX, rows.valueY, ...
                1 + mod(rows.shotNo, 2), 'VariableNames', ["中心X", "中心Y", "位置X", "位置Y", "OVL_X", "OVL_Y", "走査"]), free);
            cleanupFree = onCleanup(@() delete(free));
            [raw, info] = alignest.readHighOrderFile(free);
            testCase.verifyEqual(info.mapping.Xmm, "");
            testCase.verifyEqual(info.columns, ["中心X", "中心Y", "位置X", "位置Y", "OVL_X", "OVL_Y", "走査"]);
            chosen = struct("Xmm", "中心X", "Ymm", "中心Y", "markXmm", "位置X", "markYmm", "位置Y", "measX", "OVL_X", ...
                "measY", "OVL_Y", "Direction", "走査");
            [data, used] = alignest.prepareHighOrderData(raw, chosen);
            testCase.verifyEqual(used.Direction, "走査");
            testCase.verifyEqual(used.Wafer, "", "選ばなかった項目は列なし");
            testCase.verifyEqual(sort(unique(data.units.marks.direction)).', [1, 2]);
            testCase.verifyEqual(numel(data.units.marks.x), height(rows));
            testCase.verifyError(@() alignest.prepareHighOrderData(raw, rmfield(chosen, "measY")), 'alignest:highOrderFile');
            twice = chosen;
            twice.measY = "OVL_X";
            testCase.verifyError(@() alignest.prepareHighOrderData(raw, twice), 'alignest:highOrderFile');
            unknown = chosen;
            unknown.measY = "無い列";
            testCase.verifyError(@() alignest.prepareHighOrderData(raw, unknown), 'alignest:highOrderFile');
            % Scan 方向の列が無いときは規則で付ける
            noScan = rmfield(chosen, "Direction");
            data = alignest.prepareHighOrderData(raw, noScan, directionRule="rowParity");
            testCase.verifyEqual(sort(unique(data.units.marks.direction)).', [1, 2]);
        end

        function appComputesFromEachInput(testCase)
            % 画面：タブの番号、計測データ・推定値・Excel からの計算、点の数で項を絞ったときの知らせと表、設定を変えた後の
            % 知らせ、マップ（グリッド・並べて表示）、Wafer の比較、書き出し、データ・表を読み直すと、それを入力にした結果を
            % 消す、補正の比較（くくり・λ）、項の組み合わせの保存、設定ファイルを読むと欄も変わる
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
            testCase.verifyTrue(any(contains(string(c.highOrderSummaryTable.Data.Properties.VariableNames), "95% 点")));
            % 1 Shot 4 点（Shot 内の位置 4 か所）なので、決められる項だけに絞り、表の「使う」も外す（古い結果の知らせは出さない）
            testCase.verifyTrue(startsWith(string(c.highOrderMessage.Value{1}), "⚠ dx："));
            dropped = [result.reduction.dropped];
            testCase.verifyNotEmpty(dropped);
            testCase.verifyTrue(all(ismember(dropped, app.Settings.highOrder.excludedTerms)));
            testCase.verifyEqual(nnz([c.highOrderTermTable.Data{:, 1}]), 8, "dx・dy 4 項ずつ");
            testCase.verifyFalse(any(startsWith(string(c.highOrderMessage.Value), "⚠ 設定・入力を変えました")));
            coefficients = c.highOrderCoefficientTable.Data;
            testCase.verifyEqual(height(coefficients), 5, "Shot で共通：Wafer ごとに1行");
            names = string(coefficients.Properties.VariableNames);
            testCase.verifyEqual(names(2:5), ["残差の点の数", "残差 |平均|+3σ [nm]", "|残差| 95% 点 [nm]", ...
                "|残差| 中央値 [nm]"], "Xc・Yc の代わりに回帰の残差");
            testCase.verifyFalse(any(contains(names, ["Xc", "Yc"])));
            testCase.verifyEqual(str2double(coefficients{1, 3}), result.summary.highOrder(1), 'AbsTol', 1e-3);
            testCase.verifyEqual(string(c.highOrderExport.Enable), "on");
            label = result.summary.wafer(2);
            mine = result.points(result.points.wafer == label, :);
            for value = ["residual", "linear", "correction", "highOnly", "value"]
                summary = app.drawHighOrderMap(2, "wafer", value, "vector");
                testCase.verifyGreaterThan(summary.n, 0);
            end
            summary = app.drawHighOrderMap(2, "wafer", "residual", "vector");
            testCase.verifyEqual(summary.n, nnz(isfinite(mine.residualX) | isfinite(mine.residualY)));
            summary = app.drawHighOrderMap(1, "stack", "residual", "X");
            testCase.verifyEqual(summary.positions, 4);
            % グリッド（Shot の形）：補正量を、求めた式で変形させた Shot の枠で描く（Shot の数）
            summary = app.drawHighOrderMap(2, "wafer", "correction", "grid");
            testCase.verifyEqual(summary.n, numel(unique(mine.shotNo)));
            summary = app.drawHighOrderMap(2, "stack", "highOnly", "grid");
            testCase.verifyEqual(summary.n, numel(unique(mine.shotNo)));
            % 補正前の値・補正量・残差を並べる（3つの図。値の選択は使わない）
            app.drawHighOrderMap(2, "wafer", "residual", "vector", "", "side");
            testCase.verifyEqual(c.highOrderAxesGrid.ColumnWidth, {'1x', '1x', '1x'});
            testCase.verifyEqual(string(c.highOrderMapValue.Enable), "off");
            testCase.verifyNotEmpty(c.highOrderAxes3.Children);
            testCase.verifyEqual(numel(strfind(c.highOrderMapInfo.Text, '|平均|+3σ')), 3);
            app.drawHighOrderMap(2, "wafer", "residual", "vector", "", "single");
            testCase.verifyEqual(c.highOrderAxesGrid.ColumnWidth, {'1x', 0, 0});
            testCase.verifyEmpty(allchild(c.highOrderAxes2), "使わない図は中身を消す（保存・コピーしない）");
            app.drawHighOrderMap(2, "wafer", "residual", "X", "", "side");
            testCase.verifyNotEmpty(allchild(c.highOrderAxes3), "色の図も描く（点は凡例に出さないので Children には無い）");
            % Wafer の比較：Wafer ごとの k パラメータ（Shot の端での大きさ）と残差
            values = app.drawHighOrderWaferComparison("edge", "dx");
            testCase.verifyEqual(height(values), 5);
            testCase.verifyEqual(width(values), 1 + 2 * 4, "Wafer と、使う4項の値と標準偏差");
            residuals = app.drawHighOrderWaferComparison("residual", "dy", "median");
            testCase.verifyEqual(residuals.Properties.VariableNames, {'Wafer', '補正前', 'Shot ごとの1次', '高次補正'});
            y = result.summary(result.summary.axis == "Y" & result.summary.wafer ~= "すべての Wafer", :);
            testCase.verifyEqual(residuals.("高次補正"), y.highOrderMedian, 'AbsTol', 1e-9);
            testCase.verifyEqual(string(c.highOrderWaferStatistic.Enable), "on");
            % 項を戻すと、前の結果が古いことを知らせる
            excluded = app.selectHighOrderTermsByVif(10);
            testCase.verifyNotEmpty(excluded);
            app.useAllHighOrderTerms();
            testCase.verifyTrue(startsWith(string(c.highOrderMessage.Value{1}), "⚠ 設定・入力を変えました"));
            testCase.verifyError(@() app.setHighOrderTermUsed(3, false), 'alignest:highOrderTerms');
            app.setHighOrderSettings(unit="shot", loss="lad");
            perShot = app.computeHighOrder(1);
            testCase.verifyEqual(perShot.options.loss, "lad");
            testCase.verifyEqual(string(c.highOrderCoefficientWafer.Enable), "on");
            testCase.verifyEqual(height(c.highOrderCoefficientTable.Data), 99, "Shot ごと：Shot ごとに1行");
            testCase.verifyTrue(contains(perShot.reduction(1).reference, "の Shot"), "Shot ごとは Mark の最も少ない Shot が基準");
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
            % 自由な列名：読んだ直後は計算できない。列を選ぶと Wafer ごとのデータになり、Scan 方向ごとにも求められる
            free = [tempname, '.csv'];
            writetable(table(repmat("F2", height(unitPoints), 1), unitPoints.Xc, unitPoints.Yc, unitPoints.localX, ...
                unitPoints.localY, unitPoints.valueX, unitPoints.valueY, unitPoints.direction, 'VariableNames', ...
                ["ロット_ウェハ", "SX", "SY", "LX", "LY", "OVL_X", "OVL_Y", "ScanDir"]), free);
            removeFree = onCleanup(@() delete(free));
            testCase.verifyEmpty(app.loadHighOrderFile(free));
            testCase.verifyEqual(c.highOrderOutputs.SelectedTab, c.highOrderColumnTab);
            testCase.verifyEqual(string(c.highOrderCompute.Enable), "off", "列を選ぶまで計算できない");
            testCase.verifyEqual(size(c.highOrderMappingTable.Data, 1), numel(alignest.highOrderColumns()));
            testCase.verifyError(@() app.applyHighOrderMapping(struct("Xmm", "SX")), 'alignest:highOrderFile');
            data = app.applyHighOrderMapping(struct("Wafer", "ロット_ウェハ", "Xmm", "SX", "Ymm", "SY", "markXmm", "LX", ...
                "markYmm", "LY", "measX", "OVL_X", "measY", "OVL_Y", "Direction", "ScanDir"));
            testCase.verifyEqual(data.units.label, "F2");
            testCase.verifyEqual(c.highOrderMappingTable.Data{4, 4}, 'SX', "選んだ列を表に出す");
            app.setHighOrderSettings(unit="scan");
            fromFree = app.computeHighOrder();
            testCase.verifyEqual(fromFree.summary.kSets(1), 2);
            testCase.verifyEqual(height(c.highOrderCoefficientTable.Data), 2, "Wafer × Scan 方向の2行");
            testCase.verifyEqual(string(c.highOrderCoefficientTable.Data.Properties.VariableNames(1:2)), ["Wafer", "くくり"]);
            testCase.verifyEqual(string(c.highOrderMapGroup.Items), ["すべての点", "Scan 方向 1", "Scan 方向 2"]);
            one = app.drawHighOrderMap(1, "stack", "residual", "vector", "Scan 方向 1");
            all_ = app.drawHighOrderMap(1, "wafer", "residual", "vector", "");
            testCase.verifyLessThan(one.n, all_.n);
            % 補正の比較：4つのくくりと λ のスイープ × 2軸。条件・入力を変えると知らせ、書き出しには比べ直した結果だけを書く
            testCase.verifyError(@() app.compareHighOrderConditionsNow(), 'alignest:highOrderCondition');
            app.addHighOrderConditions("units");
            app.addHighOrderConditions("lambda", [0, 0.5]);
            testCase.verifyError(@() app.addHighOrderConditions("lambda", -1), 'alignest:highOrderLambda');
            testCase.verifyEqual(numel(c.highOrderConditionList.Items), 6);
            comparison = app.compareHighOrderConditionsNow();
            testCase.verifyEqual(height(comparison), 12);
            testCase.verifyEqual(c.highOrderOutputs.SelectedTab, c.highOrderCompareTab);
            testCase.verifyEqual(height(c.highOrderCompareTable.Data), 12);
            testCase.verifyEqual(comparison.lambda(contains(comparison.label, "λ = 0｜")), [0; 0]);
            testCase.verifyNotEmpty(c.highOrderCompareAxes.Children);
            exported = [tempname, '.xlsx'];
            app.exportHighOrderTo(exported);
            testCase.verifyTrue(any(string(sheetnames(exported)) == "補正の比較"));
            delete(exported);
            app.setHighOrderSettings(lambda=0.5);   % 条件は足したときの設定のまま：左の設定を変えても比較は古くならない
            testCase.verifyFalse(startsWith(string(c.highOrderCompareInfo.Text), "⚠"));
            app.addHighOrderConditions("current");
            testCase.verifyTrue(startsWith(string(c.highOrderCompareInfo.Text), "⚠"));
            app.exportHighOrderTo(exported);
            testCase.verifyFalse(any(string(sheetnames(exported)) == "補正の比較"), "古い比較は書かない");
            delete(exported);
            app.removeHighOrderConditions(numel(app.HighOrderConditions));
            testCase.verifyFalse(startsWith(string(c.highOrderCompareInfo.Text), "⚠"));
            app.removeHighOrderConditions("all");
            testCase.verifyEmpty(app.HighOrderConditions);
            % 項の組み合わせ：名前を付けて保存し、呼び出す・比べる・消す。設定ファイルを読んでも消えない
            app.setHighOrderSettings(maker="custom");
            testCase.verifyEqual(size(c.highOrderTermTable.Data, 1), 38, "カスタムは k1〜k38");
            app.useAllHighOrderTerms();
            app.setHighOrderTermUsed(37, false);
            testCase.verifyError(@() app.saveHighOrderTermSet("a|b"), 'alignest:highOrderTermSet');
            testCase.verifyEqual(app.saveHighOrderTermSet("k37 なし"), "k37 なし");
            testCase.verifyEqual(string(c.highOrderTermSetList.Enable), "on");
            app.setHighOrderSettings(maker="nikon");
            app.useAllHighOrderTerms();
            app.applyHighOrderTermSet("k37 なし");
            testCase.verifyEqual(c.highOrderMaker.Value, 'custom');
            testCase.verifyEqual(app.Settings.highOrder.excludedTerms, 37);
            app.addHighOrderConditions("termSet", "k37 なし");
            testCase.verifyEqual(app.HighOrderConditions(end).highOrder.excludedTerms, 37);
            testCase.verifyError(@() app.applyHighOrderTermSet("無い名前"), 'alignest:highOrderTermSet');
            app.removeHighOrderConditions("all");
            % 設定ファイルを読むと、欄も変わる（保存した項の組み合わせは残す）
            settings = app.Settings;
            settings.highOrder.maker = "canon";
            settings.highOrder.lambda = 0.4;
            settings.highOrder.termSets = strings(0, 1);
            app.setSettings(settings);
            testCase.verifyEqual(c.highOrderMaker.Value, 'canon');
            testCase.verifyEqual(c.highOrderLambda.Value, 0.4);
            testCase.verifyEqual(size(c.highOrderTermTable.Data, 1), 16, "Canon の dx 8 項・dy 8 項");
            testCase.verifyEqual(app.Settings.highOrder.termSets, "k37 なし|custom|" + strjoin(string([1:2:35, 2:2:38]), " "));
            app.deleteHighOrderTermSet("k37 なし");
            testCase.verifyEmpty(app.Settings.highOrder.termSets);
            testCase.verifyEqual(string(c.highOrderTermSetApply.Enable), "off");
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
