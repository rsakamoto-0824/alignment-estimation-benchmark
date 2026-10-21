function choice = overlayChoice(settings)
%OVERLAYCHOICE Overlay 補正の評価に使う補正モデル（settings.overlay）を確かめ、説明の文を付けて返す。
%   choice.waferOrder：Wafer 成分（Shot 中心の座標の多項式の次数。0 = なし、1 = 並進・倍率・回転・直交度）
%   choice.shotCommon：Shot 共通成分（全 Shot に共通の Shot 内の補正。none・linear（k1〜k6）・asml・canon・nikon）
%   choice.perShot   ：Shot ごとの成分（Shot ごとの補正。none・translation（k1・k2）・linear（k1〜k6））
%   choice.enabled   ：どれかの成分を使うとき true（すべて「なし」なら補正の評価をしない）
%   以前の設定（overlay が無い）は、評価しない（すべて「なし」）として扱う。
MAX_WAFER_ORDER = 5;
choice = struct("waferOrder", 0, "shotCommon", "none", "perShot", "none", "enabled", false, "description", "");
if isfield(settings, "overlay")
    overlay = settings.overlay;
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
commonNames = ["none", "linear", "asml", "canon", "nikon"];
commonLabels = ["なし", "1次（k1〜k6）", "ASML の高次式", "Canon の高次式", "Nikon の高次式"];
perShotNames = ["none", "translation", "linear"];
perShotLabels = ["なし", "並進（k1・k2）", "1次（k1〜k6）"];
if ~any(choice.shotCommon == commonNames)
    error('alignest:overlayModel', 'Shot 共通成分は %s のいずれかです: %s', strjoin(commonNames, "・"), choice.shotCommon);
end
if ~any(choice.perShot == perShotNames)
    error('alignest:overlayModel', 'Shot ごとの成分は %s のいずれかです: %s', strjoin(perShotNames, "・"), choice.perShot);
end
choice.enabled = choice.waferOrder > 0 || choice.shotCommon ~= "none" || choice.perShot ~= "none";
waferText = "なし";
if choice.waferOrder == 1
    waferText = "1次（並進・倍率・回転・直交度）";
elseif choice.waferOrder > 1
    waferText = sprintf("%d次の多項式", choice.waferOrder);
end
choice.description = "Wafer 成分 " + waferText + "、Shot 共通成分 " + commonLabels(commonNames == choice.shotCommon) + ...
    "、Shot ごとの成分 " + perShotLabels(perShotNames == choice.perShot);
end
