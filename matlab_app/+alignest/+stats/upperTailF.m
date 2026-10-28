function p = upperTailF(f, dfNumerator, dfDenominator)
%UPPERTAILF F 分布の上側確率（正則化不完全ベータ関数で求める。Toolbox の fcdf を使わない）。
%   p = alignest.stats.upperTailF(f, dfNumerator, dfDenominator)。f が NaN なら NaN、Inf なら 0。
if isnan(f)
    p = NaN;
elseif isinf(f)
    p = 0;
else
    p = betainc(dfDenominator / (dfDenominator + dfNumerator * f), dfDenominator / 2, dfNumerator / 2);
end
end
