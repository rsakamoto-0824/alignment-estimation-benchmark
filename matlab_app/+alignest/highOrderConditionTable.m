function data = highOrderConditionTable(results, labels, value)
%HIGHORDERCONDITIONTABLE 「補正の比較」の条件ごとの点の値（補正量・残差など）を、1つの表に列を並べてまとめる（「7. Shot高次補正」
%   の「書き出し」）。
%   data = alignest.highOrderConditionTable(results, labels, value)
%   results：alignest.compareHighOrderConditions の2つ目の出力（条件ごとの結果。求められなかった条件は []）、labels：条件の
%   名前、value：alignest.highOrderValueColumns の値。行は点（どの条件も同じ点の並び）。列：Wafer・shotNo・Xmm・Ymm（Shot
%   中心）・markXmm・markYmm（Shot 内の座標）・範囲、補正前の値 X・Y と、条件ごとの値 X・Y（列の名前は「番号. 条件の名前：値の
%   名前X[nm]」）。求められなかった条件の列は書かない。
arguments
    results cell
    labels string
    value (1, 1) string
end
[columnX, columnY, valueLabel] = alignest.highOrderValueColumns(value);
done = find(~cellfun(@isempty, results));
if isempty(done)
    error('alignest:highOrderConditions', '書き出せる条件がありません（「補正の比較」で計算できた条件がありません）。');
end
points = results{done(1)}.points;
data = table(points.wafer, points.shotNo, points.x - points.localX, points.y - points.localY, points.localX, ...
    points.localY, points.zone, points.valueX, points.valueY, 'VariableNames', ["Wafer", "shotNo", "Xmm", "Ymm", ...
    "markXmm", "markYmm", "範囲", "補正前の値X[nm]", "補正前の値Y[nm]"]);
for c = reshape(done, 1, [])
    own = results{c}.points;
    if height(own) ~= height(points) || ~isequaln(own.shotNo, points.shotNo) || ~isequaln(own.x, points.x)
        error('alignest:highOrderConditions', '条件 %d の点が、ほかの条件と違います。', c);
    end
    prefix = sprintf("%d. %s：%s", c, labels(c), valueLabel);
    data.(prefix + "X[nm]") = own.(columnX);
    data.(prefix + "Y[nm]") = own.(columnY);
end
end
