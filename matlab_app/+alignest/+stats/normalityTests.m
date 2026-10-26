function result = normalityTests(values)
%NORMALITYTESTS 値の要約（平均・標準偏差・歪度・尖度）と3つの正規性検定をまとめて求める。
%   result.n, mean, std, skewness, excessKurtosis（正規分布なら 0）
%   result.swW, swP：Shapiro–Wilk（3〜5000 点のときだけ）
%   result.adA2, adP：Anderson–Darling（8 点以上）
%   result.jb, jbP：Jarque–Bera（歪度と尖度から。点数が多いときに向く。p 値は自由度2のカイ二乗分布）
%   result.swNote, adNote：Shapiro–Wilk・Anderson–Darling を計算しなかった理由（例："6000 点（5000 点超）"。
%   計算したときは ""。画面の表・Excel に出す）
SW_MIN_POINTS = 3;      % alignest.stats.shapiroWilk の近似が使える点数の範囲
SW_MAX_POINTS = 5000;
AD_MIN_POINTS = 8;      % alignest.stats.andersonDarling
x = values(isfinite(values));
x = x(:);
n = numel(x);
result = struct("n", n, "mean", NaN, "std", NaN, "skewness", NaN, "excessKurtosis", NaN, ...
    "swW", NaN, "swP", NaN, "adA2", NaN, "adP", NaN, "jb", NaN, "jbP", NaN, "swNote", "", "adNote", "");
[result.swNote, result.adNote] = skipReasons(x, n, SW_MIN_POINTS, SW_MAX_POINTS, AD_MIN_POINTS);
if n == 0
    return
end
result.mean = mean(x);
if n < 2
    return
end
result.std = std(x);
centered = x - mean(x);
secondMoment = mean(centered .^ 2);
if secondMoment > 0
    result.skewness = mean(centered .^ 3) / secondMoment ^ 1.5;
    result.excessKurtosis = mean(centered .^ 4) / secondMoment ^ 2 - 3;
    result.jb = n / 6 * (result.skewness ^ 2 + result.excessKurtosis ^ 2 / 4);
    result.jbP = exp(-result.jb / 2);
end
[result.swW, result.swP] = alignest.stats.shapiroWilk(x);
[result.adA2, result.adP] = alignest.stats.andersonDarling(x);
end

function [swNote, adNote] = skipReasons(x, n, swMin, swMax, adMin)
% 検定を計算しない理由（点数が範囲の外・値がすべて同じ）。表の欄に入るように短くする
swNote = "";
adNote = "";
allSame = n > 0 && max(x) - min(x) <= eps(max(abs(x)));
if n < swMin
    swNote = sprintf("%d 点（%d 点未満）", n, swMin);
elseif n > swMax
    swNote = sprintf("%d 点（%d 点超）", n, swMax);
elseif allSame
    swNote = "値がすべて同じ";
end
if n < adMin
    adNote = sprintf("%d 点（%d 点未満）", n, adMin);
elseif allSame
    adNote = "値がすべて同じ";
end
end
