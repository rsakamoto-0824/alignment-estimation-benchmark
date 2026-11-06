function options = setRegressionControls(regression, options)
%SETREGRESSIONCONTROLS 名前と値の組の回帰の項目を「③ 回帰」の欄に入れ、残りの項目を返す。loss・huberTuning・regularization・
%   lambda は値が1つなら X・Y 両方、[X, Y] なら軸ごと。penaltyOrders は X・Y 両方、penaltyOrdersY は Y だけ。
fields = struct("loss", regression.loss, "huberTuning", regression.huber, "regularization", regression.regularization, ...
    "lambda", regression.lambda);
for name = string(fieldnames(fields)).'
    if ~isfield(options, name)
        continue
    end
    values = reshape(options.(name), 1, []);
    if isscalar(values)
        values = [values, values];
    end
    if numel(values) ~= 2
        error('alignest:regressionAxes', '%s は1つ（X・Y で同じ）か [X, Y] の2つで渡してください。', name);
    end
    for a = 1:2
        if isstring(values)
            control = fields.(name)(a);
            if ~any(strcmp(control.ItemsData, char(values(a))))
                error('alignest:regressionAxes', '%s に「%s」は選べません。', name, values(a));
            end
            control.Value = char(values(a));
        else
            fields.(name)(a).Value = values(a);
        end
    end
    options = rmfield(options, name);
end
if isfield(options, "penaltyOrders")
    for order = 1:size(regression.orders, 2)
        regression.orders(1, order).Value = any(options.penaltyOrders == order);
        regression.orders(2, order).Value = any(options.penaltyOrders == order);
    end
    options = rmfield(options, "penaltyOrders");
end
if isfield(options, "penaltyOrdersY")
    for order = 1:size(regression.orders, 2)
        regression.orders(2, order).Value = any(options.penaltyOrdersY == order);
    end
    options = rmfield(options, "penaltyOrdersY");
end
end
