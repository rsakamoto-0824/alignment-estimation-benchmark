function [trainCodes, testCodes, levels] = effectCoding(trainLevels, testLevels)
%EFFECTCODING 質的変数の効果コード（和が0になる表し方、水準数 − 1 列）。
%   水準は学習点にある値を昇順に並べたもの。最後の水準の行は全列 −1。
%   学習点にない水準の評価点は全列 0（全水準の平均の効果）にする。
%   学習点の水準が1つ以下なら効果を推定できないので 0 列を返す。
trainLevels = trainLevels(:);
testLevels = testLevels(:);
levels = unique(trainLevels(~isnan(trainLevels)));
nColumns = max(numel(levels) - 1, 0);
trainCodes = zeros(numel(trainLevels), nColumns);
testCodes = zeros(numel(testLevels), nColumns);
for column = 1:nColumns
    trainCodes(:, column) = (trainLevels == levels(column)) - (trainLevels == levels(end));
    testCodes(:, column) = (testLevels == levels(column)) - (testLevels == levels(end));
end
end
