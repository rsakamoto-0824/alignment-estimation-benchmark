function factors = residualFactors(points)
%RESIDUALFACTORS 残差の ANOVA・箱ひげ図で調べる質的変数と、点ごとの水準（文字列。値の無い点は ""）。
%   factors = alignest.residualFactors(estimates)   % estimates は alignest.collectEstimates の表
%   Scan 方向・Mark 番号・Shot 行の奇偶・工程（Operation）・装置（EqpId）・ロット（LotID）と、質的変数に選んだ
%   ファイルのその他の列（表の「質的変数:<列名>」）。値が1つも無い変数（例：Operation の列が無い）は入れない。
%   factors は構造体配列（name：変数の名前、levels：点ごとの水準）。alignest.residualAnalysis と同じ分け方。
direction = string(points.direction);
direction(ismissing(direction) | isnan(points.direction)) = "";
parity = repmat("", height(points), 1);
parity(points.shotRowParity == 1) = "奇数行";
parity(points.shotRowParity == 2) = "偶数行";
candidates = struct("name", {"Scan 方向", "Mark 番号", "Shot 行の奇偶", "工程（Operation）", "装置（EqpId）", ...
    "ロット（LotID）"}, "levels", {direction, string(points.markNo), parity, string(points.Operation), ...
    string(points.EqpId), string(points.LotID)});
for name = string(points.Properties.VariableNames(startsWith(points.Properties.VariableNames, "質的変数:")))
    candidates(end + 1) = struct("name", extractAfter(name, "質的変数:"), "levels", string(points.(name))); %#ok<AGROW>
end
for k = 1:numel(candidates)
    candidates(k).levels(ismissing(candidates(k).levels)) = "";
end
keep = arrayfun(@(factor) any(factor.levels ~= ""), candidates);
factors = candidates(keep);
end
