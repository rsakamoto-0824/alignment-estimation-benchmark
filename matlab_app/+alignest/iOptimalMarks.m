function layouts = iOptimalMarks(designs, required, counts, options)
%IOPTIMALMARKS 候補の Mark から、計測する Mark の数ごとに I 最適計画の配置を選ぶ（「8. Mark配置の最適化」）。
%   layouts = alignest.iOptimalMarks(designs, required, counts, starts=5, seed=1, progressFcn=...)
%   designs：補正の式ごとの設計行列のセル配列（{dx の式, dy の式}。候補の数 × 項の数。列は使う項）。
%   required：必ず計測する Mark（候補の数 × 1 の logical）。どの数の配置にも必ず入れる。
%   counts：配置を選ぶ Mark の数（昇順。必ず計測する Mark の数以上・候補の数以下）。
%   I 基準（平均の予測の分散。小さいほどよい）：式ごとに、選んだ Mark で最小二乗で当てはめたときの、すべての候補の Mark の
%   位置での予測の分散の平均（計測のばらつきの分散を 1 とする）を足した値
%     I(S) = Σ_式 trace(M_S^(-1) W)、M_S = F_S' F_S（選んだ Mark の行）、W = F' F / N（すべての候補の行の平均）
%   すべての候補を計測したときは Σ_式 p / N（p：項の数、N：候補の数）。I 効率 = すべての候補を計測したときの I ÷ その配置の I
%   （すべての候補を計測すると 100%）。式ごとの I 効率も出す。列の大きさをそろえても I は変わらない（計算のときにそろえる）。
%   選び方：Mark の数ごとに、次の始め方から交換法（修正 Fedorov 法：選んだ Mark を1つずつ、I が最も小さくなる候補と入れ替え、
%   よくならなくなるまで繰り返す。必ず計測する Mark は入れ替えない）で解き、最もよい配置を使う（数ごとに解き直すので、
%   数が1つ違う配置どうしで Mark が入れ替わることがある）。
%   - 1つ前の数の配置に、I が最も小さくなる Mark を足した配置
%   - 必ず計測する Mark から、I が最も小さくなる Mark を1つずつ足した配置
%   - 必ず計測する Mark と乱数で選んだ Mark に、I が最も小さくなる Mark を足した配置（starts − 2 通り。乱数の種 seed）
%   項が決まらない（M_S が特異）配置は、M_S にわずかな値（RIDGE_RATIO）を足して I を求める（大きな I になり、交換で外れる）。
%   progressFcn(済んだ数, 全体の数, 説明) が false を返すと、そこで止める（済んだ数までを返す）。
%   layouts：counts（K × 1）・selected（候補の数 × K の logical）・criterion（I。K × 1）・efficiency（I 効率 [%]。K × 1）・
%   axisEfficiency（式ごとの I 効率 [%]。K × 式の数）・changed（1つ前の数の配置に無い Mark の数。K × 1）・fullCriterion
%   （すべての候補を計測したときの I）・cancelled。
arguments
    designs cell
    required logical
    counts double
    options.starts (1, 1) double {mustBePositive, mustBeInteger} = 5
    options.seed (1, 1) double {mustBeNonnegative, mustBeInteger} = 1
    options.progressFcn = []
end
RIDGE_RATIO = 1e-9;     % 項が決まらない配置でも I を求めるために M に足す値（M の対角の平均に対する比）
MAX_PASSES = 100;       % 交換法で全部の Mark を見直す回数の上限
TOLERANCE = 1e-10;      % I がこの割合より小さくしかよくならなければ入れ替えない
nAxes = numel(designs);
n = size(designs{1}, 1);
required = reshape(required, [], 1);
counts = reshape(counts, [], 1);
if numel(required) ~= n || any(cellfun(@(F) size(F, 1), designs) ~= n)
    error('alignest:markLayout', '候補の数と、設計行列の行・必ず計測する Mark の数が合いません。');
end
if isempty(counts) || any(counts ~= round(counts)) || any(diff(counts) <= 0) || counts(1) < nnz(required) || counts(end) > n
    error('alignest:markLayout', ['配置を選ぶ Mark の数は、必ず計測する Mark の数（%d）以上・候補の数（%d）以下の' ...
        '整数を小さい順に並べてください。'], nnz(required), n);
end
% 列の大きさをそろえる（I は変わらない。逆行列の計算を安定させるため）
F = cell(1, nAxes);
W = cell(1, nAxes);
ridge = zeros(1, nAxes);
fullCriterion = 0;
for a = 1:nAxes
    scale = sqrt(mean(designs{a} .^ 2, 1));
    scale(scale == 0) = 1;
    F{a} = designs{a} ./ scale;
    W{a} = (F{a}.' * F{a}) / n;
    p = size(F{a}, 2);
    ridge(a) = RIDGE_RATIO * trace(F{a}.' * F{a}) / max(p, 1);
    fullCriterion = fullCriterion + p / n;
end
K = numel(counts);
layouts = struct("counts", counts, "selected", false(n, K), "criterion", nan(K, 1), "efficiency", nan(K, 1), ...
    "axisEfficiency", nan(K, nAxes), "changed", zeros(K, 1), "fullCriterion", fullCriterion, "cancelled", false);
stream = RandStream('mt19937ar', 'Seed', options.seed);
previous = [];
for k = 1:K
    count = counts(k);
    starts = cell(1, 0);
    if ~isempty(previous)
        starts{end + 1} = greedyFill(previous, count, F, W, ridge); %#ok<AGROW>
    end
    starts{end + 1} = greedyFill(required, count, F, W, ridge); %#ok<AGROW>
    free = find(~required);
    for s = numel(starts) + 1:options.starts
        seedSet = required;
        nRandom = floor((count - nnz(required)) / 2);
        seedSet(free(randperm(stream, numel(free), nRandom))) = true;
        starts{end + 1} = greedyFill(seedSet, count, F, W, ridge); %#ok<AGROW>
    end
    best = [];
    bestValue = Inf;
    for s = 1:numel(starts)
        [selection, value] = exchange(starts{s}, required, F, W, ridge, MAX_PASSES, TOLERANCE);
        if value < bestValue * (1 - TOLERANCE)
            best = selection;
            bestValue = value;
        end
    end
    layouts.selected(:, k) = best;
    layouts.criterion(k) = bestValue;
    layouts.efficiency(k) = 100 * fullCriterion / bestValue;
    for a = 1:nAxes
        p = size(F{a}, 2);
        layouts.axisEfficiency(k, a) = 100 * (p / n) / criterionOf(best, F(a), W(a), ridge(a));
    end
    if ~isempty(previous)
        layouts.changed(k) = nnz(best & ~previous);
    end
    previous = best;
    if ~isempty(options.progressFcn) && ~options.progressFcn(k, K, sprintf("%d 点", count))
        layouts.cancelled = k < K;
        keep = 1:k;
        layouts.counts = layouts.counts(keep);
        layouts.selected = layouts.selected(:, keep);
        layouts.criterion = layouts.criterion(keep);
        layouts.efficiency = layouts.efficiency(keep);
        layouts.axisEfficiency = layouts.axisEfficiency(keep, :);
        layouts.changed = layouts.changed(keep);
        break
    end
end
end

function value = criterionOf(selection, F, W, ridge)
% I = Σ_式 trace((F_S' F_S + ridge I)^(-1) W)
value = 0;
for a = 1:numel(F)
    Fs = F{a}(selection, :);
    M = Fs.' * Fs + ridge(a) * eye(size(Fs, 2));
    value = value + trace(M \ W{a});
end
end

function selection = greedyFill(selection, count, F, W, ridge)
% I が最も小さくなる Mark を1つずつ足して count 点にする（足す前の I から、足したときの減り方
% (f' A W A f) / (1 + f' A f) が最も大きい候補。A = M^(-1)）
while nnz(selection) < count
    gain = zeros(numel(selection), 1);
    for a = 1:numel(F)
        Fs = F{a}(selection, :);
        G = F{a} / (Fs.' * Fs + ridge(a) * eye(size(Fs, 2)));   % 候補ごとの f' A（M は対称）
        gain = gain + sum((G * W{a}) .* G, 2) ./ (1 + sum(G .* F{a}, 2));
    end
    gain(selection) = -Inf;
    [~, pick] = max(gain);
    selection(pick) = true;
end
end

function [selection, value] = exchange(selection, fixed, F, W, ridge, maxPasses, tolerance)
% 修正 Fedorov 法：選んだ Mark（必ず計測する Mark を除く）を1つずつ、I が最も小さくなる候補と入れ替える。
% Mark i を抜いた M_(−i) の逆行列 A から、候補 j を足したときの I = trace(A W) − (f_j' A W A f_j) / (1 + f_j' A f_j)
nAxes = numel(F);
value = criterionOf(selection, F, W, ridge);
for pass = 1:maxPasses
    improved = false;
    for i = find(selection & ~fixed).'
        others = selection;
        others(i) = false;
        candidateValue = zeros(numel(selection), 1);
        for a = 1:nAxes
            Fs = F{a}(others, :);
            M = Fs.' * Fs + ridge(a) * eye(size(Fs, 2));
            G = F{a} / M;   % 候補ごとの f' A（M は対称）
            candidateValue = candidateValue + trace(M \ W{a}) - sum((G * W{a}) .* G, 2) ./ (1 + sum(G .* F{a}, 2));
        end
        candidateValue(others) = Inf;   % 選んでいる Mark（i のほか）は足せない
        [bestValue, pick] = min(candidateValue);
        if pick ~= i && bestValue < value * (1 - tolerance)
            selection = others;
            selection(pick) = true;
            value = bestValue;
            improved = true;
        end
    end
    if ~improved
        break
    end
end
value = criterionOf(selection, F, W, ridge);   % 入れ替えの式の丸めの差を除いて求め直す
end
