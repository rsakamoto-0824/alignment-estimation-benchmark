function value = jsDivergence(first, second, edges)
%JSDIVERGENCE 2つの値の集まりの分布の Jensen–Shannon ダイバージェンス（底 2。0 = 同じ分布 〜 1 = 重なりなし）。
%   value = alignest.stats.jsDivergence(first, second, edges)
%   共通の区間 edges でヒストグラムにして割合 P・Q にし、M = (P + Q) / 2 として
%   JS = KL(P‖M) / 2 + KL(Q‖M) / 2（KL は log2、0·log 0 = 0）を求める。区間の外の値は数えない。
%   値の数が違ってもよい（割合で比べる）。どちらかに区間内の値が無ければ NaN。区間の取り方で値が少し変わる。
first = first(isfinite(first));
second = second(isfinite(second));
p = histcounts(first, edges);
q = histcounts(second, edges);
value = NaN;
if sum(p) == 0 || sum(q) == 0
    return
end
p = p / sum(p);
q = q / sum(q);
m = (p + q) / 2;
value = (klTerm(p, m) + klTerm(q, m)) / 2;
value = min(max(value, 0), 1);   % 丸めの誤差で範囲の外に出ないように
end

function value = klTerm(p, m)
used = p > 0;
value = sum(p(used) .* log2(p(used) ./ m(used)));
end
