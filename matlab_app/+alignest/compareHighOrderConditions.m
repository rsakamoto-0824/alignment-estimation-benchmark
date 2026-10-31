function comparison = compareHighOrderConditions(wafers, settings, conditions)
%COMPAREHIGHORDERCONDITIONS Shot 高次補正の条件（補正の式・使う項・くくり・回帰・λ など）をまとめて計算し、すべての Wafer を
%   まとめた評価を並べる（「7. Shot高次補正」の「補正の比較」。λ のスイープ・くくりの比較にも使う）。
%   comparison = alignest.compareHighOrderConditions(wafers, settings, conditions)
%   wafers・settings は alignest.shotHighOrder と同じ。conditions：構造体の配列。label（条件の名前）・highOrder（その条件の
%   settings.highOrder。足りない項目は settings.highOrder の値）。
%   comparison：行は条件 × 軸（X、Y の順に、条件の順）。label・axis・description（補正の説明）・maker・unit・loss・lambda
%   （使った λ。L2 なしは 0）・nTerms（使った項の数。項数を絞った後）・kSets・skipped・nCorrected・before・linear（Shot
%   ごとの1次）・highOrder・improvement・highOrderP95・highOrderMedian（|残差| の 95% 点・中央値）・note（絞った項・求め
%   られなかった理由）。求められない条件（Scan 方向が分からないなど）の行は NaN。
arguments
    wafers struct
    settings struct
    conditions struct
end
ALL_LABEL = "すべての Wafer";
AXES = ["X", "Y"];
FORMULA_AXES = ["dx", "dy"];
parts = cell(numel(conditions), 1);
for c = 1:numel(conditions)
    conditionSettings = settings;
    for name = string(fieldnames(conditions(c).highOrder)).'
        conditionSettings.highOrder.(name) = conditions(c).highOrder.(name);
    end
    options = alignest.highOrderOptions(conditionSettings);
    rows = table(repmat(string(conditions(c).label), 2, 1), AXES.', repmat(options.description, 2, 1), ...
        repmat(options.maker, 2, 1), repmat(options.unit, 2, 1), repmat(options.loss, 2, 1), ...
        repmat(options.lambda * options.l2, 2, 1), nan(2, 1), nan(2, 1), nan(2, 1), nan(2, 1), nan(2, 1), nan(2, 1), ...
        nan(2, 1), nan(2, 1), nan(2, 1), nan(2, 1), strings(2, 1), 'VariableNames', ["label", "axis", "description", ...
        "maker", "unit", "loss", "lambda", "nTerms", "kSets", "skipped", "nCorrected", "before", "linear", "highOrder", ...
        "improvement", "highOrderP95", "highOrderMedian", "note"]);
    try
        result = alignest.shotHighOrder(wafers, conditionSettings);
        rows.description(:) = result.description;   % 点の数で項を絞ったときは、絞った後の項の数
        totals = result.summary(result.summary.wafer == ALL_LABEL, :);
        for a = 1:2
            rows.nTerms(a) = nnz(result.terms.used & result.terms.axis == FORMULA_AXES(a));
            for name = ["kSets", "skipped", "nCorrected", "before", "linear", "highOrder", "improvement", ...
                    "highOrderP95", "highOrderMedian"]
                rows.(name)(a) = totals.(name)(a);
            end
            dropped = result.reduction(a).dropped;
            if ~isempty(dropped)
                rows.note(a) = "項を絞った（外した項：" + strjoin("k" + string(dropped), "・") + "）";
            end
        end
    catch err
        if ~any(err.identifier == ["alignest:highOrderDirection", "alignest:highOrderInput"])
            rethrow(err);
        end
        rows.note(:) = string(err.message);
    end
    parts{c} = rows;
end
comparison = vertcat(parts{:});
if isempty(comparison)
    return
end
[~, order] = sortrows([comparison.axis == "Y", (1:height(comparison)).']);   % X の行、Y の行の順
comparison = comparison(order, :);
end
