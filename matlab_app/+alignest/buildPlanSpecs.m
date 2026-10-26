function specs = buildPlanSpecs(sampling)
%BUILDPLANSPECS 学習に使う Shot（Mark）の選び方の一覧（学習パターン）を作る。
%   sampling.method は選び方（複数選ぶと、選び方どうしを同じ評価の中で比べる）：
%     "ioptimal"（制約付き I 最適）："I最適 20 Shot" のように Shot 数ごとに1つ
%     "doptimal"（制約付き D 最適）："D最適 20 Shot" のように Shot 数ごとに1つ（det(M) を大きくする）
%     "random"（制約つきランダム）：Shot 数ごとに randomRepeats 回
%     "file"（ファイルの優先順）："優先順 20 Shot" のように Shot 数ごとに1つ（中身は planTrainingShots）
%     "manual"（手動・人の選択）：manualPlans の1行が1パターン（shotNo を空白またはカンマで区切る）。
%                「名前: 1 5 9」のように「:」の前に名前を書くと、その名前を学習パターンの名前にする
%                （計測マップの Excel から読み込んだ人の選択。alignest.readLayoutPlans）
%     "mark"（Mark 単位の I 最適）・"markd"（Mark 単位の D 最適）：計測する Shot ではなく Mark を選ぶ（既定では全 Shot で
%                1点以上。sampling.markRequirePerShot・markMinPerShot）。markPerShot（1 Shot あたりの平均の Mark 数）
%                ごとに1つ（"Mark最適 1 点/Shot"・"MarkD最適 1 点/Shot"）
%   sampling.countBy = "rate" なら、Shot 数の代わりに計測率 [%]（rateStart・rateEnd・rateStep）ごとに作る
%   （"I最適 計測率 20%" のように。Shot 数は Wafer の候補 Shot 数から planTrainingShots で決める。nShots は NaN）。
%   Mark 単位の計画も計測率ごとに作る（"Mark最適 計測率 20%"。計測する Mark の数 = 計測率 × 候補の全 Mark の数。
%   markPerShot は使わない）。
%   group は結果を集計するときの列（ランダムの繰り返しは同じ group にまとめる）。選び方が1つなら "20 Shot"、
%   2つ以上なら選び方の名前を付けて "I最適 20 Shot"・"D最適 20 Shot" のようにする（手動・人の選択は名前）。
%   選び方は、選んだ順によらず I 最適 → D 最適 → ランダム → 優先順 → 手動 → Mark 単位（I・D）の順に並べる。
ORDER = ["ioptimal", "doptimal", "random", "file", "manual", "mark", "markd"];
PREFIX = struct("ioptimal", "I最適", "doptimal", "D最適", "random", "ランダム", "file", "優先順", "manual", "", ...
    "mark", "Mark最適", "markd", "MarkD最適");
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
    "markPerShot", {});
for method = methods
    prefix = PREFIX.(method);
    switch method
        case {"ioptimal", "doptimal", "file"}
            if method == "file" && (~isfield(sampling, "priorityShots") || isempty(sampling.priorityShots))
                error('alignest:shotPriority', '計測する Shot の優先順のファイルを読み込んでください。');
            end
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
        case "manual"
            specs = [specs, manualSpecs(sampling)]; %#ok<AGROW>
        case {"mark", "markd"}
            if isfield(sampling, "countBy") && string(sampling.countBy) == "rate"
                % 計測率ごと（計測する Mark の数 = 計測率 × 候補の全 Mark の数。planTrainingShots）
                [~, sizeTexts, rates] = trainingSizes(sampling);
                for k = 1:numel(rates)
                    specs(end + 1) = spec(method, NaN, rates(k), 1, prefix + " " + sizeTexts(k), ...
                        groupName(compare, prefix, sizeTexts(k)), [], NaN); %#ok<AGROW>
                end
                continue
            end
            perShot = 1;
            if isfield(sampling, "markPerShot") && ~isempty(sampling.markPerShot)
                perShot = unique(double(sampling.markPerShot(:)).');
            end
            if any(~isfinite(perShot) | perShot <= 0)
                error('alignest:markPerShot', '1 Shot あたりの Mark 数は 0 より大きい数にしてください（1 なら Shot 数と同じ数）。');
            end
            for value = perShot
                sizeText = sprintf("%g 点/Shot", value);
                specs(end + 1) = spec(method, NaN, NaN, 1, prefix + " " + sizeText, groupName(compare, prefix, sizeText), ...
                    [], value); %#ok<AGROW>
            end
    end
end
if isempty(specs)
    error('alignest:nShots', '学習 Shot 数を1つ以上入れてください。');
end
end

function item = spec(type, nShots, rate, repeat, label, group, shotNos, markPerShot)
item = struct("type", type, "nShots", nShots, "rate", rate, "repeat", repeat, "label", label, "group", group, ...
    "shotNos", shotNos, "markPerShot", markPerShot);
end

function name = groupName(compare, prefix, sizeText)
% 結果の列：選び方が1つなら Shot 数（計測率）だけ、比べるときは選び方の名前を付ける
name = sizeText;
if compare
    name = prefix + " " + sizeText;
end
end

function specs = manualSpecs(sampling)
% 手動・人の選択：1行が1パターン。「名前: shotNo…」なら名前を使い、無ければ「手動1」…
specs = struct("type", {}, "nShots", {}, "rate", {}, "repeat", {}, "label", {}, "group", {}, "shotNos", {}, ...
    "markPerShot", {});
lines = string(sampling.manualPlans(:));
lines = lines(strlength(strtrim(lines)) > 0);
names = strings(0, 1);
for k = 1:numel(lines)
    line = lines(k);
    name = sprintf("手動%d", k);
    separator = regexp(line, "[:：]", 'once');
    if ~isempty(separator)
        name = strtrim(extractBefore(line, separator));
        line = extractAfter(line, separator);
        if name == ""
            name = sprintf("手動%d", k);
        end
    end
    if any(names == name)
        error('alignest:manualPlan', '手動の指定の %d 行目の名前「%s」がほかの行と同じです。名前を変えてください。', k, name);
    end
    names(end + 1) = name; %#ok<AGROW>
    numbers = str2double(split(strtrim(regexprep(alignest.normalizeNumberText(line), "[,、\s]+", " ")), " "));
    if any(isnan(numbers))
        error('alignest:manualPlan', ...
            '手動の指定の %d 行目に数字でない値があります。shotNo を空白またはカンマで区切って書いてください: %s', k, lines(k));
    end
    numbers = unique(numbers(:)).';
    specs(end + 1) = spec("manual", numel(numbers), NaN, 1, sprintf("%s（%d Shot）", name, numel(numbers)), name, ...
        numbers, NaN); %#ok<AGROW>
end
if isempty(specs)
    error('alignest:manualPlan', '手動で指定する Shot がありません。1行に1パターン、shotNo を書いてください。');
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
