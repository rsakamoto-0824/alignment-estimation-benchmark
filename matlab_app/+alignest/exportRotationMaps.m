function exportRotationMaps(filePath, maps, selection, description)
%EXPORTROTATIONMAPS 計測マップ（alignest.rotationMaps）を Excel ファイル（.xlsx）に書き出す（「9. 計測マップのローテーション」）。
%   alignest.exportRotationMaps(filePath, maps)
%   alignest.exportRotationMaps(filePath, maps, selection, description)
%   selection：書き出す計測マップの番号（省略・空ならすべて）。description：「説明」のシートに書く入力・条件の説明。
%   シート：
%   - 「計測マップ_Mark」（Mark ごとのとき）・「計測マップ」（Shot ごとのとき）：shotNo（・markNo）・Shot 中心の座標 Xmm・Ymm・
%     Shot 内の座標 x・y と、計測マップごとの列（1 = 計測する・0 = 計測しない）。「2. 評価の設定」の「Excel ファイルで
%     指定」でそのまま読める（alignest.readLayoutPlans。マップの列がパターンになる）。markNo の分からない点（未知の座標）は、
%     Shot の中の位置の順に番号を付ける
%   - 「ばらつき」：行ごとの優先度・計測の間隔・3σ（X・Y・ベクトル・長さ |v|・目的変数）・値のある Wafer の数
%   - 「説明」：優先度の分け方（指標・しきい値・間隔）、マップの数・計測数・計測率、description
arguments
    filePath (1, 1) string
    maps struct
    selection double = []
    description (1, 1) string = ""
end
[~, ~, extension] = fileparts(filePath);
if ~strcmpi(extension, ".xlsx")
    error('alignest:exportType', '書き出し先は .xlsx にしてください: %s', filePath);
end
if isempty(selection)
    selection = 1:maps.nMaps;
end
selection = unique(reshape(selection, 1, []), 'stable');
if any(selection < 1 | selection > maps.nMaps | selection ~= round(selection))
    error('alignest:rotationMaps', '書き出す計測マップの番号は 1〜%d です。', maps.nMaps);
end
if isfile(filePath)
    try
        delete(filePath);
    catch err
        error('alignest:exportLocked', '「%s」を置き換えられません（Excel で開いていないか確かめてください）。理由: %s', ...
            filePath, err.message);
    end
end
rows = maps.table;
markLevel = maps.level == "mark";
markNo = rows.markNo;
if markLevel && any(~isfinite(markNo))
    markNo = positionNumbers(rows);   % 未知の座標などで Mark の番号が無いときは、Shot の中の位置の順
end
layout = table(rows.shotNo, 'VariableNames', "shotNo");
if markLevel
    layout.markNo = markNo;
end
layout.Xmm = rows.Xc;
layout.Ymm = rows.Yc;
layout.x = rows.localX;
layout.y = rows.localY;
for m = selection
    layout.(maps.mapNames(m)) = double(maps.membership(:, m));
end
sheetName = "計測マップ";
if markLevel
    sheetName = "計測マップ_Mark";
end
writetable(layout, filePath, 'Sheet', sheetName);
spread = table(rows.shotNo, markNo, rows.rank, rows.interval, round(rows.sigma3X, 4), round(rows.sigma3Y, 4), ...
    round(rows.sigma3Vector, 4), round(rows.sigma3Length, 4), round(rows.sigma3Target, 4), rows.nWafers, ...
    'VariableNames', ["shotNo", "markNo", "優先度", "計測の間隔（Lot）", "X の 3σ", "Y の 3σ", "ベクトルの 3σ", ...
    "長さ |v| の 3σ", "目的変数の 3σ", "値のある Wafer の数"]);
if ~markLevel
    spread.markNo = [];
end
writetable(spread, filePath, 'Sheet', 'ばらつき');
items = ["単位"; "優先度を分ける指標"; "しきい値"; "計測の間隔（優先度ごと、n Lot に1回）"; "優先度"; "計測マップの数"; ...
    "マップごとの計測数"; "平均の計測率"; "書き出したマップ"; "入力と条件"];
values = [ternaryText(markLevel, "Mark ごと", "Shot ごと"); maps.metricLabel; strjoin(string(maps.thresholds), "・"); ...
    strjoin(string(maps.intervals), "・"); strjoin(maps.rankNames, "、"); string(maps.nMaps); ...
    strjoin(maps.mapNames + "：" + string(maps.counts), "、"); sprintf("%.1f%%", 100 * maps.averageRate); ...
    strjoin(maps.mapNames(selection), "・"); description];
writetable(table(items, values, 'VariableNames', ["項目", "内容"]), filePath, 'Sheet', '説明');
end

function numbers = positionNumbers(rows)
% Shot の中の位置の順の番号（表の並びは Shot の中で位置の順）
numbers = zeros(height(rows), 1);
[~, ~, group] = unique(rows.shotNo, 'stable');
for g = 1:max(group)
    members = find(group == g);
    numbers(members) = 1:numel(members);
end
end

function text = ternaryText(condition, whenTrue, whenFalse)
if condition
    text = whenTrue;
else
    text = whenFalse;
end
end
