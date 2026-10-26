function [lower, upper, label] = layoutErrorBars(comparison, kind)
%LAYOUTERRORBARS 「計測配置の比較」の評価点に付けるエラーバーの下端・上端（指標の値からの長さ。0 以上）。
%   [lower, upper, label] = alignest.layoutErrorBars(comparison, kind)
%   comparison は alignest.layoutComparison の表。kind は次のいずれか（Wafer ごとの値のばらつきから求める）：
%   "none"  ：描かない（lower・upper は NaN）
%   "sd"    ：± 標準偏差（Wafer 間のばらつき）
%   "ci95"  ：± 1.96 × 標準誤差（平均の 95% 信頼区間の幅。正規近似。集計が平均以外のときも同じ幅を目安として描く）
%   "range" ：Wafer の最小〜最大（集計の値は必ずこの間に入る）
%   Wafer が1枚だけの列は、標準偏差・信頼区間を描かない（NaN）。label は凡例・注記に使う説明。
Z_95 = 1.96;   % 95% 区間（正規近似。alignest.pairedComparison と同じ）
[kinds, labels] = alignest.errorBarKinds();
if ~any(kinds == kind)
    error('alignest:errorBar', 'エラーバーの種類は %s のいずれかです: %s', strjoin(kinds, "・"), kind);
end
label = labels(kinds == kind);
n = height(comparison);
lower = nan(n, 1);
upper = nan(n, 1);
switch kind
    case "sd"
        lower = comparison.sd;
        upper = comparison.sd;
    case "ci95"
        lower = Z_95 * comparison.se;
        upper = lower;
    case "range"
        lower = max(comparison.value - comparison.minValue, 0);
        upper = max(comparison.maxValue - comparison.value, 0);
end
end
