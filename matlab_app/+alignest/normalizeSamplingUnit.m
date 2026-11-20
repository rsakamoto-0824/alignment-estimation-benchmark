function sampling = normalizeSamplingUnit(sampling)
%NORMALIZESAMPLINGUNIT データの粒度（sampling.unit："shot"・"mark"）と計測点の選び方（sampling.method）をそろえる。
%   sampling = alignest.normalizeSamplingUnit(sampling)
%   画面では粒度を1つ選び、アルゴリズムはどちらの粒度にも共通なので、設定を画面に出す前にそろえる。
%   粒度は選び方から決める：Shot 単位の選び方だけなら "shot"、Mark 単位の選び方だけなら "mark"、「Excel 取込」
%   だけ・空なら sampling.unit のまま（無ければ "shot"）。両方の選び方がある以前の設定は sampling.unit（無ければ
%   Shot 単位）にし、別の粒度の選び方は同じアルゴリズムに直す（例：Shot 単位で mark → ioptimal。
%   alignest.convertSamplingMethods）。選び方が無ければ、その粒度の I 最適にする。
%   計算（alignest.buildPlanSpecs）は粒度を見ないので、関数から両方の選び方を渡せば、これまでどおり両方を比べられる。
UNITS = ["shot", "mark"];
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
kept = alignest.convertSamplingMethods(methods, unit);
if isempty(kept)
    defaults = alignest.samplingUnitMethods(unit);
    kept = defaults(1);   % その粒度の I 最適
end
sampling.unit = unit;
sampling.method = kept;
end
