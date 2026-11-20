function [methods, names] = samplingUnitMethods(unit)
%SAMPLINGUNITMETHODS 計測点の単位で選べる計測点の選び方（設定 sampling.method の値）と、画面の名前。
%   [methods, names] = alignest.samplingUnitMethods("shot")   % Shot 単位：計測する Shot を選ぶ
%   [methods, names] = alignest.samplingUnitMethods("mark")   % Mark 単位：計測する Mark を選ぶ
%   「Excel ファイルで指定」（excel）はどちらの単位にもある（ファイルに markNo の列があれば Mark、無ければ Shot を指定）。
arguments
    unit (1, 1) string {mustBeMember(unit, ["shot", "mark"])}
end
if unit == "shot"
    methods = ["ioptimal", "doptimal", "random", "sobol", "poisson", "excel"];
    names = ["制約付き I 最適", "制約付き D 最適", "制約つきランダム", "Sobol 列", "ポアソンディスク", "Excel ファイルで指定"];
else
    methods = [alignest.markPlanTypes(), "excel"];   % mark・markd・markrandom・markpoisson
    names = ["I 最適", "D 最適", "制約つきランダム", "ポアソンディスク", "Excel ファイルで指定"];
end
end
