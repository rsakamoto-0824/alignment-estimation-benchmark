function sweep = sweepHighOrder(wafers, settings, options)
%SWEEPHIGHORDER Shot 高次補正の正則化の強さ λ・Huber の c を変えて計算し、補正残差の推移を求める（λ・c を選ぶ目安）。
%   sweep = alignest.sweepHighOrder(wafers, settings, lambda=[0, 0.01, 0.1, 1], huberTuning=[...], progressFcn=...)
%   wafers・settings：alignest.shotHighOrder と同じ。lambda：λ の値、huberTuning：Huber の c の値（どちらか一方は空でよい。
%   空の方は設定の値のまま。両方を与えると、すべての組み合わせを計算する）。
%   λ を変えるとき、正則化が「なし」なら L2 にする（λ = 0 は正則化なしと同じ）。c を変えるとき、損失関数を Huber にする。
%   progressFcn(済んだ数, 全体の数, 説明)（省略可）が false を返すと、そこで止める（済んだ値までの結果を返す）。
%   値ごとに alignest.shotHighOrder で計算し（補正の段階の残差は求めない）、すべての Wafer の点で X・Y 別に次を求める：
%   - 当てはめた残差（高次補正の残差）：|平均|+3σ・|残差| の 95% 点・中央値・RMS（fit…）
%   - 1点抜きの予測の誤差（その点を除いて当てはめたときの、その点の誤差。result.points の looResidual）：同じ値（loo…）
%   値どうしを同じ点で比べるため、どの値でも求められた点だけを使う（当てはめた残差と 1点抜きの誤差で別に数える。
%   n・nLoo）。当てはめた残差は λ が小さいほど小さく見える（その点に合わせ込む）ので、λ・c は 1点抜きの誤差で選ぶ。
%   sweep.table：値ごと・軸ごとの行（lambda・huberTuning・axis・n・fitMeanPlus3Sigma・fitP95・fitMedian・fitRms・nLoo・
%   looMeanPlus3Sigma・looP95・looMedian・looRms・nTerms（絞った後の使う項の数）・skipped（補正しなかった k の組の数）・note）
%   sweep.parameter："lambda"・"huberTuning"・"both"、sweep.lambda・huberTuning：スイープした値、sweep.regularization・loss：
%   計算に使った正則化の種類と損失関数、sweep.description：基の設定の説明、sweep.cancelled：途中で止めたか、
%   sweep.nRuns：計算した値の組の数
arguments
    wafers struct
    settings struct
    options.lambda double = zeros(1, 0)
    options.huberTuning double = zeros(1, 0)
    options.progressFcn = []
end
MAX_RUNS = 400;   % 計算する値の組の上限（細かすぎる刻みで終わらなくならないように）
AXIS_NAMES = ["X", "Y"];
COLUMN_NAMES = ["lambda", "huberTuning", "axis", "n", "fitMeanPlus3Sigma", "fitP95", "fitMedian", "fitRms", "nLoo", ...
    "looMeanPlus3Sigma", "looP95", "looMedian", "looRms", "nTerms", "skipped", "note"];
base = alignest.highOrderOptions(settings);
lambdas = reshape(double(options.lambda), 1, []);
tunings = reshape(double(options.huberTuning), 1, []);
if isempty(lambdas) && isempty(tunings)
    error('alignest:highOrderSweep', 'スイープする λ か c の値を1つ以上入れてください。');
end
if any(~isfinite(lambdas) | lambdas < 0)
    error('alignest:highOrderSweep', 'λ は 0 以上の数にしてください。');
end
if any(~isfinite(tunings) | tunings <= 0)
    error('alignest:highOrderSweep', 'Huber の c は正の数にしてください。');
end
if ~isempty(lambdas) && ~isempty(tunings)
    parameter = "both";
elseif ~isempty(lambdas)
    parameter = "lambda";
else
    parameter = "huberTuning";
end
regularization = base.regularization;
if ~isempty(lambdas) && regularization == "none"
    regularization = "l2";
end
loss = base.loss;
if ~isempty(tunings)
    loss = "huber";
end
if isempty(lambdas)
    lambdas = base.lambda;
end
if isempty(tunings)
    tunings = base.huberTuning;
end
[lambdaGrid, tuningGrid] = ndgrid(lambdas, tunings);
lambdaGrid = lambdaGrid(:);   % 値の組ごとの λ・c（λ が速く変わる順）
tuningGrid = tuningGrid(:);
nRuns = numel(lambdaGrid);
if nRuns > MAX_RUNS
    error('alignest:highOrderSweep', ['値の組が %d 通りになります。%d 通り以下になるように、範囲を狭めるか刻みを' ...
        '大きくしてください。'], nRuns, MAX_RUNS);
end
[residuals, looResiduals] = deal(cell(nRuns, 1));
[nTerms, skipped] = deal(nan(nRuns, 1));
note = strings(nRuns, 1);
done = 0;
cancelled = false;
for r = 1:nRuns
    current = settings;
    current.highOrder.lambda = lambdaGrid(r);
    current.highOrder.huberTuning = tuningGrid(r);
    current.highOrder.regularization = regularization;
    current.highOrder.loss = loss;
    if isfield(current.highOrder, "l2")
        current.highOrder = rmfield(current.highOrder, "l2");   % 以前の設定の L2 のオン・オフ（regularization で決める）
    end
    try
        result = alignest.shotHighOrder(wafers, current, stages=false);
        residuals{r} = [result.points.residualX, result.points.residualY];
        looResiduals{r} = [result.points.looResidualX, result.points.looResidualY];
        nTerms(r) = nnz(result.terms.used);
        skipped(r) = sum(result.summary.skipped(result.summary.wafer == "すべての Wafer"), 'omitnan');
        if skipped(r) > 0
            note(r) = sprintf("補正しなかった k の組 %d（X・Y の合計）", skipped(r));
        end
    catch err
        note(r) = "計算できませんでした：" + string(err.message);
    end
    done = r;
    if ~isempty(options.progressFcn) && ~options.progressFcn(r, nRuns, runText(lambdaGrid(r), tuningGrid(r), parameter))
        cancelled = r < nRuns;
        break
    end
end
% どの値でも求められた点だけで比べる（計算できなかった値は除く）
computed = find(~cellfun(@isempty, residuals(1:done))).';
parts = cell(numel(computed), 2);
for a = 1:2
    fitCommon = true;
    looCommon = true;
    for r = computed
        fitCommon = fitCommon & isfinite(residuals{r}(:, a));
        looCommon = looCommon & isfinite(looResiduals{r}(:, a));
    end
    for j = 1:numel(computed)
        r = computed(j);
        fitStats = statistics(residuals{r}(fitCommon, a));
        looStats = statistics(looResiduals{r}(looCommon, a));
        parts{j, a} = table(lambdaGrid(r), tuningGrid(r), AXIS_NAMES(a), nnz(fitCommon), fitStats(1), fitStats(2), ...
            fitStats(3), fitStats(4), nnz(looCommon), looStats(1), looStats(2), looStats(3), looStats(4), nTerms(r), ...
            skipped(r), note(r), 'VariableNames', COLUMN_NAMES);
    end
end
% 計算できなかった値は、軸を空にして理由だけの行にする
failed = reshape(setdiff(1:done, computed), [], 1);
blank = nan(numel(failed), 1);
failedRows = table(lambdaGrid(failed), tuningGrid(failed), strings(numel(failed), 1), zeros(numel(failed), 1), blank, ...
    blank, blank, blank, zeros(numel(failed), 1), blank, blank, blank, blank, nTerms(failed), skipped(failed), ...
    note(failed), 'VariableNames', COLUMN_NAMES);
sweep.table = [vertcat(parts{:, 1}); vertcat(parts{:, 2}); failedRows];
sweep.parameter = parameter;
sweep.lambda = lambdas;
sweep.huberTuning = tunings;
sweep.regularization = regularization;
sweep.loss = loss;
sweep.description = base.description;
sweep.cancelled = cancelled;
sweep.nRuns = done;
end

function values = statistics(residual)
% [|平均|+3σ, |残差| の 95% 点, |残差| の中央値, RMS]（点が無ければ NaN。|平均|+3σ は2点以上）
values = nan(1, 4);
if isempty(residual)
    return
end
if numel(residual) >= 2
    values(1) = abs(mean(residual)) + 3 * std(residual);
end
magnitude = abs(residual);
values(2) = alignest.stats.percentile(magnitude, 95);
values(3) = median(magnitude);
values(4) = sqrt(mean(residual .^ 2));
end

function text = runText(lambda, tuning, parameter)
% 進み具合の説明（計算した値）
switch parameter
    case "lambda"
        text = sprintf("λ = %g", lambda);
    case "huberTuning"
        text = sprintf("c = %g", tuning);
    otherwise
        text = sprintf("λ = %g、c = %g", lambda, tuning);
end
end
