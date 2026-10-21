function overlay = shotOverlay(units, unitIndex, waferOrder, waferRadiusMm, direction)
%SHOTOVERLAY 選んだ Wafer のすべての Shot を、Shot 内の座標（markXmm・markYmm）で重ね合わせる。
%   overlay = alignest.shotOverlay(units, unitIndex, waferOrder, waferRadiusMm)
%   overlay = alignest.shotOverlay(units, unitIndex, waferOrder, waferRadiusMm, direction)
%   direction（Scan 方向、1 または 2）を指定すると、その Scan 方向の Mark だけを重ねる（NaN・省略ならすべて）。
%   各 Mark の計測値（その軸が無効な点は NaN）を Shot 内の座標に置き、Mark の位置ごとに Shot・Wafer 間で
%   平均と共分散を求める（alignest.averageFields）。
%   waferOrder > 0 なら、Wafer ごとに Wafer 成分（Shot 中心の座標の waferOrder 次の多項式、X・Y 別の最小二乗）を
%   除いてから重ねる（Shot 内の成分を見やすくするため。補正の当てはめは alignest.overlayProjector と同じ）。
%   overlay.points・values：重ねる前の Mark ごとの Shot 内の座標と値（Wafer ごとのセル配列）
%   overlay.average：Mark の位置ごとの平均・共分散・数。overlay.markLabels：位置ごとの markNo（多いもの）
%   overlay.shotSizeMm：最初の Wafer の Shot の大きさ。overlay.nShots・nWafers：重ねた Shot・Wafer の数
%   Wafer 成分は Scan 方向で分ける前に、その Wafer のすべての Mark で当てはめる（Scan 方向どうしを同じ基準で比べるため）。
MAX_WAFER_ORDER = 5;
if nargin < 5
    direction = NaN;
end
if ~isscalar(waferOrder) || ~any(waferOrder == 0:MAX_WAFER_ORDER)
    error('alignest:overlayModel', 'Wafer 成分の次数は 0〜%d の整数にしてください。', MAX_WAFER_ORDER);
end
if isempty(unitIndex)
    error('alignest:shotOverlay', '重ね合わせる Wafer を1枚以上選んでください。');
end
points = cell(1, numel(unitIndex));
values = cell(1, numel(unitIndex));
marksAll = cell(1, numel(unitIndex));
nShots = 0;
for k = 1:numel(unitIndex)
    unit = units(unitIndex(k));
    marks = unit.marks;
    measured = [marks.measX, marks.measY];
    measured(~marks.validX, 1) = NaN;
    measured(~marks.validY, 2) = NaN;
    if waferOrder > 0
        choice = struct("waferOrder", waferOrder, "shotCommon", "none", "perShot", "none");
        projector = alignest.overlayProjector(unit, choice, waferRadiusMm);
        axisNames = ["X", "Y"];
        for axisIndex = 1:2
            part = projector.(axisNames(axisIndex));
            index = part.index;
            measured(index, axisIndex) = measured(index, axisIndex) - part.basis * (part.basis.' * measured(index, axisIndex));
        end
    end
    usable = any(isfinite(measured), 2) & (isnan(direction) | marks.direction == direction);
    points{k} = [marks.markXmm(usable), marks.markYmm(usable)];
    values{k} = measured(usable, :);
    marksAll{k} = marks.markNo(usable);
    nShots = nShots + numel(unique(marks.shotIndex(usable)));
end
if all(cellfun(@isempty, points))
    scope = "";
    if ~isnan(direction)
        scope = sprintf("Scan 方向 %g の", direction);
    end
    error('alignest:shotOverlay', '選んだ Wafer に%s有効な Mark がありません。', scope);
end
overlay.points = points;
overlay.values = values;
overlay.average = alignest.averageFields(points, values);
% Mark の位置ごとの markNo（同じ位置で番号が違う Shot があれば多いほう）
allPoints = round(vertcat(points{:}), 3);
allMarks = vertcat(marksAll{:});
[~, position] = ismember(allPoints, round(overlay.average.points, 3), 'rows');
overlay.markLabels = accumarray(position, allMarks, [size(overlay.average.points, 1), 1], @mode);
overlay.shotSizeMm = units(unitIndex(1)).shotSizeMm;
overlay.nShots = nShots;
overlay.nWafers = numel(unitIndex);
overlay.waferOrder = waferOrder;
overlay.direction = direction;
end
