function breakdown = timingBreakdown(unit, spec, methods, settings, nRepeats)
%TIMINGBREAKDOWN 1つの条件（Wafer × 学習パターン × 手法）の処理時間を、段階ごとに測る。
%   breakdown = alignest.timingBreakdown(unit, spec, methods, settings, nRepeats)
%   unit は data.units の1つ、spec は学習パターン（alignest.buildPlanSpecs の1つ）、methods は手法（複数可）。
%   段階（breakdown.stages・labels）：
%     plan     学習パターンの作成（最適マップ：I 最適の交換法・ランダム・優先順。alignest.planTrainingShots）
%     outliers 学習データの異常値の判定（異常値を除く設定のときだけ。alignest.trainingOutliers）
%     prepare  推定の準備（学習点・評価点の選び出し、XY 1次を除く設定ならその当てはめ）
%     fit      学習（モデルの当てはめ。超パラメータ・平滑化の強さの推定を含む）
%     predict  推論（評価点の推定）
%     metrics  評価指標の計算（R²・RMSE・MAE・改善率）
%     overlay  Overlay 補正の評価（評価するときだけ）
%   学習と推論は1つの関数で続けて計算する手法が多いので、全評価点を推定したときの時間と、評価点を1点にしたときの
%   時間の差を推論とし、残りを学習とする（差が負なら 0）。nRepeats 回測った中央値を使う（初めに1回、読み込みなど
%   初回だけの時間を除くための予備の計算をして捨てる）。評価では学習パターンを同じ配置の Wafer・手法で使い回すので、
%   評価全体に占める作成の割合はこれより小さい。
%   breakdown.table：手法ごとの各段階の秒数・合計（methodLabel・methodId と段階の名前の列、total）
%   breakdown.plan：作った学習パターン、breakdown.nRepeats：測った回数
arguments
    unit struct
    spec struct
    methods struct
    settings struct
    nRepeats (1, 1) double {mustBeInteger, mustBePositive} = 3
end
STAGES = ["plan", "outliers", "prepare", "fit", "predict", "metrics", "overlay"];
LABELS = ["学習パターンの作成（最適マップ）", "異常値の判定", "推定の準備", "学習（当てはめ）", "推論（評価点の推定）", ...
    "評価指標の計算", "Overlay 補正の評価"];
radius = settings.data.waferRadiusMm;
alignest.planTrainingShots(unit, spec, settings.sampling, radius);   % 予備の計算
planSeconds = zeros(nRepeats, 1);
for r = 1:nRepeats
    planTimer = tic;
    plan = alignest.planTrainingShots(unit, spec, settings.sampling, radius);
    planSeconds(r) = toc(planTimer);
end
if ~plan.ok
    error('alignest:timingBreakdown', 'この Wafer では学習パターンを作れませんでした：%s', plan.message);
end
marks = unit.marks;
oneMask = singleTestMark(marks, alignest.trainingMarks(unit, plan));
outerMm = alignest.upgradeRadiusSettings(settings).evaluation.outerRadiusMm;
overlay = alignest.overlayChoice(settings);
values = zeros(numel(methods), numel(STAGES));
for m = 1:numel(methods)
    samples = zeros(nRepeats + 1, 6);   % 1回目は予備の計算（捨てる）
    for r = 1:nRepeats + 1
        out = alignest.estimateWafer(unit, plan, methods(m), settings);
        single = alignest.estimateWafer(unit, plan, methods(m), settings, oneMask);
        metricTimer = tic;
        alignest.computeMetrics(marks.measX(out.testIndex.X), out.estimate.X, NaN, marks.measY(out.testIndex.Y), ...
            out.estimate.Y, NaN, marks.r(out.testIndex.X) >= outerMm, marks.r(out.testIndex.Y) >= outerMm, ...
            marks.measX(out.trainIndex.X), marks.measY(out.trainIndex.Y));
        metricSeconds = toc(metricTimer);
        overlaySeconds = 0;
        if overlay.enabled
            overlayTimer = tic;
            alignest.overlayCorrection(unit, out, alignest.overlayProjector(unit, overlay, radius));
            overlaySeconds = toc(overlayTimer);
        end
        samples(r, :) = [out.timing.outliers, out.timing.prepare, out.timing.model, single.timing.model, ...
            metricSeconds, overlaySeconds];
    end
    typical = median(samples(2:end, :), 1);
    predictSeconds = max(typical(3) - typical(4), 0);
    values(m, :) = [median(planSeconds), typical(1), typical(2), typical(3) - predictSeconds, predictSeconds, ...
        typical(5), typical(6)];
end
methodLabel = reshape(string({methods.label}), [], 1);
methodId = reshape(string({methods.id}), [], 1);
breakdown.table = [table(methodLabel, methodId), array2table(values, 'VariableNames', cellstr(STAGES))];
breakdown.table.total = sum(values, 2);
breakdown.stages = STAGES;
breakdown.labels = LABELS;
breakdown.plan = plan;
breakdown.nRepeats = nRepeats;
breakdown.nTest = [numel(out.testIndex.X), numel(out.testIndex.Y)];
breakdown.nTrain = [numel(out.trainIndex.X), numel(out.trainIndex.Y)];
end

function mask = singleTestMark(marks, inTrain)
% 評価点を1点にする Mark（X・Y の両方が有効な最初の評価 Mark。無ければ X と Y の最初の評価 Mark）
test = ~inTrain;
mask = false(numel(marks.x), 1);
both = find(test & marks.validX & marks.validY, 1);
if ~isempty(both)
    mask(both) = true;
    return
end
mask(find(test & marks.validX, 1)) = true;
mask(find(test & marks.validY, 1)) = true;
end
