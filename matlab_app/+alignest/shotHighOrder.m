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
%   Shot ごとのほかは、Wafer 成分（Shot 中心の座標 Xc・Yc の 1〜waferOrder 次の項。定数は k1・k2 に含める）を Wafer で
%   共通の1組として一緒に求める（L2 はかけない）。
%   回帰は alignest.robustRidgeFit（最小二乗・Huber・LAD、L2 は2次以上の項だけ）。比べるために、同じ点・同じ損失関数で、
%   Shot ごとに 1次の項（k1〜k6）で補正した残差も求める（くくりによらず、Shot ごとに別の k1〜k6）。
%   項数の絞り込み：点の数が最も少ない k の組（Shot ごとなら Mark の最も少ない Shot。k1〜k6 を決められる組の中で）の
%   点の配置で決められる項だけを、k の番号の小さい順に選ぶ（使う項がそれより多ければ外し、result.reduction と
%   メッセージで知らせる。k1〜k6 は外さない）。
%   項がすべて決まらない k の組（点が足りない・点の配置で決まらない Shot・組・Wafer）は補正しない（補正量・残差は NaN）。
%   Wafer 成分の決まらない項は 0 にする。
%   result.terms：項の表（alignest.highOrderVif。全 Wafer の点の Shot 内の座標で求めた VIF を含む）
%   result.coefficients：補正値（係数）の表（wafer・shotNo（Shot ごとのとき）・group（k の組の名前。Wafer 成分は
%   "Wafer で共通"）・axis・component・k・term・value・unit・note・xPower・yPower（項のべき））。係数は mm の座標での値（単位 nm/mm^次数。1次は
%   nm/mm = ppm）
%   result.summary：Wafer・軸ごとの評価と、全 Wafer をまとめた行（wafer = "すべての Wafer"）。点の数、補正前・Shot ごとの
%   1次（k1〜k6）で補正した残差・高次補正の残差の |平均| + 3σ [nm]（before・linear・highOrder）、Shot ごとの1次と比べた
%   改善（improvement）、高次補正の |残差| の 95% 点・中央値（highOrderP95・highOrderMedian）、高次補正の残差の RMS、
%   ロバスト回帰で重みを下げた点の数、求めた k の組の数（kSets）と補正しなかった k の組の数（skipped）
%   result.points：点ごとの値・k の組（group）・補正量・残差・Shot ごとの1次で補正した残差・ロバスト回帰の重み
%   （wafer の列を足して縦に並べる）
%   result.reduction：軸（dx・dy）ごとの項数の絞り込み（axis・reference（基準の k の組）・nPoints（その点の数）・
%   dropped（外した k の番号））
%   result.messages：画面に出す説明、result.options・description：使った設定（絞った項は options.excludedTerms に足す）
arguments
    wafers struct
    settings struct
end
WEIGHT_TOLERANCE = 1e-6;     % 重みがこれより 1 から下がった点を「重みを下げた点」に数える
ALL_LABEL = "すべての Wafer";
AXIS_NAMES = ["X", "Y"];
FORMULA_AXES = ["dx", "dy"];
options = alignest.highOrderOptions(settings);
if isempty(wafers)
    error('alignest:highOrderInput', 'Shot 高次補正を求める点がありません。入力のデータと Wafer を選んでください。');
end
for w = 1:numel(wafers)
    wafers(w).points = withGroupColumns(wafers(w).points);
end
lambda = options.lambda * options.l2;
fitOptions = {'loss', options.loss, 'huberTuning', options.huberTuning};
terms = alignest.highOrderTerms(options.maker, options.excludedTerms);
everything = vertcat(wafers.points);
[terms, reduction] = reduceTerms(terms, wafers, options.unit, FORMULA_AXES);
dropped = [reduction.dropped];
if ~isempty(dropped)
    % 使った設定・説明（項の数）は、絞った後の項にする
    options.excludedTerms = unique([options.excludedTerms, dropped]);
    options.description = alignest.highOrderOptions(struct("highOrder", options)).description;
end
if options.unit == "scan" && ~any(ismember(everything.direction, [1, 2]) & isfinite(everything.shotNo))
    error('alignest:highOrderDirection', ['Scan 方向（Direction）が分からないので、Scan 方向ごとには求められません。' ...
        '「1. データの読み込み」で Direction の列を対応づけるか「Scan 方向の付与」の規則を選ぶ（Excel・CSV のときは' ...
        '「Excel・CSV の列」で Direction の列か規則を選ぶ）と使えます。']);
end
[terms, vifInfo] = alignest.highOrderVif(terms, [everything.localX, everything.localY], ...
    [isfinite(everything.valueX), isfinite(everything.valueY)] & isfinite(everything.shotNo), options.vifThreshold);
waferPowers = polynomialPowers(options.waferOrder);

pointParts = cell(numel(wafers), 1);
coefficientParts = cell(numel(wafers), 2);
summaryParts = cell(numel(wafers) + 1, 2);
counts = struct("skipped", [0, 0], "groups", [0, 0], "notConverged", 0, "noRobust", 0, "waferDropped", 0, ...
    "undetermined", strings(1, 0), "constant", strings(1, 0));
for w = 1:numel(wafers)
    points = wafers(w).points;
    label = string(wafers(w).label);
    nPoints = height(points);
    values = [points.valueX, points.valueY];
    coordinates = [points.localX, points.localY, points.Xc, points.Yc];   % 表より速く切り出せる数の配列で回帰に渡す
    [groupKey, groupName] = groupOfPoints(points, options.unit);
    [correction, linearCorrection, weights] = deal(nan(nPoints, 2));
    [skippedGroups, fittedGroups] = deal(zeros(1, 2));
    for a = 1:2
        rows = find(isfinite(values(:, a)) & isfinite(points.shotNo) & isfinite(groupKey));
        axisTerms = terms(terms.axis == FORMULA_AXES(a), :);
        usedTerms = axisTerms(axisTerms.used, :);
        usedNames = termNames(usedTerms);
        linearTerms = axisTerms(axisTerms.order <= 1, :);
        fitUnits = partitionRows(rows, points.shotNo, groupKey, groupName, options.unit);
        parts = cell(numel(fitUnits), 1);
        for u = 1:numel(fitUnits)
            members = fitUnits(u).members;
            groupIndex = fitUnits(u).groupIndex;
            counts.groups(a) = counts.groups(a) + numel(fitUnits(u).labels);
            fit = fitGroups(coordinates(members, :), values(members, a), groupIndex, usedTerms, waferPowers, lambda, ...
                fitOptions);
            done = fit.ok(groupIndex);
            correction(members(done), a) = fit.fitted(done);
            weights(members(done), a) = fit.weights(done);
            skippedGroups(a) = skippedGroups(a) + nnz(~fit.ok);
            fittedGroups(a) = fittedGroups(a) + nnz(fit.ok);
            counts.skipped(a) = counts.skipped(a) + nnz(~fit.ok);
            if ~all(fit.ok)
                missing = any(~fit.determined(:, ~fit.ok), 2);
                counts.undetermined = unique([counts.undetermined, usedNames(missing)], 'stable');
            end
            if any(fit.ok)
                parts{u} = coefficientRows(label, fitUnits(u), FORMULA_AXES(a), usedTerms, usedNames, waferPowers, fit);
                counts.notConverged = counts.notConverged + ~fit.converged;
                counts.noRobust = counts.noRobust + (options.loss ~= "ols" && ~fit.robust);
                counts.waferDropped = counts.waferDropped + any(~fit.waferDetermined);
                flat = any(fit.constant(:, fit.ok), 2);
                if any(flat)
                    counts.constant = unique([counts.constant, usedNames(flat)], 'stable');
                end
            end
        end
        coefficientParts{w, a} = [parts{:}];
        % 比べる補正：Shot ごとに 1次（k1〜k6）だけ（くくりによらない。Wafer 成分は Shot ごとの k1・k2 に含まれる）
        shotRows = find(isfinite(values(:, a)) & isfinite(points.shotNo));
        [~, ~, shotIndex] = unique(points.shotNo(shotRows));
        for s = 1:max([shotIndex; 0])
            members = shotRows(shotIndex == s);
            linearFit = fitGroups(coordinates(members, :), values(members, a), ones(numel(members), 1), linearTerms, ...
                zeros(0, 2), 0, fitOptions);
            if linearFit.ok
                linearCorrection(members, a) = linearFit.fitted;
            end
        end
    end
    residual = values - correction;
    linearResidual = values - linearCorrection;
    groupText = strings(nPoints, 1);
    known = isfinite(groupKey) & isfinite(points.shotNo);
    groupText(known) = groupName(groupKey(known), points.shotNo(known));
    pointParts{w} = [table(repmat(label, nPoints, 1), 'VariableNames', "wafer"), ...
        points(:, ["source", "name", "shotNo", "x", "y", "localX", "localY", "direction", "rowParity", "valueX", ...
        "valueY"]), table(groupText, correction(:, 1), correction(:, 2), residual(:, 1), residual(:, 2), ...
        linearResidual(:, 1), linearResidual(:, 2), weights(:, 1), weights(:, 2), 'VariableNames', ["group", ...
        "correctionX", "correctionY", "residualX", "residualY", "linearResidualX", "linearResidualY", "weightX", ...
        "weightY"])];
    for a = 1:2
        summaryParts{w, a} = summaryRow(label, AXIS_NAMES(a), points.shotNo, pointParts{w}, fittedGroups(a), ...
            skippedGroups(a), WEIGHT_TOLERANCE);
    end
end
result.options = options;
result.description = options.description;
result.terms = terms;
result.vifInfo = vifInfo;
result.reduction = reduction;
result.coefficients = coefficientTable([coefficientParts{:}]);
result.points = vertcat(pointParts{:});
all_ = result.points;
for a = 1:2
    axisName = AXIS_NAMES(a);
    summaryParts{end, a} = summaryRow(ALL_LABEL, axisName, all_.wafer + "|" + string(all_.shotNo), all_, ...
        counts.groups(a) - counts.skipped(a), counts.skipped(a), WEIGHT_TOLERANCE);
end
summary = vertcat(summaryParts{:});
[~, order] = sortrows([summary.axis == "Y", (1:height(summary)).']);   % X の行、Y の行の順
result.summary = summary(order, :);
result.messages = [reductionMessages(reduction); buildMessages(options, wafers, everything, counts, vifInfo)];
end

function [terms, info] = reduceTerms(terms, wafers, unit, formulaAxes)
% 項数の絞り込み：k の組（Shot ごとなら Shot、ほかは Wafer・Scan 方向・行の偶奇の組）のうち、k1〜k6 を決められて点の数が
% 最も少ない組を基準に、その点の配置で決められる項だけを k の番号の小さい順に選ぶ（前の項で表せる項は外す）。
% info：軸ごとの axis・reference（基準の組）・nPoints・dropped（外した k の番号）
RELATIVE_TOLERANCE = 1e-9;   % 前の項で表せる割合がこれより大きい項は、決められない項とする（alignest.robustRidgeFit と同じ）
info = struct("axis", cellstr(formulaAxes(:)), "reference", "", "nPoints", NaN, "dropped", zeros(1, 0));
columns = ["valueX", "valueY"];
for a = 1:numel(formulaAxes)
    best = struct("n", Inf, "local", zeros(0, 2), "label", "");
    for w = 1:numel(wafers)
        points = wafers(w).points;
        [key, nameOf] = groupOfPoints(points, unit);
        valid = find(isfinite(points.(columns(a))) & isfinite(points.shotNo) & isfinite(key));
        [keys, ~, index] = unique(key(valid));
        for g = 1:numel(keys)
            members = valid(index == g);
            local = [points.localX(members), points.localY(members)];
            if numel(members) >= best.n || rank([ones(numel(members), 1), local]) < 3
                continue   % k1〜k6 を決められない組は補正しない（基準にしない）
            end
            name = string(wafers(w).label);
            if unit ~= "common"
                name = name + " の " + nameOf(keys(g), points.shotNo(members(1)));
            end
            best = struct("n", numel(members), "local", local, "label", name);
        end
    end
    if ~isfinite(best.n)
        continue
    end
    rows = find(terms.axis == formulaAxes(a) & terms.used);
    [~, order] = sortrows([~terms.protected(rows), terms.k(rows)]);   % k1〜k6 を先に、残りは k の小さい順
    rows = rows(order);
    basis = zeros(best.n, 0);
    dropped = zeros(1, 0);
    for row = reshape(rows, 1, [])
        column = best.local(:, 1) .^ terms.xPower(row) .* best.local(:, 2) .^ terms.yPower(row);
        scale = norm(column);
        remainder = column;
        for pass = 1:2
            remainder = remainder - basis * (basis.' * remainder);
        end
        if scale > 0 && norm(remainder) > sqrt(RELATIVE_TOLERANCE) * scale
            basis(:, end + 1) = remainder / norm(remainder); %#ok<AGROW>
        elseif ~terms.protected(row)
            terms.used(row) = false;
            dropped(end + 1) = terms.k(row); %#ok<AGROW>
        end
    end
    info(a).reference = best.label;
    info(a).nPoints = best.n;
    info(a).dropped = sort(dropped);
end
end

function messages = reductionMessages(info)
% 項数を絞ったときの知らせ（絞らなければ空）
messages = strings(0, 1);
for a = 1:numel(info)
    if isempty(info(a).dropped)
        continue
    end
    messages(end + 1, 1) = sprintf(['⚠ %s：選んだ項が、点の数が最も少ない k の組（%s：%d 点）では求められないため、' ...
        'k の小さい順に決められる項だけを使いました（外した項：%s）。'], info(a).axis, info(a).reference, info(a).nPoints, ...
        strjoin("k" + string(info(a).dropped), "・")); %#ok<AGROW>
end
end

function points = withGroupColumns(points)
% Scan 方向（direction）・Shot 行の奇偶（rowParity）の列が無い点の表に足す（Scan 方向は分からない。行は Shot 中心の
% Y 座標が同じ Shot の並びを上から数える。alignest.prepareData の Shot 行と同じ数え方）
SHOT_COORDINATE_DIGITS = 3;   % 行を判定する桁（1 µm。alignest.prepareData と同じ）
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
end

function [key, nameOf] = groupOfPoints(points, unit)
% 点ごとの k の組の番号（分からない点は NaN）と、組の名前を返す関数 nameOf(番号, shotNo)
ROW_NAMES = ["奇数行", "偶数行"];
n = height(points);
switch unit
    case "common"
        key = ones(n, 1);
        nameOf = @(keys, ~) repmat("共通", numel(keys), 1);
    case "scan"
        key = points.direction;
        key(~ismember(key, [1, 2])) = NaN;
        nameOf = @(keys, ~) "Scan 方向 " + string(keys(:));
    case "row"
        key = points.rowParity;
        key(~ismember(key, [1, 2])) = NaN;
        nameOf = @(keys, ~) reshape(ROW_NAMES(keys), [], 1);
    otherwise
        key = points.shotNo;
        nameOf = @(~, shotNos) "Shot " + string(shotNos(:));
end
end

function fitUnits = partitionRows(rows, shotNo, groupKey, groupName, unit)
% 一緒に求める点の集まり（members）と、その中の k の組（groupIndex：1〜組の数、labels：組の名前）。Shot ごとは Shot ごとに
% 別に求める。ほかは Wafer の点をまとめて求める（Wafer 成分は共通、k は組ごと）
fitUnits = struct("members", {}, "groupIndex", {}, "labels", {}, "shotNo", {});
if isempty(rows)
    return   % この軸の値が無い Wafer
end
if unit == "shot"
    [shots, ~, index] = unique(shotNo(rows));
    for s = 1:numel(shots)
        members = rows(index == s);
        fitUnits(s) = struct("members", members, "groupIndex", ones(numel(members), 1), "labels", ...
            groupName(1, shots(s)), "shotNo", shots(s));
    end
    return
end
[keys, ~, index] = unique(groupKey(rows));
fitUnits(1) = struct("members", rows, "groupIndex", index, "labels", groupName(keys, nan(size(keys))), "shotNo", NaN);
end

function out = fitGroups(coordinates, values, groupIndex, terms, waferPowers, lambda, fitOptions)
% 一緒に求める点の集まりに補正の式を当てはめる：k は組（groupIndex）ごと、Wafer 成分は共通。項がすべては決まらない組は
% 補正しない（その組を除いて求め直す。組の項はその組の点だけで決まるので、ほかの組は変わらない）。
% coordinates：点ごとの [Shot 内の x, Shot 内の y, Shot 中心の Xc, Yc]。
% out.ok：補正した組、out.fitted・weights：点ごと（補正しない組の点は NaN）、out.coefficients・determined・
% constant：項 × 組、out.waferCoefficients・waferDetermined・waferConstant：Wafer 成分の項
nGroups = max([groupIndex(:); 0]);
nTerms = height(terms);
nWafer = size(waferPowers, 1);
n = numel(values);
out = struct("ok", false(1, nGroups), "fitted", nan(n, 1), "weights", nan(n, 1), ...
    "coefficients", nan(nTerms, nGroups), "determined", false(nTerms, nGroups), "constant", false(nTerms, nGroups), ...
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
    fit = solveGroups(coordinates(rows, :), values(rows), local, numel(active), terms, waferPowers, lambda, fitOptions);
    out.determined(:, active) = reshape(fit.determined(1:nTerms * numel(active)), nTerms, []);
    ok = all(out.determined(:, active), 1);
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
out.coefficients(:, active) = reshape(fit.coefficients(1:nTerms * numel(active)), nTerms, []);
out.constant(:, active) = reshape(fit.constant(1:nTerms * numel(active)), nTerms, []);
waferColumns = nTerms * numel(active) + (1:nWafer);
out.waferCoefficients = fit.coefficients(waferColumns);
out.waferDetermined = fit.determined(waferColumns);
out.waferConstant = fit.constant(waferColumns);
out.converged = fit.converged;
out.robust = fit.robust;
end

function fit = solveGroups(coordinates, values, groupIndex, nGroups, terms, waferPowers, lambda, fitOptions)
% 設計行列：組ごとの補正の式の項（その組の点だけ値があり、ほかは 0）と、共通の Wafer 成分の項
local = coordinates(:, 1) .^ (terms.xPower.') .* coordinates(:, 2) .^ (terms.yPower.');
wafer = coordinates(:, 3) .^ (waferPowers(:, 1).') .* coordinates(:, 4) .^ (waferPowers(:, 2).');
nTerms = height(terms);
blocks = zeros(numel(values), nTerms * nGroups);
for g = 1:nGroups
    blocks(:, (g - 1) * nTerms + (1:nTerms)) = local .* (groupIndex == g);
end
isPenalized = [repmat(terms.order >= 2, nGroups, 1); false(size(waferPowers, 1), 1)];
groupOptions = {};
if nGroups > 1
    groupOptions = {'rowGroup', groupIndex, 'columnGroup', [repelem((1:nGroups).', nTerms, 1); ...
        zeros(size(waferPowers, 1), 1)]};
end
fit = alignest.robustRidgeFit([blocks, wafer], values, isPenalized, fitOptions{:}, 'lambda', lambda, groupOptions{:});
end

function names = termNames(terms)
names = reshape("k" + string(terms.k) + "（" + terms.term + "）", 1, []);
end

function rows = coefficientRows(label, fitUnit, axisName, terms, names, waferPowers, fit)
% 係数の行（列ごとの配列の構造体。最後に coefficientTable で表にする）：補正した k の組ごとの補正の式の項（k）と、
% Wafer で共通の Wafer 成分の項
nTerms = height(terms);
groups = find(fit.ok);
nGroups = numel(groups);
nWafer = size(waferPowers, 1);
nRows = nTerms * nGroups + nWafer;
determined = [reshape(fit.determined(:, groups), [], 1); fit.waferDetermined];
constant = [reshape(fit.constant(:, groups), [], 1); fit.waferConstant];
note = strings(nRows, 1);
note(constant) = "点の配置では値が変わらない（定数と同じ）ので 0";
note(~determined) = "点の配置では決まらない（0 にした）";
rows = struct("wafer", repmat(string(label), nRows, 1), ...
    "shotNo", [repmat(fitUnit.shotNo, nTerms * nGroups, 1); nan(nWafer, 1)], ...
    "group", [repelem(reshape(fitUnit.labels(groups), [], 1), nTerms, 1); repmat("Wafer で共通", nWafer, 1)], ...
    "axis", repmat(string(axisName), nRows, 1), ...
    "component", [repmat("Shot 高次補正", nTerms * nGroups, 1); repmat("Wafer 成分", nWafer, 1)], ...
    "k", [repmat(terms.k, nGroups, 1); nan(nWafer, 1)], ...
    "term", [repmat(names(:), nGroups, 1); waferTermNames(waferPowers)], ...
    "value", [reshape(fit.coefficients(:, groups), [], 1); fit.waferCoefficients], ...
    "unit", unitText([repmat(terms.order, nGroups, 1); sum(waferPowers, 2)]), "note", note, ...
    "xPower", [repmat(terms.xPower, nGroups, 1); waferPowers(:, 1)], ...
    "yPower", [repmat(terms.yPower, nGroups, 1); waferPowers(:, 2)]);
end

function coefficients = coefficientTable(parts)
% 係数の行（coefficientRows の構造体の配列）を縦につないで表にする（行が無ければ列だけの表）
% xPower・yPower は項のべき（Shot 高次補正は Shot 内の x・y、Wafer 成分は Shot 中心の Xc・Yc。alignest.highOrderModelAt）
names = ["wafer", "shotNo", "group", "axis", "component", "k", "term", "value", "unit", "note", "xPower", "yPower"];
if isempty(parts)
    parts = struct("wafer", strings(0, 1), "shotNo", zeros(0, 1), "group", strings(0, 1), "axis", strings(0, 1), ...
        "component", strings(0, 1), "k", zeros(0, 1), "term", strings(0, 1), "value", zeros(0, 1), "unit", ...
        strings(0, 1), "note", strings(0, 1), "xPower", zeros(0, 1), "yPower", zeros(0, 1));
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

function row = summaryRow(label, axisName, shotKeys, points, kSets, skipped, tolerance)
% 1つの Wafer・軸の評価（points は点の表。axisName の列を使う）。補正前・Shot ごとの1次・高次補正の |平均|+3σ は、
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
row = table(string(label), string(axisName), nnz(withValue), nnz(compared), shots, kSets, skipped, before, linear, ...
    highOrder, linear - highOrder, p95, middle, rms, nnz(compared & weights < 1 - tolerance), 'VariableNames', ...
    ["wafer", "axis", "n", "nCorrected", "shots", "kSets", "skipped", "before", "linear", "highOrder", "improvement", ...
    "highOrderP95", "highOrderMedian", "rmsHighOrder", "downweighted"]);
end

function value = meanPlus3Sigma(values)
% Overlay の代表値 |平均| + 3σ（σ は不偏標準偏差）。点が2点未満なら NaN（alignest.overlayCorrection と同じ）
values = values(isfinite(values));
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end

function messages = buildMessages(options, wafers, everything, counts, vifInfo)
messages = strings(0, 1);
messages(end + 1, 1) = sprintf('%d Wafer・%d 点（dx の値 %d 点・dy の値 %d 点）で求めました。補正：%s。', numel(wafers), ...
    height(everything), nnz(isfinite(everything.valueX)), nnz(isfinite(everything.valueY)), options.description);
noShot = nnz(~isfinite(everything.shotNo));
if noShot > 0
    messages(end + 1, 1) = sprintf('Shot の分からない点 %d 点は使っていません。', noShot);
end
if options.unit == "scan"
    noDirection = nnz(~ismember(everything.direction, [1, 2]) & isfinite(everything.shotNo));
    if noDirection > 0
        messages(end + 1, 1) = sprintf('⚠ Scan 方向の分からない点 %d 点は使っていません（補正量・残差は空欄）。', noDirection);
    end
end
groupNames = struct("common", "Wafer", "scan", "k の組（Scan 方向）", "row", "k の組（行の偶奇）", "shot", "Shot");
groupName = groupNames.(options.unit);
fitName = "Wafer";
if options.unit == "shot"
    fitName = "Shot";
end
if any(counts.skipped > 0)
    messages(end + 1, 1) = sprintf(['⚠ 点が足りない（または点の配置で項が決まらない）ため補正しなかった %s：dx %d / %d・' ...
        'dy %d / %d（補正量・残差は空欄）。'], groupName, counts.skipped(1), counts.groups(1), counts.skipped(2), ...
        counts.groups(2));
    messages(end) = messages(end) + "決まらない項：" + strjoin(counts.undetermined, "・") + "。";
    if ~(options.l2 && options.lambda > 0)
        messages(end) = messages(end) + "「VIF で選ぶ」でその項を外すか、高次項に L2 正則化をかけてください" + ...
            "（L2 をかけると、点が少なくても高次項が決まります）。";
    else
        messages(end) = messages(end) + "1次の項（k1〜k6）を決めるには、1つの k の組に同じ直線の上に無い3点以上が要ります。";
    end
end
if ~isempty(counts.constant)
    messages(end + 1, 1) = "⚠ 点の配置では値が変わらない（定数と同じになる）項：" + strjoin(counts.constant, "・") + ...
        "。L2 正則化で 0 にしました（VIF が ∞ の項。「VIF で選ぶ」で外せます）。";
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
messages(end + 1, 1) = sprintf(['VIF は Shot 内の座標（dx %d 点・dy %d 点、位置 %d・%d か所）で求めました。' ...
    '「VIF で選ぶ」（しきい値 %.4g）で外す項：%s。'], vifInfo.points(1), vifInfo.points(2), vifInfo.positions(1), ...
    vifInfo.positions(2), options.vifThreshold, suggestedText(vifInfo.suggestedExcluded));
end

function text = suggestedText(numbers)
if isempty(numbers)
    text = "なし";
else
    text = strjoin("k" + string(numbers), "・");
end
end
