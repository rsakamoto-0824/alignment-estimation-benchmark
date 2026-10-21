function options = groupOptions(units)
%GROUPOPTIONS 図に出す Wafer・グループの選択肢：Wafer ごとと、全 Wafer・LotID・EqpId・Operation ごとの平均。
%   options は構造体配列（label：画面に出す名前、unitIndex：含む Wafer の番号、isGroup：平均の図か）。
%   先頭の Wafer 数ぶんは Wafer ごとで、番号は units の順と同じ（選択肢の番号をそのまま Wafer の番号に使える）。
%   LotID・EqpId・Operation は、値が2種類以上あるときだけ値ごとの平均を加える（1種類なら全 Wafer の平均と同じ）。
options = struct("label", {}, "unitIndex", {}, "isGroup", {});
for u = 1:numel(units)
    options(end + 1) = struct("label", string(units(u).label), "unitIndex", u, "isGroup", false); %#ok<AGROW>
end
if numel(units) < 2
    return
end
options(end + 1) = struct("label", sprintf("平均：全 Wafer（%d 枚）", numel(units)), "unitIndex", 1:numel(units), ...
    "isGroup", true);
fields = ["lotId", "eqpId", "operation"];
names = ["LotID", "EqpId", "Operation"];
for k = 1:numel(fields)
    if ~isfield(units, fields(k))
        continue
    end
    values = string({units.(fields(k))});
    levels = unique(values(values ~= ""), 'stable');
    if numel(levels) < 2
        continue
    end
    for level = levels
        members = find(values == level);
        options(end + 1) = struct("label", sprintf("平均：%s = %s（%d 枚）", names(k), level, numel(members)), ...
            "unitIndex", members, "isGroup", true); %#ok<AGROW>
    end
end
end
