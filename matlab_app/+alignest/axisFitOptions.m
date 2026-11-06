function fits = axisFitOptions(options)
%AXISFITOPTIONS 回帰の設定（X・Y 別）を、軸ごとの回帰の条件にする（alignest.highOrderOptions・alignest.markLayoutOptions の結果）。
%   fits = alignest.axisFitOptions(options)
%   fits(1) は X（dx の式）、fits(2) は Y（dy の式）。options：alignest.robustRidgeFit の名前と値の組（loss・huberTuning・
%   penalty）、lambda：正則化の強さ（正則化なしなら 0）、orders：正則化をかける項の次数。
fits = struct("options", cell(1, 2), "lambda", cell(1, 2), "orders", cell(1, 2));
for a = 1:2
    penaltyType = "l2";
    if options.regularization(a) == "l1"
        penaltyType = "l1";
    end
    fits(a).options = {'loss', options.loss(a), 'huberTuning', options.huberTuning(a), 'penalty', penaltyType};
    fits(a).lambda = options.lambda(a) * (options.regularization(a) ~= "none");
    fits(a).orders = options.penaltyOrders;
    if a == 2
        fits(a).orders = options.penaltyOrdersY;
    end
end
end
