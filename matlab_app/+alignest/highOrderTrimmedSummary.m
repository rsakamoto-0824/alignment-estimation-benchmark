function trimmed = highOrderTrimmedSummary(points, n)
%HIGHORDERTRIMMEDSUMMARY Shot 高次補正の残差の |平均|+3σ を、外れ値を除いて求める（「6. Shot高次補正」の補正の評価）。
%   trimmed = alignest.highOrderTrimmedSummary(points, n)
%   points：alignest.shotHighOrder の result.points（wafer・zone・residualX/Y・linearResidualX/Y の列を使う）。
%   n：外れ値の判定の幅（既定 3）。Wafer ごと・軸ごとに、高次補正の残差 r の中央値 m と MAD（中央絶対偏差）から
%      |r − m| > n × 1.4826 × MAD の点を外れ値とする（1.4826 × MAD は正規分布なら σ と同じ大きさ。外れ値に引きずられにくい）。
%      MAD が 0（ほとんど同じ値）なら外れ値は無いとする。
%   比べる点は補正の評価と同じ（高次補正と Shot ごとの1次のどちらも求められた点）。外れ値を除いた残りで |平均|+3σ を求める。
%   trimmed：表（wafer・axis・region・highOrderTrimmed・trimmedOutliers）。region は "すべて"・"内周"・"外周"、wafer の
%   "すべての Wafer" はすべての点（外れ値は各 Wafer で決めたもの）。
arguments
    points table
    n (1, 1) double {mustBePositive} = 3
end
MAD_SCALE = 1.4826;   % 正規分布で MAD を σ にそろえる係数
ALL_LABEL = "すべての Wafer";
REGIONS = ["すべて", "内周", "外周"];
AXIS_NAMES = ["X", "Y"];
waferNames = unique(points.wafer, 'stable');
rows = cell(0, 1);
for a = 1:2
    axisName = AXIS_NAMES(a);
    residual = points.("residual" + axisName);
    compared = isfinite(residual) & isfinite(points.("linearResidual" + axisName));
    outlier = false(height(points), 1);
    for w = 1:numel(waferNames)
        mine = compared & points.wafer == waferNames(w);
        values = residual(mine);
        center = median(values);
        spread = MAD_SCALE * median(abs(values - center));
        if spread > 0
            outlier(mine) = abs(values - center) > n * spread;
        end
    end
    for w = 0:numel(waferNames)
        if w == 0
            inWafer = true(height(points), 1);
            label = ALL_LABEL;
        else
            inWafer = points.wafer == waferNames(w);
            label = waferNames(w);
        end
        for region = REGIONS
            inRegion = inWafer;
            if region ~= "すべて"
                inRegion = inWafer & points.zone == region;
            end
            kept = compared & inRegion & ~outlier;
            rows{end + 1, 1} = table(label, axisName, region, meanPlus3Sigma(residual(kept)), ...
                nnz(compared & inRegion & outlier), 'VariableNames', ["wafer", "axis", "region", ...
                "highOrderTrimmed", "trimmedOutliers"]); %#ok<AGROW>
        end
    end
end
trimmed = vertcat(rows{:});
end

function value = meanPlus3Sigma(values)
% |平均| + 3σ（σ は不偏標準偏差）。点が2点未満なら NaN（alignest.shotHighOrder と同じ）
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end
