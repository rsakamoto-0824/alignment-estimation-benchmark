function plan = cachedTrainingPlan(unit, spec, settings, planCache)
%CACHEDTRAININGPLAN 1つの Wafer の学習パターン（alignest.planTrainingShots）を作る。
%   plan = alignest.cachedTrainingPlan(unit, spec, settings, planCache)
%   同じ配置の Wafer では、同じ学習パターンを使い回す（planCache は呼ぶ側で作る containers.Map。手動はそのまま作る）。
%   Shot 単位の計画は候補の Shot（計測値が1点以上ある Shot）が同じ Wafer、Mark 単位の計画は使える Mark が同じ Wafer
%   （alignest.planLayoutKey）。Shot（Mark 単位の計画では Mark も）は座標で対応づけ直す。Shot 単位の計画を、Shot の中の
%   Mark の欠けが違う Wafer で使い回すときは、学習に使う Mark の数と I 基準・D 基準を、その Wafer の Mark で求め直す
%   （交換法を解き直さないので、Wafer が多いと評価が速い）。
%   plan.seconds は学習パターンを作るのにかかった時間（使い回したときは 0、reused = true）。
timer = tic;
if spec.type == "manual"
    plan = alignest.planTrainingShots(unit, spec, settings.sampling, settings.data.waferRadiusMm);
    plan = addPlanFields(plan, toc(timer), false);
    return
end
level = alignest.planSpecLevel(spec);
markLayout = alignest.planLayoutKey(unit);
key = [char(spec.label), '|', char(level), '|', alignest.planLayoutKey(unit, level)];
shotKey = round([unit.shots.Xmm, unit.shots.Ymm], 3);
if isKey(planCache, key)
    cached = planCache(key);
    plan = cached.plan;
    [~, plan.shotIndex] = ismember(cached.coordinates, shotKey, 'rows');
    [~, plan.requiredShotIndex] = ismember(cached.requiredCoordinates, shotKey, 'rows');
    [~, plan.markIndex] = ismember(cached.markCoordinates, markKey(unit), 'rows');
    plan.shotNos = unit.shots.shotNo(plan.shotIndex);
    if ~strcmp(cached.markLayout, markLayout)
        % Shot は同じで Mark の欠けが違う Wafer：学習に使う Mark の数と I 基準・D 基準をこの Wafer の Mark で求め直す
        evaluated = alignest.planTrainingShots(unit, spec, settings.sampling, settings.data.waferRadiusMm, plan.shotIndex);
        plan.nMarks = evaluated.nMarks;
        [plan.criterionI, plan.criterionD, plan.efficiencyI, plan.efficiencyD] = deal(evaluated.criterionI, ...
            evaluated.criterionD, evaluated.efficiencyI, evaluated.efficiencyD);
    end
    plan.seconds = 0;
    plan.reused = true;
    return
end
plan = alignest.planTrainingShots(unit, spec, settings.sampling, settings.data.waferRadiusMm);
plan = addPlanFields(plan, toc(timer), false);
keys = markKey(unit);
planCache(key) = struct("plan", plan, "coordinates", shotKey(plan.shotIndex, :), ...
    "requiredCoordinates", shotKey(plan.requiredShotIndex, :), "markCoordinates", keys(plan.markIndex, :), ...
    "markLayout", markLayout);
end

function key = markKey(unit)
% Mark の座標（Mark 単位の計画を、同じ配置の Wafer で使い回すため）
key = round([unit.marks.x, unit.marks.y], 3);
end

function plan = addPlanFields(plan, seconds, reused)
plan.seconds = seconds;
plan.reused = reused;
plan.unitIndex = 0;
plan.unitLabel = "";
end
