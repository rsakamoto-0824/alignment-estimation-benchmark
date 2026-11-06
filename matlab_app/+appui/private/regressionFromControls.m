function values = regressionFromControls(regression)
%REGRESSIONFROMCONTROLS 「③ 回帰」の欄の値を設定の項目にする。X・Y が同じなら1つにまとめる（X・Y を分けないときと同じ設定になる）。
values.loss = sameOrPair(string({regression.loss.Value}));
values.huberTuning = sameOrPair([regression.huber.Value]);
values.regularization = sameOrPair(string({regression.regularization.Value}));
values.lambda = sameOrPair([regression.lambda.Value]);
orders = reshape([regression.orders.Value], size(regression.orders));
values.penaltyOrders = find(orders(1, :));
values.penaltyOrdersY = find(orders(2, :));
if isequal(values.penaltyOrders, values.penaltyOrdersY)
    values.penaltyOrdersY = -1;
end
end

function value = sameOrPair(pair)
value = pair;
if pair(1) == pair(2)
    value = pair(1);
end
end
