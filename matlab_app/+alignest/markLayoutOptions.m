function options = markLayoutOptions(settings)
%MARKLAYOUTOPTIONS 「8. Mark配置の最適化」の設定 settings.markLayout を確かめ、説明の文を付けて返す。
%   options = alignest.markLayoutOptions(settings)
%   項目（alignest.defaultSettings の markLayout）：
%   - maker・excludedTerms・vifThreshold：補正の式・使わない k の番号・「VIF で選ぶ」のしきい値（「7. Shot高次補正」と同じ）
%   - loss・huberTuning・regularization・penaltyOrders・penaltyOrdersY・lambda：回帰（ロバスト回帰と正則化。「7. Shot高次補正」と
%     同じで X・Y 別にできる。[X, Y] の並び。1つなら X・Y で同じ。penaltyOrdersY は -1 なら X と同じ）
%   - minMarks・maxMarks：計測する Mark の数の最低数・最大数（0 = 使う項の数・すべての候補）
%   - starts：Mark の数ごとに I 最適な配置を探す始め方の数（1〜50）
%   - values：制御残差を求める値。"measured"（実測値）・"random"（乱数の Shot の形）
%   - shapes：乱数の Shot の形の数（1〜1000）
%   - seed：乱数の種。markLayout には持たず、学習 Shot の選び方と同じ settings.sampling.seed を使う（メニュー「設定」→
%     「乱数の種…」。無ければ初期値）
%   - orderSigmaNm：乱数の形の 0〜7次の項の大きさ（Shot の端での標準偏差 [nm]。8つ。以前の6つの設定は 6・7次を 0 にする）、
%     noiseNm：計測のばらつき [nm]、
%     outlierPercent：飛び値にする点の割合 [%]、outlierNm：飛び値の大きさ [nm]
%   - coordinateXmm・coordinateYmm：画面で入力する候補の Mark の Shot 内の座標 [mm]
%   - requiredXmm・requiredYmm：必ず計測する Mark の Shot 内の座標 [mm]
%   - excludedXmm・excludedYmm：計測しない Mark の Shot 内の座標 [mm]（残差の評価には使う）
%   options.description：画面・Excel に出す説明。以前の設定（markLayout が無い・項目が足りない）は初期値を使う。
MAKER_NAMES = ["asml", "canon", "nikon", "custom"];
MAKER_LABELS = ["ASML", "Canon", "Nikon", "カスタム（k1〜k38）"];
LOSS_NAMES = ["ols", "huber", "lad"];
LOSS_LABELS = ["最小二乗", "Huber（ロバスト回帰）", "LAD（ロバスト回帰）"];
REGULARIZATION_NAMES = ["none", "l2", "l1"];
VALUE_NAMES = ["measured", "random"];
MAX_PENALTY_ORDER = 6;    % 正則化をかけられる次数の上限（「7. Shot高次補正」と同じ）
MAX_STARTS = 50;          % 配置を探す始め方の数の上限
MAX_SHAPES = 1000;        % 乱数の Shot の形の数の上限
RANDOM_ORDERS = 8;        % 乱数の形の項の次数の数（0〜7次）
OLD_RANDOM_ORDERS = 6;    % 以前の設定の次数の数（0〜5次）
MAX_OUTLIER_PERCENT = 50; % 飛び値にする点の割合の上限 [%]（半分を超えるとロバスト回帰でも見分けられない）
defaults = alignest.defaultSettings().markLayout;
source = struct();
if isfield(settings, "markLayout") && isstruct(settings.markLayout)
    source = settings.markLayout;
end
options = defaults;
for name = string(fieldnames(defaults)).'
    if isfield(source, name)
        options.(name) = source.(name);
    end
end
options.seed = alignest.defaultSettings().sampling.seed;   % 乱数の種は学習 Shot の選び方と共通
if isfield(settings, "sampling") && isstruct(settings.sampling) && isfield(settings.sampling, "seed")
    options.seed = settings.sampling.seed;
end
options.maker = lower(string(options.maker));
options.loss = axisPair(lower(string(options.loss)));
options.regularization = axisPair(lower(string(options.regularization)));
options.huberTuning = axisPair(options.huberTuning);
options.lambda = axisPair(options.lambda);
options.values = string(options.values);
options.excludedTerms = reshape(double(options.excludedTerms), 1, []);
options.penaltyOrders = reshape(double(options.penaltyOrders), 1, []);
if isequal(options.penaltyOrdersY, -1)
    options.penaltyOrdersY = options.penaltyOrders;
end
options.penaltyOrdersY = reshape(double(options.penaltyOrdersY), 1, []);
options.orderSigmaNm = reshape(double(options.orderSigmaNm), 1, []);
if numel(options.orderSigmaNm) == OLD_RANDOM_ORDERS
    options.orderSigmaNm(RANDOM_ORDERS) = 0;
end
for name = ["coordinateXmm", "coordinateYmm", "requiredXmm", "requiredYmm", "excludedXmm", "excludedYmm"]
    options.(name) = reshape(double(options.(name)), [], 1);
end
if ~isscalar(options.maker) || ~any(options.maker == MAKER_NAMES)
    error('alignest:markLayout', '補正の式は %s のいずれかです: %s', strjoin(MAKER_NAMES, "・"), strjoin(options.maker, "・"));
end
if numel(options.loss) ~= 2 || ~all(ismember(options.loss, LOSS_NAMES))
    error('alignest:markLayout', '回帰の損失関数は ols・huber・lad のいずれかです: %s', strjoin(options.loss, "・"));
end
if numel(options.regularization) ~= 2 || ~all(ismember(options.regularization, REGULARIZATION_NAMES))
    error('alignest:markLayout', '正則化は none・l2・l1 のいずれかです: %s', strjoin(options.regularization, "・"));
end
if ~isscalar(options.values) || ~any(options.values == VALUE_NAMES)
    error('alignest:markLayout', ['制御残差を求める値は measured（実測値）・random（乱数の Shot の形）のいずれかです: ' ...
        '%s'], strjoin(options.values, "・"));
end
mustBeScalarIn(options.vifThreshold, 1, Inf, "VIF のしきい値", false);
for a = 1:2
    mustBeScalarIn(options.huberTuning(a), 0, Inf, "Huber の c", false);
    mustBeScalarIn(options.lambda(a), 0, Inf, "正則化の強さ λ", true);
end
if any(~ismember([options.penaltyOrders, options.penaltyOrdersY], 1:MAX_PENALTY_ORDER))
    error('alignest:markLayout', '正則化をかける次数は 1〜%d から選んでください。', MAX_PENALTY_ORDER);
end
mustBeCount(options.minMarks, 0, Inf, "計測する Mark の最低数");
mustBeCount(options.maxMarks, 0, Inf, "計測する Mark の最大数");
if options.maxMarks > 0 && options.minMarks > options.maxMarks
    error('alignest:markLayout', '計測する Mark の最低数（%d）を最大数（%d）以下にしてください。', options.minMarks, ...
        options.maxMarks);
end
mustBeCount(options.starts, 1, MAX_STARTS, "配置を探す始め方の数");
mustBeCount(options.shapes, 1, MAX_SHAPES, "乱数の Shot の形の数");
alignest.checkRandomSeed(options.seed);
if numel(options.orderSigmaNm) ~= RANDOM_ORDERS || any(~isfinite(options.orderSigmaNm) | options.orderSigmaNm < 0)
    error('alignest:markLayout', '乱数の形の項の大きさは、0〜7次の %d つの 0 以上の数 [nm] にしてください。', RANDOM_ORDERS);
end
mustBeScalarIn(options.noiseNm, 0, Inf, "計測のばらつき", true);
mustBeScalarIn(options.outlierPercent, 0, MAX_OUTLIER_PERCENT, "飛び値にする点の割合 [%]", true);
mustBeScalarIn(options.outlierNm, 0, Inf, "飛び値の大きさ", true);
if numel(options.coordinateXmm) ~= numel(options.coordinateYmm) || any(~isfinite([options.coordinateXmm; ...
        options.coordinateYmm]))
    error('alignest:markLayout', '画面で入力する Mark の座標は、X・Y を同じ数だけ数で入れてください。');
end
if numel(options.requiredXmm) ~= numel(options.requiredYmm) || any(~isfinite([options.requiredXmm; options.requiredYmm]))
    error('alignest:markLayout', '必ず計測する Mark の座標は、X・Y を同じ数だけ数で入れてください。');
end
if numel(options.excludedXmm) ~= numel(options.excludedYmm) || any(~isfinite([options.excludedXmm; options.excludedYmm]))
    error('alignest:markLayout', '計測しない Mark の座標は、X・Y を同じ数だけ数で入れてください。');
end
regressionText = strings(1, 2);
for a = 1:2
    orders = options.penaltyOrders;
    if a == 2
        orders = options.penaltyOrdersY;
    end
    regularizationText = "正則化なし";
    if options.regularization(a) ~= "none"
        regularizationText = sprintf("%s 正則化（λ = %g、%s次）", upper(options.regularization(a)), options.lambda(a), ...
            strjoin(string(orders), "・"));
    end
    lossText = LOSS_LABELS(LOSS_NAMES == options.loss(a));
    if options.loss(a) == "huber"
        lossText = lossText + sprintf("（c = %g）", options.huberTuning(a));
    end
    regressionText(a) = lossText + "、" + regularizationText;
end
if regressionText(1) == regressionText(2)
    regressionText = regressionText(1);
else
    regressionText = "X は " + regressionText(1) + "、Y は " + regressionText(2);
end
excludedText = "";
if ~isempty(options.excludedTerms)
    excludedText = "・外した項 " + strjoin("k" + string(options.excludedTerms), "・");
end
options.description = MAKER_LABELS(MAKER_NAMES == options.maker) + excludedText + "、" + regressionText;
end

function values = axisPair(values)
% 回帰の設定を [X, Y] の並びにする（1つなら X・Y で同じ）
values = reshape(values, 1, []);
if isscalar(values)
    values = [values, values];
end
end

function mustBeScalarIn(value, lower, upper, name, lowerInclusive)
% 有限の数1つで、範囲に入るか（lowerInclusive なら下限を含む）
ok = isnumeric(value) && isscalar(value) && isfinite(value) && value <= upper && ...
    (value > lower || (lowerInclusive && value == lower));
if ~ok
    if lowerInclusive
        error('alignest:markLayout', '%s は %g 以上 %g 以下の数にしてください。', name, lower, upper);
    end
    error('alignest:markLayout', '%s は %g より大きい数にしてください。', name, lower);
end
end

function mustBeCount(value, lower, upper, name)
% 整数1つで、範囲に入るか
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value ~= round(value) || value < lower || value > upper
    if isinf(upper)
        error('alignest:markLayout', '%s は %d 以上の整数にしてください。', name, lower);
    end
    error('alignest:markLayout', '%s は %d〜%d の整数にしてください。', name, lower, upper);
end
end
