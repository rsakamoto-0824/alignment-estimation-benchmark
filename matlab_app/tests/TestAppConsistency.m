classdef TestAppConsistency < matlab.unittest.TestCase
    %TESTAPPCONSISTENCY アプリ全体の点検で直したところ：図の画像の保存・コピー（できないときの知らせ）、データを変えたときに
    %   前のデータの交互作用の結果を残さないこと、Wafer ごとのマップの上の欄の並び。

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
        function savingFigureExplainsWhyItCannot(testCase)
            % 図の保存・コピー：画面を出していないとき・図の名前が違うときは、MATLAB を止めずにエラーで知らせる
            % （画面を出したときの保存・コピーは、見えない画面では書き出せないので自動テストでは確かめない）。
            % 「図をコピー」のボタンは保存のボタンの隣にあり、結果が無いうちは保存と同じく使えない
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            file = [tempname, '.png'];
            testCase.verifyError(@() app.saveFigureImage("chart", file), 'alignest:hiddenFigure');
            testCase.verifyError(@() app.saveFigureImage("noSuchFigure", file), 'alignest:figureName');
            testCase.verifyError(@() app.copyFigureImage("map"), 'alignest:hiddenFigure');
            testCase.verifyFalse(isfile(file));
            pairs = [c.saveMeasure, c.copyMeasure; c.saveChart, c.copyChart; c.saveMap, c.copyMap; ...
                c.targetSaveFigure, c.targetCopyFigure; c.targetResidualSave, c.targetResidualCopy];
            for k = 1:size(pairs, 1)
                testCase.verifyEqual(pairs(k, 2).Parent, pairs(k, 1).Parent, "保存のボタンの隣");
                testCase.verifyEqual(string(pairs(k, 2).Enable), string(pairs(k, 1).Enable), "保存と同じく使える・使えない");
            end
        end

        function changingDataClearsInteractions(testCase)
            % 読み込むと交互作用を調べ、読み込みの条件を変えたら前のデータの結果を消す（読み込み直すと調べ直す）
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            app.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            app.applyMapping();
            c = app.Controls;
            testCase.verifyNotEmpty(app.Interactions);
            testCase.verifyNotEmpty(c.interactionMainTable.Data);
            testCase.verifyEqual(string(c.interactionRun.Enable), "on");
            c.excludeZeroMeasurements.Value = ~c.excludeZeroMeasurements.Value;
            c.excludeZeroMeasurements.ValueChangedFcn(c.excludeZeroMeasurements, []);
            testCase.verifyEmpty(app.Data);
            testCase.verifyEmpty(app.Interactions);
            testCase.verifyEmpty(c.interactionMainTable.Data);
            testCase.verifyEmpty(c.interactionTable.Data);
            testCase.verifyEqual(string(c.interactionRun.Enable), "off");
            testCase.verifyEqual(string(c.interactionAxes.Visible), "off");
            app.applyMapping();
            testCase.verifyNotEmpty(app.Interactions);
        end

        function mapHeaderKeepsMethodWide(testCase)
            % 「Shot の枠」は2行目、「図を画像で保存…」は右の列（手法・図の内容の欄を広く取るため）
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            c = app.Controls;
            testCase.verifyEqual(c.mapShotFrames.Parent, c.mapScanFrames.Parent);
            testCase.verifyEqual(c.saveMap.Parent, c.mapClearConditions.Parent);
            testCase.verifyNotEqual(c.saveMap.Parent, c.mapMethod.Parent);
            testCase.verifyEqual(numel(c.mapMethod.Parent.ColumnWidth), 9);
        end
    end
end
