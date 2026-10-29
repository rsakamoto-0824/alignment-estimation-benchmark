classdef (Abstract) Display < appui.Core
    %DISPLAY 「8. ヘルプ」タブと表示の設定：画面の色（ライト・ダーク）、文字の大きさ、凡例の位置、画面（モニター）の大きさに合わせる窓。
    %   AlignmentEstimationApp（画面の本体）の一部。画面の部品は Controls、データ・結果は Core のプロパティに持つ。
    %   ほかのタブの関数も同じように呼べる（どれも AlignmentEstimationApp の関数になる）。

    methods
        function fitToScreen(app, center)
            %FITTOSCREEN 窓を、窓の中心がある画面（モニター）に合わせる（メニューの「表示」→「画面の大きさに合わせる」）。
            %   大きさは FIGURE_SIZE を画面に収まるように縮めたもの（画面が大きければ FIGURE_SIZE に戻す）。窓は画面の
            %   中に入れ、center が true（省略時）なら画面の中央に置く。決まった幅の欄も窓の幅に合わせる。
            if nargin < 2
                center = true;
            end
            [~, monitor] = monitorIndexOf(app.Figure.Position);
            available = monitor(3:4) - 2 * app.SCREEN_MARGIN;
            size_ = max(min(app.FIGURE_SIZE, available), min(app.MIN_FIGURE_SIZE, monitor(3:4)));
            corner = app.Figure.Position(1:2);
            if center
                corner = monitor(1:2) + (monitor(3:4) - size_) / 2;
            end
            % 画面の外にはみ出さない（左下の角を、画面の中に収まる範囲に入れる）
            lower = monitor(1:2);
            upper = max(monitor(1:2) + monitor(3:4) - size_, lower);
            corner = min(max(corner, lower), upper);
            app.Figure.Position = [round(corner), round(size_)];
            app.CurrentMonitor = monitorIndexOf(app.Figure.Position);
            applyResponsiveLayout(app);
        end

        function setTheme(app, mode)
            %SETTHEME 画面の色を mode = "light"（ライトモード）・"dark"（ダークモード）にする（メニューの「表示」と同じ）。
            %   画面の部品・図（軸・文字・凡例・色の目盛り）・表・ヘルプの色を変え、これから描く図にも同じ色を使う。
            %   画面を出しているときは、次に開いたときも同じ色にする（setpref）。
            mode = string(mode);
            if ~any(mode == ["light", "dark"])
                error('alignest:theme', '画面の色は light（ライトモード）か dark（ダークモード）です: %s', mode);
            end
            previous = themePalette(app.Theme);
            app.Theme = mode;
            applyTheme(app, previous, themePalette(mode));
            app.Controls.themeLight.Checked = onOff(mode == "light");
            app.Controls.themeDark.Checked = onOff(mode == "dark");
            savePreference(app, 'theme', char(mode));
        end

        function setFontSize(app, size)
            %SETFONTSIZE 画面の文字の大きさを size [pt] にする（メニューの「表示」→「文字の大きさ」と同じ。16 が標準）。
            %   画面の欄・表の文字と、描いた図の文字（軸・題名・凡例・図の中の文字・色の目盛り）を同じ比で変え、
            %   これから描く図にも使う。決まった幅・高さの欄（左の条件の欄・一覧の高さなど）と表の列の幅も同じ比で変える
            %   （大きな文字が欄からはみ出さないように）。画面を出しているときは、次に開いたときも同じ大きさにする（setpref）。
            if ~(isnumeric(size) && isscalar(size) && isfinite(size) && size >= app.FONT_SIZE_LIMITS(1) && ...
                    size <= app.FONT_SIZE_LIMITS(2))
                error('alignest:fontSize', '文字の大きさは %d〜%d [pt] の数で指定します。', app.FONT_SIZE_LIMITS(1), ...
                    app.FONT_SIZE_LIMITS(2));
            end
            previousScale = app.FontScale;
            app.FontSize = double(size);
            applyFontSize(app, previousScale);
            for item = app.Controls.fontSizeItems
                item.Checked = onOff(item.UserData == app.FontSize);
            end
            savePreference(app, 'fontSize', app.FontSize);
        end

        function setLegendLocation(app, location, target)
            %SETLEGENDLOCATION 図の凡例の位置を location にする（LEGEND_CHOICES の1つ。"auto" は図ごとの既定、
            %   "none" は凡例を出さない）。target を省略すると、すべての図（メニューの「表示」→「凡例の位置」）。
            %   target に図（axes）か図の名前（Controls の名前。並べた図は枠の名前）を渡すと、その図だけ（図を右クリック
            %   したときのメニュー）。location = "inherit" で、その図の指定をやめて、すべての図の設定に従う。
            %   描いてある図はすぐに置き直し、これから描く図にも使う。画面を出しているときは、次に開いたときも同じにする。
            location = string(location);
            if nargin < 3
                if ~(isscalar(location) && any(location == app.LEGEND_CHOICES))
                    error('alignest:legendLocation', '凡例の位置は %s のどれかです: %s', ...
                        join(app.LEGEND_CHOICES, "・"), join(location, "・"));
                end
                app.LegendLocation = location;
                markLegendItems(app);
                savePreference(app, 'legendLocation', char(location));
            else
                if isstring(target) || ischar(target)
                    key = string(target);
                else
                    key = legendKey(app, legendOwner(target));
                end
                if ~(isscalar(key) && isvarname(key))
                    error('alignest:legendLocation', '凡例の位置を変える図が見つかりません。');
                end
                if ~(isscalar(location) && any(location == [app.LEGEND_CHOICES, "inherit"]))
                    error('alignest:legendLocation', '図ごとの凡例の位置は %s のどれかです: %s', ...
                        join([app.LEGEND_CHOICES, "inherit"], "・"), join(location, "・"));
                end
                if location == "inherit"
                    if isfield(app.LegendOverrides, key)
                        app.LegendOverrides = rmfield(app.LegendOverrides, key);
                    end
                else
                    app.LegendOverrides.(key) = location;
                end
                savePreference(app, 'legendOverrides', app.LegendOverrides);
            end
            placeAllLegends(app);
        end

        function resetLegendOverrides(app)
            %RESETLEGENDOVERRIDES 図ごとに選んだ凡例の位置をすべてやめて、すべての図の設定に従う
            app.LegendOverrides = struct();
            savePreference(app, 'legendOverrides', app.LegendOverrides);
            placeAllLegends(app);
        end

        function saveFigureImage(app, figureName, filePath)
            %SAVEFIGUREIMAGE 画面の図を PNG に保存する（「図を画像で保存…」のボタンと同じ）。figureName：
            %   "measure"（3. 実行の計測マップ）・"chart"（4. 結果一覧のグラフ）・"map"（5. Waferごとのマップ）・
            %   "target"（6. 未知の座標の図）・"targetResidual"（6. の補正残差の図）・"highOrder"（7. Shot高次補正の
            %   マップ）。凡例・色の目盛りも入れる。
            %   図が2つ以上（グラフの I 基準・D 基準、マップの計測値・推定値・残差）なら横に並べて1枚にする。
            %   画面の部品（uigridlayout）を含む枠は exportgraphics で書き出せない（白紙になり保存に失敗する）ので、
            %   図（axes）・並べた図（tiledlayout）ごとに書き出してつなぐ。描いた図が無ければエラー。
            %   画面を出していないときもエラー（見えない画面の図を書き出すと MATLAB が止まることがあるため）。
            imwrite(figureImage(app, figureName), filePath);
        end

        function copyFigureImage(app, figureName)
            %COPYFIGUREIMAGE 画面の図を、保存と同じ画像としてクリップボードにコピーする（「図をコピー」のボタンと同じ）。
            %   PowerPoint・Teams・メールなどに貼り付けられる。figureName は saveFigureImage と同じ。
            %   MATLAB の copygraphics は図しかコピーできないので、作った画像を作業用の見えない figure に原寸で描いて
            %   画像としてコピーする。描いた図が無いとき・画面を出していないときはエラー。
            pixels = figureImage(app, figureName);
            helper = figure('Visible', 'off', 'Units', 'pixels', 'Position', [0, 0, size(pixels, 2), size(pixels, 1)], ...
                'Color', 'w');
            cleanup = onCleanup(@() delete(helper));
            ax = axes(helper, 'Units', 'normalized', 'Position', [0, 0, 1, 1]);
            image(ax, pixels);
            axis(ax, 'image', 'off');
            copygraphics(helper, 'ContentType', 'image', 'Resolution', get(groot, 'ScreenPixelsPerInch'));
        end

        function captureTab(app, tabName, filePath)
            %CAPTURETAB タブを表示して画面の画像を保存する（説明資料・動作確認用）。
            % 画面の配置が描き終わるまで少し待ってから保存する（すぐ保存すると古い配置の絵になることがある）
            RENDER_WAIT_SECONDS = 1.5;
            app.TabGroup.SelectedTab = app.Tabs.(tabName);
            drawnow;
            pause(RENDER_WAIT_SECONDS);
            drawnow;
            exportapp(app.Figure, filePath);
        end
    end

    methods (Access = {?appui.Core})
        % ================= 8. ヘルプ =================
        function buildHelpTab(app)
            % 用語・推定の手法・カーネル・Overlay 補正の式の説明（help/help.html。exe にも入れる）を出す
            grid = uigridlayout(app.Tabs.help, [1, 1], 'Padding', 0);
            % help フォルダは、このファイルのある +appui の1つ上（アプリのフォルダ）にある
            helpFile = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'help', 'help.html');
            c.helpView = uihtml(grid, 'HTMLSource', helpFile, 'Data', helpData(app));
            if ~isfile(helpFile)
                c.helpView.HTMLSource = ['<p style="font-family:sans-serif">ヘルプのファイルが見つかりません：', ...
                    char(helpFile), '</p>'];
            end
            app.Controls = mergeStruct(app.Controls, c);
        end

        % ================= 画面の色（ライト・ダーク） =================
        function applyTheme(app, old, new)
            % 画面の部品と図の色を old から new の色の組に変える。これから描く図の色は、図の既定値（Default…）で決める
            % （図を描き直す関数は cla(ax, 'reset') で既定値に戻すので、そのまま新しい色になる）
            fig = app.Figure;
            fig.Color = new.background;
            set(fig, 'DefaultAxesColor', new.axes, 'DefaultAxesXColor', new.axisLine, 'DefaultAxesYColor', new.axisLine, ...
                'DefaultAxesZColor', new.axisLine, 'DefaultAxesGridColor', new.grid, 'DefaultAxesMinorGridColor', new.grid, ...
                'DefaultTextColor', new.text, 'DefaultLegendTextColor', new.text, 'DefaultLegendColor', new.axes, ...
                'DefaultLegendEdgeColor', new.grid, 'DefaultColorbarColor', new.axisLine);
            for object = reshape(findall(fig), 1, [])
                if ~isvalid(object) || ~isprop(object, 'Type')
                    continue   % 色を持たない部品（図の中の空の置き場など）
                end
                switch object.Type
                    case 'uigridlayout'
                        object.BackgroundColor = new.background;
                    case 'uipanel'
                        object.BackgroundColor = new.background;
                        object.ForegroundColor = new.text;
                    case 'uitab'
                        % タブの見出しの地はどちらのモードでも明るいので、見出しの文字は黒のまま（中の地だけ変える）
                        object.BackgroundColor = new.background;
                    case 'uilabel'
                        object.FontColor = themeColor(object.FontColor, old, new);
                    case 'uicheckbox'
                        object.FontColor = new.text;
                    case 'uibutton'
                        if object.Tag ~= "primary"
                            object.BackgroundColor = new.button;
                            object.FontColor = new.text;
                        end
                    case 'uidropdown'
                        object.BackgroundColor = new.button;
                        object.FontColor = new.text;
                    case {'uieditfield', 'uinumericeditfield', 'uispinner', 'uitextarea', 'uilistbox'}
                        object.BackgroundColor = new.field;
                        object.FontColor = new.text;
                    case 'uitable'
                        object.BackgroundColor = [new.field; new.fieldAlt];
                        object.ForegroundColor = new.text;
                    case 'axes'
                        themeAxes(object, old, new);
                    case 'uihtml'
                        object.Data = helpData(app);
                end
            end
            % 色に依存する表の印（座標の単位の警告・各列の最良）を付け直す
            fillUnitTable(app);
            if ~isempty(app.Results)
                refreshResults(app);
            end
            if ~isempty(app.TargetRun)
                showTargetRun(app);   % 外挿の行の色・メッセージの色を新しい色の組にする
            end
            refreshHighOrderTerms(app);   % VIF の大きい行・使わない行の色
            if ~isempty(app.HighOrderRun)
                showHighOrderRun(app);
            end
        end

        function data = helpData(app)
            % ヘルプ（uihtml）に渡す表示の設定：画面の色と文字の大きさの比
            data = struct("theme", app.Theme, "fontScale", app.FontScale);
        end

        % ================= 表示の設定（文字の大きさ・凡例の位置） =================
        function value = loadPreference(app, name, fallback)
            % 前回保存した表示の設定（getpref）。読めないときは fallback
            try
                value = getpref(app.PREF_GROUP, name, fallback);
            catch
                value = fallback;
            end
        end

        function savePreference(app, name, value)
            % 表示の設定を、次に開いたときも使えるように保存する（画面を出しているときだけ。自動テストでは保存しない）
            if app.Figure.Visible == "on"
                try
                    setpref(app.PREF_GROUP, name, value);
                catch
                    % 保存できなくても、今の画面の表示は変わっている
                end
            end
        end

        function tables = fontTables(app)
            % 列の多い表（TABLE_FONT_SIZE の文字で出す表）
            tables = [app.Controls.unitTable, app.Controls.normalityTable, app.Controls.anovaTable, ...
                app.Controls.targetTable, app.Controls.targetResultTable, app.Controls.highOrderTermTable, ...
                app.Controls.highOrderSummaryTable, app.Controls.highOrderCoefficientTable];
        end

        function pixels = scaledPixels(app, pixels)
            % 標準の文字の大きさのときの幅・高さ [px] を、今の文字の大きさに合わせる
            pixels = round(pixels * app.FontScale);
        end

        function applyFontSize(app, previousScale)
            % 画面の欄・表・図の文字と、決まった大きさの欄・表の列の幅を、今の文字の大きさ（FontScale）にする
            set(fontComponents(app.Figure), 'FontSize', scaledPixels(app, app.FONT_SIZE));
            % 文字の大きさを変えるときに、表が無くなっていても止まらないように、ある表だけに付ける
            % （点検で一度だけ、無くなった表に付けようとして止まったことがある。原因は再現できていない）
            tables = fontTables(app);
            set(tables(isvalid(tables)), 'FontSize', scaledPixels(app, app.TABLE_FONT_SIZE));
            % 今見えているタブは付け直し済み。ほかのタブは開いたときに付け直す（refreshTabFonts）
            app.FontVersion = app.FontVersion + 1;
            markShownTabs(app, app.TabGroup.SelectedTab);
            % 表の列の幅（描いたときに今の文字の大きさで決めた幅）は、前の大きさとの比で変える
            for table_ = reshape(findall(app.Figure, 'Type', 'uitable'), 1, [])
                widths = table_.ColumnWidth;
                if iscell(widths)
                    fixed = cellfun(@(width) isnumeric(width) && width > 0, widths);
                    widths(fixed) = cellfun(@(width) round(width * app.FontScale / previousScale), widths(fixed), ...
                        'UniformOutput', false);
                    table_.ColumnWidth = widths;
                end
            end
            for item = app.FixedSizes
                if ~isvalid(item.grid)
                    continue
                end
                sizes = item.grid.(item.property);
                % 隠している行・列（0）や、後から 'fit' などに変えた行・列はそのままにする
                if item.index <= numel(sizes) && isnumeric(sizes{item.index}) && sizes{item.index} > 0
                    sizes{item.index} = scaledPixels(app, item.size);
                    item.grid.(item.property) = sizes;
                end
            end
            applyResponsiveLayout(app);
            styleAxes(app, findall(app.Figure, 'Type', 'axes'));
            app.Controls.helpView.Data = helpData(app);
        end

        function refreshTabFonts(app, tab)
            % 開いたタブの部品の文字の大きさを付け直す（見えていないときに変えた大きさが、ボタン・選ぶ欄などに出ないことが
            % あるため。同じ値を入れ直しても描き直されないので、一度別の値にしてから戻す）。文字の大きさを変えてから
            % まだ付け直していないタブだけ
            if ~isa(tab, 'matlab.ui.container.Tab') || ~isvalid(tab) || ...
                    (isappdata(tab, 'AlignFontVersion') && getappdata(tab, 'AlignFontVersion') == app.FontVersion) || ...
                    (~isappdata(tab, 'AlignFontVersion') && app.FontVersion == 0)
                return
            end
            components = fontComponents(tab);
            if ~isempty(components)
                sizes = get(components, {'FontSize'});
                set(components, 'FontSize', 1);
                set(components, {'FontSize'}, sizes);
            end
            markShownTabs(app, tab);
        end

        function markShownTabs(app, tab)
            % tab と、その中で今見えているタブ（入れ子のタブで選んでいるもの）に、文字を付け直した印を付ける
            setappdata(tab, 'AlignFontVersion', app.FontVersion);
            for tabGroup = reshape(findall(tab, 'Type', 'uitabgroup'), 1, [])
                shown = true;
                ancestor = tabGroup.Parent;
                while shown && ancestor ~= tab
                    if isa(ancestor, 'matlab.ui.container.Tab')
                        shown = ancestor.Parent.SelectedTab == ancestor;
                    end
                    ancestor = ancestor.Parent;
                end
                if shown && ~isempty(tabGroup.SelectedTab)
                    setappdata(tabGroup.SelectedTab, 'AlignFontVersion', app.FontVersion);
                end
            end
        end

        function collectFixedSizes(app)
            % 決まった大きさ [px] の行・列（一覧の高さ・入力欄の幅など）を、標準の文字の大きさのときの大きさとして覚える
            % （文字の大きさを変えたときに同じ比で変えるため。窓の幅に合わせる欄は applyResponsiveLayout が受け持つ）
            for grid = reshape(findall(app.Figure, 'Type', 'uigridlayout'), 1, [])
                if grid == app.RootGrid
                    continue
                end
                for property = ["RowHeight", "ColumnWidth"]
                    sizes = grid.(property);
                    for k = 1:numel(sizes)
                        responsive = property == "ColumnWidth" && ...
                            any(arrayfun(@(item) item.grid == grid && item.column == k, app.ResponsiveColumns));
                        if isnumeric(sizes{k}) && sizes{k} > 0 && ~responsive
                            app.FixedSizes(end + 1) = struct("grid", grid, "property", property, "index", k, ...
                                "size", sizes{k});
                        end
                    end
                end
            end
        end

        function styleAxes(app, axesList, baseSize)
            %STYLEAXES 描いた図に表示の設定（文字の大きさ・凡例の位置）を当てる。図を描く関数の最後に呼ぶ。
            %   baseSize：標準の文字の大きさのときの軸の文字の大きさ（省略すると前に決めた大きさ。無ければ AXES_FONT_SIZE）。
            %   図の中の文字・色の目盛り・大きさを決めた凡例は、描いた関数が決めた大きさを基準に同じ比で変える
            %   （題名・軸の名前・大きさを決めていない凡例は、軸の文字の大きさに合わせて変わる）。
            %   図を右クリックすると、その図だけの凡例の位置を選べるようにする。
            for ax = reshape(axesList, 1, [])
                if ~isvalid(ax)
                    continue
                end
                if nargin >= 3
                    setappdata(ax, 'AlignAxesFontSize', baseSize);
                end
                base = app.AXES_FONT_SIZE;
                if isappdata(ax, 'AlignAxesFontSize')
                    base = getappdata(ax, 'AlignAxesFontSize');
                end
                ax.FontSize = base * app.FontScale;
                labels = [ax.Title, ax.Subtitle, ax.XLabel, ax.YLabel, ax.ZLabel];
                texts = findall(ax, 'Type', 'text');
                texts = texts(~arrayfun(@(text_) any(text_ == labels), texts));
                parts = [reshape(texts, 1, []), ax.Colorbar];
                if ~isempty(ax.Legend) && isvalid(ax.Legend) && ax.Legend.FontSizeMode == "manual"
                    parts = [parts, ax.Legend]; %#ok<AGROW>
                end
                scaleFonts(app, parts);
                placeLegend(app, ax);
                attachLegendMenu(app, ax);
            end
        end

        function scaleFonts(app, objects)
            % 文字の大きさを、描いた関数が決めた大きさ（基準）× 文字の大きさの比にする。基準は図の部品に覚えておく
            % （描き直して大きさが付け直されたら、その大きさを基準にし直す。何度呼んでも同じ大きさになる）
            for object = objects
                if ~isvalid(object)
                    continue
                end
                record = [object.FontSize, NaN];   % [基準, 付けた大きさ]
                if isappdata(object, 'AlignFontBase')
                    saved = getappdata(object, 'AlignFontBase');
                    if abs(object.FontSize - saved(2)) < 1e-9
                        record = saved;
                    end
                end
                record(2) = record(1) * app.FontScale;
                object.FontSize = record(2);
                setappdata(object, 'AlignFontBase', record);
            end
        end

        function placeAllLegends(app)
            % 描いてあるすべての図の凡例を、今の設定の位置に置き直す
            for ax = reshape(findall(app.Figure, 'Type', 'axes'), 1, [])
                placeLegend(app, ax);
            end
        end

        function placeLegend(app, ax)
            % 図の凡例を、選んだ位置（その図の指定、無ければすべての図の設定）に置く。「図ごとの既定」は描いた関数が
            % 決めた位置・並べ方（描き直したら覚え直す）。図の上・下に置くときは横に、それ以外は縦に並べる
            legend_ = ax.Legend;
            if isempty(legend_) || ~isvalid(legend_)
                return
            end
            % 並べた図（tiledlayout）の凡例は、置いた直後の位置を読み直すと古い値のことがあるので、置いた位置を覚えて使う
            % （並べた図は描くたびに作り直すので、描き直されたかを確かめなくてよい）
            tiled = isa(legend_.Parent, 'matlab.graphics.layout.TiledChartLayout');
            current = legendPlace(legend_);
            record = struct("place", current, "orientation", string(legend_.Orientation), ...
                "columns", legend_.NumColumns, "applied", "");
            if isappdata(legend_, 'AlignLegendDefault')
                saved = getappdata(legend_, 'AlignLegendDefault');
                if tiled || saved.applied == current
                    record = saved;
                end
            end
            choice = app.LegendLocation;
            key = legendKey(app, legendOwner(ax));
            if key ~= "" && isfield(app.LegendOverrides, key)
                choice = app.LegendOverrides.(key);
            end
            target = record.place;
            if ~any(choice == ["auto", "none"])
                target = choice;
            end
            if startsWith(target, "tile:")
                % 並べた図の外側（図を並べたときの既定）。タイルの番号のときは数にする
                tile = extractAfter(target, "tile:");
                if ~isnan(str2double(tile))
                    tile = str2double(tile);
                end
                legend_.Location = 'layout';
                legend_.Layout.Tile = tile;
            elseif tiled && endsWith(target, "outside")
                legend_.Location = 'layout';
                legend_.Layout.Tile = extractBefore(target, "outside");
            else
                legend_.Location = target;
            end
            if isWideLegend(target) == isWideLegend(record.place)
                legend_.Orientation = record.orientation;
                legend_.NumColumns = record.columns;
            elseif isWideLegend(target)
                legend_.Orientation = 'vertical';
                legend_.NumColumns = min(numel(legend_.String), app.LEGEND_MAX_COLUMNS);
            else
                legend_.Orientation = 'vertical';
                legend_.NumColumns = 1;
            end
            legend_.Visible = onOff(choice ~= "none");
            record.applied = legendPlace(legend_);
            if tiled
                record.applied = target;
            end
            setappdata(legend_, 'AlignLegendDefault', record);
        end

        function key = legendKey(app, owner)
            % 凡例の位置を図ごとに覚えるための図の名前（Controls の名前。いくつか並ぶ図は「名前_番号」）。無ければ ""
            key = "";
            if isempty(owner) || ~isvalid(owner)
                return
            end
            if isappdata(owner, 'AlignLegendKey')
                key = getappdata(owner, 'AlignLegendKey');
                return
            end
            names = fieldnames(app.Controls);
            ownerClass = class(owner);
            for k = 1:numel(names)
                value = app.Controls.(names{k});
                if ~isa(value, ownerClass) || isempty(value)
                    continue
                end
                index = find(value == owner, 1);
                if ~isempty(index)
                    key = string(names{k});
                    if numel(value) > 1
                        key = key + "_" + index;
                    end
                    setappdata(owner, 'AlignLegendKey', key);
                    return
                end
            end
        end

        function attachLegendMenu(app, ax)
            % 図（と凡例）を右クリックしたときに、その図だけの凡例の位置を選ぶメニューを出す（メニューは図ごとに1つ。
            % 凡例の無い図には付けない。並べた図は、凡例が1つでもあれば、どの図からも選べる）
            legends = ax.Legend;
            if isa(ax.Parent, 'matlab.graphics.layout.TiledChartLayout')
                legends = findobj(ax.Parent.Children, 'flat', 'Type', 'legend');
            end
            if isempty(legends)
                return
            end
            key = legendKey(app, legendOwner(ax));
            if key == ""
                return
            end
            if ~isfield(app.LegendMenus, key) || ~isvalid(app.LegendMenus.(key))
                menu = uicontextmenu(app.Figure, 'ContextMenuOpeningFcn', @(source, ~) app.markLegendMenu(source, key));
                uimenu(menu, 'Text', 'この図の凡例の位置：', 'Enable', 'off');
                uimenu(menu, 'Text', 'すべての図の設定に従う', 'UserData', "inherit", ...
                    'MenuSelectedFcn', @(~, ~) app.setLegendLocation("inherit", key));
                for k = 1:numel(app.LEGEND_CHOICES)
                    choice = app.LEGEND_CHOICES(k);
                    uimenu(menu, 'Text', app.LEGEND_LABELS(k), 'UserData', choice, 'Separator', onOff(k == 1), ...
                        'MenuSelectedFcn', @(~, ~) app.setLegendLocation(choice, key));
                end
                app.LegendMenus.(key) = menu;
            end
            ax.ContextMenu = app.LegendMenus.(key);
            if ~isempty(ax.Legend) && isvalid(ax.Legend)
                ax.Legend.ContextMenu = app.LegendMenus.(key);
            end
        end

        function markLegendMenu(app, menu, key)
            % 右クリックのメニューに、その図の今の指定の印を付ける
            choice = "inherit";
            if isfield(app.LegendOverrides, key)
                choice = app.LegendOverrides.(key);
            end
            for item = reshape(menu.Children, 1, [])
                if ~isempty(item.UserData)
                    item.Checked = onOff(item.UserData == choice);
                end
            end
        end

        function markLegendItems(app)
            % 「表示」→「凡例の位置」のメニューに、今の設定の印を付ける
            for item = app.Controls.legendItems
                item.Checked = onOff(item.UserData == app.LegendLocation);
            end
        end
    end
end

% ================= このファイルだけで使う小さな関数 =================
function components = fontComponents(parent)
% parent の中の画面の部品（欄・ボタン・表など。種類が ui で始まるもの）のうち、文字の大きさを持つもの（図の部品は除く）
components = findall(parent, '-property', 'FontSize');
if ~isempty(components)
    components = components(startsWith(string(get(components, {'Type'})), "ui"));
end
end

function owner = legendOwner(ax)
% 凡例の位置を図ごとに覚えるときの持ち主：ふつうは図（axes）。tiledlayout で並べた図は、並べる枠（描くたびに
% 図が作り直されても、同じ指定を使えるように）
owner = ax;
if isa(ax.Parent, 'matlab.graphics.layout.TiledChartLayout')
    owner = ax.Parent.Parent;
end
end

function place = legendPlace(legend_)
% 凡例の今の位置（Location）。tiledlayout の外側に置いた凡例は "tile:" + タイルの名前（east など）
% （タイルに置いた直後は Location が前の値のまま（自動）のことがあるので、位置を指定していなければタイルとみなす）
place = string(legend_.Location);
if isa(legend_.Parent, 'matlab.graphics.layout.TiledChartLayout') && ...
        (place == "layout" || legend_.LocationMode == "auto")
    tile = legend_.Layout.Tile;
    if ~isempty(tile) && ~isequal(tile, 0)
        place = "tile:" + string(tile);
    end
end
end

function wide = isWideLegend(place)
% 図の上・下に置く凡例（横に並べる）か
wide = any(place == ["northoutside", "southoutside", "tile:north", "tile:south"]);
end

function color = themeColor(current, old, new)
% 文字の色を、前の色の組での役割（エラー・補足・強調・ふつう）のまま新しい色の組の色にする
near = @(a, b) isnumeric(a) && numel(a) == 3 && all(abs(a(:).' - b) < 0.03);
if near(current, old.error)
    color = new.error;
elseif near(current, old.muted)
    color = new.muted;
elseif near(current, old.accent)
    color = new.accent;
else
    color = new.text;
end
end

function themeAxes(ax, old, new)
% 描いてある図の色を変える（軸・題名・凡例・色の目盛り・文字。塗りの上に書いた文字（Tag = keepColor）は変えない）
if ~(ischar(ax.Color) || isstring(ax.Color))
    ax.Color = new.axes;
end
set(ax, 'XColor', new.axisLine, 'YColor', new.axisLine, 'ZColor', new.axisLine, 'GridColor', new.grid, ...
    'MinorGridColor', new.grid);
set([ax.Title, ax.XLabel, ax.YLabel], 'Color', new.text);
if ~isempty(ax.Legend) && isvalid(ax.Legend)
    ax.Legend.TextColor = new.text;
    ax.Legend.EdgeColor = new.grid;
    if ~(ischar(ax.Legend.Color) || isstring(ax.Legend.Color))
        ax.Legend.Color = new.axes;
    end
end
if ~isempty(ax.Colorbar) && isvalid(ax.Colorbar)
    ax.Colorbar.Color = new.axisLine;
    set([ax.Colorbar.Title, ax.Colorbar.Label], 'Color', new.text);
end
for item = reshape(findall(ax, 'Type', 'text'), 1, [])
    if item.Tag ~= "keepColor" && isnumeric(item.Color) && all(abs(item.Color - old.text) < 0.03)
        item.Color = new.text;
    end
end
for item = reshape(findall(ax, 'Tag', 'foreground'), 1, [])
    item.Color = new.text;   % 長さの目安の矢印など、背景と反対の色で描くもの
end
end
