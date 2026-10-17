function [lags, semivariance] = krigingEmpiricalVariogram(model, values)
%KRIGINGEMPIRICALVARIOGRAM 経験バリオグラム（区間ごとの距離の平均と、半分散 ½(差)² の平均）。点の組がない区間は除く。
semi = 0.5 * (values(model.pairI) - values(model.pairJ)) .^ 2;
lags = zeros(0, 1);
semivariance = zeros(0, 1);
for lag = 1:model.nLags
    inBin = model.pairBin == lag;
    if any(inBin)
        lags(end + 1, 1) = mean(model.pairDistance(inBin)); %#ok<AGROW>
        semivariance(end + 1, 1) = mean(semi(inBin)); %#ok<AGROW>
    end
end
end
