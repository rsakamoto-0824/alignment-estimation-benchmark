function choice = targetCorrectionChoice(settings)
%TARGETCORRECTIONCHOICE 「5. 未知の座標の推定」の補正のモデル（settings.targetCorrection）を確かめ、alignest.overlayDesign の
%   choice の形（alignest.overlayChoice と同じ項目）にして返す。
%   choice = alignest.targetCorrectionChoice(settings)
%   settings.targetCorrection：
%     waferOrder   ：Wafer 成分（Shot 中心の座標の多項式の次数。0 = なし、1〜5）
%     shotCommon   ：Shot 共通成分（全 Shot で同じ係数の Shot 内の補正式）："none"・"linear"（1次 k1〜k6）・"quadratic"
%                    （2次 k1〜k12）・"asml"・"canon"・"nikon"（Shot 高次補正の式）・"custom"（カスタム k1〜k38）
%     perShot      ：Shot ごとの成分："none"・"translation"（並進 k1・k2）・"linear"（1次 k1〜k6）
%     excludedTerms：使わない項（alignest.overlayTermKeys の文字："成分|dx|x のべき,y のべき"）。0次・1次の項は外さない
%   未知の座標の推定値を足すと Shot 内の点が増えるので、「2. 面内推定の設定」の Overlay 補正（基準の補正）より高次の式で
%   補正できる。設定が無い（以前の設定）・読めない値は初期値（alignest.defaultSettings）を使う。
SHOT_COMMON = ["none", "linear", "quadratic", "asml", "canon", "nikon", "custom"];
SHOT_COMMON_LABELS = ["なし", "1次", "2次", "ASML", "Canon", "Nikon", "カスタム"];
PER_SHOT = ["none", "translation", "linear"];
PER_SHOT_LABELS = ["なし", "並進", "1次"];
MAX_WAFER_ORDER = 5;
defaults = alignest.defaultSettings().targetCorrection;
source = defaults;
if isfield(settings, "targetCorrection") && isstruct(settings.targetCorrection)
    for name = string(fieldnames(defaults)).'
        if isfield(settings.targetCorrection, name)
            source.(name) = settings.targetCorrection.(name);
        end
    end
end
waferOrder = double(source.waferOrder);
if ~(isscalar(waferOrder) && any(waferOrder == 0:MAX_WAFER_ORDER))
    error('alignest:targetCorrection', 'Wafer 成分の次数は 0〜%d の整数にしてください。', MAX_WAFER_ORDER);
end
shotCommon = lower(string(source.shotCommon));
if ~(isscalar(shotCommon) && any(shotCommon == SHOT_COMMON))
    error('alignest:targetCorrection', 'Shot 共通成分は %s のいずれかです: %s', strjoin(SHOT_COMMON, "・"), ...
        strjoin(shotCommon, "・"));
end
perShot = lower(string(source.perShot));
if ~(isscalar(perShot) && any(perShot == PER_SHOT))
    error('alignest:targetCorrection', 'Shot ごとの成分は %s のいずれかです: %s', strjoin(PER_SHOT, "・"), ...
        strjoin(perShot, "・"));
end
choice.waferOrder = waferOrder;
choice.waferUseFormula = false;
choice.waferTerms = [];
choice.shotCommon = shotCommon;
choice.shotTerms = [];
choice.perShot = perShot;
choice.perShotTerms = [];
choice.excludedTerms = reshape(string(source.excludedTerms), 1, []);
choice.enabled = waferOrder > 0 || shotCommon ~= "none" || perShot ~= "none";
choice.modelName = "「5. 未知の座標の推定」の補正のモデル";
parts = strings(1, 0);
if waferOrder > 0
    parts(end + 1) = sprintf("Wafer 成分 %d次", waferOrder);
end
if shotCommon ~= "none"
    parts(end + 1) = "Shot 共通成分 " + SHOT_COMMON_LABELS(SHOT_COMMON == shotCommon);
end
if perShot ~= "none"
    parts(end + 1) = "Shot ごとの成分 " + PER_SHOT_LABELS(PER_SHOT == perShot);
end
if isempty(parts)
    choice.description = "補正なし";
else
    choice.description = strjoin(parts, " ＋ ");
end
if ~isempty(choice.excludedTerms)
    choice.description = choice.description + sprintf("（外した項 %d）", numel(choice.excludedTerms));
end
end
