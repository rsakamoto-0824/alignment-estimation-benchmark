function [selected, criterion, violation] = constrainedIOptimal(blocks, nSelect, labels, slack, stream, nStarts, maxIterations)
%CONSTRAINEDIOPTIMAL 制約付き I 最適な Shot の組を交換法（Fedorov 型）で探す。
%   blocks{s}  : 候補 Shot s の Mark での基底（全候補 Mark で正規直交化した XY 多項式の行）
%   labels     : 候補 Shot × 制約の種類 の区分番号（同心円・象限・Scan方向。制約なしなら 0 列）
%   I 基準 tr(M⁻¹)（M = 選んだ Shot の情報行列の和）を小さくする。B が正規直交なので全 Mark の平均予測分散に比例する。
%   制約：各区分の Shot 数を、全候補に占める割合 × 選ぶ数 ± slack に収める。
%   制約を満たす初期配置から始め、違反を増やさない交換だけを受け入れる。初期配置を nStarts 回変えて最良を採る。
%   選んだ組・基準値（tr(M⁻¹)）・制約の違反量（0 なら満たす）を返す。
REGULARIZATION = 1e-10;
nCandidates = numel(blocks);
nParams = size(blocks{1}, 2);
information = zeros(nParams, nParams, nCandidates);
for s = 1:nCandidates
    information(:, :, s) = blocks{s}.' * blocks{s};
end
stacked = vertcat(blocks{:});
rowsOfShot = cell(nCandidates, 1);
offset = 0;
for s = 1:nCandidates
    rowsOfShot{s} = offset + (1:size(blocks{s}, 1));
    offset = offset + size(blocks{s}, 1);
end
bounds = alignest.shotGroupBounds(labels, nSelect, slack);
identity = eye(nParams);
context = struct("information", information, "stacked", stacked, "rowsOfShot", {rowsOfShot}, ...
    "labels", labels, "bounds", bounds, "regularization", REGULARIZATION);

bestSelected = [];
bestValue = Inf;
bestViolation = Inf;
for start = 1:nStarts
    [current, currentViolation] = alignest.randomFeasibleShots(nCandidates, nSelect, labels, slack, stream);
    information_ = sum(information(:, :, current), 3);
    value = iCriterion(information_ + REGULARIZATION * identity);
    for iteration = 1:maxIterations
        [outShot, inShot, newValue, newViolation] = bestSwap(context, current, currentViolation, information_, value);
        if isempty(outShot)
            break
        end
        current(outShot) = false;
        current(inShot) = true;
        information_ = information_ - information(:, :, outShot) + information(:, :, inShot);
        value = newValue;
        currentViolation = newViolation;
    end
    if currentViolation < bestViolation || (currentViolation == bestViolation && value < bestValue)
        bestSelected = current;
        bestValue = value;
        bestViolation = currentViolation;
    end
end
selected = find(bestSelected);
criterion = bestValue;
violation = bestViolation;
end

function [bestOut, bestIn, bestSwapValue, bestSwapViolation] = bestSwap(context, current, currentViolation, totalInformation, currentValue)
% 1つ外して1つ入れる交換のうち、I 基準が最も下がるものを探す
bestOut = [];
bestIn = [];
bestSwapValue = currentValue;
bestSwapViolation = currentViolation;
selectedShots = find(current);
others = find(~current);
for outShot = selectedShots.'
    reduced = totalInformation - context.information(:, :, outShot) + context.regularization * eye(size(totalInformation));
    [upperFactor, failed] = chol(reduced);
    violations = swapViolations(context.labels, context.bounds, current, outShot, others);
    allowed = violations <= currentViolation;
    if ~any(allowed)
        continue
    end
    if failed
        % 外すと情報行列が特異になる Shot は、入れる Shot ごとに直接計算する
        for inShot = others(allowed).'
            value = iCriterion(reduced + context.information(:, :, inShot));
            [bestOut, bestIn, bestSwapValue, bestSwapViolation] = keepBetter(value, outShot, inShot, ...
                violations(others == inShot), bestOut, bestIn, bestSwapValue, bestSwapViolation);
        end
        continue
    end
    inverseFactor = upperFactor \ eye(size(totalInformation));
    inverse = inverseFactor * inverseFactor.';
    traceInverse = trace(inverse);
    projected = context.stacked * inverse;
    % Woodbury の式：tr((M_o + BᵀB)⁻¹) = tr(M_o⁻¹) − tr((I + B M_o⁻¹ Bᵀ)⁻¹ B M_o⁻² Bᵀ)
    for position = find(allowed).'
        inShot = others(position);
        rows = context.rowsOfShot{inShot};
        blockProjected = projected(rows, :);
        capacitance = eye(numel(rows)) + blockProjected * context.stacked(rows, :).';
        value = traceInverse - trace(capacitance \ (blockProjected * blockProjected.'));
        [bestOut, bestIn, bestSwapValue, bestSwapViolation] = keepBetter(value, outShot, inShot, ...
            violations(position), bestOut, bestIn, bestSwapValue, bestSwapViolation);
    end
end
end

function [bestOut, bestIn, bestValue, bestViolation] = keepBetter(value, outShot, inShot, violation, bestOut, bestIn, bestValue, bestViolation)
if violation < bestViolation || (violation == bestViolation && value < bestValue - 1e-12 * abs(bestValue))
    bestOut = outShot;
    bestIn = inShot;
    bestValue = value;
    bestViolation = violation;
end
end

function value = iCriterion(information)
[upperFactor, failed] = chol(information);
if failed
    value = Inf;
    return
end
inverseFactor = upperFactor \ eye(size(information));
value = sum(inverseFactor .^ 2, 'all');
end

function violations = swapViolations(labels, bounds, current, outShot, others)
% outShot を外して others の各 Shot を入れたときの違反量（ベクトル）
violations = zeros(numel(others), 1);
for p = 1:numel(bounds)
    counts = accumarray(labels(current, p), 1, [numel(bounds(p).lower), 1]);
    counts(labels(outShot, p)) = counts(labels(outShot, p)) - 1;
    penalty = max(0, bounds(p).lower - counts) + max(0, counts - bounds(p).upper);
    penaltyPlus = max(0, bounds(p).lower - counts - 1) + max(0, counts + 1 - bounds(p).upper);
    violations = violations + sum(penalty) + (penaltyPlus(labels(others, p)) - penalty(labels(others, p)));
end
end
