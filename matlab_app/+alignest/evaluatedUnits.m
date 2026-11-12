function index = evaluatedUnits(results)
%EVALUATEDUNITS 評価の結果で評価した Wafer の番号（results.unitLabels・data.units の何番目か。小さい順）。
%   index = alignest.evaluatedUnits(results)
%   results.evaluatedUnits があればその番号（「評価に使う Wafer」で枚数・割合を決めたとき）、無ければすべての Wafer
%   （以前の結果・Excel から読み込んだ結果）。
if isfield(results, "evaluatedUnits") && ~isempty(results.evaluatedUnits)
    index = reshape(results.evaluatedUnits, 1, []);
else
    index = 1:numel(results.unitLabels);
end
end
