function inTrain = trainingMarks(unit, training)
%TRAININGMARKS 学習に使う Mark（unit.marks の並びの論理ベクトル。計測値の有効・無効は見ない）。
%   inTrain = alignest.trainingMarks(unit, plan)          % 学習パターン（alignest.planTrainingShots の結果）
%   inTrain = alignest.trainingMarks(unit, shotIndex)     % 学習 Shot の番号（unit.shots の何番目か）
%   学習パターンの markIndex（Mark 単位の計画）が空でなければその Mark、空なら学習 Shot のすべての Mark。
marks = unit.marks;
if isstruct(training)
    if isfield(training, "markIndex") && ~isempty(training.markIndex)
        inTrain = false(numel(marks.x), 1);
        inTrain(training.markIndex) = true;
        return
    end
    training = training.shotIndex;
end
inTrain = ismember(marks.shotIndex, training);
end
