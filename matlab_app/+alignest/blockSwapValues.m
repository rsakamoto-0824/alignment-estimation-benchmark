function values = blockSwapValues(slots, candidates, inverse, criterion, logDetReduced)
%BLOCKSWAPVALUES 交換法で、外した後の情報行列 M_o に候補の基底の行 B（複数行）を足したときの基準を、候補ごとにまとめて求める
%   （alignest.constrainedIOptimal・alignest.exchangeDesign の入れ替えの候補の評価）。
%   values = alignest.blockSwapValues(slots, candidates, inverse, criterion)
%   values = alignest.blockSwapValues(slots, candidates, inverse, "D", logDetReduced)
%   slots：候補の基底の行を行の番号ごとに並べたもの（alignest.blockSlots）。candidates：評価する候補の番号。
%   inverse：M_o⁻¹。criterion："I"・"D"。logDetReduced：log det(M_o)（D のとき）。
%   I：tr((M_o + BᵀB)⁻¹) = tr(M_o⁻¹) − tr((I + B M_o⁻¹ Bᵀ)⁻¹ B M_o⁻² Bᵀ)（Woodbury の式）
%   D：−log det(M_o + BᵀB) = −log det(M_o) − log det(I + B M_o⁻¹ Bᵀ)（行列式の補題）
%   C = I + B M_o⁻¹ Bᵀ を Cholesky 分解 C = L Lᵀ し、I は tr(M_o⁻¹) − ‖L⁻¹ B M_o⁻¹‖²、D は 2 Σ log diag(L) を使う。
%   候補を1つずつ解くと、候補の数だけ小さな行列の計算を繰り返して遅いので、C・L の同じ位置の値を全候補の列にして、
%   行の数だけの繰り返しでまとめて解く（C の固有値は 1 以上なので、Cholesky 分解は止まらない）。
%   values：候補ごとの基準（列ベクトル）。
if nargin < 5
    logDetReduced = 0;
end
nRows = numel(slots);
nCandidates = numel(candidates);
rows = cell(1, nRows);        % 各候補の i 行目 b_i（候補 × 項）
projected = cell(1, nRows);   % b_i M_o⁻¹（候補 × 項）
for i = 1:nRows
    rows{i} = slots{i}(candidates, :);
    projected{i} = rows{i} * inverse;
end
factor = cell(nRows, nRows);  % L の (i, j) の値（候補ごとの列）
logDiagonal = zeros(nCandidates, 1);
for j = 1:nRows
    pivot = 1 + sum(projected{j} .* rows{j}, 2);   % C(j, j) = 1 + b_j M_o⁻¹ b_jᵀ
    for k = 1:j - 1
        pivot = pivot - factor{j, k} .^ 2;
    end
    pivot = sqrt(pivot);
    factor{j, j} = pivot;
    logDiagonal = logDiagonal + log(pivot);
    for i = j + 1:nRows
        entry = sum(projected{i} .* rows{j}, 2);     % C(i, j) = b_i M_o⁻¹ b_jᵀ
        for k = 1:j - 1
            entry = entry - factor{i, k} .* factor{j, k};
        end
        factor{i, j} = entry ./ pivot;
    end
end
if criterion == "D"
    values = -logDetReduced - 2 * logDiagonal;
    return
end
values = repmat(trace(inverse), nCandidates, 1);
solved = cell(1, nRows);      % L⁻¹ B M_o⁻¹ の i 行目（前進代入）
for i = 1:nRows
    row = projected{i};
    for k = 1:i - 1
        row = row - factor{i, k} .* solved{k};
    end
    solved{i} = row ./ factor{i, i};
    values = values - sum(solved{i} .^ 2, 2);
end
end
