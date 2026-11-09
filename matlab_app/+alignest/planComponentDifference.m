function difference = planComponentDifference(unit, plan, settings)
%PLANCOMPONENTDIFFERENCE 計測配置（学習パターン）の点だけで求めた補正の成分が、全計測で求めた成分とどれだけ違うか。
%   difference = alignest.planComponentDifference(unit, plan, settings)
%   unit：評価の単位（Wafer）、plan：学習パターン（alignest.planTrainingShots の結果）、settings：設定。
%   補正モデルは「2. 評価の設定」の Overlay 補正の Wafer 成分と Shot 共通成分（alignest.overlayChoice・
%   alignest.overlayDesign）。Shot ごとの成分は使わない（計測配置の点が Shot に数点だと決まらず、Wafer 成分の分まで
%   吸い込むため）。X・Y 別に最小二乗で、全計測（その軸が有効なすべての Mark）と、計測配置の点（alignest.trainingMarks の
%   Mark のうち有効な Mark）で当てはめる。成分どうしで重なる項（Wafer 成分の定数と Shot 共通成分の k1 など）と、点の
%   配置で決まらない項は、前の項（Wafer → Shot 共通、各成分の中は式の順）に含めて 0 にする（alignest.targetOverlayCorrection
%   と同じ。alignest.independentColumns）。
%   成分：Wafer 線形（Wafer 成分の定数と1次の項）・Wafer 高次（2次以上）・Shot 共通 低次（定数と1次の項。k1〜k6）・
%   Shot 共通 高次（2次以上）と、合計（Wafer 成分 + Shot 共通成分）。
%   difference.summary：成分ごとの表（component・sizeX・sizeY：全計測で求めた成分の補正量の |平均|+3σ [nm]、
%   differenceX・differenceY：計測配置の点で求めた成分の補正量 − 全計測で求めた成分の補正量 の |平均|+3σ [nm]、
%   maxX・maxY：その差の絶対値の最大 [nm]）。補正量はどちらも全計測の Mark の位置で求める。成分の項が無ければ NaN
%   difference.coefficients：項ごとの表（axis・component（成分の名前）・term・full・plan・difference・unit・note）。
%   係数は mm の座標での値（nm/mm^べき。Wafer 成分は Shot 中心の座標、Shot 共通成分は Shot 内の座標）
%   difference.nPoints：当てはめた点の数（[全計測 X, Y; 計測配置 X, Y]）、difference.description：補正モデルの説明、
%   difference.messages：知らせ（成分が無い・決まらない項）
arguments
    unit struct
    plan struct
    settings struct
end
RELATIVE_TOLERANCE = 1e-9;   % 前の項で表せる割合がこれより大きい列は 0 にする（alignest.targetOverlayCorrection と同じ）
LEVEL_NAMES = ["Wafer 線形", "Wafer 高次", "Shot 共通 低次", "Shot 共通 高次", "合計"];
HIGH_ORDER = 2;   % これ以上の次数を高次とする
AXIS_NAMES = ["X", "Y"];
COMPONENT_LABELS = struct("wafer", "Wafer 成分", "shotCommon", "Shot 共通成分");
choice = alignest.overlayChoice(settings);
choice.perShot = "none";
hasWafer = choice.waferUseFormula || choice.waferOrder > 0;
hasCommon = choice.shotCommon ~= "none";
nLevels = numel(LEVEL_NAMES);
[sizes, differences, maxima] = deal(nan(nLevels, 2));
coefficientParts = cell(2, 1);
nPoints = zeros(2, 2);
messages = strings(0, 1);
description = "Wafer 成分：" + waferText(choice) + "、Shot 共通成分：" + commonText(choice) + "（Shot ごとの成分は使わない）";
if ~hasWafer && ~hasCommon
    messages(end + 1, 1) = "「2. 評価の設定」の Overlay 補正に Wafer 成分・Shot 共通成分が無いので、成分の差は出しません。";
else
    marks = unit.marks;
    used = alignest.trainingMarks(unit, plan) & plan.ok;
    undetermined = strings(1, 0);
    for a = 1:2
        valid = marks.("valid" + AXIS_NAMES(a));
        values = marks.("meas" + AXIS_NAMES(a));
        fullIndex = find(valid);
        planIndex = find(valid & used);
        nPoints(:, a) = [numel(fullIndex); numel(planIndex)];
        [design, terms] = alignest.overlayDesign(marks, choice, settings.data.waferRadiusMm, a, fullIndex);
        [fullCoefficients, fullKeep] = orderedFit(design, values(fullIndex), RELATIVE_TOLERANCE);
        planDesign = alignest.overlayDesign(marks, choice, settings.data.waferRadiusMm, a, planIndex);
        [planCoefficients, planKeep] = orderedFit(planDesign, values(planIndex), RELATIVE_TOLERANCE);
        power = terms.xPower + terms.yPower;
        level = 1 + double(power >= HIGH_ORDER) + 2 * double(terms.component == "shotCommon");
        for L = 1:nLevels
            columns = level == L | L == nLevels;
            if ~any(columns)
                continue
            end
            fullPart = design(:, columns) * fullCoefficients(columns);
            planPart = design(:, columns) * planCoefficients(columns);
            sizes(L, a) = meanPlus3Sigma(fullPart);
            differences(L, a) = meanPlus3Sigma(planPart - fullPart);
            if ~isempty(fullPart)
                maxima(L, a) = max(abs(planPart - fullPart));
            end
        end
        scale = terms.scaleMm .^ power;   % 座標を割った値のべきで割って、mm の座標での係数に直す
        note = strings(height(terms), 1);
        note(~fullKeep & planKeep) = "全計測では前の項と重なる・決まらないため 0";
        note(fullKeep & ~planKeep) = "計測配置の点では前の項と重なる・決まらないため 0";
        note(~fullKeep & ~planKeep) = "前の項と重なる・決まらないため 0";
        undetermined = [undetermined, reshape(AXIS_NAMES(a) + "：" + terms.name(fullKeep & ~planKeep), 1, [])]; %#ok<AGROW>
        componentNames = strings(height(terms), 1);
        for name = ["wafer", "shotCommon"]
            componentNames(terms.component == name) = COMPONENT_LABELS.(name);
        end
        coefficientParts{a} = table(repmat(AXIS_NAMES(a), height(terms), 1), reshape(LEVEL_NAMES(level), [], 1), ...
            componentNames, terms.name, fullCoefficients ./ scale, planCoefficients ./ scale, ...
            (planCoefficients - fullCoefficients) ./ scale, unitText(power), note, 'VariableNames', ["axis", "level", ...
            "component", "term", "full", "plan", "difference", "unit", "note"]);
    end
    if ~isempty(undetermined)
        messages(end + 1, 1) = "計測配置の点では決まらない項（0 にした）：" + strjoin(undetermined, "・") + "。";
    end
end
difference.summary = table(reshape(LEVEL_NAMES, [], 1), sizes(:, 1), sizes(:, 2), differences(:, 1), differences(:, 2), ...
    maxima(:, 1), maxima(:, 2), 'VariableNames', ["component", "sizeX", "sizeY", "differenceX", "differenceY", "maxX", "maxY"]);
difference.coefficients = vertcat(coefficientParts{:});
if isempty(difference.coefficients)
    difference.coefficients = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
        zeros(0, 1), strings(0, 1), strings(0, 1), 'VariableNames', ["axis", "level", "component", "term", "full", "plan", ...
        "difference", "unit", "note"]);
end
difference.nPoints = nPoints;
difference.description = description;
difference.messages = messages;
end

function [coefficients, keep] = orderedFit(design, values, tolerance)
% 前の列で表せる列を 0 にして、残りの列で最小二乗（列が無い・点が無ければすべて 0）
coefficients = zeros(size(design, 2), 1);
keep = false(1, size(design, 2));
if isempty(design) || isempty(values)
    return
end
keep = alignest.independentColumns(design, tolerance);
coefficients(keep) = design(:, keep) \ values;
end

function text = waferText(choice)
if choice.waferUseFormula
    text = "入力した式";
elseif choice.waferOrder > 0
    text = sprintf("%d次の多項式", choice.waferOrder);
else
    text = "なし";
end
end

function text = commonText(choice)
names = struct("none", "なし", "linear", "1次（k1〜k6）", "asml", "ASML の式", "canon", "Canon の式", "nikon", "Nikon の式", ...
    "formula", "入力した式");
text = string(names.(choice.shotCommon));
end

function text = unitText(power)
text = "nm/mm^" + string(power);
text(power == 0) = "nm";
text(power == 1) = "nm/mm（ppm）";
end

function value = meanPlus3Sigma(values)
% Overlay の代表値 |平均| + 3σ（σ は不偏標準偏差）。点が2点未満なら NaN（alignest.overlayCorrection と同じ）
values = values(isfinite(values));
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end
