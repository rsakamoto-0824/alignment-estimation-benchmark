function values = continuousFeatures(unit, marks, columns, waferRadiusMm)
%CONTINUOUSFEATURES 説明変数に足す連続値の列（設定 methods.continuousColumns）の、点ごとの値（点 × 列）。
%   values = alignest.continuousFeatures(unit, marks, columns, waferRadiusMm)
%   列の値（数として読めるその他の列。alignest.numericColumns）を、その Wafer の点で平均 0・標準偏差を座標（x・y を Wafer
%   半径で割った値）の標準偏差にそろえる（距離で比べる手法で、座標と同じくらいの重みにするため）。
%   値の無い点（空欄・数でない値、未知の座標の推定で足した点）は平均（0）にする。値がすべて同じ・2点未満の列は 0。
arguments
    unit struct
    marks struct
    columns string
    waferRadiusMm (1, 1) double {mustBePositive}
end
columns = reshape(columns, 1, []);
values = zeros(numel(marks.x), numel(columns));
if isempty(columns)
    return
end
scale = std([marks.x; marks.y] / waferRadiusMm);
for k = 1:numel(columns)
    position = find(string(unit.attributeNames) == columns(k), 1);
    if isempty(position)
        error('alignest:continuousColumn', '説明変数に選んだ連続値の列「%s」が、読み込んだデータにありません。', columns(k));
    end
    raw = str2double(marks.attributes(:, position));
    known = isfinite(raw);
    if nnz(known) < 2
        continue
    end
    spread = std(raw(known));
    if ~(spread > 0)
        continue
    end
    column = (raw - mean(raw(known))) / spread * scale;
    column(~known) = 0;
    values(:, k) = column;
end
end
