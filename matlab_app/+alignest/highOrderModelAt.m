function [dx, dy] = highOrderModelAt(coefficients, unit, waferLabel, shots, local, part)
%HIGHORDERMODELAT 求めた Shot 高次補正の式（alignest.shotHighOrder の result.coefficients）の値を、Shot 内の好きな位置で求める
%   （Shot の形のグリッド、2次以上の項だけの補正量）。
%   [dx, dy] = alignest.highOrderModelAt(coefficients, unit, waferLabel, shots, local, part)
%   unit：補正のくくり（"common"・"scan"・"row"・"shot"。result.options.unit）、waferLabel：Wafer の名前、
%   shots：Shot ごとの表（shotNo・Xc・Yc（Shot 中心 [mm]）・group（その Shot の k の組の名前。result.points.group））、
%   local：Shot 内の位置 [mm]（位置の数 × 2）、part："all"（すべての項と Wafer 成分）・"highOrder"（2次以上の項だけ）。
%   dx・dy：Shot の数 × 位置の数 [nm]。補正しなかった Shot（係数の無い Shot）は NaN。
arguments
    coefficients table
    unit (1, 1) string
    waferLabel (1, 1) string
    shots table
    local double
    part (1, 1) string {mustBeMember(part, ["all", "highOrder"])} = "all"
end
HIGH_ORDER = 2;   % これ以上の次数を「高次の項」とする
rows = coefficients(coefficients.wafer == waferLabel, :);
nShots = height(shots);
nPoints = size(local, 1);
[dx, dy] = deal(nan(nShots, nPoints));
axisNames = ["dx", "dy"];
for a = 1:2
    axisRows = rows(rows.axis == axisNames(a), :);
    shotTerms = axisRows(axisRows.component == "Shot 高次補正", :);
    waferTerms = axisRows(axisRows.component == "Wafer 成分", :);
    if part == "highOrder"
        shotTerms = shotTerms(shotTerms.xPower + shotTerms.yPower >= HIGH_ORDER, :);
        waferTerms = waferTerms([], :);
    end
    values = nan(nShots, nPoints);
    for s = 1:nShots
        if unit == "shot"
            mine = shotTerms(shotTerms.shotNo == shots.shotNo(s), :);
        else
            mine = shotTerms(shotTerms.group == shots.group(s), :);
        end
        hasGroup = unit == "shot" && any(axisRows.shotNo == shots.shotNo(s)) || ...
            unit ~= "shot" && any(axisRows.group == shots.group(s));
        if ~hasGroup
            continue   % 補正しなかった Shot・k の組
        end
        value = local(:, 1) .^ (mine.xPower.') .* local(:, 2) .^ (mine.yPower.') * mine.value;
        if isempty(mine)
            value = zeros(nPoints, 1);
        end
        if ~isempty(waferTerms)
            value = value + sum(waferTerms.value .* shots.Xc(s) .^ waferTerms.xPower .* shots.Yc(s) .^ waferTerms.yPower);
        end
        values(s, :) = value.';
    end
    if a == 1
        dx = values;
    else
        dy = values;
    end
end
end
