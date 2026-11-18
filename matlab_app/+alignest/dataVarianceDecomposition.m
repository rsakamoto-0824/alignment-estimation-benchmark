function result = dataVarianceDecomposition(units, eqpId, spec)
%DATAVARIANCEDECOMPOSITION 読み込んだ計測値のばらつき分解（「1. データ読込」の「ばらつき分解」）。
%   result = alignest.dataVarianceDecomposition(units)
%   result = alignest.dataVarianceDecomposition(units, eqpId, spec)
%   units：計測データの Wafer（alignest.prepareData の data.units）。eqpId：使う装置（EqpId の値。"" ならすべての装置）。
%   spec：値の種類（alignest.valueSpec。1変数なら X の列だけを、値の名前で分ける）。
%   棒は Operation ごと（Operation の列に値が無ければ「すべて」の1本）。値は有効な計測値（measX・measY。除いた点・Sts が
%   無効な点は使わない）。Lot は LotID、Wafer は計測（Operation × EqpId × LotID × Wafer × DateTime。同じ Wafer の別の計測は
%   別の Wafer として数える）、Scan 方向は Direction（「Scan 方向の付与」の規則も含む）、Shot は Shot（alignest.varianceDecomposition）。
%   Lot 間は選んだ計測に Lot が2つ以上あるとき、Scan 方向間は Scan 方向の分かる点があるときだけ分ける。
%   result：alignest.varianceDecomposition の結果に、eqpIds（データの装置の一覧）・eqpId（使った装置）・nUnits（使った計測の数）・
%   hasOperation（Operation ごとに分けたか）・unitLabel（値の単位）を足したもの
arguments
    units struct
    eqpId (1, 1) string = ""
    spec struct = alignest.valueSpec(struct())
end
ALL_CATEGORY = "すべて";
eqpIds = unique(string({units.eqpId}));
eqpIds = reshape(eqpIds(eqpIds ~= ""), 1, []);
chosen = units;
if eqpId ~= ""
    chosen = units(string({units.eqpId}) == eqpId);
    if isempty(chosen)
        error('alignest:varianceDecomposition', '装置「%s」の計測がありません。', eqpId);
    end
end
operations = string({chosen.operation});
hasOperation = any(operations ~= "");
parts = cell(numel(chosen), 1);
for u = 1:numel(chosen)
    marks = chosen(u).marks;
    n = numel(marks.x);
    valueX = marks.measX;
    valueY = marks.measY;
    valueX(~marks.validX) = NaN;
    valueY(~marks.validY) = NaN;
    categoryName = ALL_CATEGORY;
    if hasOperation
        categoryName = string(chosen(u).operation);
    end
    parts{u} = table(repmat(categoryName, n, 1), repmat(string(chosen(u).lotId), n, 1), ...
        repmat(string(u), n, 1), double(marks.direction(:)), double(marks.shotIndex(:)), valueX(:), valueY(:), ...
        'VariableNames', ["category", "lot", "wafer", "scan", "shot", "valueX", "valueY"]);
end
points = vertcat(parts{:});
categories = unique(points.category, 'stable');
if spec.scalar
    result = alignest.varianceDecomposition(points, valueColumns="valueX", axisNames=spec.name, ...
        categories=reshape(categories, 1, []));
    result.unitLabel = spec.unit;
else
    result = alignest.varianceDecomposition(points, categories=reshape(categories, 1, []));
    result.unitLabel = "nm";
end
result.eqpIds = eqpIds;
result.eqpId = eqpId;
result.nUnits = numel(chosen);
result.hasOperation = hasOperation;
end
