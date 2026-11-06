function study = markLayoutStudy(candidates, shots, settings, progressFcn)
%MARKLAYOUTSTUDY Shot 高次補正の計測 Mark の配置を、Mark の数ごとに I 最適計画で選び、補正した制御残差を I 効率と比べる。
%   study = alignest.markLayoutStudy(candidates, shots, settings)
%   study = alignest.markLayoutStudy(..., progressFcn)   % progressFcn(割合 0〜1, 説明) が false なら止める
%   candidates・shots：alignest.markCandidates の候補の Mark（required の列で必ず計測する Mark）と Shot ごとの値（座標だけなら
%   Shot は 0）。settings：設定（settings.markLayout を alignest.markLayoutOptions で確かめて使う）。
%   手順：
%   1. 補正の式の使う項（alignest.highOrderTerms。外した項を除く）と、候補の Mark の位置での VIF（alignest.highOrderVif）
%   2. Mark の数（最低数〜最大数。最低数は使う項の数と必ず計測する Mark の数より少なくしない）ごとに、I 最適計画の配置
%      （alignest.iOptimalMarks。I は dx・dy の式の予測の分散の和。必ず計測する Mark はどの数にも入れる）。実測値で評価するとき
%      は、どの Shot にも値の無い候補の Mark は選ばない（必ず計測する Mark は残す。I 効率の 100% も選べる Mark すべて）
%   3. 制御残差を求める値：実測値（Shot ごと）、または乱数の Shot の形（alignest.randomShotShapes。制御残差は計測のばらつき・
%      飛び値を足す前の形で求める）
%   4. 配置ごと（とすべての候補を計測したとき）に、選んだ Mark の値で補正の式を当てはめ（ロバスト回帰・正則化。
%      alignest.robustRidgeFit）、すべての Mark の制御残差を求める（alignest.evaluateMarkLayouts）
%   study：options（設定）・candidates・terms（項の表と VIF）・vifInfo・counts（Mark の数）・layouts（alignest.iOptimalMarks）・
%   evaluation（配置ごと・軸ごとの表。count（Mark の数）・efficiency（I 効率 [%]）・layoutType（"I 最適"・"すべての Mark"）の列を
%   足す。最後の2行がすべての候補を計測したとき）・valueSource（"measured"・"random"）・nShots（評価した Shot・形の数）・
%   shapes（乱数の形。実測値なら []）・messages（知らせ）・cancelled。
arguments
    candidates table
    shots struct
    settings struct
    progressFcn = []
end
DESIGN_SHARE = 0.5;   % 進み具合のうち、配置を選ぶ分の割合（残りは制御残差）
options = alignest.markLayoutOptions(settings);
messages = strings(0, 1);
if options.values == "measured" && isempty(shots.label)
    error('alignest:markLayout', ['実測値がありません（座標だけの入力）。制御残差を求める値を「乱数の Shot の形」に' ...
        'してください。']);
end
n = height(candidates);
local = [candidates.xMm, candidates.yMm];
selectable = true(n, 1);
if options.values == "measured"
    selectable = candidates.nShots > 0 | candidates.required;
end
nSelectable = nnz(selectable);
if nSelectable < n
    messages(end + 1) = sprintf("値の無い候補の Mark %d 点は選びません。", n - nSelectable);
end
% 1. 補正の式の使う項と VIF（候補の Mark の位置で）
terms = alignest.highOrderTerms(options.maker, options.excludedTerms);
[terms, vifInfo] = alignest.highOrderVif(terms, local, true(n, 2), options.vifThreshold);
axisNames = ["dx", "dy"];
[designs, penalized] = deal(cell(1, 2));
nTerms = zeros(1, 2);
for a = 1:2
    mine = terms(terms.axis == axisNames(a) & terms.used, :);
    designs{a} = local(:, 1) .^ (mine.xPower.') .* local(:, 2) .^ (mine.yPower.');
    penalized{a} = ismember(mine.order, options.penaltyOrders) & options.regularization ~= "none";
    nTerms(a) = height(mine);
    undetermined = mine.term(~independent(designs{a}(selectable, :)));
    if ~isempty(undetermined)
        error('alignest:markLayout', ['候補の Mark の位置では、%s の式の項 %s が決まりません（候補の Mark が足りないか、' ...
            '並びが一直線など）。「VIF で選ぶ」か表で項を外すか、候補の Mark を足してください。'], axisNames(a), ...
            strjoin(undetermined, "・"));
    end
end
% 2. Mark の数と I 最適計画の配置
nRequired = nnz(candidates.required);
minimum = max([options.minMarks, nTerms, nRequired]);
if options.minMarks > 0 && minimum > options.minMarks
    messages(end + 1) = sprintf(['計測する Mark の最低数を %d にしました（入れた %d では、使う項（dx %d・dy %d 項）か' ...
        '必ず計測する Mark（%d 点）より少ないため）。'], minimum, options.minMarks, nTerms(1), nTerms(2), nRequired);
end
maximum = nSelectable;
if options.maxMarks > 0
    maximum = min(options.maxMarks, nSelectable);
end
if minimum > nSelectable
    error('alignest:markLayout', ['候補の Mark（%d 点）が、使う項（dx %d・dy %d 項）か必ず計測する Mark（%d 点）より' ...
        '少ないです。候補の Mark を足すか、項を外してください。'], nSelectable, nTerms(1), nTerms(2), nRequired);
end
if maximum < minimum
    messages(end + 1) = sprintf('計測する Mark の最大数を %d にしました（最低数より少ないため）。', minimum);
    maximum = minimum;
end
counts = (minimum:maximum).';
cancelled = false;
layouts = alignest.iOptimalMarks(cellfun(@(F) F(selectable, :), designs, 'UniformOutput', false), ...
    candidates.required(selectable), counts, starts=options.starts, seed=options.seed, ...
    progressFcn=@(done, total, text) report(DESIGN_SHARE * done / total, "I 最適計画で配置を選んでいます：" + text + ...
    sprintf("（%d / %d）", done, total)));
chosen = false(n, size(layouts.selected, 2));
chosen(selectable, :) = layouts.selected;
layouts.selected = chosen;   % 行はすべての候補の Mark に戻す
if layouts.cancelled
    cancelled = true;
    counts = layouts.counts;
    messages(end + 1) = sprintf("途中で止めました（Mark の数 %d 点までの配置）。", counts(end));
end
% 3. 制御残差を求める値
shapes = [];
valueSource = options.values;
if valueSource == "random"
    shapes = alignest.randomShotShapes(candidates.xMm, candidates.yMm, shapes=options.shapes, seed=options.seed, ...
        orderSigmaNm=options.orderSigmaNm, noiseNm=options.noiseNm, outlierPercent=options.outlierPercent, ...
        outlierNm=options.outlierNm);
    values = struct("fitX", shapes.measuredX, "fitY", shapes.measuredY, "referenceX", shapes.trueX, ...
        "referenceY", shapes.trueY);
    nShots = shapes.count;
else
    values = struct("fitX", shots.valueX, "fitY", shots.valueY, "referenceX", shots.valueX, "referenceY", shots.valueY);
    nShots = numel(shots.label);
end
% 4. 配置ごと（とすべての候補を計測したとき）の制御残差
penaltyType = "l2";
if options.regularization == "l1"
    penaltyType = "l1";
end
fitOptions = {'loss', options.loss, 'huberTuning', options.huberTuning, 'lambda', ...
    options.lambda * (options.regularization ~= "none"), 'penalty', penaltyType};
selected = [layouts.selected, selectable];
evaluation = table();
if ~cancelled
    evaluation = alignest.evaluateMarkLayouts(designs, selected, values, penalized, fitOptions, ...
        @(done, total) report(DESIGN_SHARE + (1 - DESIGN_SHARE) * done / total, ...
        sprintf("制御残差を求めています（%d / %d 配置）", done, total)));
    if max(evaluation.layout) < size(selected, 2)
        cancelled = true;
        messages(end + 1) = "途中で止めました（制御残差は途中の配置まで）。";
    end
end
if height(evaluation) > 0
    allCounts = [counts; nSelectable];
    efficiencies = [layouts.efficiency; 100];
    types = [repmat("I 最適", numel(counts), 1); "すべての Mark"];
    evaluation.count = allCounts(evaluation.layout);
    evaluation.efficiency = efficiencies(evaluation.layout);
    evaluation.layoutType = types(evaluation.layout);
    evaluation = movevars(evaluation, ["count", "efficiency", "layoutType"], "After", "layout");
    skipped = evaluation.skipped(evaluation.layoutType == "I 最適");
    if any(skipped > 0)
        messages(end + 1) = sprintf(['値の無い Mark があって使う項が決まらない Shot は補正していません（配置ごとに多い' ...
            'ときで %d Shot。表の「補正しなかった Shot」）。'], max(skipped));
    end
    if valueSource == "random"
        messages(end + 1) = sprintf("乱数の Shot の形 %d 通り（種 %d）で評価しました。", nShots, options.seed);
    else
        messages(end + 1) = sprintf("実測値の %d Shot で評価しました。", nShots);
    end
end
study = struct("options", options, "candidates", candidates, "terms", terms, "vifInfo", vifInfo, "counts", counts, ...
    "layouts", layouts, "evaluation", evaluation, "valueSource", valueSource, "nShots", nShots, "shapes", shapes, ...
    "nTerms", nTerms, "messages", messages, "cancelled", cancelled);

    function continueRun = report(fraction, text)
        continueRun = true;
        if ~isempty(progressFcn)
            continueRun = progressFcn(fraction, text);
        end
    end
end

function keep = independent(A)
% 前の列で表せない列（列の大きさをそろえて QR 分解の対角で判定）
TOLERANCE = 1e-9;
if isempty(A)
    keep = true(1, 0);
    return
end
scale = sqrt(mean(A .^ 2, 1));
scale(scale == 0) = 1;
[~, R] = qr(A ./ scale, 0);
diagonal = abs(diag(R));
keep = false(size(A, 2), 1);
keep(1:numel(diagonal)) = diagonal > TOLERANCE * max(diagonal);
end
