function layouts = readLayoutPlans(filePath, sheetName)
%READLAYOUTPLANS 学習に使う Shot・Mark の指定を Excel・CSV から読む（「2. 評価の設定」の「Excel ファイルで指定」）。
%   layouts = alignest.readLayoutPlans(filePath)
%   layouts = alignest.readLayoutPlans(filePath, sheetName)
%   シートを指定しないときは「計測マップ_Mark」、無ければ「計測マップ」、無ければ先頭のシート（「計測マップを Excel に
%   書き出す…」で書き出したファイルをそのまま読める）。
%   形：1行目が見出し、2行目から Shot（Mark）ごとの行。
%   - shotNo の列（見出しが shotNo。無ければ「shot」を含む最初の列、それも無ければ1列目）。
%   - markNo の列があれば Mark 単位（1行が1つの Mark。計測する Mark を指定する）。無ければ Shot 単位。
%   - ほかの列が1つずつ学習パターン（見出しがパターンの名前）。座標・行・列・Scan方向・計測値あり・最外周・指定で必ず
%     計測の列（計測マップの情報）と、数でない列は読み飛ばす。
%     ・値が 1・0・空欄だけの列：パターン（1 の Shot・Mark を計測する。0・空欄は計測しない）。すべて 1 の列は
%       評価する点が残らないので使わない。
%     ・それ以外の 0 以上の整数の列、または見出しに「優先」「prior」を含む列：優先順。1 = 必ず計測する、2・3・… = その次に
%       計測する順（同じ値は行の順）、空欄 = 番号の付いた行の後に行の順、0 = 計測しない。評価では、学習 Shot 数
%       （計測率。Mark 単位は 1 Shot あたりの Mark 数・計測率）ごとに先頭から使う（以前の「ファイルの優先順」と同じ）。
%   - パターン・優先順の列が1つも無く、Shot の列だけなら、行の順を優先順にする（名前は「優先順」）。
%   layouts.plans：パターンごとの kind（"pattern"・"priority"）・name・shotNos・markNos・required（alignest.parseLayoutPlans
%   と同じ形）、layouts.lines：設定 sampling.layoutPlans に入れる行、layouts.markLevel：Mark 単位か、
%   layouts.file・sheet：読んだファイル名・シート、layouts.skipped：読み飛ばした列。
arguments
    filePath (1, 1) string
    sheetName (1, 1) string = ""
end
PREFERRED_SHEETS = ["計測マップ_Mark", "計測マップ"];
INFO_COLUMNS = ["Xmm", "Ymm", "x", "y", "行（上から）", "列（左から）", "Scan方向", "計測値あり", "最外周", "指定で必ず計測", ...
    "Mark", "Direction"];
PRIORITY_WORDS = ["優先", "prior"];
DEFAULT_PRIORITY_NAME = "優先順";
if ~isfile(filePath)
    error('alignest:readLayoutPlans', 'ファイルが見つかりません: %s', filePath);
end
[~, ~, extension] = fileparts(filePath);
options = {};
if ~strcmpi(extension, ".csv")
    try
        sheets = string(sheetnames(filePath));
    catch err
        error('alignest:readLayoutPlans', 'Excel ファイルとして読めません: %s（%s）', filePath, err.message);
    end
    if sheetName == ""
        sheetName = sheets(1);
        preferred = PREFERRED_SHEETS(ismember(PREFERRED_SHEETS, sheets));
        if ~isempty(preferred)
            sheetName = preferred(1);
        end
    end
    options = {'Sheet', char(sheetName)};
end
importOptions = detectImportOptions(filePath, options{:});
importOptions.VariableNamingRule = 'preserve';
raw = readtable(filePath, importOptions);
names = string(raw.Properties.VariableNames);
if isempty(names)
    error('alignest:readLayoutPlans', 'ファイルに列がありません: %s', filePath);
end
shotColumn = find(strcmpi(names, "shotNo"), 1);
if isempty(shotColumn)
    shotColumn = find(contains(lower(names), "shot"), 1);
end
if isempty(shotColumn)
    shotColumn = 1;
end
markColumn = find(strcmpi(names, "markNo"), 1);
markLevel = ~isempty(markColumn);
shotNos = toNumbers(raw{:, shotColumn});
markNos = nan(size(shotNos));
if markLevel
    markNos = toNumbers(raw{:, markColumn});
end
rows = isfinite(shotNos) & (~markLevel | isfinite(markNos));
if ~any(rows)
    error('alignest:readLayoutPlans', '「%s」の列に shotNo がありません: %s', names(shotColumn), filePath);
end
if any(shotNos(rows) ~= round(shotNos(rows))) || (markLevel && any(markNos(rows) ~= round(markNos(rows))))
    error('alignest:readLayoutPlans', 'shotNo・markNo は整数にしてください（列「%s」）: %s', names(shotColumn), filePath);
end
used = [shotColumn, markColumn];
plans = struct("kind", {}, "name", {}, "shotNos", {}, "markNos", {}, "required", {});
skipped = strings(1, 0);
for column = find(~ismember(1:numel(names), used) & ~ismember(names, INFO_COLUMNS))
    name = strtrim(replace(names(column), "|", "｜"));
    values = toNumbers(raw{:, column});
    values(~rows) = NaN;
    valid = isfinite(values);
    if ~any(valid)
        skipped(end + 1) = name; %#ok<AGROW>
        continue   % 数でない列（メモなど）
    end
    integers = all(values(valid) >= 0 & values(valid) == round(values(valid)));
    named = any(contains(lower(name), lower(PRIORITY_WORDS)));
    if integers && ~named && all(ismember(values(valid), [0, 1]))
        chosen = find(values == 1);
        if isempty(chosen) || (numel(chosen) == nnz(rows))
            skipped(end + 1) = name; %#ok<AGROW>
            continue   % 計測する点が無い列と、すべての点を計測する列（評価する点が残らない）
        end
        plans(end + 1) = plan("pattern", name, chosen, false(numel(chosen), 1)); %#ok<AGROW>
    elseif integers
        numbered = find(values > 0);
        [~, order] = sortrows([values(numbered), numbered]);
        blank = find(rows & ~valid);
        chosen = [numbered(order); blank];
        plans(end + 1) = plan("priority", name, chosen, values(chosen) == 1); %#ok<AGROW>
    else
        skipped(end + 1) = name; %#ok<AGROW>   % 小数・負の値の列はパターンにも優先順にもしない
    end
end
if isempty(plans)
    if numel(names) == numel(used) || all(ismember(names, [names(used), INFO_COLUMNS]))
        plans = plan("priority", DEFAULT_PRIORITY_NAME, find(rows), false(nnz(rows), 1));   % Shot の列だけ：行の順
    else
        error('alignest:readLayoutPlans', ['学習パターン（1 = 計測する、0 = しない）か優先順（1・2・3…）の列が' ...
            '見つかりません。shotNo の列の右に、名前を見出しにした列を足してください（読み飛ばした列：%s）。'], ...
            strjoin(skipped, "・"));
    end
end
[~, base, extension] = fileparts(filePath);
layouts = struct("plans", plans, "lines", planLines(plans), "markLevel", markLevel, "file", base + extension, ...
    "sheet", string(sheetName), "skipped", skipped);

    function item = plan(kind, name, chosen, required)
        % 選んだ行（chosen の順）を、shotNo（Mark 単位は markNo も）の並びにする（同じ点の2回目からは使わない）
        if markLevel
            keys = [shotNos(chosen), markNos(chosen)];
        else
            keys = shotNos(chosen);
        end
        [~, first] = unique(keys, 'rows', 'stable');
        item = struct("kind", kind, "name", name, "shotNos", shotNos(chosen(first)), "markNos", zeros(0, 1), ...
            "required", required(first));
        if markLevel
            item.markNos = markNos(chosen(first));
        end
    end
end

function lines = planLines(plans)
% 設定に入れる行（alignest.parseLayoutPlans の形）
lines = strings(numel(plans), 1);
for k = 1:numel(plans)
    items = string(plans(k).shotNos);
    if ~isempty(plans(k).markNos)
        items = items + "-" + string(plans(k).markNos);
    end
    items(plans(k).required) = "!" + items(plans(k).required);
    lines(k) = plans(k).kind + "|" + plans(k).name + "|" + strjoin(items.', " ");
end
end

function values = toNumbers(column)
% 数字・文字のどちらの列でも数にする（全角の数字も読む。空欄・読めない値は NaN）
if isnumeric(column) || islogical(column)
    values = double(column);
else
    values = str2double(alignest.normalizeNumberText(string(column)));
end
values = values(:);
end
