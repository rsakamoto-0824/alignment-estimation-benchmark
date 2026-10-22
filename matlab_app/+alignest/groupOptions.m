function options = groupOptions(units, groupBy)
%GROUPOPTIONS 図に出す Wafer・グループの選択肢：Wafer ごとと、平均（共分散楕円）の単位ごと。
%   options = alignest.groupOptions(units)            % 全 Wafer と、LotID・EqpId・Operation の値ごと（2種類以上のとき）
%   options = alignest.groupOptions(units, groupBy)   % 平均の単位を1つ選ぶ
%   groupBy："all"（全 Wafer）・"lotId"・"eqpId"・"operation"（その値ごと）・"col:<列名>"（ファイルのその他の列の値ごと）。
%   選んだ単位では、値が1種類でも平均を出す。その他の列は Mark ごとの値なので、その値の Mark だけを集めて平均する
%   （Wafer の中で値が変わる列でもよい）。
%   options は構造体配列（label：画面に出す名前、unitIndex：含む Wafer の番号、isGroup：平均の図か、
%   column・level：その他の列で Mark を絞るときの列名と値。絞らないときは ""）。
%   先頭の Wafer 数ぶんは Wafer ごとで、番号は units の順と同じ（選択肢の番号をそのまま Wafer の番号に使える）。
arguments
    units struct
    groupBy (1, 1) string = "default"
end
FIELDS = ["lotId", "eqpId", "operation"];
NAMES = ["LotID", "EqpId", "Operation"];
options = struct("label", {}, "unitIndex", {}, "isGroup", {}, "column", {}, "level", {});
for u = 1:numel(units)
    options(end + 1) = option(string(units(u).label), u, false); %#ok<AGROW>
end
if groupBy == "default"
    if numel(units) < 2
        return
    end
    options(end + 1) = option(sprintf("平均：全 Wafer（%d 枚）", numel(units)), 1:numel(units), true);
    for k = 1:numel(FIELDS)
        options = [options, fieldGroups(units, FIELDS(k), NAMES(k), 2)]; %#ok<AGROW>
    end
elseif groupBy == "all"
    options(end + 1) = option(sprintf("平均：全 Wafer（%d 枚）", numel(units)), 1:numel(units), true);
elseif any(groupBy == FIELDS)
    options = [options, fieldGroups(units, groupBy, NAMES(FIELDS == groupBy), 1)];
elseif startsWith(groupBy, "col:")
    options = [options, columnGroups(units, extractAfter(groupBy, "col:"))];
else
    error('alignest:groupBy', '平均の単位は all・lotId・eqpId・operation・col:<列名> のどれかです: %s', groupBy);
end
end

function groups = fieldGroups(units, field, name, minLevels)
% LotID・EqpId・Operation の値ごとの平均（値が minLevels 種類以上のとき）
groups = struct("label", {}, "unitIndex", {}, "isGroup", {}, "column", {}, "level", {});
if ~isfield(units, field)
    return
end
values = string({units.(field)});
levels = unique(values(values ~= ""), 'stable');
if numel(levels) < minLevels
    return
end
for level = levels
    members = find(values == level);
    groups(end + 1) = option(sprintf("平均：%s = %s（%d 枚）", name, level, numel(members)), members, true); %#ok<AGROW>
end
end

function groups = columnGroups(units, column)
% ファイルのその他の列の値ごとの平均（その値の Mark だけを使う）
groups = struct("label", {}, "unitIndex", {}, "isGroup", {}, "column", {}, "level", {});
levels = strings(1, 0);
for u = 1:numel(units)
    position = find(string(units(u).attributeNames) == column, 1);
    if ~isempty(position)
        levels = [levels, reshape(unique(units(u).marks.attributes(:, position)), 1, [])]; %#ok<AGROW>
    end
end
levels = unique(levels(levels ~= ""), 'stable');
if isempty(levels) && ~any(arrayfun(@(unit) any(string(unit.attributeNames) == column), units))
    error('alignest:groupBy', '平均の単位に選んだ列「%s」が、読み込んだデータにありません。', column);
end
for level = levels
    members = find(arrayfun(@(unit) hasLevel(unit, column, level), units));
    groups(end + 1) = option(sprintf("平均：%s = %s（%d 枚）", column, level, numel(members)), members, true); %#ok<AGROW>
    groups(end).column = column;
    groups(end).level = level;
end
end

function found = hasLevel(unit, column, level)
position = find(string(unit.attributeNames) == column, 1);
found = ~isempty(position) && any(unit.marks.attributes(:, position) == level);
end

function item = option(label, unitIndex, isGroup)
item = struct("label", string(label), "unitIndex", unitIndex, "isGroup", isGroup, "column", "", "level", "");
end
