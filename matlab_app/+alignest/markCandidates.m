function [candidates, shots] = markCandidates(wafers, coordinates, required)
%MARKCANDIDATES 「8. Mark配置の最適化」の候補の Mark（Shot 内の位置）と、Shot ごとの値を作る。
%   [candidates, shots] = alignest.markCandidates(wafers)                 % 計測データの点から
%   [candidates, shots] = alignest.markCandidates([], coordinates)        % 座標だけ（画面で入力した座標。値は無い）
%   [candidates, shots] = alignest.markCandidates(..., required)          % 必ず計測する Mark の座標（点の数 × 2 [mm]）
%   wafers：alignest.shotHighOrder と同じ Wafer ごとの構造体の配列（label・points。points は localX・localY（Shot 内の座標
%   [mm]）・shotNo・valueX・valueY（値の無い点は NaN）の列を使う）。coordinates：候補の Mark の Shot 内の座標（点の数 × 2 [mm]）。
%   同じ位置（Shot 内の座標を mm の小数点以下 POSITION_DIGITS 桁で丸めて同じ）は1つの候補にまとめる（同じ Shot で同じ位置の
%   点が2つ以上あれば値は平均）。候補の番号は、上の行（Y の大きい方）から、左（X の小さい方）から順に付ける。
%   candidates：候補ごとの表。no（番号）・xMm・yMm（Shot 内の座標 [mm]）・nShots（X か Y の値がある Shot の数。座標だけなら 0）・
%   required（必ず計測する Mark。required の座標と同じ位置）。
%   shots：Shot ごとの値。label（"Wafer の名前 Shot 番号"。Shot の数 × 1）・wafer・shotNo・valueX・valueY（候補の数 × Shot の数
%   [nm]。値の無い点は NaN）。X・Y のどちらの値も無い Shot は除く。座標だけなら Shot は 0。
arguments
    wafers
    coordinates double = zeros(0, 2)
    required double = zeros(0, 2)
end
POSITION_DIGITS = 4;   % 同じ位置とみなす Shot 内の座標の桁（mm の小数点以下。0.1 µm。alignest.highOrderVif と同じ）
shots = struct("label", strings(0, 1), "wafer", strings(0, 1), "shotNo", zeros(0, 1), "valueX", zeros(0, 0), ...
    "valueY", zeros(0, 0));
if isempty(wafers)
    if size(coordinates, 2) ~= 2 || any(~isfinite(coordinates(:)))
        error('alignest:markLayout', '候補の Mark の座標は、X・Y の2列の数で入れてください。');
    end
    local = round(coordinates, POSITION_DIGITS);
    rowLabels = strings(0, 1);
else
    parts = cell(numel(wafers), 1);
    labels = cell(numel(wafers), 1);
    for w = 1:numel(wafers)
        points = wafers(w).points;
        parts{w} = [points.localX, points.localY, points.shotNo, points.valueX, points.valueY];
        labels{w} = repmat(string(wafers(w).label), height(points), 1);
    end
    rows = vertcat(parts{:});
    rowLabels = vertcat(labels{:});
    keep = all(isfinite(rows(:, 1:3)), 2);
    rows = rows(keep, :);
    rowLabels = rowLabels(keep);
    local = round(rows(:, 1:2), POSITION_DIGITS);
end
if isempty(local)
    error('alignest:markLayout', '候補の Mark がありません（Shot 内の座標のある点がありません）。');
end
% 候補：上の行から、左から順に番号を付ける
positions = unique(local, 'rows');
positions = sortrows(positions, [-2, 1]);
[~, position] = ismember(local, positions, 'rows');
n = size(positions, 1);
isRequired = false(n, 1);
if ~isempty(required)
    isRequired = ismember(positions, round(required, POSITION_DIGITS), 'rows');
end
nShots = zeros(n, 1);
if ~isempty(rowLabels)
    % Shot（Wafer と shotNo の組）ごとの値。同じ Shot・同じ位置の点は平均
    [shotKeys, ~, shotIndex] = unique(table(rowLabels, rows(:, 3), 'VariableNames', ["wafer", "shotNo"]), 'stable');
    nShotsTotal = height(shotKeys);
    valueX = meanByCell(position, shotIndex, rows(:, 4), n, nShotsTotal);
    valueY = meanByCell(position, shotIndex, rows(:, 5), n, nShotsTotal);
    hasValue = any(isfinite(valueX), 1) | any(isfinite(valueY), 1);
    shotKeys = shotKeys(hasValue, :);
    shots.wafer = shotKeys.wafer;
    shots.shotNo = shotKeys.shotNo;
    shots.label = shotKeys.wafer + " Shot " + string(shotKeys.shotNo);
    shots.valueX = valueX(:, hasValue);
    shots.valueY = valueY(:, hasValue);
    nShots = sum(isfinite(shots.valueX) | isfinite(shots.valueY), 2);
end
candidates = table((1:n).', positions(:, 1), positions(:, 2), nShots, isRequired, 'VariableNames', ...
    ["no", "xMm", "yMm", "nShots", "required"]);
end

function means = meanByCell(position, shot, values, nPositions, nShots)
% 位置 × Shot ごとの値の平均（値の無い組は NaN）
valid = isfinite(values);
sums = accumarray([position(valid), shot(valid)], values(valid), [nPositions, nShots]);
counts = accumarray([position(valid), shot(valid)], 1, [nPositions, nShots]);
means = sums ./ counts;
means(counts == 0) = NaN;
end
