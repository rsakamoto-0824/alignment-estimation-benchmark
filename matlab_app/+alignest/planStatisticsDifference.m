function difference = planStatisticsDifference(unit, plan)
%PLANSTATISTICSDIFFERENCE 計測配置（学習パターン）の点の計測値の統計量が、全計測の統計量とどれだけ違うか。
%   difference = alignest.planStatisticsDifference(unit, plan)
%   unit：評価の単位（Wafer）、plan：学習パターン（alignest.planTrainingShots の結果）。
%   X・Y 別に、全計測（その軸が有効なすべての Mark）と、計測配置の点（alignest.trainingMarks の Mark のうち有効な Mark）の
%   計測値の平均・中央値・分散（不偏分散）・最大・最小を求め、差（計測配置の点 − 全計測）を出す。
%   difference.table：統計量ごとの表（statistic・fullX・fullY・planX・planY・differenceX・differenceY）。点が足りない
%   統計量は NaN（分散は2点以上）。difference.nPoints：[全計測 X, Y; 計測配置 X, Y]
arguments
    unit struct
    plan struct
end
STATISTICS = ["平均", "中央値", "分散", "最大", "最小"];
AXIS_NAMES = ["X", "Y"];
marks = unit.marks;
used = alignest.trainingMarks(unit, plan) & plan.ok;
[full, planned] = deal(nan(numel(STATISTICS), 2));
nPoints = zeros(2, 2);
for a = 1:2
    valid = marks.("valid" + AXIS_NAMES(a));
    values = marks.("meas" + AXIS_NAMES(a));
    fullValues = values(valid & isfinite(values));
    planValues = values(valid & used & isfinite(values));
    nPoints(:, a) = [numel(fullValues); numel(planValues)];
    full(:, a) = statisticsOf(fullValues);
    planned(:, a) = statisticsOf(planValues);
end
difference.table = table(reshape(STATISTICS, [], 1), full(:, 1), full(:, 2), planned(:, 1), planned(:, 2), ...
    planned(:, 1) - full(:, 1), planned(:, 2) - full(:, 2), 'VariableNames', ["statistic", "fullX", "fullY", "planX", ...
    "planY", "differenceX", "differenceY"]);
difference.nPoints = nPoints;
end

function values = statisticsOf(data)
% 平均・中央値・分散（不偏分散。2点以上）・最大・最小（点が無ければ NaN）
values = nan(5, 1);
if isempty(data)
    return
end
values([1, 2, 4, 5]) = [mean(data); median(data); max(data); min(data)];
if numel(data) >= 2
    values(3) = var(data);
end
end
