function converted = convertSamplingMethods(methods, unit)
%CONVERTSAMPLINGMETHODS 計測点の選び方を、同じアルゴリズムのデータの粒度 unit の選び方に直す（例：ioptimal → mark）。
%   converted = alignest.convertSamplingMethods(["ioptimal", "poisson"], "mark")   % ["mark", "markpoisson"]
%   どちらの粒度の値でもよい（同じアルゴリズムが重なれば1つにする。知らない値は外す）。並びは methods の順。
arguments
    methods string
    unit (1, 1) string {mustBeMember(unit, ["shot", "mark"])}
end
methods = reshape(methods, 1, []);
shotMethods = alignest.samplingUnitMethods("shot");
markMethods = alignest.samplingUnitMethods("mark");
[inShot, position] = ismember(methods, shotMethods);
[~, markPosition] = ismember(methods, markMethods);
position(~inShot) = markPosition(~inShot);
target = alignest.samplingUnitMethods(unit);
converted = unique(target(position(position > 0)), 'stable');
end
