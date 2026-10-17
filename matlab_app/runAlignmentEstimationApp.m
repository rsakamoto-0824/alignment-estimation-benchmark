function runAlignmentEstimationApp()
%RUNALIGNMENTESTIMATIONAPP 検証ツールを起動する（スタンドアローン版の入口）。
%   MATLAB では、このフォルダで runAlignmentEstimationApp と入力する。
%   スタンドアローン版（exe）では、画面を閉じるまで終わらないように待つ。
app = AlignmentEstimationApp();
if isdeployed
    waitfor(app.Figure);
end
end
