function groupOf = rotationCriterionExchange(basis, interval, groupOf, nMaps, criterion, stream)
%ROTATIONCRITERIONEXCHANGE 計測マップの振り分けを、すべてのマップの I 基準・D 基準の和が小さくなるよう、点の入れ替えで
%   良くする（「8. 計測Mapローテ」の振り分け「I 最適」「D 最適」。交換法）。
%   groupOf = alignest.rotationCriterionExchange(basis, interval, groupOf, nMaps, criterion, stream)
%   basis：点ごとの基底の行（alignest.rotationCriterionBasis。点 × 項 p）。interval：点ごとの頻度（n 枚に1回の n）。
%   groupOf：点ごとの組（0 始まり。頻度 n の点を n 組に分けた番号。毎回計測する点は 0）。計測マップ m（1 始まり）は
%   (m − 1) を n で割った余りが組の番号の点を計測する。nMaps：計測マップの数。criterion："I"・"D"。stream：乱数。
%   マップ m の情報行列 M_m = Σ（マップで計測する点の基底の行 b）bᵀb。基準は I：tr(M⁻¹)、D：det(M)^(−1/p)（どちらも
%   小さいほど良い。alignest.designCriteria と同じ）。乱数の順に点 a を見て、同じ頻度の違う組の点 b と入れ替えたときの
%   すべてのマップの基準の和を求め（行列の1階の更新の式で、b について一度に）、最も小さくなる b と入れ替える（和が小さく
%   なるときだけ）。入れ替えが無くなるまで、最大 MAX_SWEEPS 回繰り返す。組の点の数は変わらない。点が項の数より少ない
%   マップは M が特異なので、小さな値 RIDGE を対角に足して計算する（入れ替えで点が増える向きに働く）。
MAX_SWEEPS = 10;
RIDGE = 1e-9;
TOLERANCE = 1e-10;   % これより小さい改善は入れ替えない（計算の誤差で入れ替え続けないように）
[nPoints, nParams] = size(basis);
interval = reshape(interval, [], 1);
groupOf = reshape(groupOf, [], 1);
information = cell(1, nMaps);
inverse = cell(1, nMaps);
value = zeros(1, nMaps);
for m = 1:nMaps
    measured = mod(m - 1, interval) == groupOf;
    information{m} = basis(measured, :).' * basis(measured, :);
    [inverse{m}, value(m)] = criterionOf(information{m}, criterion, RIDGE);
end
for sweep = 1:MAX_SWEEPS
    swapped = false;
    for a = randperm(stream, nPoints)
        n = interval(a);
        partners = find(interval == n & groupOf ~= groupOf(a));
        if n == 1 || isempty(partners)
            continue
        end
        mapsOfA = find(mod(0:nMaps - 1, n) == groupOf(a));
        rowA = basis(a, :);
        rowsB = basis(partners, :);
        change = zeros(numel(partners), 1);
        for m = mapsOfA   % a を除き b を足す
            change = change + changedValue(inverse{m}, value(m), repmat(rowA, numel(partners), 1), rowsB, ...
                criterion, nParams) - value(m);
        end
        partnerGroups = groupOf(partners);
        for g = reshape(unique(partnerGroups), 1, [])   % b の組のマップでは、b を除き a を足す
            inGroup = partnerGroups == g;
            for m = find(mod(0:nMaps - 1, n) == g)
                change(inGroup) = change(inGroup) + changedValue(inverse{m}, value(m), rowsB(inGroup, :), ...
                    repmat(rowA, nnz(inGroup), 1), criterion, nParams) - value(m);
            end
        end
        [best, k] = min(change);
        if ~(best < -TOLERANCE * max(1, sum(value)))
            continue
        end
        b = partners(k);
        [groupA, groupB] = deal(groupOf(a), groupOf(b));
        rowB = basis(b, :);
        for m = find(mod(0:nMaps - 1, n) == groupA)
            information{m} = information{m} - rowA.' * rowA + rowB.' * rowB;
            [inverse{m}, value(m)] = criterionOf(information{m}, criterion, RIDGE);
        end
        for m = find(mod(0:nMaps - 1, n) == groupB)
            information{m} = information{m} + rowA.' * rowA - rowB.' * rowB;
            [inverse{m}, value(m)] = criterionOf(information{m}, criterion, RIDGE);
        end
        groupOf([a, b]) = [groupB; groupA];
        swapped = true;
    end
    if ~swapped
        break
    end
end
end

function [inverse, value] = criterionOf(information, criterion, ridge)
% 情報行列の逆行列と基準の値（I：tr(M⁻¹)、D：det(M)^(−1/p)）。特異に近いときのため、対角に ridge を足す
nParams = size(information, 1);
regularized = (information + information.') / 2 + ridge * eye(nParams);
[factor, failed] = chol(regularized);
if failed
    inverse = pinv(regularized);
    value = Inf;
    return
end
inverse = factor \ (factor.' \ eye(nParams));
if criterion == "D"
    value = exp(-2 * sum(log(diag(factor))) / nParams);
else
    value = trace(inverse);
end
end

function newValue = changedValue(inverse, value, removeRows, addRows, criterion, nParams)
% 情報行列 M から removeRows の各行 r を除き、addRows の同じ行の a を足したときの基準（行ごと）。M⁻¹ = inverse、
% 今の基準 = value。D：det(M − rᵀr + aᵀa) = det(M) {(1 + d_a)(1 − d_r) + d_ra²}（d_a = a M⁻¹ aᵀ、d_r = r M⁻¹ rᵀ、
% d_ra = r M⁻¹ aᵀ）。I：a を足す・r を除く、の2回の1階の更新（Sherman–Morrison）で tr を求める
inverseAdd = addRows * inverse;          % a M⁻¹
inverseRemove = removeRows * inverse;    % r M⁻¹
dAdd = sum(inverseAdd .* addRows, 2);
dRemove = sum(inverseRemove .* removeRows, 2);
cross = sum(inverseAdd .* removeRows, 2);
if criterion == "D"
    ratio = (1 + dAdd) .* (1 - dRemove) + cross .^ 2;
    newValue = value * max(ratio, realmin) .^ (-1 / nParams);
    newValue(ratio <= 0) = Inf;
    return
end
afterAdd = value - sum(inverseAdd .^ 2, 2) ./ (1 + dAdd);
dRemoveAfter = dRemove - cross .^ 2 ./ (1 + dAdd);
squaredNorm = sum(inverseRemove .^ 2, 2) - 2 * cross .* sum(inverseAdd .* inverseRemove, 2) ./ (1 + dAdd) + ...
    cross .^ 2 .* sum(inverseAdd .^ 2, 2) ./ (1 + dAdd) .^ 2;   % |(M + aᵀa)⁻¹ rᵀ|²
newValue = afterAdd + squaredNorm ./ (1 - dRemoveAfter);
newValue(1 - dRemoveAfter <= 0) = Inf;
end
