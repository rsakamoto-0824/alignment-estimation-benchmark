function [kinds, labels] = errorBarKinds()
%ERRORBARKINDS 「計測配置の比較」のエラーバーの種類（alignest.layoutErrorBars の kind）と、画面に出す名前。
kinds = ["none", "sd", "ci95", "range"];
labels = ["なし", "± 標準偏差（Wafer 間のばらつき）", "95% 信頼区間（平均 ± 1.96 × 標準誤差）", ...
    "Wafer の最小〜最大"];
end
