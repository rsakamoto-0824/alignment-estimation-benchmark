classdef TestDataPreparation < matlab.unittest.TestCase
    %TESTDATAPREPARATION 読み込みと前処理（Overlay 計測ルールの決まり）を確かめる。

    methods (TestClassSetup)
        function addAppPath(~)
            addpath(fileparts(fileparts(mfilename('fullpath'))));
        end
    end

    methods (Test)
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
