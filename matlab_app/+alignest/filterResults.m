function filtered = filterResults(results, data, filter)
%FILTERRESULTS 評価点を半径・Shot の条件で絞り込み、結果の表の指標を計算し直す（推定はやり直さない）。
%   filtered = alignest.filterResults(results, data, filter)
%   results は alignest.runEvaluation の結果（行ごとの評価点の推定値 results.pointEstimates が要る）、
%   filter は alignest.defaultPointFilter と同じ形（alignest.pointFilterMask）。
%   学習パターン・学習点・推定値はそのままで、評価点だけを条件に合う Mark に絞り、R²・RMSE・MAE・外周と内側の RMSE・
%   平均値・中央値に対する改善量と改善率・評価点の数を求め直す（評価と同じ alignest.computeMetrics）。
%   Overlay 補正の評価をしたときは、補正量は全 Mark で求めたまま、|平均|+3σ を条件に合う Mark で求め直す。
%   処理時間・I 基準などの指標は変わらない。条件に合う評価点が無い行は NaN。
%   filtered.filter に条件、filtered.filterText に説明を入れる。絞り込まない条件なら results をそのまま返す。
arguments
    results struct
    data struct
    filter struct
end
[~, text, active] = alignest.pointFilterMask(filter);
filtered = results;
filtered.filter = filter;
filtered.filterText = text;
if ~active
    return
end
if ~isfield(results, "pointEstimates") || numel(results.pointEstimates) ~= height(results.table)
    error('alignest:filterResults', ['この結果には評価点ごとの推定値が無いため、絞り込んで計算し直せません' ...
        '（Excel から読み込んだ結果など）。「3. 実行」で評価してください。']);
end
settings = results.settings;
outerMm = alignest.upgradeRadiusSettings(settings).evaluation.outerRadiusMm;
overlay = alignest.overlayChoice(settings);
overlayEvaluated = isfield(results, "overlayEvaluated") && results.overlayEvaluated && overlay.enabled;
table_ = results.table;
masks = cell(numel(data.units), 1);
projectors = cell(numel(data.units), 1);
metricNames = string(table_.Properties.VariableNames);
for k = 1:height(table_)
    estimate = results.pointEstimates{k};
    if isempty(estimate)
        continue
    end
    u = table_.unitIndex(k);
    unit = data.units(u);
    marks = unit.marks;
    if isempty(masks{u})
        masks{u} = alignest.unitPointFilter(unit, filter);
    end
    mask = masks{u};
    testX = estimate.testIndex.X(mask(estimate.testIndex.X));
    testY = estimate.testIndex.Y(mask(estimate.testIndex.Y));
    estimateX = estimate.estimate.X(mask(estimate.testIndex.X));
    estimateY = estimate.estimate.Y(mask(estimate.testIndex.Y));
    metrics = alignest.computeMetrics(marks.measX(testX), estimateX, NaN, marks.measY(testY), estimateY, NaN, ...
        marks.r(testX) >= outerMm, marks.r(testY) >= outerMm, marks.measX(estimate.trainIndex.X), ...
        marks.measY(estimate.trainIndex.Y));
    if overlayEvaluated
        if isempty(projectors{u})
            projectors{u} = alignest.overlayProjector(unit, overlay, settings.data.waferRadiusMm);
        end
        correction = alignest.overlayCorrection(unit, estimate, projectors{u}, mask);
        for name = string(fieldnames(correction.metrics)).'
            metrics.(name) = correction.metrics.(name);
        end
    end
    for name = string(fieldnames(metrics)).'
        if any(metricNames == name)
            table_.(name)(k) = metrics.(name);
        end
    end
end
filtered.table = table_;
end
