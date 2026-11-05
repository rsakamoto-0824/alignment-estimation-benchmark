function [wafers, coordinates, info] = markLayoutFileData(raw, mapping)
%MARKLAYOUTFILEDATA 「8. Mark配置の最適化」で読み込んだ Excel・CSV の表（alignest.readHighOrderFile）を、選んだ列で入力にする。
%   [wafers, coordinates, info] = alignest.markLayoutFileData(raw, mapping)
%   mapping：項目名（alignest.markLayoutColumns の name）→ ファイルの列の名前（"" は列なし）。Shot 内の座標（markXmm・markYmm）
%   は必ず選ぶ。X・Y の値（measX・measY）は両方選ぶか、両方選ばない（座標だけの表。乱数の Shot の形で評価する）。
%   Shot の分け方：shotNo の列があればそれで、無ければ Shot 中心の座標（Xmm・Ymm）の組で分ける。どちらも無ければ Wafer ごとに
%   1つの Shot とする（同じ Wafer に同じ Shot 内の座標の行が2つ以上あれば、Shot を分けられないので誤り）。Wafer の列が無ければ
%   すべての行を1枚とする。StsX・StsY の列があれば 0 の値だけを使う（無ければ値のある点）。
%   wafers：値があるとき、alignest.markCandidates の入力（label・points。points は shotNo・localX・localY・valueX・valueY）。
%   値が無ければ空。coordinates：値が無いとき、Shot 内の座標（行の数 × 2 [mm]）。info：rows（使った行の数）・wafers・shots
%   （Wafer・Shot の数）・hasValues。
arguments
    raw table
    mapping struct
end
POSITION_DIGITS = 4;          % 同じ位置とみなす Shot 内の座標の桁（alignest.markCandidates と同じ）
SINGLE_WAFER = "Wafer";       % Wafer の列が無いときの名前
columns = alignest.markLayoutColumns();
names = string({columns.name});
columnNames = string(raw.Properties.VariableNames);
chosen = strings(size(names));
for k = 1:numel(names)
    if isfield(mapping, names(k))
        chosen(k) = string(mapping.(names(k)));
    end
end
chosen(ismissing(chosen)) = "";
unknown = chosen ~= "" & ~ismember(chosen, columnNames);
if any(unknown)
    error('alignest:markLayoutFile', 'ファイルに無い列を選んでいます：%s。', strjoin(names(unknown) + "：" + ...
        chosen(unknown), "・"));
end
missing = [columns.required] & chosen == "";
if any(missing)
    error('alignest:markLayoutFile', '次の項目の列を選んでください：%s（ファイルの列：%s）。', ...
        strjoin(string({columns(missing).meaning}), "・"), strjoin(columnNames, "・"));
end
used = chosen(chosen ~= "");
[uniqueColumns, ~, index] = unique(used);
repeated = uniqueColumns(accumarray(index(:), 1) > 1);
if ~isempty(repeated)
    error('alignest:markLayoutFile', '同じ列「%s」を2つ以上の項目に選んでいます。項目ごとに別の列を選んでください。', ...
        strjoin(repeated, "」「"));
end
column = @(name) chosen(names == name);
hasValues = column("measX") ~= "" || column("measY") ~= "";
if hasValues && (column("measX") == "" || column("measY") == "")
    error('alignest:markLayoutFile', 'X・Y の値の列は、両方選ぶか、両方「（なし）」にしてください（座標だけの表）。');
end
n = height(raw);
local = [numbers(raw, column("markXmm")), numbers(raw, column("markYmm"))];
keep = all(isfinite(local), 2);
if ~any(keep)
    error('alignest:markLayoutFile', 'Shot 内の座標が数の行がありません（列「%s」「%s」）。', column("markXmm"), ...
        column("markYmm"));
end
info = struct("rows", nnz(keep), "wafers", 0, "shots", 0, "hasValues", hasValues);
wafers = struct("label", {}, "points", {});
coordinates = zeros(0, 2);
if ~hasValues
    coordinates = local(keep, :);
    return
end
waferLabels = repmat(SINGLE_WAFER, n, 1);
if column("Wafer") ~= ""
    waferLabels = string(raw.(column("Wafer")));
    waferLabels(ismissing(waferLabels)) = SINGLE_WAFER;
end
if column("shotNo") ~= ""
    shotNo = numbers(raw, column("shotNo"));
elseif column("Xmm") ~= "" && column("Ymm") ~= ""
    centers = [numbers(raw, column("Xmm")), numbers(raw, column("Ymm"))];
    [~, ~, shotNo] = unique(round(centers, POSITION_DIGITS), 'rows', 'stable');
    shotNo(any(~isfinite(centers), 2)) = NaN;
else
    shotNo = ones(n, 1);
    [~, ~, group] = unique(table(waferLabels(keep), round(local(keep, 1), POSITION_DIGITS), ...
        round(local(keep, 2), POSITION_DIGITS)));
    if any(accumarray(group, 1) > 1)
        error('alignest:markLayoutFile', ['同じ Wafer に、同じ Shot 内の座標の行が2つ以上あります。Shot を分けるために、' ...
            'shotNo か Shot 中心の座標（Xmm・Ymm）の列を選んでください。']);
    end
end
valueX = numbers(raw, column("measX"));
valueY = numbers(raw, column("measY"));
if column("StsX") ~= ""
    valueX(numbers(raw, column("StsX")) ~= 0) = NaN;
end
if column("StsY") ~= ""
    valueY(numbers(raw, column("StsY")) ~= 0) = NaN;
end
keep = keep & isfinite(shotNo);
labels = unique(waferLabels(keep), 'stable');
for w = 1:numel(labels)
    rows = keep & waferLabels == labels(w);
    points = table(shotNo(rows), local(rows, 1), local(rows, 2), valueX(rows), valueY(rows), 'VariableNames', ...
        ["shotNo", "localX", "localY", "valueX", "valueY"]);
    wafers(end + 1) = struct("label", labels(w), "points", points); %#ok<AGROW>
    info.shots = info.shots + numel(unique(shotNo(rows)));
end
info.rows = nnz(keep);
info.wafers = numel(wafers);
end

function values = numbers(raw, name)
% 列の値を数にする（文字の列は数に直し、直せない値は NaN）
values = raw.(name);
if isnumeric(values) || islogical(values)
    values = double(values);
else
    values = str2double(string(values));
end
values = reshape(values, [], 1);
end
