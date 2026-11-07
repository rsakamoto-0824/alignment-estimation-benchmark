function levels = highOrderLevels(result)
%HIGHORDERLEVELS Shot 高次補正の補正値（係数）を、補正の段階ごとに Wafer 低次・Wafer 高次・Wafer RT・Shot 共通 低次・Shot 共通 高次・
%   Shot 毎 低次・Shot 毎 高次の順に並べた表にする（「7. Shot高次補正」の書き出し）。
%   levels = alignest.highOrderLevels(result)
%   result：alignest.shotHighOrder の結果。低次は定数と1次の項（Shot は k1〜k6、Wafer 成分は Xc・Yc の1次）、高次は2次以上の項。
%   - Wafer：Wafer 成分（Shot 中心の座標 Xc・Yc の多項式。定数は Shot 共通の k1・k2 に含む）
%   - Wafer RT：RT モデルの係数（X・Y で共通。axis = "dx・dy"。Wafer 半径で割った座標での値）。使うときだけ
%   - Shot 共通：くくりが Shot ごとなら、Wafer 成分と一緒に Wafer 内の Shot で共通に求めた k（result.commonCoefficients。
%     外周の式を分けるときは内周・外周の2組）。ほかのくくりは k の組の k（Wafer 内で共通・Scan 方向ごと・行の偶奇ごと）
%   - Shot 毎：くくりが Shot ごとのときだけ。Shot ごとの k − Shot 共通の k（Shot 共通に足すと、その Shot に当てる k）。
%     その Shot で使わない項（点が足りず外した項）は − Shot 共通（足すと 0）
%   列：wafer・level（段階の名前）・shotNo・group（k の組の名前）・zone（外周の式を分けるときの式の範囲）・axis・k・term・
%   value・unit・note・xPower・yPower。行は Wafer の順、段階の順、Shot の番号の順、k の番号の順（Wafer 成分は dx・dy、次数の順）。
arguments
    result struct
end
LEVEL_NAMES = ["Wafer 低次", "Wafer 高次", "Wafer RT", "Shot 共通 低次", "Shot 共通 高次", "Shot 毎 低次", "Shot 毎 高次"];
COMMON_LEVEL = 4;   % LEVEL_NAMES の「Shot 共通 低次」の位置
HIGH_ORDER = 2;   % これ以上の次数を「高次」とする
coefficients = result.coefficients;
waferRows = coefficients(coefficients.component == "Wafer 成分", :);
shotRows = coefficients(coefficients.component == "Shot 高次補正", :);
waferRows.level = levelName(waferRows, 1, LEVEL_NAMES, HIGH_ORDER);
rtRows = coefficients(coefficients.component == "Wafer RT", :);
rtRows.level = repmat("Wafer RT", height(rtRows), 1);
if result.options.unit ~= "shot"
    shotRows.level = levelName(shotRows, COMMON_LEVEL, LEVEL_NAMES, HIGH_ORDER);
    parts = {waferRows, rtRows, shotRows};
else
    common = result.commonCoefficients;
    deviation = perShotDeviation(shotRows, common, LEVEL_NAMES, HIGH_ORDER);
    common.level = levelName(common, COMMON_LEVEL, LEVEL_NAMES, HIGH_ORDER);
    parts = {waferRows, rtRows, common, deviation};
end
levels = vertcat(parts{:});
levels.component = [];
% 並べ方：Wafer の順（結果の順）→ 段階 → Shot → 式（Wafer 成分）→ k（Wafer 成分は次数の順。表の元の順を保つ）
[~, waferOrder] = ismember(levels.wafer, unique(coefficients.wafer, 'stable'));
[~, levelOrder] = ismember(levels.level, LEVEL_NAMES);
shotOrder = levels.shotNo;
shotOrder(isnan(shotOrder)) = -Inf;   % Shot 共通・Wafer 成分（Shot の番号なし）を先に
axisOrder = double(levels.axis == "dy") .* isnan(levels.k);   % Wafer 成分だけ dx・dy の順（k は dx・dy が交互の番号）
kOrder = levels.k;
kOrder(isnan(kOrder)) = 0;
powerOrder = levels.xPower + levels.yPower;
powerOrder(isnan(powerOrder)) = 0;   % Wafer RT（べきなし）は表の元の順
[~, order] = sortrows([waferOrder, levelOrder, shotOrder, axisOrder, kOrder, powerOrder, (1:height(levels)).']);
levels = levels(order, ["wafer", "level", "shotNo", "group", "zone", "axis", "k", "term", "value", "unit", "note", ...
    "xPower", "yPower"]);
end

function names = levelName(rows, first, levelNames, highOrder)
% 項の次数で低次（first 番目の段階）か高次（次の段階）かを決める
isHigh = rows.xPower + rows.yPower >= highOrder;
names = reshape(levelNames(first + isHigh), [], 1);
if isempty(rows)
    names = strings(0, 1);
end
end

function rows = perShotDeviation(shotRows, common, levelNames, highOrder)
% Shot 毎：Shot ごとの k から Shot 共通の k（同じ Wafer・式・範囲・k）を引いた値。Shot 共通に無い k はそのまま（メモ）。
% その Shot で使わない Shot 共通の項は − Shot 共通の行を足す（Shot 共通に足すと 0 になる）
NO_COMMON_NOTE = "Shot 共通の k が無い（求められなかった）ので、Shot ごとの k のまま";
UNUSED_NOTE = "この Shot では使わない項（点が足りず外した）。Shot 共通に足すと 0";
commonKey = common.wafer + "|" + common.axis + "|" + common.zone + "|" + string(common.k);
shotKey = shotRows.wafer + "|" + shotRows.axis + "|" + shotRows.zone + "|" + string(shotRows.k);
[found, position] = ismember(shotKey, commonKey);
rows = shotRows;
rows.value(found) = shotRows.value(found) - common.value(position(found));
rows.note(~found & rows.note == "") = NO_COMMON_NOTE;
% その Shot で使わない Shot 共通の項
shotGroups = unique(shotRows(:, ["wafer", "shotNo", "group", "zone", "axis"]), 'stable');
extra = cell(height(shotGroups), 1);
for s = 1:height(shotGroups)
    group = shotGroups(s, :);
    mine = shotRows(shotRows.wafer == group.wafer & shotRows.shotNo == group.shotNo & shotRows.axis == group.axis, :);
    theirs = common(common.wafer == group.wafer & common.axis == group.axis & common.zone == group.zone & ...
        ~ismember(common.k, mine.k), :);
    if isempty(theirs)
        continue
    end
    theirs.shotNo(:) = group.shotNo;
    theirs.group(:) = group.group;
    theirs.value = -theirs.value;
    theirs.note(:) = UNUSED_NOTE;
    extra{s} = theirs;
end
rows = [rows; vertcat(extra{:})];
rows.component(:) = "Shot 毎";
rows.level = levelName(rows, numel(levelNames) - 1, levelNames, highOrder);
end
