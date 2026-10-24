function result = predictTargets(unit, training, method, settings, targets)
%PREDICTTARGETS 未知の座標（推定したい点）での推定値を、1つの Wafer の学習データから求める。
%   result = alignest.predictTargets(unit, training, method, settings, targets)
%   training：学習に使う Shot の番号（unit.shots の何番目か。計測した全 Shot なら 1:numel(unit.shots.shotNo)）、
%   または学習パターン（評価の results.plans の1つ。Mark 単位の計画も使える）。
%   targets：推定したい点（alignest.targetTemplate の形）。Wafer 上の座標は x = Xmm + markXmm、y = Ymm + markYmm。
%   推定は評価と同じ alignest.estimateWafer で行う（点を、計測値の無い Mark として Wafer の Mark の後ろに足し、
%   推定する点にする。学習には使わない）。1次を除く・異常値の除外などは settings.evaluation のとおり。
%   点の Shot：shotNo があればその Shot、無ければ点を含む Shot（Shot 中心 ± Shot の大きさ / 2）。Scan 方向は点の
%   direction、空欄ならその Shot の Scan 方向。Shot 行の奇偶もその Shot から。分からない点は NaN（効果は平均）。
%   学習点に無い水準（学習に無い Mark 番号など）の点は、その質的変数の効果を全水準の平均として推定する
%   （効果コードは 0、加法カーネルは同じ水準の学習点が無い。alignest.basis.effectCoding・models.gprModeSetup）。
%   外挿：学習点（X・Y のどちらかで学習に使った Mark）を囲む凸包の外に、EXTRAPOLATION_TOLERANCE_MM より
%   離れた点。
%   result.table：点ごとの name・Xmm・Ymm・markXmm・markYmm・x・y・markNo・shotNo・direction・estimateX・
%   estimateY（[nm]）・extrapolated・outsideMm（凸包の外への距離、内側は 0）・nearestMm（最も近い学習点までの
%   距離）・unseenMark（学習に無い Mark 番号）・note（点ごとの注意）。
%   result.messages：画面に出す説明（外挿・学習に無い Mark 番号・Scan 方向が分からない点など）。
%   result.nExtrapolated・nUnseenMark：その点の数、result.trainXY：学習点の座標、result.hull：凸包の頂点、
%   result.toleranceMm：外挿とみなす距離、result.seconds：推定にかかった秒数。
arguments
    unit struct
    training
    method struct
    settings struct
    targets table
end
EXTRAPOLATION_TOLERANCE_MM = 0.5;  % 凸包の外でも、この距離以内は範囲内とみなす（境界の上の点・座標の丸めの差）
NEAREST_CHUNK = 2000;              % 最も近い学習点を探すとき一度に比べる点の数（メモリを使いすぎないため）
AXIS_NAMES = ["X", "Y"];
n = height(targets);
if n == 0
    error('alignest:noTargets', '推定する点がありません。点を読み込むか、表に点を足してください。');
end
marks = unit.marks;
shots = unit.shots;
nMarks = numel(marks.x);
x = targets.Xmm + targets.markXmm;
y = targets.Ymm + targets.markYmm;
bad = ~isfinite(x) | ~isfinite(y);
if any(bad)
    error('alignest:targetCoordinates', '座標（Xmm・Ymm・markXmm・markYmm）が数でない点があります：%s', ...
        strjoin(targets.name(bad).', "・"));
end

% 点の Shot・Scan 方向を補い、計測値の無い Mark として足して推定する
[shotIndex, shotMissing] = locateShots(unit, targets, x, y);
located = shotIndex > 0;
direction = targets.direction;
fromShot = isnan(direction) & located;
direction(fromShot) = shots.direction(shotIndex(fromShot));
shotNo = targets.shotNo;
shotNo(isnan(shotNo) & located) = shots.shotNo(shotIndex(isnan(shotNo) & located));
extended = unit;
extended.marks = appendTargets(marks, targets, x, y, direction, shotIndex, shotNo, shots);
timer = tic;
out = alignest.estimateWafer(extended, training, method, settings, [false(nMarks, 1); true(n, 1)]);
estimate = nan(n, 2);
for k = 1:2
    estimate(out.testIndex.(AXIS_NAMES(k)) - nMarks, k) = out.estimate.(AXIS_NAMES(k));
end

% 学習点の範囲（凸包）と比べて外挿を判定する
trainRows = unique([out.trainIndex.X; out.trainIndex.Y]);
trainXY = [marks.x(trainRows), marks.y(trainRows)];
hull = hullOf(trainXY);
outsideMm = distanceOutside(hull, [x, y]);
nearestMm = nearestDistance(trainXY, [x, y], NEAREST_CHUNK);
extrapolated = outsideMm > EXTRAPOLATION_TOLERANCE_MM;
unseenMark = ~isnan(targets.markNo) & ~ismember(targets.markNo, unique(marks.markNo(trainRows)));

% 質的変数を使う手法か（使わない手法では、Mark 番号・Scan 方向が分からなくても推定値は変わらない）
usesFactors = method.family == "GAM" || ...
    (any(method.family == ["GPR", "TPS", "RBF", "RBFE", "OK", "UK"]) && method.factorMode ~= "none");
choices = [alignest.factorChoice(settings, "X"), alignest.factorChoice(settings, "Y")];
usesMark = usesFactors && any([choices.mark]);
usesScan = usesFactors && any([choices.scan]) && unit.hasDirection;
usesRow = usesFactors && any([choices.row]);

notes = strings(n, 1);
notes = addNote(notes, extrapolated, compose("外挿（学習範囲の外 %.1f mm）", outsideMm));
notes = addNote(notes, hypot(x, y) >= settings.data.validRadiusMm, "有効半径の外");
notes = addNote(notes, unseenMark, "学習に無い Mark 番号" + ternary(usesMark, "（効果は平均）", ""));
notes = addNote(notes, usesMark & isnan(targets.markNo), "Mark 番号が空欄（効果は平均）");
notes = addNote(notes, shotMissing, "shotNo がこの Wafer に無い");
notes = addNote(notes, usesScan & isnan(direction), "Scan 方向が不明（効果は平均）");
notes = addNote(notes, usesRow & ~located, "Shot 行が不明（効果は平均）");

messages = strings(0, 1);
if any(extrapolated)
    messages(end + 1, 1) = sprintf(['⚠ 外挿：%d / %d 点が学習点の範囲（学習点を囲む凸包）の外にあります（最大 %.1f mm 外）。' ...
        '学習点から離れるほど推定値は信頼できません（表の「外挿」、図の × 印）。'], nnz(extrapolated), n, max(outsideMm));
else
    messages(end + 1, 1) = sprintf('外挿なし：%d 点すべてが学習点の範囲（学習点を囲む凸包）の中です。', n);
end
if any(unseenMark)
    levels = unique(targets.markNo(unseenMark)).';
    tail = "この手法は Mark 番号を使わないので、位置だけで推定します。";
    if usesMark
        tail = "この手法は Mark 番号の効果を使うので、その点は全 Mark の平均の効果で推定します。";
    end
    messages(end + 1, 1) = sprintf("⚠ 学習データに無い Mark 番号：%s（%d 点）。", strjoin("M" + string(levels), "・"), ...
        nnz(unseenMark)) + tail;
end
if usesMark && any(isnan(targets.markNo))
    messages(end + 1, 1) = sprintf('Mark 番号が空欄の点：%d 点（Mark 番号の効果は全 Mark の平均で推定します）。', ...
        nnz(isnan(targets.markNo)));
end
if any(shotMissing)
    messages(end + 1, 1) = sprintf('⚠ この Wafer に無い shotNo：%s（その点は座標だけで推定します）。', ...
        strjoin(string(unique(targets.shotNo(shotMissing)).'), "・"));
end
if usesScan && any(isnan(direction))
    messages(end + 1, 1) = sprintf(['Scan 方向が分からない点：%d 点（Shot の外にあり Direction も空欄）。' ...
        'Scan 方向の効果は平均で推定します。'], nnz(isnan(direction)));
end

result.table = table(targets.name, targets.Xmm, targets.Ymm, targets.markXmm, targets.markYmm, x, y, targets.markNo, ...
    shotNo, direction, estimate(:, 1), estimate(:, 2), extrapolated, outsideMm, nearestMm, unseenMark, notes, ...
    'VariableNames', ["name", "Xmm", "Ymm", "markXmm", "markYmm", "x", "y", "markNo", "shotNo", "direction", ...
    "estimateX", "estimateY", "extrapolated", "outsideMm", "nearestMm", "unseenMark", "note"]);
result.messages = messages;
result.nExtrapolated = nnz(extrapolated);
result.nUnseenMark = nnz(unseenMark);
result.trainXY = trainXY;
result.hull = hull;
result.toleranceMm = EXTRAPOLATION_TOLERANCE_MM;
result.seconds = toc(timer);
end

function [shotIndex, missing] = locateShots(unit, targets, x, y)
% 点の Shot（unit.shots の何番目か。分からなければ 0）。shotNo があればその Shot、無ければ点を含む Shot
% （Shot 中心 ± Shot の大きさ / 2。重なる所は中心が近い Shot）。missing は shotNo がこの Wafer に無い点
shots = unit.shots;
shotIndex = zeros(numel(x), 1);
given = ~isnan(targets.shotNo);
[found, position] = ismember(targets.shotNo, shots.shotNo);
shotIndex(given & found) = position(given & found);
missing = given & ~found;
half = [NaN, NaN];
if isfield(unit, "shotSizeMm")
    half = unit.shotSizeMm / 2;
end
free = ~given;
if ~any(free) || any(~isfinite(half)) || any(half <= 0)
    return
end
dx = abs(x(free) - shots.Xmm(:).');
dy = abs(y(free) - shots.Ymm(:).');
distance = hypot(dx, dy);
distance(dx > half(1) | dy > half(2)) = Inf;
[nearest, index] = min(distance, [], 2);
index(isinf(nearest)) = 0;
shotIndex(free) = index;
end

function marks = appendTargets(marks, targets, x, y, direction, shotIndex, shotNo, shots)
% 推定する点を Mark の後ろに足す（計測値は無し。shotIndex を 0 にして、どの学習 Shot にも入れない）
n = numel(x);
located = shotIndex > 0;
[row, column, parity] = deal(nan(n, 1));
row(located) = shots.row(shotIndex(located));
column(located) = shots.column(shotIndex(located));
parity(located) = shots.rowParity(shotIndex(located));
added = struct("Xmm", targets.Xmm, "Ymm", targets.Ymm, "markXmm", targets.markXmm, "markYmm", targets.markYmm, ...
    "markNo", targets.markNo, "direction", direction, "shotRow", row, "shotRowParity", parity, "shotColumn", column, ...
    "x", x, "y", y, "r", hypot(x, y), "measX", nan(n, 1), "measY", nan(n, 1), "validX", true(n, 1), ...
    "validY", true(n, 1), "shotIndex", zeros(n, 1), "shotNo", shotNo);
for name = string(fieldnames(marks)).'
    current = marks.(name);
    if isfield(added, name)
        extra = added.(name);
    elseif isstring(current)
        extra = strings(n, size(current, 2));   % ファイルのその他の列：空欄（質的変数の効果は平均）
    elseif islogical(current)
        extra = false(n, size(current, 2));
    else
        extra = nan(n, size(current, 2));
    end
    marks.(name) = [current; extra];
end
end

function hull = hullOf(points)
% 学習点を囲む凸包の頂点（閉じた多角形）。点が3つ未満・一直線に並ぶときは点そのもの（線・点が範囲）
points = unique(points, 'rows');
hull = points;
if size(points, 1) < 3
    return
end
try
    order = convhull(points(:, 1), points(:, 2));
    hull = points(order, :);
catch
    [~, order] = sortrows(points);   % 一直線に並ぶ点：端から順に結んだ線を範囲にする
    hull = points(order, :);
end
end

function distance = distanceOutside(hull, points)
% 凸包の外への距離（内側・境界の上は 0）
distance = segmentDistance(hull, points);
if size(hull, 1) >= 4   % convhull の結果は最初の頂点を最後にもう一度含む閉じた多角形
    distance(inpolygon(points(:, 1), points(:, 2), hull(:, 1), hull(:, 2))) = 0;
end
end

function distance = segmentDistance(vertices, points)
% 点から、頂点を順に結んだ線分までの最短距離
if size(vertices, 1) == 1
    distance = hypot(points(:, 1) - vertices(1, 1), points(:, 2) - vertices(1, 2));
    return
end
startX = vertices(1:end - 1, 1).';
startY = vertices(1:end - 1, 2).';
dx = vertices(2:end, 1).' - startX;
dy = vertices(2:end, 2).' - startY;
t = ((points(:, 1) - startX) .* dx + (points(:, 2) - startY) .* dy) ./ max(dx.^2 + dy.^2, eps);
t = min(max(t, 0), 1);
distance = min(hypot(points(:, 1) - (startX + t .* dx), points(:, 2) - (startY + t .* dy)), [], 2);
end

function distance = nearestDistance(trainXY, points, chunk)
% 最も近い学習点までの距離（点が多いときは chunk 点ずつ比べる）
distance = inf(size(points, 1), 1);
for first = 1:chunk:size(points, 1)
    rows = first:min(first + chunk - 1, size(points, 1));
    distance(rows) = min(hypot(points(rows, 1) - trainXY(:, 1).', points(rows, 2) - trainXY(:, 2).'), [], 2);
end
end

function notes = addNote(notes, mask, text)
% 点のメモに text（1つの文、または点ごとの文）を足す。すでにメモがあれば「；」で区切る
text = text(:) + strings(size(notes));
separator = strings(size(notes));
separator(notes ~= "") = "；";
mask = mask(:);
notes(mask) = notes(mask) + separator(mask) + text(mask);
end

function value = ternary(condition, whenTrue, whenFalse)
if condition
    value = whenTrue;
else
    value = whenFalse;
end
end
