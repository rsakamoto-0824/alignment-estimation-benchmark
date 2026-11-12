classdef (Abstract) SettingsTab < appui.Core
    %SETTINGSTAB 「2. 評価の設定」タブ：学習 Shot の選び方・学習 Shot 数・比べる手法・質的変数・Overlay 補正・表示（Scan 方向の色）の設定と、設定ファイルの保存・読み込み。
    %   AlignmentEstimationApp（画面の本体）の一部。画面の部品は Controls、データ・結果は Core のプロパティに持つ。
    %   ほかのタブの関数も同じように呼べる（どれも AlignmentEstimationApp の関数になる）。

    methods
        function setSettings(app, settings)
            %SETSETTINGS 設定を画面に反映する（設定ファイルの読み込みと同じ）。
            %   以前の設定に無い項目は初期値にする。学習 Shot 数は並び（nShots）と開始・終了・刻みをそろえる。
            %   同心円の区切り・外周の半径が比（以前の設定）なら mm に直す。
            settings = alignest.upgradeRadiusSettings(settings);
            settings.methods = alignest.completeMethodSettings(settings.methods);
            if isfield(settings, "sampling")
                settings.sampling = alignest.upgradeLayoutSettings(settings.sampling);   % 以前の手動・ファイルの優先順
            end
            defaults = alignest.defaultSettings();
            for group = ["data", "factors", "sampling", "evaluation", "overlay", "display", "highOrder", "markLayout"]
                if ~isfield(settings, group)
                    settings.(group) = defaults.(group);
                end
                for name = string(fieldnames(defaults.(group))).'
                    if ~isfield(settings.(group), name)
                        settings.(group).(name) = defaults.(group).(name);
                    end
                end
            end
            alignest.checkRandomSeed(settings.sampling.seed);   % 画面を変える前に確かめる（途中で止まらないように）
            settings.data.coordinateUnits = alignest.coordinateUnits(settings.data.coordinateUnits);
            settings.data.directionRule = string(settings.data.directionRule);
            settings.sampling = alignest.syncShotCounts(settings.sampling);
            if ~isempty(app.Data) && ~isequal(dataOptions(settings.data), dataOptions(app.Data))
                invalidatePreparedData(app);
            end
            % 保存した項の組み合わせは、読んだ設定に無い名前のものも残す（画面で保存したものは設定ファイルを読んでも消さない）
            settings.highOrder.termSets = mergeTermSets(settings.highOrder.termSets, app.Settings.highOrder.termSets);
            app.Settings = settings;
            settingsToControls(app);
            refreshRunSummary(app);
        end

        function layouts = loadLayoutPlans(app, filePath, sheetName)
            %LOADLAYOUTPLANS 「Excel ファイルで指定」：学習に使う Shot・Mark を指定した Excel・CSV（shotNo（Mark 単位なら
            %   markNo も）と、パターン（1・0）・優先順（1・2・3…）の列。alignest.readLayoutPlans）を読み、設定
            %   sampling.layoutPlans に入れる。選び方に「Excel ファイルで指定」を足す（ほかに選んでいた選び方はそのまま。
            %   I 最適・D 最適などと比べられる）。前に読んだ指定は置き換える。
            if nargin < 3
                sheetName = "";
            end
            layouts = alignest.readLayoutPlans(filePath, sheetName);
            controlsToSettings(app);
            app.Settings.sampling.layoutPlans = layouts.lines;
            app.Settings.sampling.layoutFile = layouts.file;
            app.Settings.sampling.method = unique([reshape(string(app.Settings.sampling.method), 1, []), "excel"], 'stable');
            settingsToControls(app);
            refreshRunSummary(app);
        end
    end

    methods (Access = {?appui.Core})
        % ================= 2. 評価の設定 =================
        function buildSettingsTab(app)
            grid = uigridlayout(app.Tabs.settings, [2, 2], 'RowHeight', {'1x', 'fit'}, ...
                'ColumnWidth', {'1x', '1.45x'}, 'Padding', 12, 'ColumnSpacing', 12);
            onChange = @(~, ~) app.onSettingsChanged();

            samplingPanel = uipanel(grid, 'Title', '学習に使う Shot');
            s = uigridlayout(samplingPanel, [43, 2], 'RowHeight', repmat({'fit'}, 1, 43), 'ColumnWidth', {'1x', '1x'}, ...
                'Padding', 10, 'RowSpacing', 6, 'Scrollable', 'on');
            label(s, '選び方', 1, [1, 2]);
            c.samplingMethod = uilistbox(s, 'Items', {'制約付き I 最適', '制約付き D 最適', ...
                '制約つきランダム', 'Excel ファイルで指定', ...
                'Mark 単位の I 最適', 'Mark 単位の D 最適'}, ...
                'ItemsData', {'ioptimal', 'doptimal', 'random', 'excel', 'mark', 'markd'}, ...
                'Multiselect', 'on', 'Value', {'ioptimal'}, 'ValueChangedFcn', onChange, ...
                'Tooltip', ['D 最適：I 最適と同じ制約で det(M) を大きくする組。Mark 単位：計測する Shot ではなく Mark を選ぶ' ...
                '（既定では全 Shot を1点以上計測し、Mark 番号の割合を全計測とそろえる）。複数選ぶと、結果一覧の' ...
                '「計測配置の比較」で選び方どうしを比べられます。']);
            place(c.samplingMethod, 2, [1, 2]);
            s.RowHeight{2} = 160;
            label(s, '学習 Shot 数', 3, 1);
            c.countBy = uidropdown(s, 'Items', {'Shot 数で決める', '計測率 [%] で決める'}, 'ItemsData', {'shots', 'rate'}, ...
                'ValueChangedFcn', onChange, 'Tooltip', ['計測率は、Wafer の計測値のある Shot（候補）に対する学習 Shot の' ...
                '割合です。Wafer ごとに 候補 Shot 数 × 計測率 を四捨五入した数の Shot を学習に使います。']);
            place(c.countBy, 3, 2);
            sweep = uigridlayout(s, [3, 4], 'RowHeight', {'fit', 'fit', 'fit'}, 'ColumnWidth', {'fit', '1x', '1x', '1x'}, ...
                'Padding', 0, 'RowSpacing', 2);
            place(sweep, 4, [1, 2]);
            label(sweep, '開始', 1, 2);
            label(sweep, '終了', 1, 3);
            label(sweep, '刻み', 1, 4);
            label(sweep, 'Shot 数', 2, 1);
            c.nShotsStart = shotCountSpinner(sweep, onChange);
            place(c.nShotsStart, 2, 2);
            c.nShotsEnd = shotCountSpinner(sweep, onChange);
            place(c.nShotsEnd, 2, 3);
            c.nShotsStep = shotCountSpinner(sweep, onChange);
            place(c.nShotsStep, 2, 4);
            label(sweep, '計測率 [%]', 3, 1);
            c.rateStart = rateField(sweep, onChange);
            place(c.rateStart, 3, 2);
            c.rateEnd = rateField(sweep, onChange);
            place(c.rateEnd, 3, 3);
            c.rateStep = rateField(sweep, onChange);
            place(c.rateStep, 3, 4);
            c.nShotsList = uilabel(s, 'WordWrap', 'on', 'Text', '');
            place(c.nShotsList, 5, [1, 2]);
            c.nShotsError = errorLabel(app, s, 6, [1, 2]);
            label(s, 'ランダムの繰り返し回数', 7, 1);
            c.randomRepeats = uispinner(s, 'Limits', [1, 1000], 'RoundFractionalValues', 'on', 'ValueChangedFcn', onChange);
            place(c.randomRepeats, 8, 1);
            label(s, 'Excel ファイルで指定', 9, 1);
            c.loadLayouts = uibutton(s, 'Text', 'Excel ファイルを読み込む…', 'ButtonPushedFcn', @(~, ~) app.onLoadLayouts(), ...
                'Tooltip', ['1行目が見出しの表。shotNo の列（Mark 単位なら markNo の列も）と、名前を見出しにした列を並べます。' ...
                '1・0 だけの列はパターン（1 を計測する）、1・2・3… の列は優先順（1 = 必ず計測、その次から順に。0 = 計測' ...
                'しない）で、学習 Shot 数ごとに先頭から使います。「計測マップを Excel に書き出す…」のファイルもそのまま読めます。' ...
                '選び方の「Excel ファイルで指定」も選びます。']);
            place(c.loadLayouts, 9, 2);
            c.layoutPlanInfo = uitextarea(s, 'Editable', 'off', 'Value', {'まだ読み込んでいません'});
            place(c.layoutPlanInfo, 10, [1, 2]);
            s.RowHeight{10} = 90;
            c.layoutPlanError = errorLabel(app, s, 11, [1, 2]);
            heading(s, '必ず計測する・計測しない Shot と Mark', 14);
            selectGrid = uigridlayout(s, [4, 2], 'RowHeight', {'fit', 'fit', 'fit', 'fit'}, 'ColumnWidth', {'1x', '1x'}, ...
                'Padding', 0, 'RowSpacing', 2);
            place(selectGrid, [15, 16], [1, 2]);
            label(selectGrid, '必ず計測する shotNo', 1, 1);
            label(selectGrid, '計測しない shotNo', 1, 2);
            c.requiredShots = uieditfield(selectGrid, 'text', 'ValueChangedFcn', onChange, 'Tooltip', ['ここに書いた Shot を' ...
                '必ず学習に入れ、残りを I 最適（またはランダム）で選びます（拡張 I 最適計画）。Mark 単位の計画では、その Shot の' ...
                ' Mark をすべて計測します。「3. 実行」の計測マップでクリックしても指定できます。']);
            place(c.requiredShots, 2, 1);
            c.excludedShots = uieditfield(selectGrid, 'text', 'ValueChangedFcn', onChange, 'Tooltip', ['ここに書いた Shot は' ...
                '学習に選びません（評価には使います）。I 最適・D 最適・ランダムの Shot と、Mark 単位の計画の Mark に効きます。' ...
                '「3. 実行」の計測マップでクリックしても指定できます。']);
            place(c.excludedShots, 2, 2);
            label(selectGrid, '必ず計測する Mark', 3, 1);
            label(selectGrid, '計測しない Mark', 3, 2);
            markTip = '「shotNo-markNo」（例：12-3）を空白で区切って入れます。「3. 実行」の Mark 単位の計測マップでクリックしても指定できます。';
            c.requiredMarks = uieditfield(selectGrid, 'text', 'ValueChangedFcn', onChange, 'Placeholder', '例：12-3 40-1', ...
                'Tooltip', ['Mark 単位の計画で必ず計測する Mark。' markTip]);
            place(c.requiredMarks, 4, 1);
            c.excludedMarks = uieditfield(selectGrid, 'text', 'ValueChangedFcn', onChange, 'Placeholder', '例：12-3 40-1', ...
                'Tooltip', ['Mark 単位の計画で学習に選ばない Mark（評価には使います）。' markTip]);
            place(c.excludedMarks, 4, 2);
            c.requireOuter = uicheckbox(s, 'Text', '最外周の Shot をすべて必ず計測する', ...
                'ValueChangedFcn', onChange);
            place(c.requireOuter, 17, [1, 2]);
            c.requiredInfo = uilabel(s, 'WordWrap', 'on', 'Text', '');
            place(c.requiredInfo, 18, [1, 2]);
            c.requiredError = errorLabel(app, s, 19, [1, 2]);
            heading(s, '制約', 20);
            radiusMm = app.Settings.data.waferRadiusMm;
            label(s, '同心円の区切り [mm]', 21, [1, 2]);
            c.zoneEdges = uieditfield(s, 'text', 'ValueChangedFcn', onChange, 'Tooltip', sprintf(['Shot 中心の Wafer 中心からの' ...
                '距離 [mm] で区画を分け、区画ごとの Shot 数をそろえます（例：67.5 105 → 0〜67.5・67.5〜105・105 mm 以上の' ...
                '3区画）。Mark 単位の計画では Mark の距離で分け、区画ごとの Mark の数をそろえます（半径の方向のバランス）。' ...
                '0 より大きく %g mm より小さい値。使わないなら空欄。'], radiusMm));
            place(c.zoneEdges, 22, [1, 2]);
            c.zoneError = errorLabel(app, s, 23, [1, 2]);
            c.quadrants = uicheckbox(s, 'Text', '4象限の Shot 数をそろえる', 'ValueChangedFcn', onChange);
            place(c.quadrants, 24, [1, 2]);
            c.scanConstraint = uicheckbox(s, 'Text', 'Scan 方向ごとの Shot 数をそろえる', 'ValueChangedFcn', onChange);
            place(c.scanConstraint, 25, [1, 2]);
            label(s, '許容幅', 26, 1);
            label(s, 'I 最適の基準モデル', 26, 2);
            c.slack = uispinner(s, 'Limits', [0, 10], 'RoundFractionalValues', 'on', 'ValueChangedFcn', onChange);
            place(c.slack, 27, 1);
            c.designOrder = uispinner(s, 'Limits', [1, 8], 'RoundFractionalValues', 'on', 'ValueChangedFcn', onChange);
            place(c.designOrder, 27, 2);
            label(s, '交換法の初期配置の数', 28, [1, 2]);
            % 入力欄と時間の目安（目安の文が長くても入力欄が縦に伸びないように、小さな格子に入れる）と、Mark 単位の計画
            exchangeGrid = uigridlayout(s, [10, 2], 'ColumnWidth', {'1x', '1x'}, 'RowHeight', repmat({'fit'}, 1, 10), ...
                'Padding', 0, 'RowSpacing', 2);
            place(exchangeGrid, 29, [1, 2]);
            c.exchangeStarts = uispinner(exchangeGrid, 'Limits', [1, 100], 'RoundFractionalValues', 'on', ...
                'ValueChangedFcn', onChange, 'Tooltip', ['初期配置 1 つあたりの時間の目安は 約 0.01 秒 × 学習 Shot 数' ...
                '（候補 99 Shot の模擬データで測った値）。10 → 20 にすると学習パターンを作る時間は約 2 倍。模擬データでは' ...
                ' 10〜20 を超えると I 基準はほとんど良くならなかった。']);
            place(c.exchangeStarts, 1, 1);
            c.exchangeInfo = uilabel(exchangeGrid, 'WordWrap', 'on', 'Text', '');
            place(c.exchangeInfo, 2, [1, 2]);
            markLabel = label(exchangeGrid, 'Mark 単位の計画', 3, [1, 2]);
            markLabel.FontWeight = 'bold';
            countByGrid = uigridlayout(exchangeGrid, [1, 2], 'ColumnWidth', {'fit', '1x'}, 'Padding', 0);
            place(countByGrid, 4, [1, 2]);
            label(countByGrid, 'Mark の数の決め方', 1, 1);
            c.markCountBy = uidropdown(countByGrid, 'Items', {'1 Shot あたりの数', '計測する Mark の数（開始・終了・刻み）'}, ...
                'ItemsData', {'perShot', 'total'}, 'ValueChangedFcn', onChange, 'Tooltip', ['1 Shot あたりの数：計測する' ...
                ' Mark の数 = この値 × 候補 Shot 数。計測する Mark の数：Wafer 全体で計測する Mark の数を開始から終了まで刻みごとに' ...
                '比べます。上の「学習 Shot 数」を計測率にしたときは、計測率で決めます。']);
            place(c.markCountBy, 1, 2);
            c.markPerShot = uieditfield(exchangeGrid, 'text', 'ValueChangedFcn', onChange, 'Tooltip', ['1 Shot あたりの' ...
                '計測 Mark 数（空白区切りで複数入れると比べます）。計測する Mark の数 = この値 × 候補 Shot 数（四捨五入）。']);
            place(c.markPerShot, 5, 1);
            markCountGrid = uigridlayout(exchangeGrid, [1, 6], 'ColumnWidth', {'fit', '1x', 'fit', '1x', 'fit', '1x'}, ...
                'Padding', 0);
            place(markCountGrid, 6, [1, 2]);
            c.markCountStart = uispinner(markCountGrid, 'Limits', [1, 100000], 'RoundFractionalValues', 'on', ...
                'ValueChangedFcn', onChange);
            c.markCountEnd = uispinner(markCountGrid, 'Limits', [1, 100000], 'RoundFractionalValues', 'on', ...
                'ValueChangedFcn', onChange);
            c.markCountStep = uispinner(markCountGrid, 'Limits', [1, 100000], 'RoundFractionalValues', 'on', ...
                'ValueChangedFcn', onChange);
            countLabels = ["開始", "終了", "刻み"];
            countControls = [c.markCountStart, c.markCountEnd, c.markCountStep];
            for k = 1:3
                label(markCountGrid, countLabels(k), 1, 2 * k - 1);
                place(countControls(k), 1, 2 * k);
            end
            c.markCountNote = uilabel(exchangeGrid, 'WordWrap', 'on', 'Text', '', 'FontColor', app.Palette.muted, ...
                'UserData', "muted");
            place(c.markCountNote, 7, [1, 2]);
            balanceGrid = uigridlayout(exchangeGrid, [1, 2], 'ColumnWidth', {'fit', '1x'}, 'Padding', 0);
            place(balanceGrid, 8, [1, 2]);
            label(balanceGrid, 'Mark 番号ごとの計測数', 1, 1);
            c.markBalance = uidropdown(balanceGrid, 'Items', {'そろえない', '全計測の割合にそろえる', '均等にする'}, ...
                'ItemsData', {'none', 'ratio', 'equal'}, 'ValueChangedFcn', onChange, 'Tooltip', ['最適計画で選ぶ Mark の数を、' ...
                'Mark 番号ごとにそろえる制約。全計測の割合：候補の全 Mark での割合 × 計測する数 ± 許容幅。均等：計測する数 ÷ ' ...
                'Mark 番号の数（割り切れないときの1つの差だけ。候補の少ない Mark 番号はその数まで）。']);
            place(c.markBalance, 1, 2);
            perShotGrid = uigridlayout(exchangeGrid, [1, 3], 'ColumnWidth', {'fit', 'fit', 70}, 'Padding', 0);
            place(perShotGrid, 9, [1, 2]);
            c.markRequirePerShot = uicheckbox(perShotGrid, 'Text', 'Shot ごとに n 点の Mark 計測を必須にする', ...
                'ValueChangedFcn', onChange, 'Tooltip', ['オン：各 Shot で n 点以上の Mark を必ず計測します（Mark が n 点より' ...
                '少ない Shot はその Shot の全 Mark）。計測する数が足りないときは増やします。オフ：Shot を問わず、' ...
                '計測しない Shot もある組から選びます。']);
            label(perShotGrid, 'n', 1, 2);
            c.markMinPerShot = uispinner(perShotGrid, 'Limits', [1, 99], 'RoundFractionalValues', 'on', 'Value', 1, ...
                'ValueChangedFcn', onChange, 'Tooltip', '各 Shot で必ず計測する Mark の数');
            place(c.markMinPerShot, 1, 3);
            c.markError = errorLabel(app, exchangeGrid, 10, [1, 2]);
            heading(s, '評価', 30);
            label(s, '外周とみなす Mark の半径 [mm]', 31, [1, 2]);
            c.outerRadius = uieditfield(s, 'numeric', 'Limits', [0, radiusMm], 'ValueDisplayFormat', '%.1f', ...
                'ValueChangedFcn', onChange, 'Tooltip', ['Mark の Wafer 中心からの距離 [mm]。結果一覧の「外周の RMSE」' ...
                '「内側の RMSE」と、散布図の色分け「外周・内側」の境目です。']);
            place(c.outerRadius, 32, 1);
            c.removeLinear = uicheckbox(s, 'ValueChangedFcn', onChange, ...
                'Text', 'XY 1次を除いてから推定する');
            place(c.removeLinear, 33, [1, 2]);
            outlierGrid = uigridlayout(s, [2, 3], 'ColumnWidth', {'1x', 'fit', 70}, 'RowHeight', {'fit', 'fit'}, 'Padding', 0, ...
                'RowSpacing', 2);
            place(outlierGrid, 34, [1, 2]);
            c.excludeOutliers = uicheckbox(outlierGrid, 'ValueChangedFcn', onChange, ...
                'Text', '学習データの異常値を除いて推定する', ...
                'Tooltip', ['Wafer・学習パターンごとに、学習点の中心とばらつきを X・Y 別に求め、|値 − 中心| が n × ばらつき' ...
                'を超える軸が1つでもある Mark を、X・Y の両方の学習データから除きます。']);
            place(c.excludeOutliers, 1, [1, 3]);
            c.outlierMethod = uidropdown(outlierGrid, 'Items', {'平均と σ', '中央値と MAD'}, ...
                'ItemsData', {'sigma', 'mad'}, 'ValueChangedFcn', onChange, 'Tooltip', ['MAD = 中央値からの差の絶対値の中央値。' ...
                '1.4826 を掛けると正規分布では σ と同じ大きさになり、外れ値に引きずられにくい判定になります。']);
            place(c.outlierMethod, 2, 1);
            label(outlierGrid, 'n =', 2, 2);
            c.outlierSigma = uieditfield(outlierGrid, 'numeric', 'Limits', [0, Inf], 'LowerLimitInclusive', 'off', ...
                'ValueDisplayFormat', '%g', 'ValueChangedFcn', onChange);
            place(c.outlierSigma, 2, 3);
            c.recordTiming = uicheckbox(s, 'ValueChangedFcn', onChange, ...
                'Text', '処理時間を記録する', ...
                'Tooltip', ['手法 × 学習パターンごとに、1 枚（X・Y）の推定にかかった秒数を集計し、「4. 結果一覧」の指標と' ...
                'Excel の「処理時間」シートに出します。各手法の初回は予備の推定を1回して、読み込みの時間を除きます。']);
            place(c.recordTiming, 35, [1, 2]);
            heading(s, 'Overlay 補正の評価', 36);
            label(s, 'Wafer 成分', 37, 1);
            label(s, 'Shot 共通成分', 37, 2);
            c.overlayWafer = uidropdown(s, 'Items', {'なし', '1次', '2次', '3次', '4次', '5次', ...
                '式を入力'}, 'ItemsData', {0, 1, 2, 3, 4, 5, app.FORMULA_CHOICE}, 'ValueChangedFcn', onChange);
            place(c.overlayWafer, 38, 1);
            c.overlayShotCommon = uidropdown(s, 'Items', {'なし', '1次', '式を入力'}, ...
                'ItemsData', {'none', 'linear', 'formula'}, 'ValueChangedFcn', onChange, ...
                'Tooltip', ['1次：Shot 内の座標（markXmm・markYmm）の1次の補正（k1〜k6：並進・倍率・回転・直交度）。' ...
                '式を入力：下の dx・dy の式。どちらも全 Shot で同じ補正量にします。']);
            place(c.overlayShotCommon, 38, 2);
            formulaHelp = ['項を + でつなぎ、各項は係数と x・y のべきの積（例：k1 + k3*x + k5*y + k7*x^2 + k9*x*y）。' ...
                '係数の値は最小二乗で求めるので、係数の名前・符号は補正量に影響しません。'];
            [c.overlayWaferDx, c.overlayWaferDy] = formulaFields(s, 39, 1, onChange, ['x・y は Shot 中心の座標' ...
                '（Wafer 中心から）。' formulaHelp]);
            [c.overlayShotDx, c.overlayShotDy] = formulaFields(s, 39, 2, onChange, ['x・y は Shot 内の座標' ...
                '（markXmm・markYmm、Shot 中心から）。' formulaHelp]);
            label(s, 'Shot ごとの成分', 40, 1);
            c.overlayPerShot = uidropdown(s, 'Items', {'なし', '並進', '1次', '式を入力'}, ...
                'ItemsData', {'none', 'translation', 'linear', 'formula'}, 'ValueChangedFcn', onChange, ...
                'Tooltip', '式を入力：下の dx・dy の式の係数を、Shot ごとに別々に求めます（x・y は Shot 内の座標）。');
            place(c.overlayPerShot, 41, 1);
            [c.overlayPerShotDx, c.overlayPerShotDy] = formulaFields(s, 42, 1, onChange, ['x・y は Shot 内の座標' ...
                '（markXmm・markYmm、Shot 中心から）。係数は Shot ごとに求めます。' formulaHelp]);
            c.overlayHelp = label(s, '', [40, 42], 2);
            c.overlayHelp.FontColor = app.Palette.muted;
            c.overlayHelp.UserData = "muted";
            c.overlayFormulaError = errorLabel(app, s, 43, [1, 2]);

            methodPanel = uipanel(grid, 'Title', '比べる手法');
            m = uigridlayout(methodPanel, [29, 4], 'RowHeight', repmat({'fit'}, 1, 29), 'ColumnWidth', {'1x', '1x', '1x', '1x'}, ...
                'Padding', 10, 'RowSpacing', 6, 'Scrollable', 'on');
            presetGrid = uigridlayout(m, [1, 4], 'Padding', 0, 'ColumnWidth', {'fit', 'fit', 'fit', 'fit'});
            place(presetGrid, 1, [1, 4]);
            uibutton(presetGrid, 'Text', '初期設定', 'ButtonPushedFcn', @(~, ~) app.onPreset("default"), ...
                'Tooltip', 'アプリの初期設定の手法（ガウス過程回帰だけ）に戻します。');
            uibutton(presetGrid, 'Text', '推奨の組み合わせ', 'ButtonPushedFcn', @(~, ~) app.onPreset("recommended"), ...
                'Tooltip', ['前回の模擬データの評価で各系統の代表になった手法（GPR・TPS・Kriging・GAM・XY 5次多項式・' ...
                'RT モデル）を選びます。']);
            uibutton(presetGrid, 'Text', 'すべて選ぶ', 'ButtonPushedFcn', @(~, ~) app.onPreset("all"));
            uibutton(presetGrid, 'Text', 'すべて外す', 'ButtonPushedFcn', @(~, ~) app.onPreset("none"));
            label(m, '説明変数', 2, [1, 4]);
            c.featureXY = uicheckbox(m, 'Text', 'X, Y', 'ValueChangedFcn', onChange);
            place(c.featureXY, 3, 1);
            c.featureXYR = uicheckbox(m, 'Text', 'X, Y, 半径', 'ValueChangedFcn', onChange);
            place(c.featureXYR, 3, 2);
            factorGrid = uigridlayout(m, [6, 5], 'Padding', 0, 'RowSpacing', 4, ...
                'RowHeight', {'fit', 'fit', 'fit', 'fit', 72, 'fit'}, 'ColumnWidth', {'fit', 'fit', 'fit', 'fit', '1x'});
            place(factorGrid, 4, [1, 4]);
            label(factorGrid, '質的変数', 1, [1, 5]);
            label(factorGrid, 'X 成分', 2, 1);
            c.factorScan = uicheckbox(factorGrid, 'Text', 'Scan 方向', 'ValueChangedFcn', onChange, ...
                'Tooltip', 'Direction の列、または「Scan 方向が無い行に付ける値」で付けた値。値が無い Wafer では使いません。');
            place(c.factorScan, 2, 2);
            c.factorMark = uicheckbox(factorGrid, 'Text', 'Mark 番号', 'ValueChangedFcn', onChange);
            place(c.factorMark, 2, 3);
            rowTooltip = '各 Wafer・測定日時で、入力の Shot 中心 Y 座標を上から1行目として数えます。半径除外前に判定。入力にない行は数えません。';
            c.shotRowParity = uicheckbox(factorGrid, 'Text', 'Shot 行の奇数・偶数', 'Tooltip', rowTooltip, ...
                'ValueChangedFcn', onChange);
            place(c.shotRowParity, 2, 4);
            c.factorSeparate = uicheckbox(factorGrid, 'Text', 'Y 成分は別に選ぶ', 'ValueChangedFcn', onChange, ...
                'Tooltip', 'オフなら Y 成分も X 成分と同じ質的変数を使います。オンにすると下の行で Y 成分の質的変数を選べます。');
            place(c.factorSeparate, 2, 5);
            label(factorGrid, 'Y 成分', 3, 1);
            c.factorScanY = uicheckbox(factorGrid, 'Text', 'Scan 方向', 'ValueChangedFcn', onChange);
            place(c.factorScanY, 3, 2);
            c.factorMarkY = uicheckbox(factorGrid, 'Text', 'Mark 番号', 'ValueChangedFcn', onChange);
            place(c.factorMarkY, 3, 3);
            c.shotRowParityY = uicheckbox(factorGrid, 'Text', 'Shot 行の奇数・偶数', 'Tooltip', rowTooltip, ...
                'ValueChangedFcn', onChange);
            place(c.shotRowParityY, 3, 4);
            columnsTooltip = ['選んだ列の値（文字・数字）を水準とする質的変数。値が空の Mark がある Wafer では、その列を使いません。' ...
                '一覧はデータを読み込むと出ます。'];
            c.factorColumnsLabel = label(factorGrid, 'その他の列：X 成分', ...
                4, [1, 4]);
            label(factorGrid, 'その他の列：Y 成分', 4, 5);
            c.factorColumns = uilistbox(factorGrid, 'Items', {}, 'Multiselect', 'on', 'ValueChangedFcn', onChange, ...
                'Tooltip', columnsTooltip);
            place(c.factorColumns, 5, [1, 4]);
            c.factorColumnsY = uilistbox(factorGrid, 'Items', {}, 'Multiselect', 'on', 'ValueChangedFcn', onChange, ...
                'Tooltip', columnsTooltip);
            place(c.factorColumnsY, 5, 5);
            c.factorSingles = uicheckbox(factorGrid, 'Text', 'チェックした質的変数を1つだけ使う手法も比べる', ...
                'ValueChangedFcn', onChange, 'Tooltip', ...
                ['オンにすると、質的変数を使う手法（GPR の質的変数あり・Backfitting・GAM など）ごとに、チェックした変数を' ...
                '1つだけ使う手法を足して評価します（手法の名前の最後に「質的変数：○○だけ」）。チェックした変数が2つ以上の' ...
                'ときだけ足します。手法の数が増えるので、評価の時間も増えます。']);
            place(c.factorSingles, 6, [1, 5]);
            c.factorColumnsError = errorLabel(app, m, 5, [1, 4]);
            % 手法は 基底関数系（XY 多項式・Fringe Zernike・RBF・RT モデル）・平滑化系・確率過程系 に分けて並べる
            methodHeadings = ["基底関数系", "平滑化系", "確率過程系"];
            methodHeadingRows = [6, 11, 16];
            for k = 1:numel(methodHeadings)
                groupHeading = label(m, methodHeadings(k), methodHeadingRows(k), [1, 4]);
                groupHeading.FontWeight = 'bold';
            end
            c.gpr = uicheckbox(m, 'Text', 'GPR', 'ValueChangedFcn', onChange);
            place(c.gpr, 17, [1, 4]);
            label(m, 'カーネル', 18, [1, 2]);
            label(m, '質的変数の扱い', 18, [3, 4]);
            [kernelNames, kernelLabels] = alignest.models.gprKernelChoices();
            c.kernels = uilistbox(m, 'Items', cellstr(kernelLabels), 'ItemsData', cellstr(kernelNames), 'Multiselect', 'on', ...
                'ValueChangedFcn', onChange, 'Tooltip', ['periodic（周期）：説明変数ごとに、周期 p で同じ形をくり返す' ...
                'カーネル（p も長さスケールと一緒に推定する）。ardperiodic は長さスケールが説明変数ごと。式は「ヘルプ」。']);
            place(c.kernels, 19, [1, 2]);
            [modeNames, modeLabels] = alignest.models.gprFactorModes();
            modeLabels = plainLabels(modeLabels);
            modeGrid = uigridlayout(m, [numel(modeNames), 1], 'Padding', 0, 'RowSpacing', 2, ...
                'RowHeight', repmat({'fit'}, 1, numel(modeNames)));
            place(modeGrid, 19, [3, 4]);
            c.factorModes = gobjects(1, numel(modeNames));
            for k = 1:numel(modeNames)
                c.factorModes(k) = uicheckbox(modeGrid, 'Text', modeLabels(k), 'UserData', modeNames(k), ...
                    'ValueChangedFcn', onChange);
            end
            m.RowHeight{19} = 300;
            label(m, 'Matérn の ν', 20, [1, 2]);
            c.maternNu = uieditfield(m, 'text', 'ValueChangedFcn', onChange, 'Tooltip', ['Matérn カーネルの次数 ν' ...
                '（0 より大きく 50 以下）。大きいほど滑らか。0.5・1.5・2.5 は exponential・matern32・matern52 と同じ。' ...
                '複数入れると ν ごとに比べます（例：0.75 1 2 3.5）。']);
            place(c.maternNu, 20, [3, 4]);
            c.maternNuError = errorLabel(app, m, 21, [1, 4]);
            c.tps = uicheckbox(m, 'Text', 'TPS', 'ValueChangedFcn', onChange);
            place(c.tps, 12, [1, 2]);
            c.tpsFactors = spatialFactorDropdown(m, onChange);
            place(c.tpsFactors, 12, [3, 4]);
            smoothingGrid = uigridlayout(m, [1, 6], 'ColumnWidth', {'fit', 'fit', 'fit', 'fit', 70, '1x'}, 'Padding', 0);
            place(smoothingGrid, 13, [1, 4]);
            label(smoothingGrid, '平滑化', 1, 1);
            c.tpsSmoothing = [ ...
                uicheckbox(smoothingGrid, 'Text', 'GCV で選ぶ', 'UserData', "gcv", 'ValueChangedFcn', onChange), ...
                uicheckbox(smoothingGrid, 'Text', 'なし', 'UserData', "none", 'ValueChangedFcn', onChange, ...
                'Tooltip', '学習点を通る曲面（補間）にします。'), ...
                uicheckbox(smoothingGrid, 'Text', 'log10 λ を指定', 'UserData', "fixed", 'ValueChangedFcn', onChange)];
            for k = 1:numel(c.tpsSmoothing)
                place(c.tpsSmoothing(k), 1, 1 + k);
            end
            c.tpsLog10Lambda = uieditfield(smoothingGrid, 'numeric', 'ValueChangedFcn', onChange, 'Tooltip', ...
                'λ の常用対数。大きいほど滑らかです。');
            place(c.tpsLog10Lambda, 1, 5);
            c.rbf = uicheckbox(m, 'Text', 'RBF', 'ValueChangedFcn', onChange);
            place(c.rbf, 9, [1, 2]);
            c.rbfFactors = spatialFactorDropdown(m, onChange);
            place(c.rbfFactors, 9, [3, 4]);
            c.ordinaryKriging = uicheckbox(m, 'Text', 'Kriging', 'ValueChangedFcn', onChange);
            place(c.ordinaryKriging, 22, [1, 2]);
            c.ordinaryFactors = spatialFactorDropdown(m, onChange);
            place(c.ordinaryFactors, 22, [3, 4]);
            c.universalKriging = uicheckbox(m, 'Text', 'Universal Kriging', 'ValueChangedFcn', onChange);
            place(c.universalKriging, 23, [1, 2]);
            c.universalFactors = spatialFactorDropdown(m, onChange);
            place(c.universalFactors, 23, [3, 4]);
            label(m, 'バリオグラム', 24, [1, 4]);
            variograms = ["linear", "gaussian", "power", "exponential", "spherical"];
            variogramGrid = uigridlayout(m, [1, numel(variograms)], 'Padding', 0, ...
                'ColumnWidth', repmat({'1x'}, 1, numel(variograms)));
            place(variogramGrid, 25, [1, 4]);
            c.variograms = gobjects(1, numel(variograms));
            for k = 1:numel(variograms)
                c.variograms(k) = uicheckbox(variogramGrid, 'Text', variograms(k), 'UserData', variograms(k), ...
                    'ValueChangedFcn', onChange);
            end
            c.variograms(end).Tooltip = '球形モデル（range より遠い点の相関は 0）。説明変数（X,Y・X,Y,半径）は3次元までなので正定値が保証されます。';
            c.gam = uicheckbox(m, 'Text', 'GAM', 'ValueChangedFcn', onChange);
            place(c.gam, 14, [1, 2]);
            c.gamFactors = uidropdown(m, 'Items', {'質的変数あり', '質的変数なし', 'あり・なしを比較'}, ...
                'ItemsData', {'factor', 'none', 'both'}, 'ValueChangedFcn', onChange, 'Tooltip', ['上で選んだ質的変数を、' ...
                'GAM の項（効果コード。罰則なし）として一緒に推定するか。']);
            place(c.gamFactors, 14, [3, 4]);
            % 形状関数は項（X・Y、半径）ごとに1行、カーネルは2行に並べる（画面の幅が狭くても切れないように）
            [termNames, termLabels] = alignest.models.gamTerms("XYR");
            [gamKernelNames, gamKernelLabels] = alignest.models.gamKernelChoices();
            kernelColumns = 2;   % カーネルの名前が長いので2列（rationalquadratic が切れないように）
            nShapeRows = numel(termNames) + ceil(numel(gamKernelNames) / kernelColumns) + 1;
            shapeGrid = uigridlayout(m, [nShapeRows, kernelColumns + 1], 'Padding', 0, 'RowSpacing', 2, ...
                'ColumnWidth', [{'fit'}, repmat({'1x'}, 1, kernelColumns)], 'RowHeight', repmat({'fit'}, 1, nShapeRows));
            place(shapeGrid, 15, [1, 4]);
            shapeNames = ["spline", "gp"];
            shapeLabels = ["スプライン", "ガウス過程回帰"];
            c.gamShapeChecks = gobjects(numel(termNames), numel(shapeNames));
            for k = 1:numel(termNames)
                label(shapeGrid, "形状関数（" + termLabels(k) + "）：", k, 1);
                for j = 1:numel(shapeNames)
                    c.gamShapeChecks(k, j) = uicheckbox(shapeGrid, 'Text', shapeLabels(j), 'ValueChangedFcn', onChange, ...
                        'UserData', struct("term", termNames(k), "shape", shapeNames(j)), ...
                        'Tooltip', ['チェックした形状関数の組み合わせをすべて評価します（例：X・Y でスプラインとガウス過程回帰の' ...
                        '両方なら2通り）。スプライン：P-spline（B スプライン＋2階差分の罰則）。ガウス過程回帰：下で選んだカーネルの' ...
                        'ガウス過程（節点で近似、線形部分は罰則なし）。長さスケールは候補から REML で選び、罰則の強さは' ...
                        'どちらも REML で選びます。半径の項は説明変数が X,Y,半径 のときだけ使います。']);
                    place(c.gamShapeChecks(k, j), k, 1 + j);
                end
            end
            % ガウス過程回帰の形状関数のカーネル（チェックしたカーネルごとに比べる）
            kernelRow = numel(termNames) + 1;
            label(shapeGrid, 'ガウス過程回帰のカーネル：', kernelRow, 1);
            c.gamKernelChecks = gobjects(1, numel(gamKernelNames));
            for k = 1:numel(gamKernelNames)
                c.gamKernelChecks(k) = uicheckbox(shapeGrid, 'Text', gamKernelLabels(k), 'UserData', gamKernelNames(k), ...
                    'ValueChangedFcn', onChange, 'Tooltip', ['形状関数をガウス過程回帰にした項で使うカーネル（等方。' ...
                    '式は GPR と同じ）。チェックしたカーネルごとに評価します。rationalquadratic の α は 1 に固定します。']);
                place(c.gamKernelChecks(k), kernelRow + floor((k - 1) / kernelColumns), 2 + mod(k - 1, kernelColumns));
            end
            nuGrid = uigridlayout(shapeGrid, [1, 2], 'ColumnWidth', {'fit', 120}, 'Padding', 0);
            kernelRows = ceil(numel(gamKernelNames) / kernelColumns);
            place(nuGrid, kernelRow + kernelRows, [1, kernelColumns + 1]);
            label(nuGrid, 'matern の ν =', 1, 1);
            c.gamMaternNu = uieditfield(nuGrid, 'text', 'ValueChangedFcn', onChange, 'Tooltip', ['matern' ...
                'の ν。空白で区切ると ν ごとに比べます（例：1 2.5）。']);
            place(c.gamMaternNu, 1, 2);
            c.polynomial = uicheckbox(m, 'Text', 'XY 多項式　次数：', 'ValueChangedFcn', onChange);
            place(c.polynomial, 7, 1);
            c.polynomialOrder = uispinner(m, 'Limits', [1, 8], 'RoundFractionalValues', 'on', 'ValueChangedFcn', onChange);
            place(c.polynomialOrder, 7, 2);
            c.rt = uicheckbox(m, 'Text', 'RT モデル　次数 K：', 'ValueChangedFcn', onChange);
            place(c.rt, 10, 1);
            c.rtOrders = uieditfield(m, 'text', 'ValueChangedFcn', onChange);
            place(c.rtOrders, 10, 2);
            c.zernike = uicheckbox(m, 'Text', 'Fringe Zernike', 'ValueChangedFcn', onChange, ...
                'Tooltip', ['Fringe Zernike 多項式（Z1〜Z(k+1)²）の最小二乗。k = 3：Z1〜Z16、4：Z1〜Z25、5：Z1〜Z36、' ...
                '6：Z1〜Z49、7：Z1〜Z64（次数は 1〜7）。' ...
                '空白で区切ると次数ごとに比べます。式は「ヘルプ」。']);
            place(c.zernike, 8, 1);
            c.zernikeOrders = uieditfield(m, 'text', 'ValueChangedFcn', onChange, 'Tooltip', ...
                '次数 k（空白区切りで複数）。Z1〜Z(k+1)² を使う（k = 4 で Z25 まで）。');
            place(c.zernikeOrders, 8, 2);
            c.zernikeFactors = spatialFactorDropdown(m, onChange);
            c.zernikeFactors.Tooltip = ['質的変数（上で選んだ Scan 方向・Mark 番号など）を Backfitting で足すか。' ...
                'Backfitting：Zernike の当てはめと質的変数の効果を交互に推定します（TPS などと同じ）。'];
            place(c.zernikeFactors, 8, [3, 4]);
            c.rtError = errorLabel(app, m, 27, [1, 4]);
            c.zernikeError = errorLabel(app, m, 28, [1, 4]);
            c.gamShapeError = errorLabel(app, m, 29, [1, 4]);

            footer = uigridlayout(grid, [1, 4], 'ColumnWidth', {'fit', 'fit', 'fit', '1x'}, 'Padding', 0);
            place(footer, 2, [1, 2]);
            uibutton(footer, 'Text', '設定を保存…', 'ButtonPushedFcn', @(~, ~) app.onSaveSettings());
            uibutton(footer, 'Text', '設定を読み込む…', 'ButtonPushedFcn', @(~, ~) app.onLoadSettings());
            uibutton(footer, 'Text', '初期設定に戻す', 'ButtonPushedFcn', @(~, ~) app.setSettings(alignest.siteDefaults()), ...
                'Tooltip', ['アプリの初期設定に戻します（今のフォルダに既定の設定ファイル alignment_estimation_defaults.json が' ...
                'あれば、その値）。']);
            c.countLabel = uilabel(footer, 'WordWrap', 'on', 'Text', '');
            app.Controls = mergeStruct(app.Controls, c);
        end

        function settingsToControls(app)
            c = app.Controls;
            s = app.Settings;
            c.validRadius.Value = s.data.validRadiusMm;
            c.excludeZeroMeasurements.Value = s.data.excludeZeroMeasurements;
            c.excludeUnmeasuredRecords.Value = s.data.excludeUnmeasuredRecords;
            c.dataExcludeOutliers.Value = logical(fieldOr(s.data, "excludeOutliers", false));
            c.dataOutlierSigma.Value = double(fieldOr(s.data, "outlierSigma", 3));
            c.dataOutlierSigma.Enable = onOff(c.dataExcludeOutliers.Value);
            c.directionRule.Value = char(s.data.directionRule);
            c.invertDirection.Value = s.data.invertDirection;
            c.invertDirection.Enable = onOff(s.data.directionRule ~= "none");
            c.coordinateMode.Value = char(fieldOr(s.data, "coordinateMode", "shotMark"));
            c.valueUnit.Value = char(fieldOr(s.data, "valueUnit", "nm"));
            refreshValueColumns(app);
            fillUnitTable(app);
            choice = alignest.factorChoice(s, "X");
            c.factorScan.Value = choice.scan;
            c.factorMark.Value = choice.mark;
            c.shotRowParity.Value = choice.row;
            choiceY = alignest.factorChoice(s, "Y");   % 別に選ばないときは X と同じ（画面にもそのまま出す）
            c.factorSeparate.Value = isfield(s.factors, "separateY") && s.factors.separateY;
            c.factorSingles.Value = isfield(s.factors, "evaluateSingles") && s.factors.evaluateSingles;
            refreshScanMenu(app);   % 「設定」→「Scan 方向の向きと色」（設定 display）
            c.factorScanY.Value = choiceY.scan;
            c.factorMarkY.Value = choiceY.mark;
            c.shotRowParityY.Value = choiceY.row;
            refreshFactorColumns(app, choice.columns, choiceY.columns);
            c.samplingMethod.Value = cellstr(s.sampling.method(:).');
            c.markPerShot.Value = char(strjoin(string(fieldOr(s.sampling, "markPerShot", 1)), " "));
            balance = "none";
            if logical(fieldOr(s.sampling.constraints, "markEqual", false))
                balance = "equal";
            elseif logical(fieldOr(s.sampling.constraints, "markRatio", true))
                balance = "ratio";
            end
            c.markBalance.Value = char(balance);
            c.markRequirePerShot.Value = logical(fieldOr(s.sampling, "markRequirePerShot", true));
            c.markMinPerShot.Value = double(fieldOr(s.sampling, "markMinPerShot", 1));
            c.nShotsStart.Value = s.sampling.nShotsStart;
            c.nShotsEnd.Value = s.sampling.nShotsEnd;
            c.nShotsStep.Value = s.sampling.nShotsStep;
            c.countBy.Value = char(s.sampling.countBy);
            c.rateStart.Value = s.sampling.rateStart;
            c.rateEnd.Value = s.sampling.rateEnd;
            c.rateStep.Value = s.sampling.rateStep;
            c.requiredShots.Value = char(strjoin(string(s.sampling.requiredShots), " "));
            c.excludedShots.Value = char(strjoin(string(fieldOr(s.sampling, "excludedShots", zeros(1, 0))), " "));
            c.requiredMarks.Value = char(strjoin(string(fieldOr(s.sampling, "requiredMarks", strings(1, 0))), " "));
            c.excludedMarks.Value = char(strjoin(string(fieldOr(s.sampling, "excludedMarks", strings(1, 0))), " "));
            c.markCountBy.Value = char(fieldOr(s.sampling, "markCountBy", "perShot"));
            c.markCountStart.Value = double(fieldOr(s.sampling, "markCountStart", 100));
            c.markCountEnd.Value = double(fieldOr(s.sampling, "markCountEnd", 300));
            c.markCountStep.Value = double(fieldOr(s.sampling, "markCountStep", 50));
            c.requireOuter.Value = s.sampling.requireOuterShots;
            c.randomRepeats.Value = s.sampling.randomRepeats;
            refreshSeedMenu(app);   % 「設定」→「乱数の種…」（設定 sampling.seed）
            c.layoutPlanInfo.Value = cellstr(layoutText(s.sampling));
            c.zoneEdges.Value = char(strjoin(string(s.sampling.constraints.radialZoneEdgesMm), " "));
            c.quadrants.Value = s.sampling.constraints.quadrants;
            c.scanConstraint.Value = s.sampling.constraints.scanDirection;
            c.slack.Value = s.sampling.constraints.slack;
            c.designOrder.Value = s.sampling.designOrder;
            c.exchangeStarts.Value = s.sampling.exchangeStarts;
            c.outerRadius.Value = s.evaluation.outerRadiusMm;
            c.removeLinear.Value = s.evaluation.removeLinear;
            c.recordTiming.Value = s.evaluation.recordTiming;
            c.excludeOutliers.Value = s.evaluation.excludeOutliers;
            c.outlierSigma.Value = s.evaluation.outlierSigma;
            c.outlierMethod.Value = char(alignest.outlierMethod(s));
            % 式は画面に出してから確かめる（読めない式でも設定を読み込めるように、ここでは式を読まない）
            rawOverlay = fieldOr(s, "overlay", struct());
            defaultOverlay = alignest.defaultSettings().overlay;
            plain = s;
            plain.overlay = rawOverlay;
            plain.overlay.waferUseFormula = false;
            if string(fieldOr(rawOverlay, "shotCommon", "none")) == "formula"
                plain.overlay.shotCommon = "none";
            end
            if string(fieldOr(rawOverlay, "perShot", "none")) == "formula"
                plain.overlay.perShot = "none";
            end
            overlay = alignest.overlayChoice(plain);
            useWaferFormula = logical(fieldOr(rawOverlay, "waferUseFormula", false));
            c.overlayWafer.Value = ternary(useWaferFormula, app.FORMULA_CHOICE, overlay.waferOrder);
            % 画面で選べる Shot 共通成分は「なし」「1次」「式を入力」（以前の設定のメーカー別の高次式は 1次にする）
            shotCommon = string(fieldOr(rawOverlay, "shotCommon", overlay.shotCommon));
            if ~any(shotCommon == ["none", "linear", "formula"])
                shotCommon = "linear";
            end
            c.overlayShotCommon.Value = char(shotCommon);
            c.overlayPerShot.Value = char(string(fieldOr(rawOverlay, "perShot", overlay.perShot)));
            perShotFormula = fieldOr(rawOverlay, "perShotFormula", defaultOverlay.perShotFormula);
            c.overlayPerShotDx.Value = char(perShotFormula.dx);
            c.overlayPerShotDy.Value = char(perShotFormula.dy);
            waferFormula = fieldOr(rawOverlay, "waferFormula", defaultOverlay.waferFormula);
            shotFormula = fieldOr(rawOverlay, "shotFormula", defaultOverlay.shotFormula);
            c.overlayWaferDx.Value = char(waferFormula.dx);
            c.overlayWaferDy.Value = char(waferFormula.dy);
            c.overlayShotDx.Value = char(shotFormula.dx);
            c.overlayShotDy.Value = char(shotFormula.dy);
            methods = s.methods;
            c.featureXY.Value = any(methods.featureSets == "XY");
            c.featureXYR.Value = any(methods.featureSets == "XYR");
            c.gpr.Value = methods.gpr.enabled;
            c.kernels.Value = cellstr(methods.gpr.kernels);
            c.maternNu.Value = char(strjoin(string(methods.gpr.maternNu), " "));
            for check = reshape(c.gamShapeChecks, 1, [])
                chosen = "spline";
                if isfield(methods.gam.shapes, check.UserData.term)
                    chosen = string(methods.gam.shapes.(check.UserData.term));
                end
                check.Value = any(chosen == check.UserData.shape);
            end
            for check = c.gamKernelChecks
                check.Value = any(string(methods.gam.gpKernels) == check.UserData);
            end
            c.gamMaternNu.Value = char(strjoin(string(methods.gam.gpMaternNu), " "));
            for k = 1:numel(c.factorModes)
                c.factorModes(k).Value = any(methods.gpr.factorModes == c.factorModes(k).UserData);
            end
            c.tps.Value = methods.tps.enabled;
            for k = 1:numel(c.tpsSmoothing)
                c.tpsSmoothing(k).Value = any(string(methods.tps.smoothing) == c.tpsSmoothing(k).UserData);
            end
            c.tpsLog10Lambda.Value = methods.tps.log10Lambda;
            c.rbf.Value = methods.rbf.enabled;
            c.rbfFactors.Value = modeSelection(methods.rbf.factorModes);
            c.tpsFactors.Value = modeSelection(methods.tps.factorModes);
            c.ordinaryFactors.Value = modeSelection(methods.kriging.ordinaryFactorModes);
            c.universalFactors.Value = modeSelection(methods.kriging.universalFactorModes);
            c.ordinaryKriging.Value = methods.kriging.ordinary;
            c.universalKriging.Value = methods.kriging.universal;
            for k = 1:numel(c.variograms)
                c.variograms(k).Value = any(methods.kriging.variograms == c.variograms(k).UserData);
            end
            c.gam.Value = methods.gam.enabled;
            c.gamFactors.Value = gamFactorSelection(fieldOr(methods.gam, "factorModes", "factor"));
            c.polynomial.Value = methods.polynomial.enabled;
            c.polynomialOrder.Value = methods.polynomial.order;
            c.rt.Value = methods.rt.enabled;
            c.rtOrders.Value = char(strjoin(string(methods.rt.orders), " "));
            c.zernike.Value = methods.zernike.enabled;
            c.zernikeFactors.Value = modeSelection(methods.zernike.factorModes);
            c.zernikeOrders.Value = char(strjoin(string(methods.zernike.orders), " "));
            validateSettings(app);
            updateEnabled(app);
            highOrderSettingsToControls(app);   % 「7. Shot高次補正」の欄（設定ファイルの highOrder）
            markLayoutSettingsToControls(app);  % 「8. Mark配置の最適化」の欄（設定ファイルの markLayout）
        end

        function controlsToSettings(app)
            % 画面の値を設定に移す。数字の欄が正しくないときは前の値のまま（欄の下に理由を出す）
            c = app.Controls;
            s = app.Settings;
            s.data.validRadiusMm = c.validRadius.Value;
            s.data.coordinateUnits = currentCoordinateUnits(app);
            s.data.excludeZeroMeasurements = c.excludeZeroMeasurements.Value;
            s.data.excludeUnmeasuredRecords = c.excludeUnmeasuredRecords.Value;
            s.data.excludeOutliers = c.dataExcludeOutliers.Value;
            s.data.outlierSigma = c.dataOutlierSigma.Value;
            s.data.directionRule = string(c.directionRule.Value);
            s.data.invertDirection = c.invertDirection.Value;
            s.factors.scan = c.factorScan.Value;
            s.factors.mark = c.factorMark.Value;
            s.factors.shotRowParity = c.shotRowParity.Value;
            s.factors.columns = reshape(string(c.factorColumns.Value), 1, []);
            s.factors.separateY = c.factorSeparate.Value;
            s.factors.evaluateSingles = c.factorSingles.Value;
            if ~s.factors.separateY
                % 別に選ばないときは、Y 成分の欄を X 成分と同じにしておく（オンにしたときの初めの値）
                c.factorScanY.Value = c.factorScan.Value;
                c.factorMarkY.Value = c.factorMark.Value;
                c.shotRowParityY.Value = c.shotRowParity.Value;
                c.factorColumnsY.Value = c.factorColumns.Value;
            end
            s.factors.y.scan = c.factorScanY.Value;
            s.factors.y.mark = c.factorMarkY.Value;
            s.factors.y.shotRowParity = c.shotRowParityY.Value;
            s.factors.y.columns = reshape(string(c.factorColumnsY.Value), 1, []);
            if ~isempty(c.samplingMethod.Value)
                s.sampling.method = reshape(string(c.samplingMethod.Value), 1, []);   % 空のときは前の値のまま（欄の下に理由）
            end
            [values, ok] = parseNumbers(c.markPerShot.Value);
            if ok && ~isempty(values) && all(values > 0)
                s.sampling.markPerShot = unique(values);
            end
            s.sampling.constraints.markRatio = string(c.markBalance.Value) ~= "none";
            s.sampling.constraints.markEqual = string(c.markBalance.Value) == "equal";
            s.sampling.markRequirePerShot = c.markRequirePerShot.Value;
            s.sampling.markMinPerShot = c.markMinPerShot.Value;
            try
                s.sampling.nShots = alignest.shotCountList(c.nShotsStart.Value, c.nShotsEnd.Value, c.nShotsStep.Value);
                s.sampling.nShotsStart = c.nShotsStart.Value;
                s.sampling.nShotsEnd = c.nShotsEnd.Value;
                s.sampling.nShotsStep = c.nShotsStep.Value;
            catch
                % 正しくない組み合わせのときは前の値のまま（欄の下に理由を出す）
            end
            s.sampling.countBy = string(c.countBy.Value);
            try
                alignest.measurementRateList(c.rateStart.Value, c.rateEnd.Value, c.rateStep.Value);
                s.sampling.rateStart = c.rateStart.Value;
                s.sampling.rateEnd = c.rateEnd.Value;
                s.sampling.rateStep = c.rateStep.Value;
            catch
                % 正しくない組み合わせのときは前の値のまま（欄の下に理由を出す）
            end
            [values, ok] = parseNumbers(c.requiredShots.Value);
            if ok && all(values == round(values))
                s.sampling.requiredShots = unique(values);
            end
            s.sampling.requireOuterShots = c.requireOuter.Value;
            [values, ok] = parseNumbers(c.excludedShots.Value);
            if ok && all(values == round(values))
                s.sampling.excludedShots = reshape(unique(values), 1, []);
            end
            [keys, ok] = parseMarkText(c.requiredMarks.Value);
            if ok
                s.sampling.requiredMarks = keys;
            end
            [keys, ok] = parseMarkText(c.excludedMarks.Value);
            if ok
                s.sampling.excludedMarks = keys;
            end
            s.sampling.markCountBy = string(c.markCountBy.Value);
            s.sampling.markCountStart = c.markCountStart.Value;
            s.sampling.markCountEnd = c.markCountEnd.Value;
            s.sampling.markCountStep = c.markCountStep.Value;
            s.sampling.randomRepeats = c.randomRepeats.Value;
            [values, ok] = parseNumbers(c.zoneEdges.Value);
            if ok && all(values > 0 & values < s.data.waferRadiusMm)
                s.sampling.constraints.radialZoneEdgesMm = unique(values);
            end
            s.sampling.constraints.quadrants = c.quadrants.Value;
            s.sampling.constraints.scanDirection = c.scanConstraint.Value;
            s.sampling.constraints.slack = c.slack.Value;
            s.sampling.designOrder = c.designOrder.Value;
            s.sampling.exchangeStarts = c.exchangeStarts.Value;
            s.evaluation.outerRadiusMm = c.outerRadius.Value;
            s.evaluation.removeLinear = c.removeLinear.Value;
            s.evaluation.excludeOutliers = c.excludeOutliers.Value;
            s.evaluation.outlierSigma = c.outlierSigma.Value;
            s.evaluation.outlierMethod = string(c.outlierMethod.Value);
            s.evaluation.recordTiming = c.recordTiming.Value;
            s.overlay.waferUseFormula = c.overlayWafer.Value == app.FORMULA_CHOICE;
            if ~s.overlay.waferUseFormula
                s.overlay.waferOrder = c.overlayWafer.Value;
            end
            s.overlay.shotCommon = string(c.overlayShotCommon.Value);
            s.overlay.perShot = string(c.overlayPerShot.Value);
            s.overlay.waferFormula = struct("dx", string(c.overlayWaferDx.Value), "dy", string(c.overlayWaferDy.Value));
            s.overlay.shotFormula = struct("dx", string(c.overlayShotDx.Value), "dy", string(c.overlayShotDy.Value));
            s.overlay.perShotFormula = struct("dx", string(c.overlayPerShotDx.Value), "dy", string(c.overlayPerShotDy.Value));
            featureNames = ["XY", "XYR"];
            s.methods.featureSets = featureNames([c.featureXY.Value, c.featureXYR.Value]);
            s.methods.gpr.enabled = c.gpr.Value;
            s.methods.gpr.kernels = string(c.kernels.Value);
            [values, ok] = parseNumbers(c.maternNu.Value);
            if ok && ~isempty(values) && all(values > 0 & values <= app.MAX_MATERN_NU)
                s.methods.gpr.maternNu = unique(values, 'stable');
            end
            for k = 1:size(c.gamShapeChecks, 1)
                checks = c.gamShapeChecks(k, :);
                chosen = strings(1, 0);
                for check = checks([checks.Value])
                    chosen(end + 1) = check.UserData.shape; %#ok<AGROW>
                end
                s.methods.gam.shapes.(checks(1).UserData.term) = chosen;
            end
            s.methods.gam.gpKernels = checkedValues(c.gamKernelChecks);
            [values, ok] = parseNumbers(c.gamMaternNu.Value);
            if ok && ~isempty(values) && all(values > 0 & values <= app.MAX_MATERN_NU)
                s.methods.gam.gpMaternNu = unique(values, 'stable');
            end
            s.methods.gpr.factorModes = checkedValues(c.factorModes);
            s.methods.tps.enabled = c.tps.Value;
            s.methods.tps.smoothing = checkedValues(c.tpsSmoothing);
            s.methods.tps.log10Lambda = c.tpsLog10Lambda.Value;
            s.methods.rbf.enabled = c.rbf.Value;
            s.methods.rbf.factorModes = selectedModes(c.rbfFactors.Value);
            s.methods.tps.factorModes = selectedModes(c.tpsFactors.Value);
            s.methods.kriging.ordinaryFactorModes = selectedModes(c.ordinaryFactors.Value);
            s.methods.kriging.universalFactorModes = selectedModes(c.universalFactors.Value);
            s.methods.kriging.ordinary = c.ordinaryKriging.Value;
            s.methods.kriging.universal = c.universalKriging.Value;
            s.methods.kriging.variograms = checkedValues(c.variograms);
            s.methods.gam.enabled = c.gam.Value;
            s.methods.gam.factorModes = ternary(string(c.gamFactors.Value) == "both", ["factor", "none"], ...
                string(c.gamFactors.Value));
            s.methods.polynomial.enabled = c.polynomial.Value;
            s.methods.polynomial.order = c.polynomialOrder.Value;
            s.methods.rt.enabled = c.rt.Value;
            [values, ok] = parseNumbers(c.rtOrders.Value);
            if ok && ~isempty(values) && all(values >= 1 & values <= 10 & values == round(values))
                s.methods.rt.orders = unique(values);
            end
            s.methods.zernike.enabled = c.zernike.Value;
            s.methods.zernike.factorModes = selectedModes(c.zernikeFactors.Value);
            [values, ok] = parseNumbers(c.zernikeOrders.Value);
            if ok && ~isempty(values) && all(values >= 1 & values <= app.MAX_ZERNIKE_ORDER & values == round(values))
                s.methods.zernike.orders = unique(values);
            end
            app.Settings = s;
        end

        function messages = validateSettings(app)
            % 入力欄ごとに確かめ、欄の下に理由を出す（色だけでなく「⚠」と文で示す）
            c = app.Controls;
            messages = strings(0, 1);
            method = string(c.samplingMethod.Value);
            text = "";
            listText = "";
            try
                if string(c.countBy.Value) == "rate"
                    rates = alignest.measurementRateList(c.rateStart.Value, c.rateEnd.Value, c.rateStep.Value);
                    listText = "→ 計測率：" + previewList(rates, app.LIST_PREVIEW_COUNT) + sprintf(" %%（%d 通り）", ...
                        numel(rates)) + rateExample(app, rates);
                else
                    counts = alignest.shotCountList(c.nShotsStart.Value, c.nShotsEnd.Value, c.nShotsStep.Value);
                    listText = "→ 学習 Shot 数：" + previewList(counts, app.LIST_PREVIEW_COUNT) + ...
                        sprintf("（%d 通り）", numel(counts));
                end
            catch err
                usesCounts = any(ismember(method, ["ioptimal", "doptimal", "random"])) || ...
                    (any(method == "excel") && hasPriorityPlans(app.Settings.sampling)) || ...
                    (any(ismember(method, ["mark", "markd"])) && string(c.countBy.Value) == "rate");
                if usesCounts
                    text = "⚠ " + string(err.message);
                end
            end
            if isempty(method)
                text = "⚠ 学習 Shot の選び方を1つ以上選んでください。";
            end
            c.nShotsList.Text = listText;
            c.nShotsError.Text = text;
            messages = [messages; text(text ~= "")];
            text = "";
            if any(method == "excel")
                try
                    if isempty(alignest.parseLayoutPlans(app.Settings.sampling.layoutPlans))
                        text = "⚠ 「Excel ファイルを読み込む…」で、学習に使う Shot・Mark を指定したファイルを読み込んでください。";
                    end
                catch err
                    text = "⚠ " + string(err.message);
                end
            end
            c.layoutPlanError.Text = text;
            messages = [messages; text(text ~= "")];
            [values, ok] = parseNumbers(c.requiredShots.Value);
            text = "";
            if any(ismember(method, ["ioptimal", "doptimal", "random", "mark", "markd"])) && (~ok || any(values ~= round(values)))
                text = "⚠ 必ず計測する shotNo は整数を空白またはカンマで区切って入れてください（使わないなら空欄）。";
            end
            [values, ok] = parseNumbers(c.excludedShots.Value);
            if ~ok || any(values ~= round(values))
                text = strtrim(text + " ⚠ 計測しない shotNo は整数を空白またはカンマで区切って入れてください（使わないなら空欄）。");
            end
            [~, okRequired] = parseMarkText(c.requiredMarks.Value);
            [~, okExcluded] = parseMarkText(c.excludedMarks.Value);
            if ~okRequired || ~okExcluded
                text = strtrim(text + " ⚠ Mark は「shotNo-markNo」（例：12-3）を空白で区切って入れてください（使わないなら空欄）。");
            end
            c.requiredError.Text = text;
            c.requiredInfo.Text = requiredText(app);
            messages = [messages; text(text ~= "")];
            [values, ok] = parseNumbers(c.zoneEdges.Value);
            text = "";
            radiusMm = app.Settings.data.waferRadiusMm;
            if ~ok || any(values <= 0 | values >= radiusMm)
                text = sprintf("⚠ 同心円の区切りは 0 より大きく %g mm より小さい半径 [mm] を空白で区切って入れてください" + ...
                    "（使わないなら空欄）。", radiusMm);
            end
            c.zoneError.Text = text;
            messages = [messages; text(text ~= "")];
            text = "";
            selectedColumns = string(c.factorColumns.Value);
            if c.factorSeparate.Value
                selectedColumns = unique([selectedColumns, string(c.factorColumnsY.Value)], 'stable');
            end
            missing = missingFactorColumns(app, selectedColumns);
            if ~isempty(missing)
                text = "⚠ 質的変数に選んだ列が、読み込んだデータにありません：" + strjoin(missing, "、") + ...
                    "。選び直すか、その列を含むファイルを読み込んでください。";
            end
            c.factorColumnsError.Text = text;
            messages = [messages; text(text ~= "")];
            [values, ok] = parseNumbers(c.maternNu.Value);
            text = "";
            if usesMaternNu(c) && (~ok || isempty(values) || any(values <= 0 | values > app.MAX_MATERN_NU))
                text = sprintf("⚠ Matérn の ν は 0 より大きく %g 以下の数を空白で区切って入れてください（例：0.75 1 2）。", ...
                    app.MAX_MATERN_NU);
            end
            c.maternNuError.Text = text;
            messages = [messages; text(text ~= "")];
            [values, ok] = parseNumbers(c.rtOrders.Value);
            text = "";
            if c.rt.Value && (~ok || isempty(values) || any(values < 1 | values > 10 | values ~= round(values)))
                text = "⚠ RT モデルの次数は 1〜10 の整数を空白で区切って入れてください（例：4 5）。";
            end
            c.rtError.Text = text;
            messages = [messages; text(text ~= "")];
            [values, ok] = parseNumbers(c.zernikeOrders.Value);
            text = "";
            if c.zernike.Value && (~ok || isempty(values) || any(values < 1 | values > app.MAX_ZERNIKE_ORDER | ...
                    values ~= round(values)))
                text = sprintf("⚠ Fringe Zernike の次数は 1〜%d の整数を空白で区切って入れてください（例：3 4）。", ...
                    app.MAX_ZERNIKE_ORDER);
            end
            c.zernikeError.Text = text;
            messages = [messages; text(text ~= "")];
            [values, ok] = parseNumbers(c.markPerShot.Value);
            text = "";
            byRate = string(c.countBy.Value) == "rate";
            byTotal = string(c.markCountBy.Value) == "total";
            if any(ismember(method, ["mark", "markd"])) && ~byRate && ~byTotal && (~ok || isempty(values) || any(values <= 0))
                text = "⚠ 1 Shot あたりの計測 Mark 数は 0 より大きい数を空白で区切って入れてください（例：1 1.5 2）。";
            elseif any(ismember(method, ["mark", "markd"])) && ~byRate && byTotal
                counts = c.markCountStart.Value:c.markCountStep.Value:c.markCountEnd.Value;
                if isempty(counts)
                    text = "⚠ 計測する Mark の数の終了は、開始以上にしてください。";
                elseif numel(counts) > app.MAX_COUNT_LIST
                    text = sprintf("⚠ 計測する Mark の数が %d 通りになります（上限 %d 通り）。刻みを大きくしてください。", ...
                        numel(counts), app.MAX_COUNT_LIST);
                end
            end
            c.markError.Text = text;
            messages = [messages; text(text ~= "")];
            text = "";
            if c.gam.Value
                terms = string(arrayfun(@(k) c.gamShapeChecks(k, 1).UserData.term, 1:size(c.gamShapeChecks, 1), ...
                    'UniformOutput', false));
                used = terms == "xy" | (terms == "r" & c.featureXYR.Value);
                empty = ~any(reshape([c.gamShapeChecks.Value], size(c.gamShapeChecks)), 2).';
                if any(empty & used)
                    text = "⚠ GAM の形状関数を、項（X・Y、半径）ごとにスプラインかガウス過程回帰の少なくとも1つ選んでください。";
                elseif usesGamKernels(c) && ~any([c.gamKernelChecks.Value])
                    text = "⚠ GAM のガウス過程回帰のカーネルを1つ以上選んでください。";
                elseif usesGamKernels(c) && usesGamMaternNu(c)
                    [values, ok] = parseNumbers(c.gamMaternNu.Value);
                    if ~ok || isempty(values) || any(values <= 0 | values > app.MAX_MATERN_NU)
                        text = sprintf("⚠ GAM の Matérn の ν は 0 より大きく %g 以下の数を空白で区切って入れてください。", ...
                            app.MAX_MATERN_NU);
                    end
                end
            end
            if c.tps.Value && ~any([c.tpsSmoothing.Value])
                text = strip(text + " ⚠ TPS の平滑化を1つ以上選んでください。");
            end
            c.gamShapeError.Text = text;
            messages = [messages; text(text ~= "")];
            % Overlay 補正の式（選んだ成分だけ確かめる）
            texts = strings(0, 1);
            formulas = {c.overlayWafer.Value == app.FORMULA_CHOICE, "Wafer 成分", c.overlayWaferDx, c.overlayWaferDy; ...
                string(c.overlayShotCommon.Value) == "formula", "Shot 共通成分", c.overlayShotDx, c.overlayShotDy; ...
                string(c.overlayPerShot.Value) == "formula", "Shot ごとの成分", c.overlayPerShotDx, c.overlayPerShotDy};
            for k = 1:size(formulas, 1)
                if ~formulas{k, 1}
                    continue
                end
                fields = [formulas{k, 3}, formulas{k, 4}];
                axisNames = ["dx", "dy"];
                for a = 1:2
                    try
                        alignest.parseCorrectionFormula(fields(a).Value, formulas{k, 2} + "の " + axisNames(a));
                    catch err
                        texts(end + 1, 1) = "⚠ " + string(err.message); %#ok<AGROW>
                    end
                end
            end
            c.overlayFormulaError.Text = strjoin(texts, newline);
            messages = [messages; texts];
        end

        function updateEnabled(app)
            c = app.Controls;
            set([c.factorScanY, c.factorMarkY, c.shotRowParityY, c.factorColumnsY], 'Enable', onOff(c.factorSeparate.Value));
            method = string(c.samplingMethod.Value);
            constrained = any(ismember(method, ["ioptimal", "doptimal", "random"])) || ...
                (any(method == "excel") && hasPriorityPlans(app.Settings.sampling));   % Excel の優先順も Shot 数ごと
            markPlans = any(ismember(method, ["mark", "markd"]));   % Mark 単位の計画も計測率でスイープできる
            optimal = any(ismember(method, ["ioptimal", "doptimal", "mark", "markd"]));
            shotConstraints = any(ismember(method, ["ioptimal", "doptimal", "random"]));
            byRate = string(c.countBy.Value) == "rate";
            c.countBy.Enable = onOff(constrained || markPlans);
            c.nShotsList.Enable = onOff(constrained || markPlans);
            set([c.nShotsStart, c.nShotsEnd, c.nShotsStep], 'Enable', onOff(constrained && ~byRate));
            set([c.rateStart, c.rateEnd, c.rateStep], 'Enable', onOff((constrained || markPlans) && byRate));
            % 必ず計測する Shot・同心円の区切りは、Mark 単位の計画にも効く（Shot の Mark すべて・Mark の半径）
            set([c.requiredShots, c.requireOuter, c.requiredInfo, c.excludedShots, c.zoneEdges], 'Enable', ...
                onOff(shotConstraints || markPlans));
            set([c.requiredMarks, c.excludedMarks], 'Enable', onOff(markPlans));
            set([c.quadrants, c.scanConstraint], 'Enable', onOff(shotConstraints));
            c.slack.Enable = onOff(shotConstraints || markPlans);
            set([c.randomRepeats], 'Enable', onOff(any(method == "random")));
            set([c.designOrder, c.exchangeStarts], 'Enable', onOff(optimal));
            set([c.markBalance, c.markRequirePerShot], 'Enable', onOff(markPlans));
            byTotal = string(c.markCountBy.Value) == "total";
            c.markCountBy.Enable = onOff(markPlans && ~byRate);
            c.markPerShot.Enable = onOff(markPlans && ~byRate && ~byTotal);
            set([c.markCountStart, c.markCountEnd, c.markCountStep], 'Enable', onOff(markPlans && ~byRate && byTotal));
            % 使えない理由を書く（Mark 単位を選んでも欄が使えないと思われないように）
            if markPlans && byRate
                c.markCountNote.Text = '「学習 Shot 数」を計測率にしているので、Mark の数は上の計測率（開始・終了・刻み）で決めます。';
            elseif ~markPlans
                c.markCountNote.Text = '選び方で「Mark 単位の I 最適」「Mark 単位の D 最適」を選ぶと使えます。';
            else
                c.markCountNote.Text = 'Wafer 中心に最も近い Mark は必ず計測します。';
            end
            c.markMinPerShot.Enable = onOff(markPlans && c.markRequirePerShot.Value);
            c.layoutPlanInfo.Enable = onOff(any(method == "excel"));
            c.outlierMethod.Enable = onOff(c.excludeOutliers.Value);
            set([c.overlayPerShotDx, c.overlayPerShotDy], 'Enable', onOff(string(c.overlayPerShot.Value) == "formula"));
            set([c.zernikeOrders, c.zernikeFactors], 'Enable', onOff(c.zernike.Value));
            c.outlierSigma.Enable = onOff(c.excludeOutliers.Value);
            set([c.overlayWaferDx, c.overlayWaferDy], 'Enable', onOff(c.overlayWafer.Value == app.FORMULA_CHOICE));
            set([c.overlayShotDx, c.overlayShotDy], 'Enable', onOff(string(c.overlayShotCommon.Value) == "formula"));
            set([c.kernels, c.factorModes], 'Enable', onOff(c.gpr.Value));
            c.maternNu.Enable = onOff(usesMaternNu(c));
            set(c.gamShapeChecks, 'Enable', onOff(c.gam.Value));
            c.gamFactors.Enable = onOff(c.gam.Value);
            set(c.gamKernelChecks, 'Enable', onOff(usesGamKernels(c)));
            c.gamMaternNu.Enable = onOff(usesGamKernels(c) && usesGamMaternNu(c));
            set(c.variograms, 'Enable', onOff(c.ordinaryKriging.Value || c.universalKriging.Value));
            c.tpsFactors.Enable = onOff(c.tps.Value);
            set(c.tpsSmoothing, 'Enable', onOff(c.tps.Value));
            c.tpsLog10Lambda.Enable = onOff(c.tps.Value && c.tpsSmoothing(3).Value);
            c.rbfFactors.Enable = onOff(c.rbf.Value);
            c.ordinaryFactors.Enable = onOff(c.ordinaryKriging.Value);
            c.universalFactors.Enable = onOff(c.universalKriging.Value);
            c.polynomialOrder.Enable = onOff(c.polynomial.Value);
            % 1変数の推定では、Overlay 補正の評価と RT モデル（どちらも X・Y の2成分が要る）を使わない
            scalar = alignest.valueSpec(app.Settings.data).scalar;
            set([c.overlayWafer, c.overlayShotCommon, c.overlayPerShot], 'Enable', onOff(~scalar));
            if scalar
                set([c.overlayWaferDx, c.overlayWaferDy, c.overlayShotDx, c.overlayShotDy, c.overlayPerShotDx, ...
                    c.overlayPerShotDy], 'Enable', 'off');
            end
            c.rt.Enable = onOff(~scalar);
            c.rtOrders.Enable = onOff(c.rt.Value && ~scalar);
            c.overlayHelp.Text = char(ternary(scalar, "1変数の推定（「1. データ読込」の「推定する値」）では、" + ...
                "Overlay 補正の評価と RT モデルは使いません（X・Y の2成分が要るため）。", ""));
            syncTargetOverlayControls(app);   % 「6. 未知の座標の推定」の「補正のモデル」も同じ値にする
        end

        function refreshFactorColumns(app, selected, selectedY)
            % 質的変数に選べるその他の列の一覧（X 成分・Y 成分）：読み込んだデータの列と、設定で選んであるがデータに無い列
            c = app.Controls;
            if nargin < 2
                selected = string(c.factorColumns.Value);
                selectedY = string(c.factorColumnsY.Value);
            end
            available = strings(1, 0);
            if ~isempty(app.Data) && isfield(app.Data, "attributeNames")
                available = reshape(app.Data.attributeNames, 1, []);
            end
            lists = [c.factorColumns, c.factorColumnsY];
            choices = {reshape(string(selected), 1, []), reshape(string(selectedY), 1, [])};
            for k = 1:2
                absent = choices{k}(~ismember(choices{k}, available));
                names = [available, absent];
                lists(k).Items = cellstr([available, absent + "（データに無い）"]);
                lists(k).ItemsData = cellstr(names);
                lists(k).Value = cellstr(choices{k}(ismember(choices{k}, names)));
            end
        end

        function missing = missingFactorColumns(app, selected)
            % データを読み込んでいるときだけ、データに無い列を返す
            missing = strings(1, 0);
            if ~isempty(app.Data) && isfield(app.Data, "attributeNames")
                missing = selected(~ismember(selected, app.Data.attributeNames));
            end
        end

        function onSettingsChanged(app)
            % 欄の使える・使えないを先に変える（確かめ・設定への写しで思わぬエラーが起きても、選んだ選び方の欄を使えるように）
            updateEnabled(app);
            validateSettings(app);
            controlsToSettings(app);
            updateEnabled(app);
            refreshRunSummary(app);
        end

        function onPreset(app, selection)
            controlsToSettings(app);
            app.Settings.methods = alignest.recommendedMethods(selection);
            settingsToControls(app);
            refreshRunSummary(app);
        end

        function onLoadLayouts(app)
            [fileName, folder] = uigetfile({'*.xlsx;*.xlsm;*.xls;*.csv', '学習に使う Shot・Mark (*.xlsx, *.xlsm, *.xls, *.csv)'}, ...
                '学習に使う Shot・Mark を指定したファイルを選ぶ');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.loadLayoutPlans(fullfile(folder, fileName)), "Excel ファイルを読み込めませんでした", ...
                ['1行目に shotNo（Mark 単位なら markNo も）とパターンの名前、2行目から shotNo と 1（計測する）・0（しない）、' ...
                'または優先順（1・2・3…）を書いたファイルを選んでください。']);
        end

        function onSaveSettings(app)
            controlsToSettings(app);
            [fileName, folder] = uiputfile({'*.json', '設定ファイル (*.json)'}, '設定を保存', 'alignment_estimation_settings.json');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            if runWithAlert(app, @() alignest.saveSettings(app.Settings, fullfile(folder, fileName)), ...
                    "設定を保存できませんでした", "保存先のフォルダを変えてもう一度試してください。")
                uialert(app.Figure, sprintf('設定を保存しました：%s', fullfile(folder, fileName)), '保存しました', 'Icon', 'success');
            end
        end

        function onLoadSettings(app)
            [fileName, folder] = uigetfile({'*.json', '設定ファイル (*.json)'}, '設定を読み込む');
            figure(app.Figure);
            if isequal(fileName, 0)
                return
            end
            runWithAlert(app, @() app.setSettings(alignest.loadSettings(fullfile(folder, fileName))), ...
                "設定を読み込めませんでした", "このアプリで保存した設定ファイル（.json）を選んでください。");
        end
    end
end

% ================= このファイルだけで使う小さな関数 =================
function values = checkedValues(boxes)
% チェックの入った項目の UserData（文字列）を並べる
values = strings(1, 0);
for box = boxes(:).'
    if box.Value
        values(end + 1) = string(box.UserData); %#ok<AGROW>
    end
end
end

function used = usesGamKernels(c)
% GAM の形状関数にガウス過程回帰を1つでも選んでいるか（半径の項は説明変数に半径があるときだけ）
used = false;
if ~c.gam.Value
    return
end
for check = reshape(c.gamShapeChecks, 1, [])
    if check.Value && check.UserData.shape == "gp" && (check.UserData.term == "xy" || c.featureXYR.Value)
        used = true;
    end
end
end

function used = usesGamMaternNu(c)
used = any(string({c.gamKernelChecks([c.gamKernelChecks.Value]).UserData}) == "matern");
end

function used = usesMaternNu(c)
% GPR で ν を指定する Matérn（matern・ardmatern）を選んでいるか
used = c.gpr.Value && any(ismember(string(c.kernels.Value), ["matern", "ardmatern"]));
end

function selection = gamFactorSelection(modes)
% GAM の質的変数の扱い（factor・none、両方なら both）を欄の値にする
modes = unique(string(modes));
if isscalar(modes) && any(modes == ["factor", "none"])
    selection = char(modes);
else
    selection = 'both';
end
end

function control = spatialFactorDropdown(parent, callback)
control = uidropdown(parent, 'Items', {'質的変数なし', 'Backfitting', 'なし・Backfitting を比較'}, ...
    'ItemsData', {'none', 'backfit', 'both'}, 'ValueChangedFcn', callback, ...
    'Tooltip', '上で選んだ質的変数を固定効果として、空間成分と交互に推定します（Backfitting）。');
end

function selection = modeSelection(modes)
modes = unique(string(modes));
if numel(modes) == 2 && all(ismember(modes, ["none", "backfit"]))
    selection = 'both';
elseif isscalar(modes) && any(modes == ["none", "backfit"])
    selection = char(modes);
else
    error('alignest:spatialFactorMode', '質的変数の扱いは none・backfit のいずれか、または両方を選んでください。');
end
end

function modes = selectedModes(selection)
if string(selection) == "both"
    modes = ["none", "backfit"];
else
    modes = string(selection);
end
end

function control = rateField(parent, callback)
% 計測率 [%] の入力欄（0 より大きく 100 より小さい。並びの確かめは alignest.measurementRateList）
control = uieditfield(parent, 'numeric', 'Limits', [0, 100], 'ValueDisplayFormat', '%g', 'ValueChangedFcn', callback);
end

function lines = layoutText(sampling)
% 「Excel ファイルで指定」で読み込んだ学習パターンの要約（1パターン1行）
lines = "まだ読み込んでいません";
try
    plans = alignest.parseLayoutPlans(string(fieldOr(sampling, "layoutPlans", strings(0, 1))));
catch err
    lines = "⚠ " + string(err.message);
    return
end
if isempty(plans)
    return
end
lines = strings(numel(plans) + 1, 1);
lines(1) = string(fieldOr(sampling, "layoutFile", "")) + "：" + sprintf("%d パターン", numel(plans));
for k = 1:numel(plans)
    plan = plans(k);
    markLevel = ~isempty(plan.markNos);
    items = string(plan.shotNos);
    unitName = "Shot";
    if markLevel
        items = items + "-" + string(plan.markNos);
        unitName = "Mark";
    end
    preview = strjoin(items(1:min(end, 8)).', " ") + ternary(numel(items) > 8, " …", "");
    if plan.kind == "pattern"
        lines(k + 1) = sprintf("・%s：パターン（%d %s）　%s", plan.name, numel(items), unitName, preview);
    else
        lines(k + 1) = sprintf("・%s：優先順（%d %s。必ず計測 %d）　先頭から %s", plan.name, numel(items), unitName, ...
            nnz(plan.required), preview);
    end
end
end

function value = hasPriorityPlans(sampling)
% Excel ファイルで指定した学習パターンに優先順があるか（学習 Shot 数・計測率を使う）
value = false;
try
    plans = alignest.parseLayoutPlans(string(fieldOr(sampling, "layoutPlans", strings(0, 1))));
    value = any(string({plans.kind}) == "priority");
catch
end
end

function spinner = shotCountSpinner(parent, callback)
MAX_SHOT_COUNT = 10000;
spinner = uispinner(parent, 'Limits', [1, MAX_SHOT_COUNT], 'RoundFractionalValues', 'on', 'ValueChangedFcn', callback);
end
