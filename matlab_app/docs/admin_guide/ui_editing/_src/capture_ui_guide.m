function capture_ui_guide(mode)
% 説明用コピーで画面を描画し、アプリの公開captureTab APIで保存する。
here = fileparts(mfilename('fullpath'));
guideRoot = fileparts(here);
appRoot = fileparts(fileparts(fileparts(guideRoot)));
repoRoot = fileparts(appRoot);
out = fullfile(guideRoot, 'images');
cache = fullfile(repoRoot, '.cache', 'ui-editing-guide');
if nargin == 0, mode = "original"; end
if mode == "example"
    addpath(appRoot);
    addpath(fullfile(cache, 'example'), '-begin');
else
    addpath(appRoot, '-begin');
end
app = AlignmentEstimationApp(false);
cleanup = onCleanup(@() delete(app));
app.Figure.Position = [30 30 1600 1000];
if mode == "example"
    app.captureTab('data', fullfile(out, '07_after.png'));
    assert(string(app.Controls.chooseFile.Text) == "計測ファイルを選ぶ…");
    assert(numel(app.Controls.chooseFile.Parent.RowHeight) == 7);
    assert(numel(findall(app.Figure, 'Type','uilabel','Text','管理者向け注意：読み込み前に列と単位を確認してください。')) == 1);
    fprintf('Example assertions passed.\n');
    return
end
app.captureTab('data', fullfile(out, '01_original.png'));
app.captureTab('settings', fullfile(out, '02_settings.png'));
app.captureTab('target', fullfile(out, '03_target.png'));
app.setTheme("dark");
app.captureTab('data', fullfile(out, '04_dark.png'));
app.setTheme("light");
app.loadFile(fullfile(appRoot, 'sample_data', 'sample_alignment.csv'));
app.applyMapping();
settings = app.Settings;
settings.methods = alignest.recommendedMethods('none');
settings.methods.polynomial.enabled = true;
settings.methods.polynomial.order = 1;
settings.sampling.method = "manual";
settings.sampling.manualPlans = "1 4 7 10 13 16 19 22 25 28";
app.setSettings(settings);
results = app.runEvaluationNow(false);
assert(all(results.table.note == ""), '画面確認用の小規模評価に失敗');
app.captureTab('results', fullfile(out, '05_results.png'));
app.captureTab('run', fullfile(out, '06_run.png'));
report = struct('version',version,'mode',mode,'evaluationRows',height(results.table), ...
    'errors',nnz(results.table.note ~= ""),'source',which('AlignmentEstimationApp'), ...
    'captureMethod','AlignmentEstimationApp.captureTab -> exportapp','syntheticDataOnly',true);
f = fopen(fullfile(cache, 'capture-check.json'),'w');
fwrite(f,jsonencode(report,PrettyPrint=true),'char'); fclose(f);
fprintf('Original capture and smoke evaluation passed.\n');
end
