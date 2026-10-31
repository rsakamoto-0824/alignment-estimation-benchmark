function options = highOrderOptions(settings)
%HIGHORDEROPTIONS Shot 高次補正の評価（「7. Shot高次補正」）の設定 settings.highOrder を確かめ、説明の文を付けて返す。
%   options.maker：補正の式（"asml"・"canon"・"nikon"（Shot 高次補正の式）・"custom"（k1〜k38 から選ぶ）。alignest.highOrderTerms）
%   options.termSets：保存した項の組み合わせ（1行 = "名前|式|k の番号 …"。画面の「組み合わせを保存」）
%   options.unit：k の組のくくり。"common"（Wafer 内の Shot で共通の1組の k）・"scan"（Scan 方向ごとに1組ずつ）・
%                 "row"（Shot 行の偶奇ごとに1組ずつ）・"shot"（Shot ごとに1組の k）
%   options.waferOrder：Wafer 成分（Shot 中心の座標の多項式。定数を除く 1〜waferOrder 次の項。最大5次）の次数。0 なら
%                       使わない。Shot ごとのほかは、Wafer で共通の1組として Shot の k と一緒に求める。Shot ごとのときは、
%                       Shot ごとの k1・k2 が Wafer 成分を含むので、先に（Wafer 内で共通の k と一緒に）求めて引き、残りを
%                       Shot ごとに求める（補正量・残差は Wafer 成分なしと同じで、Shot ごとの k1・k2 が Wafer 成分を除いた値になる）
%   options.excludedTerms：使わない k の番号（「VIF で選ぶ」で外した・画面で外した項。k1〜k6 は外さない）
%   options.outerRadiusMm：外周の Shot（Shot 中心の半径がこの値 [mm] 以上）。補正の評価を内周・外周に分けるときと、外周の式に使う
%   options.outerMaker：外周の Shot の補正の式（"none" なら分けない。"asml"・"canon"・"nikon"・"custom"）。分けると、k の組を
%                       内周・外周で別にする（くくりの組ごとに、内周は options.maker、外周は outerMaker の式）
%   options.outerExcludedTerms：外周の式で使わない k の番号、options.outerName：外周の式に選んだ保存した項の組み合わせの名前
%   options.vifThreshold：「VIF で選ぶ」のしきい値（すべての項の VIF がこの値より小さくなるまで高次項を外す）
%   options.loss："ols"（最小二乗）・"huber"（Huber の M 推定）・"lad"（最小絶対偏差）。Huber・LAD はロバスト回帰
%   options.huberTuning：Huber の定数 c（残差が c × 尺度 を超える点の重みを下げる）
%   options.l2：true なら高次項（2次以上）だけに L2 正則化をかける。options.lambda：その強さ λ（列をそろえた係数に対して）
%   options.description：画面・Excel に出す説明
%   以前の設定（highOrder が無い・項目が足りない）は、alignest.defaultSettings の値を使う。
MAX_WAFER_ORDER = 5;
MAKER_NAMES = ["asml", "canon", "nikon", "custom"];
MAKER_LABELS = ["ASML", "Canon", "Nikon", "カスタム（k1〜k38）"];
UNIT_NAMES = ["common", "scan", "row", "shot"];
UNIT_LABELS = ["Wafer 内の Shot で共通", "Scan 方向ごと", "Shot 行の偶奇ごと", "Shot ごと"];
LOSS_NAMES = ["ols", "huber", "lad"];
LOSS_LABELS = ["最小二乗", "Huber（ロバスト回帰）", "LAD（ロバスト回帰）"];
defaults = alignest.defaultSettings().highOrder;
source = struct();
if isfield(settings, "highOrder") && isstruct(settings.highOrder)
    source = settings.highOrder;
end
options = defaults;
for name = string(fieldnames(defaults)).'
    if isfield(source, name)
        options.(name) = source.(name);
    end
end
options.maker = lower(string(options.maker));
options.unit = string(options.unit);
options.loss = lower(string(options.loss));
options.l2 = logical(options.l2);
options.excludedTerms = reshape(double(options.excludedTerms), 1, []);
options.termSets = reshape(string(options.termSets), [], 1);
options.outerMaker = lower(string(options.outerMaker));
options.outerExcludedTerms = reshape(double(options.outerExcludedTerms), 1, []);
options.outerName = string(options.outerName);
if ~isscalar(options.maker) || ~any(options.maker == MAKER_NAMES)
    error('alignest:highOrderModel', 'Shot 高次補正の式は %s のいずれかです: %s', strjoin(MAKER_NAMES, "・"), ...
        strjoin(options.maker, "・"));
end
if ~isscalar(options.unit) || ~any(options.unit == UNIT_NAMES)
    error('alignest:highOrderUnit', ['補正のくくりは common（Wafer 内の Shot で共通）・scan（Scan 方向ごと）・' ...
        'row（Shot 行の偶奇ごと）・shot（Shot ごと）のいずれかです: %s'], strjoin(options.unit, "・"));
end
if ~isscalar(options.waferOrder) || ~any(options.waferOrder == 0:MAX_WAFER_ORDER)
    error('alignest:highOrderWafer', 'Wafer 成分の次数は 0〜%d の整数にしてください。', MAX_WAFER_ORDER);
end
if ~isscalar(options.vifThreshold) || ~isfinite(options.vifThreshold) || options.vifThreshold <= 1
    error('alignest:highOrderVif', 'VIF のしきい値は 1 より大きい数にしてください（よく使う値は 5〜10）。');
end
if ~isscalar(options.loss) || ~any(options.loss == LOSS_NAMES)
    error('alignest:highOrderLoss', '回帰の損失関数は %s のいずれかです: %s', strjoin(LOSS_NAMES, "・"), ...
        strjoin(options.loss, "・"));
end
if ~isscalar(options.huberTuning) || ~isfinite(options.huberTuning) || options.huberTuning <= 0
    error('alignest:highOrderHuber', 'Huber の定数 c は正の数にしてください（よく使う値は 1.345）。');
end
if ~isscalar(options.lambda) || ~isfinite(options.lambda) || options.lambda < 0
    error('alignest:highOrderLambda', 'L2 正則化の強さ λ は 0 以上の数にしてください。');
end
for terms = {options.excludedTerms, options.outerExcludedTerms}
    if any(~isfinite(terms{1}) | terms{1} < 1 | terms{1} ~= round(terms{1}))
        error('alignest:highOrderTerms', '使わない項は k の番号（1 以上の整数）で指定してください。');
    end
end
if ~isscalar(options.outerRadiusMm) || ~isfinite(options.outerRadiusMm) || options.outerRadiusMm <= 0
    error('alignest:highOrderOuter', '外周の Shot の半径は正の数 [mm] にしてください（Shot 中心の半径がこの値以上の Shot を外周にします）。');
end
if ~isscalar(options.outerMaker) || ~any(options.outerMaker == ["none", MAKER_NAMES])
    error('alignest:highOrderModel', '外周の式は none（分けない）・%s のいずれかです: %s', strjoin(MAKER_NAMES, "・"), ...
        strjoin(options.outerMaker, "・"));
end
if ~isscalar(options.outerName)
    error('alignest:highOrderOuter', '外周の式の組み合わせの名前は1つの文字列にしてください。');
end
formulaText = formulaDescription(options.maker, options.excludedTerms, MAKER_NAMES, MAKER_LABELS, "");
if options.outerMaker ~= "none"
    formulaText = formulaText + sprintf("、外周（Shot 中心の半径 %g mm 以上）は ", options.outerRadiusMm) + ...
        formulaDescription(options.outerMaker, options.outerExcludedTerms, MAKER_NAMES, MAKER_LABELS, options.outerName);
end
unitText = UNIT_LABELS(UNIT_NAMES == options.unit);
if options.unit == "common" && options.waferOrder > 0
    unitText = unitText + sprintf("（Wafer 成分 %d 次も一緒に求める）", options.waferOrder);
elseif options.unit == "shot" && options.waferOrder > 0
    unitText = unitText + sprintf("（Wafer 成分 %d 次を先に求めて引く）", options.waferOrder);
elseif options.waferOrder > 0
    unitText = unitText + sprintf("（Wafer 成分 %d 次は Wafer で共通にして一緒に求める）", options.waferOrder);
end
lossText = LOSS_LABELS(LOSS_NAMES == options.loss);
if options.loss == "huber"
    lossText = lossText + sprintf("（c = %.4g）", options.huberTuning);
end
l2Text = "L2 正則化なし";
if options.l2 && options.lambda > 0
    l2Text = sprintf("高次項（2次以上）だけに L2 正則化（λ = %.4g）", options.lambda);
end
options.description = formulaText + "、" + unitText + "、" + lossText + "、" + l2Text;
end

function text = formulaDescription(maker, excludedTerms, makerNames, makerLabels, setName)
% 補正の式の説明（例："Nikon の式（dx 12 / 12 項・dy 15 / 15 項）"。保存した項の組み合わせなら名前も付ける）
terms = alignest.highOrderTerms(maker, excludedTerms);
counts = arrayfun(@(axisName) sprintf("%s %d / %d 項", axisName, nnz(terms.used & terms.axis == axisName), ...
    nnz(terms.axis == axisName)), ["dx", "dy"]);
text = makerLabels(makerNames == maker) + " の式（" + strjoin(counts, "・") + "）";
if setName ~= ""
    text = "「" + setName + "」（" + text + "）";
end
end
