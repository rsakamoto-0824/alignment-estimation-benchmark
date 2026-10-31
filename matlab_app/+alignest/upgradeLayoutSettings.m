function sampling = upgradeLayoutSettings(sampling)
%UPGRADELAYOUTSETTINGS 以前の学習 Shot の選び方「手動・人の選択」（manual）と「ファイルの優先順」（file）を、
%   「Excel ファイルで指定」（excel。sampling.layoutPlans の行。alignest.parseLayoutPlans）に直す。
%   sampling = alignest.upgradeLayoutSettings(sampling)
%   - manual：manualPlans の1行が1パターン（「名前: shotNo…」。名前が無ければ「手動1」…）。shotNo は空白・カンマ区切り
%   - file：priorityShots（行の順）と priorityLevels（1 = 必ず計測、0 = 計測しない、それ以外・空 = 行の順）を1つの優先順
%     （名前は「優先順」）にする。必ず計測する Shot を先に、残りを行の順に並べる
%   以前の設定ファイル・評価結果の Excel の設定、manualPlans・priorityShots を直接書いた設定を、今の形で読めるようにする。
%   manual・file を選んでいなければ、項目を除くだけ（layoutPlans はそのまま）。
LEGACY_FIELDS = ["manualPlans", "priorityShots", "priorityLevels", "priorityFile"];
PRIORITY_NAME = "優先順";
methods = reshape(string(fieldOr(sampling, "method", "ioptimal")), 1, []);
lines = strings(0, 1);
if any(methods == "manual")
    lines = [lines; manualLines(string(fieldOr(sampling, "manualPlans", strings(0, 1))))];
end
if any(methods == "file")
    shotNos = double(fieldOr(sampling, "priorityShots", zeros(1, 0)));
    if isempty(shotNos)
        error('alignest:shotPriority', '計測する Shot の優先順のファイルを読み込んでください。');
    end
    levels = double(fieldOr(sampling, "priorityLevels", nan(size(shotNos))));
    if numel(levels) ~= numel(shotNos)
        levels = nan(size(shotNos));
    end
    shotNos = shotNos(:);
    levels = levels(:);
    % 必ず計測（1）を先に、残りを行の順に。どこかで 0（計測しない）の Shot と、2回目からの同じ Shot は使わない
    order = [find(levels == 1); find(levels ~= 1)];
    order = order(~ismember(shotNos(order), shotNos(levels == 0)));
    [~, first] = unique(shotNos(order), 'stable');
    order = order(first);
    items = string(shotNos(order));
    required = levels(order) == 1;
    items(required) = "!" + items(required);
    lines = [lines; "priority|" + PRIORITY_NAME + "|" + strjoin(items.', " ")];
    if isfield(sampling, "priorityFile") && string(sampling.priorityFile) ~= ""
        sampling.layoutFile = string(sampling.priorityFile);
    end
end
if any(methods == "manual" | methods == "file")
    sampling.layoutPlans = lines;
    methods(methods == "manual" | methods == "file") = "excel";
    sampling.method = unique(methods, 'stable');
end
for name = LEGACY_FIELDS
    if isfield(sampling, name)
        sampling = rmfield(sampling, name);
    end
end
end

function lines = manualLines(manualPlans)
% 手動の行（「名前: shotNo…」）を pattern の行にする。名前が同じ行・数でない値は以前と同じエラー
lines = strings(0, 1);
manualPlans = manualPlans(strlength(strtrim(manualPlans)) > 0);
names = strings(0, 1);
for k = 1:numel(manualPlans)
    line = manualPlans(k);
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
            '手動の指定の %d 行目に数字でない値があります。shotNo を空白またはカンマで区切って書いてください: %s', k, ...
            manualPlans(k));
    end
    numbers = unique(numbers(:)).';
    lines(end + 1, 1) = "pattern|" + replace(name, "|", "｜") + "|" + strjoin(string(numbers), " "); %#ok<AGROW>
end
if isempty(lines)
    error('alignest:manualPlan', '手動で指定する Shot がありません。1行に1パターン、shotNo を書いてください。');
end
end

function value = fieldOr(s, name, fallback)
value = fallback;
if isfield(s, name)
    value = s.(name);
end
end
