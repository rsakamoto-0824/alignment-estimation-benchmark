function data = prepareData(raw, mapping, options)
%PREPAREDATA 読み込んだ表を、Wafer（計測）ごとの Mark・Shot の配列にまとめる。
%   Overlay 計測ルールの前処理に従う。
%   - 解析座標は x = Xmm + markXmm、y = Ymm + markYmm（mm）。有効な点は半径 r < validRadiusMm（境界上は除外）。
%   - X の解析には StsX = 0 の measX、Y の解析には StsY = 0 の measY だけを使う（未測定を0として扱わない）。
%   - Wafer・DateTime・Xmm・Ymm・markXmm・markYmm が同じ行は重複とみなし、計測値を X・Y それぞれ平均する。
%   - Radius の列があれば、Xmm・Ymm から計算した値と 0.001 mm より違う行の数を知らせる。
%   - 同じ Wafer でも Operation（工程）・EqpId（装置）・LotID（ロット）・DateTime が違えば別の計測（評価の単位）として扱う。
%   - 標準の項目に対応づけなかったファイルの列は、Mark ごとの値（文字列、空は ""）を marks.attributes に残す
%     （列の名前は data.attributeNames・unit.attributeNames。質的変数に選べる。重複行は最初の行の値）。
%   - Direction（Scan 方向）が無い行には、options.directionRule の規則で 1・2 を付ける（"none" なら付けない）。
%     規則は alignest.directionRules を参照。invertDirection が true なら付ける 1 と 2 を入れ替える。
%   - options.directionOverrideShots・directionOverrideValues（同じ長さ）の shotNo の Shot は、Scan 方向をその値にする
%     （画面で変えた Scan 方向。すべての Wafer の同じ shotNo に当てる。規則やファイルの値より優先）。
%   - unit.label は Wafer ID。Operation・EqpId・LotID のどれかがデータの中で2種類以上あれば、その値を付けて区別する
%     （例：SIM01 (EXP01)）。それでも同じ名前の計測があれば測定日時も付ける。
%   data.units は評価の単位（Operation × EqpId × LotID × Wafer × DateTime）の構造体配列、data.summary は確認用の件数と注意。
arguments
    raw table
    mapping struct
    options.validRadiusMm (1, 1) double = 150
    options.coordinateUnits (1, 1) struct = struct()
    options.excludeZeroMeasurements (1, 1) logical = false
    options.excludeUnmeasuredRecords (1, 1) logical = false
    options.directionRule (1, 1) string = "none"
    options.invertDirection (1, 1) logical = false
    options.directionOverrideShots double = zeros(1, 0)
    options.directionOverrideValues double = zeros(1, 0)
end
overrideShots = options.directionOverrideShots(:);
overrideValues = options.directionOverrideValues(:);
if numel(overrideShots) ~= numel(overrideValues) || any(~ismember(overrideValues, [1, 2]))
    error('alignest:directionOverride', '画面で変えた Scan 方向は、shotNo と 1・2 の値を同じ数だけ指定してください。');
end
RADIUS_TOLERANCE_MM = 1e-3;
COORDINATE_DIGITS = 4;  % 重複・Shot の判定で座標を丸める桁（0.1 µm）
SHOT_COORDINATE_DIGITS = 3; % Shot 中心と配列の行を判定する桁（1 µm）
nRows = height(raw);
[inputUnits, scale] = alignest.coordinateUnits(options.coordinateUnits);
[ruleNames, ruleLabels] = alignest.directionRules();
if ~any(options.directionRule == ruleNames)
    error('alignest:directionRule', 'Scan 方向を付ける規則は %s のいずれかです: %s', strjoin(ruleNames, "・"), ...
        options.directionRule);
end

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
operation = defaultText(column("Operation"), nRows, "");
eqpId = defaultText(column("EqpId"), nRows, "");
lotId = defaultText(column("LotID"), nRows, "");
[attributeNames, attributes] = otherColumns(raw, mapping);
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
hasDirectionColumn = isMapped(mapping, "Direction");
hasShotNo = isMapped(mapping, "shotNo");
hasMarkNo = isMapped(mapping, "markNo");

% ステータス：0 が有効、それ以外（−1 = 未測定など）は使わない
statusX = defaultNumeric(column("StsX"), nRows, 0);
statusY = defaultNumeric(column("StsY"), nRows, 0);
validX = statusX == 0 & ~isnan(measX);
validY = statusY == 0 & ~isnan(measY);
% 元の入力行で判定する。重複の平均後にゼロになった値は除かない。
zeroMeasurements = options.excludeZeroMeasurements & measX == 0 & measY == 0;
unmeasuredRecords = options.excludeUnmeasuredRecords & (statusX == -1 | statusY == -1);
excludedRecords = zeroMeasurements | unmeasuredRecords;

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
eligible = ~noCoordinate & ~outside;

% 評価の単位：Operation × EqpId × LotID × Wafer × DateTime
unitKey = operation + char(31) + eqpId + char(31) + lotId + char(31) + wafer + char(31) + dateTime;
% Shot の行（上から）と列（左から）。半径・測定値・ステータスで端の行が消えても、残った行の番号を付け直さない。
shotRow = nan(nRows, 1);
shotColumn = nan(nRows, 1);
for key = unique(unitKey(~noCoordinate)).'
    rows = find(unitKey == key & ~noCoordinate);
    rowCoordinates = round(Ymm(rows), SHOT_COORDINATE_DIGITS);
    [~, shotRow(rows)] = ismember(rowCoordinates, sort(unique(rowCoordinates), 'descend'));
    columnCoordinates = round(Xmm(rows), SHOT_COORDINATE_DIGITS);
    [~, shotColumn(rows)] = ismember(columnCoordinates, unique(columnCoordinates));
end
[direction, directionAssigned] = assignDirection(direction, ~noCoordinate, options, shotNo, hasShotNo, shotRow, ...
    shotColumn, unitKey);
hasDirection = hasDirectionColumn || options.directionRule ~= "none" || ~isempty(overrideShots);
summary.nZeroMeasurementsExcluded = nnz(zeroMeasurements & eligible);
summary.nUnmeasuredRecordsExcluded = nnz(unmeasuredRecords & eligible);
summary.nRecordsExcluded = nnz(excludedRecords & eligible);
if options.excludeZeroMeasurements || options.excludeUnmeasuredRecords
    messages(end + 1) = sprintf(['入力行の選択除外（座標・半径による除外後、重複を平均する前）：' ...
        '測定値X・Yがともに0 %d 行、StsXまたはStsYが−1 %d 行。重なりを除く合計 %d 行を除きました。'], ...
        summary.nZeroMeasurementsExcluded, summary.nUnmeasuredRecordsExcluded, summary.nRecordsExcluded);
end
if options.excludeUnmeasuredRecords && (~isMapped(mapping, "StsX") || ~isMapped(mapping, "StsY"))
    messages(end + 1) = "未測定行の選択除外：対応づけられていない Sts 列は判定できません。対応づけられた列だけで判定しました。";
end
keep = eligible & ~excludedRecords;
if hasDirection
    badDirection = ~isnan(direction) & ~ismember(direction, [1, 2]) & ~excludedRecords & ~noCoordinate;
    if any(badDirection)
        error('alignest:direction', ['Direction（Scan方向）は 1 か 2 にしてください。', ...
            'ほかの値が %d 行あります（例：%g）。列の対応が正しいか確かめてください。'], ...
            nnz(badDirection), direction(find(badDirection, 1)));
    end
    if any(isnan(direction) & keep)
        messages(end + 1) = "Direction が空の行があります。その行を含む Wafer では Scan 方向を質的変数に使いません。";
    end
end
summary.nDirectionAssigned = nnz(directionAssigned & keep);
summary.directionRule = options.directionRule;
summary.directionSource = directionSource(hasDirectionColumn, summary.nDirectionAssigned, ...
    nnz(~directionAssigned & keep & ~isnan(direction)));
if options.directionRule ~= "none"
    if summary.nDirectionAssigned > 0
        messages(end + 1) = sprintf("Scan 方向（Direction）が無い %d 行に、規則「%s」で 1・2 を付けました%s。", ...
            summary.nDirectionAssigned, ruleLabels(ruleNames == options.directionRule), ...
            ternary(options.invertDirection, "（1 と 2 を入れ替え）", ""));
    else
        messages(end + 1) = "Direction の列にすべて値があるので、Scan 方向を付ける規則は使いませんでした。";
    end
end
if hasMarkNo && any(isnan(markNo) & keep)
    error('alignest:markNo', 'markNo が空の行が %d 行あります。値を入れるか、markNo の対応を「（なし）」にしてください。', ...
        nnz(isnan(markNo) & keep));
end
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

unitKey(~keep) = missing;
[unitKeys, ~, unitOfRow] = unique(unitKey(keep), 'stable');
rowsKept = find(keep);
nUnits = numel(unitKeys);
if nUnits == 0
    error('alignest:noData', '解析できる行がありません。座標の列・有効半径・入力行の除外条件を確かめてください。');
end
waferOfUnit = strings(nUnits, 1);
for u = 1:nUnits
    waferOfUnit(u) = wafer(rowsKept(find(unitOfRow == u, 1)));
end
nShotSizeGuessed = 0;
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
    marks.shotColumn = shotColumn(pick);
    marks.x = x(pick);
    marks.y = y(pick);
    marks.r = r(pick);
    marks.measX = meanX;
    marks.measY = meanY;
    marks.validX = anyX;
    marks.validY = anyY;
    marks.attributes = attributes(pick, :);
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
    shots.column = marks.shotColumn(firstOfShot);
    if hasShotNo
        shots.shotNo = shotNo(pick(firstOfShot));
    else
        shots.shotNo = (1:nShots).';
    end
    % 画面で変えた Scan 方向（shotNo ごと）
    [overridden, position] = ismember(shots.shotNo, overrideShots);
    for s = find(overridden).'
        marks.direction(shotOfMark == s) = overrideValues(position(s));
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
    units(u).operation = operation(rows(1));
    units(u).eqpId = eqpId(rows(1));
    units(u).lotId = lotId(rows(1));
    units(u).attributeNames = attributeNames;
    units(u).wafer = waferOfUnit(u);
    units(u).dateTime = dateTime(rows(1));
    units(u).label = waferOfUnit(u);
    units(u).marks = marks;
    units(u).shots = shots;
    units(u).hasDirection = hasDirection && all(~isnan(marks.direction));
    [units(u).shotSizeMm, estimated] = alignest.shotSize(shots.Xmm, shots.Ymm, marks.markXmm, marks.markYmm);
    nShotSizeGuessed = nShotSizeGuessed + ~all(estimated);
    if hasShotNo && numel(unique(shots.shotNo)) < nShots
        messages(end + 1) = sprintf("%s：同じ shotNo が別の座標の Shot に付いています。手動の指定では最初の Shot を使います。", ...
            units(u).label); %#ok<AGROW>
    end
end
% 表示名：Operation・EqpId・LotID がデータの中で2種類以上あれば、Wafer ID にその値を付ける
% （同じ Wafer ID でも工程・装置が違えば別の計測なので、選ぶときに区別できるように）。それでも重なれば日時も付ける
labelFields = ["lotId", "operation", "eqpId"];
varying = arrayfun(@(field) numel(unique(arrayfun(@(unit) string(unit.(field)), units))) > 1, labelFields);
for u = 1:nUnits
    parts = strings(1, 0);
    for field = labelFields(varying)
        parts(end + 1) = emptyAsDash(units(u).(field)); %#ok<AGROW>
    end
    same = find(waferOfUnit == waferOfUnit(u));
    if numel(same) > 1 && numel(unique(arrayfun(@(k) string(units(k).dateTime), same))) > 1
        parts(end + 1) = emptyAsDash(units(u).dateTime); %#ok<AGROW>
    end
    if ~isempty(parts)
        units(u).label = waferOfUnit(u) + " (" + strjoin(parts, " / ") + ")";
    end
end
if nShotSizeGuessed > 0
    messages(end + 1) = sprintf(['%d 枚では隣り合う Shot が無い向きがあり、Shot の大きさを Mark の広がりから仮に決めました' ...
        '（Shot の枠の表示だけに使います）。'], nShotSizeGuessed);
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
summary.nDirectionOverrides = numel(overrideShots);
if ~isempty(overrideShots)
    messages(end + 1) = "画面で Scan 方向を変えた Shot（すべての Wafer の同じ shotNo）：" + ...
        strjoin(compose("%g→%d", overrideShots, overrideValues), "、") + "。";
end
summary.operations = unique(operation(keep & operation ~= "")).';
summary.eqpIds = unique(eqpId(keep & eqpId ~= "")).';
summary.lotIds = unique(lotId(keep & lotId ~= "")).';
summary.attributeNames = attributeNames;
shotSizes = vertcat(units.shotSizeMm);
summary.shotSizeRangeMm = [min(shotSizes, [], 1); max(shotSizes, [], 1)];
messages(end + 1) = "Shot 行は、Wafer・測定日時ごとに入力の Ymm を上から数えます（0.001 mm 刻み、半径・入力行の除外前）。1=奇数行、2=偶数行。入力にない行は数えません。";
summary.messages = messages;
data.units = units;
data.summary = summary;
data.validRadiusMm = options.validRadiusMm;
data.coordinateUnits = inputUnits;
data.excludeZeroMeasurements = options.excludeZeroMeasurements;
data.excludeUnmeasuredRecords = options.excludeUnmeasuredRecords;
data.attributeNames = attributeNames;
data.directionRule = options.directionRule;
data.directionOverrideShots = reshape(overrideShots, 1, []);
data.directionOverrideValues = reshape(overrideValues, 1, []);
data.invertDirection = options.invertDirection;
end

function [direction, assigned] = assignDirection(direction, usable, options, shotNo, hasShotNo, shotRow, shotColumn, unitKey)
% Direction が空の行に、規則で Scan 方向（1・2）を付ける
assigned = false(size(direction));
if options.directionRule == "none"
    return
end
blank = isnan(direction) & usable;
if ~any(blank)
    return
end
switch options.directionRule
    case "serpentine"
        values = nan(size(direction));
        for key = unique(unitKey(usable)).'
            rows = find(unitKey == key & usable);
            values(rows) = serpentineDirections(shotRow(rows), shotColumn(rows), shotNo(rows), hasShotNo);
        end
    case "shotNoParity"
        if ~hasShotNo || any(isnan(shotNo(blank)))
            error('alignest:directionRule', ['shotNo の奇偶で Scan 方向を付けるには、shotNo の列を対応づけ、' ...
                'すべての行に値を入れてください。または別の規則を選んでください。']);
        end
        values = 1 + mod(round(shotNo) - 1, 2);
    case "rowParity"
        values = 1 + mod(shotRow - 1, 2);
    case "columnParity"
        values = 1 + mod(shotColumn - 1, 2);
    case "checkerboard"
        values = 1 + mod(shotRow + shotColumn, 2);
end
if options.invertDirection
    values = 3 - values;
end
direction(blank) = values(blank);
assigned = blank;
end

function values = serpentineDirections(shotRow, shotColumn, shotNo, hasShotNo)
% 一筆書きの Scan 方向（1つの Wafer・計測の行ごと）。shotNo が最も小さい Shot から始め、その行を始めの Shot に近い端から
% 遠い端へたどり、次の行（始めの行から遠ざかる向き）は逆向きにたどる（行ごとに折り返す）。道順に 1・2 を交互に付ける。
% shotNo が無いときは、いちばん上の行の左端から始める。始めの Shot が行の途中・行が途中のときは、残りを後で同じ規則でたどる。
[cells, ~, cellOfRow] = unique([shotRow(:), shotColumn(:)], 'rows');   % Shot ごと（行・列の番号）。上の行・左の列が先
start = 1;
if hasShotNo && any(isfinite(shotNo))
    cellNo = inf(size(cells, 1), 1);
    for k = find(isfinite(shotNo(:))).'
        cellNo(cellOfRow(k)) = min(cellNo(cellOfRow(k)), shotNo(k));
    end
    [~, start] = min(cellNo);
end
rowList = unique(cells(:, 1));
startRow = cells(start, 1);
before = flipud(rowList(rowList < startRow));
after = rowList(rowList > startRow);
if numel(after) >= numel(before)
    rowOrder = [startRow; after; before];
else
    rowOrder = [startRow; before; after];
end
pathIndex = zeros(size(cells, 1), 1);
step = 0;
ascending = true;
for k = 1:numel(rowOrder)
    inRow = find(cells(:, 1) == rowOrder(k));
    columns = cells(inRow, 2);
    if k == 1
        % 始めの Shot から、近い端と反対の端へ向かう
        startColumn = cells(start, 2);
        ascending = startColumn - min(columns) <= max(columns) - startColumn;
        if ascending
            order = [sortedBy(inRow, columns, columns >= startColumn, 'ascend'); ...
                sortedBy(inRow, columns, columns < startColumn, 'descend')];
        else
            order = [sortedBy(inRow, columns, columns <= startColumn, 'descend'); ...
                sortedBy(inRow, columns, columns > startColumn, 'ascend')];
        end
    else
        ascending = ~ascending;   % 行ごとに折り返す
        [~, sortKey] = sort(columns);
        order = inRow(sortKey);
        if ~ascending
            order = flipud(order);
        end
    end
    pathIndex(order) = step + (1:numel(order));
    step = step + numel(order);
end
values = 1 + mod(pathIndex(cellOfRow) - 1, 2);
end

function index = sortedBy(index, keys, select, direction)
% index のうち select の要素を、keys の順（direction）に並べる
[~, order] = sort(keys(select), direction);
index = index(select);
index = index(order);
end

function text = emptyAsDash(value)
text = string(value);
if text == ""
    text = "—";
end
end

function source = directionSource(hasColumn, nAssigned, nFromFile)
% Scan 方向がどこから来たか（画面と Excel の説明に出す）
if nAssigned > 0 && hasColumn && nFromFile > 0
    source = "ファイルの列と規則による付与";
elseif nAssigned > 0
    source = "規則による付与";
elseif hasColumn
    source = "ファイルの列";
else
    source = "なし";
end
end

function value = ternary(condition, whenTrue, whenFalse)
if condition
    value = whenTrue;
else
    value = whenFalse;
end
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

function [names, values] = otherColumns(raw, mapping)
% 標準の項目に対応づけなかった列（質的変数の候補）を、行ごとの文字列にする（空・欠けは ""）
mapped = string(struct2cell(mapping));
names = string(raw.Properties.VariableNames);
names = names(~ismember(names, mapped(mapped ~= "")));
values = strings(height(raw), numel(names));
for k = 1:numel(names)
    column = raw.(names(k));
    if isnumeric(column) || islogical(column)
        text = string(column);
        text(isnan(double(column))) = "";  % 数値の欠け（NaN）は水準にしない
    elseif iscell(column)
        text = string(cellfun(@cellText, column, 'UniformOutput', false));
    else
        text = defaultText(column, height(raw), "");
    end
    text(ismissing(text)) = "";
    values(:, k) = strtrim(text(:));
end
end

function text = cellText(value)
% 型の混ざった列（readtable がセル配列で返す列）の1つの値を文字列にする
if isempty(value) || (isnumeric(value) && isscalar(value) && isnan(value))
    text = "";
elseif isdatetime(value)
    text = string(value, 'yyyy/MM/dd HH:mm:ss');
else
    text = string(value);
    if ~isscalar(text)
        text = strjoin(text(:).', " ");
    end
end
end

function unit = emptyUnit()
unit = struct("operation", "", "eqpId", "", "lotId", "", "attributeNames", strings(1, 0), "wafer", "", "dateTime", "", "label", "", "marks", struct(), "shots", struct(), ...
    "hasDirection", false, "shotSizeMm", [NaN, NaN]);
end
