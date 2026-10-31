function specs = buildPlanSpecs(sampling)
%BUILDPLANSPECS 学習に使う Shot（Mark）の選び方の一覧（学習パターン）を作る。
%   sampling.method は選び方（複数選ぶと、選び方どうしを同じ評価の中で比べる）：
%     "ioptimal"（制約付き I 最適）："I最適 20 Shot" のように Shot 数ごとに1つ
%     "doptimal"（制約付き D 最適）："D最適 20 Shot" のように Shot 数ごとに1つ（det(M) を大きくする）
%     "random"（制約つきランダム）：Shot 数ごとに randomRepeats 回
%     "excel"（Excel ファイルで指定）：sampling.layoutPlans の1行（alignest.readLayoutPlans・parseLayoutPlans）ごとに、
%                パターン（pattern）は "名前（12 Shot）"・"名前（30 Mark）" の1つ（type "manual"）、優先順（priority）は
%                "名前 20 Shot" のように Shot 数（計測率）ごと（type "file"）。Mark 単位の優先順は、Mark 単位の計画と同じく
%                1 Shot あたりの Mark 数（markPerShot）・計測率ごと（"名前 1 点/Shot"）。spec.shotNos・markNos が
%                その順の Shot・Mark、spec.required が必ず計測する項目（中身は planTrainingShots）
%     以前の "manual"（手動・人の選択：manualPlans）・"file"（ファイルの優先順：priorityShots）は、
%     alignest.upgradeLayoutSettings で "excel" に直して使う（学習パターンの名前は以前と同じ）
%     "mark"（Mark 単位の I 最適）・"markd"（Mark 単位の D 最適）：計測する Shot ではなく Mark を選ぶ（既定では全 Shot で
%                1点以上。sampling.markRequirePerShot・markMinPerShot）。markPerShot（1 Shot あたりの平均の Mark 数）
%                ごとに1つ（"Mark最適 1 点/Shot"・"MarkD最適 1 点/Shot"）
%   sampling.countBy = "rate" なら、Shot 数の代わりに計測率 [%]（rateStart・rateEnd・rateStep）ごとに作る
%   （"I最適 計測率 20%" のように。Shot 数は Wafer の候補 Shot 数から planTrainingShots で決める。nShots は NaN）。
%   Mark 単位の計画も計測率ごとに作る（"Mark最適 計測率 20%"。計測する Mark の数 = 計測率 × 候補の全 Mark の数。
%   markPerShot は使わない）。
%   group は結果を集計するときの列（ランダムの繰り返しは同じ group にまとめる）。選び方が1つなら "20 Shot"、
%   2つ以上なら選び方の名前を付けて "I最適 20 Shot"・"D最適 20 Shot" のようにする（Excel のパターンは名前、優先順は
%   名前と Shot 数。Excel の列が2つ以上の優先順・パターンと優先順が混ざるときも名前を付ける）。
%   選び方は、選んだ順によらず I 最適 → D 最適 → ランダム → Excel → Mark 単位（I・D）の順に並べる。
ORDER = ["ioptimal", "doptimal", "random", "excel", "mark", "markd"];
PREFIX = struct("ioptimal", "I最適", "doptimal", "D最適", "random", "ランダム", "excel", "", ...
    "mark", "Mark最適", "markd", "MarkD最適");
sampling = alignest.upgradeLayoutSettings(sampling);
methods = unique(reshape(string(sampling.method), 1, []), 'stable');
unknown = methods(~ismember(methods, ORDER));
if ~isempty(unknown)
    error('alignest:samplingMethod', '学習 Shot の選び方が正しくありません: %s', strjoin(unknown, "・"));
end
if isempty(methods)
    error('alignest:samplingMethod', '学習 Shot の選び方を1つ以上選んでください。');
end
methods = ORDER(ismember(ORDER, methods));
compare = numel(methods) > 1;
specs = struct("type", {}, "nShots", {}, "rate", {}, "repeat", {}, "label", {}, "group", {}, "shotNos", {}, ...
    "markPerShot", {}, "markNos", {}, "required", {});
for method = methods
    prefix = PREFIX.(method);
    switch method
        case {"ioptimal", "doptimal"}
            [sizes, sizeTexts, rates] = trainingSizes(sampling);
            for k = 1:numel(sizes)
                specs(end + 1) = spec(method, sizes(k), rates(k), 1, prefix + " " + sizeTexts(k), ...
                    groupName(compare, prefix, sizeTexts(k)), [], NaN); %#ok<AGROW>
            end
        case "random"
            [sizes, sizeTexts, rates] = trainingSizes(sampling);
            for k = 1:numel(sizes)
                for repeat = 1:sampling.randomRepeats
                    specs(end + 1) = spec(method, sizes(k), rates(k), repeat, sprintf("%s %s #%d", prefix, ...
                        sizeTexts(k), repeat), groupName(compare, prefix, sizeTexts(k)), [], NaN); %#ok<AGROW>
                end
            end
        case "excel"
            specs = [specs, excelSpecs(sampling, compare)]; %#ok<AGROW>
        case {"mark", "markd"}
            [perShot, rates, sizeTexts] = markSizes(sampling);
            for k = 1:numel(sizeTexts)
                specs(end + 1) = spec(method, NaN, rates(k), 1, prefix + " " + sizeTexts(k), ...
                    groupName(compare, prefix, sizeTexts(k)), [], perShot(k)); %#ok<AGROW>
            end
    end
end
if isempty(specs)
    error('alignest:nShots', '学習 Shot 数を1つ以上入れてください。');
end
end

function item = spec(type, nShots, rate, repeat, label, group, shotNos, markPerShot, markNos, required)
% 学習パターン1つ。shotNos・markNos（Mark 単位の Excel の指定）・required（優先順で必ず計測する項目）は行ベクトル。
% markNos・required は Excel の指定だけ
if nargin < 9
    markNos = zeros(1, 0);
    required = false(1, 0);
end
item = struct("type", type, "nShots", nShots, "rate", rate, "repeat", repeat, "label", label, "group", group, ...
    "shotNos", shotNos, "markPerShot", markPerShot, "markNos", markNos, "required", required);
end

function name = groupName(compare, prefix, sizeText)
% 結果の列：選び方が1つなら Shot 数（計測率）だけ、比べるときは選び方の名前を付ける
name = sizeText;
if compare
    name = prefix + " " + sizeText;
end
end

function specs = excelSpecs(sampling, compare)
% Excel ファイルで指定：パターン（type "manual"）は1つずつ、優先順（type "file"）は Shot 数・計測率（Mark 単位は
% 1 Shot あたりの Mark 数・計測率）ごと
specs = struct("type", {}, "nShots", {}, "rate", {}, "repeat", {}, "label", {}, "group", {}, "shotNos", {}, ...
    "markPerShot", {}, "markNos", {}, "required", {});
plans = alignest.parseLayoutPlans(string(fieldOr(sampling, "layoutPlans", strings(0, 1))));
if isempty(plans)
    error('alignest:layoutPlans', ['Excel ファイルで指定する学習パターンがありません。「Excel ファイルを読み込む…」で' ...
        '読み込んでください。']);
end
kinds = string({plans.kind});
named = compare || nnz(kinds == "priority") > 1 || (any(kinds == "priority") && any(kinds == "pattern"));
for plan = plans
    markLevel = ~isempty(plan.markNos);
    unitName = ternary(markLevel, "Mark", "Shot");
    if plan.kind == "pattern"
        n = numel(plan.shotNos);
        specs(end + 1) = spec("manual", ternary(markLevel, NaN, n), NaN, 1, sprintf("%s（%d %s）", plan.name, n, ...
            unitName), plan.name, plan.shotNos.', NaN, plan.markNos.', plan.required.'); %#ok<AGROW>
        continue
    end
    if markLevel
        [perShot, rates, sizeTexts] = markSizes(sampling);
        sizes = nan(size(rates));
    else
        [sizes, sizeTexts, rates] = trainingSizes(sampling);
        perShot = nan(size(rates));
    end
    for k = 1:numel(sizeTexts)
        specs(end + 1) = spec("file", sizes(k), rates(k), 1, plan.name + " " + sizeTexts(k), ...
            groupName(named, plan.name, sizeTexts(k)), plan.shotNos.', perShot(k), plan.markNos.', ...
            plan.required.'); %#ok<AGROW>
    end
end
end

function [perShot, rates, texts] = markSizes(sampling)
% Mark 単位の計画の大きさ：1 Shot あたりの Mark 数（markPerShot）ごと、計測率で決めるときは計測率ごと
if isfield(sampling, "countBy") && string(sampling.countBy) == "rate"
    [~, texts, rates] = trainingSizes(sampling);
    perShot = nan(size(rates));
    return
end
perShot = 1;
if isfield(sampling, "markPerShot") && ~isempty(sampling.markPerShot)
    perShot = unique(double(sampling.markPerShot(:)).');
end
if any(~isfinite(perShot) | perShot <= 0)
    error('alignest:markPerShot', '1 Shot あたりの Mark 数は 0 より大きい数にしてください（1 なら Shot 数と同じ数）。');
end
rates = nan(size(perShot));
texts = compose("%g 点/Shot", perShot);
end

function value = fieldOr(s, name, fallback)
value = fallback;
if isfield(s, name)
    value = s.(name);
end
end

function value = ternary(condition, whenTrue, whenFalse)
if condition
    value = whenTrue;
else
    value = whenFalse;
end
end

function [sizes, texts, rates] = trainingSizes(sampling)
% 学習 Shot 数（nShots）または計測率ごとの、spec の nShots・名前・計測率（Shot 数で決めるときは NaN）
if isfield(sampling, "countBy") && string(sampling.countBy) == "rate"
    rates = alignest.measurementRateList(sampling.rateStart, sampling.rateEnd, sampling.rateStep);
    sizes = nan(size(rates));
    texts = compose("計測率 %g%%", rates);
elseif isfield(sampling, "nShots")
    sizes = sort(sampling.nShots(:)).';
    rates = nan(size(sizes));
    texts = compose("%d Shot", sizes);
else
    [sizes, rates, texts] = deal(zeros(1, 0), zeros(1, 0), strings(1, 0));
end
end
