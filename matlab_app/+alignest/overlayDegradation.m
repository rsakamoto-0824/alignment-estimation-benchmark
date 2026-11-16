function degradation = overlayDegradation(results, xKind, yKind, statistic)
%OVERLAYDEGRADATION 推定による重ね合わせ補正（Overlay 補正）の悪化を、推定誤差・計測数に対して並べる表。
%   degradation = alignest.overlayDegradation(results, xKind, yKind, statistic)
%   xKind："error"（推定誤差 RMSE（X・Y 合計） [nm]）・"marks"（計測する Mark の数）・"shots"（学習 Shot 数）
%   yKind："overlayIncrease"（推定による増加：推定値で補正した残差の |平均|+3σ − 実測値で補正した残差の |平均|+3σ）・
%          "overlayChange"（推定による残差の変化（推定値で補正 − 実測値で補正）の |平均|+3σ）。X・Y 別（_X・_Y の列）
%   statistic：Wafer 間の集計（alignest.summarizeResults と同じ。推定誤差の横軸も同じ集計。計測数は Wafer の平均）。
%   Wafer ごとの値は、ランダムのくり返しを平均した値（alignest.perUnitValues）。
%   degradation.points：手法 × 学習パターンの列の表（methodIndex・method・group・x・valueX・valueY・nWafers と、Wafer ごとの
%     値のばらつき sdX・sdY（標準偏差。2枚未満は NaN）・seX・seY（平均の標準誤差）・minX・maxX・minY・maxY（最小・最大）。
%     エラーバーは alignest.layoutErrorBars と同じ求め方）。値の無い組（Overlay 補正を評価していない・推定できなかった）は入れない
%   degradation.wafers：Wafer ごとの点の表（methodIndex・group・unitIndex・x・valueX・valueY）
%   Overlay 補正を評価していない結果（results.overlayEvaluated が false）では、どちらも空の表。
arguments
    results struct
    xKind (1, 1) string {mustBeMember(xKind, ["error", "marks", "shots"])} = "error"
    yKind (1, 1) string {mustBeMember(yKind, ["overlayIncrease", "overlayChange"])} = "overlayIncrease"
    statistic (1, 1) string = "mean"
end
points = table(zeros(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    'VariableNames', ["methodIndex", "method", "group", "x", "valueX", "valueY", "nWafers", "sdX", "sdY", "seX", "seY", ...
    "minX", "maxX", "minY", "maxY"]);
wafers = table(zeros(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    'VariableNames', ["methodIndex", "group", "unitIndex", "x", "valueX", "valueY"]);
degradation = struct("points", points, "wafers", wafers, "xKind", xKind, "yKind", yKind, "statistic", statistic);
columns = string(results.table.Properties.VariableNames);
if ~(isfield(results, "overlayEvaluated") && results.overlayEvaluated) || ~all(ismember(yKind + ["_X", "_Y"], columns))
    return
end
groups = reshape(string(results.groups), 1, []);
nMethods = numel(results.methods);
units = reshape(alignest.evaluatedUnits(results), [], 1);
summaryX = alignest.summarizeResults(results, yKind + "_X", statistic);
summaryY = alignest.summarizeResults(results, yKind + "_Y", statistic);
perX = alignest.perUnitValues(results, yKind + "_X");
perY = alignest.perUnitValues(results, yKind + "_Y");
perAxis = unitAxisValues(results, xKind, groups);   % 手法 × 列 の cell（Wafer ごとの横軸の値）
if xKind == "error"
    groupAxis = alignest.summarizeResults(results, "RMSE_XY", statistic).values;
else
    groupAxis = cellfun(@(values) mean(values(units), 'omitnan'), perAxis);   % 計測数は Wafer の平均
end
methodLabels = string({results.methods.label});
pointRows = cell(nMethods * numel(groups), 1);
waferRows = cell(nMethods * numel(groups), 1);
for m = 1:nMethods
    for g = 1:numel(groups)
        index = (m - 1) * numel(groups) + g;
        if isfinite(groupAxis(m, g)) && (isfinite(summaryX.values(m, g)) || isfinite(summaryY.values(m, g)))
            spreadX = waferSpread(perX{m, g}(units));
            spreadY = waferSpread(perY{m, g}(units));
            pointRows{index} = table(m, methodLabels(m), groups(g), groupAxis(m, g), summaryX.values(m, g), ...
                summaryY.values(m, g), max(summaryX.counts(m, g), summaryY.counts(m, g)), spreadX.sd, spreadY.sd, ...
                spreadX.se, spreadY.se, spreadX.min, spreadX.max, spreadY.min, spreadY.max, 'VariableNames', ...
                points.Properties.VariableNames);
        end
        x = perAxis{m, g}(units);
        valueX = perX{m, g}(units);
        valueY = perY{m, g}(units);
        keep = isfinite(x) & (isfinite(valueX) | isfinite(valueY));
        if any(keep)
            waferRows{index} = table(repmat(m, nnz(keep), 1), repmat(groups(g), nnz(keep), 1), units(keep), x(keep), ...
                valueX(keep), valueY(keep), 'VariableNames', wafers.Properties.VariableNames);
        end
    end
end
degradation.points = [points; vertcat(pointRows{:})];
degradation.wafers = [wafers; vertcat(waferRows{:})];
end

function spread = waferSpread(values)
% Wafer ごとの値のばらつき：標準偏差（2枚未満は NaN）・平均の標準誤差・最小・最大
values = values(isfinite(values));
spread = struct("sd", NaN, "se", NaN, "min", NaN, "max", NaN);
if isempty(values)
    return
end
spread.min = min(values);
spread.max = max(values);
if numel(values) >= 2
    spread.sd = std(values);
    spread.se = spread.sd / sqrt(numel(values));
end
end

function perAxis = unitAxisValues(results, xKind, groups)
% Wafer ごとの横軸の値（手法 × 列 の cell。各要素は Wafer 数の列。値の無い Wafer は NaN）。
% 推定誤差・学習 Shot 数は結果の行から（ランダムのくり返しは平均）、計測する Mark の数は学習パターンから（Mark 単位も）
nMethods = numel(results.methods);
switch xKind
    case "error"
        perAxis = alignest.perUnitValues(results, "RMSE_XY");
    case "shots"
        perAxis = alignest.perUnitValues(results, "nShots");
    otherwise
        nUnits = numel(results.unitLabels);
        plans = results.plans;
        counts = nan(nUnits, numel(groups));
        if isfield(plans, "nMarks") && isfield(plans, "unitIndex")
            planGroups = string({plans.group});
            for g = 1:numel(groups)
                for u = 1:nUnits
                    mine = [plans(planGroups == groups(g) & [plans.unitIndex] == u).nMarks];
                    mine = mine(mine > 0);
                    if ~isempty(mine)
                        counts(u, g) = mean(mine);
                    end
                end
            end
        end
        perAxis = repmat(num2cell(counts, 1), nMethods, 1);   % 計測する Mark の数は手法によらない
end
end
