function result = dataVarianceDecomposition(units, eqpId, spec, kind, column)
%DATAVARIANCEDECOMPOSITION 読み込んだ計測値のばらつき分解（「1. データ読込」の「ばらつき分解」）。
%   result = alignest.dataVarianceDecomposition(units)
%   result = alignest.dataVarianceDecomposition(units, eqpId, spec)
%   result = alignest.dataVarianceDecomposition(units, eqpId, spec, kind)
%   result = alignest.dataVarianceDecomposition(units, value, spec, kind, column)
%   units：計測データの Wafer（alignest.prepareData の data.units）。eqpId：使う装置（EqpId の値。"" ならすべての装置）。
%   column：絞り込む列（既定 "EqpId"。"LotID"・"Operation"、またはファイルのその他の列の名前）。2つ目の引数はその列の値
%   （"" ならすべて）。EqpId・LotID・Operation は計測（Wafer）ごと、その他の列は Mark ごとの値で絞り込む。
%   spec：値の種類（alignest.valueSpec。1変数なら X の列だけを、値の名前で分ける）。kind：分け方。"nested"（既定。Lot 間・
%   Wafer 間・Shot 間・その他。alignest.varianceDecomposition）・"components"（Wafer ごとの全体 Shift・Wafer 倍率・回転・
%   Shot 倍率・回転の回帰係数。Shot 中心は Xmm・Ymm、Shot 内の座標は markXmm・markYmm。alignest.componentCoefficients）。
%   棒は Operation ごと（Operation の列に値が無ければ「すべて」の1本）。値は有効な計測値（measX・measY。除いた点・Sts が
%   無効な点は使わない）。Lot は LotID、Wafer は計測（Operation × EqpId × LotID × Wafer × DateTime。同じ Wafer の別の計測は
%   別の Wafer として数える）、Shot は Shot（alignest.varianceDecomposition）。Lot 間は選んだ計測に Lot が2つ以上あるときだけ分ける。
%   result：alignest.varianceDecomposition（成分は alignest.componentCoefficients）の結果に、eqpIds（データの装置の一覧）・eqpId（使った装置）・nUnits（使った計測の数）・
%   hasOperation（Operation ごとに分けたか）・unitLabel（値の単位）を足したもの
arguments
    units struct
    eqpId (1, 1) string = ""
    spec struct = alignest.valueSpec(struct())
    kind (1, 1) string {mustBeMember(kind, ["nested", "components"])} = "nested"
    column (1, 1) string = "EqpId"
end
ALL_CATEGORY = "すべて";
eqpIds = unique(string({units.eqpId}));
eqpIds = reshape(eqpIds(eqpIds ~= ""), 1, []);
chosen = units;
unitFields = struct("EqpId", "eqpId", "LotID", "lotId", "Operation", "operation");
markColumn = ~isfield(unitFields, column);   % ファイルのその他の列（Mark ごとの値）で絞り込む
if eqpId ~= "" && ~markColumn
    chosen = units(string({units.(unitFields.(column))}) == eqpId);
    if isempty(chosen)
        error('alignest:varianceDecomposition', '%s「%s」の計測がありません。', columnLabel(column), eqpId);
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
    if markColumn && eqpId ~= ""
        % その他の列の値が違う Mark は使わない（値の無い点として扱う）
        position = find(chosen(u).attributeNames == column, 1);
        keep = false(n, 1);
        if ~isempty(position)
            keep = string(marks.attributes(:, position)) == eqpId;
        end
        valueX(~keep) = NaN;
        valueY(~keep) = NaN;
    end
    categoryName = ALL_CATEGORY;
    if hasOperation
        categoryName = string(chosen(u).operation);
    end
    parts{u} = table(repmat(categoryName, n, 1), repmat(string(chosen(u).lotId), n, 1), ...
        repmat(string(u), n, 1), repmat(string(chosen(u).label), n, 1), double(marks.shotIndex(:)), valueX(:), ...
        valueY(:), double(marks.Xmm(:)), double(marks.Ymm(:)), double(marks.markXmm(:)), double(marks.markYmm(:)), ...
        'VariableNames', ["category", "lot", "wafer", "waferLabel", "shot", "valueX", "valueY", "shotX", "shotY", ...
        "localX", "localY"]);
end
points = vertcat(parts{:});
if markColumn && eqpId ~= "" && ~any(isfinite(points.valueX) | isfinite(points.valueY))
    error('alignest:varianceDecomposition', '列「%s」が「%s」の計測値がありません。', column, eqpId);
end
categories = unique(points.category, 'stable');
decompose = @alignest.varianceDecomposition;
if kind == "components"
    decompose = @alignest.componentCoefficients;
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
result.filterColumn = column;   % 絞り込んだ列と値（"" ならすべて）
result.filterValue = eqpId;
result.nUnits = numel(chosen);
result.hasOperation = hasOperation;
end

function text = columnLabel(column)
% 知らせに出す列の名前
names = struct("EqpId", "装置", "LotID", "ロット", "Operation", "Operation");
text = column;
if isfield(names, column)
    text = names.(column);
end
end
