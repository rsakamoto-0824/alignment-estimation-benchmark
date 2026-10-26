function [design, terms] = overlayDesign(marks, choice, waferRadiusMm, axisIndex, index)
%OVERLAYDESIGN 補正モデル（Wafer 成分 + Shot 共通成分 + Shot ごとの成分）の設計行列と、列ごとの項の説明。
%   [design, terms] = alignest.overlayDesign(marks, choice, waferRadiusMm, axisIndex, index)
%   marks：Xmm・Ymm（Shot 中心の座標）・markXmm・markYmm（Shot 内の座標）・shotIndex（Shot の番号）を持つ構造体。
%   choice：alignest.overlayChoice。axisIndex：1 = X（dx の式）、2 = Y（dy の式）。index：使う Mark の番号。
%   - Wafer 成分     ：Shot 中心の座標（Xmm・Ymm を Wafer 半径で割った値）の多項式（次数 choice.waferOrder）、
%                      または入力した式（choice.waferTerms）
%   - Shot 共通成分  ：Shot 内の座標（markXmm・markYmm を LOCAL_SCALE_MM で割った値）の補正式
%                      （alignest.overlayTerms、または入力した式 choice.shotTerms）。全 Shot で同じ係数
%   - Shot ごとの成分：Shot ごとに並進（k1・k2）・1次（k1〜k6）、または入力した式（choice.perShotTerms）の係数
%   座標を割る値は、べき乗の桁をそろえるためだけで、当てはめた補正量は変わらない（係数を mm の単位に直すときは
%   terms.scaleMm を使う）。alignest.overlayProjector・alignest.targetOverlayCorrection が使う。
%   terms は列ごとの表：component（"wafer"・"shotCommon"・"perShot"）・shot（Shot ごとの成分の Shot の番号。ほかは NaN）・
%   name（項の名前。k 番号のある式は "k1"・"k3（x）" など、無い式は "定数"・"x^2·y" など）・xPower・yPower・
%   scaleMm（座標を割った値）。
LOCAL_SCALE_MM = 10;  % Shot 内の座標を割る値（べき乗の桁をそろえるだけで、補正量は変わらない）
index = index(:);
useWaferFormula = isfield(choice, "waferUseFormula") && choice.waferUseFormula;
blocks = {zeros(numel(index), 0)};
termParts = {emptyTerms()};
waferX = marks.Xmm(index) / waferRadiusMm;
waferY = marks.Ymm(index) / waferRadiusMm;
if useWaferFormula
    table_ = pick(choice.waferTerms, axisIndex);
    blocks{end + 1} = powersOf(table_, waferX, waferY);
    termParts{end + 1} = describe("wafer", NaN, table_, false, waferRadiusMm);
elseif choice.waferOrder > 0
    blocks{end + 1} = alignest.basis.polynomialDesign(waferX, waferY, choice.waferOrder);
    termParts{end + 1} = describe("wafer", NaN, polynomialPowers(choice.waferOrder), false, waferRadiusMm);
end
localX = marks.markXmm(index) / LOCAL_SCALE_MM;
localY = marks.markYmm(index) / LOCAL_SCALE_MM;
if choice.shotCommon ~= "none"
    if choice.shotCommon == "formula"
        table_ = pick(choice.shotTerms, axisIndex);
        named = false;
    else
        table_ = pick(alignest.overlayTerms(choice.shotCommon), axisIndex);
        named = true;
    end
    blocks{end + 1} = powersOf(table_, localX, localY);
    termParts{end + 1} = describe("shotCommon", NaN, table_, named, LOCAL_SCALE_MM);
end
if choice.perShot ~= "none"
    named = choice.perShot ~= "formula";
    if named
        table_ = pick(alignest.overlayTerms("linear"), axisIndex);
        if choice.perShot == "translation"
            table_ = table_(1, :);  % k1（X）・k2（Y）だけ
        end
    else
        table_ = pick(choice.perShotTerms, axisIndex);
    end
    local = powersOf(table_, localX, localY);
    shots = marks.shotIndex(index);
    shotIds = unique(shots).';
    indicator = double(shots == shotIds);
    nShots = numel(shotIds);
    perShot = zeros(numel(index), nShots * size(local, 2));
    parts = cell(size(local, 2), 1);
    for term = 1:size(local, 2)
        perShot(:, (term - 1) * nShots + (1:nShots)) = indicator .* local(:, term);
        part = describe("perShot", NaN, table_(term, :), named, LOCAL_SCALE_MM);
        part = repmat(part, nShots, 1);
        part.shot = shotIds(:);
        parts{term} = part;
    end
    blocks{end + 1} = perShot;
    termParts{end + 1} = vertcat(parts{:});
end
design = [blocks{:}];
terms = vertcat(termParts{:});
end

function table_ = pick(terms, axisIndex)
% X は dx の式、Y は dy の式
if axisIndex == 1
    table_ = terms.dx;
else
    table_ = terms.dy;
end
end

function columns = powersOf(table_, x, y)
columns = x .^ (table_(:, 2).') .* y .^ (table_(:, 3).');  % べきと転置は同じ優先順位なので括弧が必要
end

function table_ = polynomialPowers(order)
% alignest.basis.polynomialDesign と同じ列の順（次数順、同じ次数では y のべきが小さい順）
table_ = zeros(0, 3);
for degree = 0:order
    for powerY = 0:degree
        table_(end + 1, :) = [size(table_, 1) + 1, degree - powerY, powerY]; %#ok<AGROW>
    end
end
end

function terms = describe(component, shot, table_, named, scaleMm)
n = size(table_, 1);
names = strings(n, 1);
for k = 1:n
    monomial = monomialName(table_(k, 2), table_(k, 3));
    if named && monomial == "1"
        names(k) = "k" + table_(k, 1);                        % 並進（定数）の項
    elseif named
        names(k) = "k" + table_(k, 1) + "（" + monomial + "）";
    elseif monomial == "1"
        names(k) = "定数";
    else
        names(k) = monomial;
    end
end
terms = table(repmat(string(component), n, 1), repmat(shot, n, 1), names, table_(:, 2), table_(:, 3), ...
    repmat(scaleMm, n, 1), 'VariableNames', ["component", "shot", "name", "xPower", "yPower", "scaleMm"]);
end

function terms = emptyTerms()
terms = table(strings(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    'VariableNames', ["component", "shot", "name", "xPower", "yPower", "scaleMm"]);
end

function name = monomialName(xPower, yPower)
% 項の名前（定数は "1"）
parts = strings(0, 1);
if xPower == 1
    parts(end + 1) = "x";
elseif xPower > 1
    parts(end + 1) = "x^" + xPower;
end
if yPower == 1
    parts(end + 1) = "y";
elseif yPower > 1
    parts(end + 1) = "y^" + yPower;
end
if isempty(parts)
    name = "1";
else
    name = strjoin(parts, "·");
end
end
