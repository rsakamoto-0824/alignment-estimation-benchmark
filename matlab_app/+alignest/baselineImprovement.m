function baseline = baselineImprovement(truthX, truthY, trainX, trainY, statistic, rmse)
%BASELINEIMPROVEMENT 学習点の平均値（または中央値）をそのまま推定値にした場合の RMSE と、それに対する改善量・改善率。
%   baseline = alignest.baselineImprovement(truthX, truthY, trainX, trainY, statistic, rmse)
%   statistic は "mean"（平均値）か "median"（中央値）。X・Y それぞれ、学習点の計測値（trainX・trainY）の値を
%   全評価点の推定値にして、評価点の計測値（truthX・truthY）との RMSE を X・Y 合わせて求める（手法の RMSE_XY と同じ形）。
%   baseline.rmse：その RMSE [nm]、baseline.improvement = baseline.rmse − rmse [nm]（正なら手法のほうが良い）、
%   baseline.percent = improvement / baseline.rmse × 100 [%]。学習点か評価点が無い軸があれば NaN。
arguments
    truthX double
    truthY double
    trainX double
    trainY double
    statistic (1, 1) string {mustBeMember(statistic, ["mean", "median"])}
    rmse (1, 1) double
end
center = @(values) feval(statistic, values(isfinite(values)));
errors = zeros(0, 1);
for pair = {{truthX, trainX}, {truthY, trainY}}
    truth = pair{1}{1}(:);
    train = pair{1}{2}(:);
    if isempty(truth)
        continue
    end
    if ~any(isfinite(train))
        errors = NaN;
        break
    end
    errors = [errors; truth - center(train)]; %#ok<AGROW>
end
baseline.rmse = NaN;
if ~isempty(errors)
    baseline.rmse = sqrt(mean(errors .^ 2));
end
baseline.improvement = baseline.rmse - rmse;
baseline.percent = 100 * baseline.improvement / baseline.rmse;
if ~(baseline.rmse > 0)
    baseline.percent = NaN;
end
end
