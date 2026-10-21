function [names, labels] = statisticNames()
%STATISTICNAMES Wafer 間の集計のしかた（alignest.summarizeResults の statistic）と、画面に出す名前。
%   worst：最も悪い Wafer の値（RMSE・MAE・処理時間は最大、R²・調整済み R² は最小）
%   p95  ：95% の Wafer がこの値より良い値（RMSE・MAE・処理時間は 95 パーセント点、R² は 5 パーセント点）
names = ["mean", "median", "worst", "p95"];
labels = ["平均", "中央値", "ワースト値", "95%値"];
end
