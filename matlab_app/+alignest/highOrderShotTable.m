function data = highOrderShotTable(result)
%HIGHORDERSHOTTABLE Shot ごとの補正値（k パラメータ）を、1行 = 1 Shot、列 = k1〜kN に横に並べた表にする（「7. Shot高次補正」の
%   「書き出し」。装置に入れる Shot ごとの補正値に近い形）。
%   data = alignest.highOrderShotTable(result)
%   result：alignest.shotHighOrder の結果。行は Wafer の順・Shot の番号の順。列：Wafer・shotNo・Xmm・Ymm（Shot 中心 [mm]）・
%   Radius・範囲（内周・外周）・くくり（k の組の名前。Wafer 内で共通などでは、同じ組の Shot は同じ k）・点の数、使う項の
%   k（使う項を k の番号の順。外周の式を分けたときは両方の式の項。その Shot の式に無い項は空欄）、Wafer 成分 dx・dy（Shot 中心で
%   求めた Wafer 成分 [nm]）、メモ。k1・k2 は Wafer 成分を足した値（Shot 中心での並進）。足した分は Wafer 成分の列にある。
%   係数は mm の座標での値（列の名前の単位：k1・k2 は nm、1次は nm/mm、n 次は nm/mm^n）。補正しなかった Shot は空欄。
arguments
    result struct
end
FORMULA_AXES = ["dx", "dy"];
points = result.points(isfinite(result.points.shotNo), :);
coefficients = result.coefficients;
terms = result.terms(result.terms.used, :);
[~, first] = unique(terms.k);   % 外周の式を分けたときは、内周・外周の式の項をまとめる
terms = terms(first, :);
names = "k" + string(terms.k) + "[" + unitOf(terms.order) + "]";
waferLabels = unique(points.wafer, 'stable');
parts = cell(numel(waferLabels), 1);
for w = 1:numel(waferLabels)
    mine = points(points.wafer == waferLabels(w), :);
    [shots, firstRows] = unique(mine.shotNo);
    nShots = numel(shots);
    Xc = mine.x(firstRows) - mine.localX(firstRows);
    Yc = mine.y(firstRows) - mine.localY(firstRows);
    groups = mine.group(firstRows);
    rows = coefficients(coefficients.wafer == waferLabels(w), :);
    shotRows = rows(rows.component == "Shot 高次補正", :);
    waferRows = rows(rows.component == "Wafer 成分", :);
    values = nan(nShots, height(terms));
    waferPart = zeros(nShots, 2);
    corrected = false(nShots, 1);
    counts = zeros(nShots, 1);
    for s = 1:nShots
        inShot = mine.shotNo == shots(s);
        counts(s) = nnz(inShot & (isfinite(mine.valueX) | isfinite(mine.valueY)));
        if result.options.unit == "shot"
            own = shotRows(shotRows.shotNo == shots(s), :);
        else
            own = shotRows(shotRows.group == groups(s), :);
        end
        corrected(s) = ~isempty(own);
        [found, column] = ismember(own.k, terms.k);
        values(s, column(found)) = own.value(found).';
        for a = 1:2
            axisRows = waferRows(waferRows.axis == FORMULA_AXES(a), :);
            waferPart(s, a) = sum(axisRows.value .* Xc(s) .^ axisRows.xPower .* Yc(s) .^ axisRows.yPower);
        end
    end
    waferPart(~corrected, :) = NaN;
    for a = 1:2
        column = find(terms.k == a, 1);   % k1（dx の定数）・k2（dy の定数）に Wafer 成分を足す
        if ~isempty(column)
            values(:, column) = values(:, column) + waferPart(:, a);
        end
    end
    note = strings(nShots, 1);
    note(~corrected) = "補正しなかった（点が足りない・点の配置で項が決まらない）";
    parts{w} = [table(repmat(waferLabels(w), nShots, 1), shots, Xc, Yc, hypot(Xc, Yc), mine.zone(firstRows), groups, ...
        counts, 'VariableNames', ["Wafer", "shotNo", "Xmm", "Ymm", "Radius", "範囲", "くくり", "点の数"]), ...
        array2table(values, 'VariableNames', cellstr(names)), table(waferPart(:, 1), waferPart(:, 2), note, ...
        'VariableNames', ["Wafer成分dx[nm](k1に含む)", "Wafer成分dy[nm](k2に含む)", "メモ"])];
end
data = vertcat(parts{:});
end

function text = unitOf(order)
% 係数の単位（mm の座標での値）
text = "nm/mm^" + string(order);
text(order == 0) = "nm";
text(order == 1) = "nm/mm";
end
