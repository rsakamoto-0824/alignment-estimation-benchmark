function [seconds, detail] = estimateRunSeconds(units, settings)
%ESTIMATERUNSECONDS 評価にかかる時間の目安 [秒]（「2. 面内推定の設定」と「2. 面内推定の設定」に出す）。
%   [seconds, detail] = alignest.estimateRunSeconds(data.units, settings)
%   目安 = 推定の時間 + 学習パターンを作る時間。
%   推定の時間 = 1条件（Wafer × 学習パターン × 手法 の1つ）あたり 2 秒 × 条件の数。
%   ただし、ν を指定した Matérn のカーネル（GPR の matern・ardmatern、GAM のガウス過程の matern）を使う手法は、
%   ベッセル関数の計算のぶん遅いので 1条件 2 秒 × MATERN_NU_FACTOR とする（模擬データ・学習 40 Shot で測ると、
%   ν = 0.75 は matern52 の約 3.3 倍、ν = 2.5 は約 1.6〜2 倍。2026-10-23、M1 Mac）。ν を複数入れると、
%   ν ごとに手法が増える（alignest.buildMethodList）ので、その数も目安に入る。
%   ほかの手法・学習 Shot 数で時間は違うが、目安は分かりやすさのため一律にする（会社の PC での使い方に合わせた値）。
%   学習パターンを作る時間 = 配置の種類（alignest.planLayoutKey。Shot 単位の計画は候補の Shot が同じ Wafer、Mark 単位の計画は
%   使える Mark が同じ Wafer で学習パターンを使い回す）ごとの alignest.planSecondsGuide の和。交換法で解く I 最適・D 最適
%   （Shot 単位・Mark 単位）だけ数える。Mark 単位の計画は Mark を1つずつ入れ替えるので長く、値の無い Mark が Wafer ごとに
%   違うと Wafer ごとに作り直すため、1枚あたりの時間が伸びる（Shot 単位は Shot の中の Mark の欠けでは作り直さない）。
%   Wafer は評価に使う Wafer（alignest.evaluationUnitIndex。settings.evaluation の枚数・割合）だけを数える。
%   detail.nRuns は条件の数（推定の回数）、detail.secondsPerRun は1条件あたりの秒数（基本）、
%   detail.nMaternNuMethods は ν を指定した Matérn の手法の数、detail.maternNuFactor はその倍率、
%   detail.estimateSeconds は推定の時間、detail.planSeconds は学習パターンを作る時間、detail.nLayouts は配置の種類の数、
%   detail.planSecondsEach は最初の Wafer の配置での学習パターンごとの時間（1 × 学習パターンの数）。
SECONDS_PER_RUN = 2;
MATERN_NU_FACTOR = 3;
detail = struct("nRuns", 0, "secondsPerRun", SECONDS_PER_RUN, "nMaternNuMethods", 0, ...
    "maternNuFactor", MATERN_NU_FACTOR, "estimateSeconds", 0, "planSeconds", 0, "nLayouts", 0, ...
    "planSecondsEach", zeros(1, 0));
seconds = 0;
if isempty(units)
    return
end
methods = alignest.activeMethods(settings);
specs = alignest.buildPlanSpecs(settings.sampling);
if isfield(settings, "evaluation")
    % 評価に使う Wafer（枚数・割合で決めたとき）だけを数える
    units = units(alignest.evaluationUnitIndex(numel(units), settings.evaluation, settings.sampling.seed));
end
usesNu = contains(string({methods.variant}), "_nu");
detail.nMaternNuMethods = nnz(usesNu);
detail.nRuns = numel(units) * numel(specs) * numel(methods);
weights = ones(1, numel(methods));
weights(usesNu) = MATERN_NU_FACTOR;
detail.estimateSeconds = SECONDS_PER_RUN * numel(units) * numel(specs) * sum(weights);
% 学習パターンを作る時間（配置の種類ごとに1回。Shot 単位と Mark 単位の計画は、配置の目印が違う）
if isempty(specs)
    seconds = detail.estimateSeconds;
    return
end
detail.planSecondsEach = alignest.planSecondsGuide(units(1), specs, settings.sampling);
levels = arrayfun(@(spec) alignest.planSpecLevel(spec), specs);
for level = ["shot", "mark"]
    picked = levels == level;
    if ~any(picked)
        continue
    end
    keys = strings(numel(units), 1);
    for u = 1:numel(units)
        keys(u) = string(alignest.planLayoutKey(units(u), level));
    end
    [~, firstOfLayout] = unique(keys, 'stable');
    detail.nLayouts = max(detail.nLayouts, numel(firstOfLayout));
    for u = reshape(firstOfLayout, 1, [])
        detail.planSeconds = detail.planSeconds + sum(alignest.planSecondsGuide(units(u), specs(picked), settings.sampling));
    end
end
seconds = detail.estimateSeconds + detail.planSeconds;
end
