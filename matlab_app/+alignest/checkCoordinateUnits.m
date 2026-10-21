function checks = checkCoordinateUnits(raw, mapping, units)
%CHECKCOORDINATEUNITS 座標の列ごとに、選んだ入力単位で mm に直したときの大きさが妥当かを確かめ、合う単位を推定する。
%   checks = alignest.checkCoordinateUnits(raw, mapping, units)
%   妥当な範囲（絶対値の最大）の目安：Shot 中心（Xmm・Ymm・Radius）は 10〜300 mm、Mark（markXmm・markYmm）は
%   0.05〜50 mm（300 mm Wafer と一般的な Shot の大きさから決めた目安）。範囲に入る単位が見つかれば suggested に入れる。
%   checks は列ごとの表：name, column, unit, scale, maxInput（ファイルの値の絶対値の最大）, maxMm（mm に直した値）,
%   ok（範囲内か。判定できなければ true）, suggested（推定した単位。無ければ ""）, message（画面に出す確認の文）。
SHOT_RANGE_MM = [10, 300];
MARK_RANGE_MM = [0.05, 50];
CANDIDATES = ["mm", "um", "nm", "m"];  % 推定するとき、先にある単位を優先する
[units, scale] = alignest.coordinateUnits(units);
names = string(fieldnames(units));
n = numel(names);
columnName = strings(n, 1);
unitName = strings(n, 1);
scaleValue = zeros(n, 1);
maxInput = nan(n, 1);
maxMm = nan(n, 1);
ok = true(n, 1);
suggested = strings(n, 1);
message = strings(n, 1);
for k = 1:n
    name = names(k);
    unitName(k) = units.(name);
    scaleValue(k) = scale.(name);
    if isfield(mapping, name) && strlength(string(mapping.(name))) > 0 && ...
            any(string(raw.Properties.VariableNames) == string(mapping.(name)))
        columnName(k) = mapping.(name);
        values = raw.(columnName(k));
        if ~isnumeric(values)
            values = str2double(string(values));
        end
        values = abs(double(values(isfinite(double(values)))));
        if ~isempty(values)
            maxInput(k) = max(values);
        end
    end
    if columnName(k) == ""
        message(k) = "列なし";
        continue
    end
    if ~(maxInput(k) > 0)
        message(k) = "— 値なし・すべて 0";
        continue
    end
    range = SHOT_RANGE_MM;
    if startsWith(name, "mark")
        range = MARK_RANGE_MM;
    end
    maxMm(k) = maxInput(k) * scaleValue(k);
    ok(k) = maxMm(k) >= range(1) && maxMm(k) <= range(2);
    for candidate = CANDIDATES
        [~, candidateScale] = alignest.coordinateUnits(struct(name, candidate));
        value = maxInput(k) * candidateScale.(name);
        if value >= range(1) && value <= range(2)
            suggested(k) = candidate;
            break
        end
    end
    if ok(k)
        message(k) = "OK";
    elseif suggested(k) ~= ""
        message(k) = sprintf("⚠ 大きさが目安（%g〜%g mm）の外。%s なら %.4g mm", range, ...
            replace(suggested(k), "um", "µm"), maxInput(k) * scaleFor(name, suggested(k)));
    else
        message(k) = sprintf("⚠ 大きさが目安（%g〜%g mm）の外", range);
    end
end
checks = table(names, columnName, unitName, scaleValue, maxInput, maxMm, ok, suggested, message, ...
    'VariableNames', ["name", "column", "unit", "scale", "maxInput", "maxMm", "ok", "suggested", "message"]);
end

function value = scaleFor(name, unit)
[~, scale] = alignest.coordinateUnits(struct(name, unit));
value = scale.(name);
end
