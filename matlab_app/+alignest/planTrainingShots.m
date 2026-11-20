function plan = planTrainingShots(unit, spec, sampling, waferRadiusMm)
%PLANTRAININGSHOTS 1つの Wafer（評価の単位）で、学習に使う Shot を選ぶ。
%   候補は、X か Y の有効な計測値を1点以上持つ Shot。選ばなかった候補 Shot の Mark を評価に使う。
%   I 最適の基準モデルは、説明変数 X・Y・半径（sampling.designFeatures = "XYR"、既定）か X・Y（"XY"）の多項式
%   （sampling.designOrder 次。alignest.basis.designPolynomial）。候補の全 Mark で正規直交化して使う。
%   制約（sampling.constraints。Excel で指定のほかのすべての選び方で使う）：同心円の区画（radialZones が true のとき、
%   Shot 中心の半径 [mm] を radialZoneEdgesMm で区切る）、4象限（quadrants。Shot 中心の偏角、軸上は反時計回りに次の
%   象限）、Scan方向（scanDirection）。各区画の Shot 数を割合 × 選ぶ数 ± slack に収める。Mark 単位は Mark の半径・偏角と、
%   その Mark の Shot の Scan 方向で区画に分け、区画ごとの Mark の数をそろえる。
%   乱数は sampling.seed・Shot 数・繰り返し番号から決めるので、候補が同じ Wafer では同じ Shot が選ばれる。
%   Excel で指定したパターン（type "manual"）：spec.shotNos の Shot（spec.markNos があれば、その Shot・Mark の組の Mark）を
%   学習に使う。Excel で指定した優先順（type "file"）：spec.required の項目は必ず学習に使い、残りを spec.shotNos の順に
%   足して学習 Shot 数にする（Mark 単位は、Mark の数 = round(spec.markPerShot × 候補 Shot 数)、計測率で決めるときは
%   round(spec.rate / 100 × 候補の全 Mark の数)）。Wafer に無い Shot・Mark、計測できない Shot・Mark は飛ばす。
%   計測率（spec.rate [%]）で決めるときは、学習 Shot 数 = round(計測率 / 100 × 候補 Shot 数)（1 以上）。
%   I 最適・ランダム・Sobol 列・ポアソンディスクでは、必ず計測する Shot（alignest.requiredShotIndex：指定した shotNo と最外周）を先に入れ、
%   残りを選ぶ（拡張 I 最適計画）。必ず計測する Shot が学習 Shot 数以上なら、それだけを使う。
%   Sobol 列（sobol）：Wafer 上に偏りなく散らばる Sobol 列の点に近い Shot を、点の順に選ぶ（alignest.sobolSelect。最適化・
%   乱数は使わない。区画の数の上限を超える Shot は選ばない。計測しない Shot は選ばない）。
%   ポアソンディスク（poisson）：Shot 中心どうしの距離が d 以上になるように、乱数の順で Shot を選ぶ（d は学習 Shot 数を
%   選べる最も大きい値。alignest.poissonDiskSelect。区画の数の上限を超える Shot は選ばない。乱数は制約つきランダムと
%   同じく sampling.seed・Shot 数・繰り返し番号から決める）。
%   plan.requiredShotIndex は必ず計測した Shot（ファイルの優先順では優先度 1）。
%   制約付き D 最適（doptimal）は、I 最適と同じ制約・必ず計測する Shot で、det(M) を大きくする組を選ぶ
%   （alignest.exchangeDesign）。
%   Mark 単位の I 最適（mark）・D 最適（markd）：計測する Mark を I 最適（D 最適）で選ぶ。Mark 単位の制約つきランダム
%   （markrandom）：同じ制約（各 Shot の点数・Mark 番号・同心円の区画・必ず計測する Mark）を満たす組を乱数で選ぶ
%   （交換法の初期配置と同じ作り方で、交換はしない。乱数は sampling.seed・Mark の数・繰り返し番号から決める）。
%   Mark 単位の Sobol 列（marksobol）・ポアソンディスク（markpoisson）：Shot 単位と同じ選び方で Mark を選ぶ（必ず計測する
%   Mark は先に入れる。同心円・4象限・Scan 方向の制約は使い、各 Shot の点数・Mark 番号の制約は使わない）。
%   Mark の数 = round(spec.markPerShot × 候補 Shot 数)、計測率で決めるときは round(spec.rate / 100 × 候補の全 Mark の数)。
%   sampling.markRequirePerShot が true（既定）なら、各 Shot で markMinPerShot 点（既定 1。Mark の少ない Shot は
%   その Shot の全 Mark）以上を必ず計測する（足りないときは Mark の数を増やし、plan.message に書く）。false なら
%   Shot を問わず選ぶ（計測しない Shot もある）。sampling.constraints.markRatio が true（既定）なら、
%   Mark 番号ごとの計測する数を、全計測（候補の全 Mark）での割合 × Mark の数 ± 許容幅にそろえる。
%   sampling.constraints.markEqual が true なら、Mark 番号ごとの計測する数を均等にする（Mark の数 / Mark 番号の数。
%   割り切れないときの1つの差だけ。候補の少ない Mark 番号はその数まで計測し、残りをほかの Mark 番号で均等に分ける。
%   alignest.equalTargets）。markEqual は markRatio より優先する。
%   plan.markIndex に計測する Mark（unit.marks の何番目か）を入れる（Shot 単位の選び方では空）。plan.shotIndex は
%   計測する Mark のある Shot。
%   plan.nMarks は学習に使う Mark の数（その軸が有効な Mark。X・Y のどちらか）。
%   Mark の数は spec.markCount があればその数（計測する Mark の数でスイープするとき）。
%   Mark 単位の I 最適・D 最適では、Wafer 中心に最も近い Mark（計測しない Mark を除く）と、必ず計測する Mark
%   （sampling.requiredMarks）、必ず計測する Shot（指定した shotNo・最外周）の Mark すべてを必ず計測する
%   （alignest.markPlanFixedMarks。plan.requiredShotIndex は必ず計測する Shot）。同心円の区切りがあれば、Wafer 中心からの
%   Mark の半径で区画に分け、区画ごとの数を割合 × Mark の数 ± 許容幅にそろえる（半径の方向のバランス）。計測しない Shot（sampling.excludedShots）・Mark（sampling.excludedMarks）は
%   学習に選ばない（評価には使う。I 最適・D 最適・ランダムの Shot と Mark 単位の Mark。alignest.measurementSelections）。
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
    case {"mark", "markd", "markrandom"}
        plan = markPlan(unit, spec, sampling, waferRadiusMm, candidates, plan);
        return
    case {"marksobol", "markpoisson"}
        plan = markSpreadPlan(unit, spec, sampling, waferRadiusMm, candidates, plan);
        return
    case {"ioptimal", "doptimal", "random", "sobol", "poisson"}
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
        % 計測しない Shot は学習に選ばない（必ず計測する Shot からも外す。評価には使う）
        selection = alignest.measurementSelections(unit, sampling);
        selectable = ~ismember(candidates, selection.excludedShots);
        plan.requiredShotIndex = setdiff(plan.requiredShotIndex, selection.excludedShots);
        if nShots >= nnz(selectable)
            plan.message = strtrim(plan.message + sprintf(" 学習 Shot 数 %d が、計測しない Shot を除いた候補 %d 以上です。", ...
                nShots, nnz(selectable)));
            return
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
            pool = find(selectable);   % 選べる候補（基底は全候補で正規直交化したまま）
            if spec.type == "ioptimal"
                blocks = shotBlocks(unit, candidates, sampling, waferRadiusMm);
                [selected, plan.criterion, plan.violation] = alignest.constrainedIOptimal(blocks(pool), nShots, ...
                    labels(pool, :), sampling.constraints.slack, stream, sampling.exchangeStarts, ...
                    sampling.exchangeMaxIterations, fixed(pool));
            elseif spec.type == "doptimal"
                blocks = shotBlocks(unit, candidates, sampling, waferRadiusMm);
                [selected, plan.criterion, plan.violation] = alignest.exchangeDesign(blocks(pool), nShots, ...
                    labels(pool, :), sampling.constraints.slack, stream, sampling.exchangeStarts, ...
                    sampling.exchangeMaxIterations, criterion="D", fixed=fixed(pool));
            elseif spec.type == "sobol"
                [selected, plan.violation] = alignest.sobolSelect([shots.Xmm(candidates(pool)), ...
                    shots.Ymm(candidates(pool))], nShots, fixed(pool), waferRadiusMm, labels=labels(pool, :), ...
                    slack=sampling.constraints.slack);
            elseif spec.type == "poisson"
                [selected, plan.violation] = alignest.poissonDiskSelect([shots.Xmm(candidates(pool)), ...
                    shots.Ymm(candidates(pool))], nShots, fixed(pool), stream, labels=labels(pool, :), ...
                    slack=sampling.constraints.slack);
            else
                [chosen, plan.violation] = alignest.randomFeasibleShots(numel(pool), nShots, labels(pool, :), ...
                    sampling.constraints.slack, stream, fixed(pool));
                selected = find(chosen);
            end
            plan.shotIndex = candidates(pool(selected(:)));
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
        error('alignest:samplingMethod', '計測点の選び方が正しくありません: %s', spec.type);
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
    sampling, waferRadiusMm);
end

function plan = markPlan(unit, spec, sampling, waferRadiusMm, candidates, plan)
% Mark 単位の I 最適・D 最適：（各 Shot で n 点以上を計測し、）Mark 番号の割合をそろえて、計測する Mark を交換法で選ぶ。
% 制約つきランダム（markrandom）は、同じ制約を満たす組を乱数で選ぶ（交換法の初期配置。交換はしない）。
% Wafer 中心に最も近い Mark・指定した必ず計測する Mark・必ず計測する Shot の Mark は必ず選び、計測しない Shot・Mark は
% 選ばない。同心円の区切りがあれば、Mark の半径の区画ごとの数もそろえる
marks = unit.marks;
[setup, plan] = markPlanSetup(unit, spec, sampling, candidates, plan);
if isempty(setup.markCandidates)
    return
end
markCandidates = setup.markCandidates;
groupOfMark = setup.groupOfMark;
nGroups = max(groupOfMark);
fixed = setup.fixed;
nMarks = setup.nMarks;
criterion = "I";
if spec.type == "markd"
    criterion = "D";
end
requirePerShot = ~isfield(sampling, "markRequirePerShot") || sampling.markRequirePerShot;
minPerShot = 1;
if isfield(sampling, "markMinPerShot") && ~isempty(sampling.markMinPerShot)
    minPerShot = max(1, round(double(sampling.markMinPerShot)));
end
group = zeros(0, 1);
if requirePerShot
    % 各 Shot で n 点（Mark の少ない Shot はその Shot の全 Mark。必ず計測する Mark がそれより多い Shot はその数）。
    % 合わせた数に足りなければ Mark の数を増やす
    perGroup = accumarray(groupOfMark, 1);
    fixedPerGroup = accumarray(groupOfMark(fixed), 1, [nGroups, 1]);
    minimumTotal = sum(max(min(minPerShot, perGroup), fixedPerGroup));
    if nMarks < minimumTotal
        plan.message = strtrim(plan.message + sprintf(" %s では各 Shot %d 点（と必ず計測する Mark）を計測できないため、" + ...
            "%d 点にしました。", setup.sizeText, minPerShot, minimumTotal));
        nMarks = minimumTotal;
    end
    group = groupOfMark;
end
[plan, ok] = checkMarkCount(plan, nMarks, numel(markCandidates), nnz(fixed));
if ~ok
    return
end
labels = zeros(numel(markCandidates), 0);
equal = isfield(sampling.constraints, "markEqual") && sampling.constraints.markEqual;
if equal || ~isfield(sampling.constraints, "markRatio") || sampling.constraints.markRatio
    [levels, ~, labels] = unique(marks.markNo(markCandidates));
end
equalColumns = equal & true(1, size(labels, 2));
if equal
    sizes = accumarray(labels, 1);
    target = alignest.equalTargets(sizes, nMarks);
    short = sizes < nMarks / numel(sizes);
    if any(short)
        plan.message = strtrim(plan.message + sprintf(" 候補の少ない Mark 番号（%s）はその数まで計測し、残りをほかの" + ...
            "Mark 番号で均等にしました（%s）。", strjoin("M" + string(levels(short).'), "・"), ...
            strjoin("M" + string(levels.') + " " + string(round(target.', 1)), "・")));
    end
end
% 同心円・4象限・Scan 方向：区画ごとの数を割合 × Mark の数 ± 許容幅にそろえる
zoneLabels = markZoneLabels(unit, markCandidates, sampling, waferRadiusMm);
labels = [labels, zoneLabels];
equalColumns = [equalColumns, false(1, size(zoneLabels, 2))];
blocks = markBlocks(unit, setup.allCandidates, sampling, waferRadiusMm);
blocks = blocks(setup.pool);
stream = RandStream('mt19937ar', 'Seed', seedFor(sampling.seed, nMarks, spec.repeat));
nStarts = sampling.exchangeStarts;
maxIterations = sampling.exchangeMaxIterations;
if spec.type == "markrandom"
    % 制約を満たす初期配置を1つ作るだけ（交換しない）＝制約つきランダム
    nStarts = 1;
    maxIterations = 0;
end
[selected, plan.criterion, plan.violation] = alignest.exchangeDesign(blocks, nMarks, labels, ...
    sampling.constraints.slack, stream, nStarts, maxIterations, criterion=criterion, ...
    group=group, minPerGroup=minPerShot, equal=equalColumns, fixed=fixed);
if plan.violation > 0
    plan.message = strtrim(plan.message + sprintf(" Mark 番号ごと・同心円・4象限・Scan 方向の区画ごとの数をそろえる" + ...
        "制約を満たす組が見つからず、違反量 %d の組を使いました。", plan.violation));
end
plan = finishMarkPlan(plan, unit, markCandidates, selected, blocks);
end

function plan = markSpreadPlan(unit, spec, sampling, waferRadiusMm, candidates, plan)
% Mark 単位の Sobol 列（marksobol）・ポアソンディスク（markpoisson）：Shot 単位と同じ選び方で、計測する Mark を選ぶ
% （alignest.sobolSelect・poissonDiskSelect）。必ず計測する Mark（Wafer 中心に最も近い Mark・指定した Mark・必ず計測する
% Shot の Mark）を先に入れ、計測しない Shot・Mark は選ばない。同心円・4象限・Scan 方向の区画の数の上限を超える Mark は
% 選ばない。各 Shot の点数・Mark 番号の制約は使わない
marks = unit.marks;
[setup, plan] = markPlanSetup(unit, spec, sampling, candidates, plan);
if isempty(setup.markCandidates)
    return
end
[plan, ok] = checkMarkCount(plan, setup.nMarks, numel(setup.markCandidates), nnz(setup.fixed));
if ~ok
    return
end
positions = [marks.x(setup.markCandidates), marks.y(setup.markCandidates)];
labels = markZoneLabels(unit, setup.markCandidates, sampling, waferRadiusMm);
if spec.type == "marksobol"
    [selected, plan.violation] = alignest.sobolSelect(positions, setup.nMarks, setup.fixed, waferRadiusMm, ...
        labels=labels, slack=sampling.constraints.slack);
else
    stream = RandStream('mt19937ar', 'Seed', seedFor(sampling.seed, setup.nMarks, spec.repeat));
    [selected, plan.violation] = alignest.poissonDiskSelect(positions, setup.nMarks, setup.fixed, stream, ...
        labels=labels, slack=sampling.constraints.slack);
end
if plan.violation > 0
    plan.message = strtrim(plan.message + sprintf(" 同心円・4象限・Scan 方向の区画ごとの数をそろえる制約を満たせず、" + ...
        "違反量 %d の組を使いました。", plan.violation));
end
blocks = markBlocks(unit, setup.allCandidates, sampling, waferRadiusMm);
plan = finishMarkPlan(plan, unit, setup.markCandidates, selected, blocks(setup.pool));
end

function labels = markZoneLabels(unit, markCandidates, sampling, waferRadiusMm)
% Mark 単位の制約の区分番号（候補 Mark × 制約の種類。1始まり）：同心円（Mark の半径）・4象限（Mark の偏角。軸上は
% 反時計回りに次の象限。Shot 単位と同じ）・Scan 方向（その Mark の Shot の Scan 方向）
marks = unit.marks;
constraints = sampling.constraints;
x = marks.x(markCandidates);
y = marks.y(markCandidates);
labels = zeros(numel(markCandidates), 0);
edges = alignest.zoneEdgesMm(sampling, waferRadiusMm);
if ~isempty(edges)
    labels(:, end + 1) = 1 + sum(hypot(x, y) >= edges, 2);
end
if isfield(constraints, "quadrants") && constraints.quadrants
    angle = mod(atan2(y, x), 2 * pi);
    labels(:, end + 1) = mod(floor(angle / (pi / 2)), 4) + 1;
end
if isfield(constraints, "scanDirection") && constraints.scanDirection && unit.hasDirection
    labels(:, end + 1) = unit.shots.direction(marks.shotIndex(markCandidates));
end
for p = 1:size(labels, 2)
    [~, ~, labels(:, p)] = unique(labels(:, p));
end
end

function [setup, plan] = markPlanSetup(unit, spec, sampling, candidates, plan)
% Mark 単位の計画の準備：選べる Mark（計測しない Shot・Mark を除く）・Mark の数・必ず計測する Mark。
% setup.allCandidates：基底を正規直交化する Mark（unit.marks の何番目か）、pool：選べる Mark（allCandidates の何番目か）、
% markCandidates：選べる Mark（unit.marks の何番目か。空なら選べない）、groupOfMark：選べる Mark の Shot の番号（1始まり）、
% nMarks・sizeText：計測する Mark の数とその決め方の説明、fixed：選べる Mark のうち必ず計測する Mark（論理値）
marks = unit.marks;
setup.allCandidates = find(ismember(marks.shotIndex, candidates) & (marks.validX | marks.validY));
selection = alignest.measurementSelections(unit, sampling);
setup.pool = find(~ismember(setup.allCandidates, selection.excludedMarks));
setup.markCandidates = setup.allCandidates(setup.pool);
if isempty(setup.markCandidates)
    plan.message = "計測しない Shot・Mark を除くと、選べる Mark がありません。";
    return
end
[~, ~, setup.groupOfMark] = unique(marks.shotIndex(setup.markCandidates));
nGroups = max(setup.groupOfMark);
if isfinite(plan.rate)
    setup.nMarks = max(1, round(plan.rate / 100 * numel(setup.allCandidates)));
    setup.sizeText = sprintf("計測率 %g%% の Mark の数 %d", plan.rate, setup.nMarks);
elseif isfield(spec, "markCount") && isfinite(spec.markCount)
    setup.nMarks = max(1, round(spec.markCount));
    setup.sizeText = sprintf("計測する Mark の数 %d", setup.nMarks);
else
    setup.nMarks = max(1, round(spec.markPerShot * nGroups));
    setup.sizeText = sprintf("1 Shot あたり %g 点の Mark の数 %d", spec.markPerShot, setup.nMarks);
end
% 必ず計測する Mark：Wafer 中心に最も近い Mark・指定した Mark・必ず計測する Shot の Mark すべて
[fixedMarks, fixedInfo] = alignest.markPlanFixedMarks(unit, sampling);
setup.fixed = ismember(setup.markCandidates, fixedMarks);
plan.requiredShotIndex = fixedInfo.requiredShots;
if ~isempty(fixedInfo.missingShotNos)
    plan.message = "必ず計測する Shot のうち、この Wafer に無い、または計測値の無い shotNo：" + ...
        strjoin(string(fixedInfo.missingShotNos.'), " ") + "。";
end
end

function [plan, ok] = checkMarkCount(plan, nMarks, nCandidates, nFixed)
% 計測する Mark の数が、候補の Mark の数・必ず計測する Mark の数に対して選べる数か（選べなければ理由を plan.message に）
ok = false;
if nMarks >= nCandidates
    plan.message = strtrim(plan.message + sprintf(" 計測する Mark の数 %d が候補の Mark の数 %d 以上なので、評価する" + ...
        " Mark が残りません。", nMarks, nCandidates));
    return
end
if nFixed >= nMarks
    plan.message = strtrim(plan.message + sprintf(" 必ず計測する Mark（Wafer 中心に最も近い Mark・指定した Mark・" + ...
        "必ず計測する Shot の Mark）が %d 個あり、計測する Mark の数 %d 以上です。", nFixed, nMarks));
    return
end
ok = true;
end

function plan = finishMarkPlan(plan, unit, markCandidates, selected, blocks)
% 選んだ Mark（markCandidates の何番目か）を plan に入れ、I 基準・D 基準と効率を求める（blocks：markCandidates の基底の行）
plan.markIndex = sort(markCandidates(selected(:)));
plan.shotIndex = unique(unit.marks.shotIndex(plan.markIndex));   % 計測する Mark のある Shot（各 Shot で必ず計測するなら全候補）
plan.nShots = numel(plan.shotIndex);
plan.shotNos = unit.shots.shotNo(plan.shotIndex);
plan.nMarks = numel(plan.markIndex);
plan.ok = true;
[plan.criterionI, plan.criterionD, plan.efficiencyI, plan.efficiencyD] = alignest.designCriteria(blocks(selected));
end

function blocks = markBlocks(unit, markCandidates, sampling, waferRadiusMm)
% 候補 Mark ごとの基底の行（全候補 Mark で正規直交化した基準モデル。Shot 単位の shotBlocks と同じ正規化）
marks = unit.marks;
design = baseDesign(marks.x(markCandidates), marks.y(markCandidates), sampling, waferRadiusMm);
[q, ~] = qr(design, 0);
blocks = num2cell(q, 2);
end

function [iValue, dValue, iEfficiency, dEfficiency] = planCriteria(unit, candidates, shotIndex, sampling, waferRadiusMm)
% 選んだ組の I 基準・D 基準と全計測に対する効率。候補の Mark が基準モデルの項数より少ないときは NaN
iValue = NaN;
dValue = NaN;
iEfficiency = NaN;
dEfficiency = NaN;
try
    blocks = shotBlocks(unit, candidates, sampling, waferRadiusMm);
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
    elseif isfield(spec, "markCount") && isfinite(spec.markCount)
        nMarks = max(1, round(spec.markCount));
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
    blocks = markBlocks(unit, markCandidates, sampling, waferRadiusMm);
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

function blocks = shotBlocks(unit, candidates, sampling, waferRadiusMm)
% 候補 Shot ごとの基底（全候補 Mark で正規直交化した基準モデル）
marks = unit.marks;
useMark = ismember(marks.shotIndex, candidates) & (marks.validX | marks.validY);
design = baseDesign(marks.x(useMark), marks.y(useMark), sampling, waferRadiusMm);
[q, ~] = qr(design, 0);
shotOfRow = marks.shotIndex(useMark);
blocks = cell(numel(candidates), 1);
for k = 1:numel(candidates)
    blocks{k} = q(shotOfRow == candidates(k), :);
end
end

function design = baseDesign(x, y, sampling, waferRadiusMm)
% I 最適の基準モデルの設計行列（説明変数 X・Y・半径、または X・Y の designOrder 次の多項式。座標は Wafer 半径で割る）。
% 以前の設定（designFeatures が無い）は既定の X・Y・半径
features = "XYR";
if isfield(sampling, "designFeatures") && ~isempty(sampling.designFeatures)
    features = string(sampling.designFeatures);
end
design = alignest.basis.designPolynomial(x / waferRadiusMm, y / waferRadiusMm, sampling.designOrder, features);
if size(design, 1) < size(design, 2)
    error('alignest:designOrder', 'I 最適の基準モデル（%d 次、%d 項）より候補の Mark（%d 点）が少ないです。次数を下げてください。', ...
        sampling.designOrder, size(design, 2), size(design, 1));
end
end
