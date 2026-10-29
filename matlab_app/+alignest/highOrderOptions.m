function options = highOrderOptions(settings)
%HIGHORDEROPTIONS Shot 高次補正の評価（「7. Shot高次補正」）の設定 settings.highOrder を確かめ、説明の文を付けて返す。
%   options.maker：補正の式（"asml"・"canon"・"nikon"。Overlay 計測ルールの Shot 高次補正の式。alignest.highOrderTerms）
%   options.unit："common"（Wafer 内の Shot で共通の1組の k）・"shot"（Shot ごとに1組の k）
%   options.waferOrder：Wafer 成分（Shot 中心の座標の多項式。定数を除く 1〜waferOrder 次の項）の次数。0 なら使わない。
%                       Shot で共通のときだけ、Shot の k と一緒に求める（Shot ごとのときは Shot ごとの k1・k2 が Wafer 成分を
%                       含むので使わない）
%   options.excludedTerms：使わない k の番号（「VIF で選ぶ」で外した・画面で外した項。k1〜k6 は外さない）
%   options.vifThreshold：「VIF で選ぶ」のしきい値（すべての項の VIF がこの値より小さくなるまで高次項を外す）
%   options.loss："ols"（最小二乗）・"huber"（Huber の M 推定）・"lad"（最小絶対偏差）。Huber・LAD はロバスト回帰
%   options.huberTuning：Huber の定数 c（残差が c × 尺度 を超える点の重みを下げる）
%   options.l2：true なら高次項（2次以上）だけに L2 正則化をかける。options.lambda：その強さ λ（列をそろえた係数に対して）
%   options.description：画面・Excel に出す説明
%   以前の設定（highOrder が無い・項目が足りない）は、alignest.defaultSettings の値を使う。
MAX_WAFER_ORDER = 3;
MAKER_NAMES = ["asml", "canon", "nikon"];
MAKER_LABELS = ["ASML", "Canon", "Nikon"];
UNIT_NAMES = ["common", "shot"];
UNIT_LABELS = ["Wafer 内の Shot で共通", "Shot ごと"];
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
if ~isscalar(options.maker) || ~any(options.maker == MAKER_NAMES)
    error('alignest:highOrderModel', 'Shot 高次補正の式は %s のいずれかです: %s', strjoin(MAKER_NAMES, "・"), ...
        strjoin(options.maker, "・"));
end
if ~isscalar(options.unit) || ~any(options.unit == UNIT_NAMES)
    error('alignest:highOrderUnit', '補正の単位は common（Wafer 内の Shot で共通）・shot（Shot ごと）のどちらかです: %s', ...
        strjoin(options.unit, "・"));
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
if any(~isfinite(options.excludedTerms) | options.excludedTerms < 1 | options.excludedTerms ~= round(options.excludedTerms))
    error('alignest:highOrderTerms', '使わない項は k の番号（1 以上の整数）で指定してください。');
end
if options.unit == "shot"
    options.waferOrder = 0;   % Shot ごとの k1・k2 が Wafer 成分（Shot 中心の座標の関数）をすべて含む
end
terms = alignest.highOrderTerms(options.maker, options.excludedTerms);
counts = arrayfun(@(axisName) sprintf("%s %d / %d 項", axisName, nnz(terms.used & terms.axis == axisName), ...
    nnz(terms.axis == axisName)), ["dx", "dy"]);
unitText = UNIT_LABELS(UNIT_NAMES == options.unit);
if options.unit == "common" && options.waferOrder > 0
    unitText = unitText + sprintf("（Wafer 成分 %d 次も一緒に求める）", options.waferOrder);
end
lossText = LOSS_LABELS(LOSS_NAMES == options.loss);
if options.loss == "huber"
    lossText = lossText + sprintf("（c = %.4g）", options.huberTuning);
end
l2Text = "L2 正則化なし";
if options.l2 && options.lambda > 0
    l2Text = sprintf("高次項（2次以上）だけに L2 正則化（λ = %.4g）", options.lambda);
end
options.description = MAKER_LABELS(MAKER_NAMES == options.maker) + " の式（" + strjoin(counts, "・") + "）、" + ...
    unitText + "、" + lossText + "、" + l2Text;
end
