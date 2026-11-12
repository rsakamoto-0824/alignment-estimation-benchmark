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
%   options.waferRtRange：Wafer RT（RT モデル。alignest.basis.rtDesign を Shot 中心の座標で当てはめる）を使う Shot。"none"（使わ
%                         ない）・"all"（すべての Shot。Wafer 成分は使わない）・"outer"（外周の Shot だけ。Wafer 成分は内周の Shot
%                         だけ）。X・Y を一緒に、Wafer ごとに先に求めて引き、残りを補正の式で求める
%   options.waferRtOrder：Wafer RT の次数 K（1〜5）
%   options.shotCommon：Shot ごと（unit = "shot"）のとき、先に引く Shot 共通の補正。"none"（引かない。Shot ごとの k をその Shot の
%                       点だけで求める）・"fit"（Wafer 内の Shot で共通の k を Wafer 成分と一緒に求めて引く）・"input"（入力した
%                       k の値 shotCommonValues・shotCommonOuterValues を引く）。引いた残りを Shot ごとに求める。ほかのくくりでは使わない
%   options.shotEachOrder：Shot 共通を先に引くとき、Shot ごとに求める項の次数の上限（0 = 使う項すべて。1〜6。k1〜k6 は必ず求める）
%   options.shotCommonTerms・shotCommonOuterTerms：Shot 共通を「計算する」ときに Shot 共通の k に使う項（k の番号。空なら
%                             使う項と同じ。k1〜k6 は必ず使う。Shot ごとの項は「使う」と shotEachOrder で決まる）
%   options.shotCommonValues：入力した Shot 共通の k（n 番目が kn の値。mm の座標での値で、k1・k2 は nm、1次は nm/mm、n 次は
%                             nm/mm^n。並びより大きい番号の k は 0）。shotCommonOuterValues：外周の式（outerMaker）の k の値
%   options.excludedTerms：使わない k の番号（「VIF で選ぶ」で外した・画面で外した項。k1〜k6 は外さない）
%   options.outerRadiusMm：外周の Shot（Shot 中心の半径がこの値 [mm] 以上）。補正の評価を内周・外周に分けるときと、外周の式に使う
%   options.outerMaker：外周の Shot の補正の式（"none" なら分けない。"asml"・"canon"・"nikon"・"custom"）。分けると、k の組を
%                       内周・外周で別にする（くくりの組ごとに、内周は options.maker、外周は outerMaker の式）
%   options.outerExcludedTerms：外周の式で使わない k の番号、options.outerName：外周の式に選んだ保存した項の組み合わせの名前
%   options.shortage：点が足りない k の組（点の配置で使う項が決まらない Shot・組）の扱い。"reduceAll"（全体の項を減らす：
%                     点の数が最も少ない組に合わせて、すべての組で使う項を k の小さい順に減らす）・"reduceGroup"（その組だけ
%                     項を減らす）・"skip"（その組は補正しない）。どれでも k1〜k6 も決まらない組は補正しない
%   options.vifThreshold：「VIF で選ぶ」のしきい値（すべての項の VIF がこの値より小さくなるまで高次項を外す）
%   回帰の設定は X（dx の式）・Y（dy の式）で別にできる（loss・huberTuning・regularization・lambda は [X, Y] の並び。1つなら
%   X・Y で同じ。結果は 1 × 2 に揃える。正則化をかける次数は penaltyOrders が X、penaltyOrdersY が Y。-1 なら X と同じ）
%   options.loss："ols"（最小二乗）・"huber"（Huber の M 推定）・"lad"（最小絶対偏差）。Huber・LAD はロバスト回帰
%   options.huberTuning：Huber の定数 c（残差が c × 尺度 を超える点の重みを下げる）
%   options.regularization：正則化の種類。"none"（なし）・"l2"（係数の二乗に罰則。係数を小さくする）・"l1"（係数の絶対値に
%                           罰則。効かない項の係数を 0 にする）。以前の設定の l2（true・false）は "l2"・"none" と読む
%   options.penaltyOrders・penaltyOrdersY：正則化をかける項の次数（1〜6 の行ベクトル。定数 k1・k2 と Wafer 成分にはかけない）
%   options.lambda：正則化の強さ λ（列をそろえた係数に対して）
%   options.description：画面・Excel に出す説明
%   以前の設定（highOrder が無い・項目が足りない）は、alignest.defaultSettings の値を使う。
MAX_WAFER_ORDER = 5;
MAX_RT_ORDER = 5;
SHOT_COMMON_NAMES = ["none", "fit", "input"];
MAX_EACH_ORDER = 6;   % Shot ごとに求める項の次数の上限の最大（Nikon の式の6次まで）
RT_RANGE_NAMES = ["none", "all", "outer"];
MAKER_NAMES = ["asml", "canon", "nikon", "custom"];
MAKER_LABELS = ["ASML", "Canon", "Nikon", "カスタム（k1〜k38）"];
UNIT_NAMES = ["common", "scan", "row", "shot"];
UNIT_LABELS = ["Wafer 内の Shot で共通", "Scan 方向ごと", "Shot 行の偶奇ごと", "Shot ごと"];
LOSS_NAMES = ["ols", "huber", "lad"];
LOSS_LABELS = ["最小二乗", "Huber（ロバスト回帰）", "LAD（ロバスト回帰）"];
REGULARIZATION_NAMES = ["none", "l2", "l1"];
SHORTAGE_NAMES = ["reduceAll", "reduceGroup", "skip"];
SHORTAGE_LABELS = ["全体の項を減らす", "その組だけ項を減らす", "その組は補正しない"];
MAX_PENALTY_ORDER = 6;   % 正則化をかけられる次数の上限（Nikon の式の6次まで）
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
if isfield(source, "l2") && isscalar(source.l2)
    % 以前の設定（L2 のオン・オフ）：オフなら正則化なし、オンで種類が無ければ L2
    if ~logical(source.l2)
        options.regularization = "none";
    elseif ~isfield(source, "regularization")
        options.regularization = "l2";
    end
end
options.maker = lower(string(options.maker));
options.unit = string(options.unit);
options.loss = axisPair(lower(string(options.loss)));
options.regularization = axisPair(lower(string(options.regularization)));
options.huberTuning = axisPair(options.huberTuning);
options.lambda = axisPair(options.lambda);
options.penaltyOrders = reshape(double(options.penaltyOrders), 1, []);
if isequal(options.penaltyOrdersY, -1)
    options.penaltyOrdersY = options.penaltyOrders;
end
options.penaltyOrdersY = reshape(double(options.penaltyOrdersY), 1, []);
options.excludedTerms = reshape(double(options.excludedTerms), 1, []);
options.termSets = reshape(string(options.termSets), [], 1);
options.outerMaker = lower(string(options.outerMaker));
options.outerExcludedTerms = reshape(double(options.outerExcludedTerms), 1, []);
options.outerName = string(options.outerName);
options.shortage = string(options.shortage);
options.waferRtRange = string(options.waferRtRange);
options.shotCommon = lower(string(options.shotCommon));
options.shotCommonValues = reshape(double(options.shotCommonValues), 1, []);
options.shotCommonOuterValues = reshape(double(options.shotCommonOuterValues), 1, []);
options.shotCommonTerms = reshape(double(options.shotCommonTerms), 1, []);
options.shotCommonOuterTerms = reshape(double(options.shotCommonOuterTerms), 1, []);
if ~isscalar(options.maker) || ~any(options.maker == MAKER_NAMES)
    error('alignest:highOrderModel', 'Shot 高次補正の式は %s のいずれかです: %s', strjoin(MAKER_NAMES, "・"), ...
        strjoin(options.maker, "・"));
end
if ~isscalar(options.unit) || ~any(options.unit == UNIT_NAMES)
    error('alignest:highOrderUnit', ['補正のくくりは common（Wafer 内の Shot で共通）・scan（Scan 方向ごと）・' ...
        'row（Shot 行の偶奇ごと）・shot（Shot ごと）のいずれかです: %s'], strjoin(options.unit, "・"));
end
if ~isscalar(options.shortage) || ~any(options.shortage == SHORTAGE_NAMES)
    error('alignest:highOrderShortage', ['点が足りない組の扱いは reduceAll（全体の項を減らす）・reduceGroup（その組だけ' ...
        '項を減らす）・skip（その組は補正しない）のいずれかです: %s'], strjoin(options.shortage, "・"));
end
if ~isscalar(options.waferOrder) || ~any(options.waferOrder == 0:MAX_WAFER_ORDER)
    error('alignest:highOrderWafer', 'Wafer 成分の次数は 0〜%d の整数にしてください。', MAX_WAFER_ORDER);
end
if ~isscalar(options.waferRtRange) || ~any(options.waferRtRange == RT_RANGE_NAMES)
    error('alignest:highOrderWafer', 'Wafer RT を使う Shot は none（使わない）・all（すべての Shot）・outer（外周だけ）のいずれかです: %s', ...
        strjoin(options.waferRtRange, "・"));
end
if ~isscalar(options.waferRtOrder) || ~any(options.waferRtOrder == 1:MAX_RT_ORDER)
    error('alignest:highOrderWafer', 'Wafer RT の次数は 1〜%d の整数にしてください。', MAX_RT_ORDER);
end
if ~isscalar(options.shotCommon) || ~any(options.shotCommon == SHOT_COMMON_NAMES)
    error('alignest:highOrderShotCommon', ['先に引く Shot 共通の補正は none（引かない）・fit（計算する）・input（入力した' ...
        '値）のいずれかです: %s'], strjoin(options.shotCommon, "・"));
end
if ~isscalar(options.shotEachOrder) || ~any(options.shotEachOrder == 0:MAX_EACH_ORDER)
    error('alignest:highOrderShotCommon', 'Shot ごとに求める項の次数は 0（使う項すべて）〜%d の整数にしてください。', ...
        MAX_EACH_ORDER);
end
for terms = {options.shotCommonTerms, options.shotCommonOuterTerms}
    if any(~isfinite(terms{1}) | terms{1} < 1 | terms{1} ~= round(terms{1}))
        error('alignest:highOrderShotCommon', 'Shot 共通の k に使う項は k の番号（1 以上の整数）で指定してください。');
    end
end
if any(~isfinite([options.shotCommonValues, options.shotCommonOuterValues]))
    error('alignest:highOrderShotCommon', '入力する Shot 共通の k の値は数にしてください（使わない k は 0）。');
end
if ~isscalar(options.vifThreshold) || ~isfinite(options.vifThreshold) || options.vifThreshold <= 1
    error('alignest:highOrderVif', 'VIF のしきい値は 1 より大きい数にしてください（よく使う値は 5〜10）。');
end
if numel(options.loss) ~= 2 || ~all(ismember(options.loss, LOSS_NAMES))
    error('alignest:highOrderLoss', '回帰の損失関数は %s のいずれかです: %s', strjoin(LOSS_NAMES, "・"), ...
        strjoin(options.loss, "・"));
end
if ~isnumeric(options.huberTuning) || numel(options.huberTuning) ~= 2 || any(~isfinite(options.huberTuning) | options.huberTuning <= 0)
    error('alignest:highOrderHuber', 'Huber の定数 c は正の数にしてください（初期値は 3。1.345 で正規分布の誤差のとき効率 95%%）。');
end
if ~isnumeric(options.lambda) || numel(options.lambda) ~= 2 || any(~isfinite(options.lambda) | options.lambda < 0)
    error('alignest:highOrderLambda', '正則化の強さ λ は 0 以上の数にしてください。');
end
if numel(options.regularization) ~= 2 || ~all(ismember(options.regularization, REGULARIZATION_NAMES))
    error('alignest:highOrderRegularization', '正則化は none（なし）・l2・l1 のいずれかです: %s', ...
        strjoin(options.regularization, "・"));
end
orderFields = ["penaltyOrders", "penaltyOrdersY"];
for a = 1:2
    orders = options.(orderFields(a));
    if any(~isfinite(orders) | orders ~= round(orders) | orders < 1 | orders > MAX_PENALTY_ORDER)
        error('alignest:highOrderPenaltyOrders', '正則化をかける次数は 1〜%d の整数にしてください。', MAX_PENALTY_ORDER);
    end
    options.(orderFields(a)) = unique(orders);
    if options.regularization(a) ~= "none" && isempty(orders)
        error('alignest:highOrderPenaltyOrders', '正則化をかける次数を1つ以上選んでください（かけないときは正則化を「なし」に）。');
    end
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
waferOrder = options.waferOrder * (options.waferRtRange ~= "all");   % すべての Shot が RT なら Wafer 成分は使わない
if options.unit == "common" && waferOrder > 0
    unitText = unitText + sprintf("（Wafer 成分 %d 次も一緒に求める）", waferOrder);
elseif options.unit == "shot" && waferOrder > 0
    unitText = unitText + sprintf("（Wafer 成分 %d 次を先に求めて引く）", waferOrder);
elseif waferOrder > 0
    unitText = unitText + sprintf("（Wafer 成分 %d 次は Wafer で共通にして一緒に求める）", waferOrder);
end
if options.unit == "shot" && options.shotCommon ~= "none"
    sourceText = "求めた";
    if options.shotCommon == "input"
        sourceText = "入力した";
    end
    eachText = "";
    if options.shotEachOrder > 0
        eachText = sprintf("%d次までの項を", options.shotEachOrder);
    end
    unitText = unitText + "、" + sourceText + " Shot 共通の k を先に引いて残りの" + eachText + " Shot ごとに求める";
end
if options.waferRtRange == "all"
    unitText = unitText + sprintf("、すべての Shot は Wafer RT %d 次を先に求めて引く", options.waferRtOrder);
elseif options.waferRtRange == "outer"
    unitText = unitText + sprintf("、外周（Shot 中心の半径 %g mm 以上）は Wafer RT %d 次を先に求めて引く（Wafer 成分は内周だけ）", ...
        options.outerRadiusMm, options.waferRtOrder);
end
regressionText = strings(1, 2);
for a = 1:2
    lossText = LOSS_LABELS(LOSS_NAMES == options.loss(a));
    if options.loss(a) == "huber"
        lossText = lossText + sprintf("（c = %.4g）", options.huberTuning(a));
    end
    l2Text = "正則化なし";
    if options.regularization(a) ~= "none" && options.lambda(a) > 0
        l2Text = sprintf("%s 正則化（%sの項、λ = %.4g）", upper(options.regularization(a)), ...
            orderText(options.(orderFields(a))), options.lambda(a));
    end
    regressionText(a) = lossText + "、" + l2Text;
end
if regressionText(1) == regressionText(2)
    regressionText = regressionText(1);
else
    regressionText = "X は " + regressionText(1) + "、Y は " + regressionText(2);
end
options.description = formulaText + "、" + unitText + "、" + regressionText;
if options.shortage ~= "reduceAll"
    % 初期の扱い（全体の項を減らす）は、以前の説明と同じにするため書かない
    options.description = options.description + "、点が足りない組：" + SHORTAGE_LABELS(SHORTAGE_NAMES == options.shortage);
end
end

function values = axisPair(values)
% 回帰の設定を [X, Y] の並びにする（1つなら X・Y で同じ）
values = reshape(values, 1, []);
if isscalar(values)
    values = [values, values];
end
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

function text = orderText(orders)
% 次数の並びの説明（例：[2 3 4 5 6] → "2〜6次"、[1 3] → "1・3次"）
if numel(orders) >= 2 && all(diff(orders) == 1)
    text = sprintf("%d〜%d次", orders(1), orders(end));
else
    text = strjoin(string(orders), "・") + "次";
end
end
