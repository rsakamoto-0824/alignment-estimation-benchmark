classdef TestShotHighOrderOutputs < matlab.unittest.TestCase
    %TESTSHOTHIGHORDEROUTPUTS Shot 高次補正（「7. Shot高次補正」）の正則化（L2・L1、かける次数を選ぶ）と、補正値・補正残差の
    %   書き出し（点ごとの値を計測データの形で・Shot ごとの k を横に並べて・補正の比較の全条件をまとめて。CSV・Excel）を確かめる。

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
            [lx, ly] = meshgrid(linspace(-12, 12, 7), linspace(-15, 15, 11));   % 1 Shot 7 × 11 点
            testCase.Grid = struct("centers", centers, "local", [lx(:), ly(:)]);
        end
    end

    methods (Test)
        function l1PenaltyIsSoftThreshold(testCase)
            % 列が直交（平均 0・二乗平均 1）なら、L1 の係数は最小二乗の係数を λ だけ 0 に近づけた値（軟しきい値。λ より
            % 小さい係数はちょうど 0）、L2 の係数は最小二乗の 1/(1 + λ)。罰則をかけない列と定数は最小二乗のまま
            n = 64;
            x1 = repmat([1; -1], n / 2, 1);
            x2 = repmat([1; 1; -1; -1], n / 4, 1);
            x3 = repmat([1; 1; 1; 1; -1; -1; -1; -1], n / 8, 1);
            A = [ones(n, 1), x1, x2, x3];
            rng(4);
            y = A * [0.5; 0.3; -0.05; 2] + 0.01 * randn(n, 1);
            penalized = [false; true; true; true];
            ols = alignest.robustRidgeFit(A, y, penalized, lambda=0);
            l1 = alignest.robustRidgeFit(A, y, penalized, lambda=0.1, penalty="l1");
            l2 = alignest.robustRidgeFit(A, y, penalized, lambda=0.1, penalty="l2");
            expected = sign(ols.coefficients(2:4)) .* max(abs(ols.coefficients(2:4)) - 0.1, 0);
            testCase.verifyEqual(l1.coefficients(2:4), expected, 'AbsTol', 1e-9);
            testCase.verifyEqual(l1.coefficients(3), 0, "λ より小さい係数はちょうど 0");
            testCase.verifyEqual(l1.coefficients(1), ols.coefficients(1), 'AbsTol', 1e-9);
            testCase.verifyEqual(l2.coefficients(2:4), ols.coefficients(2:4) / 1.1, 'AbsTol', 1e-9);
            onlySome = alignest.robustRidgeFit(A, y, [false; true; false; true], lambda=0.1, penalty="l1");
            testCase.verifyEqual(onlySome.coefficients(3), ols.coefficients(3), 'AbsTol', 1e-9, "かけない列は最小二乗");
            huber = alignest.robustRidgeFit(A, y, penalized, lambda=0.1, penalty="l1", loss="huber");
            testCase.verifyEqual(huber.coefficients(3), 0);
            testCase.verifyTrue(huber.converged);
            testCase.verifyError(@() alignest.robustRidgeFit(A, y, penalized, penalty="l3"), 'MATLAB:validators:mustBeMember');
        end

        function penaltyOrdersChooseTheShrunkTerms(testCase)
            % かける次数を選ぶ：強い L2 を3次だけにかけると3次の項（k13）だけが 0 に近づき、2次の項（k7）は変わらない
            % （点が対称なので x^3 と x^2 は無関係）。L1 は効かない小さな項をちょうど 0 にする。設定の確かめと以前の設定
            truth = struct("dx", [1, 0.5; 3, 0.02; 5, -0.01; 7, 0.001; 13, 1e-5], ...
                "dy", [2, -0.3; 4, 0.01; 6, 0.015; 8, -0.0008]);
            wafer = struct("label", "W1", "points", waferFrom(testCase, truth));
            settings = alignest.defaultSettings();
            settings.highOrder = struct("maker", "nikon", "unit", "common", "waferOrder", 0, "loss", "ols", ...
                "regularization", "none");
            ols = alignest.shotHighOrder(wafer, settings);
            valueOf = @(result, k) result.coefficients.value(result.coefficients.k == k & ...
                result.coefficients.component == "Shot 高次補正");
            testCase.verifyEqual(valueOf(ols, 13), 1e-5, 'AbsTol', 1e-12);
            settings.highOrder.regularization = "l2";
            settings.highOrder.lambda = 1e6;
            settings.highOrder.penaltyOrders = 3;
            third = alignest.shotHighOrder(wafer, settings);
            testCase.verifyLessThan(abs(valueOf(third, 13)), 1e-9, "3次だけを 0 に近づける");
            testCase.verifyEqual(valueOf(third, 7), 0.001, 'AbsTol', 1e-9, "2次はかけないので変わらない");
            testCase.verifyTrue(contains(third.description, "L2 正則化（3次の項、λ = 1e+06）"));
            settings.highOrder.penaltyOrders = 1;
            first = alignest.shotHighOrder(wafer, settings);
            testCase.verifyLessThan(abs(valueOf(first, 3)), 1e-6, "1次（k3）にもかけられる");
            testCase.verifyEqual(valueOf(first, 1), 0.5, 'AbsTol', 1e-6, "定数（k1）にはかけない");
            settings.highOrder.regularization = "l1";
            settings.highOrder.lambda = 0.05;
            settings.highOrder.penaltyOrders = 2:6;
            l1 = alignest.shotHighOrder(wafer, settings);
            testCase.verifyEqual(valueOf(l1, 13), 0, "効かない小さな項はちょうど 0");
            testCase.verifyNotEqual(valueOf(l1, 7), 0);
            testCase.verifyTrue(contains(l1.description, "L1 正則化（2〜6次の項、λ = 0.05）"));
            % 設定の確かめ
            bad = {"penaltyOrders", 0; "penaltyOrders", 7; "penaltyOrders", 1.5; "regularization", "l3"};
            for k = 1:size(bad, 1)
                broken = alignest.defaultSettings();
                broken.highOrder.(bad{k, 1}) = bad{k, 2};
                testCase.verifyError(@() alignest.highOrderOptions(broken), ...
                    "alignest:" + ternaryText(bad{k, 1} == "regularization", "highOrderRegularization", ...
                    "highOrderPenaltyOrders"));
            end
            empty = alignest.defaultSettings();
            empty.highOrder.penaltyOrders = zeros(1, 0);
            testCase.verifyError(@() alignest.highOrderOptions(empty), 'alignest:highOrderPenaltyOrders');
            empty.highOrder.regularization = "none";
            testCase.verifyTrue(contains(alignest.highOrderOptions(empty).description, "正則化なし"));
            % 以前の設定（L2 のオン・オフ）：画面の外から渡しても、設定ファイルから読んでも同じ意味
            old = struct("highOrder", struct("l2", false));
            testCase.verifyEqual(alignest.highOrderOptions(old).regularization, "none");
            old.highOrder.l2 = true;
            testCase.verifyEqual(alignest.highOrderOptions(old).regularization, "l2");
            file = [tempname, '.json'];
            fileId = fopen(file, 'w', 'n', 'UTF-8');
            fwrite(fileId, '{"highOrder": {"l2": false, "lambda": 0.3}}', 'char');
            fclose(fileId);
            loaded = alignest.loadSettings(file);
            delete(file);
            testCase.verifyEqual(loaded.highOrder.regularization, "none");
            testCase.verifyEqual(loaded.highOrder.lambda, 0.3);
        end

        function outputsMatchTheResult(testCase)
            % 書き出しの表：計測データの形（値・Sts・Mark の番号・評価の単位）、Shot ごとの k（k1 は Wafer 成分を足した値）、
            % 補正の比較の全条件、CSV（空欄・読み直し）と Excel（シート）
            truth = struct("dx", [1, 0.5; 3, 0.02; 5, -0.01; 9, 0.0005], "dy", [2, -0.3; 4, 0.01; 6, 0.015]);
            points = waferFrom(testCase, truth);
            points.valueX = points.valueX + 0.01 * points.Xc;
            points.valueX(5) = NaN;   % 値の無い点
            n = height(points);
            unit = struct("operation", "OP1", "eqpId", "EQ1", "lotId", "LOT1", "wafer", "W1", ...
                "dateTime", "2026/10/31 10:00:00", "marks", struct("markNo", 100 + (1:n).'));
            wafer = struct("label", "W1 (EQ1)", "points", points, "unit", unit);
            settings = alignest.defaultSettings();
            settings.highOrder = struct("maker", "nikon", "unit", "common", "waferOrder", 1, "loss", "ols", ...
                "regularization", "none");
            result = alignest.shotHighOrder(wafer, settings);
            data = alignest.highOrderMeasurementTable(result, wafer, "correction");
            testCase.verifyEqual(string(data.Properties.VariableNames), ["Operation", "EqpId", "LotID", "Wafer", ...
                "DateTime", "shotNo", "Direction", "Xmm", "Ymm", "Radius", "markNo", "markXmm", "markYmm", "measX", ...
                "measY", "StsX", "StsY"], "Overlay 計測ルールの列の順");
            testCase.verifyEqual(data.measX, result.points.correctionX);
            testCase.verifyEqual(unique(data.Wafer), "W1", "評価の単位の Wafer ID");
            testCase.verifyEqual(data.markNo, unit.marks.markNo);
            testCase.verifyEqual(data.StsX(5), -1);
            testCase.verifyEqual(nnz(data.StsX ~= 0), 1);
            testCase.verifyEqual(data.Xmm, points.Xc);
            % CSV：値の無いところは空欄、読み直すと同じ値
            file = [tempname, '.csv'];
            removeFile = onCleanup(@() delete(file));
            alignest.writeHighOrderTable(file, data);
            text = string(fileread(file));
            lines = splitlines(strip(text));
            testCase.verifyTrue(contains(lines(6), ",,") && endsWith(lines(6), ",-1,0"), ...
                "5番目の点：measX は空欄、StsX は -1・StsY は 0");
            back = alignest.readMeasurementFile(file);
            testCase.verifyEqual(height(back), n);
            testCase.verifyEqual(back.measY, data.measY, 'AbsTol', 1e-9);
            testCase.verifyEqual(string(back.Properties.VariableNames(1)), "Operation", "先頭の BOM は読み飛ばす");
            % 単位の無い入力：Wafer は画面の名前、markNo は Shot 内の座標の組の番号
            bare = alignest.highOrderMeasurementTable(result, struct("label", "W1 (EQ1)", "points", points), "residual");
            testCase.verifyEqual(unique(bare.Wafer), "W1 (EQ1)");
            testCase.verifyEqual(numel(unique(bare.markNo)), size(testCase.Grid.local, 1));
            % Shot ごとの k：Wafer 内で共通なら k3 はどの Shot も同じ、k1 は Wafer 成分（0.01 × Xc）を足した値
            shots = alignest.highOrderShotTable(result);
            testCase.verifyEqual(height(shots), size(testCase.Grid.centers, 1));
            testCase.verifyEqual(shots.("k3[nm/mm]"), repmat(0.02, height(shots), 1), 'AbsTol', 1e-9);
            testCase.verifyEqual(shots.("Wafer成分dx[nm](k1に含む)"), 0.01 * shots.Xmm, 'AbsTol', 1e-9);
            testCase.verifyEqual(shots.("k1[nm]"), 0.5 + 0.01 * shots.Xmm, 'AbsTol', 1e-8);
            testCase.verifyEqual(shots.("k9[nm/mm^2]"), repmat(0.0005, height(shots), 1), 'AbsTol', 1e-9);
            % Shot ごと：Shot ごとの k をそのまま並べる
            settings.highOrder.unit = "shot";
            perShot = alignest.shotHighOrder(wafer, settings);
            shotK = alignest.highOrderShotTable(perShot);
            k3 = perShot.coefficients(perShot.coefficients.k == 3, :);
            [~, row] = ismember(k3.shotNo, shotK.shotNo);
            testCase.verifyEqual(shotK.("k3[nm/mm]")(row), k3.value, 'AbsTol', 1e-12);
            testCase.verifyEqual(shotK.("k1[nm]"), 0.5 + 0.01 * shotK.Xmm, 'AbsTol', 1e-8, "Shot ごとの k1 も Shot 中心の並進");
            % 補正の比較の全条件：条件ごとに X・Y の列。計算できなかった条件は書かない
            conditions = alignest.highOrderConditionTable({result, [], perShot}, ["共通", "失敗", "Shot ごと"], "residual");
            names = string(conditions.Properties.VariableNames);
            testCase.verifyEqual(names(end - 3:end), ["1. 共通：高次補正の残差X[nm]", "1. 共通：高次補正の残差Y[nm]", ...
                "3. Shot ごと：高次補正の残差X[nm]", "3. Shot ごと：高次補正の残差Y[nm]"]);
            testCase.verifyEqual(conditions.("3. Shot ごと：高次補正の残差X[nm]"), perShot.points.residualX);
            testCase.verifyError(@() alignest.highOrderConditionTable({[]}, "失敗", "residual"), ...
                'alignest:highOrderConditions');
            % Excel：説明と値のシート。拡張子の誤り
            workbook = [tempname, '.xlsx'];
            removeWorkbook = onCleanup(@() delete(workbook));
            alignest.writeHighOrderTable(workbook, shots, ["補正", result.description]);
            testCase.verifyEqual(string(sheetnames(workbook)).', ["説明", "値"]);
            testCase.verifyError(@() alignest.writeHighOrderTable([tempname, '.txt'], shots), 'alignest:exportType');
        end

        function appWritesValuesAndChoosesRegularization(testCase)
            % 画面：正則化（なし・L2・L1）とかける次数の欄、書き出しのタブ（3つの表・はじめの行・書き出し・読み直し）、
            % 補正の比較を比べ直す前は全条件を書かない、設定ファイル
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual(c.highOrderRegularization.Value, 'l2');
            testCase.verifyEqual(find([c.highOrderPenaltyOrders.Value]), 2:6, "初期値は2次以上");
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            app.setHighOrderSource("data");
            app.setHighOrderSettings(regularization="none");
            testCase.verifyEqual(string(c.highOrderLambda.Enable), "off");
            testCase.verifyEqual(string(c.highOrderPenaltyOrders(1).Enable), "off");
            app.setHighOrderSettings(regularization="l1", penaltyOrders=[1, 3], lambda=0.05);
            testCase.verifyEqual(string(c.highOrderLambda.Enable), "on");
            result = app.computeHighOrder(0);
            testCase.verifyTrue(contains(result.description, "L1 正則化（1・3次の項、λ = 0.05）"));
            testCase.verifyEqual(app.Settings.highOrder.penaltyOrders, [1, 3]);
            testCase.verifyFalse(isfield(app.Settings.highOrder, "l2"));
            % 書き出しのタブ
            c.highOrderOutputs.SelectedTab = c.highOrderOutputTab;
            c.highOrderOutputs.SelectionChangedFcn(c.highOrderOutputs, struct("NewValue", c.highOrderOutputTab));
            values = app.exportHighOrderValues("points", "residual");
            testCase.verifyEqual(height(values), 1980);
            testCase.verifyEqual(height(c.highOrderOutputTable.Data), 200, "画面にははじめの 200 行");
            testCase.verifyTrue(contains(string(c.highOrderOutputInfo.Text), "1980 行"));
            shots = app.exportHighOrderValues("shots");
            testCase.verifyEqual(height(shots), 495, "5 Wafer × 99 Shot");
            testCase.verifyEqual(string(c.highOrderOutputValue.Enable), "off", "Shot ごとの k では値を選ばない");
            testCase.verifyError(@() app.exportHighOrderValues("conditions", "residual"), 'alignest:highOrderConditions');
            c.highOrderOutputKind.Value = 'conditions';
            c.highOrderOutputKind.ValueChangedFcn(c.highOrderOutputKind, []);
            testCase.verifyTrue(startsWith(string(c.highOrderOutputInfo.Text), "⚠"));
            testCase.verifyEqual(string(c.highOrderOutputWrite.Enable), "off");
            % 点ごとの残差を CSV に書き、別の画面で「1. データの読み込み」から読み直すと同じ値
            file = [tempname, '.csv'];
            removeFile = onCleanup(@() delete(file));
            app.exportHighOrderValues("points", "residual", file);
            other = AlignmentEstimationApp(false);
            cleanupOther = onCleanup(@() delete(other));
            other.loadFile(file);
            other.applyMapping();
            testCase.verifyEqual(numel(other.Data.units), 5);
            marks = other.Data.units(1).marks;
            mine = result.points(result.points.wafer == result.points.wafer(1), :);
            testCase.verifyEqual(marks.measX(marks.validX), mine.residualX(isfinite(mine.residualX)), 'AbsTol', 1e-8);
            % 補正の比較の全条件（比べた後に条件を足すと、比べ直すまで書かない）
            app.addHighOrderConditions("loss");
            app.compareHighOrderConditionsNow(0);
            workbook = [tempname, '.xlsx'];
            removeWorkbook = onCleanup(@() delete(workbook));
            all_ = app.exportHighOrderValues("conditions", "correction", workbook);
            testCase.verifyEqual(width(all_), 9 + 3 * 2, "点の列 + 補正前の値 + 3つの条件 × X・Y");
            testCase.verifyEqual(string(sheetnames(workbook)).', ["説明", "値"]);
            app.addHighOrderConditions("current");
            testCase.verifyError(@() app.exportHighOrderValues("conditions", "correction"), 'alignest:highOrderConditions');
            % 設定ファイル：正則化の種類とかける次数が残り、読むと欄も変わる
            settingsFile = [tempname, '.json'];
            alignest.saveSettings(app.Settings, settingsFile);
            loaded = alignest.loadSettings(settingsFile);
            delete(settingsFile);
            testCase.verifyEqual(loaded.highOrder.regularization, "l1");
            testCase.verifyEqual(loaded.highOrder.penaltyOrders, [1, 3]);
            loaded.highOrder.penaltyOrders = [2, 4];
            loaded.highOrder.regularization = "l2";
            app.setSettings(loaded);
            testCase.verifyEqual(find([c.highOrderPenaltyOrders.Value]), [2, 4]);
            testCase.verifyEqual(c.highOrderRegularization.Value, 'l2');
        end
    end
end

function points = waferFrom(testCase, terms)
% 合成の Wafer の点の表（alignest.highOrderUnitPoints の形）：Shot 内の座標の項（[k, 係数] の行。番号はカスタムの式と同じ）の和
centers = testCase.Grid.centers;
local = testCase.Grid.local;
nShots = size(centers, 1);
nMarks = size(local, 1);
Xc = repelem(centers(:, 1), nMarks, 1);
Yc = repelem(centers(:, 2), nMarks, 1);
L = repmat(local, nShots, 1);
custom = alignest.highOrderTerms("custom");
values = zeros(nShots * nMarks, 2);
axisNames = ["dx", "dy"];
for a = 1:2
    for row = 1:size(terms.(axisNames(a)), 1)
        term = custom(custom.k == terms.(axisNames(a))(row, 1), :);
        values(:, a) = values(:, a) + terms.(axisNames(a))(row, 2) * L(:, 1) .^ term.xPower .* L(:, 2) .^ term.yPower;
    end
end
points = table(repmat("計測値", nShots * nMarks, 1), strings(nShots * nMarks, 1), repelem((1:nShots).', nMarks, 1), Xc, ...
    Yc, L(:, 1), L(:, 2), Xc + L(:, 1), Yc + L(:, 2), values(:, 1), values(:, 2), 'VariableNames', ["source", "name", ...
    "shotNo", "Xc", "Yc", "localX", "localY", "x", "y", "valueX", "valueY"]);
end

function text = ternaryText(condition, whenTrue, whenFalse)
if condition
    text = whenTrue;
else
    text = whenFalse;
end
end
