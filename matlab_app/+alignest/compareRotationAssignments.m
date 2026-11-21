function comparison = compareRotationAssignments(variability, metric, thresholds, nMaps, options)
%COMPAREROTATIONASSIGNMENTS 計測マップの振り分け方（I 最適・D 最適・Sobol 列・ポアソンディスク・ランダム・表の順）を、
%   同じ優先度・マップの数で作って比べる（「8. 計測Mapローテ」の振り分けの比較）。
%   comparison = alignest.compareRotationAssignments(variability, metric, thresholds, nMaps)
%   comparison = alignest.compareRotationAssignments(..., 名前と値の組)
%   名前と値の組は alignest.rotationMaps と同じ（thresholdKind・outerRadiusMm・seed・priorityShotNos・waferRadiusMm・
%   designOrder・designFeatures）と、assignments（比べる振り分け。既定はすべて）。
%   comparison.table：振り分けごとの指標（alignest.rotationMapMetrics。どれも小さいほど良い）と計算の時間。作れなかった
%   振り分けは NaN で、理由は comparison.messages。comparison.maps：振り分けごとの計測マップ（作れなければ []）。
%   comparison.assignments・labels：振り分けの名前と画面の名前。
arguments
    variability struct
    metric (1, 1) string
    thresholds double
    nMaps double
    options.thresholdKind (1, 1) string = "value"
    options.outerRadiusMm (1, 1) double = NaN
    options.seed (1, 1) double = 0
    options.priorityShotNos double = zeros(1, 0)
    options.waferRadiusMm (1, 1) double {mustBePositive} = 150
    options.designOrder (1, 1) double {mustBeInteger, mustBePositive} = 5
    options.designFeatures (1, 1) string = "XYR"
    options.assignments (1, :) string = alignest.rotationAssignments()
end
[~, allLabels] = alignest.rotationAssignments();
[known, position] = ismember(options.assignments, alignest.rotationAssignments());
if ~all(known)
    error('alignest:rotationMaps', '振り分けの名前が正しくありません: %s', strjoin(options.assignments(~known), "・"));
end
labels = allLabels(position);
nAssignments = numel(options.assignments);
values = nan(nAssignments, 8);
messages = strings(nAssignments, 1);
maps = cell(nAssignments, 1);
for k = 1:nAssignments
    started = tic;
    try
        maps{k} = alignest.rotationMaps(variability, metric, thresholds, nMaps, thresholdKind=options.thresholdKind, ...
            outerRadiusMm=options.outerRadiusMm, assignment=options.assignments(k), seed=options.seed, ...
            priorityShotNos=options.priorityShotNos, waferRadiusMm=options.waferRadiusMm, ...
            designOrder=options.designOrder, designFeatures=options.designFeatures);
        result = alignest.rotationMapMetrics(maps{k}, waferRadiusMm=options.waferRadiusMm, ...
            designOrder=options.designOrder, designFeatures=options.designFeatures);
        values(k, :) = [result.klBetween, result.klWhole, result.fillDistanceMm, result.meanI, result.maxI, ...
            result.meanD, result.maxD, toc(started)];
    catch err
        messages(k) = labels(k) + "：" + err.message;
        maps{k} = [];
    end
end
table_ = array2table(values, 'VariableNames', ["マップ間の KL", "全体との KL", "最大の空白 [mm]", "I 基準（平均）", ...
    "I 基準（最大）", "D 基準（平均）", "D 基準（最大）", "計算の時間 [s]"]);
table_ = [table(labels(:), 'VariableNames', "振り分け"), table_];
comparison = struct("table", table_, "maps", {maps}, "assignments", options.assignments, "labels", labels, ...
    "messages", messages(messages ~= ""));
end
