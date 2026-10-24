function fit = gprFit(gp, y, basis, start)
%GPRFIT 対数周辺尤度を最大にするハイパーパラメータを求め、その値で条件づける。
%   start を省略すると fitrgp と同じ考え方の初期値から始める（Backfitting では前回の値から始める）。
FAILED_OBJECTIVE = 1e20;
[initial, lower, upper] = alignest.models.gprInitialParams(gp, y);
if nargin < 4 || isempty(start)
    start = initial;
end
start = min(max(start(:), lower), upper);
objective = @(params) alignest.models.gprObjective(gp, params, y, basis);
[logParams, value, info] = alignest.optim.minimizeBox(objective, start, lower, upper, ...
    maxIterations=gp.maxIterations);
if ~isfinite(value) || value >= FAILED_OBJECTIVE
    logParams = start;
end
fit = alignest.models.gprCondition(gp, logParams, y, basis);
fit.nll = value;
fit.converged = info.converged;
fit.nEvaluations = info.evaluations;
end
