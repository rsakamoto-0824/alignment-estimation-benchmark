function specs = buildPlanSpecs(sampling)
%BUILDPLANSPECS 学習に使う Shot の選び方の一覧（学習パターン）を作る。
%   sampling.method = "ioptimal"（制約付き I 最適）："I最適 20 Shot" のように Shot 数ごとに1つ
%                     "random"（制約つきランダム）：Shot 数ごとに randomRepeats 回
%                     "manual"（手動で指定）：manualPlans の1行が1パターン（shotNo を空白またはカンマで区切る）
%   group は結果を集計するときの列（ランダムの繰り返しは同じ group にまとめる）。
specs = struct("type", {}, "nShots", {}, "repeat", {}, "label", {}, "group", {}, "shotNos", {});
switch string(sampling.method)
    case "ioptimal"
        for nShots = sort(sampling.nShots(:)).'
            specs(end + 1) = struct("type", "ioptimal", "nShots", nShots, "repeat", 1, ...
                "label", sprintf("I最適 %d Shot", nShots), "group", sprintf("%d Shot", nShots), "shotNos", []); %#ok<AGROW>
        end
    case "random"
        for nShots = sort(sampling.nShots(:)).'
            for repeat = 1:sampling.randomRepeats
                specs(end + 1) = struct("type", "random", "nShots", nShots, "repeat", repeat, ...
                    "label", sprintf("ランダム %d Shot #%d", nShots, repeat), "group", sprintf("%d Shot", nShots), ...
                    "shotNos", []); %#ok<AGROW>
            end
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
            specs(end + 1) = struct("type", "manual", "nShots", numel(numbers), "repeat", 1, ...
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
