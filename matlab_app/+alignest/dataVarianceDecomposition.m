function result = dataVarianceDecomposition(units, eqpId, spec, kind)
%DATAVARIANCEDECOMPOSITION 読み込んだ計測値のばらつき分解（「1. データ読込」の「ばらつき分解」）。
%   result = alignest.dataVarianceDecomposition(units)
%   result = alignest.dataVarianceDecomposition(units, eqpId, spec)
%   result = alignest.dataVarianceDecomposition(units, eqpId, spec, kind)
%   units：計測データの Wafer（alignest.prepareData の data.units）。eqpId：使う装置（EqpId の値。"" ならすべての装置）。
%   spec：値の種類（alignest.valueSpec。1変数なら X の列だけを、値の名前で分ける）。kind：分け方。"nested"（既定。Lot 間・
%   Wafer 間・Shot 間・その他。alignest.varianceDecomposition）・"components"（全体 Shift・Wafer 倍率・回転・その他・Shot 倍率・
%   回転・その他。Shot 中心は Xmm・Ymm、Shot 内の座標は markXmm・markYmm。alignest.componentVarianceDecomposition）。
%   棒は Operation ごと（Operation の列に値が無ければ「すべて」の1本）。値は有効な計測値（measX・measY。除いた点・Sts が
%   無効な点は使わない）。Lot は LotID、Wafer は計測（Operation × EqpId × LotID × Wafer × DateTime。同じ Wafer の別の計測は
%   別の Wafer として数える）、Shot は Shot（alignest.varianceDecomposition）。Lot 間は選んだ計測に Lot が2つ以上あるときだけ分ける。
%   result：alignest.varianceDecomposition の結果に、eqpIds（データの装置の一覧）・eqpId（使った装置）・nUnits（使った計測の数）・
%   hasOperation（Operation ごとに分けたか）・unitLabel（値の単位）を足したもの
arguments
    units struct
    eqpId (1, 1) string = ""
    spec struct = alignest.valueSpec(struct())
    kind (1, 1) string {mustBeMember(kind, ["nested", "components"])} = "nested"
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
        repmat(string(u), n, 1), double(marks.shotIndex(:)), valueX(:), valueY(:), double(marks.Xmm(:)), ...
        double(marks.Ymm(:)), double(marks.markXmm(:)), double(marks.markYmm(:)), ...
        'VariableNames', ["category", "lot", "wafer", "shot", "valueX", "valueY", "shotX", "shotY", "localX", "localY"]);
end
points = vertcat(parts{:});
categories = unique(points.category, 'stable');
decompose = @alignest.varianceDecomposition;
if kind == "components"
    decompose = @alignest.componentVarianceDecomposition;
end
if spec.scalar
    result = decompose(points, valueColumns="valueX", axisNames=spec.name, categories=reshape(categories, 1, []));
    result.unitLabel = spec.unit;
else
    result = decompose(points, categories=reshape(categories, 1, []));
    result.unitLabel = "nm";
end
result.eqpIds = eqpIds;
result.eqpId = eqpId;
result.nUnits = numel(chosen);
result.hasOperation = hasOperation;
end
