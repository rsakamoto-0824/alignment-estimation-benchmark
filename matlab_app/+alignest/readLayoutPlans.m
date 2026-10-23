function layouts = readLayoutPlans(filePath, sheetName)
%READLAYOUTPLANS 人が選んだ計測配置（学習パターン）を Excel・CSV から読み、手動の指定の行（manualPlans）にする。
%   layouts = alignest.readLayoutPlans(filePath)             % 「計測マップ」シート（無ければ最初のシート）
%   layouts = alignest.readLayoutPlans(filePath, sheetName)
%   形：1行目が見出し、2行目から Shot ごとの行。shotNo の列と、パターンごとの列（1 = 計測する、0 = しない）。
%   「計測マップを Excel に書き出す…」で書き出したファイル（alignest の計測マップのシート）をそのまま使える
%   （座標・行・列・Scan方向・計測値あり・最外周・指定で必ず計測 の列は読み飛ばす）。人が列を足して 1・0 を書けば、
%   その列が1つのパターンになる（見出しがパターンの名前）。空欄・0 は計測しない。
%   layouts.names：パターンの名前、layouts.shotNos：パターンごとの計測する shotNo（セル）、
%   layouts.lines：manualPlans に入れる行（"名前: shotNo shotNo …"。alignest.buildPlanSpecs が読む）、
%   layouts.file：読んだファイルの名前。
arguments
    filePath (1, 1) string
    sheetName (1, 1) string = ""
end
SHOT_COLUMN = "shotNo";
INFO_COLUMNS = ["Xmm", "Ymm", "行（上から）", "列（左から）", "Scan方向", "計測値あり", "最外周", "指定で必ず計測", ...
    "markNo", "Mark"];
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
        if any(sheets == "計測マップ")
            sheetName = "計測マップ";
        end
    end
    options = {'Sheet', char(sheetName)};
end
importOptions = detectImportOptions(filePath, options{:});
importOptions.VariableNamingRule = 'preserve';
raw = readtable(filePath, importOptions);
names = string(raw.Properties.VariableNames);
shotColumn = find(strcmpi(names, SHOT_COLUMN), 1);
if isempty(shotColumn)
    error('alignest:readLayoutPlans', ['「shotNo」の列がありません。1行目に shotNo と、パターンごとの列（1 = 計測する、' ...
        '0 = しない）を書いてください（計測マップの Excel と同じ形）。']);
end
shotNos = toNumbers(raw{:, shotColumn});
patternColumns = find(~ismember(names, [names(shotColumn), INFO_COLUMNS]));
layouts = struct("names", strings(0, 1), "shotNos", {cell(0, 1)}, "lines", strings(0, 1), "file", "");
for column = patternColumns
    values = toNumbers(raw{:, column});
    valid = isfinite(values);
    if ~any(valid) || any(~ismember(values(valid), [0, 1])) || all(values(valid) == 1)
        continue   % 1・0 でない列（メモなど）と、全 Shot を計測する列（評価する Shot が残らない）はパターンにしない
    end
    chosen = unique(shotNos(values == 1 & isfinite(shotNos)));
    if isempty(chosen)
        continue
    end
    name = strtrim(names(column));
    layouts.names(end + 1, 1) = name;
    layouts.shotNos{end + 1, 1} = chosen(:).';
    layouts.lines(end + 1, 1) = replace(name, [":", "："], "・") + ": " + strjoin(string(chosen(:).'), " ");
end
if isempty(layouts.names)
    error('alignest:readLayoutPlans', ['計測するパターンの列（1 = 計測する、0 = しない）が見つかりません。shotNo の列の' ...
        '右に、パターンの名前を見出しにした列を足して 1・0 を書いてください。']);
end
[~, name, extension] = fileparts(filePath);
layouts.file = name + extension;
end

function values = toNumbers(column)
% 数字・文字のどちらの列でも数にする（空欄・読めない値は NaN）
if isnumeric(column) || islogical(column)
    values = double(column);
else
    values = str2double(string(column));
end
values = values(:);
end
