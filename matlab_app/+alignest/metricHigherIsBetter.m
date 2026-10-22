function higher = metricHigherIsBetter(metricName)
%METRICHIGHERISBETTER 指標が大きいほど良いか（R²・平均値／中央値に対する改善量・改善率）。
%   ほかの指標（RMSE・MAE・Overlay の |平均|+3σ・処理時間など）は小さいほど良い。
%   ワースト値・95%値・最良（★）・基準の手法との比較で、良い向きを決めるのに使う。
higher = startsWith(string(metricName), ["R2", "improve"]);
end
