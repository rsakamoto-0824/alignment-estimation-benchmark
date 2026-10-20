function data = prepareData(raw, mapping, options)
%PREPAREDATA 読み込んだ表を、Wafer（計測）ごとの Mark・Shot の配列にまとめる。
%   Overlay 計測ルールの前処理に従う。
%   - 解析座標は x = Xmm + markXmm、y = Ymm + markYmm（mm）。有効な点は半径 r < validRadiusMm（境界上は除外）。
%   - X の解析には StsX = 0 の measX、Y の解析には StsY = 0 の measY だけを使う（未測定を0として扱わない）。
%   - Wafer・DateTime・Xmm・Ymm・markXmm・markYmm が同じ行は重複とみなし、計測値を X・Y それぞれ平均する。
%   - Radius の列があれば、Xmm・Ymm から計算した値と 0.001 mm より違う行の数を知らせる。
%   - 同じ Wafer でも DateTime が違えば別の計測（評価の単位）として扱う。
%   data.units は評価の単位（Wafer × DateTime）の構造体配列、data.summary は確認用の件数と注意。
arguments
    raw table
    mapping struct
    options.validRadiusMm (1, 1) double = 150
    options.coordinateUnits (1, 1) struct = struct()
end
RADIUS_TOLERANCE_MM = 1e-3;
COORDINATE_DIGITS = 4;  % 重複・Shot の判定で座標を丸める桁（0.1 µm）
SHOT_COORDINATE_DIGITS = 3; % Shot 中心と配列の行を判定する桁（1 µm）
nRows = height(raw);
[inputUnits, scale] = alignest.coordinateUnits(options.coordinateUnits);

required = alignest.standardColumns();
required = string({required([required.required]).name});
missingColumns = required(arrayfun(@(name) ~isfield(mapping, name) || mapping.(name) == "", required));
if ~isempty(missingColumns)
    error('alignest:missingColumn', ['必須の項目が対応づけられていません: %s。', ...
        '「列の対応」の表で、ファイルのどの列にあたるかを選んでください。'], strjoin(missingColumns, "、"));
end
column = @(name) columnValues(raw, mapping, name);
Xmm = toNumeric(column("Xmm")) * scale.Xmm;
Ymm = toNumeric(column("Ymm")) * scale.Ymm;
markXmm = toNumeric(column("markXmm")) * scale.markXmm;
markYmm = toNumeric(column("markYmm")) * scale.markYmm;
measX = toNumeric(column("measX"));
measY = toNumeric(column("measY"));
wafer = defaultText(column("Wafer"), nRows, "Wafer");
dateTime = defaultText(column("DateTime"), nRows, "");
shotNo = defaultNumeric(column("shotNo"), nRows);
direction = defaultNumeric(column("Direction"), nRows);
markNo = defaultNumeric(column("markNo"), nRows);
radius = defaultNumeric(column("Radius"), nRows) * scale.Radius;
coordinateNames = string(fieldnames(inputUnits));
messages = strings(numel(coordinateNames), 1);
for k = 1:numel(coordinateNames)
    name = coordinateNames(k);
    if isMapped(mapping, name)
        messages(k) = sprintf("%s：入力 %s → mm（倍率 %g）。", name, inputUnits.(name), scale.(name));
    end
end
messages = messages(messages ~= "");
hasDirection = isMapped(mapping, "Direction");
hasShotNo = isMapped(mapping, "shotNo");
hasMarkNo = isMapped(mapping, "markNo");

% ステータス：0 が有効、それ以外（−1 = 未測定など）は使わない
statusX = defaultNumeric(column("StsX"), nRows, 0);
statusY = defaultNumeric(column("StsY"), nRows, 0);
validX = statusX == 0 & ~isnan(measX);
validY = statusY == 0 & ~isnan(measY);

summary.nRowsRead = nRows;
noCoordinate = any(~isfinite([Xmm, Ymm, markXmm, markYmm]), 2) | wafer == "";
summary.nNoCoordinate = nnz(noCoordinate);
if summary.nNoCoordinate > 0
    messages(end + 1) = sprintf("座標が空・非有限値、または Wafer が空の %d 行を除きました。", summary.nNoCoordinate);
end
summary.nRadiusMismatch = nnz(abs(radius - hypot(Xmm, Ymm)) > RADIUS_TOLERANCE_MM);
if summary.nRadiusMismatch > 0
    messages(end + 1) = sprintf("Radius が sqrt(Xmm² + Ymm²) と 0.001 mm より違う行が %d 行あります（解析には計算値を使います）。", ...
        summary.nRadiusMismatch);
end
x = Xmm + markXmm;
y = Ymm + markYmm;
r = hypot(x, y);
outside = r >= options.validRadiusMm & ~noCoordinate;
summary.nOutsideRadius = nnz(outside);
if summary.nOutsideRadius > 0
    messages(end + 1) = sprintf("半径 %g mm 以上の %d 行を除きました（有効な点は r < %g mm）。", ...
        options.validRadiusMm, summary.nOutsideRadius, options.validRadiusMm);
end
if hasDirection
    badDirection = ~isnan(direction) & ~ismember(direction, [1, 2]);
    if any(badDirection)
        error('alignest:direction', ['Direction（Scan方向）は 1 か 2 にしてください。', ...
            'ほかの値が %d 行あります（例：%g）。列の対応が正しいか確かめてください。'], ...
            nnz(badDirection), direction(find(badDirection, 1)));
    end
    if any(isnan(direction) & ~noCoordinate & ~outside)
        messages(end + 1) = "Direction が空の行があります。その行を含む Wafer では Scan 方向を質的変数に使いません。";
    end
end
if hasMarkNo && any(isnan(markNo) & ~noCoordinate & ~outside)
    error('alignest:markNo', 'markNo が空の行が %d 行あります。値を入れるか、markNo の対応を「（なし）」にしてください。', ...
        nnz(isnan(markNo) & ~noCoordinate & ~outside));
end
keep = ~noCoordinate & ~outside;
summary.nInvalidX = nnz(~validX & keep);
summary.nInvalidY = nnz(~validY & keep);
if summary.nInvalidX + summary.nInvalidY > 0
    messages(end + 1) = sprintf("未測定・無効の値（Sts ≠ 0 または空）：X %d 点、Y %d 点。解析に使いません。", ...
        summary.nInvalidX, summary.nInvalidY);
end
if ~hasMarkNo
    % マーク座標の組ごとに番号を付ける（下の行から、左→右）
    markKey = round([markYmm, markXmm], COORDINATE_DIGITS);
    [~, ~, derived] = unique(markKey, 'rows');
    markNo = derived;
    messages(end + 1) = "markNo の列が無いので、マーク座標（markXmm, markYmm）の組ごとに番号を付けました。";
end

% 評価の単位：Wafer × DateTime
unitKey = wafer + char(31) + dateTime;
% 半径で上端の行が消えても、残った行の奇偶を付け直さない。
shotRow = nan(nRows, 1);
for key = unique(unitKey(~noCoordinate)).'
    rows = find(unitKey == key & ~noCoordinate);
    rowCoordinates = round(Ymm(rows), SHOT_COORDINATE_DIGITS);
    levels = sort(unique(rowCoordinates), 'descend');
    [~, shotRow(rows)] = ismember(rowCoordinates, levels);
end
unitKey(~keep) = missing;
[unitKeys, ~, unitOfRow] = unique(unitKey(keep), 'stable');
rowsKept = find(keep);
nUnits = numel(unitKeys);
if nUnits == 0
    error('alignest:noData', '解析できる行がありません。座標の列と有効半径を確かめてください。');
end
waferOfUnit = strings(nUnits, 1);
for u = 1:nUnits
    waferOfUnit(u) = wafer(rowsKept(find(unitOfRow == u, 1)));
end
units = repmat(emptyUnit(), nUnits, 1);
summary.nDuplicateRows = 0;
for u = 1:nUnits
    rows = rowsKept(unitOfRow == u);
    % 重複（同じ座標の行）をまとめる
    coordinateKey = round([Xmm(rows), Ymm(rows), markXmm(rows), markYmm(rows)], COORDINATE_DIGITS);
    [~, first, group] = unique(coordinateKey, 'rows', 'stable');
    summary.nDuplicateRows = summary.nDuplicateRows + numel(rows) - numel(first);
    [meanX, anyX] = groupMean(measX(rows), validX(rows), group, numel(first));
    [meanY, anyY] = groupMean(measY(rows), validY(rows), group, numel(first));
    pick = rows(first);
    marks.Xmm = Xmm(pick);
    marks.Ymm = Ymm(pick);
    marks.markXmm = markXmm(pick);
    marks.markYmm = markYmm(pick);
    marks.markNo = markNo(pick);
    marks.direction = direction(pick);
    marks.shotRow = shotRow(pick);
    marks.shotRowParity = 1 + mod(marks.shotRow - 1, 2); % 1 = 奇数行、2 = 偶数行
    marks.x = x(pick);
    marks.y = y(pick);
    marks.r = r(pick);
    marks.theta = atan2(marks.y, marks.x);
    marks.measX = meanX;
    marks.measY = meanY;
    marks.validX = anyX;
    marks.validY = anyY;
    % Shot：Shot 中心の座標が同じ Mark の集まり。番号は shotNo の列、無ければ上の行から左→右
    shotKey = round([marks.Xmm, marks.Ymm], SHOT_COORDINATE_DIGITS);
    [shotCoordinates, firstOfShot, shotOfMark] = unique(shotKey, 'rows');
    nShots = size(shotCoordinates, 1);
    [~, order] = sortrows([-shotCoordinates(:, 2), shotCoordinates(:, 1)]);
    shotRank = zeros(nShots, 1);
    shotRank(order) = 1:nShots;
    shotOfMark = shotRank(shotOfMark);
    firstOfShot(shotRank) = firstOfShot;
    shots.Xmm = marks.Xmm(firstOfShot);
    shots.Ymm = marks.Ymm(firstOfShot);
    shots.radius = hypot(shots.Xmm, shots.Ymm);
    shots.row = marks.shotRow(firstOfShot);
    shots.rowParity = marks.shotRowParity(firstOfShot);
    if hasShotNo
        shots.shotNo = shotNo(pick(firstOfShot));
    else
        shots.shotNo = (1:nShots).';
    end
    shots.direction = nan(nShots, 1);
    for s = 1:nShots
        values = marks.direction(shotOfMark == s & ~isnan(marks.direction));
        if ~isempty(values)
            shots.direction(s) = mode(values);
        end
    end
    shots.nValidX = accumarray(shotOfMark, marks.validX, [nShots, 1]);
    shots.nValidY = accumarray(shotOfMark, marks.validY, [nShots, 1]);
    marks.shotIndex = shotOfMark;
    marks.shotNo = shots.shotNo(shotOfMark);
    units(u).wafer = waferOfUnit(u);
    units(u).dateTime = dateTime(rows(1));
    units(u).label = waferOfUnit(u);
    units(u).marks = marks;
    units(u).shots = shots;
    units(u).hasDirection = hasDirection && all(~isnan(marks.direction));
    if hasShotNo && numel(unique(shots.shotNo)) < nShots
        messages(end + 1) = sprintf("%s：同じ shotNo が別の座標の Shot に付いています。手動の指定では最初の Shot を使います。", ...
            units(u).label); %#ok<AGROW>
    end
end
% 同じ Wafer に複数の日時があるときは、表示名に日時を付ける
for u = 1:nUnits
    if nnz(waferOfUnit == waferOfUnit(u)) > 1
        units(u).label = waferOfUnit(u) + " (" + units(u).dateTime + ")";
    end
end
if summary.nDuplicateRows > 0
    messages(end + 1) = sprintf("Wafer・DateTime・座標が同じ重複行 %d 行を、計測値の平均にまとめました。", summary.nDuplicateRows);
end
nShotsPerUnit = arrayfun(@(unit) numel(unit.shots.Xmm), units);
nMarksPerUnit = arrayfun(@(unit) numel(unit.marks.x), units);
summary.nUnits = nUnits;
summary.nShotsRange = [min(nShotsPerUnit), max(nShotsPerUnit)];
summary.nMarksRange = [min(nMarksPerUnit), max(nMarksPerUnit)];
summary.markLevels = unique(markNo(keep)).';
summary.hasDirection = hasDirection;
messages(end + 1) = "Shot 行は、Wafer・測定日時ごとに入力の Ymm を上から数えます（0.001 mm 刻み、半径除外前）。1=奇数行、2=偶数行。入力にない行は数えません。";
summary.messages = messages;
data.units = units;
data.summary = summary;
data.validRadiusMm = options.validRadiusMm;
data.coordinateUnits = inputUnits;
end

function values = columnValues(raw, mapping, name)
if isMapped(mapping, name)
    values = raw.(mapping.(name));
else
    values = [];
end
end

function result = isMapped(mapping, name)
result = isfield(mapping, name) && strlength(string(mapping.(name))) > 0;
end

function values = toNumeric(values)
if isnumeric(values) || islogical(values)
    values = double(values);
elseif isstring(values) || iscellstr(values) || iscategorical(values) || ischar(values)
    values = str2double(string(values));
elseif isdatetime(values)
    error('alignest:numericColumn', '数値の項目に日時の列が対応づけられています。列の対応を確かめてください。');
else
    error('alignest:numericColumn', '数値として読めない列があります（型: %s）。', class(values));
end
values = values(:);
end

function values = defaultNumeric(values, nRows, fallback)
if nargin < 3
    fallback = NaN;
end
if isempty(values)
    values = repmat(fallback, nRows, 1);
else
    values = toNumeric(values);
end
end

function text = defaultText(values, nRows, fallback)
if isempty(values)
    text = repmat(string(fallback), nRows, 1);
    return
end
if isdatetime(values)
    text = string(values, 'yyyy/MM/dd HH:mm:ss');
else
    text = string(values);
end
text(ismissing(text)) = "";
text = strtrim(text(:));
end

function [averages, anyValid] = groupMean(values, valid, group, nGroups)
% 有効な値だけで群ごとに平均する。有効な値が無い群は NaN・無効
counts = accumarray(group, double(valid), [nGroups, 1]);
values(~valid) = 0;
sums = accumarray(group, values, [nGroups, 1]);
averages = sums ./ counts;
anyValid = counts > 0;
averages(~anyValid) = NaN;
end

function unit = emptyUnit()
unit = struct("wafer", "", "dateTime", "", "label", "", "marks", struct(), "shots", struct(), "hasDirection", false);
end
