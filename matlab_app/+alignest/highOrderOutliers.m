function outlier = highOrderOutliers(weights)
%HIGHORDEROUTLIERS Shot 高次補正のロバスト回帰（Huber・LAD）で「外れ値とみなした点」を返す（点ごとの true・false）。
%   outlier = alignest.highOrderOutliers(weights)
%   weights：alignest.robustRidgeFit の点ごとの重み（alignest.shotHighOrder の result.points の weightX・weightY）。
%   残差が大きいため、当てはめでの重みを OUTLIER_WEIGHT 未満に下げた点（その点の影響を半分未満にした点）を外れ値とみなす。
%   Huber の重みは min(1, c × 尺度 / |残差|) なので |残差| > 2c × 尺度（c = 1.345 なら尺度の約 2.7 倍）の点、LAD の重みは
%   尺度 / |残差| なので |残差| > 2 × 尺度 の点。尺度は残差の MAD × 1.4826（正規分布なら標準偏差に当たる）。
%   最小二乗は重みがすべて 1 なので、外れ値とみなした点は無い。重みの無い点（NaN。補正しなかった点）は false。
OUTLIER_WEIGHT = 0.5;
outlier = weights < OUTLIER_WEIGHT;
end
