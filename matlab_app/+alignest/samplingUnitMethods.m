function [methods, names] = samplingUnitMethods(unit)
%SAMPLINGUNITMETHODS データの粒度で選べる計測点の選び方（設定 sampling.method の値）と、画面のアルゴリズムの名前。
%   [methods, names] = alignest.samplingUnitMethods("shot")   % Shot 単位：計測する Shot を選ぶ
%   [methods, names] = alignest.samplingUnitMethods("mark")   % Mark 単位：計測する Mark を選ぶ
%   アルゴリズムはどちらの単位も同じ並び（I 最適・D 最適・Sobol 列・ポアソンディスク・ランダム・Excel 取込）で、
%   names も同じ。methods は単位ごとの値（同じ位置が同じアルゴリズム。alignest.convertSamplingMethods）。
%   「Excel 取込」（excel）はどちらも同じ値（ファイルに markNo の列があれば Mark、無ければ Shot を指定）。
arguments
    unit (1, 1) string {mustBeMember(unit, ["shot", "mark"])}
end
names = ["I 最適", "D 最適", "Sobol 列", "ポアソンディスク", "ランダム", "Excel 取込"];
if unit == "shot"
    methods = ["ioptimal", "doptimal", "sobol", "poisson", "random", "excel"];
else
    methods = [alignest.markPlanTypes(), "excel"];   % mark・markd・marksobol・markpoisson・markrandom
end
end
