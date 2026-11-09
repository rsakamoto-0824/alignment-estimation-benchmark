classdef TestShotHighOrderShotCommon < matlab.unittest.TestCase
    %TESTSHOTHIGHORDERSHOTCOMMON Shot 共通を先に引いてから Shot ごとに求める Shot 高次補正（「7. Shot高次補正」の
    %   「Shot 共通補正」）：計算した Shot 共通・入力した Shot 共通、Shot ごとの次数の上限、外周の式、点が足りない Shot の扱い、
    %   補正値の段階・Shot ごとの表・グリッド、回帰の自由度、設定の確かめ、書き出し、画面。

    properties
        Root
        Centers   % 合成の Wafer の Shot 中心 [mm]
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
            testCase.Centers = centers;
        end
    end

    methods (Test)
        function fitWithAllTermsMatchesIndependentShots(testCase)
            % Shot ごとに使う項をすべて求め、正則化なしなら、補正量・Shot ごとの k は Shot 共通を引かないときと同じ。
            % 段階の「Shot 毎」は Shot ごとの k − Shot 共通の k
            points = noisy(sequentialWafer(testCase, [], Inf));
            wafer = struct("label", "W1", "points", points);
            plain = alignest.shotHighOrder(wafer, sequentialSettings("none", 0));
            fitted = alignest.shotHighOrder(wafer, sequentialSettings("fit", 0));
            testCase.verifyEqual(fitted.points.correctionX, plain.points.correctionX, 'AbsTol', 1e-9);
            testCase.verifyEqual(fitted.points.correctionY, plain.points.correctionY, 'AbsTol', 1e-9);
            plainRows = plain.coefficients(plain.coefficients.component == "Shot 高次補正", :);
            fittedRows = fitted.coefficients(fitted.coefficients.component == "Shot 高次補正", :);
            testCase.verifyEqual(fittedRows.value, plainRows.value, 'AbsTol', 1e-8, "Shot ごとの k は Shot 共通を足した値");
            testCase.verifyTrue(any(contains(fitted.messages, "Shot 共通を引かないときと同じ")));
            levels = alignest.highOrderLevels(fitted);
            each = levels(startsWith(levels.level, "Shot 毎") & levels.shotNo == 1 & levels.axis == "dx", :);
            common = fitted.commonCoefficients(fitted.commonCoefficients.axis == "dx", :);
            [~, position] = ismember(each.k, common.k);
            shotOne = fittedRows(fittedRows.shotNo == 1 & fittedRows.axis == "dx", :);
            [~, shotPosition] = ismember(each.k, shotOne.k);
            testCase.verifyEqual(each.value + common.value(position), shotOne.value(shotPosition), 'AbsTol', 1e-9);
        end

        function fitWithLowOrderShotsKeepsTheCommonShape(testCase)
            % Shot ごとは1次まで：Shot 共通の3次の形は Shot 共通の k で、Shot ごとの違い（1次）は Shot ごとの k で表せる。
            % Shot ごとに求めない項は Shot 共通の値（メモ）、段階の「Shot 毎 高次」は 0、グリッドは補正量と同じ、自由度は
            % Shot ごとの項 + 先に引いた Wafer 成分・Shot 共通の項
            [points, truth] = sequentialWafer(testCase, [], Inf);
            wafer = struct("label", "W1", "points", points);
            result = alignest.shotHighOrder(wafer, sequentialSettings("fit", 1));
            testCase.verifyLessThan(max(abs([result.points.residualX; result.points.residualY])), 1e-7);
            common = result.commonCoefficients;
            high = common(common.xPower + common.yPower >= 2, :);
            testCase.verifyEqual(high.value, reshape(truth{1}(high.k), [], 1), 'AbsTol', 1e-8);
            shotRows = result.coefficients(result.coefficients.component == "Shot 高次補正" & result.coefficients.shotNo == 1, :);
            shotHigh = shotRows(shotRows.xPower + shotRows.yPower >= 2, :);
            testCase.verifyEqual(shotHigh.value, reshape(truth{1}(shotHigh.k), [], 1), 'AbsTol', 1e-8);
            testCase.verifyEqual(unique(shotHigh.note), "Shot ごとには求めない項（Shot 共通の値）");
            levels = alignest.highOrderLevels(result);
            testCase.verifyLessThan(max(abs(levels.value(levels.level == "Shot 毎 高次"))), 1e-12);
            shotTable = alignest.highOrderShotTable(result);
            names = string(shotTable.Properties.VariableNames);
            k7 = names(startsWith(names, "合計k7["));
            testCase.verifyEqual(shotTable.(k7), repmat(truth{1}(7), height(shotTable), 1), 'AbsTol', 1e-8);
            nShots = size(testCase.Centers, 1);
            shots = table((1:nShots).', testCase.Centers(:, 1), testCase.Centers(:, 2), "Shot " + string((1:nShots).'), ...
                'VariableNames', ["shotNo", "Xc", "Yc", "group"]);
            [lx, ly] = meshgrid(linspace(-12, 12, 7), linspace(-15, 15, 11));
            [dx, ~] = alignest.highOrderModelAt(result.coefficients, "shot", "W1", shots, [lx(:), ly(:)]);
            testCase.verifyEqual(reshape(dx.', [], 1), result.points.correctionX, 'AbsTol', 1e-9, "グリッドも Shot 共通を含む");
            nCommon = nnz(common.axis == "dx");
            testCase.verifyEqual(sum(result.points.leverageX), 3 * nShots + 2 + nCommon, 'AbsTol', 1e-6);
            testCase.verifyTrue(contains(result.description, "求めた Shot 共通の k を先に引いて残りの1次までの項を Shot ごとに求める"));
        end

        function inputValuesAreSubtractedFirst(testCase)
            % 入力した Shot 共通の k を先に引く：正しい値なら残差は 0、0 のままなら Shot 共通の形が残る。Shot 共通の行は入力した
            % 値（メモ）、補正の段階「Wafer 高次補正＋Shot 共通補正」は入力した k を含む、自由度に入力した k は入れない
            [points, truth] = sequentialWafer(testCase, 6, Inf);
            wafer = struct("label", "W1", "points", points);
            settings = sequentialSettings("input", 1);
            settings.highOrder.shotCommonValues = truth{1};
            result = alignest.shotHighOrder(wafer, settings);
            testCase.verifyLessThan(max(abs([result.points.residualX; result.points.residualY])), 1e-7);
            rows = result.commonCoefficients;
            testCase.verifyEqual(unique(rows.note), "入力した値");
            testCase.verifyEqual(rows.value, reshape(truth{1}(rows.k), [], 1), 'AbsTol', 1e-12);
            staged = result.points.valueX - result.points.commonResidualX;   % Wafer 成分 + 入力した k の分
            terms = alignest.highOrderTerms("custom", 21:38);
            dxTerms = terms(terms.axis == "dx", :);
            inputPart = (points.localX .^ (dxTerms.xPower.') .* points.localY .^ (dxTerms.yPower.')) * ...
                reshape(truth{1}(dxTerms.k), [], 1);
            waferRows = result.coefficients(result.coefficients.component == "Wafer 成分" & result.coefficients.axis == "dx", :);
            waferPart = (points.Xc .^ (waferRows.xPower.') .* points.Yc .^ (waferRows.yPower.')) * waferRows.value;
            testCase.verifyEqual(staged, inputPart + waferPart, 'AbsTol', 1e-9);
            nShots = size(testCase.Centers, 1);
            testCase.verifyEqual(sum(result.points.leverageX), 3 * nShots + 2, 'AbsTol', 1e-6, "入力した k は求めていない");
            testCase.verifyTrue(any(contains(result.messages, "入力した Shot 共通の k を引いた残りで求めて先に")));
            settings.highOrder.shotCommonValues = zeros(1, 0);
            zero = alignest.shotHighOrder(wafer, settings);
            testCase.verifyGreaterThan(rms(zero.points.residualX), 0.05, "Shot 共通の形が残る");
            testCase.verifyEqual(zero.commonCoefficients.value, zeros(height(zero.commonCoefficients), 1));
        end

        function zonesUseInnerAndOuterValues(testCase)
            % 外周の式を分けるとき：入力は内周の式・外周の式で別。計算する Shot 共通も内周・外周の2組
            [points, truth] = sequentialWafer(testCase, 6, 100);
            wafer = struct("label", "W1", "points", points);
            settings = sequentialSettings("input", 1);
            settings.highOrder.outerMaker = "custom";
            settings.highOrder.outerExcludedTerms = 13:38;
            settings.highOrder.outerRadiusMm = 100;
            settings.highOrder.shotCommonValues = truth{1};
            settings.highOrder.shotCommonOuterValues = truth{2}(1:12);
            result = alignest.shotHighOrder(wafer, settings);
            testCase.verifyLessThan(max(abs([result.points.residualX; result.points.residualY])), 1e-7);
            rows = result.commonCoefficients;
            testCase.verifyEqual(sort(unique(rows.zone)), ["内周"; "外周"]);
            testCase.verifyEqual(nnz(rows.zone == "外周" & rows.axis == "dx"), 6, "外周の式は2次まで");
            [gridPoints, ~] = sequentialWafer(testCase, [], 100);
            settings.highOrder.shotCommon = "fit";
            fitted = alignest.shotHighOrder(struct("label", "W1", "points", gridPoints), settings);
            testCase.verifyLessThan(max(abs([fitted.points.residualX; fitted.points.residualY])), 1e-7);
            testCase.verifyEqual(sort(unique(fitted.commonCoefficients.zone)), ["内周"; "外周"]);
        end

        function shortageAppliesToShotTermsOnly(testCase)
            % 点が足りない Shot の扱いは Shot ごとに求める項だけに当てる：1次までなら6点の Shot でも足りる。全項を Shot ごとに
            % 求めて「全体の項を減らす」でも、Shot 共通の項は減らさず、減らした項は Shot 共通の値（表の「使う」も変えない）
            [points, ~] = sequentialWafer(testCase, 6, Inf);
            wafer = struct("label", "W1", "points", points);
            check = alignest.shotHighOrder(wafer, sequentialSettings("fit", 1), checkOnly=true);
            testCase.verifyEmpty(check.messages, "1次までなら足りる");
            plainCheck = alignest.shotHighOrder(wafer, sequentialSettings("none", 0), checkOnly=true);
            testCase.verifyNotEmpty(plainCheck.messages);
            allCheck = alignest.shotHighOrder(wafer, sequentialSettings("fit", 0), checkOnly=true);
            testCase.verifyTrue(any(contains(allCheck.messages, "減らすのは Shot ごとに求める項だけ")));
            result = alignest.shotHighOrder(wafer, sequentialSettings("fit", 0));
            dropped = [result.reduction.dropped];
            testCase.verifyNotEmpty(dropped);
            testCase.verifyEqual(result.options.excludedTerms, 21:38, "使う項は変えない");
            testCase.verifyEqual(nnz(result.commonCoefficients.axis == "dx"), 10, "Shot 共通はすべての項");
            testCase.verifyTrue(any(contains(result.messages, "Shot 共通の値だけにした項")));
            shotRows = result.coefficients(result.coefficients.component == "Shot 高次補正" & ...
                ismember(result.coefficients.k, dropped), :);
            testCase.verifyEqual(unique(shotRows.note), "Shot ごとには求めない項（Shot 共通の値）");
        end

        function regularizationShrinksTowardTheCommonShape(testCase)
            % 正則化をかけると、Shot ごとの高次の項は 0 ではなく Shot 共通の値に寄る（引かないときと補正量が違う）
            points = noisy(sequentialWafer(testCase, [], Inf));
            wafer = struct("label", "W1", "points", points);
            plainSettings = sequentialSettings("none", 0);
            plainSettings.highOrder.regularization = "l2";
            plainSettings.highOrder.lambda = 5;
            fitSettings = plainSettings;
            fitSettings.highOrder.shotCommon = "fit";
            plain = alignest.shotHighOrder(wafer, plainSettings);
            fitted = alignest.shotHighOrder(wafer, fitSettings);
            testCase.verifyGreaterThan(max(abs(fitted.points.correctionX - plain.points.correctionX)), 1e-3);
            testCase.verifyLessThan(rms(fitted.points.residualX), rms(plain.points.residualX));
            testCase.verifyFalse(any(contains(fitted.messages, "引かないときと同じ")));
        end

        function optionsAreChecked(testCase)
            % 設定の確かめと説明。Shot ごとでなければ Shot 共通は使わない
            settings = sequentialSettings("both", 0);
            testCase.verifyError(@() alignest.highOrderOptions(settings), 'alignest:highOrderShotCommon');
            settings = sequentialSettings("fit", 7);
            testCase.verifyError(@() alignest.highOrderOptions(settings), 'alignest:highOrderShotCommon');
            settings = sequentialSettings("input", 0);
            settings.highOrder.shotCommonValues = [1, NaN];
            testCase.verifyError(@() alignest.highOrderOptions(settings), 'alignest:highOrderShotCommon');
            settings.highOrder.shotCommonValues = [1, 2];
            options = alignest.highOrderOptions(settings);
            testCase.verifyTrue(contains(options.description, "入力した Shot 共通の k を先に引いて残りの Shot ごとに求める"));
            settings.highOrder.unit = "common";
            options = alignest.highOrderOptions(settings);
            testCase.verifyFalse(contains(options.description, "Shot 共通の k を先に"));
            defaults = alignest.defaultSettings().highOrder;
            testCase.verifyEqual([defaults.shotCommon, string(defaults.shotEachOrder)], ["none", "0"]);
        end

        function excelExplainsTheCommonPart(testCase)
            % 書き出し：「説明」に先に引いた Shot 共通、「補正値」に入力した値の行
            [points, truth] = sequentialWafer(testCase, 6, Inf);
            settings = sequentialSettings("input", 1);
            settings.highOrder.shotCommonValues = truth{1};
            result = alignest.shotHighOrder(struct("label", "W1", "points", points), settings);
            filePath = [tempname, '.xlsx'];
            cleanup = onCleanup(@() delete(filePath));
            alignest.exportHighOrder(filePath, result);
            levels = readtable(filePath, 'Sheet', '補正値', 'VariableNamingRule', 'preserve', 'TextType', 'string');
            testCase.verifyTrue(any(levels.("段階") == "Shot 共通 高次" & levels.("メモ") == "入力した値"));
            notes = readcell(filePath, 'Sheet', '説明');
            testCase.verifyTrue(any(contains(string(notes(:, 2)), "入力した値。先に引いた")));
        end

        function screenSetsInputsAndCopiesComputedValues(testCase)
            % 画面：欄の使える・使えない、「共通の値」の列（外周の式を分けると2列）と編集、計算した値を写す、計算、補正の
            % 比較の条件名、設定の読み直し
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual(string({c.highOrderShotCommon.Enable, c.highOrderShotEachOrder.Enable}), ["off", "off"], ...
                "Shot ごとでなければ使わない");
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            app.setHighOrderSource("data");
            app.setHighOrderSettings(unit="shot", shotCommon="fit", shotEachOrder=1);
            testCase.verifyEqual(string({c.highOrderShotCommon.Enable, c.highOrderShotEachOrder.Enable, ...
                c.highOrderCopyCommon.Enable}), ["on", "on", "off"]);
            testCase.verifyFalse(any(string(c.highOrderTermTable.ColumnName) == "共通の値"), "計算するときは入力しない");
            computed = app.computeHighOrder(0);
            testCase.verifyNotEmpty(computed.commonCoefficients);
            app.setHighOrderSettings(shotCommon="input");
            testCase.verifyEqual(string(c.highOrderCopyCommon.Enable), "on");
            names = reshape(string(c.highOrderTermTable.ColumnName), 1, []);
            testCase.verifyTrue(any(names == "共通の値"));
            values = app.copyHighOrderCommonValues();
            common = computed.commonCoefficients(computed.commonCoefficients.k == 1, :);
            testCase.verifyEqual(values{1}(1), mean(common.value), 'AbsTol', 1e-12, "Wafer の平均");
            testCase.verifyEqual(app.Settings.highOrder.shotCommonValues, values{1});
            row = find(string(c.highOrderTermTable.Data(:, 3)) == "k5", 1);
            valueColumn = find(names == "共通の値");
            testCase.verifyEqual(valueColumn, 6, "次数の右（横に送らなくても見える）");
            c.highOrderTermTable.CellEditCallback(c.highOrderTermTable, struct("Indices", [row, valueColumn], "NewData", 1.5));
            testCase.verifyEqual(app.Settings.highOrder.shotCommonValues(5), 1.5);
            c.highOrderTermTable.CellEditCallback(c.highOrderTermTable, struct("Indices", [row, valueColumn], "NewData", NaN));
            testCase.verifyEqual(app.Settings.highOrder.shotCommonValues(5), 1.5, "数でなければ変えない");
            testCase.verifyEqual(string(c.highOrderTermInfo.Text), "共通の値は数を入れてください");
            result = app.computeHighOrder(0);
            testCase.verifyTrue(any(contains(string(c.highOrderMessage.Value), "Shot 共通補正（入力した k）を先に引き")));
            testCase.verifyEqual(result.commonCoefficients.value(result.commonCoefficients.k == 5 & ...
                result.commonCoefficients.wafer == result.commonCoefficients.wafer(1)), 1.5);
            app.addHighOrderConditions("current");
            testCase.verifyTrue(contains(string(c.highOrderConditionTable.Data{end, 4}), "共通（入力）→ Shot ごと 1次まで"));
            app.setHighOrderSettings(outerMaker="asml", outerRadiusMm=100);
            names = reshape(string(c.highOrderTermTable.ColumnName), 1, []);
            testCase.verifyEqual(names(7:8), ["内周 共通の値", "外周 共通の値"]);
            merged = c.highOrderTermTable.UserData;
            row = find(isfinite(merged.kOuter) & ~merged.protected, 1);   % 外周の式（ASML）にある高次の項の行
            c.highOrderTermTable.CellEditCallback(c.highOrderTermTable, struct("Indices", [row, 8], "NewData", 0.25));
            testCase.verifyEqual(app.Settings.highOrder.shotCommonOuterValues(merged.kOuter(row)), 0.25, "外周の式の値");
            testCase.verifyEqual(string(c.highOrderCopyCommon.Enable), "on");
            testCase.verifyError(@() app.copyHighOrderCommonValues(), 'alignest:highOrderShotCommon', "式が違う計算は写さない");
            app.setHighOrderSettings(unit="common");
            testCase.verifyEqual(string({c.highOrderShotCommon.Enable, c.highOrderShotEachOrder.Enable, ...
                c.highOrderCopyCommon.Enable}), ["off", "off", "off"]);
            testCase.verifyFalse(any(contains(string(c.highOrderTermTable.ColumnName), "共通の値")));
            settings = app.Settings;
            settings.highOrder.unit = "shot";
            settings.highOrder.shotCommon = "fit";
            settings.highOrder.shotEachOrder = 6;
            app.setSettings(settings);
            testCase.verifyEqual([string(c.highOrderShotCommon.Value), string(c.highOrderShotEachOrder.Value)], ["fit", "6"]);
        end
    end
end

function settings = sequentialSettings(shotCommon, eachOrder)
% Shot ごと、カスタムの式の k1〜k20（3次まで）、Wafer 成分1次、最小二乗・正則化なし
settings = alignest.defaultSettings();
settings.highOrder = struct("maker", "custom", "excludedTerms", 21:38, "unit", "shot", "waferOrder", 1, ...
    "loss", "ols", "regularization", "none", "shotCommon", shotCommon, "shotEachOrder", eachOrder);
end

function [points, truth] = sequentialWafer(testCase, marksPerShot, outerRadiusMm)
% 合成の Wafer：Shot 共通の Shot 内の形（内周は2・3次、外周（Shot 中心の半径 outerRadiusMm 以上）は2次だけの別の形）＋
% Shot ごとの1次の k（k1〜k6）＋ Wafer の1次（dx に 0.01 × Xc）。marksPerShot が空なら Shot ごとに 7 × 11 の格子（どの
% Shot も同じ位置）、数なら Shot ごとにばらばらの位置の点。truth：{内周の形の k の値, 外周の形の k の値}（n 番目が kn）
rng(7);
centers = testCase.Centers;
nShots = size(centers, 1);
if isempty(marksPerShot)
    [lx, ly] = meshgrid(linspace(-12, 12, 7), linspace(-15, 15, 11));
    shotNo = repelem((1:nShots).', numel(lx), 1);
    local = repmat([lx(:), ly(:)], nShots, 1);
else
    shotNo = repelem((1:nShots).', marksPerShot, 1);
    local = (rand(numel(shotNo), 2) - 0.5) .* [24, 30];
end
n = numel(shotNo);
Xc = centers(shotNo, 1);
Yc = centers(shotNo, 2);
terms = alignest.highOrderTerms("custom", 21:38);
truth = {shapeValues(terms, 3, 1.7), shapeValues(terms, 2, 0.9)};
isOuter = hypot(Xc, Yc) >= outerRadiusMm;
values = zeros(n, 2);
axisNames = ["dx", "dy"];
for a = 1:2
    axisTerms = terms(terms.axis == axisNames(a), :);
    design = local(:, 1) .^ (axisTerms.xPower.') .* local(:, 2) .^ (axisTerms.yPower.');
    values(:, a) = design * reshape(truth{1}(axisTerms.k), [], 1);
    outer = design * reshape(truth{2}(axisTerms.k), [], 1);
    values(isOuter, a) = outer(isOuter);
end
linear = randn(nShots, 6) .* [2, 2, 0.05, 0.05, 0.05, 0.05];   % Shot ごとの k1〜k6（k4 は y、k6 は x の係数）
values(:, 1) = values(:, 1) + linear(shotNo, 1) + linear(shotNo, 3) .* local(:, 1) + linear(shotNo, 5) .* local(:, 2) + ...
    0.01 * Xc;
values(:, 2) = values(:, 2) + linear(shotNo, 2) + linear(shotNo, 4) .* local(:, 2) + linear(shotNo, 6) .* local(:, 1);
points = table(repmat("mark", n, 1), "M" + string((1:n).'), shotNo, Xc, Yc, local(:, 1), local(:, 2), Xc + local(:, 1), ...
    Yc + local(:, 2), values(:, 1), values(:, 2), 'VariableNames', ["source", "name", "shotNo", "Xc", "Yc", "localX", ...
    "localY", "x", "y", "valueX", "valueY"]);
end

function values = shapeValues(terms, maxOrder, phase)
% Shot 共通の形の k の値（2〜maxOrder 次の項。n 番目が kn）
values = zeros(1, max(terms.k));
shape = terms(terms.order >= 2 & terms.order <= maxOrder, :);
values(shape.k) = 0.004 * sin(phase * shape.k) ./ 8 .^ (shape.order - 2);
end

function points = noisy(points)
% 点ごとのばらつき（決まった値）を足す
index = (1:height(points)).';
points.valueX = points.valueX + 0.2 * sin(index * 1.3);
points.valueY = points.valueY + 0.2 * cos(index * 2.1);
end

function value = rms(values)
value = sqrt(mean(values(:) .^ 2));
end
