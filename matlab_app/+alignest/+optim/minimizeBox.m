function [x, fval, info] = minimizeBox(objective, x0, lower, upper, options)
%MINIMIZEBOX 上下限つきの最小化（射影つき L-BFGS）。MATLAB 本体だけで動く（Optimization Toolbox 不要）。
%   [x, fval, info] = alignest.optim.minimizeBox(objective, x0, lower, upper, options)
%   objective(x) は [値, 勾配] を返す。options.gradient = "forward" なら値だけを使い、勾配は前進差分で求める。
%   止め方は SciPy の L-BFGS-B（Python 版の評価で使った方法）に合わせる：
%     射影した勾配の最大値 ≤ gradientTolerance、または値の相対減少 ≤ functionTolerance で収束。
%   L-BFGS-B の一般化コーシー点の探索の代わりに、上下限に張り付いた変数を固定して残りを L-BFGS で動かし、
%   上下限へ射影しながら Armijo 条件で歩幅を半分ずつにする（簡略版）。収束した先は同じ停留点になる。
arguments
    objective (1, 1) function_handle
    x0 (:, 1) double
    lower (:, 1) double
    upper (:, 1) double
    options.maxIterations (1, 1) double = 300
    options.maxEvaluations (1, 1) double = 15000
    options.memory (1, 1) double = 10
    options.gradientTolerance (1, 1) double = 1e-5
    options.functionTolerance (1, 1) double = 2.220446049250313e-09
    options.maxLineSearch (1, 1) double = 20
    options.gradient (1, 1) string = "analytic"
    options.finiteDifferenceStep (1, 1) double = 1e-4
end
ARMIJO = 1e-4;
nVariables = numel(x0);
x = min(max(x0, lower), upper);
nEvaluations = 0;
[fval, gradient] = evaluate(x);
pairsS = zeros(nVariables, 0);
pairsY = zeros(nVariables, 0);
converged = false;
message = "反復の上限に達した";
iteration = 0;
while iteration < options.maxIterations
    iteration = iteration + 1;
    projected = x - min(max(x - gradient, lower), upper);
    if max(abs(projected)) <= options.gradientTolerance
        converged = true;
        message = "勾配が十分小さい";
        break
    end
    % 上下限に張り付き、勾配が外向きの変数は動かさない
    fixed = (x <= lower & gradient > 0) | (x >= upper & gradient < 0);
    free = ~fixed;
    direction = zeros(nVariables, 1);
    direction(free) = -twoLoop(gradient(free), pairsS(free, :), pairsY(free, :));
    if gradient.' * direction >= 0
        pairsS = zeros(nVariables, 0);
        pairsY = zeros(nVariables, 0);
        direction = zeros(nVariables, 1);
        direction(free) = -gradient(free);
    end
    if isempty(pairsS)
        step = min(1, 1 / max(norm(direction), eps));
    else
        step = 1;
    end
    accepted = false;
    for trial = 1:options.maxLineSearch
        candidate = min(max(x + step * direction, lower), upper);
        if all(candidate == x) || nEvaluations >= options.maxEvaluations
            break
        end
        [candidateValue, candidateGradient] = evaluate(candidate);
        if candidateValue <= fval + ARMIJO * gradient.' * (candidate - x)
            accepted = true;
            break
        end
        step = step / 2;
    end
    if ~accepted
        if ~isempty(pairsS)
            % 準ニュートンの近似が悪いときは最急降下からやり直す
            pairsS = zeros(nVariables, 0);
            pairsY = zeros(nVariables, 0);
            continue
        end
        message = "直線探索で値が下がらない";
        converged = max(abs(projected)) <= 1e3 * options.gradientTolerance;
        break
    end
    s = candidate - x;
    y = candidateGradient - gradient;
    if s.' * y > eps * (y.' * y)
        pairsS = [pairsS, s]; %#ok<AGROW>
        pairsY = [pairsY, y]; %#ok<AGROW>
        if size(pairsS, 2) > options.memory
            pairsS(:, 1) = [];
            pairsY(:, 1) = [];
        end
    end
    previous = fval;
    x = candidate;
    fval = candidateValue;
    gradient = candidateGradient;
    if previous - fval <= options.functionTolerance * max([abs(previous), abs(fval), 1])
        converged = true;
        message = "値の減少が十分小さい";
        break
    end
    if nEvaluations >= options.maxEvaluations
        message = "評価回数の上限に達した";
        break
    end
end
info = struct("converged", converged, "message", message, "iterations", iteration, "evaluations", nEvaluations);

    function [value, grad] = evaluate(point)
        nEvaluations = nEvaluations + 1;
        if options.gradient == "forward"
            value = objective(point);
            grad = zeros(nVariables, 1);
            for k = 1:nVariables
                shifted = point;
                h = options.finiteDifferenceStep;
                if shifted(k) + h > upper(k)
                    h = -h;
                end
                shifted(k) = shifted(k) + h;
                grad(k) = (objective(shifted) - value) / h;
                nEvaluations = nEvaluations + 1;
            end
        else
            [value, grad] = objective(point);
            grad = grad(:);
        end
    end
end

function r = twoLoop(q, pairsS, pairsY)
% L-BFGS の2重ループ再帰で、逆ヘッセ行列の近似 × q を求める
curvature = sum(pairsS .* pairsY, 1);
keep = curvature > 0;
pairsS = pairsS(:, keep);
pairsY = pairsY(:, keep);
curvature = curvature(keep);
nPairs = size(pairsS, 2);
alpha = zeros(nPairs, 1);
for i = nPairs:-1:1
    alpha(i) = (pairsS(:, i).' * q) / curvature(i);
    q = q - alpha(i) * pairsY(:, i);
end
if nPairs > 0
    scale = curvature(end) / (pairsY(:, end).' * pairsY(:, end));
else
    scale = 1;
end
r = scale * q;
for i = 1:nPairs
    beta = (pairsY(:, i).' * r) / curvature(i);
    r = r + pairsS(:, i) * (alpha(i) - beta);
end
end
