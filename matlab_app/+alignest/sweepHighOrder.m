function sweep = sweepHighOrder(wafers, settings, options)
%SWEEPHIGHORDER Shot 高次補正の正則化の強さ λ・Huber の c を変えて計算し、補正残差の推移を求める（λ・c を選ぶ目安）。
%   sweep = alignest.sweepHighOrder(wafers, settings, lambda=[0, 0.01, 0.1, 1], huberTuning=[...], progressFcn=...)
%   sweep = alignest.sweepHighOrder(..., resume=前の結果)   % 一時中断したスイープの続きを計算する
%   wafers・settings：alignest.shotHighOrder と同じ。lambda：λ の値、huberTuning：Huber の c の値（どちらか一方は空でよい。
%   空の方は設定の値のまま。両方を与えると、すべての組み合わせを計算する）。λ・c は X・Y で同じ値を計算し、結果を軸ごとに出す
%   （dx の式と dy の式は別に解くので、軸ごとに最もよい値を選べる）。
%   λ を変えるとき、正則化が「なし」の軸は L2 にする（λ = 0 は正則化なしと同じ）。c を変えるとき、損失関数を Huber にする。
%   c = 0 は LAD で計算する（Huber は c を小さくすると LAD に近づく）。
%   progressFcn(済んだ数, 全体の数, 説明)（省略可）が false を返すと、そこで止める（済んだ値までの結果を返す。sweep.cancelled。
%   resume に渡すと続きを計算する。値の並びが違うと止める）。
%   値ごとに alignest.shotHighOrder で計算し（補正の段階の残差は求めない）、すべての Wafer の点で X・Y 別に次を求める：
%   - 当てはめた残差（高次補正の残差）：|平均|+3σ・|残差| の 95% 点・中央値・RMS（fit…）
%   - 1点抜きの予測の誤差（その点を除いて当てはめたときの、その点の誤差。result.points の looResidual）：同じ値（loo…）
%   値どうしを同じ点で比べるため、どの値でも求められた点だけを使う（当てはめた残差と 1点抜きの誤差で別に数える。
%   n・nLoo）。当てはめた残差は λ が小さいほど小さく見える（その点に合わせ込む）ので、λ・c は 1点抜きの誤差で選ぶ。
%   sweep.table：値ごと・軸ごとの行（run（値の組の番号）・lambda・huberTuning・axis・n・fitMeanPlus3Sigma・fitP95・fitMedian・
%   fitRms・nLoo・looMeanPlus3Sigma・looP95・looMedian・looRms・nTerms（絞った後の使う項の数）・skipped（補正しなかった k の組の
%   数）・note）。sweep.perWafer：Wafer ごとの同じ値（run・axis・wafer と fit…・loo…。エラーバーに使う）。
%   sweep.baseline：基準（最小二乗・正則化なし）の軸ごとの行（axis と fit…・loo…。同じ点で求める。計算できなければ空の表）。
%   sweep.parameter："lambda"・"huberTuning"・"both"、sweep.lambda・huberTuning：スイープした値、sweep.regularization・loss：
%   計算に使った軸ごとの正則化の種類と損失関数、sweep.description：基の設定の説明、sweep.cancelled：途中で止めたか、
%   sweep.nRuns：計算した値の組の数、sweep.total：全体の値の組の数、sweep.state：続きを計算するための途中の値
arguments
    wafers struct
    settings struct
    options.lambda double = zeros(1, 0)
    options.huberTuning double = zeros(1, 0)
    options.progressFcn = []
    options.resume = []
end
MAX_RUNS = 400;   % 計算する値の組の上限（細かすぎる刻みで終わらなくならないように）
base = alignest.highOrderOptions(settings);
lambdas = reshape(double(options.lambda), 1, []);
tunings = reshape(double(options.huberTuning), 1, []);
if isempty(lambdas) && isempty(tunings)
    error('alignest:highOrderSweep', 'スイープする λ か c の値を1つ以上入れてください。');
end
if any(~isfinite(lambdas) | lambdas < 0)
    error('alignest:highOrderSweep', 'λ は 0 以上の数にしてください。');
end
if any(~isfinite(tunings) | tunings < 0)
    error('alignest:highOrderSweep', 'Huber の c は 0 以上の数にしてください（0 は LAD と同じです）。');
end
if ~isempty(lambdas) && ~isempty(tunings)
    parameter = "both";
elseif ~isempty(lambdas)
    parameter = "lambda";
else
    parameter = "huberTuning";
end
regularization = base.regularization;
if ~isempty(lambdas)
    regularization(regularization == "none") = "l2";
end
loss = base.loss;
if ~isempty(tunings)
    loss(:) = "huber";
end
sweepLambda = ~isempty(lambdas);
sweepTuning = ~isempty(tunings);
if ~sweepLambda
    lambdas = NaN;   % λ は設定の値のまま（軸ごとの値）
end
if ~sweepTuning
    tunings = NaN;   % c は設定の値のまま（軸ごとの値）
end
[lambdaGrid, tuningGrid] = ndgrid(lambdas, tunings);
lambdaGrid = lambdaGrid(:);   % 値の組ごとの λ・c（λ が速く変わる順）
tuningGrid = tuningGrid(:);
nRuns = numel(lambdaGrid);
if nRuns > MAX_RUNS
    error('alignest:highOrderSweep', ['値の組が %d 通りになります。%d 通り以下になるように、範囲を狭めるか評価数を' ...
        '減らしてください。'], nRuns, MAX_RUNS);
end
if isempty(options.resume)
    state = struct("lambdaGrid", lambdaGrid, "tuningGrid", tuningGrid, "done", 0, "residuals", {cell(nRuns, 1)}, ...
        "looResiduals", {cell(nRuns, 1)}, "nTerms", nan(nRuns, 1), "skipped", nan(nRuns, 1), "note", strings(nRuns, 1), ...
        "pointWafers", strings(0, 1), "baseline", []);
    state.baseline = baselineResiduals(wafers, settings);
else
    state = options.resume;
    if ~isequaln(state.lambdaGrid, lambdaGrid) || ~isequaln(state.tuningGrid, tuningGrid)
        error('alignest:highOrderSweep', '続きを計算する値の並びが、一時中断した値と違います。');
    end
end
cancelled = false;
for r = state.done + 1:nRuns
    current = settings;
    current.highOrder.regularization = regularization;
    current.highOrder.loss = loss;
    if sweepLambda
        current.highOrder.lambda = lambdaGrid(r);
    end
    if sweepTuning
        if tuningGrid(r) == 0
            current.highOrder.loss(:) = "lad";   % c → 0 の Huber は LAD
        else
            current.highOrder.huberTuning = tuningGrid(r);
        end
    end
    if isfield(current.highOrder, "l2")
        current.highOrder = rmfield(current.highOrder, "l2");   % 以前の設定の L2 のオン・オフ（regularization で決める）
    end
    try
        result = alignest.shotHighOrder(wafers, current, stages=false);
        state.residuals{r} = [result.points.residualX, result.points.residualY];
        state.looResiduals{r} = [result.points.looResidualX, result.points.looResidualY];
        state.pointWafers = result.points.wafer;
        state.nTerms(r) = nnz(result.terms.used);
        state.skipped(r) = sum(result.summary.skipped(result.summary.wafer == "すべての Wafer"), 'omitnan');
        if state.skipped(r) > 0
            state.note(r) = sprintf("補正しなかった k の組 %d（X・Y の合計）", state.skipped(r));
        end
    catch err
        state.note(r) = "計算できませんでした：" + string(err.message);
    end
    state.done = r;
    if ~isempty(options.progressFcn) && ~options.progressFcn(r, nRuns, runText(lambdaGrid(r), tuningGrid(r), parameter))
        cancelled = r < nRuns;
        break
    end
end
[sweep.table, sweep.perWafer, sweep.baseline] = summarize(state, base);
sweep.parameter = parameter;
sweep.lambda = lambdas;
sweep.huberTuning = tunings;
sweep.regularization = regularization;
sweep.loss = loss;
sweep.description = base.description;
sweep.cancelled = cancelled;
sweep.nRuns = state.done;
sweep.total = nRuns;
sweep.state = state;
end

function baseline = baselineResiduals(wafers, settings)
% 基準（最小二乗・正則化なし）の残差と 1点抜きの誤差（計算できなければ []）
settings.highOrder.loss = "ols";
settings.highOrder.regularization = "none";
if isfield(settings.highOrder, "l2")
    settings.highOrder = rmfield(settings.highOrder, "l2");
end
baseline = [];
try
    result = alignest.shotHighOrder(wafers, settings, stages=false);
    baseline = struct("residual", [result.points.residualX, result.points.residualY], "loo", ...
        [result.points.looResidualX, result.points.looResidualY]);
catch
    % 基準を求められなくても（Scan 方向が分からないなど、スイープでも止まる場合を除く）、スイープの結果は出す
end
end

function [results, perWafer, baseline] = summarize(state, base)
% 値ごと・軸ごとの表と、Wafer ごとの表、基準の表（どの値でも求められた点だけで比べる。計算できなかった値は除く）
AXIS_NAMES = ["X", "Y"];
STAT_NAMES = ["MeanPlus3Sigma", "P95", "Median", "Rms"];
statColumns = ["fit" + STAT_NAMES, "loo" + STAT_NAMES];
columnNames = ["run", "lambda", "huberTuning", "axis", "n", "fit" + STAT_NAMES, "nLoo", "loo" + STAT_NAMES, "nTerms", ...
    "skipped", "note"];
done = state.done;
computed = find(~cellfun(@isempty, state.residuals(1:done))).';
parts = cell(numel(computed), 2);
waferParts = cell(numel(computed), 2);
baseline = table();
baselineParts = cell(1, 2);
waferNames = unique(state.pointWafers, 'stable');
for a = 1:2
    fitCommon = true;
    looCommon = true;
    for r = computed
        fitCommon = fitCommon & isfinite(state.residuals{r}(:, a));
        looCommon = looCommon & isfinite(state.looResiduals{r}(:, a));
    end
    for j = 1:numel(computed)
        r = computed(j);
        fitStats = statistics(state.residuals{r}(fitCommon, a));
        looStats = statistics(state.looResiduals{r}(looCommon, a));
        parts{j, a} = [table(r, axisValue(state.lambdaGrid(r), base.lambda(a)), axisValue(state.tuningGrid(r), ...
            base.huberTuning(a)), AXIS_NAMES(a), nnz(fitCommon), 'VariableNames', columnNames(1:5)), ...
            array2table(fitStats, 'VariableNames', columnNames(6:9)), table(nnz(looCommon), 'VariableNames', columnNames(10)), ...
            array2table(looStats, 'VariableNames', columnNames(11:14)), table(state.nTerms(r), state.skipped(r), ...
            state.note(r), 'VariableNames', columnNames(15:17))];
        rows = cell(numel(waferNames), 1);
        for w = 1:numel(waferNames)
            mine = state.pointWafers == waferNames(w);
            rows{w} = [table(r, AXIS_NAMES(a), waferNames(w), 'VariableNames', ["run", "axis", "wafer"]), ...
                array2table([statistics(state.residuals{r}(fitCommon & mine, a)), ...
                statistics(state.looResiduals{r}(looCommon & mine, a))], 'VariableNames', statColumns)];
        end
        waferParts{j, a} = vertcat(rows{:});
    end
    if ~isempty(state.baseline) && ~isempty(computed)
        fitValues = state.baseline.residual(fitCommon, a);
        looValues = state.baseline.loo(looCommon, a);
        baselineParts{a} = [table(AXIS_NAMES(a), 'VariableNames', "axis"), array2table([statistics(fitValues(isfinite(fitValues))), ...
            statistics(looValues(isfinite(looValues)))], 'VariableNames', statColumns)];
    end
end
% 計算できなかった値は、軸を空にして理由だけの行にする
failed = reshape(setdiff(1:done, computed), [], 1);
blank = nan(numel(failed), 1);
failedRows = table(failed, state.lambdaGrid(failed), state.tuningGrid(failed), strings(numel(failed), 1), ...
    zeros(numel(failed), 1), blank, blank, blank, blank, zeros(numel(failed), 1), blank, blank, blank, blank, ...
    state.nTerms(failed), state.skipped(failed), state.note(failed), 'VariableNames', columnNames);
results = [vertcat(parts{:, 1}); vertcat(parts{:, 2}); failedRows];
perWafer = vertcat(waferParts{:});
if ~isempty(baselineParts{1})
    baseline = vertcat(baselineParts{:});
end
end

function value = axisValue(swept, setting)
% スイープした値（スイープしないときは NaN）と、その軸の設定の値
value = swept;
if isnan(swept)
    value = setting;
end
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
