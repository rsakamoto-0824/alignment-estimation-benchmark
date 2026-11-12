function rows = markLayoutCriterion(study)
%MARKLAYOUTCRITERION 「8. Mark配置の最適化」で配置を選んだ I 最適計画の式（採用した演算式）と、その中身（使った項・点の数）。
%   rows = alignest.markLayoutCriterion(study)   % study：alignest.markLayoutStudy の結果
%   rows：[項目, 内容] の2列の文字列（画面の「I 最適の式」タブと、Excel の「説明」シートに出す）。
%   式は alignest.iOptimalMarks と同じ：I(S) = Σ_式 trace(M_S⁻¹ W)、M_S = F_S' F_S（計測する Mark の行）、
%   W = F' F / N（予測の分散を求める候補の Mark N 点の平均）。F の列は補正の式（dx・dy）の使う項（表で外した項・VIF で
%   外した項を除く）。N は配置を選んだ候補の Mark（実測値で評価するときは、どの Shot にも値の無い候補の Mark を除く。
%   必ず計測する Mark は残す。計測しない Mark は選ばないが N には入れる）。
arguments
    study struct
end
AXIS_NAMES = ["dx", "dy"];
candidates = study.candidates;
nPredict = height(candidates);
if study.valueSource == "measured"
    nPredict = nnz(candidates.nShots > 0 | candidates.required);
end
nRequired = nnz(candidates.required);
nExcluded = nnz(candidates.excluded & ~candidates.required);
rows = [
    "採用した式", "I(S) = Σ trace(M_S⁻¹ W)（Σ は dx・dy の2つの式の和）。Mark の数ごとに I(S) が最も小さい配置 S を選ぶ"
    "M_S", "F_S' F_S（F_S：計測する Mark の行だけの F）"
    "W", sprintf("F' F / N（N = %d：予測の分散を求める候補の Mark）", nPredict)
    ];
terms = study.terms;
for a = 1:numel(AXIS_NAMES)
    mine = terms(terms.axis == AXIS_NAMES(a) & terms.used, :);
    names = "k" + string(mine.k) + "（" + string(mine.term) + "）";
    rows(end + 1, :) = ["F の列（" + AXIS_NAMES(a) + " の式）", sprintf("%d 項：%s", height(mine), strjoin(names, "・"))]; %#ok<AGROW>
end
rows = [rows
    "補正の式", string(study.options.description)
    "I の意味", "重みなしの最小二乗で当てはめたときの、N 点での予測の分散の平均（計測のばらつきの分散を 1 とする）。" + ...
        "ロバスト回帰・正則化は配置を選ぶ式には入れず、制御残差の評価に使う"
    "I 効率", "計測できる Mark をすべて計測したときの I ÷ その配置の I"
    "D 基準（参考）", "D(S) = Σ det(M_S)^(−1/p)（p：その式の項の数）。配置は I で選ぶ"
    "選び方", sprintf("交換法（修正 Fedorov 法）。始め方 %d 通り（乱数の種 %d）", study.options.starts, study.options.seed)
    "必ず計測・計測しない", sprintf("必ず計測する Mark %d 点（どの数の配置にも入れる）・計測しない Mark %d 点（選ばないが N には入れる）", ...
        nRequired, nExcluded)
    ];
end
