function types = markPlanTypes()
%MARKPLANTYPES Mark 単位の学習パターンの選び方（計測する Shot ではなく Mark を選ぶ）。
%   "mark"（Mark 単位の I 最適）・"markd"（Mark 単位の D 最適）・"markrandom"（Mark 単位の制約つきランダム）。
%   画面・時間の目安・書き出しで、Mark 単位の計画かを見分けるのに使う（alignest.planTrainingShots・buildPlanSpecs）。
types = ["mark", "markd", "markrandom"];
end
