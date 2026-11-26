function runAlignmentEstimationAppStandard()
%RUNALIGNMENTESTIMATIONAPPSTANDARD 面内推定評価ツールの通常版を起動する（通常版のスタンドアローン版の入口）。
%   通常版は、比べる手法を GPR・TPS・XY 多項式、計測点の選び方を Shot 単位の I 最適・ランダム、Overlay 補正を組み込みの
%   式だけにした版（設定の欄が少ないので起動が速い。alignest.editionSettings）。すべての設定を使う Pro 版は
%   runAlignmentEstimationApp。MATLAB では、このフォルダで runAlignmentEstimationAppStandard と入力する。
%   スタンドアローン版（exe）では、画面を閉じるまで終わらないように待つ。
app = AlignmentEstimationApp(true, true, "standard");
if isdeployed
    waitfor(app.Figure);
end
end
