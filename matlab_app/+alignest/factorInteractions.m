function analysis = factorInteractions(data, options)
%FACTORINTERACTIONS 読み込んだ計測値で、質的変数の効果と交互作用を調べる（説明変数・カーネルを選ぶ判断材料）。
%   analysis = alignest.factorInteractions(data, unitIndex=..., trendOrder=3, columns=[...])
%   1. Wafer ごと・X・Y 別に、計測値から面内の傾向（Wafer 上の座標 x・y を Wafer 半径で割った値の多項式、
%      次数 trendOrder。0 なら平均だけ）を最小二乗で除き、残りを質的変数の効果を見る値にする。
%   2. 選んだ Wafer の値をまとめ、質的変数（Scan 方向・Mark 番号・Shot 行の奇偶と、columns のその他の列）ごとの
%      主効果（alignest.stats.anovaMainEffects）と、2つずつの組の交互作用（alignest.stats.interactionTests）を調べる。
%   3. 判定：p < SIGNIFICANCE かつ 効果量（主効果は η²、交互作用は偏 η²）≥ MIN_EFFECT なら「あり」。点が多いと
%      小さな差でも p が小さくなるので、効果量でも判定する。結果から手法の選び方の目安（advice）を作る。
%   analysis.main：軸・変数ごとの主効果の表（axis・factor・nLevels・F・p・etaSquared・verdict・levelSummary）
%   analysis.tests：軸・組ごとの交互作用の表（axis・factorA・factorB・n・FA・pA・FB・pB・F・df・p・partialEta2・
%     verdict・note）
%   analysis.cells：交互作用の図に使う水準の組の平均（axis を足した alignest.stats.interactionTests の cells）
%   analysis.advice：説明変数・カーネルの選び方の目安（文の並び）、ほかに nUnits・nPoints・trendOrder・axes。
arguments
    data struct
    options.unitIndex double = []
    options.trendOrder (1, 1) double {mustBeInteger, mustBeNonnegative} = 3
    options.columns string = strings(1, 0)
    options.waferRadiusMm (1, 1) double {mustBePositive} = 150
end
SIGNIFICANCE = 0.05;   % 有意水準
MIN_EFFECT = 0.01;     % 効果ありとみなす効果量（η²・偏 η²）の下限（点が多いときに小さな差を「あり」としないため）
MAX_TREND_ORDER = 5;
if options.trendOrder > MAX_TREND_ORDER
    error('alignest:trendOrder', '除く傾向の次数は 0〜%d にしてください。', MAX_TREND_ORDER);
end
unitIndex = options.unitIndex;
if isempty(unitIndex)
    unitIndex = 1:numel(data.units);
end
units = data.units(unitIndex);
axisNames = ["X", "Y"];
[mainParts, testParts, cellParts] = deal(cell(1, 2));
nPoints = zeros(1, 2);
for k = 1:2
    [values, factors] = pooledValues(units, axisNames(k), options);
    nPoints(k) = nnz(isfinite(values));
    if nPoints(k) == 0
        continue   % 1変数の Y 成分など、計測値の無い成分
    end
    main = alignest.stats.anovaMainEffects(values, factors);
    main.verdict = verdicts(main.p, main.etaSquared, main.note, SIGNIFICANCE, MIN_EFFECT, "効果あり");
    mainParts{k} = [table(repmat(axisNames(k), height(main), 1), 'VariableNames', "axis"), ...
        main(:, ["factor", "nLevels", "F", "p", "etaSquared", "verdict", "levelSummary"])];
    [tests, cells] = alignest.stats.interactionTests(values, factors);
    tests.verdict = verdicts(tests.p, tests.partialEta2, tests.note, SIGNIFICANCE, MIN_EFFECT, "交互作用あり");
    testParts{k} = [table(repmat(axisNames(k), height(tests), 1), 'VariableNames', "axis"), tests];
    cellParts{k} = [table(repmat(axisNames(k), height(cells), 1), 'VariableNames', "axis"), cells];
end
analysis.main = vertcatOrEmpty(mainParts);
analysis.tests = vertcatOrEmpty(testParts);
analysis.cells = vertcatOrEmpty(cellParts);
analysis.nUnits = numel(units);
analysis.nPoints = nPoints;
analysis.trendOrder = options.trendOrder;
analysis.axes = axisNames(nPoints > 0);
analysis.significance = SIGNIFICANCE;
analysis.minEffect = MIN_EFFECT;
analysis.advice = adviceLines(analysis);
end

function [values, factors] = pooledValues(units, axisName, options)
% Wafer ごとに面内の傾向を除いた値と、点ごとの質的変数の水準を、選んだ Wafer の分だけ縦に並べる
names = ["Scan 方向", "Mark 番号", "Shot 行の奇偶", "列「" + options.columns + "」"];
valueParts = cell(numel(units), 1);
levelParts = cell(numel(units), numel(names));
for u = 1:numel(units)
    marks = units(u).marks;
    measured = double(marks.("meas" + axisName));
    valid = marks.("valid" + axisName) & isfinite(measured);
    residual = nan(size(measured));
    if any(valid)
        design = alignest.basis.polynomialDesign(marks.x(valid) / options.waferRadiusMm, ...
            marks.y(valid) / options.waferRadiusMm, options.trendOrder);
        residual(valid) = measured(valid) - design * (pinv(design) * measured(valid));
    end
    valueParts{u} = residual;
    n = numel(measured);
    scan = strings(n, 1);
    if units(u).hasDirection
        scan(isfinite(marks.direction)) = string(marks.direction(isfinite(marks.direction)));
    end
    mark = strings(n, 1);
    mark(isfinite(marks.markNo)) = string(marks.markNo(isfinite(marks.markNo)));
    row = strings(n, 1);
    row(marks.shotRowParity == 1) = "奇数";
    row(marks.shotRowParity == 2) = "偶数";
    levelParts(u, 1:3) = {scan, mark, row};
    for c = 1:numel(options.columns)
        column = strings(n, 1);
        position = find(string(units(u).attributeNames) == options.columns(c), 1);
        if ~isempty(position)
            column = marks.attributes(:, position);
        end
        levelParts{u, 3 + c} = column;
    end
end
values = vertcat(valueParts{:});
factors = struct("name", cellstr(names), "levels", []);
for k = 1:numel(names)
    factors(k).levels = vertcat(levelParts{:, k});
end
end

function result = verdicts(p, effect, note, significance, minEffect, positive)
% 判定の文：p < 有意水準 かつ 効果量 ≥ 下限 なら「あり」、p だけ小さければ「有意だが小さい」
result = repmat("みられない", numel(p), 1);
result(p < significance & effect >= minEffect) = positive;
result(p < significance & ~(effect >= minEffect)) = sprintf("有意だが小さい（効果量 < %g）", minEffect);
result(isnan(p)) = "調べられない";
result(isnan(p) & note == "") = "—";
end

function lines = adviceLines(analysis)
% 説明変数（質的変数）と GPR のカーネル（質的変数の扱い）を選ぶ目安
lines = strings(0, 1);
main = analysis.main;
tests = analysis.tests;
if height(main) == 0
    lines = "計測値が無いので調べられません。";
    return
end
effective = unique(main.factor(main.verdict == "効果あり"), 'stable');
weak = setdiff(unique(main.factor(main.verdict ~= "調べられない" & main.verdict ~= "—"), 'stable'), effective, ...
    'stable');
interacting = tests(tests.verdict == "交互作用あり", :);
if ~isempty(effective)
    lines(end + 1, 1) = "効果のある質的変数：" + strjoin(effective, "・") + " → 質的変数（説明変数）に入れる候補です。";
end
if ~isempty(weak)
    lines(end + 1, 1) = "効果が小さい・みられない質的変数：" + strjoin(weak, "・") + ...
        " → 入れなくても推定はほぼ変わらない見込みです（入れると調べる手法が増えます）。";
end
if height(interacting) > 0
    pairs = unique(interacting.factorA + " × " + interacting.factorB, 'stable');
    lines(end + 1, 1) = "⚠ 交互作用あり：" + strjoin(pairs, "、") + " → GPR の質的変数の扱いで「同時推定＋交互作用」" + ...
        "「加法カーネル＋交互作用」「混合＋交互作用」も比べてください（交互作用の無い扱いでは組み合わせの差が残ります）。";
else
    lines(end + 1, 1) = "交互作用はみられません → 交互作用の無い扱い（同時推定・加法カーネル・混合・Backfitting・GAM）で" + ...
        "足りる見込みです。";
end
unclear = tests(tests.verdict == "調べられない", :);
if height(unclear) > 0
    lines(end + 1, 1) = "調べられない組：" + strjoin(unique(unclear.factorA + " × " + unclear.factorB, 'stable'), "、") + ...
        "（同じ分け方になる、または点の無い水準の組が多い）。";
end
lines(end + 1, 1) = sprintf(["判定：p < %g かつ 効果量（η²・偏 η²）≥ %g なら「あり」。値は Wafer ごとに面内の傾向" + ...
    "（XY 多項式 %d 次）を除いた計測値（Wafer %d 枚）。"], analysis.significance, analysis.minEffect, ...
    analysis.trendOrder, analysis.nUnits);
end

function merged = vertcatOrEmpty(parts)
parts = parts(~cellfun(@isempty, parts));
if isempty(parts)
    merged = table();
else
    merged = vertcat(parts{:});
end
end
