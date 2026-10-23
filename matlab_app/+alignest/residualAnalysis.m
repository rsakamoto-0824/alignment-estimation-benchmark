function analysis = residualAnalysis(estimates)
%RESIDUALANALYSIS 推定値の表（alignest.collectEstimates）の残差を、正規性検定と質的変数の ANOVA で調べる。
%   analysis = alignest.residualAnalysis(estimates)
%   手法 × 学習パターンの列 × 軸（X・Y）ごとに、表にある Wafer の評価点をまとめて扱う。
%   analysis.normality：点数・平均・標準偏差・歪度・尖度（過剰）・Shapiro–Wilk・Anderson–Darling・Jarque–Bera と判定
%     （判定は Shapiro–Wilk の p 値。5000 点を超えて計算できないときは Anderson–Darling の p 値）
%   analysis.anova    ：質的変数ごとの一元配置の F 検定と、ほかの質的変数で調整した F 検定（alignest.stats.anovaMainEffects）
%     質的変数は Scan 方向・Mark 番号・Shot 行の奇偶・工程（Operation）・装置（EqpId）・ロット（LotID）と、
%     質的変数に選んだファイルのその他の列（表の「質的変数:<列名>」）。値の無い変数は出さない。
SIGNIFICANCE = 0.05;
methodIds = string(estimates.methodId);
groups = string(estimates.group);
[combinations, first] = unique([methodIds, groups], 'rows', 'stable');
normalityRows = cell(0, 1);
anovaRows = cell(0, 1);
for c = 1:size(combinations, 1)
    select = methodIds == combinations(c, 1) & groups == combinations(c, 2);
    subset = estimates(select, :);
    methodLabel = string(estimates.methodLabel(first(c)));
    for axisName = ["X", "Y"]
        residual = subset.("residual" + axisName);
        result = alignest.stats.normalityTests(residual);
        [judgement, basis] = normalityJudgement(result, SIGNIFICANCE);
        normalityRows{end + 1, 1} = table(methodLabel, combinations(c, 1), combinations(c, 2), axisName, ...
            result.n, result.mean, result.std, result.skewness, result.excessKurtosis, result.swW, result.swP, ...
            result.adA2, result.adP, result.jb, result.jbP, basis, judgement, 'VariableNames', ["methodLabel", ...
            "methodId", "group", "axis", "n", "mean", "std", "skewness", "excessKurtosis", "swW", "swP", "adA2", ...
            "adP", "jb", "jbP", "basis", "judgement"]); %#ok<AGROW>
        anova = alignest.stats.anovaMainEffects(residual, alignest.residualFactors(subset));
        if height(anova) == 0
            continue
        end
        judgements = repmat("—", height(anova), 1);
        judgements(anova.p < SIGNIFICANCE) = sprintf("水準で差がある（p < %.2f）", SIGNIFICANCE);
        judgements(anova.p >= SIGNIFICANCE) = "差があるとはいえない";
        prefix = table(repmat(methodLabel, height(anova), 1), repmat(combinations(c, 1), height(anova), 1), ...
            repmat(combinations(c, 2), height(anova), 1), repmat(axisName, height(anova), 1), ...
            'VariableNames', ["methodLabel", "methodId", "group", "axis"]);
        anovaRows{end + 1, 1} = [prefix, anova, table(judgements, 'VariableNames', "judgement")]; %#ok<AGROW>
    end
end
analysis.normality = vertcatOrEmpty(normalityRows);
analysis.anova = vertcatOrEmpty(anovaRows);
analysis.significance = SIGNIFICANCE;
end

function [judgement, basis] = normalityJudgement(result, significance)
if isfinite(result.swP)
    p = result.swP;
    basis = "Shapiro–Wilk";
elseif isfinite(result.adP)
    p = result.adP;
    basis = "Anderson–Darling";
else
    judgement = "点数が少なく判定できない";
    basis = "—";
    return
end
if p < significance
    judgement = sprintf("正規分布から外れている（p < %.2f）", significance);
else
    judgement = "正規分布から外れているとはいえない";
end
end

function merged = vertcatOrEmpty(parts)
if isempty(parts)
    merged = table();
else
    merged = vertcat(parts{:});
end
end
