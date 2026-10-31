function data = highOrderMeasurementTable(result, wafers, value)
%HIGHORDERMEASUREMENTTABLE Shot 高次補正の点ごとの値（補正量・残差など）を、計測データと同じ列の表にする（「7. Shot高次補正」の
%   「書き出し」。書き出したファイルは「1. データの読み込み」や「Excel・CSV を読み込む…」でそのまま読み直せる）。
%   data = alignest.highOrderMeasurementTable(result, wafers, value)
%   result：alignest.shotHighOrder の結果、wafers：そのときの入力（label・unit。unit は alignest.prepareData の評価の単位。
%   無ければ Wafer は label、markNo は Shot 内の座標から付ける）、
%   value：書き出す値（alignest.highOrderValueColumns："residual"・"correction"・"linear"・"value"）。
%   列は Overlay 計測ルールの表の順：Operation・EqpId・LotID・Wafer・DateTime・shotNo・Direction・Xmm・Ymm（Shot 中心）・
%   Radius（Shot 中心の半径）・markNo・markXmm・markYmm（Shot 内の座標）・measX・measY（選んだ値 [nm]）・StsX・StsY
%   （値があれば 0、無ければ −1。無い値は空欄にし、0 にしない）。Wafer は評価の単位の Wafer ID（同じ単位を2回以上使う
%   未知の座標の推定値などでは、区別できるように画面の名前）。markNo は、計測データの点なら元の番号、ほかは Wafer ごとに
%   Shot 内の座標の組へ付けた番号。
arguments
    result struct
    wafers struct
    value (1, 1) string
end
UNMEASURED = -1;   % 値が無い点の Sts（Overlay 計測ルール：-1 は未測定）
POSITION_DIGITS = 4;   % 同じ Mark とみなす Shot 内の座標の桁（mm の小数点以下）
[columnX, columnY] = alignest.highOrderValueColumns(value);
labels = string({wafers.label});
units = cell(1, numel(wafers));   % 評価の単位（無ければ []。Wafer は画面の名前、markNo は座標から付ける）
if isfield(wafers, "unit")
    units = {wafers.unit};
end
keys = strings(1, numel(wafers));
for w = 1:numel(wafers)
    keys(w) = strjoin([textOf(units{w}, "operation"), textOf(units{w}, "eqpId"), textOf(units{w}, "lotId"), ...
        textOf(units{w}, "wafer"), textOf(units{w}, "dateTime")], "|");
end
parts = cell(numel(wafers), 1);
for w = 1:numel(wafers)
    unit = units{w};
    points = result.points(result.points.wafer == labels(w), :);
    n = height(points);
    waferId = textOf(unit, "wafer");
    if waferId == "" || nnz(keys == keys(w)) > 1
        waferId = labels(w);   % 同じ評価の単位を2回以上使う（推定値の学習データ違いなど）：画面の名前で区別する
    end
    markNo = [];
    if isfield(unit, "marks") && isfield(unit.marks, "markNo") && numel(unit.marks.markNo) == n && ...
            all(points.source == "計測値")
        markNo = double(unit.marks.markNo(:));
    end
    if isempty(markNo)
        [~, ~, markNo] = unique(round([points.localX, points.localY], POSITION_DIGITS), 'rows');
    end
    valueX = points.(columnX);
    valueY = points.(columnY);
    [stsX, stsY] = deal(zeros(n, 1));
    stsX(~isfinite(valueX)) = UNMEASURED;
    stsY(~isfinite(valueY)) = UNMEASURED;
    parts{w} = table(repmat(textOf(unit, "operation"), n, 1), repmat(textOf(unit, "eqpId"), n, 1), ...
        repmat(textOf(unit, "lotId"), n, 1), repmat(waferId, n, 1), repmat(textOf(unit, "dateTime"), n, 1), ...
        points.shotNo, points.direction, points.x - points.localX, points.y - points.localY, points.shotRadius, ...
        markNo, points.localX, points.localY, valueX, valueY, stsX, stsY, 'VariableNames', ["Operation", "EqpId", ...
        "LotID", "Wafer", "DateTime", "shotNo", "Direction", "Xmm", "Ymm", "Radius", "markNo", "markXmm", "markYmm", ...
        "measX", "measY", "StsX", "StsY"]);
end
data = vertcat(parts{:});
end

function text = textOf(unit, name)
% 評価の単位の文字の項目（無ければ ""）
text = "";
if isstruct(unit) && isfield(unit, name)
    text = string(unit.(name));
    if isempty(text) || ismissing(text)
        text = "";
    end
end
end
