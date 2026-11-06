function regressionToControls(regression, options)
%REGRESSIONTOCONTROLS 回帰の設定（alignest.highOrderOptions などの [X, Y] の並び）を「③ 回帰」の欄に写す。
orderLists = {options.penaltyOrders, options.penaltyOrdersY};
for a = 1:2
    regression.loss(a).Value = char(options.loss(a));
    regression.huber(a).Value = options.huberTuning(a);
    regression.regularization(a).Value = char(options.regularization(a));
    regression.lambda(a).Value = options.lambda(a);
    for order = 1:size(regression.orders, 2)
        regression.orders(a, order).Value = any(orderLists{a} == order);
    end
end
updateRegressionEnabled(regression);
end
