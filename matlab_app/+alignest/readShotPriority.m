function priority = readShotPriority(filePath, sheetName)
%READSHOTPRIORITY 計測する Shot の優先順のファイル（Excel・CSV）を読む。
%   1行目に項目名、2行目から Shot 番号と優先度の表。行の順が計測する順（評価で Shot を足していく順）。
%   列は名前で探す：Shot 番号は「shot」を含む列、優先度は「prior」または「優先」を含む列（大文字・小文字は区別しない）。
%   見つからなければ1列目を Shot 番号、2列目を優先度とする（優先度の列が無くてもよい）。
%   優先度 0 = 計測しない（学習に使わない）、1 = 必ず計測する（学習 Shot 数によらず使う）、それ以外・空 = 行の順に使う。
%   priority.shotNo・priority.level は行ベクトル（ファイルの行の順）。priority.file はファイル名。
arguments
    filePath (1, 1) string
    sheetName (1, 1) string = ""
end
raw = alignest.readMeasurementFile(filePath, sheetName);
names = string(raw.Properties.VariableNames);
shotColumn = find(contains(lower(names), "shot"), 1);
priorityColumn = find(contains(lower(names), "prior") | contains(names, "優先"), 1);
if isempty(shotColumn)
    shotColumn = 1;
end
if isempty(priorityColumn) && width(raw) >= 2
    priorityColumn = find((1:width(raw)) ~= shotColumn, 1);
end
shotNo = toNumber(raw.(names(shotColumn)));
level = nan(size(shotNo));
if ~isempty(priorityColumn)
    level = toNumber(raw.(names(priorityColumn)));
end
keep = isfinite(shotNo);
if ~any(keep)
    error('alignest:shotPriority', '優先順のファイルに Shot 番号がありません（列「%s」）: %s', names(shotColumn), filePath);
end
if any(shotNo(keep) ~= round(shotNo(keep)))
    error('alignest:shotPriority', 'Shot 番号は整数にしてください（列「%s」）: %s', names(shotColumn), filePath);
end
if any(level(keep & isfinite(level)) < 0)
    error('alignest:shotPriority', '優先度に負の値があります（0 = 計測しない、1 = 必ず計測する）: %s', filePath);
end
[~, fileName, extension] = fileparts(filePath);
priorityName = "";
if ~isempty(priorityColumn)
    priorityName = names(priorityColumn);
end
priority.shotNo = reshape(shotNo(keep), 1, []);
priority.level = reshape(level(keep), 1, []);
priority.file = fileName + extension;
priority.shotColumn = names(shotColumn);
priority.priorityColumn = priorityName;
end

function values = toNumber(values)
if isnumeric(values) || islogical(values)
    values = double(values(:));
else
    values = str2double(string(values(:)));
end
end
