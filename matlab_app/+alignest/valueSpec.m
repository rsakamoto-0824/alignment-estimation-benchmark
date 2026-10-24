function spec = valueSpec(dataSettings)
%VALUESPEC 推定する値の種類（X・Y の2成分か、ファイルの1つの列か）と、画面・Excel に出す名前・単位。
%   spec = alignest.valueSpec(settings.data)
%   1変数（settings.data.valueColumn が空でない）は、膜厚・線幅などの1つの列を推定する。中では X 成分として扱い
%   （計測値は marks.measX）、Y 成分は使わない（marks.validY がすべて false）。X・Y を合わせた指標（RMSE_XY など）は、
%   Y が無いのでその1変数の指標と同じになる。
%   spec.scalar：1変数なら true、spec.name：値の名前（2成分は "X・Y"、1変数は列の名前）、spec.unit：単位
%   （2成分は "nm"、1変数は settings.data.valueUnit）、spec.components：使う成分（["X", "Y"] または "X"）、
%   spec.labels：成分の表示名（["X", "Y"] または列の名前）、spec.combinedLabel：合わせた指標の表示名
%   （"X・Y 合計" または列の名前）。
column = "";
unit = "nm";
if isfield(dataSettings, "valueColumn")
    column = strtrim(string(dataSettings.valueColumn));
end
if isfield(dataSettings, "valueUnit") && strtrim(string(dataSettings.valueUnit)) ~= ""
    unit = strtrim(string(dataSettings.valueUnit));
end
if column == ""
    spec = struct("scalar", false, "name", "X・Y", "unit", "nm", "components", ["X", "Y"], "labels", ["X", "Y"], ...
        "combinedLabel", "X・Y 合計");
else
    spec = struct("scalar", true, "name", column, "unit", unit, "components", "X", "labels", column, ...
        "combinedLabel", column);
end
end
