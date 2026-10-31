function result = shotHighOrder(wafers, settings)
%SHOTHIGHORDER Shot 高次補正（Shot 内の座標の補正の式）の係数（k パラメータ）を Wafer ごとに求め、補正の効果を評価する。
%   result = alignest.shotHighOrder(wafers, settings)
%   wafers：Wafer ごとの構造体の配列。label（Wafer の名前）・points（点の表。alignest.highOrderUnitPoints・
%   alignest.highOrderTargetPoints の形：source・name・shotNo・Xc・Yc（Shot 中心 [mm]）・localX・localY（Shot 内の座標 [mm]）・
%   x・y（Wafer 上の座標 [mm]）・valueX・valueY（dx・dy の値 [nm]。値の無い点は NaN）・direction（Scan 方向 1・2。分からない
%   点は NaN）・rowParity（Shot 行の奇偶。1 = 奇数行・2 = 偶数行。上の行から数える））。direction・rowParity の列が無ければ、
%   direction は分からない、rowParity は Shot 中心の Y 座標（Yc）の行を上から数えて付ける。
%   settings：設定（settings.highOrder を alignest.highOrderOptions で確かめて使う）。
%   補正の式：補正の式（ASML・Canon・Nikon・カスタム）のうち使う項（k パラメータ。terms.used）。dx の式は X の値、dy の式は Y の値に
%   当てはめる。x・y は Shot 内の座標 [mm]。k の組のくくり（options.unit）：
%   - Wafer 内の Shot で共通（"common"）：Wafer ごとに1組の k を、その Wafer のすべての点で求める
%   - Scan 方向ごと（"scan"）・Shot 行の偶奇ごと（"row"）：Wafer ごとに、Scan 方向（1・2）・Shot 行の奇偶（奇数行・偶数行）
%     ごとに1組ずつの k を、その Wafer のすべての点で一緒に求める（組の点だけで決まる。L2 の強さは組ごとに別に求めたときと
%     同じ）
%   - Shot ごと（"shot"）：Shot ごとに1組の k を、その Shot の点だけで求める
%   内周・外周：Shot 中心の半径が options.outerRadiusMm 以上の Shot を外周とする（点の zone）。外周の式（options.outerMaker）を
%   分けるときは、k の組を内周・外周で別にし（くくりの組ごとに、内周は options.maker、外周は outerMaker の式）、Wafer 成分は
%   両方で共通にする。補正の評価は、分けなくても内周・外周ごとにも出す（result.regionSummary）。
%   Wafer 成分（Shot 中心の座標 Xc・Yc の 1〜waferOrder 次の項。定数は k1・k2 に含める）：Shot ごとのほかは、Wafer で共通の
%   1組として k と一緒に求める（正則化はかけない）。Shot ごとのときは、Shot ごとの k1・k2 が Wafer 成分を含むので、先に Wafer 内で
%   共通の k と一緒に求めて引き、残りを Shot ごとに求める（補正量・残差は Wafer 成分なしと同じで、Shot ごとの k1・k2 が
%   Wafer 成分を除いた値になる）。
%   回帰は alignest.robustRidgeFit（最小二乗・Huber・LAD、正則化（L2・L1）は選んだ次数の項だけ）。比べるために、同じ点・同じ損失関数で、
%   Shot ごとに 1次の項（k1〜k6）で補正した残差も求める（くくりによらず、Shot ごとに別の k1〜k6）。
%   項数の絞り込み：点の数が最も少ない k の組（Shot ごとなら Mark の最も少ない Shot。k1〜k6 を決められる組の中で。外周の式を
%   分けるときは内周・外周ごと）の点の配置で決められる項だけを、k の番号の小さい順に選ぶ（使う項がそれより多ければ外し、
%   result.reduction とメッセージで知らせる。k1〜k6 は外さない）。
%   項がすべて決まらない k の組（点が足りない・点の配置で決まらない Shot・組・Wafer）は補正しない（補正量・残差は NaN）。
%   Wafer 成分の決まらない項は 0 にする。
%   result.terms：項の表（alignest.highOrderVif。点の Shot 内の座標で求めた VIF を含む）。zone：式の範囲（外周の式を分けない
%   ときは ""、分けるときは "内周"・"外周"。VIF はその範囲の点で求める）
%   result.coefficients：補正値（係数）の表（wafer・shotNo（Shot ごとのとき）・group（k の組の名前。Wafer 成分は
%   "Wafer で共通"）・zone（外周の式を分けるときの式の範囲）・axis・component・k・term・value・unit・note・xPower・yPower
%   （項のべき））。係数は mm の座標での値（単位 nm/mm^次数。1次は nm/mm = ppm）
%   result.summary：Wafer・軸ごとの評価と、全 Wafer をまとめた行（wafer = "すべての Wafer"。region = "すべて"）。点の数、
%   補正前・Shot ごとの1次（k1〜k6）で補正した残差・高次補正の残差の |平均| + 3σ [nm]（before・linear・highOrder）、Shot
%   ごとの1次と比べた改善（improvement）、高次補正の |残差| の 95% 点・中央値（highOrderP95・highOrderMedian）、高次補正の
%   残差の RMS、ロバスト回帰で重みを下げた点の数、求めた k の組の数（kSets）と補正しなかった k の組の数（skipped）
%   result.regionSummary：result.summary と同じ列で、内周・外周（region = "内周"・"外周"）の Shot だけの行。k の組が内周と
%   外周にまたがるとき（外周の式を分けない Wafer 内で共通など）は kSets・skipped が NaN
%   result.points：点ごとの値・k の組（group）・Shot 中心の半径（shotRadius）・内周か外周か（zone）・補正量・残差・Shot
%   ごとの1次で補正した残差・ロバスト回帰の重み（wafer の列を足して縦に並べる）
%   result.reduction：式の範囲・軸（dx・dy）ごとの項数の絞り込み（axis・zone（"" または "内周"・"外周"）・zoneIndex・
%   reference（基準の k の組）・nPoints（その点の数）・dropped（外した k の番号））
%   result.messages：画面に出す説明、result.options・description：使った設定（絞った項は options.excludedTerms・
%   outerExcludedTerms に足す）
arguments
    wafers struct
    settings struct
end
WEIGHT_TOLERANCE = 1e-6;     % 重みがこれより 1 から下がった点を「重みを下げた点」に数える
ALL_LABEL = "すべての Wafer";
ALL_REGION = "すべて";
ZONE_NAMES = ["内周", "外周"];
AXIS_NAMES = ["X", "Y"];
FORMULA_AXES = ["dx", "dy"];
options = alignest.highOrderOptions(settings);
if isempty(wafers)
    error('alignest:highOrderInput', 'Shot 高次補正を求める点がありません。入力のデータと Wafer を選んでください。');
end
zoneSplit = options.outerMaker ~= "none";
for w = 1:numel(wafers)
    wafers(w).points = withGroupColumns(wafers(w).points, options.outerRadiusMm);
end
% 正則化：強さ λ（なしなら 0）と、かける項の次数。種類（L2・L1）は回帰の設定に渡す
penalty = struct("lambda", options.lambda * (options.regularization ~= "none"), "orders", options.penaltyOrders);
penaltyType = "l2";
if options.regularization == "l1"
    penaltyType = "l1";
end
fitOptions = {'loss', options.loss, 'huberTuning', options.huberTuning, 'penalty', penaltyType};
noPenalty = struct("lambda", 0, "orders", zeros(1, 0));
zoneTerms = {alignest.highOrderTerms(options.maker, options.excludedTerms)};
if zoneSplit
    zoneTerms{2} = alignest.highOrderTerms(options.outerMaker, options.outerExcludedTerms);
end
everything = vertcat(wafers.points);
[zoneTerms, reduction] = reduceTerms(zoneTerms, wafers, options.unit, FORMULA_AXES, zoneSplit);
dropped = droppedTerms(reduction, 1);
outerDropped = droppedTerms(reduction, 2);
if ~isempty(dropped) || ~isempty(outerDropped)
    % 使った設定・説明（項の数）は、絞った後の項にする
    options.excludedTerms = unique([options.excludedTerms, dropped]);
    options.outerExcludedTerms = unique([options.outerExcludedTerms, outerDropped]);
    options.description = alignest.highOrderOptions(struct("highOrder", options)).description;
end
if options.unit == "scan" && ~any(ismember(everything.direction, [1, 2]) & isfinite(everything.shotNo))
    error('alignest:highOrderDirection', ['Scan 方向（Direction）が分からないので、Scan 方向ごとには求められません。' ...
        '「1. データの読み込み」で Direction の列を対応づけるか「Scan 方向の付与」の規則を選ぶ（Excel・CSV のときは' ...
        '「Excel・CSV の列」で Direction の列か規則を選ぶ）と使えます。']);
end
vifInfos = cell(1, numel(zoneTerms));
for z = 1:numel(zoneTerms)
    inZone = ~zoneSplit | everything.zone == z;   % 外周の式を分けるときは、その範囲の点で VIF を求める
    [zoneTerms{z}, vifInfos{z}] = alignest.highOrderVif(zoneTerms{z}, [everything.localX(inZone), ...
        everything.localY(inZone)], [isfinite(everything.valueX(inZone)), isfinite(everything.valueY(inZone))] & ...
        isfinite(everything.shotNo(inZone)), options.vifThreshold);
    zoneTerms{z}.zone = repmat(ternaryText(zoneSplit, ZONE_NAMES(z), ""), height(zoneTerms{z}), 1);
end
waferPowers = polynomialPowers(options.waferOrder);
waferFirst = options.unit == "shot" && options.waferOrder > 0;   % Shot ごと：Wafer 成分を先に求めて引く
fitWaferPowers = waferPowers;
if options.unit == "shot"
    fitWaferPowers = zeros(0, 2);   % Shot ごとの k と一緒には求めない（k1・k2 が Wafer 成分を含む）
end

pointParts = cell(numel(wafers), 1);
coefficientParts = cell(numel(wafers), 2);
summaryParts = cell(numel(wafers) + 1, 2);
regionParts = cell(numel(wafers) + 1, 2, 2);
counts = struct("skipped", [0, 0], "groups", [0, 0], "notConverged", 0, "noRobust", 0, "waferDropped", 0, ...
    "undetermined", strings(1, 0), "constant", strings(1, 0));
% 求めた・補正しなかった k の組の数（軸 × 範囲。1列目は内周と外周にまたがる組、2・3列目は内周・外周の組）
[totalFitted, totalSkipped] = deal(zeros(2, 3));
for w = 1:numel(wafers)
    points = wafers(w).points;
    label = string(wafers(w).label);
    nPoints = height(points);
    values = [points.valueX, points.valueY];
    coordinates = [points.localX, points.localY, points.Xc, points.Yc];   % 表より速く切り出せる数の配列で回帰に渡す
    [groupKey, groupName] = groupOfPoints(points, options.unit, zoneSplit);
    [correction, linearCorrection, weights] = deal(nan(nPoints, 2));
    [fitted, skipped] = deal(zeros(2, 3));
    for a = 1:2
        rows = find(isfinite(values(:, a)) & isfinite(points.shotNo) & isfinite(groupKey));
        axisTerms = cellfun(@(terms) terms(terms.axis == FORMULA_AXES(a) & terms.used, :), zoneTerms, ...
            'UniformOutput', false);   % 式の範囲（内周・外周）ごとの使う項
        linearTerms = zoneTerms{1}(zoneTerms{1}.axis == FORMULA_AXES(a) & zoneTerms{1}.order <= 1, :);
        parts = cell(1, 0);
        waferPart = zeros(nPoints, 1);
        if waferFirst
            [waferPart, waferFit] = fitWaferFirst(points, coordinates, values(:, a), axisTerms, waferPowers, ...
                zoneSplit, penalty, fitOptions);
            if isempty(waferFit) || ~any(waferFit.ok)
                counts.waferDropped = counts.waferDropped + 1;   % 求められなかった Wafer 成分は 0（Shot ごとの k だけ）
            else
                parts{end + 1} = waferRows(label, FORMULA_AXES(a), waferPowers, waferFit); %#ok<AGROW>
                counts.waferDropped = counts.waferDropped + any(~waferFit.waferDetermined);
                counts.notConverged = counts.notConverged + ~waferFit.converged;
            end
        end
        fitUnits = partitionRows(rows, points, groupKey, groupName, options.unit, zoneSplit);
        for u = 1:numel(fitUnits)
            members = fitUnits(u).members;
            groupIndex = fitUnits(u).groupIndex;
            groupTerms = axisTerms(fitUnits(u).zones);
            counts.groups(a) = counts.groups(a) + numel(fitUnits(u).labels);
            fit = fitGroups(coordinates(members, :), values(members, a) - waferPart(members), groupIndex, groupTerms, ...
                fitWaferPowers, penalty, fitOptions);
            done = fit.ok(groupIndex);
            correction(members(done), a) = fit.fitted(done) + waferPart(members(done));
            weights(members(done), a) = fit.weights(done);
            column = 1 + groupZones(points.zone(members), groupIndex, numel(fit.ok));
            fitted(a, :) = fitted(a, :) + accumarray(column(:), double(fit.ok(:)), [3, 1]).';
            skipped(a, :) = skipped(a, :) + accumarray(column(:), double(~fit.ok(:)), [3, 1]).';
            counts.skipped(a) = counts.skipped(a) + nnz(~fit.ok);
            for g = find(~fit.ok)
                names = termNames(groupTerms{g});
                counts.undetermined = unique([counts.undetermined, names(~fit.determined{g})], 'stable');
            end
            if any(fit.ok)
                parts{end + 1} = coefficientRows(label, fitUnits(u), FORMULA_AXES(a), groupTerms, fitWaferPowers, ...
                    fit, zoneSplit); %#ok<AGROW>
                counts.notConverged = counts.notConverged + ~fit.converged;
                counts.noRobust = counts.noRobust + (options.loss ~= "ols" && ~fit.robust);
                counts.waferDropped = counts.waferDropped + any(~fit.waferDetermined);
                for g = find(fit.ok)
                    names = termNames(groupTerms{g});
                    counts.constant = unique([counts.constant, names(fit.constant{g})], 'stable');
                end
            end
        end
        coefficientParts{w, a} = [parts{:}];
        % 比べる補正：Shot ごとに 1次（k1〜k6）だけ（くくりによらない。Wafer 成分は Shot ごとの k1・k2 に含まれる）
        shotRows = find(isfinite(values(:, a)) & isfinite(points.shotNo));
        [~, ~, shotIndex] = unique(points.shotNo(shotRows));
        for s = 1:max([shotIndex; 0])
            members = shotRows(shotIndex == s);
            linearFit = fitGroups(coordinates(members, :), values(members, a), ones(numel(members), 1), {linearTerms}, ...
                zeros(0, 2), noPenalty, fitOptions);
            if linearFit.ok
                linearCorrection(members, a) = linearFit.fitted;
            end
        end
    end
    totalFitted = totalFitted + fitted;
    totalSkipped = totalSkipped + skipped;
    residual = values - correction;
    linearResidual = values - linearCorrection;
    groupText = strings(nPoints, 1);
    known = isfinite(groupKey) & isfinite(points.shotNo);
    groupText(known) = groupName(groupKey(known), points.shotNo(known));
    zoneText = strings(nPoints, 1);
    zoneText(isfinite(points.zone)) = ZONE_NAMES(points.zone(isfinite(points.zone)));
    pointParts{w} = [table(repmat(label, nPoints, 1), 'VariableNames', "wafer"), ...
        points(:, ["source", "name", "shotNo", "x", "y", "localX", "localY", "direction", "rowParity", "valueX", ...
        "valueY"]), table(groupText, points.shotRadius, zoneText, correction(:, 1), correction(:, 2), residual(:, 1), ...
        residual(:, 2), linearResidual(:, 1), linearResidual(:, 2), weights(:, 1), weights(:, 2), 'VariableNames', ...
        ["group", "shotRadius", "zone", "correctionX", "correctionY", "residualX", "residualY", "linearResidualX", ...
        "linearResidualY", "weightX", "weightY"])];
    for a = 1:2
        summaryParts{w, a} = summaryRow(label, AXIS_NAMES(a), ALL_REGION, points.shotNo, pointParts{w}, ...
            sum(fitted(a, :)), sum(skipped(a, :)), WEIGHT_TOLERANCE);
        for z = 1:2
            inZone = points.zone == z;
            [kSets, notCorrected] = zoneGroupCounts(fitted(a, :), skipped(a, :), z);
            regionParts{w, a, z} = summaryRow(label, AXIS_NAMES(a), ZONE_NAMES(z), points.shotNo(inZone), ...
                pointParts{w}(inZone, :), kSets, notCorrected, WEIGHT_TOLERANCE);
        end
    end
end
result.options = options;
result.description = options.description;
result.terms = vertcat(zoneTerms{:});
result.vifInfo = vifInfos{1};
result.reduction = reduction;
result.coefficients = coefficientTable([coefficientParts{:}]);
result.points = vertcat(pointParts{:});
all_ = result.points;
allKeys = all_.wafer + "|" + string(all_.shotNo);
for a = 1:2
    axisName = AXIS_NAMES(a);
    summaryParts{end, a} = summaryRow(ALL_LABEL, axisName, ALL_REGION, allKeys, all_, ...
        counts.groups(a) - counts.skipped(a), counts.skipped(a), WEIGHT_TOLERANCE);
    for z = 1:2
        inZone = all_.zone == ZONE_NAMES(z);
        [kSets, notCorrected] = zoneGroupCounts(totalFitted(a, :), totalSkipped(a, :), z);
        regionParts{end, a, z} = summaryRow(ALL_LABEL, axisName, ZONE_NAMES(z), allKeys(inZone), all_(inZone, :), ...
            kSets, notCorrected, WEIGHT_TOLERANCE);
    end
end
result.summary = xFirst(vertcat(summaryParts{:}));
% 内周・外周の行：Wafer ごとに内周・外周の順（X の行、Y の行の順）
regions = permute(regionParts, [3, 1, 2]);
result.regionSummary = xFirst(vertcat(regions{:}));
result.messages = [reductionMessages(reduction); buildMessages(options, wafers, everything, counts, vifInfos, ...
    zoneSplit, ZONE_NAMES)];
end

function rows = xFirst(rows)
% X の行、Y の行の順に並べる（同じ軸の中は元の順）
[~, order] = sortrows([rows.axis == "Y", (1:height(rows)).']);
rows = rows(order, :);
end

function numbers = droppedTerms(reduction, zoneIndex)
% 項数の絞り込みで外した k の番号（式の範囲ごと）
numbers = [reduction([reduction.zoneIndex] == zoneIndex).dropped];
end

function [terms, info] = reduceTerms(terms, wafers, unit, formulaAxes, zoneSplit)
% 項数の絞り込み：k の組（Shot ごとなら Shot、ほかは Wafer・Scan 方向・行の偶奇の組）のうち、k1〜k6 を決められて点の数が
% 最も少ない組を基準に、その点の配置で決められる項だけを k の番号の小さい順に選ぶ（前の項で表せる項は外す）。
% terms：式の範囲（外周の式を分けないときは1つ、分けるときは内周・外周）ごとの項の表の cell。外周の式を分けるときは、
% 範囲ごとにその範囲の組を基準にする。info：範囲・軸ごとの axis・zone・zoneIndex・reference（基準の組）・nPoints・
% dropped（外した k の番号）
RELATIVE_TOLERANCE = 1e-9;   % 前の項で表せる割合がこれより大きい項は、決められない項とする（alignest.robustRidgeFit と同じ）
ZONE_NAMES = ["内周", "外周"];
info = struct("axis", {}, "zone", {}, "zoneIndex", {}, "reference", {}, "nPoints", {}, "dropped", {});
columns = ["valueX", "valueY"];
for z = 1:numel(terms)
    zoneTerms = terms{z};
    for a = 1:numel(formulaAxes)
        best = struct("n", Inf, "local", zeros(0, 2), "label", "");
        for w = 1:numel(wafers)
            points = wafers(w).points;
            [key, nameOf] = groupOfPoints(points, unit, zoneSplit);
            valid = find(isfinite(points.(columns(a))) & isfinite(points.shotNo) & isfinite(key));
            if zoneSplit
                valid = valid(points.zone(valid) == z);
            end
            [keys, ~, index] = unique(key(valid));
            for g = 1:numel(keys)
                members = valid(index == g);
                local = [points.localX(members), points.localY(members)];
                if numel(members) >= best.n || rank([ones(numel(members), 1), local]) < 3
                    continue   % k1〜k6 を決められない組は補正しない（基準にしない）
                end
                name = string(wafers(w).label);
                if unit ~= "common" || zoneSplit
                    name = name + " の " + nameOf(keys(g), points.shotNo(members(1)));
                end
                best = struct("n", numel(members), "local", local, "label", name);
            end
        end
        entry = struct("axis", formulaAxes(a), "zone", ternaryText(zoneSplit, ZONE_NAMES(z), ""), "zoneIndex", z, ...
            "reference", "", "nPoints", NaN, "dropped", zeros(1, 0));
        if isfinite(best.n)
            rows = find(zoneTerms.axis == formulaAxes(a) & zoneTerms.used);
            [~, order] = sortrows([~zoneTerms.protected(rows), zoneTerms.k(rows)]);   % k1〜k6 を先に、残りは k の小さい順
            rows = rows(order);
            basis = zeros(best.n, 0);
            dropped = zeros(1, 0);
            for row = reshape(rows, 1, [])
                column = best.local(:, 1) .^ zoneTerms.xPower(row) .* best.local(:, 2) .^ zoneTerms.yPower(row);
                scale = norm(column);
                remainder = column;
                for pass = 1:2
                    remainder = remainder - basis * (basis.' * remainder);
                end
                if scale > 0 && norm(remainder) > sqrt(RELATIVE_TOLERANCE) * scale
                    basis(:, end + 1) = remainder / norm(remainder); %#ok<AGROW>
                elseif ~zoneTerms.protected(row)
                    zoneTerms.used(row) = false;
                    dropped(end + 1) = zoneTerms.k(row); %#ok<AGROW>
                end
            end
            entry.reference = best.label;
            entry.nPoints = best.n;
            entry.dropped = sort(dropped);
        end
        info(end + 1) = entry; %#ok<AGROW>
    end
    terms{z} = zoneTerms;
end
end

function messages = reductionMessages(info)
% 項数を絞ったときの知らせ（絞らなければ空）
messages = strings(0, 1);
for a = 1:numel(info)
    if isempty(info(a).dropped)
        continue
    end
    axisText = info(a).axis;
    if info(a).zone ~= ""
        axisText = axisText + "（" + info(a).zone + "の式）";
    end
    messages(end + 1, 1) = sprintf(['⚠ %s：選んだ項が、点の数が最も少ない k の組（%s：%d 点）では求められないため、' ...
        'k の小さい順に決められる項だけを使いました（外した項：%s）。'], axisText, info(a).reference, info(a).nPoints, ...
        strjoin("k" + string(info(a).dropped), "・")); %#ok<AGROW>
end
end

function points = withGroupColumns(points, outerRadiusMm)
% 点の表に、Scan 方向（direction）・Shot 行の奇偶（rowParity）の列が無ければ足し（Scan 方向は分からない。行は Shot 中心の
% Y 座標が同じ Shot の並びを上から数える。alignest.prepareData の Shot 行と同じ数え方）、Shot 中心の半径（shotRadius）と
% 内周・外周（zone：1 = 内周、2 = 外周。半径が outerRadiusMm 以上を外周）を足す
SHOT_COORDINATE_DIGITS = 3;   % 行を判定する桁（1 µm。alignest.prepareData と同じ）
RADIUS_TOLERANCE_MM = 1e-9;   % 境界ちょうどの Shot を外周に入れる（計算の丸めの差を除く）
names = string(points.Properties.VariableNames);
if ~any(names == "direction")
    points.direction = nan(height(points), 1);
end
if ~any(names == "rowParity")
    rowY = round(points.Yc, SHOT_COORDINATE_DIGITS);
    [~, row] = ismember(rowY, sort(unique(rowY(isfinite(rowY))), 'descend'));
    parity = 1 + mod(row - 1, 2);
    parity(row == 0) = NaN;
    points.rowParity = parity;
end
points.shotRadius = hypot(points.Xc, points.Yc);
zone = 1 + double(points.shotRadius >= outerRadiusMm - RADIUS_TOLERANCE_MM);
zone(~isfinite(points.shotRadius)) = NaN;
points.zone = zone;
end

function [key, nameOf] = groupOfPoints(points, unit, zoneSplit)
% 点ごとの k の組の番号（分からない点は NaN）と、組の名前を返す関数 nameOf(番号, shotNo)。外周の式を分けるときは、
% Shot ごとのほかは内周・外周で別の組にする（番号は 範囲の番号 × ZONE_STRIDE ＋ くくりの番号、名前は「内周・Scan 方向 1」など）
ROW_NAMES = ["奇数行", "偶数行"];
ZONE_NAMES = ["内周", "外周"];
ZONE_STRIDE = 10;   % 範囲ごとに番号をずらす幅（くくりの番号は 1・2）
n = height(points);
switch unit
    case "common"
        key = ones(n, 1);
        baseName = @(keys) repmat("共通", numel(keys), 1);
    case "scan"
        key = points.direction;
        key(~ismember(key, [1, 2])) = NaN;
        baseName = @(keys) "Scan 方向 " + string(keys(:));
    case "row"
        key = points.rowParity;
        key(~ismember(key, [1, 2])) = NaN;
        baseName = @(keys) reshape(ROW_NAMES(keys), [], 1);
    otherwise
        key = points.shotNo;
        if zoneSplit
            key(~isfinite(points.zone)) = NaN;
        end
        nameOf = @(~, shotNos) "Shot " + string(shotNos(:));
        return
end
if ~zoneSplit
    nameOf = @(keys, ~) baseName(keys);
    return
end
key = key + (points.zone - 1) * ZONE_STRIDE;
zoneName = @(keys) reshape(ZONE_NAMES(floor((keys(:) - 1) / ZONE_STRIDE) + 1), [], 1);
if unit == "common"
    nameOf = @(keys, ~) zoneName(keys);
else
    nameOf = @(keys, ~) zoneName(keys) + "・" + baseName(mod(keys(:) - 1, ZONE_STRIDE) + 1);
end
end

function fitUnits = partitionRows(rows, points, groupKey, groupName, unit, zoneSplit)
% 一緒に求める点の集まり（members）と、その中の k の組（groupIndex：1〜組の数、labels：組の名前、zones：組の式の範囲
% （1 = 内周の式、2 = 外周の式。外周の式を分けないときはすべて 1））。Shot ごとは Shot ごとに別に求める。ほかは Wafer の点を
% まとめて求める（Wafer 成分は共通、k は組ごと）
fitUnits = struct("members", {}, "groupIndex", {}, "labels", {}, "shotNo", {}, "zones", {});
if isempty(rows)
    return   % この軸の値が無い Wafer
end
if unit == "shot"
    [shots, ~, index] = unique(points.shotNo(rows));
    for s = 1:numel(shots)
        members = rows(index == s);
        zone = 1;
        if zoneSplit
            zone = points.zone(members(1));
        end
        fitUnits(s) = struct("members", members, "groupIndex", ones(numel(members), 1), "labels", ...
            groupName(1, shots(s)), "shotNo", shots(s), "zones", zone);
    end
    return
end
[keys, first, index] = unique(groupKey(rows));
zones = ones(1, numel(keys));
if zoneSplit
    zones = reshape(points.zone(rows(first)), 1, []);
end
fitUnits(1) = struct("members", rows, "groupIndex", index, "labels", groupName(keys, nan(size(keys))), "shotNo", NaN, ...
    "zones", zones);
end

function zones = groupZones(pointZones, groupIndex, nGroups)
% k の組ごとの範囲（1 = 内周・2 = 外周。組の点が内周と外周にまたがるときは 0）
zones = zeros(1, nGroups);
for g = 1:nGroups
    mine = unique(pointZones(groupIndex == g));
    if isscalar(mine) && isfinite(mine)
        zones(g) = mine;
    end
end
end

function [kSets, skipped] = zoneGroupCounts(fitted, notFitted, zone)
% 内周・外周の行の k の組の数（内周と外周にまたがる組があれば数えられないので NaN）
if fitted(1) + notFitted(1) > 0
    [kSets, skipped] = deal(NaN);
else
    kSets = fitted(zone + 1);
    skipped = notFitted(zone + 1);
end
end

function [waferPart, fit] = fitWaferFirst(points, coordinates, values, axisTerms, waferPowers, zoneSplit, penalty, ...
        fitOptions)
% Shot ごとのとき、Wafer 成分を先に求める：Wafer 内で共通の k（外周の式を分けるときは内周・外周の2組）と一緒に全点で
% 求め（「Wafer 内で共通」と同じ求め方）、点ごとの Wafer 成分の分（waferPart。定数は含めない）を返す。Wafer 成分は Shot 中心の
% 座標の関数なので、残りを Shot ごとに求めても補正量・残差は変わらず、Shot ごとの k1・k2 が Wafer 成分を除いた値になる
waferPart = zeros(height(points), 1);
fit = [];
[key, name] = groupOfPoints(points, "common", zoneSplit);
rows = find(isfinite(values) & isfinite(points.shotNo) & isfinite(key));
fitUnits = partitionRows(rows, points, key, name, "common", zoneSplit);
if isempty(fitUnits)
    return
end
unit = fitUnits(1);
fit = fitGroups(coordinates(unit.members, :), values(unit.members), unit.groupIndex, axisTerms(unit.zones), ...
    waferPowers, penalty, fitOptions);
if ~any(fit.ok)
    return
end
coefficients = fit.waferCoefficients;
coefficients(~isfinite(coefficients)) = 0;
waferPart = (coordinates(:, 3) .^ (waferPowers(:, 1).') .* coordinates(:, 4) .^ (waferPowers(:, 2).')) * coefficients;
waferPart(~isfinite(waferPart)) = 0;
end

function out = fitGroups(coordinates, values, groupIndex, groupTerms, waferPowers, penalty, fitOptions)
% 一緒に求める点の集まりに補正の式を当てはめる：k は組（groupIndex）ごと（組 g の項は groupTerms{g}。外周の式を分けると
% 組ごとに項が違う）、Wafer 成分は共通。項がすべては決まらない組は補正しない（その組を除いて求め直す。組の項はその組の
% 点だけで決まるので、ほかの組は変わらない）。
% coordinates：点ごとの [Shot 内の x, Shot 内の y, Shot 中心の Xc, Yc]。penalty：正則化の強さ lambda とかける項の次数 orders。
% out.ok：補正した組、out.fitted・weights：点ごと（補正しない組の点は NaN）、out.coefficients・determined・
% constant：組ごとの cell（組の項の数 × 1）、out.waferCoefficients・waferDetermined・waferConstant：Wafer 成分の項
nGroups = max([groupIndex(:); 0]);
nWafer = size(waferPowers, 1);
n = numel(values);
emptyOf = @(fill) cellfun(@(terms) fill(height(terms), 1), groupTerms, 'UniformOutput', false);
out = struct("ok", false(1, nGroups), "fitted", nan(n, 1), "weights", nan(n, 1), ...
    "coefficients", {emptyOf(@nan)}, "determined", {emptyOf(@false)}, "constant", {emptyOf(@false)}, ...
    "waferCoefficients", nan(nWafer, 1), "waferDetermined", true(nWafer, 1), "waferConstant", false(nWafer, 1), ...
    "converged", true, "robust", false);
active = 1:nGroups;
rows = true(n, 1);
local = groupIndex;
while ~isempty(active)
    if numel(active) < nGroups   % 決まらない組を除いたとき（はじめはすべての組）
        rows = ismember(groupIndex, active);
        [~, local] = ismember(groupIndex(rows), active);
    end
    fit = solveGroups(coordinates(rows, :), values(rows), local, groupTerms(active), waferPowers, penalty, fitOptions);
    ok = true(1, numel(active));
    for j = 1:numel(active)
        out.determined{active(j)} = fit.determined(fit.columns{j});
        ok(j) = all(out.determined{active(j)});
    end
    if all(ok)
        break
    end
    active = active(ok);   % 決まらない組を除いて求め直す（残りが無ければ終わり）
end
if isempty(active)
    return
end
out.ok(active) = true;
out.fitted(rows) = fit.fitted;
out.weights(rows) = fit.weights;
for j = 1:numel(active)
    out.coefficients{active(j)} = fit.coefficients(fit.columns{j});
    out.constant{active(j)} = fit.constant(fit.columns{j});
end
out.waferCoefficients = fit.coefficients(fit.waferColumns);
out.waferDetermined = fit.determined(fit.waferColumns);
out.waferConstant = fit.constant(fit.waferColumns);
out.converged = fit.converged;
out.robust = fit.robust;
end

function fit = solveGroups(coordinates, values, groupIndex, groupTerms, waferPowers, penalty, fitOptions)
% 設計行列：組ごとの補正の式の項（その組の点だけ値があり、ほかは 0）と、共通の Wafer 成分の項。
% fit.columns{g}：組 g の項の列、fit.waferColumns：Wafer 成分の列
nGroups = numel(groupTerms);
widths = cellfun(@height, groupTerms);
blocks = zeros(numel(values), sum(widths));
isPenalized = false(sum(widths), 1);
columnGroup = zeros(sum(widths), 1);
columns = cell(1, nGroups);
offset = 0;
for g = 1:nGroups
    terms = groupTerms{g};
    columns{g} = offset + (1:height(terms));
    local = coordinates(:, 1) .^ (terms.xPower.') .* coordinates(:, 2) .^ (terms.yPower.');
    blocks(:, columns{g}) = local .* (groupIndex == g);
    isPenalized(columns{g}) = ismember(terms.order, penalty.orders);   % 選んだ次数の項だけ（Wafer 成分にはかけない）
    columnGroup(columns{g}) = g;
    offset = offset + height(terms);
end
wafer = coordinates(:, 3) .^ (waferPowers(:, 1).') .* coordinates(:, 4) .^ (waferPowers(:, 2).');
nWafer = size(waferPowers, 1);
groupOptions = {};
if nGroups > 1
    groupOptions = {'rowGroup', groupIndex, 'columnGroup', [columnGroup; zeros(nWafer, 1)]};
end
fit = alignest.robustRidgeFit([blocks, wafer], values, [isPenalized; false(nWafer, 1)], fitOptions{:}, ...
    'lambda', penalty.lambda, groupOptions{:});
fit.columns = columns;
fit.waferColumns = offset + (1:nWafer);
end

function names = termNames(terms)
names = reshape("k" + string(terms.k) + "（" + terms.term + "）", 1, []);
end

function rows = coefficientRows(label, fitUnit, axisName, groupTerms, waferPowers, fit, zoneSplit)
% 係数の行（列ごとの配列の構造体。最後に coefficientTable で表にする）：補正した k の組ごとの補正の式の項（k）と、
% Wafer で共通の Wafer 成分の項
ZONE_NAMES = ["内周", "外周"];
groups = find(fit.ok);
parts = cell(1, numel(groups) + 1);
for j = 1:numel(groups)
    g = groups(j);
    terms = groupTerms{g};
    n = height(terms);
    note = strings(n, 1);
    note(fit.constant{g}) = "点の配置では値が変わらない（定数と同じ）ので 0";
    note(~fit.determined{g}) = "点の配置では決まらない（0 にした）";
    zone = "";
    if zoneSplit
        zone = ZONE_NAMES(fitUnit.zones(g));
    end
    parts{j} = struct("wafer", repmat(string(label), n, 1), "shotNo", repmat(fitUnit.shotNo, n, 1), ...
        "group", repmat(fitUnit.labels(g), n, 1), "zone", repmat(zone, n, 1), "axis", repmat(string(axisName), n, 1), ...
        "component", repmat("Shot 高次補正", n, 1), "k", terms.k, "term", reshape(termNames(terms), [], 1), ...
        "value", fit.coefficients{g}, "unit", unitText(terms.order), "note", note, "xPower", terms.xPower, ...
        "yPower", terms.yPower);
end
if ~isempty(waferPowers)
    parts{end} = waferRows(label, axisName, waferPowers, fit);
end
rows = [parts{:}];
end

function rows = waferRows(label, axisName, waferPowers, fit)
% Wafer で共通の Wafer 成分の係数の行（coefficientRows と同じ形）
nWafer = size(waferPowers, 1);
note = strings(nWafer, 1);
note(fit.waferConstant) = "点の配置では値が変わらない（定数と同じ）ので 0";
note(~fit.waferDetermined) = "点の配置では決まらない（0 にした）";
rows = struct("wafer", repmat(string(label), nWafer, 1), "shotNo", nan(nWafer, 1), ...
    "group", repmat("Wafer で共通", nWafer, 1), "zone", strings(nWafer, 1), "axis", repmat(string(axisName), nWafer, 1), ...
    "component", repmat("Wafer 成分", nWafer, 1), "k", nan(nWafer, 1), "term", waferTermNames(waferPowers), ...
    "value", fit.waferCoefficients, "unit", unitText(sum(waferPowers, 2)), "note", note, ...
    "xPower", waferPowers(:, 1), "yPower", waferPowers(:, 2));
end

function coefficients = coefficientTable(parts)
% 係数の行（coefficientRows の構造体の配列）を縦につないで表にする（行が無ければ列だけの表）
% xPower・yPower は項のべき（Shot 高次補正は Shot 内の x・y、Wafer 成分は Shot 中心の Xc・Yc。alignest.highOrderModelAt）
names = ["wafer", "shotNo", "group", "zone", "axis", "component", "k", "term", "value", "unit", "note", "xPower", "yPower"];
if isempty(parts)
    parts = struct("wafer", strings(0, 1), "shotNo", zeros(0, 1), "group", strings(0, 1), "zone", strings(0, 1), ...
        "axis", strings(0, 1), "component", strings(0, 1), "k", zeros(0, 1), "term", strings(0, 1), "value", ...
        zeros(0, 1), "unit", strings(0, 1), "note", strings(0, 1), "xPower", zeros(0, 1), "yPower", zeros(0, 1));
end
columns = cell(1, numel(names));
for k = 1:numel(names)
    columns{k} = vertcat(parts.(names(k)));
end
coefficients = table(columns{:}, 'VariableNames', names);
end

function names = waferTermNames(powers)
% Wafer 成分の項の名前（Shot 中心の座標を Xc・Yc と書く）
names = strings(size(powers, 1), 1);
for k = 1:size(powers, 1)
    parts = strings(0, 1);
    for v = 1:2
        symbol = ["Xc", "Yc"];
        if powers(k, v) == 1
            parts(end + 1) = symbol(v); %#ok<AGROW>
        elseif powers(k, v) > 1
            parts(end + 1) = symbol(v) + "^" + powers(k, v); %#ok<AGROW>
        end
    end
    names(k) = strjoin(parts, "·");
end
end

function powers = polynomialPowers(order)
% Wafer 成分の項のべき [Xc のべき, Yc のべき]（1〜order 次。次数の順、同じ次数では Yc のべきが小さい順。定数は含めない）
powers = zeros(0, 2);
for degree = 1:order
    for powerY = 0:degree
        powers(end + 1, :) = [degree - powerY, powerY]; %#ok<AGROW>
    end
end
end

function text = unitText(order)
text = "nm/mm^" + string(order);
text(order == 0) = "nm";
text(order == 1) = "nm/mm（ppm）";
end

function text = ternaryText(condition, whenTrue, whenFalse)
if condition
    text = whenTrue;
else
    text = whenFalse;
end
end

function row = summaryRow(label, axisName, region, shotKeys, points, kSets, skipped, tolerance)
% 1つの Wafer・軸・範囲の評価（points は点の表。axisName の列を使う）。補正前・Shot ごとの1次・高次補正の |平均|+3σ は、
% どちらの補正もできた点で比べる。|残差| の 95% 点・中央値も同じ点。kSets・skipped：求めた・補正しなかった k の組の数
values = points.("value" + axisName);
residual = points.("residual" + axisName);
linearResidual = points.("linearResidual" + axisName);
weights = points.("weight" + axisName);
compared = isfinite(residual) & isfinite(linearResidual);
withValue = isfinite(values);
shots = numel(unique(shotKeys(withValue)));
before = meanPlus3Sigma(values(compared));
linear = meanPlus3Sigma(linearResidual(compared));
highOrder = meanPlus3Sigma(residual(compared));
rms = NaN;
if any(compared)
    rms = sqrt(mean(residual(compared) .^ 2));
end
magnitude = abs(residual(compared));
p95 = alignest.stats.percentile(magnitude, 95);
middle = NaN;
if ~isempty(magnitude)
    middle = median(magnitude);
end
row = table(string(label), string(axisName), string(region), nnz(withValue), nnz(compared), shots, kSets, skipped, ...
    before, linear, highOrder, linear - highOrder, p95, middle, rms, nnz(compared & weights < 1 - tolerance), ...
    'VariableNames', ["wafer", "axis", "region", "n", "nCorrected", "shots", "kSets", "skipped", "before", "linear", ...
    "highOrder", "improvement", "highOrderP95", "highOrderMedian", "rmsHighOrder", "downweighted"]);
end

function value = meanPlus3Sigma(values)
% Overlay の代表値 |平均| + 3σ（σ は不偏標準偏差）。点が2点未満なら NaN（alignest.overlayCorrection と同じ）
values = values(isfinite(values));
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end

function messages = buildMessages(options, wafers, everything, counts, vifInfos, zoneSplit, zoneNames)
messages = strings(0, 1);
messages(end + 1, 1) = sprintf('%d Wafer・%d 点（dx の値 %d 点・dy の値 %d 点）で求めました。補正：%s。', numel(wafers), ...
    height(everything), nnz(isfinite(everything.valueX)), nnz(isfinite(everything.valueY)), options.description);
noShot = nnz(~isfinite(everything.shotNo));
if noShot > 0
    messages(end + 1, 1) = sprintf('Shot の分からない点 %d 点は使っていません。', noShot);
end
shotKeys = strings(0, 1);
shotZones = zeros(0, 1);
for w = 1:numel(wafers)
    points = wafers(w).points;
    [shots, first] = unique(points.shotNo(isfinite(points.shotNo)));
    zones = points.zone(isfinite(points.shotNo));
    shotKeys = [shotKeys; string(w) + "|" + string(shots)]; %#ok<AGROW>
    shotZones = [shotZones; zones(first)]; %#ok<AGROW>
end
outerText = sprintf('外周の Shot（Shot 中心の半径 %g mm 以上）：%d Shot・内周 %d Shot（%d Wafer の合計）', ...
    options.outerRadiusMm, nnz(shotZones == 2), nnz(shotZones == 1), numel(wafers));
if zoneSplit
    messages(end + 1, 1) = outerText + "。外周の Shot は外周の式で、k の組を内周と別にして求めました。";
else
    messages(end + 1, 1) = outerText + "。「補正の評価」で内周・外周に分けて出せます。";
end
if options.unit == "shot" && options.waferOrder > 0
    messages(end + 1, 1) = sprintf(['Shot ごと：Wafer 成分（%d 次）を先に、Wafer 内で共通の k と一緒に求めて引き、残りを' ...
        ' Shot ごとに求めました（Shot ごとの k1・k2 は Wafer 成分を除いた値。補正量・残差は Wafer 成分なしと同じ）。'], ...
        options.waferOrder);
end
if options.unit == "scan"
    noDirection = nnz(~ismember(everything.direction, [1, 2]) & isfinite(everything.shotNo));
    if noDirection > 0
        messages(end + 1, 1) = sprintf('⚠ Scan 方向の分からない点 %d 点は使っていません（補正量・残差は空欄）。', noDirection);
    end
end
groupNames = struct("common", "Wafer", "scan", "k の組（Scan 方向）", "row", "k の組（行の偶奇）", "shot", "Shot");
groupName = groupNames.(options.unit);
if zoneSplit && options.unit == "common"
    groupName = "k の組（内周・外周）";
end
fitName = "Wafer";
if options.unit == "shot"
    fitName = "Shot";
end
if any(counts.skipped > 0)
    messages(end + 1, 1) = sprintf(['⚠ 点が足りない（または点の配置で項が決まらない）ため補正しなかった %s：dx %d / %d・' ...
        'dy %d / %d（補正量・残差は空欄）。'], groupName, counts.skipped(1), counts.groups(1), counts.skipped(2), ...
        counts.groups(2));
    messages(end) = messages(end) + "決まらない項：" + strjoin(counts.undetermined, "・") + "。";
    if options.regularization == "none" || options.lambda == 0
        messages(end) = messages(end) + "「VIF で選ぶ」でその項を外すか、その次数の項に正則化（L2・L1）をかけてください" + ...
            "（正則化をかけた次数の項は、点が少なくても決まります）。";
    else
        messages(end) = messages(end) + "1次の項（k1〜k6）を決めるには、1つの k の組に同じ直線の上に無い3点以上が要ります。";
    end
end
if ~isempty(counts.constant)
    messages(end + 1, 1) = "⚠ 点の配置では値が変わらない（定数と同じになる）項：" + strjoin(counts.constant, "・") + ...
        "。正則化で 0 にしました（VIF が ∞ の項。「VIF で選ぶ」で外せます）。";
end
if counts.noRobust > 0
    messages(end + 1, 1) = sprintf(['点の数が項の数以下の %s が %d 個あり、そこではロバスト回帰の重みを使わずに' ...
        '求めました（残差がほぼ 0 になり、外れ値を見分けられないため）。'], fitName, counts.noRobust);
end
if counts.notConverged > 0
    messages(end + 1, 1) = sprintf('⚠ ロバスト回帰の繰り返しが収束しなかった組が %d 個あります（最後の値を使いました）。', ...
        counts.notConverged);
end
if counts.waferDropped > 0
    messages(end + 1, 1) = sprintf(['Shot の数が少なく Wafer 成分の項が決まらない Wafer が %d 個あり、その項は 0 に' ...
        'しました（係数の表の「メモ」）。'], counts.waferDropped);
end
for z = 1:numel(vifInfos)
    info = vifInfos{z};
    rangeText = "";
    if zoneSplit
        rangeText = zoneNames(z) + "の式の";
    end
    messages(end + 1, 1) = sprintf(['%sVIF は Shot 内の座標（dx %d 点・dy %d 点、位置 %d・%d か所）で求めました。' ...
        '「VIF で選ぶ」（しきい値 %.4g）で外す項：%s。'], rangeText, info.points(1), info.points(2), ...
        info.positions(1), info.positions(2), options.vifThreshold, suggestedText(info.suggestedExcluded)); %#ok<AGROW>
end
end

function text = suggestedText(numbers)
if isempty(numbers)
    text = "なし";
else
    text = strjoin("k" + string(numbers), "・");
end
end
