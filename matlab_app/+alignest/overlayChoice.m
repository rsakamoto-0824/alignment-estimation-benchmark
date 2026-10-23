function choice = overlayChoice(settings)
%OVERLAYCHOICE Overlay 補正の評価に使う補正モデル（settings.overlay）を確かめ、説明の文を付けて返す。
%   choice.waferOrder：Wafer 成分（Shot 中心の座標の多項式の次数。0 = なし、1 = 並進・倍率・回転・直交度）
%   choice.waferUseFormula：true なら Wafer 成分に入力した式（settings.overlay.waferFormula の dx・dy）を使う
%   choice.waferTerms：Wafer 成分の式の項（alignest.parseCorrectionFormula。式を使わないときは空）
%   choice.shotCommon：Shot 共通成分（全 Shot に共通の Shot 内の補正。none・linear（k1〜k6）・asml・canon・nikon・
%                      formula（入力した式 settings.overlay.shotFormula））
%   choice.shotTerms ：Shot 共通成分の式の項（formula のとき）
%   choice.perShot   ：Shot ごとの成分（Shot ごとの補正。none・translation（k1・k2）・linear（k1〜k6）・
%                      formula（入力した式 settings.overlay.perShotFormula。係数は Shot ごとに求める））
%   choice.perShotTerms：Shot ごとの成分の式の項（formula のとき）
%   choice.enabled   ：どれかの成分を使うとき true（すべて「なし」なら補正の評価をしない）
%   以前の設定（overlay が無い）は、評価しない（すべて「なし」）として扱う。
MAX_WAFER_ORDER = 5;
choice = struct("waferOrder", 0, "waferUseFormula", false, "waferTerms", [], "shotCommon", "none", "shotTerms", [], ...
    "perShot", "none", "perShotTerms", [], "enabled", false, "description", "");
waferFormula = struct("dx", "", "dy", "");
shotFormula = struct("dx", "", "dy", "");
perShotFormula = struct("dx", "", "dy", "");
if isfield(settings, "overlay")
    overlay = settings.overlay;
    if isfield(overlay, "waferUseFormula")
        choice.waferUseFormula = logical(overlay.waferUseFormula);
    end
    if isfield(overlay, "waferFormula")
        waferFormula = overlay.waferFormula;
    end
    if isfield(overlay, "shotFormula")
        shotFormula = overlay.shotFormula;
    end
    if isfield(overlay, "perShotFormula")
        perShotFormula = overlay.perShotFormula;
    end
    if isfield(overlay, "waferOrder")
        choice.waferOrder = double(overlay.waferOrder);
    end
    if isfield(overlay, "shotCommon")
        choice.shotCommon = string(overlay.shotCommon);
    end
    if isfield(overlay, "perShot")
        choice.perShot = string(overlay.perShot);
    end
end
if ~isscalar(choice.waferOrder) || ~any(choice.waferOrder == 0:MAX_WAFER_ORDER)
    error('alignest:overlayModel', 'Wafer 成分の次数は 0〜%d の整数にしてください。', MAX_WAFER_ORDER);
end
commonNames = ["none", "linear", "asml", "canon", "nikon", "formula"];
commonLabels = ["なし", "1次（k1〜k6）", "ASML の高次式", "Canon の高次式", "Nikon の高次式", "入力した式"];
perShotNames = ["none", "translation", "linear", "formula"];
perShotLabels = ["なし", "並進（k1・k2）", "1次（k1〜k6）", "入力した式"];
if ~any(choice.shotCommon == commonNames)
    error('alignest:overlayModel', 'Shot 共通成分は %s のいずれかです: %s', strjoin(commonNames, "・"), choice.shotCommon);
end
if ~any(choice.perShot == perShotNames)
    error('alignest:overlayModel', 'Shot ごとの成分は %s のいずれかです: %s', strjoin(perShotNames, "・"), choice.perShot);
end
if choice.waferUseFormula
    choice.waferTerms = formulaTerms(waferFormula, "Wafer 成分");
end
if choice.shotCommon == "formula"
    choice.shotTerms = formulaTerms(shotFormula, "Shot 共通成分");
end
if choice.perShot == "formula"
    choice.perShotTerms = formulaTerms(perShotFormula, "Shot ごとの成分");
end
choice.enabled = choice.waferOrder > 0 || choice.waferUseFormula || choice.shotCommon ~= "none" || choice.perShot ~= "none";
waferText = "なし";
if choice.waferUseFormula
    waferText = formulaText(waferFormula);
elseif choice.waferOrder == 1
    waferText = "1次（並進・倍率・回転・直交度）";
elseif choice.waferOrder > 1
    waferText = sprintf("%d次の多項式", choice.waferOrder);
end
commonText = commonLabels(commonNames == choice.shotCommon);
if choice.shotCommon == "formula"
    commonText = formulaText(shotFormula);
end
perShotText = perShotLabels(perShotNames == choice.perShot);
if choice.perShot == "formula"
    perShotText = formulaText(perShotFormula);
end
choice.description = "Wafer 成分 " + waferText + "、Shot 共通成分 " + commonText + "、Shot ごとの成分 " + perShotText;
end

function terms = formulaTerms(formula, componentName)
% dx・dy の式を読む（X 成分は dx の式、Y 成分は dy の式。alignest.overlayTerms と同じ形）
if ~isfield(formula, "dx") || ~isfield(formula, "dy")
    error('alignest:overlayFormula', '%sの式（dx・dy）がありません。', componentName);
end
terms.dx = alignest.parseCorrectionFormula(formula.dx, componentName + "の dx");
terms.dy = alignest.parseCorrectionFormula(formula.dy, componentName + "の dy");
end

function text = formulaText(formula)
text = "入力した式（dx = " + strtrim(string(formula.dx)) + "、dy = " + strtrim(string(formula.dy)) + "）";
end
