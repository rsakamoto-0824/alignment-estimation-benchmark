classdef TestShotHighOrderWaferRt < matlab.unittest.TestCase
    %TESTSHOTHIGHORDERWAFERRT Wafer RT（「7. Shot高次補正」で RT モデルを Wafer レベルの補正に使う）：すべての Shot・外周だけの
    %   補正、次数の上限、補正の段階の残差、自由度、係数・Shot ごとの表・グリッド、書き出し、画面。

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
                    if hypot(cx, cy) < 145
                        centers(end + 1, :) = [cx, cy]; %#ok<AGROW>
                    end
                end
            end
            [lx, ly] = meshgrid(linspace(-12, 12, 7), linspace(-15, 15, 11));   % 1 Shot 7 × 11 点
            testCase.Grid = struct("centers", centers, "local", [lx(:), ly(:)]);
        end
    end

    methods (Test)
        function allShotsRecoverTheRtField(testCase)
            % すべての Shot：RT の場 + Shot 内の k を取り戻す（Wafer 成分の次数を選んでいても使わない）
            [points, field] = rtWafer(testCase, 3, @(p) true(height(p), 1));
            settings = highOrderSettings("all", 3, 2);
            result = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            testCase.verifyLessThan(max(abs([result.points.residualX; result.points.residualY])), 1e-8);
            testCase.verifyEqual([result.points.waferRtX, result.points.waferRtY], field, 'AbsTol', 1e-6);
            testCase.verifyTrue(all(result.points.waferRtUsed));
            coefficients = result.coefficients;
            testCase.verifyEmpty(coefficients(coefficients.component == "Wafer 成分", :), "Wafer 成分は使わない");
            rt = coefficients(coefficients.component == "Wafer RT", :);
            testCase.verifyEqual(height(rt), 4 + 2 * 10, "K = 3 の項の数");
            testCase.verifyEqual(unique(rt.axis), "dx・dy");
            testCase.verifyEqual(unique(rt.unit), "nm");
            testCase.verifyEqual(rt.term(1:4).', ["並進 X", "並進 Y", "非対称倍率", "直交度"]);
            testCase.verifyEqual(rt.value, rtTruth(3), 'AbsTol', 1e-6, "係数も取り戻す");
            testCase.verifyTrue(contains(result.description, "すべての Shot は Wafer RT 3 次"));
            testCase.verifyFalse(contains(result.description, "Wafer 成分"));
            testCase.verifyTrue(any(contains(result.messages, "すべての Shot は、Wafer RT（RT モデル 3 次")));
        end

        function outerShotsUseRtAndInnerShotsKeepThePolynomial(testCase)
            % 外周だけ：外周の Shot は RT、内周の Shot は既存の Wafer 成分で補正する
            isOuter = @(p) hypot(p.Xc, p.Yc) >= 100;
            [points, field] = rtWafer(testCase, 5, isOuter);
            inner = ~isOuter(points);
            polynomialX = 0.02 * points.Xc + 3e-4 * points.Xc .* points.Yc;
            polynomialY = -0.01 * points.Yc + 2e-4 * points.Xc .^ 2;
            points.valueX(inner) = points.valueX(inner) + polynomialX(inner);
            points.valueY(inner) = points.valueY(inner) + polynomialY(inner);
            settings = highOrderSettings("outer", 5, 2);
            settings.highOrder.outerRadiusMm = 100;
            result = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            testCase.verifyLessThan(max(abs([result.points.residualX; result.points.residualY])), 1e-7);
            testCase.verifyEqual(result.points.waferRtUsed, ~inner);
            testCase.verifyEqual(result.points.waferRtX(inner), zeros(nnz(inner), 1), "内周の Shot に RT は当てない");
            testCase.verifyEqual([result.points.waferRtX(~inner), result.points.waferRtY(~inner)], field(~inner, :), ...
                'AbsTol', 1e-6);
            coefficients = result.coefficients;
            wafer = coefficients(coefficients.component == "Wafer 成分", :);
            testCase.verifyEqual(unique(wafer.zone), "内周", "Wafer 成分は内周だけ");
            testCase.verifyEqual(unique(coefficients.zone(coefficients.component == "Wafer RT")), "外周");
            term = @(axisName, name) wafer.value(wafer.axis == axisName & wafer.term == name);
            testCase.verifyEqual(term("dx", "Xc"), 0.02, 'AbsTol', 1e-9);
            testCase.verifyEqual(term("dx", "Xc·Yc"), 3e-4, 'AbsTol', 1e-9);
            testCase.verifyEqual(term("dy", "Yc"), -0.01, 'AbsTol', 1e-9);
            testCase.verifyEqual(term("dy", "Xc^2"), 2e-4, 'AbsTol', 1e-9);
            testCase.verifyTrue(contains(result.description, "外周（Shot 中心の半径 100 mm 以上）は Wafer RT 5 次"));
            testCase.verifyTrue(any(contains(result.messages, "内周の Shot は Wafer 成分（2 次）")));
            % 外周の式と一緒に使える
            settings.highOrder.outerMaker = "asml";
            both = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            testCase.verifyLessThan(max(abs([both.points.residualX; both.points.residualY])), 1e-6);
            testCase.verifyEqual(both.points.waferRtUsed, ~inner);
        end

        function pointsWithoutGroupAreLeftOutOfRt(testCase)
            % Scan 方向の分からない点は、補正の式と同じく RT の当てはめにも使わない
            points = rtWafer(testCase, 2, @(p) true(height(p), 1));
            points.direction = 1 + mod(points.shotNo, 2);
            unknown = points.shotNo == 10;
            points.direction(unknown) = NaN;
            points.valueX(unknown) = points.valueX(unknown) + 500;
            settings = highOrderSettings("all", 2, 0);
            settings.highOrder.unit = "scan";
            result = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            testCase.verifyLessThan(max(abs(result.points.residualX(~unknown))), 1e-8, "500 nm 足した Shot の影響を受けない");
            testCase.verifyTrue(all(isnan(result.points.residualX(unknown))));
        end

        function perShotUnitWorksWithOuterRt(testCase)
            % Shot ごと：内周の Wafer 成分を先に引く流れでも、外周の RT と一緒に使える。k1・k2 は Wafer の分を除いた値
            isOuter = @(p) hypot(p.Xc, p.Yc) >= 100;
            points = rtWafer(testCase, 2, isOuter);
            inner = ~isOuter(points);
            points.valueX(inner) = points.valueX(inner) + 0.02 * points.Xc(inner);
            settings = highOrderSettings("outer", 2, 1);
            settings.highOrder.outerRadiusMm = 100;
            settings.highOrder.unit = "shot";
            result = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            testCase.verifyLessThan(max(abs([result.points.residualX; result.points.residualY])), 1e-7);
            wafer = result.coefficients(result.coefficients.component == "Wafer 成分" & result.coefficients.axis == "dx", :);
            testCase.verifyEqual(wafer.value(wafer.term == "Xc"), 0.02, 'AbsTol', 1e-9);
            shots = result.coefficients(result.coefficients.component == "Shot 高次補正" & result.coefficients.k == 1, :);
            testCase.verifyLessThan(max(abs(shots.value)), 1e-6, "Shot ごとの k1 に Wafer の分は入らない");
            testCase.verifyTrue(any(contains(result.messages, "補正量・残差は Wafer RT なしと同じ")));
            points.valueX = points.valueX + 0.4 * sin((1:height(points)).' * 1.1);
            plain = settings;
            plain.highOrder.waferRtRange = "none";
            wafer = struct("label", "W1", "points", points);
            testCase.verifyEqual(alignest.shotHighOrder(wafer, settings).points.residualX, ...
                alignest.shotHighOrder(wafer, plain).points.residualX, 'AbsTol', 1e-8, "Shot ごとの k1・k2 が吸収する");
        end

        function stagesAndSummaryIncludeRt(testCase)
            % 補正の段階の残差：Wafer 高次補正だけの残差 = 値 − RT、＋Shot 共通補正の残差は RT を含む
            isOuter = @(p) hypot(p.Xc, p.Yc) >= 100;
            points = rtWafer(testCase, 2, isOuter);
            settings = highOrderSettings("outer", 2, 2);
            settings.highOrder.outerRadiusMm = 100;
            settings.highOrder.unit = "row";
            result = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            outer = isOuter(points);
            testCase.verifyEqual(result.points.waferResidualX(outer), points.valueX(outer) - result.points.waferRtX(outer), ...
                'AbsTol', 1e-9);
            testCase.verifyTrue(all(isfinite(result.points.waferResidualX(~outer))), "内周は Wafer 成分だけの残差");
            fitted = result.points.valueX - result.points.commonResidualX;
            testCase.verifyLessThan(max(abs(fitted(outer) - points.valueX(outer))), 1e-6, "外周は RT + Shot 共通で表せる");
            none = alignest.shotHighOrder(struct("label", "W1", "points", points), highOrderSettings("none", 2, 2));
            testCase.verifyEmpty(none.coefficients(none.coefficients.component == "Wafer RT", :));
            testCase.verifyEqual([none.points.waferRtX; none.points.waferRtY], zeros(2 * height(points), 1));
            testCase.verifyFalse(any(none.points.waferRtUsed));
            testCase.verifyFalse(contains(none.description, "Wafer RT"));
            testCase.verifyFalse(any(contains(none.messages, "Wafer RT")));
        end

        function degreesOfFreedomCountTheRtTerms(testCase)
            % 回帰の自由度（ハット行列の対角の和）：k の項の数（dx・dy）+ RT の項の数
            points = rtWafer(testCase, 3, @(p) true(height(p), 1));
            points.valueX = points.valueX + 0.3 * sin((1:height(points)).' * 1.7);
            points.valueY = points.valueY + 0.3 * cos((1:height(points)).' * 2.3);
            result = alignest.shotHighOrder(struct("label", "W1", "points", points), highOrderSettings("all", 3, 0));
            nRt = nnz(result.coefficients.component == "Wafer RT");
            nTerms = nnz(result.coefficients.component == "Shot 高次補正");
            total = sum(result.points.leverageX) + sum(result.points.leverageY);
            testCase.verifyEqual(total, nRt + nTerms, 'AbsTol', 1e-6);
            row = result.summary(result.summary.axis == "X" & result.summary.wafer == "W1", :);
            testCase.verifyTrue(isfinite(row.adjustedRSquared));
            testCase.verifyLessThan(row.adjustedRSquared, row.rSquared);
        end

        function fewShotsLeaveHighTermsAtZero(testCase)
            % Shot が少なくて決まらない RT の項は 0 にして、メモと知らせを出す。Wafer に外周の Shot が無ければ何もしない
            points = rtWafer(testCase, 2, @(p) true(height(p), 1));
            near = hypot(points.Xc, points.Yc) < 40;
            few = points(near, :);
            result = alignest.shotHighOrder(struct("label", "W1", "points", few), highOrderSettings("all", 5, 0));
            rt = result.coefficients(result.coefficients.component == "Wafer RT", :);
            testCase.verifyGreaterThan(nnz(rt.note ~= ""), 0);
            testCase.verifyEqual(rt.value(rt.note ~= ""), zeros(nnz(rt.note ~= ""), 1));
            testCase.verifyTrue(any(contains(result.messages, "Wafer RT の項が決まらない Wafer が 1 個")));
            testCase.verifyTrue(all(isfinite(result.points.residualX)));
            noOuter = highOrderSettings("outer", 3, 1);
            noOuter.highOrder.outerRadiusMm = 500;
            plain = highOrderSettings("none", 3, 1);
            wafer = struct("label", "W1", "points", points);
            testCase.verifyEqual(alignest.shotHighOrder(wafer, noOuter).points.residualX, ...
                alignest.shotHighOrder(wafer, plain).points.residualX, 'AbsTol', 1e-12, "外周の Shot が無いと RT なしと同じ");
        end

        function differentLossesUseLeastSquares(testCase)
            % X・Y で損失関数が違うと RT は最小二乗。同じなら Huber で、外れた Shot の影響を抑える
            points = rtWafer(testCase, 2, @(p) true(height(p), 1));
            shot = points.shotNo == 10;
            field = points.valueX;
            points.valueX(shot) = points.valueX(shot) + 200;
            robust = highOrderSettings("all", 2, 0);
            robust.highOrder.loss = "huber";
            huber = alignest.shotHighOrder(struct("label", "W1", "points", points), robust);
            mixed = robust;
            mixed.highOrder.loss = ["huber", "ols"];
            least = alignest.shotHighOrder(struct("label", "W1", "points", points), mixed);
            testCase.verifyTrue(any(contains(least.messages, "Wafer RT は最小二乗で")));
            testCase.verifyFalse(any(contains(huber.messages, "Wafer RT は最小二乗で")));
            clean = alignest.shotHighOrder(struct("label", "W1", "points", replaceColumn(points, field)), robust);
            gap = @(run) max(abs(run.points.waferRtX(~shot) - clean.points.waferRtX(~shot)));
            testCase.verifyLessThan(gap(huber), gap(least), "Huber は外れた Shot の影響が小さい");
        end

        function optionsAreChecked(testCase)
            % 次数は 1〜5、範囲は none・all・outer。以前の設定（項目が無い）は使わない
            settings = alignest.defaultSettings();
            options = alignest.highOrderOptions(settings);
            testCase.verifyEqual([options.waferRtRange, string(options.waferRtOrder)], ["none", "3"]);
            old = rmfield(settings.highOrder, ["waferRtRange", "waferRtOrder"]);
            settings.highOrder = old;
            testCase.verifyEqual(alignest.highOrderOptions(settings).waferRtRange, "none");
            for order = [0, 6, 2.5]
                settings.highOrder = old;
                settings.highOrder.waferRtOrder = order;
                testCase.verifyError(@() alignest.highOrderOptions(settings), 'alignest:highOrderWafer');
            end
            settings.highOrder = old;
            settings.highOrder.waferRtRange = "inner";
            testCase.verifyError(@() alignest.highOrderOptions(settings), 'alignest:highOrderWafer');
            settings.highOrder = old;
            settings.highOrder.waferRtRange = 'outer';
            testCase.verifyEqual(alignest.highOrderOptions(settings).waferRtRange, "outer", "文字でも読める");
        end

        function tablesAndGridCarryTheRtPart(testCase)
            % 段階の表の Wafer RT の行、Shot ごとの補正値の WaferRT の列と合計 k1・k2、グリッド（好きな位置の補正量）
            isOuter = @(p) hypot(p.Xc, p.Yc) >= 100;
            points = rtWafer(testCase, 3, isOuter);
            settings = highOrderSettings("outer", 3, 1);
            settings.highOrder.outerRadiusMm = 100;
            result = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            levels = alignest.highOrderLevels(result);
            order = unique(levels.level, 'stable').';
            testCase.verifyEqual(order, ["Wafer 低次", "Wafer RT", "Shot 共通 低次", "Shot 共通 高次"]);
            testCase.verifyEqual(height(levels), height(result.coefficients), "係数の行がすべて入る");
            data = alignest.highOrderShotTable(result);
            names = string(data.Properties.VariableNames);
            testCase.verifyTrue(all(ismember(["WaferRTdx[nm]", "WaferRTdy[nm]"], names)));
            mine = result.points(isfinite(result.points.shotNo), :);
            atCenter = mine.localX == 0 & mine.localY == 0;
            center = mine(atCenter, :);
            [~, row] = ismember(data.shotNo, center.shotNo);
            testCase.verifyEqual(isnan(data.("WaferRTdx[nm]")), ~center.waferRtUsed(row));
            testCase.verifyEqual(isnan(data.("Wafer低次dx[nm]")), center.waferRtUsed(row), "RT の Shot は Wafer 成分が空欄");
            testCase.verifyEqual(data.("合計k1[nm]"), center.correctionX(row), 'AbsTol', 1e-9, "Shot 中心の補正量");
            testCase.verifyEqual(data.("合計k2[nm]"), center.correctionY(row), 'AbsTol', 1e-9);
            [~, first] = unique(mine.shotNo);
            shots = table(mine.shotNo(first), mine.x(first) - mine.localX(first), mine.y(first) - mine.localY(first), ...
                mine.group(first), mine.waferRtUsed(first), mine.waferRtX(first), mine.waferRtY(first), 'VariableNames', ...
                ["shotNo", "Xc", "Yc", "group", "waferRtUsed", "waferRtX", "waferRtY"]);
            local = testCase.Grid.local;
            [dx, dy] = alignest.highOrderModelAt(result.coefficients, "common", "W1", shots, local);
            for s = [1, height(shots)]
                rows = find(mine.shotNo == shots.shotNo(s));
                [~, position] = ismember([mine.localX(rows), mine.localY(rows)], local, 'rows');
                testCase.verifyEqual(dx(s, position).', mine.correctionX(rows), 'AbsTol', 1e-9);
                testCase.verifyEqual(dy(s, position).', mine.correctionY(rows), 'AbsTol', 1e-9);
            end
            plain = alignest.highOrderShotTable(alignest.shotHighOrder(struct("label", "W1", "points", points), ...
                highOrderSettings("none", 3, 1)));
            testCase.verifyFalse(any(contains(string(plain.Properties.VariableNames), "WaferRT")), "使わなければ列も無い");
        end

        function excelExplainsTheRtPart(testCase)
            % 書き出し：補正値の段階・Shot ごとの補正値・点ごとの値に Wafer RT が入る
            points = rtWafer(testCase, 2, @(p) true(height(p), 1));
            settings = highOrderSettings("outer", 2, 1);
            settings.highOrder.outerRadiusMm = 100;
            result = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            filePath = [tempname, '.xlsx'];
            cleanup = onCleanup(@() delete(filePath));
            alignest.exportHighOrder(filePath, result);
            levels = readtable(filePath, 'Sheet', '補正値', 'VariableNamingRule', 'preserve', 'TextType', 'string');
            testCase.verifyTrue(any(levels.("段階") == "Wafer RT"));
            pointSheet = readcell(filePath, 'Sheet', '点ごとの値', 'Range', '1:1');
            testCase.verifyTrue(any(string(pointSheet) == "Wafer RTの補正量X[nm]"));
            shotSheet = readcell(filePath, 'Sheet', 'Shotごとの補正値', 'Range', '1:1');
            testCase.verifyTrue(any(string(shotSheet) == "WaferRTdx[nm]"));
            notes = readcell(filePath, 'Sheet', '説明');
            testCase.verifyTrue(any(contains(string(notes(:, 2)), "Wafer RT：RT モデルの係数")));
        end

        function screenSetsAndShowsTheRtChoice(testCase)
            % 画面：欄の選択と使える欄、計算と知らせ、補正の比較の条件の表、設定の読み直し
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual(string(c.highOrderRtRange.Value), "none");
            testCase.verifyEqual(string(c.highOrderRtOrder.Enable), "off", "使わないときは次数を選ばない");
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            app.setHighOrderSource("data");
            app.setHighOrderSettings(waferRtRange="outer", waferRtOrder=2, waferOrder=1, outerRadiusMm=100);
            testCase.verifyEqual(app.Settings.highOrder.waferRtRange, "outer");
            testCase.verifyEqual(app.Settings.highOrder.waferRtOrder, 2);
            testCase.verifyEqual(string(c.highOrderRtOrder.Enable), "on");
            testCase.verifyEqual(string(c.highOrderWaferOrder.Enable), "on");
            result = app.computeHighOrder(0);
            testCase.verifyTrue(any(result.points.waferRtUsed));
            testCase.verifyTrue(any(contains(string(c.highOrderMessage.Value), "Wafer RT")));
            summary = app.drawHighOrderMap(1, "wafer", "correction", "grid");
            testCase.verifyGreaterThan(summary.n, 0);
            app.setHighOrderSettings(waferRtRange="all");
            testCase.verifyEqual(string(c.highOrderWaferOrder.Enable), "off", "すべて RT なら Wafer 成分は使わない");
            app.addHighOrderConditions("loss");
            labels = string(c.highOrderConditionTable.Data(:, 5));
            testCase.verifyEqual(unique(labels), "RT 2次");
            settings = app.Settings;
            settings.highOrder.waferRtRange = "outer";
            settings.highOrder.waferRtOrder = 5;
            app.setSettings(settings);
            testCase.verifyEqual([string(c.highOrderRtRange.Value), string(c.highOrderRtOrder.Value)], ["outer", "5"]);
        end
    end
end

function settings = highOrderSettings(range, order, waferOrder)
% 回帰は最小二乗・正則化なし。k は ASML の1次の項と3次の項
settings = alignest.defaultSettings();
settings.highOrder = struct("maker", "custom", "excludedTerms", 13:38, "unit", "common", "waferOrder", waferOrder, ...
    "loss", "ols", "regularization", "none", "waferRtRange", range, "waferRtOrder", order);
end

function coefficients = rtTruth(order)
% 合成の RT の係数（並進は 0 にして、Shot 内の k1・k2 と分ける）
nTerms = 4 + 2 * size(alignest.basis.zernikeModes(order), 1);
coefficients = 3 * sin((1:nTerms).' * 1.3);
coefficients(1:2) = [8; -6];
end

function [points, field] = rtWafer(testCase, order, inScope)
% 合成の Wafer：inScope の Shot に RT の場（次数 order）、すべての Shot に Shot 内の1次の k。field：RT の場（点の数 × 2。
% inScope でない Shot は 0）
centers = testCase.Grid.centers;
local = testCase.Grid.local;
nShots = size(centers, 1);
nLocal = size(local, 1);
shotNo = reshape(repmat(1:nShots, nLocal, 1), [], 1);
Xc = centers(shotNo, 1);
Yc = centers(shotNo, 2);
localX = repmat(local(:, 1), nShots, 1);
localY = repmat(local(:, 2), nShots, 1);
n = numel(shotNo);
points = table(repmat("mark", n, 1), "M" + string((1:n).'), shotNo, Xc, Yc, localX, localY, Xc + localX, Yc + localY, ...
    nan(n, 1), nan(n, 1), nan(n, 1), 'VariableNames', ["source", "name", "shotNo", "Xc", "Yc", "localX", "localY", ...
    "x", "y", "valueX", "valueY", "direction"]);
[basisX, basisY] = alignest.basis.rtDesign([Xc, Yc] / 150, order);
coefficients = rtTruth(order);
field = [basisX * coefficients, basisY * coefficients] .* inScope(points);
points.valueX = field(:, 1) + 0.03 * localX - 0.02 * localY;
points.valueY = field(:, 2) + 0.01 * localX + 0.04 * localY;
end

function points = replaceColumn(points, valueX)
points.valueX = valueX;
end
