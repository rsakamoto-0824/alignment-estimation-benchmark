function capture_screens()
%CAPTURE_SCREENS 仕様書・画面遷移図に載せる画面の画像を、サンプルデータで撮り直す。
%   想定利用用途（手法比較・未知の座標・Shot 高次補正・Mark 配置・計測Mapローテ）の順に画面を操作し、
%   ../images/ に PNG を保存する。MATLAB R2022b で、matlab_app フォルダを MATLAB のパスに入れずに実行してよい。
%   画面の色・文字の大きさは、ライトモード・16 pt に固定して撮る（利用者の表示の設定によらず同じ画像にするため）。
SCREEN_POSITION = [20, 20, 1440, 900];   % 撮る窓の大きさ（アプリの標準の大きさ）
SETTLE_SECONDS = 1.5;                    % 図を描き終えるのを待つ時間 [秒]
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(fileparts(here)));   % matlab_app
outDir = fullfile(fileparts(here), 'images');
if ~isfolder(outDir)
    mkdir(outDir);
end
addpath(root);
oldFolder = cd(root);
restoreFolder = onCleanup(@() cd(oldFolder));

app = AlignmentEstimationApp(true);
closeApp = onCleanup(@() delete(app));
app.Figure.Position = SCREEN_POSITION;
app.setTheme("light");
app.setFontSize(16);
shoot = @(name) snap(app.Figure, fullfile(outDir, name), SETTLE_SECONDS);

% ---- 想定利用 1：手法比較の評価 ----
shoot('s01_start.png');
app.loadFile(fullfile(root, 'sample_data', 'sample_alignment.xlsx'));
shoot('s02_data_mapping.png');
app.applyMapping();
selectTabs(app.Tabs.data, ["Wafer マップ"]);
shoot('s03_data_wafermap.png');
selectTabs(app.Tabs.data, ["Shot レイアウト"]);
shoot('s04_data_layout.png');
selectTabs(app.Tabs.data, ["ばらつき分解"]);
app.decomposeDataVariance("", "nested");
shoot('s05_data_variance.png');
app.decomposeDataVariance("", "components");
shoot('s05b_data_components.png');

app.openTab("settings");
settings = app.Settings;
settings.methods = alignest.recommendedMethods("recommended");
settings.sampling.method = ["ioptimal", "random"];
settings.sampling.nShots = [10, 20, 30];
[settings.sampling.nShotsStart, settings.sampling.nShotsEnd, settings.sampling.nShotsStep] = deal(10, 30, 10);
settings.sampling.randomRepeats = 2;
app.setSettings(settings);
selectTabs(app.Tabs.settings, ["計測設定"]);
app.drawMeasurementMap(1);
shoot('s06_settings_points.png');
selectTabs(app.Tabs.settings, ["比べる手法"]);
shoot('s07_settings_methods.png');
selectTabs(app.Tabs.settings, ["評価・Overlay 補正"]);
shoot('s08_settings_overlay.png');

results = app.runEvaluationNow(false);
app.openTab("results");
selectTabs(app.Tabs.results, ["表・グラフ", "表"]);
shoot('s09_results_table.png');
selectTabs(app.Tabs.results, ["表・グラフ", "グラフ"]);
shoot('s10_results_chart.png');
selectTabs(app.Tabs.results, ["誤差の分析", "推定値と誤差の分布"]);
tryRun(@() app.analyzeResiduals(1, results.plans(1).label, 1));
shoot('s11_results_analysis.png');
selectTabs(app.Tabs.results, ["計測配置", "補正の悪化"]);
shoot('s12_results_degradation.png');

app.openTab("map");
app.showMap(1, results.plans(1).label, 1, "vector");
shoot('s13_map.png');

% ---- 想定利用 2：未知の座標の推定と重ね合わせ補正値 ----
app.openTab("target");
app.setTargetPoints(alignest.targetGrid(20, 140));
app.estimateTargets(1, "all", 1);
selectTabs(app.Tabs.target, ["図"]);
shoot('s14_target.png');
app.computeTargetOverlay();
selectTabs(app.Tabs.target, ["補正値"]);
shoot('s15_target_overlay.png');
% このタブの補正のモデル（高次の式と項のチェック）・補正残差のマップ（並べる）・補正の比較
app.estimateTargets(1, results.plans(1).label, 1);
app.setTargetCorrection(waferOrder=1, shotCommon="quadratic", perShot="linear");
selectTabs(app.Tabs.target, ["補正のモデル"]);
shoot('s15b_target_model.png');
app.computeTargetOverlay();
selectTabs(app.Tabs.target, ["補正残差のマップ"]);
app.Controls.targetResidualCircles.Value = '100 135';
app.drawTargetCorrectionMap("residual", "all", "vector", "side", "wafer");
shoot('s15d_target_side.png');
app.compareTargetCorrection();
selectTabs(app.Tabs.target, ["補正の比較"]);
shoot('s15c_target_compare.png');

% ---- 想定利用 3：Shot 高次補正の評価 ----
app.openTab("highOrder");
app.setHighOrderSource("data");
app.computeHighOrder(0);
selectTabs(app.Tabs.highOrder, ["結果", "補正の評価"]);
shoot('s16_highorder_summary.png');
selectTabs(app.Tabs.highOrder, ["結果", "マップ"]);
app.drawHighOrderMap(1, "wafer", "residual", "vector");
shoot('s17_highorder_map.png');

% ---- 想定利用 4：Mark 配置の最適化 ----
app.openTab("markLayout");
app.setMarkLayoutSource("manual");   % サンプルの計測データは Shot の角の 4 Mark だけなので、格子の候補と乱数の Shot で示す
app.makeMarkLayoutGrid([24, 30], [5, 7]);
app.setMarkLayoutSettings(maker="canon", loss="ols", regularization="none", maxMarks=16, shapes=50);
app.generateMarkLayoutShapes();
app.optimizeMarkLayout();
selectTabs(app.Tabs.markLayout, ["制御残差推移"]);
shoot('s18_marklayout.png');

% ---- 想定利用 5：計測Mapローテ ----
app.openTab("rotation");
app.computeRotationVariability("shot", "max");
selectTabs(app.Tabs.rotation, ["ばらつき"]);
shoot('s19_rotation_spread.png');
app.makeRotationMaps();
selectTabs(app.Tabs.rotation, ["計測マップ"]);
shoot('s20_rotation_map.png');
app.runRotationFeedback();
selectTabs(app.Tabs.rotation, ["FB の検証"]);
shoot('s21_rotation_feedback.png');

% ---- メニュー「ヘルプ」 ----
view = app.openHelp();
helpWindow = ancestor(view, 'figure');
snap(helpWindow, fullfile(outDir, 's22_help.png'), 3);
fprintf('画面の画像を %s に保存しました\n', outDir);
end

function snap(figureHandle, filePath, settleSeconds)
% 図を描き終えるのを待ってから、窓の画像を保存する
drawnow;
pause(settleSeconds);
drawnow;
exportapp(figureHandle, filePath);
end

function selectTabs(scope, titles)
% 題名の並び（外側のタブから内側へ）で、scope（アプリのタブ）の中のタブを選ぶ（クリックしたときと同じに、選んだときの処理も呼ぶ）。
% 「図」「表」のように同じ題名のタブがほかのタブにもあるので、アプリのタブの中だけを探す
for title = titles
    tabs = findall(scope, 'Type', 'uitab', 'Title', char(title));
    if isempty(tabs)
        error('capture:noTab', 'タブ「%s」が見つかりません。', title);
    end
    tab = tabs(1);
    group = tab.Parent;
    old = group.SelectedTab;
    group.SelectedTab = tab;
    callback = group.SelectionChangedFcn;
    if ~isempty(callback)
        callback(group, struct("NewValue", tab, "OldValue", old));
    end
    drawnow;
    scope = tab;
end
end

function tryRun(action)
% 図の補助の操作。失敗しても撮影は続ける（画面のまま撮る）
try
    action();
catch err
    fprintf('（撮影の補助の操作を飛ばしました：%s）\n', err.message);
end
end
