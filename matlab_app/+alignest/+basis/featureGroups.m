function groups = featureGroups(featureSet)
%FEATUREGROUPS distanceFeatures の各列が属する説明変数の番号（1始まり）。
%   ARD カーネルは番号ごとに長さスケールを1つ持つ。XYRT の cos θ・sin θ は T（方位角）1変数の展開なので同じ番号にする。
switch featureSet
    case 'XY'
        groups = [1, 2];
    case 'XYR'
        groups = [1, 2, 3];
    case 'XYRT'
        groups = [1, 2, 3, 4, 4];
    otherwise
        error('alignest:featureSet', '説明変数の組は XY・XYR・XYRT のいずれかです: %s', featureSet);
end
end
