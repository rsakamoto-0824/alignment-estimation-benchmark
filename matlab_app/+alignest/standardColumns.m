function columns = standardColumns(coordinateMode, valueColumn)
%STANDARDCOLUMNS アライメント計測テーブルの標準の項目（Overlay 計測ルールの項目名・順序・意味）。
%   columns = alignest.standardColumns()                              % Shot 中心＋Shot 内の位置、X・Y 成分
%   columns = alignest.standardColumns(coordinateMode, valueColumn)   % 座標の定義・推定する値に合わせる
%   先頭の Operation（工程名）・EqpId（装置ID）・LotID（ロットID）は、このツールで追加した任意の項目。
%   required が true の項目は必ず対応づける。false の項目は無くても動く（無いときの扱いは note）。
%   coordinateMode = "absolute"（Wafer 上の絶対座標だけ）なら、Xmm・Ymm は点の座標で、markXmm・markYmm は任意。
%   valueColumn が空でない（1つの列を1変数として推定する）なら、measX・measY・StsX・StsY は使わない（任意）。
arguments
    coordinateMode (1, 1) string {mustBeMember(coordinateMode, ["shotMark", "absolute"])} = "shotMark"
    valueColumn (1, 1) string = ""
end
names = ["Operation", "EqpId", "LotID", "Wafer", "DateTime", "shotNo", "Direction", "Xmm", "Ymm", "Radius", "markNo", ...
    "markXmm", "markYmm", "measX", "measY", "StsX", "StsY"];
meanings = ["工程名", "装置ID", "ロットID", "ウェハを識別するID", "測定日時", "ウェハ上のショット番号", "Scan方向の区分（1 または 2）", ...
    "ショット中心のX座標 [mm]", "ショット中心のY座標 [mm]", "ショット中心の半径位置 [mm]", ...
    "ショット内のマーク番号", "ショット中心から見たマークX座標 [mm]", "ショット中心から見たマークY座標 [mm]", ...
    "マークのX方向測定値 [nm]", "マークのY方向測定値 [nm]", "X測定値のステータス（0 = 有効）", ...
    "Y測定値のステータス（0 = 有効）"];
required = [false, false, false, false, false, false, false, true, true, false, false, true, true, true, true, false, false];
notes = ["無ければ空。工程が違えば別の計測として扱う", "無ければ空。装置が違えば別の計測として扱う", ...
    "無ければ空。ロットが違えば別の計測として扱う（Wafer ID がロットごとに同じでも分かれる）", ...
    "無ければ全行を1枚とみなす", "無ければ空。同じ Wafer でも日時が違えば別の計測として扱う", ...
    "無ければ座標から番号を付ける（上の行から左→右）", "無ければ「Scan 方向の付与」の規則で付ける（規則が「なし」なら使わない）", ...
    "", "", "あれば Xmm・Ymm から計算した値と合うか確かめる", "無ければマーク座標から番号を付ける", ...
    "", "", "", "", "無ければ measX が空でない値を有効とする", "無ければ measY が空でない値を有効とする"];
columns = struct("name", cellstr(names), "meaning", cellstr(meanings), ...
    "required", num2cell(required), "note", cellstr(notes));
if coordinateMode == "absolute"
    columns(names == "Xmm").meaning = 'マークのX座標（Wafer 上の絶対座標）[mm]';
    columns(names == "Ymm").meaning = 'マークのY座標（Wafer 上の絶対座標）[mm]';
    columns(names == "Radius").meaning = 'マークの半径位置 [mm]';
    [columns(ismember(names, ["markXmm", "markYmm"])).required] = deal(false);
    columns(names == "markXmm").note = '無ければ Shot 内の位置は使わない（shotNo があれば Shot の点の平均を Shot 中心にする）';
    columns(names == "markYmm").note = '無ければ Shot 内の位置は使わない';
end
if valueColumn ~= ""
    [columns(ismember(names, ["measX", "measY"])).required] = deal(false);
    [columns(ismember(names, ["measX", "measY", "StsX", "StsY"])).note] = deal(char("使わない（推定する値は「" + ...
        valueColumn + "」の列）"));
end
end
