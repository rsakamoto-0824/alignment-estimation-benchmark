function [targets, info] = readTargetPoints(filePath, sheetName)
%READTARGETPOINTS 未知の座標（推定したい点）の表を Excel・CSV から読む。
%   [targets, info] = alignest.readTargetPoints(filePath)             % 「未知の座標」シート（無ければ書き出した
%                                                                     % 推定値の「推定値」シート、それも無ければ最初のシート）
%   [targets, info] = alignest.readTargetPoints(filePath, sheetName)
%   1行目が見出し、2行目から1行1点。見出しは計測データと同じ名前（大文字・小文字・前後の空白は区別しない）：
%     必須：Xmm・Ymm（Shot 中心の座標 [mm]。markXmm・markYmm が無い・空欄なら点そのものの Wafer 上の座標）
%     任意：markXmm・markYmm（Shot 中心から見た点の座標 [mm]、空欄は 0）、markNo、shotNo、Direction（Scan 方向 1・2）、
%           名前（名前・Name・ID・PointID。空欄は P1, P2, …）
%   全角の数字も読む。空の行は読み飛ばす。Xmm・Ymm が数でない行、Direction が 1・2 以外の行があれば、
%   Excel の行番号を出して止める。targets は alignest.targetTemplate の形。
%   info.file：ファイル名、info.sheet：読んだシート（CSV は ""）、info.columns：使った列の見出し。
arguments
    filePath (1, 1) string
    sheetName (1, 1) string = ""
end
PREFERRED_SHEETS = ["未知の座標", "推定値"];   % 先に探すシート（推定値は書き出した Excel を読み直すとき）
NAME_ALIASES = ["名前", "name", "id", "pointid"];
DIRECTION_ALIASES = ["direction", "scan方向"];
if ~isfile(filePath)
    error('alignest:readTargetPoints', 'ファイルが見つかりません: %s', filePath);
end
[~, baseName, extension] = fileparts(filePath);
options = {};
if ~strcmpi(extension, ".csv")
    try
        sheets = string(sheetnames(filePath));
    catch err
        error('alignest:readTargetPoints', 'Excel ファイルとして読めません: %s（%s）', filePath, err.message);
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
importOptions = setvartype(importOptions, 'string');   % 全角の数字・空欄の混じる列も文字として読み、下で数にする
raw = readtable(filePath, importOptions);
headers = string(raw.Properties.VariableNames);
keys = lower(strtrim(headers));
column = @(names) find(ismember(keys, lower(names)), 1);
xColumn = column("Xmm");
yColumn = column("Ymm");
if isempty(xColumn) || isempty(yColumn)
    error('alignest:readTargetPoints', ['「Xmm」「Ymm」の列がありません（見出し：%s）。1行目に Xmm・Ymm と、' ...
        '必要なら markXmm・markYmm・markNo・shotNo・Direction・名前 の見出しを書いてください。'], strjoin(headers, "・"));
end
n = height(raw);
values = struct("Xmm", toNumbers(raw{:, xColumn}), "Ymm", toNumbers(raw{:, yColumn}));
used = headers([xColumn, yColumn]);
optional = struct("markXmm", "markXmm", "markYmm", "markYmm", "markNo", "markNo", "shotNo", "shotNo");
for name = string(fieldnames(optional)).'
    position = column(optional.(name));
    values.(name) = nan(n, 1);
    if ~isempty(position)
        values.(name) = toNumbers(raw{:, position});
        used(end + 1) = headers(position); %#ok<AGROW>
    end
end
values.direction = nan(n, 1);
position = column(DIRECTION_ALIASES);
if ~isempty(position)
    values.direction = toNumbers(raw{:, position});
    used(end + 1) = headers(position);
end
names = strings(n, 1);
position = column(NAME_ALIASES);
if ~isempty(position)
    names = strtrim(string(raw{:, position}));
    names(ismissing(names)) = "";
    used(end + 1) = headers(position);
end
blank = isnan(values.Xmm) & isnan(values.Ymm) & names == "";
excelRow = find(~blank) + 1;   % 見出しの1行を足した Excel の行番号
keep = ~blank;
missing = isnan(values.Xmm(keep)) | isnan(values.Ymm(keep));
if any(missing)
    error('alignest:readTargetPoints', 'Xmm・Ymm が数でない行があります（Excel の %s 行目）。', ...
        strjoin(string(excelRow(missing).'), "・"));
end
badDirection = ~isnan(values.direction(keep)) & ~ismember(values.direction(keep), [1, 2]);
if any(badDirection)
    error('alignest:readTargetPoints', 'Direction（Scan 方向）は 1 か 2 にしてください（Excel の %s 行目）。', ...
        strjoin(string(excelRow(badDirection).'), "・"));
end
if ~any(keep)
    error('alignest:readTargetPoints', '点がありません。2行目から Xmm・Ymm を書いてください。');
end
targets = alignest.targetTemplate(nnz(keep));
targets.name = names(keep);
for name = ["Xmm", "Ymm", "markNo", "shotNo", "direction"]
    targets.(name) = values.(name)(keep);
end
for name = ["markXmm", "markYmm"]
    offset = values.(name)(keep);
    offset(isnan(offset)) = 0;   % 空欄は Shot 中心（Xmm・Ymm がそのまま点の座標）
    targets.(name) = offset;
end
unnamed = targets.name == "";
targets.name(unnamed) = "P" + string(find(unnamed));
info = struct("file", baseName + extension, "sheet", sheetName, "columns", used);
end

function values = toNumbers(column)
% 数字・文字のどちらの列でも数にする（空欄・読めない値は NaN。全角の数字も読む）
if isnumeric(column) || islogical(column)
    values = double(column);
else
    text = string(column);
    text(ismissing(text)) = "";
    values = str2double(alignest.normalizeNumberText(text));
end
values = values(:);
end
