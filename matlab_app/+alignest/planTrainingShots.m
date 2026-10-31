function plan = planTrainingShots(unit, spec, sampling, waferRadiusMm)
%PLANTRAININGSHOTS 1つの Wafer（評価の単位）で、学習に使う Shot を選ぶ。
%   候補は、X か Y の有効な計測値を1点以上持つ Shot。選ばなかった候補 Shot の Mark を評価に使う。
%   I 最適の基準モデルは XY 多項式（sampling.designOrder 次）。候補の全 Mark で正規直交化して使う。
%   制約（sampling.constraints）：同心円の区画（Shot 中心の半径 [mm] を radialZoneEdgesMm で区切る）、
%   4象限（Shot 中心の偏角、軸上は反時計回りに次の象限）、Scan方向。各区画の Shot 数を割合 × 選ぶ数 ± slack に収める。
%   乱数は sampling.seed・Shot 数・繰り返し番号から決めるので、候補が同じ Wafer では同じ Shot が選ばれる。
%   Excel で指定したパターン（type "manual"）：spec.shotNos の Shot（spec.markNos があれば、その Shot・Mark の組の Mark）を
%   学習に使う。Excel で指定した優先順（type "file"）：spec.required の項目は必ず学習に使い、残りを spec.shotNos の順に
%   足して学習 Shot 数にする（Mark 単位は、Mark の数 = round(spec.markPerShot × 候補 Shot 数)、計測率で決めるときは
%   round(spec.rate / 100 × 候補の全 Mark の数)）。Wafer に無い Shot・Mark、計測できない Shot・Mark は飛ばす。
%   計測率（spec.rate [%]）で決めるときは、学習 Shot 数 = round(計測率 / 100 × 候補 Shot 数)（1 以上）。
%   I 最適・ランダムでは、必ず計測する Shot（alignest.requiredShotIndex：指定した shotNo と最外周）を先に入れ、
%   残りを選ぶ（拡張 I 最適計画）。必ず計測する Shot が学習 Shot 数以上なら、それだけを使う。
%   plan.requiredShotIndex は必ず計測した Shot（ファイルの優先順では優先度 1）。
%   制約付き D 最適（doptimal）は、I 最適と同じ制約・必ず計測する Shot で、det(M) を大きくする組を選ぶ
%   （alignest.exchangeDesign）。
%   Mark 単位の I 最適（mark）・D 最適（markd）：計測する Mark を I 最適（D 最適）で選ぶ。
%   Mark の数 = round(spec.markPerShot × 候補 Shot 数)、計測率で決めるときは round(spec.rate / 100 × 候補の全 Mark の数)。
%   sampling.markRequirePerShot が true（既定）なら、各 Shot で markMinPerShot 点（既定 1。Mark の少ない Shot は
%   その Shot の全 Mark）以上を必ず計測する（足りないときは Mark の数を増やし、plan.message に書く）。false なら
%   Shot を問わず選ぶ（計測しない Shot もある）。sampling.constraints.markRatio が true（既定）なら、
%   Mark 番号ごとの計測する数を、全計測（候補の全 Mark）での割合 × Mark の数 ± 許容幅にそろえる。
%   plan.markIndex に計測する Mark（unit.marks の何番目か）を入れる（Shot 単位の選び方では空）。plan.shotIndex は
%   計測する Mark のある Shot。
%   plan.nMarks は学習に使う Mark の数（その軸が有効な Mark。X・Y のどちらか）。
%   選び方によらず、選んだ組の I 基準 tr(M⁻¹) と D 基準 det(M)^(−1/p)、全計測に対する I 効率・D 効率を求める
%   （alignest.designCriteria。基準モデルの項数より学習点が少ないなど、求められないときは NaN）。
shots = unit.shots;
candidates = find(shots.nValidX + shots.nValidY > 0);
plan = struct("label", spec.label, "group", spec.group, "type", spec.type, "repeat", spec.repeat, ...
    "shotIndex", zeros(0, 1), "shotNos", zeros(0, 1), "nShots", 0, "criterion", NaN, ...
    "violation", 0, "criterionI", NaN, "criterionD", NaN, "ok", false, "message", "", ...
    "requiredShotIndex", zeros(0, 1), "rate", NaN, "efficiencyI", NaN, "efficiencyD", NaN, "markIndex", zeros(0, 1), ...
    "nMarks", 0);
nShots = spec.nShots;
if isfield(spec, "rate") && isfinite(spec.rate)
    plan.rate = spec.rate;
    nShots = max(1, round(spec.rate / 100 * numel(candidates)));
end
if any(spec.type == ["manual", "file"]) && isfield(spec, "markNos") && ~isempty(spec.markNos)
    plan = markListPlan(unit, spec, sampling, waferRadiusMm, candidates, plan);   % Excel で指定した Mark
    return
end
switch spec.type
    case "manual"
        [found, position] = ismember(spec.shotNos(:), shots.shotNo);
        missingNos = spec.shotNos(~found);
        chosen = unique(position(found));
        chosen = chosen(ismember(chosen, candidates));
        if ~isempty(missingNos)
            plan.message = "この Wafer に無い shotNo：" + strjoin(string(missingNos), " ");
        end
        if isempty(chosen)
            plan.message = strtrim(plan.message + " 学習に使える Shot がありません。");
            return
        end
        plan.shotIndex = chosen(:);
    case "file"
        [plan.shotIndex, plan.message, plan.requiredShotIndex] = priorityShots(shots, candidates, spec, nShots);
        if isempty(plan.shotIndex)
            return
        end
    case {"mark", "markd"}
        plan = markPlan(unit, spec, sampling, waferRadiusMm, candidates, plan);
        return
    case {"ioptimal", "doptimal", "random"}
        if nShots >= numel(candidates)
            plan.message = sprintf("学習 Shot 数 %d が候補の Shot 数 %d 以上なので、評価する Shot が残りません。", ...
                nShots, numel(candidates));
            return
        end
        [plan.requiredShotIndex, required] = alignest.requiredShotIndex(shots, candidates, sampling);
        if ~isempty(required.missingNos)
            plan.message = "必ず計測する Shot のうち、この Wafer に無い、または計測値の無い shotNo：" + ...
                strjoin(string(required.missingNos.'), " ") + "。";
        end
        fixed = ismember(candidates, plan.requiredShotIndex);
        if nnz(fixed) >= nShots
            plan.shotIndex = plan.requiredShotIndex;
            if nnz(fixed) > nShots
                plan.message = strtrim(plan.message + sprintf(" 必ず計測する Shot が %d 個あり、学習 Shot 数 %d より" + ...
                    "多いので、必ず計測する Shot だけを使いました。", nnz(fixed), nShots));
            end
        else
            labels = partitionLabels(shots, candidates, sampling, waferRadiusMm, unit.hasDirection);
            stream = RandStream('mt19937ar', 'Seed', seedFor(sampling.seed, nShots, spec.repeat));
            if spec.type == "ioptimal"
                blocks = shotBlocks(unit, candidates, sampling.designOrder, waferRadiusMm);
                [selected, plan.criterion, plan.violation] = alignest.constrainedIOptimal(blocks, nShots, labels, ...
                    sampling.constraints.slack, stream, sampling.exchangeStarts, sampling.exchangeMaxIterations, fixed);
            elseif spec.type == "doptimal"
                blocks = shotBlocks(unit, candidates, sampling.designOrder, waferRadiusMm);
                [selected, plan.criterion, plan.violation] = alignest.exchangeDesign(blocks, nShots, labels, ...
                    sampling.constraints.slack, stream, sampling.exchangeStarts, sampling.exchangeMaxIterations, ...
                    criterion="D", fixed=fixed);
            else
                [chosen, plan.violation] = alignest.randomFeasibleShots(numel(candidates), nShots, labels, ...
                    sampling.constraints.slack, stream, fixed);
                selected = find(chosen);
            end
            plan.shotIndex = candidates(selected(:));
            if plan.violation > 0 && any(fixed)
                plan.message = strtrim(plan.message + sprintf(" 必ず計測する Shot を入れると制約（同心円・4象限・" + ...
                    "Scan 方向の Shot 数）を満たせないため、違反量 %d の組を使いました（残りは違反が少なくなるように選んだ）。", ...
                    plan.violation));
            elseif plan.violation > 0
                plan.message = strtrim(plan.message + sprintf(" 制約を満たす組が見つからず、違反量 %d の組を使いました。", ...
                    plan.violation));
            end
        end
    otherwise
        error('alignest:samplingMethod', '学習 Shot の選び方が正しくありません: %s', spec.type);
end
if numel(plan.shotIndex) >= numel(candidates)
    plan.message = strtrim(plan.message + " 全候補 Shot が学習に入り、評価する Shot が残りません。");
    plan.shotIndex = zeros(0, 1);
    return
end
plan.shotIndex = sort(plan.shotIndex);
plan.shotNos = shots.shotNo(plan.shotIndex);
plan.nShots = numel(plan.shotIndex);
plan.nMarks = nnz(ismember(unit.marks.shotIndex, plan.shotIndex) & (unit.marks.validX | unit.marks.validY));
plan.ok = true;
[plan.criterionI, plan.criterionD, plan.efficiencyI, plan.efficiencyD] = planCriteria(unit, candidates, plan.shotIndex, ...
    sampling.designOrder, waferRadiusMm);
end

function plan = markPlan(unit, spec, sampling, waferRadiusMm, candidates, plan)
% Mark 単位の I 最適・D 最適：（各 Shot で n 点以上を計測し、）Mark 番号の割合をそろえて、計測する Mark を交換法で選ぶ
marks = unit.marks;
markCandidates = find(ismember(marks.shotIndex, candidates) & (marks.validX | marks.validY));
[~, ~, groupOfMark] = unique(marks.shotIndex(markCandidates));
nGroups = max(groupOfMark);
criterion = "I";
if spec.type == "markd"
    criterion = "D";
end
if isfinite(plan.rate)
    nMarks = max(1, round(plan.rate / 100 * numel(markCandidates)));
    sizeText = sprintf("計測率 %g%% の Mark の数 %d", plan.rate, nMarks);
else
    nMarks = max(1, round(spec.markPerShot * nGroups));
    sizeText = sprintf("1 Shot あたり %g 点の Mark の数 %d", spec.markPerShot, nMarks);
end
requirePerShot = ~isfield(sampling, "markRequirePerShot") || sampling.markRequirePerShot;
minPerShot = 1;
if isfield(sampling, "markMinPerShot") && ~isempty(sampling.markMinPerShot)
    minPerShot = max(1, round(double(sampling.markMinPerShot)));
end
group = zeros(0, 1);
if requirePerShot
    % 各 Shot で n 点（Mark の少ない Shot はその Shot の全 Mark）。合わせた数に足りなければ Mark の数を増やす
    perGroup = accumarray(groupOfMark, 1);
    minimumTotal = sum(min(minPerShot, perGroup));
    if nMarks < minimumTotal
        plan.message = sprintf("%s では各 Shot %d 点を計測できないため、%d 点にしました。", sizeText, minPerShot, ...
            minimumTotal);
        nMarks = minimumTotal;
    end
    group = groupOfMark;
end
if nMarks >= numel(markCandidates)
    plan.message = sprintf("計測する Mark の数 %d が候補の Mark の数 %d 以上なので、評価する Mark が残りません。", ...
        nMarks, numel(markCandidates));
    return
end
blocks = markBlocks(unit, markCandidates, sampling.designOrder, waferRadiusMm);
labels = zeros(numel(markCandidates), 0);
if ~isfield(sampling.constraints, "markRatio") || sampling.constraints.markRatio
    [~, ~, labels] = unique(marks.markNo(markCandidates));
end
stream = RandStream('mt19937ar', 'Seed', seedFor(sampling.seed, nMarks, spec.repeat));
[selected, plan.criterion, plan.violation] = alignest.exchangeDesign(blocks, nMarks, labels, ...
    sampling.constraints.slack, stream, sampling.exchangeStarts, sampling.exchangeMaxIterations, criterion=criterion, ...
    group=group, minPerGroup=minPerShot);
if plan.violation > 0
    plan.message = strtrim(plan.message + sprintf(" Mark 番号ごとの数をそろえる制約を満たす組が見つからず、" + ...
        "違反量 %d の組を使いました。", plan.violation));
end
plan.markIndex = sort(markCandidates(selected(:)));
plan.shotIndex = unique(marks.shotIndex(plan.markIndex));   % 計測する Mark のある Shot（各 Shot で必ず計測するなら全候補）
plan.nShots = numel(plan.shotIndex);
plan.shotNos = unit.shots.shotNo(plan.shotIndex);
plan.nMarks = numel(plan.markIndex);
plan.ok = true;
[plan.criterionI, plan.criterionD, plan.efficiencyI, plan.efficiencyD] = alignest.designCriteria(blocks(selected));
end

function blocks = markBlocks(unit, markCandidates, designOrder, waferRadiusMm)
% 候補 Mark ごとの基底の行（全候補 Mark で正規直交化した XY 多項式。Shot 単位の shotBlocks と同じ正規化）
marks = unit.marks;
design = alignest.basis.polynomialDesign(marks.x(markCandidates) / waferRadiusMm, ...
    marks.y(markCandidates) / waferRadiusMm, designOrder);
if size(design, 1) < size(design, 2)
    error('alignest:designOrder', 'I 最適の基準モデル（%d 次、%d 項）より候補の Mark（%d 点）が少ないです。次数を下げてください。', ...
        designOrder, size(design, 2), size(design, 1));
end
[q, ~] = qr(design, 0);
blocks = num2cell(q, 2);
end

function [iValue, dValue, iEfficiency, dEfficiency] = planCriteria(unit, candidates, shotIndex, designOrder, waferRadiusMm)
% 選んだ組の I 基準・D 基準と全計測に対する効率。候補の Mark が基準モデルの項数より少ないときは NaN
iValue = NaN;
dValue = NaN;
iEfficiency = NaN;
dEfficiency = NaN;
try
    blocks = shotBlocks(unit, candidates, designOrder, waferRadiusMm);
catch
    return
end
[~, selected] = ismember(shotIndex, candidates);
[iValue, dValue, iEfficiency, dEfficiency] = alignest.designCriteria(blocks(selected));
end

function [shotIndex, message, required] = priorityShots(shots, candidates, spec, nShots)
% 優先順：必ず計測する Shot（spec.required）を全部、残りを spec.shotNos の順に。required は必ず計測した Shot
message = "";
shotNos = spec.shotNos(:);
flags = requiredFlags(spec);
[found, position] = ismember(shotNos, shots.shotNo);
usable = found & ismember(position, candidates);
missing = unique(shotNos(~usable));
if ~isempty(missing)
    message = "この Wafer に無い、または計測できない優先順の Shot：" + strjoin(string(missing.'), " ") + "。";
end
required = unique(position(usable & flags), 'stable');
ordered = position(usable & ~flags);
[~, firstPosition] = unique(ordered, 'stable');
ordered = ordered(sort(firstPosition));
ordered = ordered(~ismember(ordered, required));
if numel(required) >= nShots
    shotIndex = required;
    if numel(required) > nShots
        message = strtrim(message + sprintf(" 必ず計測する Shot が %d 個あり、学習 Shot 数 %d より多いので、すべて使いました。", ...
            numel(required), nShots));
    end
else
    added = ordered(1:min(nShots - numel(required), numel(ordered)));
    shotIndex = [required; added];
    if numel(shotIndex) < nShots
        message = strtrim(message + sprintf(" 優先順のファイルで使える Shot が %d 個しかなく、学習 Shot 数 %d に足りません。", ...
            numel(shotIndex), nShots));
    end
end
if isempty(shotIndex)
    message = strtrim(message + " 学習に使える Shot がありません。");
end
shotIndex = shotIndex(:);
required = required(:);
end

function plan = markListPlan(unit, spec, sampling, waferRadiusMm, candidates, plan)
% Excel で指定した Mark：パターン（manual）はその Mark、優先順（file）は必ず計測する Mark と、残りを順に足して Mark の数にする
marks = unit.marks;
markCandidates = find(ismember(marks.shotIndex, candidates) & (marks.validX | marks.validY));
keys = [spec.shotNos(:), spec.markNos(:)];
[found, position] = ismember(keys, [marks.shotNo, marks.markNo], 'rows');
usable = found & ismember(position, markCandidates);
if any(~usable)
    missing = unique(compose("%g-%g", keys(~usable, 1), keys(~usable, 2)), 'stable');
    plan.message = "この Wafer に無い、または計測値の無い Mark（shotNo-markNo）：" + strjoin(missing(:).', " ") + "。";
end
if spec.type == "manual"
    chosen = unique(position(usable), 'stable');
else
    nGroups = numel(unique(marks.shotIndex(markCandidates)));
    if isfinite(plan.rate)
        nMarks = max(1, round(plan.rate / 100 * numel(markCandidates)));
    else
        nMarks = max(1, round(spec.markPerShot * nGroups));
    end
    flags = requiredFlags(spec);
    required = unique(position(usable & flags), 'stable');
    ordered = unique(position(usable & ~flags), 'stable');
    ordered = ordered(~ismember(ordered, required));
    if numel(required) >= nMarks
        chosen = required;
        if numel(required) > nMarks
            plan.message = strtrim(plan.message + sprintf(" 必ず計測する Mark が %d 個あり、計測する Mark の数 %d より" + ...
                "多いので、すべて使いました。", numel(required), nMarks));
        end
    else
        chosen = [required; ordered(1:min(nMarks - numel(required), numel(ordered)))];
        if numel(chosen) < nMarks
            plan.message = strtrim(plan.message + sprintf(" 優先順で使える Mark が %d 個しかなく、計測する Mark の数 %d に" + ...
                "足りません。", numel(chosen), nMarks));
        end
    end
end
if isempty(chosen)
    plan.message = strtrim(plan.message + " 学習に使える Mark がありません。");
    return
end
if numel(chosen) >= numel(markCandidates)
    plan.message = strtrim(plan.message + " 全候補 Mark が学習に入り、評価する Mark が残りません。");
    return
end
plan.markIndex = sort(chosen(:));
plan.shotIndex = unique(marks.shotIndex(plan.markIndex));
plan.nShots = numel(plan.shotIndex);
plan.shotNos = unit.shots.shotNo(plan.shotIndex);
plan.nMarks = numel(plan.markIndex);
plan.ok = true;
try
    blocks = markBlocks(unit, markCandidates, sampling.designOrder, waferRadiusMm);
    [~, selected] = ismember(plan.markIndex, markCandidates);
    [plan.criterionI, plan.criterionD, plan.efficiencyI, plan.efficiencyD] = alignest.designCriteria(blocks(selected));
catch
    % 候補の Mark が基準モデルの項数より少ないときは、I 基準・D 基準を求めない（NaN のまま）
end
end

function flags = requiredFlags(spec)
% 優先順で必ず計測する項目（spec.required。無ければすべて false）
flags = false(numel(spec.shotNos), 1);
if isfield(spec, "required") && numel(spec.required) == numel(spec.shotNos)
    flags = logical(spec.required(:));
end
end

function seed = seedFor(baseSeed, nShots, repeat)
seed = mod(round(baseSeed) + 1000 * nShots + 7919 * repeat, 2^32);
end

function labels = partitionLabels(shots, candidates, sampling, waferRadiusMm, hasDirection)
% 候補 Shot × 制約の種類 の区分番号（1始まり）
constraints = sampling.constraints;
labels = zeros(numel(candidates), 0);
edges = alignest.zoneEdgesMm(sampling, waferRadiusMm);
if ~isempty(edges)
    labels(:, end + 1) = 1 + sum(shots.radius(candidates) >= edges, 2);
end
if constraints.quadrants
    angle = mod(atan2(shots.Ymm(candidates), shots.Xmm(candidates)), 2 * pi);
    labels(:, end + 1) = mod(floor(angle / (pi / 2)), 4) + 1;
end
if constraints.scanDirection && hasDirection
    labels(:, end + 1) = shots.direction(candidates);
end
% 区分番号を 1, 2, … に詰める（使われない番号があると下限が 0 の区分ができるだけなので、詰めて扱う）
for p = 1:size(labels, 2)
    [~, ~, labels(:, p)] = unique(labels(:, p));
end
end

function blocks = shotBlocks(unit, candidates, designOrder, waferRadiusMm)
% 候補 Shot ごとの基底（全候補 Mark で正規直交化した XY 多項式）
marks = unit.marks;
useMark = ismember(marks.shotIndex, candidates) & (marks.validX | marks.validY);
design = alignest.basis.polynomialDesign(marks.x(useMark) / waferRadiusMm, marks.y(useMark) / waferRadiusMm, designOrder);
if size(design, 1) < size(design, 2)
    error('alignest:designOrder', 'I 最適の基準モデル（%d 次、%d 項）より候補の Mark（%d 点）が少ないです。次数を下げてください。', ...
        designOrder, size(design, 2), size(design, 1));
end
[q, ~] = qr(design, 0);
shotOfRow = marks.shotIndex(useMark);
blocks = cell(numel(candidates), 1);
for k = 1:numel(candidates)
    blocks{k} = q(shotOfRow == candidates(k), :);
end
end
