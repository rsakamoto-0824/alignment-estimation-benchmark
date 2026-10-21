function groups = featureGroups(featureSet)
%FEATUREGROUPS distanceFeatures の各列が属する説明変数の番号（1始まり）。
%   ARD カーネルは番号ごとに長さスケールを1つ持つ。
switch featureSet
    case 'XY'
        groups = [1, 2];
    case 'XYR'
        groups = [1, 2, 3];
    otherwise
        error('alignest:featureSet', '説明変数の組は XY・XYR のいずれかです: %s', featureSet);
end
end
