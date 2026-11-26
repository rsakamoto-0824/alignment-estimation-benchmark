function result = varianceResult(rowCategory, rowAxis, components, variances, counts)
%VARIANCERESULT ばらつき分解の結果の表（alignest.varianceDecomposition・componentVarianceDecomposition で共通）。
%   result = alignest.varianceResult(rowCategory, rowAxis, components, variances, counts)
%   rowCategory・rowAxis：行（棒 × 軸）の名前、components：成分（段）の名前、variances：行 × 成分の分散、counts：行ごとの点の数。
%   全体の分散 = 成分の分散の和（分散の加法性）。3σ = 3√分散、3σ の配分 = 全体の 3σ × 成分の分散の割合（足すと全体の 3σ）。
%   result.table：category・axis・component・variance・sigma3・sigma3Share・percent・n。result.totals：category・axis・
%   variance・sigma3・n。result.components。
SIGMA_MULTIPLE = 3;   % 3σ
nRows = numel(rowCategory);
nComponents = numel(components);
total = sum(variances, 2);
percent = 100 * variances ./ total;
percent(~(total > 0), :) = NaN;
share = SIGMA_MULTIPLE * sqrt(total) .* percent / 100;
long = reshape(variances.', [], 1);
result.components = components;
result.table = table(repelem(rowCategory, nComponents, 1), repelem(rowAxis, nComponents, 1), ...
    repmat(components(:), nRows, 1), long, SIGMA_MULTIPLE * sqrt(long), reshape(share.', [], 1), ...
    reshape(percent.', [], 1), repelem(counts, nComponents, 1), 'VariableNames', ["category", "axis", "component", ...
    "variance", "sigma3", "sigma3Share", "percent", "n"]);
result.totals = table(rowCategory, rowAxis, total, SIGMA_MULTIPLE * sqrt(total), counts, ...
    'VariableNames', ["category", "axis", "variance", "sigma3", "n"]);
end
