function [names, labels] = gamTerms(featureSet)
%GAMTERMS 説明変数の組で GAM に入る平滑項の名前と、画面に出す名前。
%   XY：s(x, y)、XYR：s(x, y) + s(r)
names = ["xy", "r"];
labels = ["X・Y", "半径"];
switch string(featureSet)
    case "XY"
        count = 1;
    case "XYR"
        count = 2;
    otherwise
        error('alignest:featureSet', '説明変数の組は XY・XYR のいずれかです: %s', featureSet);
end
names = names(1:count);
labels = labels(1:count);
end
