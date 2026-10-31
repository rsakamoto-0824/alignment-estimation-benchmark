function [data, mapping] = prepareHighOrderData(raw, mapping, options)
%PREPAREHIGHORDERDATA Excel・CSV の表（alignest.readHighOrderFile）を、選んだ列で Wafer ごとのデータにする（Shot 高次補正の入力）。
%   [data, mapping] = alignest.prepareHighOrderData(raw, mapping)
%   [data, mapping] = alignest.prepareHighOrderData(raw, mapping, directionRule="serpentine")
%   mapping：項目名（alignest.highOrderColumns の name）→ ファイルの列の名前（"" は列なし）。必須の項目（Shot 中心・Shot 内の
%   座標・X・Y の値）は必ず選ぶ。同じ列を2つの項目に選ばない。任意の項目で、値がすべて空の列は使わない（返す mapping では ""）。
%   directionRule：Direction（Scan 方向）が無い行に付ける規則（alignest.directionRules。既定は "none" = 付けない）。
%   前処理は「1. データの読み込み」と同じ alignest.prepareData（座標は mm、値は nm のまま。有効な点は半径 150 mm 未満、
%   StsX・StsY が 0 でない値は使わない、同じ点の行は平均）。data は alignest.prepareData の結果（data.units が Wafer）。
arguments
    raw table
    mapping struct
    options.directionRule (1, 1) string = "none"
end
VALID_RADIUS_MM = 150;        % Overlay 計測ルール：有効な点は半径 150 mm 未満
columns = alignest.highOrderColumns();
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
    error('alignest:highOrderFile', 'ファイルに無い列を選んでいます：%s。', strjoin(names(unknown) + "：" + ...
        chosen(unknown), "・"));
end
missing = [columns.required] & chosen == "";
if any(missing)
    error('alignest:highOrderFile', 'Shot 高次補正に要る項目の列を選んでください：%s（ファイルの列：%s）。', ...
        strjoin(string({columns(missing).meaning}), "・"), strjoin(columnNames, "・"));
end
used = chosen(chosen ~= "");
[uniqueColumns, ~, index] = unique(used);
repeated = uniqueColumns(accumarray(index(:), 1) > 1);
if ~isempty(repeated)
    error('alignest:highOrderFile', '同じ列「%s」を2つ以上の項目に選んでいます。項目ごとに別の列を選んでください。', ...
        strjoin(repeated, "」「"));
end
% 任意の項目で、列はあるが値がすべて空の列は使わない（無い列と同じに扱う）
for k = find(~[columns.required] & chosen ~= "")
    if all(ismissing(raw.(chosen(k))))
        chosen(k) = "";
    end
end
standard = alignest.guessColumnMapping(strings(1, 0));   % 標準の項目をすべて ""（この表で使わない項目）
mapping = struct();
for k = 1:numel(names)
    standard.(names(k)) = chosen(k);
    mapping.(names(k)) = chosen(k);
end
data = alignest.prepareData(raw, standard, validRadiusMm=VALID_RADIUS_MM, directionRule=options.directionRule);
end
