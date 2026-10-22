classdef TestDataPreparation < matlab.unittest.TestCase
    %TESTDATAPREPARATION 読み込みと前処理（Overlay 計測ルールの決まり）を確かめる。

    methods (TestClassSetup)
        function addAppPath(~)
            addpath(fileparts(fileparts(mfilename('fullpath'))));
        end
    end

    methods (Test)
        function operationAndEquipmentSeparateMeasurements(testCase)
            raw = smallTable();
            raw.Operation = repmat("OP1", height(raw), 1);
            raw.EqpId = repmat("EXP01", height(raw), 1);
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            testCase.verifyEqual([mapping.Operation, mapping.EqpId], ["Operation", "EqpId"]);
            otherOperation = raw;
            otherOperation.Operation(:) = "OP2";
            otherEquipment = raw;
            otherEquipment.EqpId(:) = "EXP02";
            data = alignest.prepareData([raw; otherOperation; otherEquipment], mapping);
            testCase.verifyEqual(numel(data.units), 3);
            testCase.verifyEqual(data.summary.nDuplicateRows, 0, "工程・装置が違う行は重複にしない");
            testCase.verifyEqual(string({data.units.operation}), ["OP1", "OP2", "OP1"]);
            testCase.verifyEqual(string({data.units.eqpId}), ["EXP01", "EXP01", "EXP02"]);
            % 同じ Wafer の表示名には、違う項目だけを付ける
            testCase.verifyEqual(string({data.units.label}), ["W01 (OP1 / EXP01)", "W01 (OP2 / EXP01)", "W01 (OP1 / EXP02)"]);
            testCase.verifyEqual(data.summary.operations, ["OP1", "OP2"]);
            testCase.verifyEqual(data.summary.eqpIds, ["EXP01", "EXP02"]);
            % 列が無ければ空で、従来どおり Wafer・日時で分ける
            data = alignest.prepareData(smallTable(), alignest.guessColumnMapping(smallTable().Properties.VariableNames));
            testCase.verifyEqual([data.units.operation, data.units.eqpId], ["", ""]);
            testCase.verifyEmpty(data.summary.operations);
        end

        function lotIdAndOtherColumnsAreKept(testCase)
            raw = smallTable();
            raw.LotID = repmat("LOT1", height(raw), 1);
            raw.Chuck = repmat(["A"; "B"; "A"; "B"], height(raw) / 4, 1);
            raw.Temp = (1:height(raw)).' / 10;
            raw.Temp(5) = NaN;
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            testCase.verifyEqual(mapping.LotID, "LotID");
            other = raw;
            other.LotID(:) = "LOT2";
            data = alignest.prepareData([raw; other], mapping);
            % 同じ Wafer ID でもロットが違えば別の計測。表示名にロットを付ける
            testCase.verifyEqual(numel(data.units), 2);
            testCase.verifyEqual(string({data.units.label}), ["W01 (LOT1)", "W01 (LOT2)"]);
            testCase.verifyEqual(data.summary.lotIds, ["LOT1", "LOT2"]);
            testCase.verifyEqual(data.summary.nDuplicateRows, 0);
            % 標準の項目に対応づけなかった列は、Mark ごとの文字列として残る（数値の欠けは空）
            testCase.verifyEqual(data.attributeNames, ["Chuck", "Temp"]);
            unit = data.units(1);
            testCase.verifyEqual(unit.attributeNames, ["Chuck", "Temp"]);
            first = find(unit.marks.x == raw.Xmm(1) + raw.markXmm(1) & unit.marks.y == raw.Ymm(1) + raw.markYmm(1));
            testCase.verifyEqual(unit.marks.attributes(first, :), ["A", "0.1"]);
            fifth = find(unit.marks.x == raw.Xmm(5) + raw.markXmm(5) & unit.marks.y == raw.Ymm(5) + raw.markYmm(5));
            testCase.verifyEqual(unit.marks.attributes(fifth, 2), "");
            % 標準の項目に対応づけた列は、その他の列に入らない
            mapping.LotID = "";
            data = alignest.prepareData(raw, mapping);
            testCase.verifyEqual(data.attributeNames, ["LotID", "Chuck", "Temp"]);
        end

        function directionRulesFillOnlyBlankRows(testCase)
            raw = removevars(smallTable(), "Direction");
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            plain = alignest.prepareData(raw, mapping);
            testCase.verifyFalse(plain.units(1).hasDirection);
            testCase.verifyEqual(plain.summary.directionSource, "なし");
            shots = plain.units(1).shots;
            expected = struct("shotNoParity", 1 + mod(shots.shotNo - 1, 2), "rowParity", shots.rowParity, ...
                "columnParity", 1 + mod(shots.column - 1, 2), "checkerboard", 1 + mod(shots.row + shots.column, 2));
            for rule = string(fieldnames(expected)).'
                data = alignest.prepareData(raw, mapping, directionRule=rule);
                unit = data.units(1);
                testCase.verifyTrue(unit.hasDirection, rule);
                testCase.verifyEqual(unit.shots.direction, expected.(rule), rule);
                testCase.verifyEqual(unit.marks.direction, unit.shots.direction(unit.marks.shotIndex), rule);
                testCase.verifyEqual(data.summary.nDirectionAssigned, height(raw), rule);
                inverted = alignest.prepareData(raw, mapping, directionRule=rule, invertDirection=true);
                testCase.verifyEqual(inverted.units(1).shots.direction, 3 - expected.(rule), rule);
            end
            % 左上の Shot が市松模様の 1、列は左から数える
            data = alignest.prepareData(raw, mapping, directionRule="checkerboard");
            corner = data.units(1).shots.Xmm == -26 & data.units(1).shots.Ymm == 33;
            testCase.verifyEqual(data.units(1).shots.direction(corner), 1);
            % Direction の列があれば、空の行だけに付ける
            raw = smallTable();
            raw.Direction(raw.shotNo == 5) = NaN;
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames), ...
                directionRule="rowParity");
            unit = data.units(1);
            testCase.verifyEqual(data.summary.nDirectionAssigned, nnz(raw.shotNo == 5));
            testCase.verifyEqual(data.summary.directionSource, "ファイルの列と規則による付与");
            testCase.verifyEqual(unit.shots.direction(unit.shots.shotNo == 5), unit.shots.rowParity(unit.shots.shotNo == 5));
            filled = unit.shots.shotNo ~= 5;
            fromFile = arrayfun(@(no) raw.Direction(find(raw.shotNo == no, 1)), unit.shots.shotNo(filled));
            testCase.verifyEqual(unit.shots.direction(filled), fromFile);
            % shotNo の奇偶は shotNo の列が必要
            raw = removevars(smallTable(), ["Direction", "shotNo"]);
            testCase.verifyError(@() alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames), ...
                directionRule="shotNoParity"), 'alignest:directionRule');
            testCase.verifyError(@() alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames), ...
                directionRule="spiral"), 'alignest:directionRule');
        end

        function serpentineStartsAtSmallestShotAndAlternates(testCase)
            % 3 行 × 4 列、shotNo は上の行から左→右（1〜4・5〜8・9〜12）。一筆書き：1 行目は左→右、2 行目は右→左、
            % 3 行目は左→右にたどり、道順に 1・2 を交互に付ける（shotNo の奇偶とは 2 行目が違う）
            raw = rasterTable(3, 4, 1:12);
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            data = alignest.prepareData(raw, mapping, directionRule="serpentine");
            shots = data.units(1).shots;
            [~, order] = sort(shots.shotNo);
            testCase.verifyEqual(shots.direction(order).', [1, 2, 1, 2, 2, 1, 2, 1, 1, 2, 1, 2]);
            testCase.verifyEqual(data.summary.nDirectionAssigned, height(raw));
            inverted = alignest.prepareData(raw, mapping, directionRule="serpentine", invertDirection=true);
            testCase.verifyEqual(inverted.units(1).shots.direction, 3 - shots.direction);
            % shotNo 1 が右下の Shot なら、下の行を右→左、その上の行を左→右…とたどる
            raw = rasterTable(3, 4, 13 - (1:12));
            shots = alignest.prepareData(raw, mapping, directionRule="serpentine").units(1).shots;
            at = @(row, column) shots.direction(shots.row == row & shots.column == column);
            testCase.verifyEqual([at(3, 4), at(3, 3), at(3, 2), at(3, 1)], [1, 2, 1, 2], "始めの行は右から左");
            testCase.verifyEqual([at(2, 1), at(2, 2), at(2, 4)], [1, 2, 2], "次の行は折り返して左から右");
            testCase.verifyEqual(at(1, 4), 1, "上の行は右から左（道順の 9 番目）");
            % shotNo の列が無ければ、いちばん上の行の左端から始める
            raw = removevars(rasterTable(3, 4, 1:12), "shotNo");
            shots = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames), ...
                directionRule="serpentine").units(1).shots;
            testCase.verifyEqual(shots.direction(shots.row == 1 & shots.column == 1), 1);
            testCase.verifyEqual(shots.direction(shots.row == 2 & shots.column == 4), 1);
            % 初期設定は一筆書き
            testCase.verifyEqual(alignest.defaultSettings().data.directionRule, "serpentine");
        end

        function scanDirectionOverridesApplyToEveryWafer(testCase)
            raw = rasterTable(3, 4, 1:12);
            second = raw;
            second.Wafer(:) = "W02";
            raw = [raw; second];
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            data = alignest.prepareData(raw, mapping, directionRule="serpentine", directionOverrideShots=[5, 6], ...
                directionOverrideValues=[1, 1]);
            for unit = data.units.'
                testCase.verifyEqual(unit.shots.direction(ismember(unit.shots.shotNo, [5, 6])), [1; 1]);
                testCase.verifyEqual(unit.marks.direction, unit.shots.direction(unit.marks.shotIndex));
            end
            testCase.verifyEqual(data.summary.nDirectionOverrides, 2);
            testCase.verifyTrue(any(contains(data.summary.messages, "画面で Scan 方向を変えた Shot")));
            testCase.verifyEqual(data.directionOverrideShots, [5, 6]);
            % 規則が「付けない」でも、変えた Shot にだけ Scan 方向が付く
            data = alignest.prepareData(raw, mapping, directionOverrideShots=7, directionOverrideValues=2, ...
                directionRule="none");
            testCase.verifyEqual(data.units(1).shots.direction(data.units(1).shots.shotNo == 7), 2);
            testCase.verifyFalse(data.units(1).hasDirection, "ほかの Shot に方向が無いので質的変数には使わない");
            testCase.verifyError(@() alignest.prepareData(raw, mapping, directionOverrideShots=1, ...
                directionOverrideValues=3), 'alignest:directionOverride');
        end

        function labelsShowEquipmentAndOperationWhenTheyVary(testCase)
            raw = rasterTable(2, 2, 1:4);
            raw.EqpId = repmat("E1", height(raw), 1);
            raw.Operation = repmat("OP1", height(raw), 1);
            other = raw;
            other.EqpId(:) = "E2";
            third = raw;
            third.Wafer(:) = "W02";
            raw = [raw; other; third];
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            testCase.verifyEqual(sort(string({data.units.label})), ["W01 (E1)", "W01 (E2)", "W02 (E1)"], ...
                "同じ Wafer ID でも装置が違えば別の計測。装置が2種類以上なので、どの Wafer にも装置を付ける");
            % 工程も違えば両方を付ける
            raw.Operation(raw.EqpId == "E2") = "OP2";
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            testCase.verifyTrue(any(string({data.units.label}) == "W01 (OP2 / E2)"));
            % 装置・工程が1種類なら Wafer ID だけ
            data = alignest.prepareData(rasterTable(2, 2, 1:4), ...
                alignest.guessColumnMapping(rasterTable(2, 2, 1:4).Properties.VariableNames));
            testCase.verifyEqual(data.units(1).label, "W01");
        end

        function shotSizeComesFromCenterSpacing(testCase)
            raw = smallTable();
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            testCase.verifyEqual(data.units(1).shotSizeMm, [26, 33]);
            % 端の Shot が抜けて間隔が2倍の所があっても、最も小さい間隔を使う
            [sizeMm, estimated] = alignest.shotSize([0; 26; 78; 0], [0; 0; 0; 33], [-10; 10], [-12; 12]);
            testCase.verifyEqual(sizeMm, [26, 33]);
            testCase.verifyEqual(estimated, [true, true]);
            % 隣の Shot が無い向きは Mark の広がりの 1.2 倍
            [sizeMm, estimated] = alignest.shotSize(0, 0, [-10; 10], [-12; 12]);
            testCase.verifyEqual(sizeMm, [24, 28.8], 'AbsTol', 1e-12);
            testCase.verifyEqual(estimated, [false, false]);
        end

        function coordinateUnitCheckSuggestsUnits(testCase)
            raw = smallTable();
            raw.Xmm = raw.Xmm * 1000;
            raw.markYmm = raw.markYmm * 1e6;
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            checks = alignest.checkCoordinateUnits(raw, mapping, struct());
            testCase.verifyEqual(checks.name.', ["Xmm", "Ymm", "markXmm", "markYmm", "Radius"]);
            testCase.verifyEqual(checks.ok.', [false, true, true, false, true]);
            testCase.verifyEqual(checks.suggested.', ["um", "mm", "mm", "nm", "mm"]);
            testCase.verifyTrue(contains(checks.message(1), "µm"));
            mapping.Radius = "";
            checks = alignest.checkCoordinateUnits(raw, mapping, struct("Xmm", "um", "markYmm", "nm"));
            testCase.verifyTrue(all(checks.ok));
            testCase.verifyEqual(checks.message(5), "列なし");
            testCase.verifyEqual(checks.maxMm(1), 26, 'AbsTol', 1e-9);
        end

        function recordFiltersApplyIndependentlyAndCountOverlap(testCase)
            raw = smallTable();
            raw.measX(:) = 10;
            raw.measY(:) = 20;
            raw.StsX(:) = 0;
            raw.measX([1, 2, 6]) = 0;
            raw.measY([1, 3, 6]) = 0;
            raw.StsX([4, 6]) = -1;
            raw.StsY([5, 6]) = -1;
            raw.StsX(7) = 2; % −1以外は行を残し、従来どおりその軸だけ無効
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            for excludeZero = [false, true]
                for excludeUnmeasured = [false, true]
                    removed = (excludeZero & raw.measX == 0 & raw.measY == 0) | ...
                        (excludeUnmeasured & (raw.StsX == -1 | raw.StsY == -1));
                    data = alignest.prepareData(raw, mapping, excludeZeroMeasurements=excludeZero, ...
                        excludeUnmeasuredRecords=excludeUnmeasured);
                    expected = alignest.prepareData(raw(~removed, :), mapping);
                    testCase.verifyEqual(data.units, expected.units);
                    testCase.verifyEqual(data.summary.nRowsRead, height(raw));
                    testCase.verifyEqual(data.summary.nRecordsExcluded, nnz(removed));
                    testCase.verifyEqual(data.summary.nZeroMeasurementsExcluded, 2*double(excludeZero));
                    testCase.verifyEqual(data.summary.nUnmeasuredRecordsExcluded, 3*double(excludeUnmeasured));
                end
            end
        end

        function recordFiltersPrecedeDuplicateMeans(testCase)
            raw = smallTable();
            extra = raw([1, 1], :);
            extra.measX = [0; 1000];
            extra.measY = [0; 1000];
            extra.StsY = [0; -1];
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            expected = alignest.prepareData(raw, mapping, excludeUnmeasuredRecords=true);
            actual = alignest.prepareData([raw; extra], mapping, ...
                excludeZeroMeasurements=true, excludeUnmeasuredRecords=true);
            testCase.verifyEqual(actual.units, expected.units);
            testCase.verifyEqual(actual.summary.nDuplicateRows, 0);
            testCase.verifyEqual(actual.summary.nRecordsExcluded, 3);
            % 元の値は非ゼロでも、平均した結果がX・Yとも0になる点は残す
            raw.StsX(:) = 0;
            opposite = raw(1, :);
            opposite.measX = -opposite.measX;
            opposite.measY = -opposite.measY;
            actual = alignest.prepareData([raw; opposite], mapping, excludeZeroMeasurements=true);
            testCase.verifyEqual(actual.summary.nRecordsExcluded, 0);
            testCase.verifyEqual(actual.summary.nDuplicateRows, 1);
            testCase.verifyTrue(any(actual.units(1).marks.measX == 0 & actual.units(1).marks.measY == 0));
        end

        function recordFiltersHandleMissingStatusAndTextColumns(testCase)
            raw = removevars(smallTable(), 'StsY');
            raw.StsX = string(raw.StsX);
            raw.measX = string(raw.measX);
            raw.measY = string(raw.measY);
            raw.measX(1) = "0";
            raw.measY(1) = "0";
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            data = alignest.prepareData(raw, mapping, excludeZeroMeasurements=true, excludeUnmeasuredRecords=true);
            testCase.verifyEqual(data.summary.nRecordsExcluded, 2);
            testCase.verifyTrue(any(contains(data.summary.messages, "対応づけられていない Sts 列")));
            raw = removevars(raw, 'StsX');
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames), ...
                excludeUnmeasuredRecords=true);
            testCase.verifyEqual(data.summary.nRecordsExcluded, 0);
            testCase.verifyEqual(numel(data.units(1).marks.x), height(raw));
        end

        function recordFiltersPreserveRowParityAndReportEmptyData(testCase)
            raw = smallTable();
            top = raw.Ymm == max(raw.Ymm);
            raw.measX(top) = 0;
            raw.measY(top) = 0;
            raw.Direction(top) = 3;
            raw.markNo(top) = NaN; % 除外した行の補助項目は解析を妨げない
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            data = alignest.prepareData(raw, mapping, excludeZeroMeasurements=true);
            testCase.verifyEqual(data.summary.nRecordsExcluded, nnz(top));
            testCase.verifyEqual(data.units(1).shots.rowParity(data.units(1).shots.Ymm == 0), repmat(2, 3, 1));
            raw.measX(:) = 0;
            raw.measY(:) = 0;
            testCase.verifyError(@() alignest.prepareData(raw, mapping, excludeZeroMeasurements=true), 'alignest:noData');
            raw.StsY(:) = -1;
            testCase.verifyError(@() alignest.prepareData(raw, mapping, excludeUnmeasuredRecords=true), 'alignest:noData');
        end

        function coordinateConversionPrecedesAllFiltering(testCase)
            raw = smallTable();
            raw = [raw; raw(1, :)];
            raw.Xmm(end) = 150;
            raw.markXmm(end) = 0;
            raw.Ymm(end) = 0;
            raw.markYmm(end) = 0;
            raw.Radius(end) = 150;
            raw = [raw; raw(1, :)];
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            expected = alignest.prepareData(raw, mapping);
            for unit = ["m", "um", "nm"]
                units = struct("Xmm", unit, "Ymm", unit, "markXmm", unit, "markYmm", unit, "Radius", unit);
                [~, scale] = alignest.coordinateUnits(units);
                converted = raw;
                for name = string(fieldnames(scale)).'
                    converted.(name) = raw.(name) / scale.(name);
                end
                actual = alignest.prepareData(converted, mapping, coordinateUnits=units);
                testCase.verifyEqual(actual.units, expected.units, 'AbsTol', 1e-10);
                testCase.verifyEqual(actual.summary.nOutsideRadius, 1);
                testCase.verifyEqual(actual.summary.nDuplicateRows, 1);
                testCase.verifyEqual(actual.summary.nRadiusMismatch, 0);
            end
        end

        function coordinateColumnsCanUseDifferentUnits(testCase)
            raw = smallTable();
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            expected = alignest.prepareData(raw, mapping);
            units = struct("Xmm", "m", "Ymm", "um", "markXmm", "nm", "markYmm", "µm");
            [~, scale] = alignest.coordinateUnits(units);
            for name = string(fieldnames(scale)).'
                raw.(name) = raw.(name) / scale.(name);
            end
            actual = alignest.prepareData(raw, mapping, coordinateUnits=units);
            testCase.verifyEqual(actual.units, expected.units, 'AbsTol', 1e-10);
            testCase.verifyEqual(actual.coordinateUnits.markYmm, "um");
            testCase.verifyError(@() alignest.prepareData(raw, mapping, coordinateUnits=struct("Xmm", "inch")), ...
                'alignest:coordinateUnit');
        end

        function rowParityUsesShotYBeforeFilteringAndIgnoresInputOrder(testCase)
            raw = smallTable();
            raw.shotNo = 1000 - raw.shotNo; % Shot 番号の奇偶とは独立
            raw.Ymm(raw.Ymm == 33) = 200;  % 最上段を全て半径の外にする
            raw.Radius = hypot(raw.Xmm, raw.Ymm);
            raw = raw(end:-1:1, :);
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            unit = data.units(1);
            testCase.verifyEqual(unit.shots.row(unit.shots.Ymm == 0), repmat(2, 3, 1));
            testCase.verifyEqual(unit.shots.rowParity(unit.shots.Ymm == 0), repmat(2, 3, 1));
            testCase.verifyEqual(unit.shots.rowParity(unit.shots.Ymm == -33), ones(3, 1));
            testCase.verifyEqual(unit.marks.shotRowParity, unit.shots.rowParity(unit.marks.shotIndex));
            % 同じ Wafer でも測定日時ごとに最上段から数え直す
            second = raw(raw.Ymm ~= 200, :);
            second.DateTime(:) = "2026/10/18 09:00:00";
            data = alignest.prepareData([raw; second], alignest.guessColumnMapping(raw.Properties.VariableNames));
            testCase.verifyEqual(data.units(2).shots.rowParity(data.units(2).shots.Ymm == 0), ones(3, 1));
        end

        function statusDuplicatesAndRadiusFollowTheRules(testCase)
            raw = smallTable();
            % 重複：同じ座標の行を足す（X は有効な値どうしの平均、Y は片方が未測定）
            duplicate = raw(1, :);
            duplicate.measX = 3;
            duplicate.measY = 100;
            duplicate.StsY = -1;
            raw = [raw; duplicate];
            % 半径 150 mm ちょうどの点（除外される）
            outside = raw(2, :);
            outside.Xmm = 140;
            outside.Ymm = 0;
            outside.markXmm = 10;
            outside.markYmm = 0;
            outside.Radius = 140;
            raw = [raw; outside];
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            testCase.verifyEqual(data.summary.nDuplicateRows, 1);
            testCase.verifyEqual(data.summary.nOutsideRadius, 1);
            unit = data.units(1);
            first = find(unit.marks.x == raw.Xmm(1) + raw.markXmm(1) & unit.marks.y == raw.Ymm(1) + raw.markYmm(1));
            testCase.verifyEqual(unit.marks.measX(first), (raw.measX(1) + 3) / 2, 'AbsTol', 1e-12, 'X は2行の平均');
            testCase.verifyEqual(unit.marks.measY(first), raw.measY(1), 'AbsTol', 1e-12, 'Y は有効な1行だけ');
            % StsX = -1 の点は X だけ無効
            invalidRow = find(raw.StsX == -1, 1);
            mark = find(unit.marks.x == raw.Xmm(invalidRow) + raw.markXmm(invalidRow) & ...
                unit.marks.y == raw.Ymm(invalidRow) + raw.markYmm(invalidRow));
            testCase.verifyFalse(unit.marks.validX(mark));
            testCase.verifyTrue(unit.marks.validY(mark));
            testCase.verifyTrue(all(unit.marks.r < 150));
        end

        function radiusMismatchIsReported(testCase)
            raw = smallTable();
            raw.Radius(3) = raw.Radius(3) + 0.5;
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            testCase.verifyEqual(data.summary.nRadiusMismatch, 1);
            testCase.verifyTrue(any(contains(data.summary.messages, "Radius")));
        end

        function missingRequiredColumnIsAnError(testCase)
            raw = removevars(smallTable(), "measY");
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            testCase.verifyError(@() alignest.prepareData(raw, mapping), 'alignest:missingColumn');
        end

        function invalidDirectionIsAnError(testCase)
            raw = smallTable();
            raw.Direction(2) = 3;
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            testCase.verifyError(@() alignest.prepareData(raw, mapping), 'alignest:direction');
        end

        function numbersAreDerivedWhenColumnsAreMissing(testCase)
            raw = removevars(smallTable(), ["shotNo", "markNo", "Direction", "StsX", "StsY"]);
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            unit = data.units(1);
            testCase.verifyFalse(unit.hasDirection);
            % Shot 番号は上の行から左→右
            [~, order] = sortrows([-unit.shots.Ymm, unit.shots.Xmm]);
            testCase.verifyEqual(unit.shots.shotNo(order), (1:numel(order)).');
            testCase.verifyEqual(unique(unit.marks.markNo).', 1:4);
        end

        function dateTimeSeparatesMeasurements(testCase)
            raw = smallTable();
            second = raw;
            second.DateTime(:) = "2026/10/18 09:00:00";
            data = alignest.prepareData([raw; second], alignest.guessColumnMapping(raw.Properties.VariableNames));
            testCase.verifyEqual(numel(data.units), 2);
            testCase.verifyTrue(all(contains(string({data.units.label}), "2026/10/1")));
        end

        function textNumbersAndCaseInsensitiveNamesAreAccepted(testCase)
            raw = smallTable();
            raw.measX = string(raw.measX);
            raw = renamevars(raw, ["markXmm", "Wafer"], ["MARKXMM", "wafer"]);
            mapping = alignest.guessColumnMapping(raw.Properties.VariableNames);
            testCase.verifyEqual(mapping.markXmm, "MARKXMM");
            testCase.verifyEqual(mapping.Wafer, "wafer");
            data = alignest.prepareData(raw, mapping);
            testCase.verifyTrue(all(isfinite(data.units(1).marks.measX(data.units(1).marks.validX))));
        end

        function sampleExcelFileIsRead(testCase)
            file = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'sample_data', 'sample_alignment.xlsx');
            [raw, sheets] = alignest.readMeasurementFile(file);
            testCase.verifyEqual(sheets, "アライメント計測");
            data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
            testCase.verifyEqual(numel(data.units), 5);
            testCase.verifyEqual(data.summary.nDuplicateRows, 15);
            testCase.verifyEqual(data.summary.nShotsRange, [99, 99]);
        end

        function unsupportedFileIsAnError(testCase)
            file = [tempname, '.txt.json'];
            fileId = fopen(file, 'w');
            fprintf(fileId, '{}');
            fclose(fileId);
            cleanup = onCleanup(@() delete(file));
            testCase.verifyError(@() alignest.readMeasurementFile(file), 'alignest:fileType');
        end
    end
end

function raw = smallTable()
% 3 × 3 の Shot、Mark 4点の小さな表（値は座標の式）
[column, row] = meshgrid(-1:1, -1:1);
shotX = column(:) * 26;
shotY = row(:) * 33;
marks = [-10, -12; 10, -12; 10, 12; -10, 12];
n = numel(shotX) * 4;
shotIndex = repelem((1:numel(shotX)).', 4);
markIndex = repmat((1:4).', numel(shotX), 1);
Xmm = shotX(shotIndex);
Ymm = shotY(shotIndex);
markXmm = marks(markIndex, 1);
markYmm = marks(markIndex, 2);
x = Xmm + markXmm;
y = Ymm + markYmm;
raw = table(repmat("W01", n, 1), repmat("2026/10/17 09:00:00", n, 1), shotIndex, 1 + mod(column(shotIndex) + 1, 2), ...
    Xmm, Ymm, hypot(Xmm, Ymm), markIndex, markXmm, markYmm, 0.02 * x + 0.5, -0.01 * y + 0.3, zeros(n, 1), zeros(n, 1), ...
    'VariableNames', ["Wafer", "DateTime", "shotNo", "Direction", "Xmm", "Ymm", "Radius", "markNo", "markXmm", ...
    "markYmm", "measX", "measY", "StsX", "StsY"]);
raw.StsX(7) = -1;
end

function raw = rasterTable(nRows, nColumns, shotNos)
% nRows × nColumns の Shot（Mark 1 点）。Shot は上の行から左→右の順に並べ、shotNo をその順に shotNos で付ける
[column, row] = meshgrid(1:nColumns, 1:nRows);
order = reshape(permute(cat(3, row, column), [2, 1, 3]), [], 2);   % 上の行から、各行は左→右
Xmm = (order(:, 2) - (nColumns + 1) / 2) * 26;
Ymm = ((nRows + 1) / 2 - order(:, 1)) * 33;
n = numel(Xmm);
raw = table(repmat("W01", n, 1), shotNos(:), Xmm, Ymm, zeros(n, 1), zeros(n, 1), 0.01 * Xmm, -0.01 * Ymm, ...
    'VariableNames', ["Wafer", "shotNo", "Xmm", "Ymm", "markXmm", "markYmm", "measX", "measY"]);
end
