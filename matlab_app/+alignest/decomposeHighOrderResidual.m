function decomposition = decomposeHighOrderResidual(points, options)
%DECOMPOSEHIGHORDERRESIDUAL Shot 高次補正の残差を、Wafer 線形成分・Shot 共通成分・Shot 成分・残りに分け、それぞれが
%   k パラメータのどの項に近いかを求める（「7. Shot高次補正」の「残差の成分分解」）。
%   decomposition = alignest.decomposeHighOrderResidual(points)
%   decomposition = alignest.decomposeHighOrderResidual(points, terms=..., shotTerms="linear")
%   points：alignest.shotHighOrder の result.points（wafer・shotNo・x・y・localX・localY・residualX・residualY を使う）。
%   terms：Shot 共通成分・Shot 成分に使う項（alignest.highOrderTerms の表の使う項。既定はカスタムの k1〜k38）。
%   shotTerms："linear"（Shot 成分は k1〜k6：並進・倍率・回転）・"same"（Shot 成分も terms の項）。
%   分け方（Wafer・軸ごと。残差のある点だけ。前の成分を引いた残りに次の成分を当てはめる。どれも最小二乗）：
%   1. Wafer 線形成分：Shot 中心の座標の1次（dx：k1 + k3·Xc + k5·Yc、dy：k2 + k4·Yc + k6·Xc）
%   2. Shot 共通成分：terms の項のうち定数を除く項（Shot 内の座標 x・y。Wafer 内の全 Shot で同じ係数）
%   3. Shot 成分：Shot ごとの項（Shot ごとに別の係数。Shot の点の数より少ない項だけを使う。点の数と同じだけ項を使うと、
%      雑音まで項に入ってしまうため）
%   4. 残り：どの項にも当てはまらない分（計測の雑音・式に無い形）
%   項は k の小さい順に足し、項を足して減った残差の二乗和を、その項の分とする（前の項で表せる分は前の項に入る。点の配置で
%   決まらない項は使わない）。成分・項の分は足すと全体（残差の二乗和）になる。
%   decomposition.levels：成分ごとの表（wafer（"すべての Wafer" は全 Wafer の合計）・axis（"X"・"Y"）・level・n（点の数）・
%   ss（二乗和 [nm²]）・rms（√(ss / 点の数) [nm]）・share（全体の二乗和に占める割合 [%]））
%   decomposition.terms：項ごとの表（wafer・axis・level・k・term・coefficient（係数。Shot 成分は Shot の平均、
%   「すべての Wafer」は Wafer の平均）・spread（係数の Shot・Wafer の間の標準偏差）・nUnits（係数を求めた Shot・Wafer の数）・
%   ss・rms・share・largest（Shot 成分で、その項の分が最も大きい Shot））。係数は mm の座標での値（nm/mm^次数）
%   decomposition.components：点ごとの成分（waferLinear・common・shot・rest。それぞれ点の数 × 2（X・Y）[nm]。残差の無い点は NaN）
arguments
    points table
    options.terms table = alignest.highOrderTerms("custom")
    options.shotTerms (1, 1) string {mustBeMember(options.shotTerms, ["linear", "same"])} = "linear"
end
ALL_LABEL = "すべての Wafer";
LEVEL_NAMES = ["Wafer 線形", "Shot 共通", "Shot", "残り"];
AXIS_NAMES = ["X", "Y"];
FORMULA_AXES = ["dx", "dy"];
% Wafer 線形成分の項（Shot 中心の座標。k の番号は Shot 内の1次の項と同じ付け方）
WAFER_TERMS = struct("dx", struct("k", [1; 3; 5], "term", ["1"; "Xc"; "Yc"], "xPower", [0; 1; 0], "yPower", [0; 0; 1]), ...
    "dy", struct("k", [2; 4; 6], "term", ["1"; "Yc"; "Xc"], "xPower", [0; 0; 1], "yPower", [0; 1; 0]));
n = height(points);
waferNames = unique(points.wafer, 'stable');
Xc = points.x - points.localX;
Yc = points.y - points.localY;
components = struct("waferLinear", nan(n, 2), "common", nan(n, 2), "shot", nan(n, 2), "rest", nan(n, 2));
levelParts = cell(numel(waferNames) + 1, 2);
termParts = cell(numel(waferNames) + 1, 2);
for a = 1:2
    terms = options.terms(options.terms.axis == FORMULA_AXES(a) & options.terms.used, :);
    terms = sortrows(terms, "k");
    commonTerms = terms(terms.order >= 1, :);   % 定数は Wafer 線形成分の k1・k2 に入る
    shotTerms = terms;
    if options.shotTerms == "linear"
        shotTerms = terms(terms.order <= 1, :);
    end
    waferTerms = WAFER_TERMS.(FORMULA_AXES(a));
    descriptions = {describe(waferTerms.k, waferTerms.term), describe(commonTerms.k, commonTerms.term), ...
        describe(shotTerms.k, shotTerms.term)};
    % 成分ごと・Wafer ごとの、係数（係数を求めた単位（Wafer・Shot）× 項）と項の二乗和、単位の名前、点の数、残りの二乗和
    store = struct("coefficients", {cell(numel(waferNames), 3)}, "ss", {cell(numel(waferNames), 3)}, ...
        "units", {cell(numel(waferNames), 3)}, "n", zeros(numel(waferNames), 1), "rest", zeros(numel(waferNames), 1), ...
        "total", zeros(numel(waferNames), 1));
    for w = 1:numel(waferNames)
        rows = find(points.wafer == waferNames(w) & isfinite(points.("residual" + AXIS_NAMES(a))) & ...
            isfinite(points.shotNo));
        remaining = points.("residual" + AXIS_NAMES(a))(rows);
        store.n(w) = numel(rows);
        store.total(w) = sum(remaining .^ 2);
        % 1. Wafer 線形成分
        A = Xc(rows) .^ (waferTerms.xPower.') .* Yc(rows) .^ (waferTerms.yPower.');
        [ss, coefficients, fitted, waferBasis] = sequentialFit(A, remaining, Inf, zeros(numel(rows), 0));
        store = keep(store, w, 1, coefficients.', ss.', waferNames(w));
        components.waferLinear(rows, a) = fitted;
        remaining = remaining - fitted;
        % 2. Shot 共通成分
        A = points.localX(rows) .^ (commonTerms.xPower.') .* points.localY(rows) .^ (commonTerms.yPower.');
        [ss, coefficients, fitted] = sequentialFit(A, remaining, Inf, waferBasis);   % Wafer 線形成分で表せる項は使わない
        store = keep(store, w, 2, coefficients.', ss.', waferNames(w));
        components.common(rows, a) = fitted;
        remaining = remaining - fitted;
        % 3. Shot 成分（Shot ごと）
        [shotNumbers, ~, shotIndex] = unique(points.shotNo(rows));
        [shotCoefficients, shotSs] = deal(nan(numel(shotNumbers), height(shotTerms)));
        fittedShot = zeros(numel(rows), 1);
        for s = 1:numel(shotNumbers)
            members = find(shotIndex == s);
            A = points.localX(rows(members)) .^ (shotTerms.xPower.') .* points.localY(rows(members)) .^ ...
                (shotTerms.yPower.');
            [ss, coefficients, fitted] = sequentialFit(A, remaining(members), numel(members) - 1, zeros(numel(members), 0));
            shotCoefficients(s, :) = coefficients.';
            ss(~isfinite(coefficients)) = NaN;
            shotSs(s, :) = ss.';
            fittedShot(members) = fitted;
        end
        store = keep(store, w, 3, shotCoefficients, shotSs, "Shot " + string(shotNumbers));
        components.shot(rows, a) = fittedShot;
        remaining = remaining - fittedShot;
        components.rest(rows, a) = remaining;
        store.rest(w) = sum(remaining .^ 2);
    end
    for w = 1:numel(waferNames) + 1
        if w <= numel(waferNames)
            label = waferNames(w);
            pick = w;
            units = @(level) store.units{w, level};
        else
            label = ALL_LABEL;
            pick = 1:numel(waferNames);
            units = @(level) allUnitNames(store, level, waferNames);
        end
        total = sum(store.total(pick));
        nPoints = sum(store.n(pick));
        levelSs = zeros(1, 4);
        parts = cell(1, 3);
        for level = 1:3
            coefficients = vertcat(store.coefficients{pick, level});
            ss = vertcat(store.ss{pick, level});
            names = units(level);
            parts{level} = termRows(label, AXIS_NAMES(a), LEVEL_NAMES(level), descriptions{level}, coefficients, ss, ...
                names, nPoints, total, level == 3);
            levelSs(level) = sum(ss, 'all', 'omitnan');
        end
        levelSs(4) = sum(store.rest(pick));
        termParts{w, a} = vertcat(parts{:});
        levelParts{w, a} = table(repmat(label, 4, 1), repmat(AXIS_NAMES(a), 4, 1), LEVEL_NAMES.', ...
            repmat(nPoints, 4, 1), levelSs.', sqrt(levelSs.' / max(nPoints, 1)), shareOf(levelSs.', total), ...
            'VariableNames', ["wafer", "axis", "level", "n", "ss", "rms", "share"]);
    end
end
decomposition.levels = vertcat(levelParts{:});
decomposition.terms = vertcat(termParts{:});
decomposition.components = components;
end

function store = keep(store, w, level, coefficients, ss, units)
store.coefficients{w, level} = coefficients;
store.ss{w, level} = ss;
store.units{w, level} = reshape(string(units), [], 1);
end

function names = allUnitNames(store, level, waferNames)
% 「すべての Wafer」の行の係数を求めた単位の名前（Shot 成分は「Wafer の Shot n」）
parts = cell(numel(waferNames), 1);
for w = 1:numel(waferNames)
    parts{w} = store.units{w, level};
    if level == 3
        parts{w} = waferNames(w) + " の " + parts{w};
    end
end
names = vertcat(parts{:});
end

function description = describe(k, term)
description = struct("k", reshape(k, [], 1), "term", reshape("k" + string(k) + "（" + string(term) + "）", [], 1));
end

function rows = termRows(label, axisName, level, description, coefficients, ss, units, nPoints, total, perShot)
% 1つの成分の項ごとの行：係数は単位（Wafer・Shot）の平均と標準偏差、項の分は単位の合計
nTerms = numel(description.k);
[coefficient, spread] = deal(nan(nTerms, 1));
[nUnits, termSs] = deal(zeros(nTerms, 1));
largest = strings(nTerms, 1);
for t = 1:nTerms
    values = coefficients(isfinite(coefficients(:, t)), t);
    nUnits(t) = numel(values);
    if ~isempty(values)
        coefficient(t) = mean(values);
    end
    if numel(values) >= 2
        spread(t) = std(values);
    end
    termSs(t) = sum(ss(:, t), 'omitnan');
    if perShot && any(isfinite(ss(:, t)))
        [~, best] = max(ss(:, t));
        largest(t) = units(best);
    end
end
rows = table(repmat(string(label), nTerms, 1), repmat(string(axisName), nTerms, 1), repmat(string(level), nTerms, 1), ...
    description.k, description.term, coefficient, spread, nUnits, termSs, sqrt(termSs / max(nPoints, 1)), ...
    shareOf(termSs, total), largest, 'VariableNames', ["wafer", "axis", "level", "k", "term", "coefficient", "spread", ...
    "nUnits", "ss", "rms", "share", "largest"]);
end

function share = shareOf(ss, total)
share = nan(size(ss));
if total > 0
    share = 100 * ss / total;
end
end

function [ss, coefficients, fitted, basis] = sequentialFit(A, values, maxTerms, previous)
% 列を左から順に足す最小二乗（前の列と、前の成分の列 previous（正規直交）で表せる列は使わない。使う列は maxTerms まで）。
% values は前の成分を引いた残り（previous と直交）。ss：列ごとの、足して減った二乗和（使わない列は 0）、coefficients：
% 使った列の係数（使わない列は NaN）、fitted：当てはめた値、basis：前の成分の列と、使った列の正規直交の基底（次の成分に渡す）
RELATIVE_TOLERANCE = 1e-9;   % 前の列で表せる割合がこれより大きい列は使わない（alignest.robustRidgeFit と同じ）
nColumns = size(A, 2);
ss = zeros(nColumns, 1);
coefficients = nan(nColumns, 1);
basis = previous;
nPrevious = size(previous, 2);
used = false(nColumns, 1);
for j = 1:nColumns
    if size(basis, 2) - nPrevious >= maxTerms
        break
    end
    column = A(:, j);
    scale = norm(column);
    remainder = column;
    for pass = 1:2
        remainder = remainder - basis * (basis.' * remainder);
    end
    if scale > 0 && norm(remainder) > sqrt(RELATIVE_TOLERANCE) * scale
        direction = remainder / norm(remainder);
        basis(:, end + 1) = direction; %#ok<AGROW>
        used(j) = true;
        ss(j) = (direction.' * values) ^ 2;
    end
end
added = basis(:, nPrevious + 1:end);
fitted = added * (added.' * values);
if isempty(values)
    fitted = zeros(0, 1);
end
if any(used)
    % fitted は前の成分の列と使った列で表せる（前の成分の列の分を除いて、使った列の係数にする）
    solution = [previous, A(:, used)] \ fitted;
    coefficients(used) = solution(nPrevious + 1:end);
end
end
