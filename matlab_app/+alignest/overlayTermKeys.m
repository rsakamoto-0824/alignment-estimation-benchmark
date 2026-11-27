function keys = overlayTermKeys(terms, axisIndex)
%OVERLAYTERMKEYS 補正モデルの項（alignest.overlayDesign の terms の行）を見分ける文字："成分|軸|x のべき,y のべき"。
%   keys = alignest.overlayTermKeys(terms, axisIndex)
%   成分は "wafer"・"shotCommon"・"perShot"、軸は axisIndex = 1 なら "dx"（X 成分の式）、2 なら "dy"。
%   Shot ごとの成分は、どの Shot の列でも同じ文字（項ごとに使う・使わないを選ぶため）。
%   「5. 未知の座標の推定」の補正のモデルで、チェックを外した項（settings.targetCorrection.excludedTerms）に使う。
axisNames = ["dx", "dy"];
keys = string(terms.component) + "|" + axisNames(axisIndex) + "|" + string(terms.xPower) + "," + string(terms.yPower);
end
