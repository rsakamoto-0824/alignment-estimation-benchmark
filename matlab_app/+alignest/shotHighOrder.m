function result = shotHighOrder(wafers, settings)
%SHOTHIGHORDER Shot 高次補正（Shot 内の座標の補正の式）の係数（k パラメータ）を Wafer ごとに求め、補正の効果を評価する。
%   result = alignest.shotHighOrder(wafers, settings)
%   wafers：Wafer ごとの構造体の配列。label（Wafer の名前）・points（点の表。alignest.highOrderUnitPoints・
%   alignest.highOrderTargetPoints の形：source・name・shotNo・Xc・Yc（Shot 中心 [mm]）・localX・localY（Shot 内の座標 [mm]）・
%   x・y（Wafer 上の座標 [mm]）・valueX・valueY（dx・dy の値 [nm]。値の無い点は NaN））。
%   settings：設定（settings.highOrder を alignest.highOrderOptions で確かめて使う）。
%   補正の式：補正の式（ASML・Canon・Nikon）のうち使う項（k パラメータ。terms.used）。dx の式は X の値、dy の式は Y の値に
%   当てはめる。x・y は Shot 内の座標 [mm]。
%   - Wafer 内の Shot で共通（unit = "common"）：Wafer ごとに1組の k を、その Wafer のすべての点で求める。Wafer 成分
%     （Shot 中心の座標 Xc・Yc の 1〜waferOrder 次の項。定数は k1・k2 に含める）も一緒に求める（L2 はかけない）
%   - Shot ごと（unit = "shot"）：Shot ごとに1組の k を、その Shot の点だけで求める
%   回帰は alignest.robustRidgeFit（最小二乗・Huber・LAD、L2 は2次以上の項だけ）。比べるために、同じ点・同じ損失関数で
%   1次の項（k1〜k6）だけ（と Wafer 成分）で補正した残差も求める。
%   項がすべて決まらない組（点が足りない・点の配置で決まらない Shot・Wafer）は補正しない（補正量・残差は NaN）。
%   L2 をかける高次項は点が少なくても決まる（λ > 0 のとき）。Wafer 成分の決まらない項は 0 にする。
%   result.terms：項の表（alignest.highOrderVif。全 Wafer の点の Shot 内の座標で求めた VIF を含む）
%   result.coefficients：補正値（係数）の表（wafer・shotNo（Shot ごとのとき）・axis・component・k・term・value・unit・note）。
%   係数は mm の座標での値（単位 nm/mm^次数。1次は nm/mm = ppm）
%   result.summary：Wafer・軸ごとの評価と、全 Wafer をまとめた行（wafer = "すべての Wafer"）。点の数、補正前・1次だけで
%   補正した残差・高次補正の残差の |平均| + 3σ [nm]（before・linear・highOrder）、1次だけと比べた改善（improvement）、
%   1点抜きの予測の誤差の |平均| + 3σ（looLinear・looHighOrder。点を1つずつ抜いて求め直した補正で、抜いた点を予測した
%   ときの誤差。同じ点で当てはめた残差は、項を増やすほど小さく見えるので、項の選び方は予測の誤差でも比べる）、
%   高次補正の残差の RMS、ロバスト回帰で重みを下げた点の数、補正しなかった組（Shot ごとのときは Shot、共通のときは
%   Wafer）の数
%   result.points：点ごとの値・補正量・残差・1次だけで補正した残差・1点抜きの予測の誤差・ロバスト回帰の重み
%   （wafer の列を足して縦に並べる）
%   result.messages：画面に出す説明、result.options・description：使った設定
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
lambda = options.lambda * options.l2;
fitOptions = {'loss', options.loss, 'huberTuning', options.huberTuning};
terms = alignest.highOrderTerms(options.maker, options.excludedTerms);
everything = vertcat(wafers.points);
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
    [correction, linearCorrection, weights, loo, linearLoo] = deal(nan(nPoints, 2));
    skippedShots = zeros(1, 2);
    for a = 1:2
        rows = find(isfinite(values(:, a)) & isfinite(points.shotNo));
        axisTerms = terms(terms.axis == FORMULA_AXES(a), :);
        usedTerms = axisTerms(axisTerms.used, :);
        linearTerms = axisTerms(axisTerms.order <= 1, :);
        if options.unit == "common"
            groups = {rows};
            groupShot = NaN;
        else
            [groupShot, ~, groupIndex] = unique(points.shotNo(rows));
            groups = accumarray(groupIndex, rows, [], @(members) {members});
        end
        parts = cell(numel(groups), 1);
        for g = 1:numel(groups)
            members = groups{g};
            if isempty(members)
                continue   % この軸の値が無い Wafer
            end
            counts.groups(a) = counts.groups(a) + 1;
            [fit, ok, waferMissing] = fitGroup(points(members, :), values(members, a), usedTerms, waferPowers, lambda, ...
                fitOptions);
            if ok
                correction(members, a) = fit.fitted;
                weights(members, a) = fit.weights;
                loo(members, a) = fit.looResidual;
                parts{g} = coefficientRows(label, groupShot(g), FORMULA_AXES(a), usedTerms, waferPowers, fit);
                counts.notConverged = counts.notConverged + ~fit.converged;
                counts.noRobust = counts.noRobust + (options.loss ~= "ols" && ~fit.robust);
                counts.waferDropped = counts.waferDropped + waferMissing;
                flat = fit.constant(1:height(usedTerms));
                counts.constant = unique([counts.constant, ...
                    reshape("k" + string(usedTerms.k(flat)) + "（" + usedTerms.term(flat) + "）", 1, [])], 'stable');
            else
                skippedShots(a) = skippedShots(a) + 1;
                counts.skipped(a) = counts.skipped(a) + 1;
                missing = ~fit.determined(1:height(usedTerms));
                counts.undetermined = unique([counts.undetermined, ...
                    reshape("k" + string(usedTerms.k(missing)) + "（" + usedTerms.term(missing) + "）", 1, [])], 'stable');
            end
            [linearFit, linearOk] = fitGroup(points(members, :), values(members, a), linearTerms, waferPowers, 0, ...
                fitOptions);
            if linearOk
                linearCorrection(members, a) = linearFit.fitted;
                linearLoo(members, a) = linearFit.looResidual;
            end
        end
        coefficientParts{w, a} = vertcat(parts{:});
    end
    residual = values - correction;
    linearResidual = values - linearCorrection;
    pointParts{w} = [table(repmat(label, nPoints, 1), 'VariableNames', "wafer"), ...
        points(:, ["source", "name", "shotNo", "x", "y", "localX", "localY", "valueX", "valueY"]), ...
        table(correction(:, 1), correction(:, 2), residual(:, 1), residual(:, 2), linearResidual(:, 1), ...
        linearResidual(:, 2), loo(:, 1), loo(:, 2), linearLoo(:, 1), linearLoo(:, 2), weights(:, 1), weights(:, 2), ...
        'VariableNames', ["correctionX", "correctionY", "residualX", "residualY", "linearResidualX", "linearResidualY", ...
        "looX", "looY", "linearLooX", "linearLooY", "weightX", "weightY"])];
    for a = 1:2
        summaryParts{w, a} = summaryRow(label, AXIS_NAMES(a), points.shotNo, pointParts{w}, skippedShots(a), ...
            WEIGHT_TOLERANCE);
    end
end
result.options = options;
result.description = options.description;
result.terms = terms;
result.vifInfo = vifInfo;
coefficients = vertcat(coefficientParts{:});
if isempty(coefficients)
    coefficients = coefficientRows(strings(0, 1), NaN, "dx", terms([], :), zeros(0, 2), struct("coefficients", ...
        zeros(0, 1), "determined", false(0, 1), "constant", false(0, 1)));
end
result.coefficients = coefficients;
result.points = vertcat(pointParts{:});
all_ = result.points;
for a = 1:2
    axisName = AXIS_NAMES(a);
    summaryParts{end, a} = summaryRow(ALL_LABEL, axisName, all_.wafer + "|" + string(all_.shotNo), all_, ...
        counts.skipped(a), WEIGHT_TOLERANCE);
end
summary = vertcat(summaryParts{:});
[~, order] = sortrows([summary.axis == "Y", (1:height(summary)).']);   % X の行、Y の行の順
result.summary = summary(order, :);
result.messages = buildMessages(options, wafers, everything, counts, vifInfo);
totals = result.summary(result.summary.wafer == ALL_LABEL, :);
if any(totals.nPredicted < totals.nCorrected)
    result.messages(end + 1, 1) = sprintf(['1点抜きの予測の誤差は、抜くと項が決まらなくなる点（その点だけで決まる項がある）' ...
        'では求めていません（dx %d / %d 点・dy %d / %d 点で比べました）。'], totals.nPredicted(1), totals.nCorrected(1), ...
        totals.nPredicted(2), totals.nCorrected(2));
end
end

function [fit, ok, waferMissing] = fitGroup(points, values, terms, waferPowers, lambda, fitOptions)
% 1つの組（Wafer、または Shot）の点に、補正の式の項（と Wafer 成分）を当てはめる。ok は補正の式の項がすべて決まったか
local = points.localX .^ (terms.xPower.') .* points.localY .^ (terms.yPower.');
wafer = points.Xc .^ (waferPowers(:, 1).') .* points.Yc .^ (waferPowers(:, 2).');
A = [local, wafer];
isPenalized = [terms.order >= 2; false(size(waferPowers, 1), 1)];
fit = alignest.robustRidgeFit(A, values, isPenalized, fitOptions{:}, 'lambda', lambda);
nTerms = height(terms);
ok = all(fit.determined(1:nTerms));
waferMissing = any(~fit.determined(nTerms + 1:end));
end

function rows = coefficientRows(label, shotNo, axisName, terms, waferPowers, fit)
% 係数の表の行：補正の式の項（k）と Wafer 成分の項。決まらない Wafer 成分の項はメモを付ける
nTerms = height(terms);
nWafer = size(waferPowers, 1);
order = [terms.order; sum(waferPowers, 2)];
component = [repmat("Shot 高次補正", nTerms, 1); repmat("Wafer 成分", nWafer, 1)];
k = [terms.k; nan(nWafer, 1)];
names = ["k" + string(terms.k) + "（" + terms.term + "）"; waferTermNames(waferPowers)];
note = strings(nTerms + nWafer, 1);
note(fit.constant) = "点の配置では値が変わらない（定数と同じ）ので 0";
note(~fit.determined) = "点の配置では決まらない（0 にした）";
n = nTerms + nWafer;
rows = table(repmat(string(label), n, 1), repmat(shotNo, n, 1), repmat(string(axisName), n, 1), component, k, names, ...
    fit.coefficients(:), unitText(order), note, 'VariableNames', ["wafer", "shotNo", "axis", "component", "k", "term", ...
    "value", "unit", "note"]);
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

function row = summaryRow(label, axisName, shotKeys, points, skipped, tolerance)
% 1つの Wafer・軸の評価（points は点の表。axisName の列を使う）。補正前・1次だけ・高次補正の |平均|+3σ は、どちらの
% 補正もできた点で比べる。1点抜きの予測の誤差は、どちらも求められた点で比べる
values = points.("value" + axisName);
residual = points.("residual" + axisName);
linearResidual = points.("linearResidual" + axisName);
loo = points.("loo" + axisName);
linearLoo = points.("linearLoo" + axisName);
weights = points.("weight" + axisName);
compared = isfinite(residual) & isfinite(linearResidual);
predicted = compared & isfinite(loo) & isfinite(linearLoo);
withValue = isfinite(values);
shots = numel(unique(shotKeys(withValue)));
before = meanPlus3Sigma(values(compared));
linear = meanPlus3Sigma(linearResidual(compared));
highOrder = meanPlus3Sigma(residual(compared));
rms = NaN;
if any(compared)
    rms = sqrt(mean(residual(compared) .^ 2));
end
row = table(string(label), string(axisName), nnz(withValue), nnz(compared), shots, skipped, before, linear, highOrder, ...
    linear - highOrder, meanPlus3Sigma(linearLoo(predicted)), meanPlus3Sigma(loo(predicted)), nnz(predicted), rms, ...
    nnz(compared & weights < 1 - tolerance), 'VariableNames', ["wafer", "axis", "n", "nCorrected", "shots", "skipped", ...
    "before", "linear", "highOrder", "improvement", "looLinear", "looHighOrder", "nPredicted", "rmsHighOrder", ...
    "downweighted"]);
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
groupName = "Wafer";
if options.unit == "shot"
    groupName = "Shot";
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
        messages(end) = messages(end) + "1次の項（k1〜k6）を決めるには、1つの組に同じ直線の上に無い3点以上が要ります。";
    end
end
if ~isempty(counts.constant)
    messages(end + 1, 1) = "⚠ 点の配置では値が変わらない（定数と同じになる）項：" + strjoin(counts.constant, "・") + ...
        "。L2 正則化で 0 にしました（VIF が ∞ の項。「VIF で選ぶ」で外せます）。";
end
if counts.noRobust > 0
    messages(end + 1, 1) = sprintf(['点の数が項の数以下の %s が %d 個あり、そこではロバスト回帰の重みを使わずに' ...
        '求めました（残差がほぼ 0 になり、外れ値を見分けられないため）。'], groupName, counts.noRobust);
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
