function updateRegressionEnabled(regression)
%UPDATEREGRESSIONENABLED 「③ 回帰」の欄：Huber のときだけ c、正則化をかけるときだけ λ と次数を使えるようにする（X・Y それぞれ）。
for a = 1:2
    regression.huber(a).Enable = onOff(string(regression.loss(a).Value) == "huber");
    regularized = string(regression.regularization(a).Value) ~= "none";
    regression.lambda(a).Enable = onOff(regularized);
    set(regression.orders(a, :), 'Enable', onOff(regularized));
end
end
