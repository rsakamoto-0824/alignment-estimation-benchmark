function [seconds, detail] = estimateRunSeconds(units, settings)
%ESTIMATERUNSECONDS 評価にかかる時間の目安 [秒]（「2. 評価の設定」と「3. 実行」に出す）。
%   [seconds, detail] = alignest.estimateRunSeconds(data.units, settings)
%   目安 = 1条件（Wafer × 学習パターン × 手法 の1つ）あたり 2 秒 × 条件の数。
%   手法や学習 Shot 数で時間は違うが、目安は分かりやすさのため一律にする（会社の PC での使い方に合わせた値）。
%   detail.nRuns は条件の数（推定の回数）、detail.secondsPerRun は1条件あたりの秒数。
SECONDS_PER_RUN = 2;
detail = struct("nRuns", 0, "secondsPerRun", SECONDS_PER_RUN);
seconds = 0;
if isempty(units)
    return
end
methods = alignest.buildMethodList(settings.methods);
specs = alignest.buildPlanSpecs(settings.sampling);
detail.nRuns = numel(units) * numel(specs) * numel(methods);
seconds = SECONDS_PER_RUN * detail.nRuns;
end
