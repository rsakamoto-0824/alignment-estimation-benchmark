classdef ProgressWindow < handle
    %PROGRESSWINDOW 時間のかかる計算の進み具合を出す小さな窓（評価中・推定値の計算・計測マップの書き出し）。
    %   window = appui.ProgressWindow(owner, titleText, message, palette, fontSize, cancelText)
    %   使い方は uiprogressdlg と同じ：Value（0〜1）・Message（改行で複数行）・CancelRequested、close(window)。
    %   uiprogressdlg は窓の大きさを変えられないので、知らせの文が長いと（手法・学習パターンの名前が長い、Windows で文字が
    %   大きいなど）文の下が見切れることがある。この窓は文の行数（折り返しを含めて見積もる）に合わせて窓の高さを変える
    %   （高さは減らさない。計算中に窓の大きさが行ったり来たりしないように）。
    %   owner：アプリの画面（uifigure。この中央に出す。見えていなければ窓も出さない＝自動テスト）、palette：画面の色の組
    %   （themePalette）、fontSize：文字の大きさ、cancelText：止めるボタンの文字（"" なら止めるボタンを出さない）。
    %   止めるボタンか窓の × を押すと CancelRequested が true になる（計算の側が見て止める）。

    properties (Dependent)
        Value       % 進み具合（0〜1）
        Message     % 知らせの文
    end

    properties (SetAccess = private)
        CancelRequested (1, 1) logical = false   % 止めるボタン（または窓の ×）が押された
        Window                                   % 窓（uifigure）
    end

    properties (Access = private)
        MessageLabel
        BarGrid
        PercentLabel
        CancelButton
        CurrentValue = 0
        FontSize
        Cancelable
    end

    properties (Constant, Access = private)
        WIDTH = 560               % 窓の幅 [px]
        PADDING = 16              % 窓の内側の余白 [px]
        ROW_SPACING = 10          % 行の間 [px]
        BAR_HEIGHT = 14           % 進み具合の棒の高さ [px]
        BUTTON_HEIGHT = 30        % ボタンの行の高さ [px]
        LINE_HEIGHT_RATIO = 1.6   % 1行の高さ = 文字の大きさ × この比
        WIDE_CHAR_RATIO = 1.05    % 全角などの文字の幅 = 文字の大きさ × この比（行数の見積もり。広めに見る）
        NARROW_CHAR_RATIO = 0.62  % 半角の英数字の幅 = 文字の大きさ × この比
        EXTRA_LINES = 1           % 見積もりの誤差（Windows の字の幅など）のぶん、行を足して高さを取る
        MIN_LINES = 3             % 知らせの欄の行の数の下限（短い文でも窓の大きさを変えずに済むように）
    end

    methods
        function obj = ProgressWindow(owner, titleText, message, palette, fontSize, cancelText)
            obj.FontSize = fontSize;
            obj.Cancelable = string(cancelText) ~= "";
            obj.Window = uifigure('Name', char(titleText), 'Visible', 'off', 'Resize', 'off', 'WindowStyle', 'modal', ...
                'Color', palette.background, 'CloseRequestFcn', @(~, ~) obj.requestCancel());
            grid = uigridlayout(obj.Window, [4, 1], 'RowHeight', {'1x', obj.BAR_HEIGHT, 'fit', obj.BUTTON_HEIGHT}, ...
                'Padding', obj.PADDING, 'RowSpacing', obj.ROW_SPACING, 'BackgroundColor', palette.background);
            obj.MessageLabel = uilabel(grid, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment', 'top', ...
                'FontSize', fontSize, 'FontColor', palette.text);
            % 進み具合の棒：左の列（色）と右の列（地）の幅の比を進み具合にする
            track = uipanel(grid, 'BackgroundColor', palette.field, 'BorderType', 'line');
            obj.BarGrid = uigridlayout(track, [1, 2], 'ColumnWidth', {0, '1x'}, 'Padding', 0, 'ColumnSpacing', 0, ...
                'BackgroundColor', palette.field);
            uipanel(obj.BarGrid, 'BackgroundColor', palette.accent, 'BorderType', 'none');
            uipanel(obj.BarGrid, 'BackgroundColor', palette.field, 'BorderType', 'none');
            obj.PercentLabel = uilabel(grid, 'Text', '0%', 'HorizontalAlignment', 'center', ...
                'FontSize', round(0.85 * fontSize), 'FontColor', palette.muted);
            buttons = uigridlayout(grid, [1, 2], 'ColumnWidth', {'1x', 'fit'}, 'Padding', 0, ...
                'BackgroundColor', palette.background);
            if obj.Cancelable
                obj.CancelButton = uibutton(buttons, 'Text', char(cancelText), 'FontSize', fontSize, ...
                    'BackgroundColor', palette.button, 'FontColor', palette.text, ...
                    'ButtonPushedFcn', @(~, ~) obj.requestCancel());
                obj.CancelButton.Layout.Column = 2;
            end
            obj.Window.Position = [0, 0, obj.WIDTH, obj.windowHeight(obj.MIN_LINES)];
            obj.Message = message;
            obj.placeOver(owner);
            if owner.Visible == "on"
                obj.Window.Visible = 'on';
                drawnow;
            end
        end

        function set.Value(obj, value)
            value = min(max(double(value), 0), 1);
            obj.CurrentValue = value;
            if value <= 0
                widths = {0, '1x'};
            elseif value >= 1
                widths = {'1x', 0};
            else
                widths = {sprintf('%.4fx', value), sprintf('%.4fx', 1 - value)};
            end
            obj.BarGrid.ColumnWidth = widths;
            obj.PercentLabel.Text = sprintf('%d%%', round(100 * value));
        end

        function value = get.Value(obj)
            value = obj.CurrentValue;
        end

        function set.Message(obj, message)
            obj.MessageLabel.Text = char(message);
            % 文の行数に合わせて窓を高くする（上の辺の位置は変えない）
            height = obj.windowHeight(obj.estimateLines(message));
            position = obj.Window.Position;
            if height > position(4)
                obj.Window.Position = [position(1), position(2) + position(4) - height, position(3), height];
            end
        end

        function message = get.Message(obj)
            message = string(obj.MessageLabel.Text);
        end

        function close(obj)
            % 窓を閉じる（uiprogressdlg の close と同じ）
            delete(obj);
        end

        function delete(obj)
            if ~isempty(obj.Window) && isvalid(obj.Window)
                delete(obj.Window);
            end
        end
    end

    methods (Access = private)
        function requestCancel(obj)
            % 止めるボタン・窓の ×：計算の側に止めてもらう（止められない窓では何もしない）
            if ~obj.Cancelable || obj.CancelRequested
                return
            end
            obj.CancelRequested = true;
            obj.CancelButton.Text = '止めています…';
            obj.CancelButton.Enable = 'off';
        end

        function lines = estimateLines(obj, message)
            % 折り返しを含めた行の数の見積もり：行ごとに、全角などの文字（ASCII 以外）と半角の文字の幅を足し、欄の幅で割る
            labelWidth = obj.WIDTH - 2 * obj.PADDING;
            lines = 0;
            for line = reshape(split(string(message), newline), 1, [])
                codes = double(char(line));
                width = (nnz(codes > 127) * obj.WIDE_CHAR_RATIO + nnz(codes <= 127) * obj.NARROW_CHAR_RATIO) * obj.FontSize;
                lines = lines + max(1, ceil(width / labelWidth));
            end
            lines = max(lines + obj.EXTRA_LINES, obj.MIN_LINES);
        end

        function height = windowHeight(obj, lines)
            % 窓の高さ [px]：余白 + 知らせの欄（行の数 × 1行の高さ）+ 棒 + 割合の文字 + ボタンの行 + 行の間
            percentHeight = ceil(obj.LINE_HEIGHT_RATIO * 0.85 * obj.FontSize);
            height = 2 * obj.PADDING + ceil(lines * obj.LINE_HEIGHT_RATIO * obj.FontSize) + obj.BAR_HEIGHT + ...
                percentHeight + obj.BUTTON_HEIGHT + 3 * obj.ROW_SPACING;
        end

        function placeOver(obj, owner)
            % アプリの画面の中央に置く
            ownerPosition = owner.Position;
            position = obj.Window.Position;
            position(1) = ownerPosition(1) + (ownerPosition(3) - position(3)) / 2;
            position(2) = ownerPosition(2) + (ownerPosition(4) - position(4)) / 2;
            obj.Window.Position = position;
        end
    end
end
