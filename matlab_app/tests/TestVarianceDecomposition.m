classdef TestVarianceDecomposition < matlab.unittest.TestCase
    %TESTVARIANCEDECOMPOSITION ばらつき分解（Lot 間・Wafer 間・Shot 間・その他の分散成分と、全体 Shift・倍率・回転・その他の
    %   成分）：手で決めた値での分け方と合計・3σ、点の数がそろわないときの分散成分、
    %   「1. データ読込」の「ばらつき分解」（Operation ごとの棒・装置の切り替え）、「3. 結果一覧」の「補正残差のばらつき分解」
    %   （補正で Wafer 間のばらつきが変わること）を確かめる。

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
        function nestedPartsAddUpToTheVariance(testCase)
            % 釣り合った入れ子（Lot 2 × Wafer 2 × Shot 2 × 点 2）：分散成分は入れ子の分散分析のモーメント法の式
            % （その他 = MS_E、Shot 間 = (MS_C − MS_E)/n、Wafer 間 = (MS_B − MS_C)/(c n)、Lot 間 = (MS_A − MS_B)/(b c n)）。
            % 全体の分散 = 分散成分の和、段の 3σ = 3√分散、3σ の配分は足すと全体の 3σ
            effects = [4, 3, 1, 0.5];   % Lot・Wafer・Shot・点の差（上の段の中で ±）
            [lotIndex, waferIndex, shotIndex, pointIndex] = ndgrid(1:2, 1:2, 1:2, 1:2);
            signOf = @(index) 2 * index(:) - 3;   % 1 → −1、2 → +1
            values = 10 + effects(1) * signOf(lotIndex) + effects(2) * signOf(waferIndex) + effects(3) * signOf(shotIndex) + ...
                effects(4) * signOf(pointIndex);
            points = table(repmat("A", numel(values), 1), "L" + lotIndex(:), "W" + lotIndex(:) + "-" + waferIndex(:), ...
                shotIndex(:), values, -2 * values, 'VariableNames', ["category", "lot", "wafer", "shot", "valueX", "valueY"]);
            result = alignest.varianceDecomposition(points);
            testCase.verifyEqual(result.components, ["Lot 間", "Wafer 間", "Shot 間", "その他"], "Scan 方向では分けない");
            testCase.verifyEqual(result.kind, "nested");
            N = numel(values);
            meanSquares = N * effects .^ 2 ./ [1, 2, 4, 8];   % 平方和 / 自由度（Lot 1・Wafer 2・Shot 4・その他 8）
            expected = [(meanSquares(1) - meanSquares(2)) / 8, (meanSquares(2) - meanSquares(3)) / 4, ...
                (meanSquares(3) - meanSquares(4)) / 2, meanSquares(4)];
            x = result.table(result.table.axis == "X", :);
            testCase.verifyEqual(x.variance.', expected, 'AbsTol', 1e-9);
            testCase.verifyEqual(x.variance.', [23, 17, 1.75, 0.5], 'AbsTol', 1e-9, "手で計算した値");
            testCase.verifyEqual(x.sigma3.', 3 * sqrt(expected), 'AbsTol', 1e-9, "段の 3σ = 3√（段の分散）");
            testCase.verifyEqual(sum(x.percent), 100, 'AbsTol', 1e-9);
            testCase.verifyEqual(result.totals.variance(1), sum(expected), 'AbsTol', 1e-9, "全体の分散 = 分散成分の和");
            testCase.verifyEqual(result.totals.sigma3, 3 * sqrt(result.totals.variance), 'AbsTol', 1e-12);
            testCase.verifyEqual(sum(x.sigma3Share), result.totals.sigma3(1), 'AbsTol', 1e-9, "3σ の配分は足すと全体の 3σ");
            testCase.verifyGreaterThan(sum(x.sigma3), result.totals.sigma3(1), "段の 3σ は足しても全体の 3σ にならない");
            y = result.table(result.table.axis == "Y", :);
            testCase.verifyEqual(y.variance.', 4 * expected, 'AbsTol', 1e-9, "値を2倍すると分散は4倍");
            % Lot が1つなら Lot 間は分けない（その分は Wafer 間に入る）
            points.lot(:) = "L1";
            merged = alignest.varianceDecomposition(points);
            testCase.verifyEqual(merged.components, ["Wafer 間", "Shot 間", "その他"]);
            testCase.verifyFalse(merged.useLot);
            xm = merged.table(merged.table.axis == "X", :);
            waferMeanSquare = N * (effects(1) ^ 2 + effects(2) ^ 2) / 3;   % Wafer 4 枚：自由度 3
            testCase.verifyEqual(xm.variance.', [(waferMeanSquare - meanSquares(3)) / 4, expected(3:4)], 'AbsTol', 1e-9, ...
                "Lot の分は Wafer 間に入る");
            % 値の無い点は使わず、棒（category）ごとに分ける。点の無い棒は NaN
            points.valueX(1:4) = NaN;
            points.category(9:end) = "B";
            split = alignest.varianceDecomposition(points, categories=["A", "B", "C"]);
            testCase.verifyEqual(split.totals.n(split.totals.axis == "X").', [4, 8, 0]);
            testCase.verifyTrue(all(isnan(split.table.variance(split.table.category == "C"))));
            testCase.verifyError(@() alignest.varianceDecomposition(points, valueColumns="valueX", axisNames=["X", "Y"]), ...
                'alignest:varianceDecomposition');
        end

        function unbalancedComponentsAreUnbiased(testCase)
            % 点の数がそろわない入れ子（Lot 60 × Wafer 4 × Shot 6 × 点 1〜4）で、分かっている分散成分（Lot 4・Wafer 2・Shot 1・
            % その他 0.5）を、平方和を点の数で割っただけの値よりよく求める（上の段に下の段のばらつきが入らない）
            stream = RandStream('mt19937ar', 'Seed', 11);
            truth = [4, 2, 1, 0.5];
            parts = {};
            for lot = 1:60
                lotEffect = sqrt(truth(1)) * randn(stream);
                for waferNo = 1:4
                    waferEffect = sqrt(truth(2)) * randn(stream);
                    for shotNo = 1:6
                        shotEffect = sqrt(truth(3)) * randn(stream);
                        nPoints = randi(stream, 4);
                        value = lotEffect + waferEffect + shotEffect + sqrt(truth(4)) * randn(stream, nPoints, 1);
                        parts{end + 1} = table(repmat("A", nPoints, 1), repmat("L" + lot, nPoints, 1), ...
                            repmat("W" + lot + "-" + waferNo, nPoints, 1), repmat(shotNo, nPoints, 1), value, value, ...
                            'VariableNames', ["category", "lot", "wafer", "shot", "valueX", "valueY"]); %#ok<AGROW>
                    end
                end
            end
            points = vertcat(parts{:});
            result = alignest.varianceDecomposition(points);
            x = result.table(result.table.axis == "X", :);
            testCase.verifyEqual(x.variance.', truth, 'RelTol', 0.35, "分散成分は分かっている値に近い");
            testCase.verifyEqual(x.variance(end), truth(end), 'RelTol', 0.15);
            testCase.verifyEqual(result.totals.variance(1), sum(x.variance), 'AbsTol', 1e-9);
        end

        function componentCoefficientsRecoverKnownTerms(testCase)
            % 分け方「成分」：Wafer ごとの回帰係数。Wafer の成分（全体 Shift・Wafer 倍率・回転）は Shot ごとの点の平均を
            % Shot 中心の座標に当てはめ、Shot 倍率・回転はそれを除いた値を Shot 内の座標に当てはめる（X は倍率 = X の項・
            % 回転 = Y の項、Y は逆）。分かっている係数で作った値から、その係数が戻る
            [shotX, shotY] = meshgrid(-40:20:40);
            [localX, localY] = meshgrid([-5, 5]);
            nShots = numel(shotX);
            nMarks = numel(localX);
            wafers = 3;
            [markIndex, shotIndex, waferIndex] = ndgrid(1:nMarks, 1:nShots, 1:wafers);
            points = table(repmat("A", numel(markIndex), 1), "W" + waferIndex(:), shotIndex(:), shotX(shotIndex(:)), ...
                shotY(shotIndex(:)), localX(markIndex(:)), localY(markIndex(:)), 'VariableNames', ["category", "wafer", ...
                "shot", "shotX", "shotY", "localX", "localY"]);
            w = double(waferIndex(:));
            % X：Shift = Wafer の番号、Wafer 倍率 0.01·番号、Wafer 回転 −0.02、Shot 倍率 0.3、Shot 回転 0.1·番号
            points.valueX = w + 0.01 * w .* points.shotX - 0.02 * points.shotY + 0.3 * points.localX + 0.1 * w .* points.localY;
            % Y：Shift 5、Wafer 倍率 0.04（Shot 中心 Y の項）、Wafer 回転 0.03（Shot 中心 X の項）、Shot 倍率 −0.2（Shot 内 Y）、
            % Shot 回転 0.5（Shot 内 X）
            points.valueY = 5 + 0.04 * points.shotY + 0.03 * points.shotX - 0.2 * points.localY + 0.5 * points.localX;
            result = alignest.componentCoefficients(points);
            testCase.verifyEqual(result.components, ["全体 Shift", "Wafer 倍率", "Wafer 回転", "Wafer 成分の残留 3σ", ...
                "Shot 倍率", "Shot 回転", "Shot 共通成分の残留 3σ"]);
            testCase.verifyEqual(result.kind, "components");
            testCase.verifyEqual(result.wafers, ["W1", "W2", "W3"]);
            coefficient = @(table_, axisName, k) table_.coefficient(table_.axis == axisName & table_.waferIndex == k).';
            terms = [1, 2, 3, 5, 6];   % 回帰係数（4・7 番目は残留）
            for k = 1:wafers
                x = coefficient(result.table, "X", k);
                y = coefficient(result.table, "Y", k);
                testCase.verifyEqual(x(terms), [k, 0.01 * k, -0.02, 0.3, 0.1 * k], 'AbsTol', 1e-10);
                testCase.verifyEqual(y(terms), [5, 0.04, 0.03, -0.2, 0.5], 'AbsTol', 1e-10);
                testCase.verifyEqual([x([4, 7]), y([4, 7])], zeros(1, 4), 'AbsTol', 1e-9, "式で表せる値なので残留は 0");
            end
            % 残留：式に無い形を足すと、その形の 3σ が残る（Wafer レベル：Shot 中心の X·Y、Shot レベル：Shot 内の x·y。
            % どちらも、この配置では式の項と直交するので、回帰残差はその形そのもの）
            withRest = points;
            withRest.valueY = withRest.valueY + 0.001 * withRest.shotX .* withRest.shotY + 0.01 * withRest.localX .* withRest.localY;
            rest = alignest.componentCoefficients(withRest);
            y = coefficient(rest.table, "Y", 1);
            mine = withRest.wafer == "W1";
            testCase.verifyEqual(y(4), 3 * std(0.001 * withRest.shotX(mine) .* withRest.shotY(mine)), 'RelTol', 1e-9, ...
                "Wafer 成分の残留 = Wafer レベルの回帰残差の 3σ");
            testCase.verifyEqual(y(7), 3 * std(0.01 * withRest.localX(mine) .* withRest.localY(mine)), 'RelTol', 1e-9, ...
                "Shot 共通成分の残留 = Shot レベルの回帰残差の 3σ");
            testCase.verifyEqual(y(terms), [5, 0.04, 0.03, -0.2, 0.5], 'AbsTol', 1e-10, "足した形は係数を変えない");
            testCase.verifyEqual(unique(result.table.n), nMarks * nShots);
            % 値の無い点は使わない（Shot の平均と Shot 内の座標の平均は残りの点で求めるので、Shot の係数は変わらない）
            points.valueX(5) = NaN;
            missing = alignest.componentCoefficients(points);
            rows = missing.table(missing.table.axis == "X" & missing.table.waferIndex == 1, :);
            testCase.verifyEqual(rows.n(1), nMarks * nShots - 1);
            testCase.verifyEqual(rows.coefficient(5:6).', [0.3, 0.1], 'AbsTol', 1e-10);
            % Shot が足りず決まらない係数は NaN（Shot が2つでは Wafer の倍率・回転は決まらない）
            few = alignest.componentCoefficients(points(points.wafer == "W1" & points.shot <= 2, :));
            testCase.verifyTrue(all(isnan(few.table.coefficient(few.table.component == "Wafer 倍率"))));
            testCase.verifyTrue(all(isfinite(few.table.coefficient(few.table.component == "Shot 倍率"))));
            % Wafer の並びは categories の順
            points.category(points.wafer == "W1") = "B";
            ordered = alignest.componentCoefficients(points, categories=["B", "A"]);
            testCase.verifyEqual(ordered.wafers, ["W1", "W2", "W3"]);
            testCase.verifyEqual(ordered.waferCategories, ["B", "A", "A"]);
            reversed = alignest.componentCoefficients(points, categories=["A", "B"]);
            testCase.verifyEqual(reversed.wafers, ["W2", "W3", "W1"]);
        end

        function importedDataIsSplitByOperationAndEqp(testCase)
            % 「1. データ読込」の「ばらつき分解」：Operation ごとの棒、Lot が2つ以上なら Lot 間。装置を選ぶとその装置の計測だけ。
            % 段の分散を足すと有効な計測値の分散になる。縦軸（3σ・分散）で表の数値も変わる
            raw = readtable(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'), 'TextType', 'string');
            later = ismember(raw.Wafer, ["SIM04", "SIM05"]);
            raw.Operation(later) = "OP-M2-ALIGN";
            raw.LotID(raw.Wafer == "SIM02") = "LOTSIM02";
            file = [tempname, '.csv'];
            writetable(raw, file);
            cleanupFile = onCleanup(@() delete(file));
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(file);
            app.applyMapping();
            c = app.Controls;
            result = app.DataVariance;
            testCase.verifyNotEmpty(result, "読み込むと一度分ける");
            testCase.verifyEqual(result.categories, ["OP-M1-ALIGN", "OP-M2-ALIGN"], "Operation ごとの棒");
            testCase.verifyEqual(result.components, ["Lot 間", "Wafer 間", "Shot 間", "その他"]);
            testCase.verifyEqual(string(c.varianceEqp.Items), ["すべての装置", "装置 EXP01", "装置 EXP02"]);
            testCase.verifyEqual(string(c.varianceEqp.Enable), "on");
            units = app.Data.units;
            first = units(string({units.operation}) == "OP-M1-ALIGN");
            marks = [first.marks];
            values = vertcat(marks.measX);
            valid = logical(vertcat(marks.validX));
            parts = result.table(result.table.category == "OP-M1-ALIGN" & result.table.axis == "X", :);
            totalX = result.totals.variance(result.totals.category == "OP-M1-ALIGN" & result.totals.axis == "X");
            testCase.verifyEqual(sum(parts.variance), totalX, 'RelTol', 1e-12, "全体の分散 = 分散成分の和");
            testCase.verifyEqual(totalX, var(values(valid), 1), 'RelTol', 0.3, "全体の分散は値の分散に近い");
            testCase.verifyGreaterThan(parts.variance(parts.component == "Lot 間"), 0);
            testCase.verifyNotEmpty(c.varianceAxes(1).Children);
            testCase.verifyEqual(height(c.varianceTable.Data), 2 * 2 * 5, "棒 × 軸 × （4つの段と全体）");
            testCase.verifyEqual(string(c.varianceQuantity.Value), "sigma3", "はじめは 3σ");
            names = string(c.varianceTable.Data.Properties.VariableNames);
            testCase.verifyTrue(all(ismember(["3σ の配分 [nm]", "単独の 3σ [nm]"], names)) && ~any(contains(names, "分散 [")));
            first = c.varianceTable.Data(1, :);
            row = result.table(result.table.category == "OP-M1-ALIGN" & result.table.axis == "X" & ...
                result.table.component == string(first.("ばらつき")), :);
            testCase.verifyEqual(first.("単独の 3σ [nm]"), round(row.sigma3, 4), 'AbsTol', 1e-9);
            testCase.verifyEqual(first.("3σ の配分 [nm]"), round(row.sigma3Share, 4), 'AbsTol', 1e-9);
            bars = c.varianceAxes(1).Children(arrayfun(@(item) isa(item, 'matlab.graphics.chart.primitive.Bar'), ...
                c.varianceAxes(1).Children));
            testCase.verifyEqual(numel(bars), 4, "3σ：4つの段の棒");
            testCase.verifyEqual(string(bars(1).BarLayout), "stacked", "3σ の配分を積み上げる");
            barTop = sum(cell2mat(arrayfun(@(item) item.YData(1), bars, 'UniformOutput', false)));
            testCase.verifyEqual(barTop, result.totals.sigma3(1), 'RelTol', 1e-9, "積み上げの上端は全体の 3σ（分散は足せる）");
            total = findobj(c.varianceAxes(1), 'Type', 'line', 'DisplayName', '全体の 3σ');
            testCase.verifyNotEmpty(total, "全体の 3σ を ◆ で重ねる");
            testCase.verifyEqual(string(total(1).Marker), "diamond");
            totals = result.totals(result.totals.axis == "X", :);
            testCase.verifyEqual(total(1).YData(:), totals.sigma3, 'AbsTol', 1e-9);
            app.setVarianceQuantity("data", "variance");
            names = string(c.varianceTable.Data.Properties.VariableNames);
            testCase.verifyTrue(any(names == "分散 [nm²]") && ~any(names == "3σ [nm]"));
            testCase.verifyEqual(c.varianceAxes(1).Children(end).BarLayout, 'stacked', "分散は積み上げ");
            app.setVarianceQuantity("data", "sigma3");
            one = app.decomposeDataVariance("EXP02");
            testCase.verifyEqual(one.nUnits, nnz(string({units.eqpId}) == "EXP02"));
            testCase.verifyEqual(one.categories, "OP-M2-ALIGN", "EXP02 の計測は2つ目の Operation だけ");
            testCase.verifyFalse(one.useLot, "その装置の計測の Lot は1つ");
            testCase.verifyTrue(contains(string(c.varianceInfo.Text), "EXP02"));
            % 凡例は右の列の凡例だけの図にまとめ、X・Y の図には出さない（4つの図の大きさをそろえる）
            testCase.verifyNotEmpty(c.varianceLegendAxes.Legend, "凡例だけの図");
            testCase.verifyTrue(all(arrayfun(@(ax) isempty(ax.Legend) || strcmp(ax.Legend.Visible, 'off'), c.varianceAxes)));
            % 装置以外の列でも絞り込める（ロット：計測ごと）
            testCase.verifyEqual(string(c.varianceColumn.ItemsData(1:3)), ["EqpId", "LotID", "Operation"]);
            lotResult = app.decomposeDataVariance("", "nested", "LotID");
            lots = string(c.varianceEqp.ItemsData(2:end));
            testCase.verifyNotEmpty(lots);
            oneLot = app.decomposeDataVariance(lots(1), "nested", "LotID");
            testCase.verifyEqual(oneLot.nUnits, nnz(string({units.lotId}) == lots(1)));
            testCase.verifyEqual(oneLot.filterColumn, "LotID");
            testCase.verifyLessThanOrEqual(oneLot.nUnits, lotResult.nUnits);
            app.decomposeDataVariance("", "nested", "EqpId");
            testCase.verifyError(@() app.decomposeDataVariance("NONE"), 'alignest:varianceDecomposition');
            % 分け方「成分」：Wafer ごとの回帰係数の図（成分ごと）と表（Wafer × 軸 の行）。3σ・分散は出さず「縦軸」も使わない
            components = app.decomposeDataVariance("", "components");
            testCase.verifyEqual(components.components, ["全体 Shift", "Wafer 倍率", "Wafer 回転", "Wafer 成分の残留 3σ", ...
                "Shot 倍率", "Shot 回転", "Shot 共通成分の残留 3σ"]);
            testCase.verifyEqual(sort(components.wafers), sort(string({units.label})));
            testCase.verifyEqual(height(c.varianceTable.Data), 2 * numel(units), "Wafer × 軸（X・Y）の行");
            names = string(c.varianceTable.Data.Properties.VariableNames);
            testCase.verifyEqual(names, ["No.", "Operation", "Wafer", "軸", "全体 Shift [nm]", "Wafer 倍率 [nm/mm]", ...
                "Wafer 回転 [nm/mm]", "Wafer 成分の残留 3σ [nm]", "Shot 倍率 [nm/mm]", "Shot 回転 [nm/mm]", ...
                "Shot 共通成分の残留 3σ [nm]", "点の数"]);
            testCase.verifyFalse(any(contains(names, ["3σ の配分", "単独の 3σ", "分散"])), "段の 3σ・分散は出さない（残留は回帰残差の 3σ）");
            testCase.verifyEqual(string(c.varianceQuantity.Enable), "off");
            expected = components.table.coefficient(components.table.axis == "X" & components.table.component == "Wafer 倍率");
            xLine = findobj(c.coefficientAxes(2), 'Type', 'line', 'DisplayName', 'X');
            testCase.verifyEqual(xLine.YData(:), expected, 'AbsTol', 1e-12, "図は Wafer ごとの係数");
            testCase.verifyEqual(c.varianceTable.Data{1, "Wafer 倍率 [nm/mm]"}, round(expected(1), 4, 'significant'), ...
                'AbsTol', 1e-12, "表は係数（有効数字 4 桁）");
            testCase.verifyTrue(contains(string(c.varianceInfo.Text), "回帰係数"));
            app.decomposeDataVariance("", "nested");
            testCase.verifyEqual(string(c.varianceQuantity.Enable), "on", "Lot・Wafer・Shot 間では「縦軸」を使う");
            % 図・表の保存とコピー：分けた後に押せる。表は画面と同じ列・行で、コピーは1行目が列名のタブ区切り
            testCase.verifyEqual(unique(string({c.varianceOutputs.Enable})), "on");
            text = app.copyVarianceTable("data");
            lines = splitlines(string(text));
            data = c.varianceTable.Data;
            testCase.verifyEqual(numel(lines), height(data) + 1);
            testCase.verifyEqual(split(lines(1), sprintf('\t')).', string(data.Properties.VariableNames));
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            app.exportVarianceTable("data", fullfile(folder, "variance.xlsx"));
            back = readtable(fullfile(folder, "variance.xlsx"), 'Sheet', '値', 'VariableNamingRule', 'preserve', ...
                'TextType', 'string');
            testCase.verifyEqual(string(back.Properties.VariableNames), string(data.Properties.VariableNames));
            testCase.verifyEqual(back{:, end}, data{:, end}, "点の数");
            notes = readtable(fullfile(folder, "variance.xlsx"), 'Sheet', '説明', 'TextType', 'string', 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(notes{2, 2}, string(c.varianceInfo.Text), "説明シートに図の下の説明");
            app.exportVarianceTable("data", fullfile(folder, "variance.csv"));
            testCase.verifyEqual(height(readtable(fullfile(folder, "variance.csv"), 'VariableNamingRule', 'preserve')), ...
                height(data));
            testCase.verifyError(@() app.saveFigureImage("variance", fullfile(folder, "variance.png")), ...
                'alignest:hiddenFigure', "図の画像は画面を出しているときだけ");
            % 1変数の推定：値の名前の1列だけ
            spec = struct("scalar", true, "name", "Thickness_nm", "unit", "nm");
            scalar = alignest.dataVarianceDecomposition(units, "", spec);
            testCase.verifyEqual(scalar.axes, "Thickness_nm");
            scalarComponents = alignest.dataVarianceDecomposition(units, "", spec, "components");
            testCase.verifyEqual(unique(scalarComponents.table.axis), "Thickness_nm");
        end

        function correctionChangesWaferToWaferVariation(testCase)
            % 「3. 結果一覧」の「補正残差のばらつき分解」：補正前の値と、実測値・推定値で補正した残差（足す成分のある段階）を
            % 並べる。Wafer 成分（定数を含む）で Wafer ごとに補正すると、実測値で補正した残差の Wafer 間はほぼ 0 になる
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            c = app.Controls;
            settings = app.Settings;
            settings.methods = alignest.recommendedMethods("none");
            settings.methods.polynomial.enabled = true;
            settings.sampling.nShots = 20;
            [settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(20, 20, 10);
            app.setSettings(settings);
            app.runEvaluationNow(false);
            testCase.verifyEqual(string(c.correctionVarianceButton.Enable), "on");
            testCase.verifyError(@() app.decomposeCorrectionVariance(), 'alignest:varianceDecomposition', ...
                "比べる前は分けられない");
            testCase.verifyEqual(unique(string({c.correctionVarianceOutputs.Enable})), "off", "分ける前は保存・コピーできない");
            testCase.verifyError(@() app.copyVarianceTable("correction"), 'alignest:noVarianceTable');
            comparison = app.compareEstimatedCorrection(1, app.Results.groups(end), 0);
            testCase.verifyEqual(comparison.stageUsed, [true, false, true], "初期の補正モデル：Wafer 成分と Shot ごとの成分");
            testCase.verifyEqual(height(comparison.points), sum(arrayfun(@(unit) numel(unit.marks.x), app.Data.units)));
            result = app.CorrectionVariance;
            testCase.verifyNotEmpty(result, "比べると、ばらつき分解も描く");
            testCase.verifyEqual(result.categories, ["補正前", "実測・Wafer 成分", "推定・Wafer 成分", "実測・全成分", ...
                "推定・全成分"]);
            testCase.verifyEqual(result.nWafers, numel(app.Data.units));
            pick = @(category, component) result.table.variance(result.table.category == category & ...
                result.table.axis == "X" & result.table.component == component);
            total = @(category) result.totals.variance(result.totals.category == category & result.totals.axis == "X");
            testCase.verifyGreaterThan(pick("補正前", "Wafer 間"), 0.01 * total("補正前"));
            testCase.verifyLessThan(pick("実測・Wafer 成分", "Wafer 間"), 1e-9 * total("補正前"), ...
                "Wafer ごとの補正で Wafer 間はほぼ 0");
            testCase.verifyLessThan(pick("実測・全成分", "Shot 間"), 1e-9 * total("補正前"), "Shot ごとの補正で Shot 間はほぼ 0");
            testCase.verifyEqual(result.totals.n(result.totals.axis == "X"), ...
                repmat(comparison.table.n(comparison.table.wafer == "すべての Wafer" & ...
                comparison.table.scope == "すべての点" & comparison.table.axis == "X"), 5, 1), "「実測値と推定値の補正」と同じ点");
            testCase.verifyNotEmpty(c.correctionVarianceAxes(3).Children);
            testCase.verifyTrue(contains(string(c.correctionVarianceInfo.Text), "Wafer 間"));
            testCase.verifyEqual(unique(string({c.correctionVarianceOutputs.Enable})), "on");
            copied = splitlines(string(app.copyVarianceTable("correction")));
            testCase.verifyEqual(numel(copied), height(c.correctionVarianceTable.Data) + 1);
            target = app.decomposeCorrectionVariance(result.methodPlan, "推定対象の点");
            testCase.verifyLessThan(target.totals.n(1), result.totals.n(1));
            % 1枚だけなら Wafer 間は 0 と知らせる
            app.compareEstimatedCorrection(1, app.Results.groups(end), 1);
            testCase.verifyEqual(app.CorrectionVariance.nWafers, 1);
            testCase.verifyTrue(contains(string(c.correctionVarianceInfo.Text), "Wafer が1枚"));
        end
    end
end
