function [names, labels] = overlayMetricNames()
%OVERLAYMETRICNAMES Overlay 補正の評価の指標の列名と、画面に出す名前（どれも |平均| + 3σ [nm]、小さいほど良い）。
%   overlayActual    ：実測値で補正した残差
%   overlayEstimated ：推定値で補正した残差（学習しなかった Shot は推定値で補正を求める）
%   overlayChange    ：推定による残差の変化（推定値で補正した残差 − 実測値で補正した残差）
%   overlayIncrease  ：推定による増加（推定値で補正 − 実測値で補正 の |平均|+3σ の差）
kinds = ["overlayActual", "overlayEstimated", "overlayChange", "overlayIncrease"];
kindLabels = ["OVL 残差 実測値で補正", "OVL 残差 推定値で補正", "OVL 推定による変化", "OVL 推定による増加"];
names = strings(1, 0);
labels = strings(1, 0);
for axisName = ["X", "Y"]
    for k = 1:numel(kinds)
        names(end + 1) = kinds(k) + "_" + axisName; %#ok<AGROW>
        labels(end + 1) = kindLabels(k) + " |m|+3σ [nm]（" + axisName + "）"; %#ok<AGROW>
    end
end
end
