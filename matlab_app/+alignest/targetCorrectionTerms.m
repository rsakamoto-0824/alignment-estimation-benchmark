function terms = targetCorrectionTerms(settings)
%TARGETCORRECTIONTERMS 「5. 未知の座標の推定」の補正のモデルの項の一覧（チェックで使う・使わないを選ぶ表）。
%   terms = alignest.targetCorrectionTerms(settings)
%   terms：項ごとの表。component（"wafer"・"shotCommon"・"perShot"）・componentLabel・axis（"dx"・"dy"）・name（項の名前。
%   k 番号のある式は "k7（x^2）" など）・order（x と y のべきの和）・key（alignest.overlayTermKeys の文字）・
%   required（0次・1次の項。補正の土台なので外さない）・used（使う項。settings.targetCorrection.excludedTerms に無い項）。
%   Shot ごとの成分は、項ごとに1行（どの Shot の係数も同じく使う・使わない）。
COMPONENT_NAMES = ["wafer", "shotCommon", "perShot"];
COMPONENT_LABELS = ["Wafer 成分", "Shot 共通成分", "Shot ごとの成分"];
AXIS_NAMES = ["dx", "dy"];
choice = alignest.targetCorrectionChoice(settings);
excluded = choice.excludedTerms;
choice.excludedTerms = strings(1, 0);   % 一覧にはすべての項を出す
% 項の名前・べきは alignest.overlayDesign と同じにする（1つの Shot・1点の置き場で設計行列の列の説明だけを作る）
marks = struct("Xmm", 0, "Ymm", 0, "markXmm", 0, "markYmm", 0, "shotIndex", 1);
parts = cell(2, 1);
for a = 1:2
    [~, listed] = alignest.overlayDesign(marks, choice, 150, a, 1);
    keys = alignest.overlayTermKeys(listed, a);
    order = listed.xPower + listed.yPower;
    [~, position] = ismember(listed.component, COMPONENT_NAMES);
    parts{a} = table(string(listed.component), reshape(COMPONENT_LABELS(position), [], 1), ...
        repmat(AXIS_NAMES(a), height(listed), 1), string(listed.name), order, keys, order <= 1, ...
        order <= 1 | ~ismember(keys, excluded), 'VariableNames', ["component", "componentLabel", "axis", "name", ...
        "order", "key", "required", "used"]);
end
terms = vertcat(parts{:});
end
