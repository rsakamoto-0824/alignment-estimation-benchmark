function name = factorFieldName(column)
%FACTORFIELDNAME ファイルのその他の列を質的変数に使うときの名前（col_<列名>。MATLAB の項目名に使える文字にする）。
%   GPR の加法カーネルの τ（tau_col_<列名>）や、質的変数の水準の構造体の項目名に使う。長い列名は切り詰める。
MAX_LENGTH = 40;
valid = matlab.lang.makeValidName(char(column));
name = "col_" + string(valid(1:min(end, MAX_LENGTH)));
end
