function plan = cachedTrainingPlan(unit, spec, settings, planCache)
%CACHEDTRAININGPLAN 1つの Wafer の学習パターン（alignest.planTrainingShots）を作る。
%   plan = alignest.cachedTrainingPlan(unit, spec, settings, planCache)
%   候補 Shot と使える Mark が同じ Wafer では、同じ学習パターンを使い回す（planCache は呼ぶ側で作る
%   containers.Map。手動はそのまま作る）。Shot（Mark 単位の計画では Mark も）は座標で対応づけ直す。
%   plan.seconds は学習パターンを作るのにかかった時間（使い回したときは 0、reused = true）。
timer = tic;
if spec.type == "manual"
    plan = alignest.planTrainingShots(unit, spec, settings.sampling, settings.data.waferRadiusMm);
    plan = addPlanFields(plan, toc(timer), false);
    return
end
marks = unit.marks;
usable = marks.validX | marks.validY;
signature = sprintf('%.3f,', [marks.x(usable); marks.y(usable); marks.direction(usable)]);
key = [char(spec.label), '|', signature];
shotKey = round([unit.shots.Xmm, unit.shots.Ymm], 3);
if isKey(planCache, key)
    cached = planCache(key);
    plan = cached.plan;
    [~, plan.shotIndex] = ismember(cached.coordinates, shotKey, 'rows');
    [~, plan.requiredShotIndex] = ismember(cached.requiredCoordinates, shotKey, 'rows');
    [~, plan.markIndex] = ismember(cached.markCoordinates, markKey(unit), 'rows');
    plan.shotNos = unit.shots.shotNo(plan.shotIndex);
    plan.seconds = 0;
    plan.reused = true;
    return
end
plan = alignest.planTrainingShots(unit, spec, settings.sampling, settings.data.waferRadiusMm);
plan = addPlanFields(plan, toc(timer), false);
keys = markKey(unit);
planCache(key) = struct("plan", plan, "coordinates", shotKey(plan.shotIndex, :), ...
    "requiredCoordinates", shotKey(plan.requiredShotIndex, :), "markCoordinates", keys(plan.markIndex, :));
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
