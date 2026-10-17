function mapping = guessColumnMapping(columnNames)
%GUESSCOLUMNMAPPING ファイルの列名から、標準の項目への対応を推定する。
%   1. 項目名が完全に一致する列、2. 大文字・小文字だけ違う列、の順に探す。見つからなければ ""。
%   mapping は標準の項目名をフィールド名、ファイルの列名を値に持つ構造体。
columnNames = string(columnNames);
mapping = struct();
for column = alignest.standardColumns()
    name = string(column.name);
    match = columnNames(columnNames == name);
    if isempty(match)
        match = columnNames(strcmpi(columnNames, name));
    end
    if isempty(match)
        mapping.(name) = "";
    else
        mapping.(name) = match(1);
    end
end
end
