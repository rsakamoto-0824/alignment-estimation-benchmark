% 実際のローカルアプリを、同梱の模擬データで操作して撮影する。
% 撮影と同時に、手順書の番号を置く位置（画面の部品の左寄り・縦の中央、画像のピクセル座標）を
% images/control-positions.json に書き出す（content.json の markers に使う）。
here = fileparts(mfilename('fullpath'));
appRoot = fileparts(fileparts(fileparts(here)));
addpath(appRoot);
out = fullfile(fileparts(here), 'images');
if ~isfolder(out), mkdir(out); end
app = AlignmentEstimationApp(false);
cleanup = onCleanup(@() delete(app));
app.Figure.Position = [30, 30, 1600, 1000];
positions = struct();
app.loadFile(fullfile(appRoot, 'sample_data', 'sample_alignment.xlsx'));
app.captureTab('data', fullfile(out, '01_import.png'));
app.applyMapping();
app.captureTab('data', fullfile(out, '02_prepared.png'));
app.Controls.dataTabs.SelectedTab = app.Controls.previewTab;
app.captureTab('data', fullfile(out, '03_preview.png'));
positions.p03_preview = markerAt(app, {app.Controls.previewWafer, app.Controls.previewMarkerSize});
app.Controls.previewGroupBy.Value = 'eqpId';
app.Controls.previewGroupBy.ValueChangedFcn([], []);
group = find(string(app.Controls.previewWafer.Items) == "平均：EqpId = EXP01（3 枚）");
app.Controls.previewWafer.Value = group;
app.Controls.previewWafer.ValueChangedFcn([], []);
app.captureTab('data', fullfile(out, '17_preview_group.png'));
positions.p17_preview_group = markerAt(app, {app.Controls.previewWafer, app.Controls.previewEllipse, app.Controls.previewAxes(1)});
app.Controls.previewWafer.Value = 1;
app.Controls.previewWafer.ValueChangedFcn([], []);
app.Controls.dataTabs.SelectedTab = app.Controls.layoutTab;
app.captureTab('data', fullfile(out, '04_layout.png'));
app.Controls.dataTabs.SelectedTab = app.Controls.shotOverlayTab;
app.Controls.shotOverlayWaferOrder.Value = 1;
app.drawShotOverlay(1:5, true);
app.captureTab('data', fullfile(out, '18_shot_overlay.png'));
positions.p18_shot_overlay = markerAt(app, {app.Controls.shotOverlayWafers, app.Controls.shotOverlayByScan, ...
    app.Controls.shotOverlayEllipse});
app.Controls.dataTabs.SelectedTab = app.Controls.mappingTab;
s = app.Settings;
s.sampling.nShotsStart = 10; s.sampling.nShotsEnd = 20; s.sampling.nShotsStep = 10;
s.sampling.nShots = [10, 20];
app.setSettings(s);
app.captureTab('settings', fullfile(out, '05_settings.png'));
positions.p05_settings = markerAt(app, {app.Controls.samplingMethod, app.Controls.nShotsStart, app.Controls.zoneEdges, ...
    app.Controls.factorScan, app.Controls.factorColumns, app.Controls.featureXY});
scroll(app.Controls.tps.Parent, 'bottom');
app.captureTab('settings', fullfile(out, '06_methods.png'));
scroll(app.Controls.overlayWafer.Parent, 'bottom');
app.captureTab('settings', fullfile(out, '07_overlay_settings.png'));
app.captureTab('run', fullfile(out, '08_ready.png'));
results = app.runEvaluationNow(false);
assert(all(results.table.note == ""), '撮影用の評価に失敗した組み合わせがあります');
app.captureTab('run', fullfile(out, '09_completed.png'));
app.captureTab('results', fullfile(out, '10_table.png'));
app.Controls.resultTabs.SelectedTab = app.Controls.chartTab;
app.Controls.chartErrorBars.Value = 'sd';
app.Controls.chartErrorBars.ValueChangedFcn([], []);
app.captureTab('results', fullfile(out, '11_chart.png'));
positions.p11_chart = markerAt(app, {app.Controls.chartXAxis, app.Controls.chartMethods, app.Controls.chartErrorBars});
app.Controls.chartXAxis.Value = 'criteria';
app.Controls.chartXAxis.ValueChangedFcn([], []);
app.captureTab('results', fullfile(out, '12_criteria.png'));
positions.p12_criteria = markerAt(app, {app.Controls.chartXAxis, app.Controls.chartPoints, app.Controls.chartAxes2});
app.Controls.chartXAxis.Value = 'plan';
app.Controls.chartErrorBars.Value = 'none';
app.Controls.chartXAxis.ValueChangedFcn([], []);
tabs = app.Controls.resultTabs.Children;
app.Controls.resultTabs.SelectedTab = tabs(strcmp(string({tabs.Title}), '基準の手法との比較'));
app.captureTab('results', fullfile(out, '13_compare.png'));
app.Controls.resultTabs.SelectedTab = tabs(strcmp(string({tabs.Title}), '推定値と誤差の分布'));
app.analyzeResiduals(1, results.groups(1), 0);
app.captureTab('results', fullfile(out, '14_analysis.png'));
app.drawScatter(1, results.groups(end), 0, "mark");
app.Controls.resultTabs.SelectedTab = app.Controls.scatterTab;
app.captureTab('results', fullfile(out, '20_scatter.png'));
positions.p20_scatter = markerAt(app, {app.Controls.scatterMethod, app.Controls.scatterColor, app.Controls.scatterAxes(1)});
app.showMap(1, results.plans(1).label, 1, 'vector', 'estimate');
app.captureTab('map', fullfile(out, '15_map.png'));
positions.p15_map = markerAt(app, {app.Controls.mapWafer, app.Controls.mapMode, app.Controls.mapMarkerSize});
app.showMap(1, results.plans(1).label, 1, 'X', 'overlay');
app.captureTab('map', fullfile(out, '16_overlay.png'));
positions.p16_overlay = markerAt(app, {app.Controls.mapContent, app.Controls.mapAxes(2), app.Controls.mapAxes(3)});
group = find(string(app.Controls.mapWafer.Items) == "平均：全 Wafer（5 枚）");
app.showMap(group, results.plans(end).label, 1, 'vector', 'estimate');
app.captureTab('map', fullfile(out, '21_map_group.png'));
positions.p21_map_group = markerAt(app, {app.Controls.mapWafer, app.Controls.mapEllipse, app.Controls.mapAxes(3)});
% 計測する Shot の優先順のファイル（撮影用の一時ファイル。Shot 番号と優先度）
priorityFile = fullfile(tempdir, 'shot_priority.csv');
writetable(table([50; 1; 99; (2:2:40).'], [1; 0; 1; nan(20, 1)], 'VariableNames', ["shotNo", "優先度"]), priorityFile);
app.loadShotPriority(priorityFile);
delete(priorityFile);
scroll(app.Controls.samplingMethod.Parent, 'top');
app.captureTab('settings', fullfile(out, '19_priority.png'));
positions.p19_priority = markerAt(app, {app.Controls.samplingMethod, app.Controls.loadPriority, app.Controls.priorityInfo});
% 計測率のスイープ・必ず計測する Shot（指定と最外周）・計測マップ（拡張 I 最適計画）
s = app.Settings;
s.sampling.method = "ioptimal";
s.sampling.countBy = "rate";
s.sampling.rateStart = 20; s.sampling.rateEnd = 40; s.sampling.rateStep = 10;
s.sampling.requiredShots = [1, 50, 99];
s.sampling.requireOuterShots = true;
app.setSettings(s);
scroll(app.Controls.samplingMethod.Parent, 'top');
app.captureTab('settings', fullfile(out, '22_rate_required.png'));
positions.p22_rate_required = markerAt(app, {app.Controls.countBy, app.Controls.rateStart, app.Controls.requiredShots, ...
    app.Controls.requireOuter, app.Controls.requiredInfo});
app.TabGroup.SelectedTab = app.Tabs.run;
drawnow;
app.drawMeasurementMap(1, "I最適 計測率 40%");
app.captureTab('run', fullfile(out, '23_measurement_map.png'));
positions.p23_measurement_map = markerAt(app, {app.Controls.measureWafer, app.Controls.drawMeasure, ...
    app.Controls.exportMeasure, app.Controls.measureInfo});
% 学習データの異常値を除いて推定（n = 2.5）し、Wafer ごとのマップで除いた Mark（×）を見る
s = app.Settings;
s.sampling.rateStart = 40;
s.evaluation.excludeOutliers = true;
s.evaluation.outlierSigma = 2.5;
app.setSettings(s);
scroll(app.Controls.excludeOutliers.Parent.Parent, 'bottom');
app.captureTab('settings', fullfile(out, '24_outlier_settings.png'));
positions.p24_outlier_settings = markerAt(app, {app.Controls.excludeOutliers, app.Controls.outlierSigma});
outlierResults = app.runEvaluationNow(false);
app.showMap(1, outlierResults.plans(1).label, 1, 'vector', 'estimate');
app.captureTab('map', fullfile(out, '25_outlier_map.png'));
positions.p25_outlier_map = markerAt(app, {app.Controls.mapAxes(1), app.Controls.mapInfo});
fid = fopen(fullfile(out, 'capture-summary.txt'), 'w');
fprintf(fid, '撮影日時: %s\n評価行数: %d\n推定失敗: %d\n入力: sample_alignment.xlsx（模擬データ）\n', ...
    char(datetime('now')), height(results.table), nnz(results.table.note ~= ""));
fclose(fid);
fid = fopen(fullfile(out, 'control-positions.json'), 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonencode(positions, 'PrettyPrint', true));
fclose(fid);
fprintf('SCREENSHOTS_COMPLETE %d evaluation rows\n', height(results.table));

function points = markerAt(app, controls)
% 部品の左端から少し内側・縦の中央の位置（画像のピクセル座標。左上が原点）
INSET_PX = 16;
drawnow;
figureHeight = app.Figure.Position(4);
points = zeros(numel(controls), 2);
for k = 1:numel(controls)
    position = getpixelposition(controls{k}, true);
    points(k, :) = round([position(1) + INSET_PX, figureHeight - (position(2) + position(4) / 2)]);
end
end
