function result = gamFitPredict(model, y, options)
%GAMFITPREDICT REML で平滑化パラメータ λ（平滑項ごと）を選んで GAM を当てはめ、評価点を推定する。
%   探索は log10 λ = −6〜6 の13点で最良の値から始め、−8〜8 の範囲で最小化する（Python 版と同じ）。
%   options.fixedLog10Lambda を与えると λ を選ばずにその値を使う（動作確認用）。
arguments
    model struct
    y (:, 1) double
    options.fixedLog10Lambda double = []
end
LOG10_LAMBDA_BOUNDS = [-8, 8];
START_GRID = linspace(-6, 6, 13);
FINITE_DIFFERENCE_STEP = 1e-4;
xty = model.design.' * y;
yty = y.' * y;
nSmooth = numel(model.penalties);
if isempty(options.fixedLog10Lambda)
    startScores = zeros(size(START_GRID));
    for k = 1:numel(START_GRID)
        startScores(k) = alignest.models.gamCriterion(model, repmat(START_GRID(k), nSmooth, 1), xty, yty);
    end
    [bestStartScore, bestStart] = min(startScores);
    start = repmat(START_GRID(bestStart), nSmooth, 1);
    objective = @(v) alignest.models.gamCriterion(model, v, xty, yty);
    [optimum, value] = alignest.optim.minimizeBox(objective, start, ...
        repmat(LOG10_LAMBDA_BOUNDS(1), nSmooth, 1), repmat(LOG10_LAMBDA_BOUNDS(2), nSmooth, 1), ...
        gradient="forward", finiteDifferenceStep=FINITE_DIFFERENCE_STEP);
    if isfinite(value) && value <= bestStartScore
        log10Lambda = optimum;
    else
        log10Lambda = start;
    end
else
    log10Lambda = options.fixedLog10Lambda(:);
end
[criterion, coef, edf] = alignest.models.gamCriterion(model, log10Lambda, xty, yty);
result.prediction = model.designTest * coef;
result.edf = edf;
result.log10Lambda = log10Lambda;
result.criterion = criterion;
end
