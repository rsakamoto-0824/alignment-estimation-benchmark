function sampling = normalizeSamplingUnit(sampling)
%NORMALIZESAMPLINGUNIT 計測点の単位（sampling.unit："shot"・"mark"）と計測点の選び方（sampling.method）をそろえる。
%   sampling = alignest.normalizeSamplingUnit(sampling)
%   画面では Shot 単位と Mark 単位の選び方を一緒には選べないので、設定を画面に出す前にそろえる。
%   単位は選び方から決める：Shot 単位の選び方だけなら "shot"、Mark 単位の選び方だけなら "mark"、「Excel ファイルで指定」
%   だけ・空なら sampling.unit のまま（無ければ "shot"）。両方の選び方がある以前の設定は、sampling.unit（無ければ
%   Shot 単位）の選び方だけを残す。残る選び方が無ければ、その単位の I 最適にする。
%   計算（alignest.buildPlanSpecs）は単位を見ないので、関数から両方の選び方を渡せば、これまでどおり両方を比べられる。
UNITS = ["shot", "mark"];
DEFAULT_METHODS = struct("shot", "ioptimal", "mark", "mark");
methods = reshape(string(sampling.method), 1, []);
unit = "shot";
if isfield(sampling, "unit") && isscalar(string(sampling.unit)) && any(string(sampling.unit) == UNITS)
    unit = string(sampling.unit);
end
shotMethods = alignest.samplingUnitMethods("shot");
markMethods = alignest.markPlanTypes();
hasShot = any(ismember(methods, shotMethods(shotMethods ~= "excel")));
hasMark = any(ismember(methods, markMethods));
if hasShot && ~hasMark
    unit = "shot";
elseif hasMark && ~hasShot
    unit = "mark";
end
kept = methods(ismember(methods, alignest.samplingUnitMethods(unit)));
if isempty(kept)
    kept = DEFAULT_METHODS.(unit);
end
sampling.unit = unit;
sampling.method = kept;
end
