function data = highOrderShotTable(result)
%HIGHORDERSHOTTABLE Shot ごとの補正値を、1行 = 1 Shot に、Wafer 低次・Wafer 高次・Wafer RT・Shot 共通 低次・Shot 共通 高次・Shot 毎 低次・
%   Shot 毎 高次の順に横に並べた表にする（「7. Shot高次補正」の「書き出し」。段階の分け方は alignest.highOrderLevels）。
%   data = alignest.highOrderShotTable(result)
%   result：alignest.shotHighOrder の結果。行は Wafer の順・Shot の番号の順。列：
%   - Wafer・shotNo・Xmm・Ymm（Shot 中心 [mm]）・Radius・範囲（内周・外周）・くくり（k の組の名前）・点の数
%   - Wafer 低次 dx・dy、Wafer 高次 dx・dy：Wafer 成分のその次数の項を Shot 中心で求めた値 [nm]（その Shot の並進になる）
%     RT で補正する Shot は空欄
%   - Wafer RT dx・dy：Wafer RT の補正量 [nm]（その Shot の並進になる。Wafer RT を使うときだけの列。RT で補正しない Shot は空欄）
%   - Shot 共通の k、Shot 毎の k（くくりが Shot ごとのときだけ。ほかは空欄）：それぞれ低次（k1〜k6）、高次（k7〜）の順
%   - 合計の k：その Shot に当てる k（Shot 共通 + Shot 毎。k1・k2 には Wafer 低次・高次・RT の並進も足す）
%   - 決定係数・自由度調整済決定係数（X・Y。その Shot の k の組の回帰。alignest.highOrderRSquared）
%   - メモ（補正しなかった Shot、点が足りず項を減らした Shot）
%   k は使う項（外周の式を分けたときは両方の式の項）。その Shot の式に無い項は空欄。係数は mm の座標での値（列の名前の単位：
%   k1・k2 は nm、1次は nm/mm、n 次は nm/mm^n）。補正しなかった Shot は値が空欄。
arguments
    result struct
end
HIGH_ORDER = 2;   % これ以上の次数を「高次」とする（alignest.highOrderLevels と同じ）
CONSTANT_K = [1, 2];   % dx・dy の定数の k（Wafer 成分・Wafer RT の並進を足す）
points = result.points(isfinite(result.points.shotNo), :);
levels = alignest.highOrderLevels(result);
terms = result.terms(result.terms.used, :);
[~, first] = unique(terms.k);   % 外周の式を分けたときは、内周・外周の式の項をまとめる
terms = terms(first, :);
[~, order] = sortrows([terms.order >= HIGH_ORDER, terms.k]);   % 低次（k1〜k6）、高次の順
terms = terms(order, :);
names = "k" + string(terms.k) + "[" + unitOf(terms.order) + "]";
perShot = result.options.unit == "shot";
zoneSplit = result.options.outerMaker ~= "none";
reductions = result.groupReductions;
waferLabels = unique(points.wafer, 'stable');
parts = cell(numel(waferLabels), 1);
for w = 1:numel(waferLabels)
    mine = points(points.wafer == waferLabels(w), :);
    [shots, firstRows] = unique(mine.shotNo);
    nShots = numel(shots);
    Xc = mine.x(firstRows) - mine.localX(firstRows);
    Yc = mine.y(firstRows) - mine.localY(firstRows);
    groups = mine.group(firstRows);
    zones = mine.zone(firstRows);
    rows = levels(levels.wafer == waferLabels(w), :);
    waferRows = rows(startsWith(rows.level, "Wafer"), :);
    commonRows = rows(startsWith(rows.level, "Shot 共通"), :);
    eachRows = rows(startsWith(rows.level, "Shot 毎"), :);
    waferPart = nan(nShots, 4);   % 低次 dx・dy、高次 dx・dy
    rtPart = nan(nShots, 2);      % Wafer RT の dx・dy
    [common, each] = deal(nan(nShots, height(terms)));
    counts = zeros(nShots, 1);
    regression = nan(nShots, 4);   % R²・調整済 R²（X）、R²・調整済 R²（Y）
    note = strings(nShots, 1);
    for s = 1:nShots
        inShot = mine.shotNo == shots(s);
        counts(s) = nnz(inShot & (isfinite(mine.valueX) | isfinite(mine.valueY)));
        if ~any(inShot & (isfinite(mine.correctionX) | isfinite(mine.correctionY)))
            note(s) = "補正しなかった（点が足りない・点の配置で項が決まらない）";
            continue
        end
        members = inShot;
        if ~perShot
            members = mine.group == groups(s);
        end
        [regression(s, 1), regression(s, 2)] = alignest.highOrderRSquared(mine.valueX(members), mine.residualX(members), ...
            mine.leverageX(members));
        [regression(s, 3), regression(s, 4)] = alignest.highOrderRSquared(mine.valueY(members), mine.residualY(members), ...
            mine.leverageY(members));
        if mine.waferRtUsed(firstRows(s))
            rtPart(s, :) = [mine.waferRtX(firstRows(s)), mine.waferRtY(firstRows(s))];
        else
            for part = 1:4
                levelRows = waferRows(waferRows.level == ternary(part <= 2, "Wafer 低次", "Wafer 高次") & ...
                    waferRows.axis == ternary(mod(part, 2) == 1, "dx", "dy"), :);
                waferPart(s, part) = sum(levelRows.value .* Xc(s) .^ levelRows.xPower .* Yc(s) .^ levelRows.yPower);
            end
        end
        if perShot
            zone = ternary(zoneSplit, zones(s), "");
            common(s, :) = valuesByK(commonRows(commonRows.zone == zone, :), terms.k);
            each(s, :) = valuesByK(eachRows(eachRows.shotNo == shots(s), :), terms.k);
            mineReduced = reductions(reductions.wafer == waferLabels(w) & reductions.shotNo == shots(s), :);
        else
            common(s, :) = valuesByK(commonRows(commonRows.group == groups(s), :), terms.k);
            mineReduced = reductions(reductions.wafer == waferLabels(w) & reductions.group == groups(s), :);
        end
        if height(mineReduced) > 0
            note(s) = "点が足りず項を減らした（" + strjoin(mineReduced.axis + "：" + mineReduced.dropped, "、") + ...
                " を使わない）";
        end
    end
    % 合計：Shot 共通 + Shot 毎（どちらも無い項は空欄）。k1・k2 には Wafer 成分・Wafer RT の並進を足す
    total = sum(cat(3, common, each), 3, 'omitnan');
    total(isnan(common) & isnan(each)) = NaN;
    for a = 1:2
        column = find(terms.k == CONSTANT_K(a), 1);
        if ~isempty(column)
            total(:, column) = total(:, column) + sum([waferPart(:, [a, a + 2]), rtPart(:, a)], 2, 'omitnan');
        end
    end
    waferColumns = array2table(waferPart, 'VariableNames', ["Wafer低次dx[nm]", "Wafer低次dy[nm]", "Wafer高次dx[nm]", ...
        "Wafer高次dy[nm]"]);
    if result.options.waferRtRange ~= "none"
        waferColumns = [waferColumns, array2table(rtPart, 'VariableNames', ["WaferRTdx[nm]", "WaferRTdy[nm]"])]; %#ok<AGROW>
    end
    parts{w} = [table(repmat(waferLabels(w), nShots, 1), shots, Xc, Yc, hypot(Xc, Yc), zones, groups, counts, ...
        'VariableNames', ["Wafer", "shotNo", "Xmm", "Ymm", "Radius", "範囲", "くくり", "点の数"]), ...
        waferColumns, array2table(common, 'VariableNames', cellstr("Shot共通" + names)), ...
        array2table(each, 'VariableNames', cellstr("Shot毎" + names)), ...
        array2table(total, 'VariableNames', cellstr("合計" + names)), array2table(regression, 'VariableNames', ...
        ["決定係数R2X", "自由度調整済決定係数X", "決定係数R2Y", "自由度調整済決定係数Y"]), table(note, 'VariableNames', "メモ")];
end
data = vertcat(parts{:});
end

function values = valuesByK(rows, kNumbers)
% 行の値を k の番号の列に並べる（無い k は NaN）
values = nan(1, numel(kNumbers));
[found, column] = ismember(rows.k, kNumbers);
values(column(found)) = rows.value(found);
end

function text = unitOf(order)
% 係数の単位（mm の座標での値）
text = "nm/mm^" + string(order);
text(order == 0) = "nm";
text(order == 1) = "nm/mm";
end

function value = ternary(condition, whenTrue, whenFalse)
if condition
    value = whenTrue;
else
    value = whenFalse;
end
end
