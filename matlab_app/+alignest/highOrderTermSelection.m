function selection = highOrderTermSelection(wafers, settings, method, options)
%HIGHORDERTERMSELECTION Shot 高次補正の k パラメータ（補正の式の項）を、単純な回帰で選ぶ。
%   selection = alignest.highOrderTermSelection(wafers, settings, "importance", threshold=2)
%   selection = alignest.highOrderTermSelection(wafers, settings, "stepwise")
%   wafers：alignest.shotHighOrder と同じ Wafer ごとの点（label・points。points は localX・localY・Xc・Yc・valueX・valueY・shotNo）。
%   settings：設定（settings.highOrder の補正の式 maker・使わない項 excludedTerms・Wafer 成分の次数 waferOrder を使う）。
%   回帰は、Wafer ごと・式（dx・dy）ごとの最小二乗（Wafer 内の Shot で共通の1組の k。くくり・正則化・ロバスト回帰は使わない）。
%   Wafer 成分（Shot 中心の座標 Xc・Yc の 1〜waferOrder 次の項）があれば、一緒に当てはめる（選ぶ対象にはしない）。
%   列は大きさをそろえてから解く（t 値・残差は変わらない）。外周の式（outerMaker）は対象にせず、内周の式の項で全 Shot の点を使う。
%   - "importance"（変数重要度で一括して外す）：式のすべての項で当てはめ、項ごとの |t 値|（係数 ÷ 標準誤差）の Wafer の間の
%     中央値を重要度とする。重要度がしきい値 threshold より小さい項を外す（k1〜k6 は外さない）。点の配置で決まらない項
%     （前の項で表せる項。k の小さい項を残す）は、その Wafer では t 値を求めず、どの Wafer でも決まらない項は重要度 NaN で外す。
%     selection.importance：項ごとの表（axis・k・term・order・protected・importance（|t| の中央値）・minT・maxT（|t| の最小・
%     最大）・nWafers（求められた Wafer の数）・keep（使うか））
%   - "stepwise"（ステップワイズで足す）：今の使う項（settings の excludedTerms を除いた項。k1〜k6 は必ず）から始め、式の残りの
%     項のうち、BIC（すべての Wafer の Σ [n ln(RSS/n) + p ln n]。n は点の数、p は決まる列の数（Wafer 成分を含む））が最も小さくなる項を
%     1つずつ足す。BIC が下がらなくなったら止める（式ごと）。
%     selection.steps：足した順の表（axis・step（0 は始めの項）・k・term・bic・change（1つ前との差））
%   selection.used：式ごとの使う項（k の番号。{dx の k, dy の k}）、selection.excludedTerms：使わない項（k の番号。設定の
%   excludedTerms にそのまま入れられる）、selection.messages：知らせ、selection.method・threshold・maker
arguments
    wafers struct
    settings struct
    method (1, 1) string {mustBeMember(method, ["importance", "stepwise"])}
    options.threshold (1, 1) double {mustBeNonnegative, mustBeFinite} = 2
end
FORMULA_AXES = ["dx", "dy"];
AXIS_NAMES = ["X", "Y"];
TOLERANCE = 1e-9;   % BIC がこれより下がらなければ足さない
highOrder = alignest.highOrderOptions(settings);
allTerms = alignest.highOrderTerms(highOrder.maker);
currentTerms = alignest.highOrderTerms(highOrder.maker, highOrder.excludedTerms);
waferPowers = powersUpTo(highOrder.waferOrder);
messages = strings(0, 1);
if highOrder.outerMaker ~= "none"
    messages(end + 1, 1) = "外周の式は選ぶ対象にせず、内周の式の項で全 Shot の点を使って選びました。";
end
data = cell(numel(wafers), 2);   % Wafer × 式：struct（local：Shot 内の座標、wafer：Wafer 成分の列、y：値）
for w = 1:numel(wafers)
    points = wafers(w).points;
    for a = 1:2
        rows = isfinite(points.("value" + AXIS_NAMES(a))) & isfinite(points.shotNo);
        data{w, a} = struct("local", [points.localX(rows), points.localY(rows)], ...
            "wafer", [points.Xc(rows), points.Yc(rows)], "y", points.("value" + AXIS_NAMES(a))(rows));
    end
end
% 足しても決まらない（ほかの列で表せる）項は残差が減らず BIC が増えるだけなので、その知らせは出さない
warningState = warning('off', 'MATLAB:rankDeficientMatrix');
restoreWarning = onCleanup(@() warning(warningState));
used = cell(1, 2);
importanceParts = cell(2, 1);
stepParts = cell(2, 1);
for a = 1:2
    terms = allTerms(allTerms.axis == FORMULA_AXES(a), :);
    if method == "importance"
        tValues = nan(height(terms), numel(wafers));
        for w = 1:numel(wafers)
            [design, nuisance] = designOf(data{w, a}, terms, waferPowers);
            tValues(:, w) = termTValues([design, nuisance], data{w, a}.y, height(terms));
        end
        nWafers = sum(isfinite(tValues), 2);
        importance = median(abs(tValues), 2, 'omitnan');
        keep = terms.protected | importance >= options.threshold;
        importanceParts{a} = table(terms.axis, terms.k, terms.term, terms.order, terms.protected, importance, ...
            min(abs(tValues), [], 2, 'omitnan'), max(abs(tValues), [], 2, 'omitnan'), nWafers, keep, 'VariableNames', ...
            ["axis", "k", "term", "order", "protected", "importance", "minT", "maxT", "nWafers", "keep"]);
        if all(nWafers == 0)
            messages(end + 1, 1) = FORMULA_AXES(a) + " の式：点が項の数より少ない Wafer ばかりで、重要度を求められませんでした。"; %#ok<AGROW>
        end
        used{a} = reshape(terms.k(keep), 1, []);
    else
        start = currentTerms.axis == FORMULA_AXES(a) & (currentTerms.used | currentTerms.protected);
        chosen = reshape(currentTerms.k(start), 1, []);
        candidates = setdiff(reshape(terms.k, 1, []), chosen, 'stable');
        bic = totalBic(data(:, a), terms, chosen, waferPowers);
        steps = {stepRow(FORMULA_AXES(a), 0, NaN, "始めの項：" + strjoin("k" + string(chosen), "・"), bic, NaN)};
        while ~isempty(candidates)
            trial = arrayfun(@(k) totalBic(data(:, a), terms, [chosen, k], waferPowers), candidates);
            [best, position] = min(trial);
            if ~(best < bic - TOLERANCE)
                break
            end
            added = candidates(position);
            chosen = [chosen, added]; %#ok<AGROW>
            candidates(position) = [];
            steps{end + 1} = stepRow(FORMULA_AXES(a), numel(steps), added, terms.term(terms.k == added), best, ...
                best - bic); %#ok<AGROW>
            bic = best;
        end
        stepParts{a} = vertcat(steps{:});
        used{a} = sort(chosen);
    end
end
excluded = setdiff(reshape(allTerms.k, 1, []), [used{:}]);
selection = struct("method", method, "threshold", options.threshold, "maker", highOrder.maker, "used", {used}, ...
    "excludedTerms", excluded, "messages", messages);
if method == "importance"
    selection.importance = vertcat(importanceParts{:});
else
    selection.steps = vertcat(stepParts{:});
end
end

function powers = powersUpTo(order)
% Wafer 成分の項のべき（1〜order 次。定数は補正の式の k1・k2 に含める）
powers = zeros(0, 2);
for degree = 1:order
    for yPower = 0:degree
        powers(end + 1, :) = [degree - yPower, yPower]; %#ok<AGROW>
    end
end
end

function [design, nuisance] = designOf(datum, terms, waferPowers)
% 補正の式の項の列と、Wafer 成分の列（大きさをそろえる前）
design = datum.local(:, 1) .^ (terms.xPower.') .* datum.local(:, 2) .^ (terms.yPower.');
nuisance = datum.wafer(:, 1) .^ (waferPowers(:, 1).') .* datum.wafer(:, 2) .^ (waferPowers(:, 2).');
end

function tValues = termTValues(design, y, nTerms)
% 最小二乗の係数の |t| のための t 値（先頭 nTerms 列）。点の配置で決まらない列（前の列で表せる列。k の小さい項を残す）は
% 外して当てはめ、その項は NaN。点が列の数以下なら NaN
RELATIVE_TOLERANCE = 1e-9;
tValues = nan(nTerms, 1);
scale = sqrt(mean(design .^ 2, 1));
scale(scale == 0) = 1;
keep = alignest.independentColumns(design ./ scale, RELATIVE_TOLERANCE);
scaled = design(:, keep) ./ scale(keep);
[n, p] = size(scaled);
if n <= p || p == 0
    return
end
[q, r] = qr(scaled, 0);
beta = r \ (q.' * y);
residual = y - scaled * beta;
sigma2 = sum(residual .^ 2) / (n - p);
rInverse = r \ eye(p);
standardError = sqrt(sigma2 * sum(rInverse .^ 2, 2));
t = nan(size(design, 2), 1);
t(keep) = beta ./ standardError;
tValues = t(1:nTerms);
end

function bic = totalBic(waferData, terms, chosen, waferPowers)
% すべての Wafer の BIC の和：Σ [n ln(RSS/n) + p ln n]（点が列の数以下の Wafer は入れない）
bic = 0;
mine = terms(ismember(terms.k, chosen), :);
for w = 1:numel(waferData)
    [design, nuisance] = designOf(waferData{w}, mine, waferPowers);
    design = [design, nuisance]; %#ok<AGROW>
    [n, p] = size(design);
    if n <= p
        continue
    end
    scale = sqrt(mean(design .^ 2, 1));
    scale(scale == 0) = 1;
    scaled = design ./ scale;
    residual = waferData{w}.y - scaled * (scaled \ waferData{w}.y);
    rss = max(sum(residual .^ 2), realmin);
    bic = bic + n * log(rss / n) + rank(scaled) * log(n);   % 決まらない列は数えない（足しても BIC は下がらない）
end
end

function row = stepRow(axisName, step, k, term, bic, change)
row = table(string(axisName), step, k, string(term), bic, change, 'VariableNames', ...
    ["axis", "step", "k", "term", "bic", "change"]);
end
