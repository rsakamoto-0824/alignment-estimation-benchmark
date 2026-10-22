function columns = factorColumnsUsed(settings)
%FACTORCOLUMNSUSED 質的変数に選んだファイルのその他の列（X 成分と Y 成分のどちらかで使う列。重ならない並び）。
columns = unique([alignest.factorChoice(settings, "X").columns, alignest.factorChoice(settings, "Y").columns], 'stable');
end
