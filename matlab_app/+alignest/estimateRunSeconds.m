function [seconds, detail] = estimateRunSeconds(units, settings)
%ESTIMATERUNSECONDS 評価にかかる時間の目安 [秒]（「2. 評価の設定」と「3. 実行」に出す）。
%   [seconds, detail] = alignest.estimateRunSeconds(data.units, settings)
%   目安 = 1条件（Wafer × 学習パターン × 手法 の1つ）あたり 2 秒 × 条件の数。
%   ただし、ν を指定した Matérn のカーネル（GPR の matern・ardmatern、GAM のガウス過程の matern）を使う手法は、
%   ベッセル関数の計算のぶん遅いので 1条件 2 秒 × MATERN_NU_FACTOR とする（模擬データ・学習 40 Shot で測ると、
%   ν = 0.75 は matern52 の約 3.3 倍、ν = 2.5 は約 1.6〜2 倍。2026-10-23、M1 Mac）。ν を複数入れると、
%   ν ごとに手法が増える（alignest.buildMethodList）ので、その数も目安に入る。
%   ほかの手法・学習 Shot 数で時間は違うが、目安は分かりやすさのため一律にする（会社の PC での使い方に合わせた値）。
%   detail.nRuns は条件の数（推定の回数）、detail.secondsPerRun は1条件あたりの秒数（基本）、
%   detail.nMaternNuMethods は ν を指定した Matérn の手法の数、detail.maternNuFactor はその倍率。
SECONDS_PER_RUN = 2;
MATERN_NU_FACTOR = 3;
detail = struct("nRuns", 0, "secondsPerRun", SECONDS_PER_RUN, "nMaternNuMethods", 0, ...
    "maternNuFactor", MATERN_NU_FACTOR);
seconds = 0;
if isempty(units)
    return
end
methods = alignest.buildMethodList(settings.methods);
specs = alignest.buildPlanSpecs(settings.sampling);
usesNu = contains(string({methods.variant}), "_nu");
detail.nMaternNuMethods = nnz(usesNu);
detail.nRuns = numel(units) * numel(specs) * numel(methods);
weights = ones(1, numel(methods));
weights(usesNu) = MATERN_NU_FACTOR;
seconds = SECONDS_PER_RUN * numel(units) * numel(specs) * sum(weights);
end
