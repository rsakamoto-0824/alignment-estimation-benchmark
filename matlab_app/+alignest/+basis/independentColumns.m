function [train, test] = independentColumns(train, test)
%INDEPENDENTCOLUMNS 学習点で一次従属な列を除く。同じ列を評価点からも除く。
% Scan 方向と Shot 行の奇偶が一致する場合などに係数を一意にする。
keep = false(1, size(train, 2));
for column = 1:size(train, 2)
    keep(column) = true;
    if rank(train(:, keep)) < nnz(keep)
        keep(column) = false;
    end
end
train = train(:, keep);
test = test(:, keep);
end
