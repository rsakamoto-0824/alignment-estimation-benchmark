function plan = planTrainingShots(unit, spec, sampling, waferRadiusMm)
%PLANTRAININGSHOTS 1つの Wafer（評価の単位）で、学習に使う Shot を選ぶ。
%   候補は、X か Y の有効な計測値を1点以上持つ Shot。選ばなかった候補 Shot の Mark を評価に使う。
%   I 最適の基準モデルは XY 多項式（sampling.designOrder 次）。候補の全 Mark で正規直交化して使う。
%   制約（sampling.constraints）：同心円の区画（Shot 中心の半径 / Wafer 半径 を radialZoneEdges で区切る）、
%   4象限（Shot 中心の偏角、軸上は反時計回りに次の象限）、Scan方向。各区画の Shot 数を割合 × 選ぶ数 ± slack に収める。
%   乱数は sampling.seed・Shot 数・繰り返し番号から決めるので、候補が同じ Wafer では同じ Shot が選ばれる。
%   ファイルの優先順（file）：優先度 1 の Shot は必ず学習に使い、残りを優先度 0（計測しない）を除いてファイルの行の順に
%   足して学習 Shot 数にする（sampling.priorityShots・priorityLevels）。Wafer に無い Shot・計測できない Shot は飛ばす。
%   計測率（spec.rate [%]）で決めるときは、学習 Shot 数 = round(計測率 / 100 × 候補 Shot 数)（1 以上）。
%   I 最適・ランダムでは、必ず計測する Shot（alignest.requiredShotIndex：指定した shotNo と最外周）を先に入れ、
%   残りを選ぶ（拡張 I 最適計画）。必ず計測する Shot が学習 Shot 数以上なら、それだけを使う。
%   plan.requiredShotIndex は必ず計測した Shot（ファイルの優先順では優先度 1）。
%   選び方によらず、選んだ組の I 基準 tr(M⁻¹) と D 基準 det(M)^(−1/p) を求める（alignest.designCriteria。
%   基準モデルの項数より学習点が少ないなど、求められないときは NaN）。
shots = unit.shots;
candidates = find(shots.nValidX + shots.nValidY > 0);
plan = struct("label", spec.label, "group", spec.group, "type", spec.type, "repeat", spec.repeat, ...
    "shotIndex", zeros(0, 1), "shotNos", zeros(0, 1), "nShots", 0, "criterion", NaN, ...
    "violation", 0, "criterionI", NaN, "criterionD", NaN, "ok", false, "message", "", ...
    "requiredShotIndex", zeros(0, 1), "rate", NaN);
nShots = spec.nShots;
if isfield(spec, "rate") && isfinite(spec.rate)
    plan.rate = spec.rate;
    nShots = max(1, round(spec.rate / 100 * numel(candidates)));
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
        [plan.shotIndex, plan.message, plan.requiredShotIndex] = priorityShots(shots, candidates, sampling, nShots);
        if isempty(plan.shotIndex)
            return
        end
    case {"ioptimal", "random"}
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
plan.ok = true;
[plan.criterionI, plan.criterionD] = planCriteria(unit, candidates, plan.shotIndex, sampling.designOrder, waferRadiusMm);
end

function [iValue, dValue] = planCriteria(unit, candidates, shotIndex, designOrder, waferRadiusMm)
% 選んだ組の I 基準・D 基準。候補の Mark が基準モデルの項数より少ないときは NaN
iValue = NaN;
dValue = NaN;
try
    blocks = shotBlocks(unit, candidates, designOrder, waferRadiusMm);
catch
    return
end
[~, selected] = ismember(shotIndex, candidates);
[iValue, dValue] = alignest.designCriteria(blocks(selected));
end

function [shotIndex, message, required] = priorityShots(shots, candidates, sampling, nShots)
% 優先度 1 を全部、残りを行の順に（優先度 0 は使わない）。required は優先度 1 の Shot
message = "";
shotNos = sampling.priorityShots(:);
levels = sampling.priorityLevels(:);
if numel(levels) ~= numel(shotNos)
    levels = nan(size(shotNos));
end
[found, position] = ismember(shotNos, shots.shotNo);
usable = found & ismember(position, candidates);
missing = unique(shotNos(~usable));
if ~isempty(missing)
    message = "この Wafer に無い、または計測できない優先順の Shot：" + strjoin(string(missing.'), " ") + "。";
end
excluded = unique(position(usable & levels == 0));
required = unique(position(usable & levels == 1), 'stable');
required = setdiff(required, excluded, 'stable');
ordered = position(usable & levels ~= 0 & levels ~= 1);
[~, firstPosition] = unique(ordered, 'stable');
ordered = ordered(sort(firstPosition));
ordered = ordered(~ismember(ordered, [required; excluded]));
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

function seed = seedFor(baseSeed, nShots, repeat)
seed = mod(round(baseSeed) + 1000 * nShots + 7919 * repeat, 2^32);
end

function labels = partitionLabels(shots, candidates, sampling, waferRadiusMm, hasDirection)
% 候補 Shot × 制約の種類 の区分番号（1始まり）
constraints = sampling.constraints;
labels = zeros(numel(candidates), 0);
edges = sort(constraints.radialZoneEdges(:)).';
edges = edges(edges > 0 & edges < 1);
if ~isempty(edges)
    rho = shots.radius(candidates) / waferRadiusMm;
    labels(:, end + 1) = 1 + sum(rho >= edges, 2);
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
