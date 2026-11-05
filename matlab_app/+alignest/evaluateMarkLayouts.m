function evaluation = evaluateMarkLayouts(designs, selected, values, penalized, fitOptions, progressFcn)
%EVALUATEMARKLAYOUTS Mark の配置ごとに、選んだ Mark の値で補正の式を当てはめ、すべての Mark の制御残差（補正した後に残る値）を求める。
%   evaluation = alignest.evaluateMarkLayouts(designs, selected, values, penalized, fitOptions)
%   evaluation = alignest.evaluateMarkLayouts(..., progressFcn)   % progressFcn(済んだ数, 全体の数) が false なら止める
%   designs：{dx の式, dy の式} の設計行列（候補の数 × 項の数。Shot 内の座標 [mm] の項の値）。
%   selected：配置（候補の数 × 配置の数の logical。列ごとに計測する Mark）。
%   values：fitX・fitY（当てはめに使う値。候補の数 × Shot の数 [nm]。値の無い点は NaN）と、referenceX・referenceY（制御残差を
%   求める値。実測値なら fit と同じ、乱数の形なら計測のばらつき・飛び値を足す前の形）。
%   penalized：{dx の式, dy の式} の正則化をかける項（項の数 × 1）。fitOptions：alignest.robustRidgeFit の名前と値の組
%   （loss・huberTuning・lambda・penalty）。
%   Shot ごと・配置ごとに、配置の Mark のうち値のある点で当てはめ（alignest.robustRidgeFit）、値のあるすべての候補の位置で
%   制御残差 = 値 − 補正量 を求める。使う項が決まらない Shot（値の無い Mark があって点が足りないなど）は補正しない（数える）。
%   最小二乗で正則化が L2 か無いときは、当てはめが値の一次式なので、配置ごとに1度求めた係数の式を、値がそろった Shot に
%   まとめて使う（Shot ごとに当てはめたときと同じ値）。
%   evaluation：配置と軸（X・Y）ごとの表。layout（配置の番号）・axis・nShots（補正した Shot の数）・skipped（補正しなかった
%   Shot の数）・nPoints（制御残差の点の数）・meanPlus3Sigma・p95（|制御残差| の 95% 点）・median（|制御残差| の中央値）・rms
%   [nm]、unmeasured…（計測しなかった Mark だけの同じ値。計測しなかった Mark が無ければ NaN）。
arguments
    designs cell
    selected logical
    values struct
    penalized cell
    fitOptions cell
    progressFcn = []
end
AXIS_NAMES = ["X", "Y"];
FIT_FIELDS = ["fitX", "fitY"];
REFERENCE_FIELDS = ["referenceX", "referenceY"];
STAT_NAMES = ["meanPlus3Sigma", "p95", "median", "rms"];
options = struct(fitOptions{:});
linear = options.loss == "ols" && (options.penalty == "l2" || options.lambda == 0);
nLayouts = size(selected, 2);
parts = cell(nLayouts, 2);
for k = 1:nLayouts
    rows = selected(:, k);
    for a = 1:2
        A = designs{a};
        fitValues = values.(FIT_FIELDS(a));
        reference = values.(REFERENCE_FIELDS(a));
        nShots = size(fitValues, 2);
        predicted = nan(size(reference));
        fitted = false(1, nShots);
        complete = all(isfinite(fitValues(rows, :)), 1);
        if linear && any(complete)
            [operator, determined] = linearOperator(A(rows, :), penalized{a}, fitOptions);
            if determined
                predicted(:, complete) = A * (operator * fitValues(rows, complete));
                fitted(complete) = true;
            end
            others = find(~complete);
        else
            others = 1:nShots;
        end
        for s = others
            use = rows & isfinite(fitValues(:, s));
            if ~any(use)
                continue
            end
            fit = alignest.robustRidgeFit(A(use, :), fitValues(use, s), penalized{a}, fitOptions{:});
            if all(fit.determined)
                predicted(:, s) = A * fit.coefficients;
                fitted(s) = true;
            end
        end
        residual = reference - predicted;
        residual(:, ~fitted) = NaN;
        allStats = statistics(residual(:));
        unmeasured = residual(~rows, :);
        unmeasuredStats = statistics(unmeasured(:));
        parts{k, a} = [table(k, AXIS_NAMES(a), nnz(fitted), nShots - nnz(fitted), nnz(isfinite(residual)), ...
            'VariableNames', ["layout", "axis", "nShots", "skipped", "nPoints"]), ...
            array2table([allStats, unmeasuredStats], 'VariableNames', [STAT_NAMES, "unmeasured" + upperFirst(STAT_NAMES)])];
    end
    if ~isempty(progressFcn) && ~progressFcn(k, nLayouts)
        parts = parts(1:k, :);
        break
    end
end
evaluation = vertcat(parts{:});
end

function [operator, determined] = linearOperator(A, isPenalized, fitOptions)
% 当てはめが値の一次式のとき（最小二乗・L2 か正則化なし）、係数 = operator × 値 の operator（項の数 × 点の数）。
% 点ごとに値が 1・ほかが 0 の値で当てはめて求める（alignest.robustRidgeFit と同じ列のそろえ方・罰則）
n = size(A, 1);
operator = zeros(size(A, 2), n);
determined = true;
for i = 1:n
    unit = zeros(n, 1);
    unit(i) = 1;
    fit = alignest.robustRidgeFit(A, unit, isPenalized, fitOptions{:});
    if ~all(fit.determined)
        determined = false;
        return
    end
    operator(:, i) = fit.coefficients;
end
end

function values = statistics(residual)
% [|平均|+3σ, |残差| の 95% 点, |残差| の中央値, RMS]（点が無ければ NaN。|平均|+3σ は2点以上）
residual = residual(isfinite(residual));
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

function names = upperFirst(names)
names = upper(extractBefore(names, 2)) + extractAfter(names, 1);
end
