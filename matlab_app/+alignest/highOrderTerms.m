function terms = highOrderTerms(maker, excludedTerms)
%HIGHORDERTERMS Shot 高次補正の式の項（k パラメータ）の表。どの項を使うか（excludedTerms で外した項）も持つ。
%   terms = alignest.highOrderTerms(maker)                 % すべての項を使う
%   terms = alignest.highOrderTerms(maker, excludedTerms)  % excludedTerms の k の番号の項は使わない
%   maker："asml"・"canon"・"nikon"（Shot 高次補正の式。alignest.overlayTerms。Canon・Nikon は Overlay 計測ルールの式
%   のまま、ASML は k1〜k19 のすべての項。式に無い項は足さない）、または "custom"（カスタム：k1〜k38 のすべての項から
%   使う項を選ぶ。番号の付け方は Canon・Nikon の式と同じで、次数の低い順に、dx（奇数の k）は x^n, x^(n−1)·y, …, y^n、
%   dy（偶数の k）は y^n, x·y^(n−1), …, x^n。例：k21 = x^4、k29 = y^4、k37 = x^2·y^3、k38 = x^3·y^2）。
%   terms は項ごとの表：axis（"dx"・"dy"）・k（係数の番号）・xPower・yPower（Shot 内の座標 x・y のべき）・order（次数）・
%   term（"1"・"x"・"x^2·y" など）・protected（k1〜k6 の並進・倍率・回転。外さない）・used（使う項）。
%   k1〜k6 は excludedTerms にあっても使う（補正の土台なので外さない）。式に無い番号は無視する。
arguments
    maker (1, 1) string
    excludedTerms double = zeros(1, 0)
end
LINEAR_ORDER = 1;   % これ以下の次数の項（k1〜k6）は外さない
CUSTOM_MAX_K = 38;  % カスタムの式で選べる k の番号の上限
if ~any(maker == ["asml", "canon", "nikon", "custom"])
    error('alignest:highOrderModel', 'Shot 高次補正の式は asml・canon・nikon・custom のいずれかです: %s', maker);
end
if maker == "custom"
    formula = customFormula(CUSTOM_MAX_K);
else
    formula = alignest.overlayTerms(maker);
end
parts = cell(2, 1);
axisNames = ["dx", "dy"];
for a = 1:2
    table_ = formula.(axisNames(a));
    n = size(table_, 1);
    order = table_(:, 2) + table_(:, 3);
    names = strings(n, 1);
    for k = 1:n
        names(k) = monomialName(table_(k, 2), table_(k, 3));
    end
    protected = order <= LINEAR_ORDER;
    used = protected | ~ismember(table_(:, 1), excludedTerms);
    parts{a} = table(repmat(axisNames(a), n, 1), table_(:, 1), table_(:, 2), table_(:, 3), order, names, protected, ...
        used, 'VariableNames', ["axis", "k", "xPower", "yPower", "order", "term", "protected", "used"]);
end
terms = vertcat(parts{:});
end

function formula = customFormula(maxK)
% カスタムの式：k1〜maxK のすべての項 [k, x のべき, y のべき]（alignest.overlayTerms と同じ形）
formula = struct("dx", zeros(0, 3), "dy", zeros(0, 3));
next = [1, 2];   % 次の dx・dy の k の番号
order = 0;
while any(next <= maxK)
    for j = 0:order
        if next(1) <= maxK
            formula.dx(end + 1, :) = [next(1), order - j, j];   % x^(n−j)·y^j
        end
        if next(2) <= maxK
            formula.dy(end + 1, :) = [next(2), j, order - j];   % x^j·y^(n−j)
        end
        next = next + 2;
    end
    order = order + 1;
end
end

function name = monomialName(xPower, yPower)
% 項の名前（定数は "1"。alignest.overlayDesign と同じ書き方）
parts = strings(0, 1);
if xPower == 1
    parts(end + 1) = "x";
elseif xPower > 1
    parts(end + 1) = "x^" + xPower;
end
if yPower == 1
    parts(end + 1) = "y";
elseif yPower > 1
    parts(end + 1) = "y^" + yPower;
end
if isempty(parts)
    name = "1";
else
    name = strjoin(parts, "·");
end
end
