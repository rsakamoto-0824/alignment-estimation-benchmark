function [seconds, detail] = estimateRunSeconds(units, settings)
%ESTIMATERUNSECONDS 評価にかかる時間の目安 [秒]（「2. 評価の設定」と「3. 実行」に出す）。
%   [seconds, detail] = alignest.estimateRunSeconds(data.units, settings)
%   目安 = 手法の当てはめ（Wafer × 学習パターン × 手法）＋ I 最適の学習パターンを作る時間 ＋ 指標の計算などの手間
%          ＋ 結果の表・グラフを画面に出す時間。
%   - 当てはめ：手法の系統ごとの1回（X・Y）の時間 × 質的変数の扱い・カーネルなどの倍率 × 学習点の数の倍率
%     （学習点が多いほど長い。学習点 120 点を 1 として、点数に比例）。
%   - I 最適：同じ配置の Wafer では1回だけ作る。交換法の手間（選ぶ数 × 残りの数）に比例。ランダム・手動・ファイルはほぼ 0。
%   値は M1 Mac・模擬データ（99 Shot・4 Mark）で測った時間から決めた（いくつかの設定で実際の 0.8〜0.95 倍の誤差）。
%   PC によっては数倍かかることがある。
%   detail.fitSeconds・planSeconds・overheadSeconds・displaySeconds は内訳、detail.nRuns は推定の回数。
FIT_SECONDS = struct("GPR", 0.035, "TPS", 0.012, "RBF", 0.05, "OK", 0.015, "UK", 0.02, "GAM", 0.045, ...
    "XY", 0.005, "RT", 0.007);                 % 学習点 120 点のときの1回（X・Y）[秒]
REFERENCE_TRAIN_POINTS = 120;
MIN_SIZE_FACTOR = 0.4;                         % 学習点が少なくても、これより短くはならない
GPR_MODE_FACTOR = struct("none", 1, "basis", 1.1, "basis_int", 1.1, "mixed", 1, "mixed_int", 2.4, ...
    "additive", 1.4, "additive_int", 2.5, "backfit", 3.3);
GPR_ARD_FACTOR = 1.8;                          % ard のカーネル（長さスケールが説明変数ごと）
GPR_MATERN_NU_FACTOR = 3.1;                    % ν を指定する Matérn（ベッセル関数の計算のぶん遅い）
BACKFIT_FACTOR = struct("TPS", 1.7, "RBF", 1.1, "OK", 3.5, "UK", 3.5);
GAM_GP_TERM_FACTOR = 1.2;                      % GAM のガウス過程の項1つごとに足す倍率
OVERHEAD_SECONDS_PER_RUN = 0.008;              % 指標・Overlay 補正の計算など（推定1回あたり）
PLAN_SECONDS_PER_PAIR = 0.0012;                % I 最適：選ぶ Shot × 残りの Shot あたり（初期配置 10 回）
PLAN_SECONDS_PER_SHOT = 0.03;
REFERENCE_EXCHANGE_STARTS = 10;
RESULT_DISPLAY_SECONDS = 2;                    % 評価の後に結果の表・グラフを画面に出す時間

detail = struct("fitSeconds", 0, "planSeconds", 0, "overheadSeconds", 0, "displaySeconds", 0, "nRuns", 0);
seconds = 0;
if isempty(units)
    return
end
methods = alignest.buildMethodList(settings.methods);
specs = alignest.buildPlanSpecs(settings.sampling);
[nCandidates, marksPerShot, nLayouts] = layoutSizes(units);
for spec = specs
    nShots = trainShotCount(spec, nCandidates);
    sizeFactor = max(MIN_SIZE_FACTOR, nShots * marksPerShot / REFERENCE_TRAIN_POINTS);
    for method = methods
        detail.fitSeconds = detail.fitSeconds + numel(units) * sizeFactor * FIT_SECONDS.(method.family) * ...
            methodFactor(method);
    end
    if spec.type == "ioptimal"
        exchange = PLAN_SECONDS_PER_PAIR * nShots * max(nCandidates - nShots, 0) + PLAN_SECONDS_PER_SHOT * nShots;
        detail.planSeconds = detail.planSeconds + nLayouts * exchange * ...
            settings.sampling.exchangeStarts / REFERENCE_EXCHANGE_STARTS;
    end
end
detail.nRuns = numel(units) * numel(specs) * numel(methods);
detail.overheadSeconds = OVERHEAD_SECONDS_PER_RUN * detail.nRuns;
detail.displaySeconds = RESULT_DISPLAY_SECONDS;
seconds = detail.fitSeconds + detail.planSeconds + detail.overheadSeconds + detail.displaySeconds;

    function factor = methodFactor(method)
        % 手法の系統の中での倍率（質的変数の扱い・カーネル・Backfitting・GAM のガウス過程の項）
        factor = 1;
        switch method.family
            case "GPR"
                if isfield(GPR_MODE_FACTOR, method.factorMode)
                    factor = GPR_MODE_FACTOR.(method.factorMode);
                end
                if startsWith(method.variant, "ard")
                    factor = factor * GPR_ARD_FACTOR;
                end
                if contains(method.variant, "_nu")
                    factor = factor * GPR_MATERN_NU_FACTOR;
                end
            case {"TPS", "RBF", "OK", "UK"}
                if method.factorMode == "backfit"
                    factor = BACKFIT_FACTOR.(method.family);
                end
            case "GAM"
                if startsWith(method.variant, "gp:")
                    nTerms = numel(split(extractAfter(method.variant, "gp:"), "+"));
                    factor = 1 + GAM_GP_TERM_FACTOR * nTerms;
                end
        end
    end
end

function nShots = trainShotCount(spec, nCandidates)
% 学習 Shot 数（計測率なら候補 Shot 数から。手動は指定した数）
nShots = spec.nShots;
if isfield(spec, "rate") && isfinite(spec.rate)
    nShots = max(1, round(spec.rate / 100 * nCandidates));
end
end

function [nCandidates, marksPerShot, nLayouts] = layoutSizes(units)
% 候補 Shot 数と Shot あたりの Mark 数（Wafer の平均）、学習パターンを作り直す配置の数（使える Mark の並びが違う Wafer の数）
candidateCounts = zeros(numel(units), 1);
markCounts = zeros(numel(units), 1);
signatures = strings(numel(units), 1);
for u = 1:numel(units)
    marks = units(u).marks;
    usable = marks.validX | marks.validY;
    candidateCounts(u) = nnz(units(u).shots.nValidX + units(u).shots.nValidY > 0);
    markCounts(u) = nnz(usable);
    signatures(u) = sprintf('%.3f,', [marks.x(usable); marks.y(usable); marks.direction(usable)]);
end
nCandidates = round(mean(candidateCounts));
marksPerShot = sum(markCounts) / max(sum(candidateCounts), 1);
nLayouts = numel(unique(signatures));
end
