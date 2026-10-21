function specs = buildPlanSpecs(sampling)
%BUILDPLANSPECS 学習に使う Shot の選び方の一覧（学習パターン）を作る。
%   sampling.method = "ioptimal"（制約付き I 最適）："I最適 20 Shot" のように Shot 数ごとに1つ
%                     "file"（ファイルの優先順）："優先順 20 Shot" のように Shot 数ごとに1つ（中身は planTrainingShots）
%                     "random"（制約つきランダム）：Shot 数ごとに randomRepeats 回
%                     "manual"（手動で指定）：manualPlans の1行が1パターン（shotNo を空白またはカンマで区切る）
%   sampling.countBy = "rate" なら、Shot 数の代わりに計測率 [%]（rateStart・rateEnd・rateStep）ごとに作る
%   （"I最適 計測率 20%" のように。Shot 数は Wafer の候補 Shot 数から planTrainingShots で決める。nShots は NaN）。
%   group は結果を集計するときの列（ランダムの繰り返しは同じ group にまとめる）。
specs = struct("type", {}, "nShots", {}, "rate", {}, "repeat", {}, "label", {}, "group", {}, "shotNos", {});
[sizes, sizeTexts, rates] = trainingSizes(sampling);
switch string(sampling.method)
    case "ioptimal"
        for k = 1:numel(sizes)
            specs(end + 1) = struct("type", "ioptimal", "nShots", sizes(k), "rate", rates(k), "repeat", 1, ...
                "label", "I最適 " + sizeTexts(k), "group", sizeTexts(k), "shotNos", []); %#ok<AGROW>
        end
    case "random"
        for k = 1:numel(sizes)
            for repeat = 1:sampling.randomRepeats
                specs(end + 1) = struct("type", "random", "nShots", sizes(k), "rate", rates(k), "repeat", repeat, ...
                    "label", sprintf("ランダム %s #%d", sizeTexts(k), repeat), "group", sizeTexts(k), ...
                    "shotNos", []); %#ok<AGROW>
            end
        end
    case "file"
        if ~isfield(sampling, "priorityShots") || isempty(sampling.priorityShots)
            error('alignest:shotPriority', '計測する Shot の優先順のファイルを読み込んでください。');
        end
        for k = 1:numel(sizes)
            specs(end + 1) = struct("type", "file", "nShots", sizes(k), "rate", rates(k), "repeat", 1, ...
                "label", "優先順 " + sizeTexts(k), "group", sizeTexts(k), "shotNos", []); %#ok<AGROW>
        end
    case "manual"
        lines = string(sampling.manualPlans(:));
        lines = lines(strlength(strtrim(lines)) > 0);
        for k = 1:numel(lines)
            numbers = str2double(split(strtrim(regexprep(lines(k), "[,、\s]+", " ")), " "));
            if any(isnan(numbers))
                error('alignest:manualPlan', ...
                    '手動の指定の %d 行目に数字でない値があります。shotNo を空白またはカンマで区切って書いてください: %s', k, lines(k));
            end
            numbers = unique(numbers(:)).';
            name = sprintf("手動%d", k);
            specs(end + 1) = struct("type", "manual", "nShots", numel(numbers), "rate", NaN, "repeat", 1, ...
                "label", sprintf("%s（%d Shot）", name, numel(numbers)), "group", name, "shotNos", numbers); %#ok<AGROW>
        end
        if isempty(specs)
            error('alignest:manualPlan', '手動で指定する Shot がありません。1行に1パターン、shotNo を書いてください。');
        end
    otherwise
        error('alignest:samplingMethod', '学習 Shot の選び方が正しくありません: %s', sampling.method);
end
if isempty(specs)
    error('alignest:nShots', '学習 Shot 数を1つ以上入れてください。');
end
end

function [sizes, texts, rates] = trainingSizes(sampling)
% 学習 Shot 数（nShots）または計測率ごとの、spec の nShots・名前・計測率（Shot 数で決めるときは NaN）
if isfield(sampling, "countBy") && string(sampling.countBy) == "rate" && string(sampling.method) ~= "manual"
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
