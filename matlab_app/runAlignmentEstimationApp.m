function runAlignmentEstimationApp()
%RUNALIGNMENTESTIMATIONAPP 面内推定評価ツールの Pro 版（すべての設定）を起動する（Pro 版のスタンドアローン版の入口）。
%   MATLAB では、このフォルダで runAlignmentEstimationApp と入力する。設定を絞った通常版は
%   runAlignmentEstimationAppStandard。
%   スタンドアローン版（exe）では、画面を閉じるまで終わらないように待つ。
app = AlignmentEstimationApp();
if isdeployed
    waitfor(app.Figure);
end
end
