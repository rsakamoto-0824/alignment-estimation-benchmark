classdef TestAppConsistency < matlab.unittest.TestCase
    %TESTAPPCONSISTENCY アプリ全体の点検で直したところ：図の画像の保存（保存できないときの知らせ）、データを変えたときに
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
            % 画面を出していないとき・図の名前が違うときは、MATLAB を止めずにエラーで知らせる
            % （画面を出したときの保存は、見えない画面では書き出せないので自動テストでは確かめない）
            app = AlignmentEstimationApp(false);
            cleanup = onCleanup(@() delete(app));
            file = [tempname, '.png'];
            testCase.verifyError(@() app.saveFigureImage("chart", file), 'alignest:hiddenFigure');
            testCase.verifyError(@() app.saveFigureImage("noSuchFigure", file), 'alignest:figureName');
            testCase.verifyFalse(isfile(file));
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
