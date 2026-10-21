function choice = factorChoice(settings)
%FACTORCHOICE 推定に使う質的変数の選択（settings.factors）を、以前の設定にも合う形にそろえる。
%   choice.scan：Scan 方向、choice.mark：Mark 番号、choice.row：Shot 行の奇偶（shotRowParity）、
%   choice.columns：ファイルのその他の列の名前（標準の項目に対応づけなかった列）。
%   以前の設定（scan・mark・columns が無い）は Scan 方向と Mark 番号を使い、その他の列は使わない。
choice = struct("scan", true, "mark", true, "row", false, "columns", strings(1, 0));
if ~isfield(settings, "factors")
    return
end
factors = settings.factors;
if isfield(factors, "scan")
    choice.scan = logical(factors.scan);
end
if isfield(factors, "mark")
    choice.mark = logical(factors.mark);
end
if isfield(factors, "shotRowParity")
    choice.row = logical(factors.shotRowParity);
end
if isfield(factors, "columns") && ~isempty(factors.columns)
    columns = string(factors.columns);
    choice.columns = unique(reshape(columns(columns ~= ""), 1, []), 'stable');
end
end
