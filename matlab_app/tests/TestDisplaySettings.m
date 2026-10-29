classdef TestDisplaySettings < matlab.unittest.TestCase
    %TESTDISPLAYSETTINGS 「表示」の文字の大きさ（画面の欄・表・図・決まった大きさの欄）と、凡例の位置（すべての図・
    %   図ごと・並べた図）を確かめる。

    properties
        Root
        App
    end

    methods (TestClassSetup)
        function addPath(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.Root);
        end
    end

    methods (TestMethodSetup)
        function openApp(testCase)
            testCase.App = AlignmentEstimationApp(false);
            testCase.addTeardown(@() delete(testCase.App));
            testCase.App.loadFile(fullfile(testCase.Root, 'sample_data', 'sample_alignment.csv'));
            testCase.App.applyMapping();
        end
    end

    methods (Test)
        function fontSizeScalesControlsTablesAndPlots(testCase)
            % 文字の大きさを変えると、欄・表・図の文字と決まった大きさの欄が同じ比で変わり、標準に戻すと元どおり
            app = testCase.App;
            c = app.Controls;
            fontSize = 16;   % アプリの FONT_SIZE・TABLE_FONT_SIZE・AXES_FONT_SIZE と同じ値
            tableFontSize = 13;
            axesFontSize = 13;
            testCase.verifyEqual(app.FontSize, fontSize);
            fixed = app.FixedSizes(1);
            fixedSize = fixed.grid.(fixed.property){fixed.index};
            testCase.verifyEqual(fixedSize, fixed.size);
            shotLegend = c.layoutAxes(1).Legend;
            legendSize = shotLegend.FontSize;
            texts = findobj(c.layoutAxes(1), 'Type', 'text');   % Shot の番号
            textSize = texts(1).FontSize;

            app.setFontSize(20);
            scale = 20 / fontSize;
            testCase.verifyEqual(c.mapping.FontSize, 20);
            testCase.verifyEqual(c.applyMapping.FontSize, 20);
            testCase.verifyEqual(c.unitTable.FontSize, round(tableFontSize * scale));
            testCase.verifyEqual(c.layoutAxes(1).FontSize, axesFontSize * scale, 'AbsTol', 1e-9);
            testCase.verifyEqual(texts(1).FontSize, textSize * scale, 'AbsTol', 1e-9, "図の中の文字");
            testCase.verifyEqual(c.layoutAxes(1).Legend.FontSize, legendSize * scale, 'AbsTol', 1e-9);
            testCase.verifyEqual(fixed.grid.(fixed.property){fixed.index}, round(fixed.size * scale), "決まった大きさの欄");
            testCase.verifyEqual(c.helpView.Data.fontScale, scale);
            testCase.verifyEqual(string({c.fontSizeItems([c.fontSizeItems.UserData] == 20).Checked}), "on");
            % 描き直した図も今の文字の大きさで描く
            app.applyMapping();
            testCase.verifyEqual(c.layoutAxes(1).FontSize, axesFontSize * scale, 'AbsTol', 1e-9);
            texts = findobj(c.layoutAxes(1), 'Type', 'text');
            testCase.verifyEqual(texts(1).FontSize, textSize * scale, 'AbsTol', 1e-9);

            app.setFontSize(12);
            app.setFontSize(fontSize);
            testCase.verifyEqual(c.applyMapping.FontSize, fontSize);
            testCase.verifyEqual(c.unitTable.FontSize, tableFontSize);
            testCase.verifyEqual(c.layoutAxes(1).FontSize, axesFontSize, 'AbsTol', 1e-9);
            testCase.verifyEqual(texts(1).FontSize, textSize, 'AbsTol', 1e-9);
            testCase.verifyEqual(c.layoutAxes(1).Legend.FontSize, legendSize, 'AbsTol', 1e-9);
            testCase.verifyEqual(fixed.grid.(fixed.property){fixed.index}, fixed.size);
            testCase.verifyError(@() app.setFontSize(40), 'alignest:fontSize');
            testCase.verifyError(@() app.setFontSize("大"), 'alignest:fontSize');
        end

        function legendLocationForAllAndForOnePlot(testCase)
            % 凡例の位置：すべての図・図ごと（描き直しても続く）・出さない・図ごとの既定に戻す
            app = testCase.App;
            c = app.Controls;
            shotLegend = c.layoutAxes(1).Legend;   % Shot レイアウト（既定は図の下に横並び）
            markLegend = c.layoutAxes(2).Legend;
            original = {shotLegend.Location, shotLegend.Orientation, shotLegend.NumColumns};
            testCase.verifyEqual(string(original{1}), "southoutside");
            testCase.verifyNotEmpty(c.layoutAxes(1).ContextMenu, "図を右クリックすると凡例の位置を選べる");

            app.setLegendLocation("northwest");
            testCase.verifyEqual(string(shotLegend.Location), "northwest");
            testCase.verifyEqual(string(shotLegend.Orientation), "vertical", "図の中は縦に並べる");
            testCase.verifyEqual(string(markLegend.Location), "northwest");
            app.setLegendLocation("none");
            testCase.verifyEqual(string(shotLegend.Visible), "off");
            app.setLegendLocation("auto");
            testCase.verifyEqual(string(shotLegend.Visible), "on");
            testCase.verifyEqual({shotLegend.Location, shotLegend.Orientation, shotLegend.NumColumns}, original);

            % 図ごと：その図だけ変わり、描き直しても続く。「すべての図の設定に従う」で戻る
            app.setLegendLocation("eastoutside", c.layoutAxes(1));
            testCase.verifyEqual(string(fieldnames(app.LegendOverrides)), "layoutAxes_1");
            testCase.verifyEqual(string(c.layoutAxes(1).Legend.Location), "eastoutside");
            testCase.verifyEqual(string(markLegend.Location), "southoutside");
            app.setLegendLocation("northeast");
            testCase.verifyEqual(string(c.layoutAxes(1).Legend.Location), "eastoutside", "図ごとの指定が優先");
            testCase.verifyEqual(string(markLegend.Location), "northeast");
            app.applyMapping();
            testCase.verifyEqual(string(c.layoutAxes(1).Legend.Location), "eastoutside");
            menu = c.layoutAxes(1).ContextMenu;
            menu.ContextMenuOpeningFcn(menu, []);
            checked = findobj(menu.Children, 'Checked', 'on');
            testCase.verifyEqual(string(checked.UserData), "eastoutside");
            app.setLegendLocation("inherit", "layoutAxes_1");
            testCase.verifyEqual(string(c.layoutAxes(1).Legend.Location), "northeast");
            app.setLegendLocation("southwest", c.layoutAxes(1));
            app.resetLegendOverrides();
            testCase.verifyEmpty(fieldnames(app.LegendOverrides));
            testCase.verifyEqual(string(c.layoutAxes(1).Legend.Location), "northeast");
            testCase.verifyError(@() app.setLegendLocation("middle"), 'alignest:legendLocation');
            testCase.verifyError(@() app.setLegendLocation("north", "noSuchPlot"), 'alignest:legendLocation');
        end

        function legendOfTiledPlots(testCase)
            % 並べた図（計測マップ）の凡例：既定は並べた図の右。図の外は並べた図の外側、図の中は1つ目の図の中
            app = testCase.App;
            settings = app.Settings;
            settings.sampling.nShots = [10, 20];
            app.setSettings(settings);
            app.drawMeasurementMap([1, 2], ["I最適 10 Shot", "I最適 20 Shot"]);
            shown = app.Controls.measureAxes(1).Legend;
            testCase.verifyEqual(string(shown.Location), "layout");
            testCase.verifyEqual(string(shown.Layout.Tile), "east");
            app.setLegendLocation("southoutside");
            testCase.verifyEqual(string(shown.Layout.Tile), "south");
            app.setLegendLocation("northeast");
            testCase.verifyEqual(string(shown.Location), "northeast");
            % 図ごとの指定は並べる枠に付けるので、描き直しても続く
            app.setLegendLocation("westoutside", app.Controls.measureAxes(3));
            testCase.verifyEqual(string(fieldnames(app.LegendOverrides)), "measurePanel");
            app.drawMeasurementMap([1, 2], ["I最適 10 Shot", "I最適 20 Shot"]);
            testCase.verifyEqual(string(app.Controls.measureAxes(1).Legend.Layout.Tile), "west");
            app.resetLegendOverrides();
            app.setLegendLocation("auto");
            shown = app.Controls.measureAxes(1).Legend;
            testCase.verifyEqual(string(shown.Location), "layout");
            testCase.verifyEqual(string(shown.Layout.Tile), "east");
        end
    end
end
