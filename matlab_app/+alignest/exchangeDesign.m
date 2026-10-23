function [selected, criterion, violation] = exchangeDesign(blocks, nSelect, labels, slack, stream, nStarts, maxIterations, options)
%EXCHANGEDESIGN 制約付きの最適計画（I 最適・D 最適）を交換法（Fedorov 型）で探す。Shot 単位・Mark 単位で使える。
%   [selected, criterion, violation] = alignest.exchangeDesign(blocks, nSelect, labels, slack, stream, nStarts, ...
%       maxIterations, criterion="D", fixed=..., group=..., minPerGroup=1)
%   blocks{c}  : 候補 c の基底の行（候補の全 Mark で正規直交化した XY 多項式。Shot 単位なら Shot の Mark の行、
%                Mark 単位なら1行）
%   labels     : 候補 × 制約の種類 の区分番号（同心円・象限・Scan 方向・Mark 番号。制約なしなら 0 列）。
%                各区分の数を、全候補に占める割合 × 選ぶ数 ± slack に収める（alignest.shotGroupBounds）
%   options.criterion  ："I"（tr(M⁻¹) を小さく）・"D"（det(M) を大きく、det(M)^(−1/p) を小さく）
%   options.fixed      ：必ず選ぶ候補（論理ベクトル。交換で外さない）
%   options.group      ：候補のまとまり（例：Mark の Shot 番号）。minPerGroup とともに、まとまりごとに
%                        minPerGroup 個以上を選ぶ（全 Shot で必ず1点を計測する Mark 単位の計画）。空なら使わない
%   制約を満たす初期配置から始め、違反を増やさず、まとまりの最小数を割らない交換だけを受け入れる。
%   初期配置を nStarts 回変えて最良を採る。criterion は選んだ組の基準値（I：tr(M⁻¹)、D：det(M)^(−1/p)）。
%   制約付き I 最適の Shot 単位の計画は、以前の結果と同じにするため alignest.constrainedIOptimal を使う。
arguments
    blocks cell
    nSelect (1, 1) double
    labels double
    slack (1, 1) double
    stream
    nStarts (1, 1) double
    maxIterations (1, 1) double
    options.criterion (1, 1) string {mustBeMember(options.criterion, ["I", "D"])} = "D"
    options.fixed logical = false(0, 1)
    options.group double = zeros(0, 1)
    options.minPerGroup (1, 1) double = 1
end
REGULARIZATION = 1e-10;
nCandidates = numel(blocks);
fixed = options.fixed(:);
if isempty(fixed)
    fixed = false(nCandidates, 1);
end
group = options.group(:);
useGroups = ~isempty(group);
nParams = size(blocks{1}, 2);
singleRows = all(cellfun(@(block) size(block, 1) == 1, blocks));
stacked = vertcat(blocks{:});
rowsOf = cell(nCandidates, 1);
offset = 0;
for c = 1:nCandidates
    rowsOf{c} = offset + (1:size(blocks{c}, 1));
    offset = offset + size(blocks{c}, 1);
end
information = zeros(nParams, nParams, nCandidates);
for c = 1:nCandidates
    information(:, :, c) = blocks{c}.' * blocks{c};
end
bounds = alignest.shotGroupBounds(labels, nSelect, slack);
context = struct("information", information, "stacked", stacked, "rowsOf", {rowsOf}, "labels", labels, ...
    "bounds", bounds, "fixed", fixed, "group", group, "useGroups", useGroups, "minPerGroup", options.minPerGroup, ...
    "criterion", options.criterion, "singleRows", singleRows, "regularization", REGULARIZATION);
bestSelected = [];
bestValue = Inf;
bestViolation = Inf;
for start = 1:nStarts
    if useGroups
        [current, currentViolation] = initialGroupedDesign(nSelect, labels, bounds, group, options.minPerGroup, fixed, stream);
    else
        [current, currentViolation] = alignest.randomFeasibleShots(nCandidates, nSelect, labels, slack, stream, fixed);
    end
    total = sum(information(:, :, current), 3);
    value = designValue(total + REGULARIZATION * eye(nParams), options.criterion);
    for iteration = 1:maxIterations
        [outC, inC, newValue, newViolation] = bestSwap(context, current, currentViolation, total, value);
        if isempty(outC)
            break
        end
        current(outC) = false;
        current(inC) = true;
        total = total - information(:, :, outC) + information(:, :, inC);
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
violation = bestViolation;
criterion = bestValue;
if options.criterion == "D" && isfinite(bestValue)
    criterion = exp(bestValue / nParams);   % −log det(M) → det(M)^(−1/p)
end
end

function [bestOut, bestIn, bestValue, bestViolation] = bestSwap(context, current, currentViolation, total, currentValue)
% 1つ外して1つ入れる交換のうち、基準が最も良くなるもの（違反を増やさず、まとまりの最小数を割らない）
bestOut = [];
bestIn = [];
bestValue = currentValue;
bestViolation = currentViolation;
nParams = size(total, 1);
others = find(~current);
if context.useGroups
    counts = accumarray(context.group(current), 1, [max(context.group), 1]);
end
for outC = find(current & ~context.fixed).'
    violations = swapViolations(context.labels, context.bounds, current, outC, others);
    allowed = violations <= currentViolation;
    if context.useGroups && counts(context.group(outC)) <= context.minPerGroup
        allowed = allowed & context.group(others) == context.group(outC);   % そのまとまりの別の候補とだけ入れ替える
    end
    if ~any(allowed)
        continue
    end
    reduced = total - context.information(:, :, outC) + context.regularization * eye(nParams);
    [upperFactor, failed] = chol(reduced);
    candidates = others(allowed);
    candidateViolations = violations(allowed);
    if failed
        values = arrayfun(@(inC) designValue(reduced + context.information(:, :, inC), context.criterion), candidates);
    else
        inverseFactor = upperFactor \ eye(nParams);
        inverse = inverseFactor * inverseFactor.';
        values = swapValues(context, candidates, inverse, upperFactor);
    end
    for k = 1:numel(candidates)
        if candidateViolations(k) < bestViolation || (candidateViolations(k) == bestViolation && ...
                values(k) < bestValue - 1e-12 * abs(bestValue))
            bestOut = outC;
            bestIn = candidates(k);
            bestValue = values(k);
            bestViolation = candidateViolations(k);
        end
    end
end
end

function values = swapValues(context, candidates, inverse, upperFactor)
% 外した後の M_o に候補 B を足したときの基準（Woodbury の式・行列式の補題）
%   I：tr((M_o + BᵀB)⁻¹) = tr(M_o⁻¹) − tr((I + B M_o⁻¹ Bᵀ)⁻¹ B M_o⁻² Bᵀ)
%   D：−log det(M_o + BᵀB) = −log det(M_o) − log det(I + B M_o⁻¹ Bᵀ)
logDetReduced = 2 * sum(log(diag(upperFactor)));
traceInverse = trace(inverse);
if context.singleRows
    rows = context.stacked(cell2mat(context.rowsOf(candidates)), :);
    projected = rows * inverse;
    leverage = sum(projected .* rows, 2);
    if context.criterion == "I"
        values = traceInverse - sum(projected .^ 2, 2) ./ (1 + leverage);
    else
        values = -logDetReduced - log1p(leverage);
    end
    return
end
values = zeros(numel(candidates), 1);
for k = 1:numel(candidates)
    rows = context.stacked(context.rowsOf{candidates(k)}, :);
    projected = rows * inverse;
    capacitance = eye(size(rows, 1)) + projected * rows.';
    if context.criterion == "I"
        values(k) = traceInverse - trace(capacitance \ (projected * projected.'));
    else
        values(k) = -logDetReduced - 2 * sum(log(diag(chol(capacitance))));
    end
end
end

function value = designValue(information, criterion)
% I：tr(M⁻¹)、D：−log det(M)（どちらも小さいほど良い）。特異なら Inf
[upperFactor, failed] = chol(information);
if failed
    value = Inf;
    return
end
if criterion == "I"
    inverseFactor = upperFactor \ eye(size(information));
    value = sum(inverseFactor .^ 2, 'all');
else
    value = -2 * sum(log(diag(upperFactor)));
end
end

function violations = swapViolations(labels, bounds, current, outC, others)
% outC を外して others の各候補を入れたときの違反量（alignest.constrainedIOptimal と同じ数え方）
violations = zeros(numel(others), 1);
for p = 1:numel(bounds)
    counts = accumarray(labels(current, p), 1, [numel(bounds(p).lower), 1]);
    counts(labels(outC, p)) = counts(labels(outC, p)) - 1;
    penalty = max(0, bounds(p).lower - counts) + max(0, counts - bounds(p).upper);
    penaltyPlus = max(0, bounds(p).lower - counts - 1) + max(0, counts + 1 - bounds(p).upper);
    violations = violations + sum(penalty) + (penaltyPlus(labels(others, p)) - penalty(labels(others, p)));
end
end

function [selected, violation] = initialGroupedDesign(nSelect, labels, bounds, group, minPerGroup, fixed, stream)
% まとまりごとに minPerGroup 個を選び（区分の不足が大きい候補から）、残りを区分の不足が大きい候補から足す。
% そのあと、違反を増やさずまとまりの最小数を割らない入れ替えをランダムにくり返して違反を減らす
MAX_TRIES = 5000;
nCandidates = numel(group);
selected = fixed;
order = randperm(stream, max(group));
for g = order
    members = find(group == g & ~selected);
    need = minPerGroup - nnz(selected & group == g);
    for k = 1:need
        if isempty(members)
            break
        end
        pick = members(bestByDeficit(members, selected, labels, bounds, stream));
        selected(pick) = true;
        members(members == pick) = [];
    end
end
while nnz(selected) < nSelect
    free = find(~selected);
    selected(free(bestByDeficit(free, selected, labels, bounds, stream))) = true;
end
violation = alignest.shotGroupViolation(selected, labels, bounds);
for trial = 1:MAX_TRIES
    if violation == 0
        break
    end
    inside = find(selected & ~fixed);
    outside = find(~selected);
    outC = inside(randi(stream, numel(inside)));
    if nnz(selected & group == group(outC)) <= minPerGroup
        outside = outside(group(outside) == group(outC));
        if isempty(outside)
            continue
        end
    end
    candidate = selected;
    candidate(outC) = false;
    candidate(outside(randi(stream, numel(outside)))) = true;
    candidateViolation = alignest.shotGroupViolation(candidate, labels, bounds);
    if candidateViolation <= violation
        selected = candidate;
        violation = candidateViolation;
    end
end
if nnz(selected) ~= nSelect || nCandidates == 0
    error('alignest:exchangeDesign', '初期配置を作れませんでした（選ぶ数 %d・候補 %d）。', nSelect, nCandidates);
end
end

function position = bestByDeficit(members, selected, labels, bounds, stream)
% 区分の上限までの余裕が最も大きい（不足している）候補を選ぶ（同じならランダム）
if isempty(bounds)
    position = randi(stream, numel(members));
    return
end
room = zeros(numel(members), 1);
for p = 1:numel(bounds)
    counts = accumarray(labels(selected, p), 1, [numel(bounds(p).lower), 1]);
    remaining = bounds(p).upper - counts;
    room = room + remaining(labels(members, p));
end
best = find(room == max(room));
position = best(randi(stream, numel(best)));
end
