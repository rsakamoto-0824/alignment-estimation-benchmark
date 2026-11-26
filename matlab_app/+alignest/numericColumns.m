function names = numericColumns(units)
%NUMERICCOLUMNS 読み込んだデータの「その他の列」（列の対応で標準の項目にしなかった列）のうち、数値の列の名前。
%   names = alignest.numericColumns(app.Data.units)
%   空でない値の MIN_NUMERIC_RATIO 以上が数として読める列を数値の列とする（全 Wafer の値で判断）。
%   説明変数に足す連続値の列（「2. 面内推定の設定」）の候補に使う。
MIN_NUMERIC_RATIO = 0.9;
names = strings(1, 0);
if isempty(units) || ~isfield(units, "attributeNames")
    return
end
allNames = string(units(1).attributeNames);
for j = 1:numel(allNames)
    values = strings(0, 1);
    for u = 1:numel(units)
        values = [values; units(u).marks.attributes(:, j)]; %#ok<AGROW>
    end
    values = values(strlength(strtrim(values)) > 0);
    if ~isempty(values) && mean(isfinite(str2double(values))) >= MIN_NUMERIC_RATIO
        names(end + 1) = allNames(j); %#ok<AGROW>
    end
end
end
