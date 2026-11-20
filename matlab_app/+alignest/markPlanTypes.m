function types = markPlanTypes()
%MARKPLANTYPES Mark 単位の学習パターンの選び方（計測する Shot ではなく Mark を選ぶ）。
%   "mark"（Mark 単位の I 最適）・"markd"（Mark 単位の D 最適）・"marksobol"（Mark 単位の Sobol 列）・
%   "markpoisson"（Mark 単位のポアソンディスク）・"markrandom"（Mark 単位のランダム）。Shot 単位の ioptimal・doptimal・
%   sobol・poisson・random と同じ並び（alignest.samplingUnitMethods。画面の表示順）。
%   画面・時間の目安・書き出しで、Mark 単位の計画かを見分けるのに使う（alignest.planTrainingShots・buildPlanSpecs）。
types = ["mark", "markd", "marksobol", "markpoisson", "markrandom"];
end
