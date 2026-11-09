function result = shotHighOrder(wafers, settings, flags)
%SHOTHIGHORDER Shot 高次補正（Shot 内の座標の補正の式）の係数（k パラメータ）を Wafer ごとに求め、補正の効果を評価する。
%   result = alignest.shotHighOrder(wafers, settings)
%   check = alignest.shotHighOrder(wafers, settings, checkOnly=true)   % 計算の前の確かめ（点が足りない k の組）だけ
%   result = alignest.shotHighOrder(wafers, settings, stages=false)   % 補正の段階の残差を求めない（スイープを速くする）
%   wafers：Wafer ごとの構造体の配列。label（Wafer の名前）・points（点の表。alignest.highOrderUnitPoints・
%   alignest.highOrderTargetPoints の形：source・name・shotNo・Xc・Yc（Shot 中心 [mm]）・localX・localY（Shot 内の座標 [mm]）・
%   x・y（Wafer 上の座標 [mm]）・valueX・valueY（dx・dy の値 [nm]。値の無い点は NaN）・direction（Scan 方向 1・2。分からない
%   点は NaN）・rowParity（Shot 行の奇偶。1 = 奇数行・2 = 偶数行。上の行から数える））。direction・rowParity の列が無ければ、
%   direction は分からない、rowParity は Shot 中心の Y 座標（Yc）の行を上から数えて付ける。
%   settings：設定（settings.highOrder を alignest.highOrderOptions で確かめて使う）。
%   補正の式：補正の式（ASML・Canon・Nikon・カスタム）のうち使う項（k パラメータ。terms.used）。dx の式は X の値、dy の式は Y の値に
%   当てはめる。x・y は Shot 内の座標 [mm]。k の組のくくり（options.unit）：
%   - Wafer 内の Shot で共通（"common"）：Wafer ごとに1組の k を、その Wafer のすべての点で求める
%   - Scan 方向ごと（"scan"）・Shot 行の偶奇ごと（"row"）：Wafer ごとに、Scan 方向（1・2）・Shot 行の奇偶（奇数行・偶数行）
%     ごとに1組ずつの k を、その Wafer のすべての点で一緒に求める（組の点だけで決まる。L2 の強さは組ごとに別に求めたときと
%     同じ）
%   - Shot ごと（"shot"）：Shot ごとに1組の k を、その Shot の点だけで求める
%   内周・外周：Shot 中心の半径が options.outerRadiusMm 以上の Shot を外周とする（点の zone）。外周の式（options.outerMaker）を
%   分けるときは、k の組を内周・外周で別にし（くくりの組ごとに、内周は options.maker、外周は outerMaker の式）、Wafer 成分は
%   両方で共通にする。補正の評価は、分けなくても内周・外周ごとにも出す（result.regionSummary）。
%   Wafer 成分（Shot 中心の座標 Xc・Yc の 1〜waferOrder 次の項。定数は k1・k2 に含める）：Shot ごとのほかは、Wafer で共通の
%   1組として k と一緒に求める（正則化はかけない）。Shot ごとのときは、Shot ごとの k1・k2 が Wafer 成分を含むので、先に Wafer 内で
%   共通の k と一緒に求めて引き、残りを Shot ごとに求める（補正量・残差は Wafer 成分なしと同じで、Shot ごとの k1・k2 が
%   Wafer 成分を除いた値になる）。
%   Shot 共通を先に引く（Shot ごとのとき。options.shotCommon が "fit"・"input"）：Shot 共通の k（"fit" は Wafer 成分と一緒に
%   Wafer 内の Shot で共通に求めた k、"input" は入力した k の値 options.shotCommonValues・shotCommonOuterValues。外周の式を
%   分けるときは内周・外周の2組）を先に引き、残りを Shot ごとに求める（Shot ごとの項は次数 options.shotEachOrder まで。
%   0 なら使う項すべて）。"input" で Wafer 成分があれば、入力した k を引いた残りで（定数と一緒に）求めて引く。結果の
%   Shot ごとの k は Shot 共通の k を足した値（その Shot に当てる k。Shot ごとに求めない項は Shot 共通の値）。Shot ごとに
%   使う項をすべて求めて正則化もかけなければ、補正量・残差は引かないときと同じ（損失関数は残差だけで決まるため）。
%   点が足りない Shot の扱いは Shot ごとに求める項に当て、Shot 共通の項は減らさない。
%   回帰は alignest.robustRidgeFit（最小二乗・Huber・LAD、正則化（L2・L1）は選んだ次数の項だけ）。比べるために、同じ点・同じ損失関数で、
%   Shot ごとに 1次の項（k1〜k6）で補正した残差も求める（くくりによらず、Shot ごとに別の k1〜k6）。
%   点が足りない k の組（点の配置で使う項が決まらない Shot・組）の扱い（options.shortage）：
%   - "reduceAll"（全体の項を減らす）：点の数が最も少ない k の組（Shot ごとなら Mark の最も少ない Shot。k1〜k6 を決められる組の
%     中で。外周の式を分けるときは内周・外周ごと）の点の配置で決められる項だけを、k の番号の小さい順に選び、すべての組で使う
%     （使う項がそれより多ければ外し、result.reduction とメッセージで知らせる。k1〜k6 は外さない）
%   - "reduceGroup"（その組だけ項を減らす）：k の組ごとに、その組の点の配置で決められる項だけを k の番号の小さい順に使う
%     （k1〜k6 は外さない。外した項は result.groupReductions とメッセージ）。ほかの組は選んだ項をすべて使う
%   - "skip"（その組は補正しない）：項は減らさない
%   どの扱いでも、項がすべて決まらない k の組（k1〜k6 も決まらないなど）は補正しない（補正量・残差は NaN）。
%   Wafer 成分の決まらない項は 0 にする。
%   Wafer RT（options.waferRtRange。"all" はすべての Shot、"outer" は外周の Shot）：RT モデル（次数 options.waferRtOrder。
%   alignest.basis.rtDesign）を、Shot 中心の座標（Wafer 半径 settings.data.waferRadiusMm で割る）で、Wafer ごとに X・Y を一緒に
%   当てはめて先に引き、残りを上の補正の式で求める（正則化はかけない。X・Y の損失関数が同じならその損失関数、違えば最小二乗）。
%   Wafer 成分（多項式）は RT で補正しない Shot だけに使う（"all" なら使わない）。RT の決まらない項は 0 にする。
%   補正の段階を比べるために、同じ点・同じ損失関数で、Wafer 高次補正だけ（Shot 中心の座標 Xc・Yc の 0〜waferOrder 次の多項式。
%   定数を含む）と、Wafer 高次補正＋Shot 共通補正（Wafer 成分と、Wafer 内の Shot で共通の1組の k（外周の式を分けるときは
%   内周・外周の2組）を一緒に。くくりが Wafer 内で共通なら高次補正そのもの）の残差も求める。
%   result.terms：項の表（alignest.highOrderVif。点の Shot 内の座標で求めた VIF を含む）。zone：式の範囲（外周の式を分けない
%   ときは ""、分けるときは "内周"・"外周"。VIF はその範囲の点で求める）
%   result.coefficients：補正値（係数）の表（wafer・shotNo（Shot ごとのとき）・group（k の組の名前。Wafer 成分は
%   "Wafer で共通"）・zone（外周の式を分けるときの式の範囲）・axis・component・k・term・value・unit・note・xPower・yPower
%   （項のべき））。係数は mm の座標での値（単位 nm/mm^次数。1次は nm/mm = ppm）。Wafer RT は component = "Wafer RT"・
%   axis = "dx・dy"（X・Y で共通の係数）で、Wafer 半径で割った座標での値（単位 nm。k・xPower・yPower は NaN）
%   result.summary：Wafer・軸ごとの評価と、全 Wafer をまとめた行（wafer = "すべての Wafer"。region = "すべて"）。点の数、
%   補正前・Shot ごとの1次（k1〜k6）で補正した残差・高次補正の残差の |平均| + 3σ [nm]（before・linear・highOrder）、Shot
%   ごとの1次と比べた改善（improvement）、高次補正の |残差| の 95% 点・中央値（highOrderP95・highOrderMedian）、高次補正の
%   残差の RMS、外れ値とみなした点の数（outliers：ロバスト回帰が、残差が大きいため当てはめでの重みを半分未満に下げた点。
%   alignest.highOrderOutliers。最小二乗では 0）、求めた k の組の数（kSets）と補正しなかった k の組の数（skipped）、回帰の
%   決定係数（rSquared）と自由度調整済決定係数（adjustedRSquared。alignest.highOrderRSquared）
%   result.regionSummary：result.summary と同じ列で、内周・外周（region = "内周"・"外周"）の Shot だけの行。k の組が内周と
%   外周にまたがるとき（外周の式を分けない Wafer 内で共通など）は kSets・skipped が NaN
%   result.points：点ごとの値・k の組（group）・Shot 中心の半径（shotRadius）・内周か外周か（zone）・Wafer RT の補正量
%   （waferRtX・Y。RT で補正しない Shot は 0）・RT で補正する Shot か（waferRtUsed）・補正量・残差・Shot
%   ごとの1次で補正した残差・Wafer 高次補正だけの残差（waferResidualX・Y）・Wafer 高次補正＋Shot 共通補正の残差
%   （commonResidualX・Y）・1点抜きの予測の誤差（looResidualX・Y。高次補正の当てはめで、その点を除いて当てはめたときの、
%   その点の誤差。alignest.robustRidgeFit の looResidual。Shot ごとで Wafer 成分を先に引くときは、Wafer 成分は除かずに
%   求める。その点だけで決まる項があれば NaN）・ロバスト回帰の重み・ハット行列の対角（leverageX・Y。足すと回帰の自由度。
%   Shot ごとで Wafer 成分を先に引くときは、Wafer 成分の項の数を点で等分して足す。Wafer RT の分も足す）（wafer の列を足して
%   縦に並べる）
%   result.commonCoefficients：Wafer 高次補正＋Shot 共通補正の Shot 共通の k（coefficients と同じ列。component は "Shot 共通"、
%   group は "共通" または "内周"・"外周"）。くくりが Wafer 内で共通のときは空（coefficients の k が Shot 共通の k）。
%   Shot 共通を先に引くときは、引いた k（入力した値なら、メモが「入力した値」）
%   result.reduction：式の範囲・軸（dx・dy）ごとの項数の絞り込み（axis・zone（"" または "内周"・"外周"）・zoneIndex・
%   reference（基準の k の組）・nPoints（その点の数）・dropped（外した k の番号））。"reduceAll" のときだけ
%   result.groupReductions：「その組だけ項を減らす」で項を減らした k の組の表（wafer・axis・group・shotNo・zone・dropped
%   （外した k の番号の文字。例 "k7・k8"））
%   result.shortage：計算の前の確かめ（点が足りない k の組）。式の範囲・軸ごとの axis・zone・zoneIndex・reference（k1〜k6 を
%   決められて点の数が最も少ない k の組）・nPoints（その点の数）・nUsed（使う項の数）・dropped（その組の点の配置で決められない
%   k の番号）・nGroups（k の組の数）・nShort（使う項がすべては決まらない組の数）・nUnfit（k1〜k6 も決まらない組の数）
%   result.messages：画面に出す説明、result.options・description：使った設定（絞った項は options.excludedTerms・
%   outerExcludedTerms に足す）
%   checkOnly=true なら、当てはめずに確かめだけを返す（check.options・check.shortage・check.messages（点が足りない組の
%   知らせ。足りなければ空）。画面で「補正を計算する」の前に知らせるため）。stages=false なら、補正の段階の残差（Wafer 高次
%   補正だけ・＋Shot 共通補正）を求めず NaN にする（Shot ごとで Wafer 成分を先に引くときの Wafer 成分は求める）。
arguments
    wafers struct
    settings struct
    flags.checkOnly (1, 1) logical = false
    flags.stages (1, 1) logical = true
end
checkOnly = flags.checkOnly;
ALL_LABEL = "すべての Wafer";
ALL_REGION = "すべて";
ZONE_NAMES = ["内周", "外周"];
AXIS_NAMES = ["X", "Y"];
FORMULA_AXES = ["dx", "dy"];
options = alignest.highOrderOptions(settings);
if isempty(wafers)
    error('alignest:highOrderInput', 'Shot 高次補正を求める点がありません。入力のデータと Wafer を選んでください。');
end
zoneSplit = options.outerMaker ~= "none";
sequential = options.unit == "shot" && options.shotCommon ~= "none";   % Shot 共通を先に引き、残りを Shot ごとに求める
inputCommon = sequential && options.shotCommon == "input";
inputValues = {options.shotCommonValues, options.shotCommonOuterValues};   % 入力した Shot 共通の k（内周の式・外周の式）
for w = 1:numel(wafers)
    wafers(w).points = withGroupColumns(wafers(w).points, options.outerRadiusMm);
end
% 軸ごとの回帰の条件：損失関数・正則化の種類（回帰の設定に渡す）と、強さ λ（なしなら 0）・かける項の次数
axisFits = alignest.axisFitOptions(options);
noPenalty = struct("lambda", 0, "orders", zeros(1, 0));
zoneTerms = {alignest.highOrderTerms(options.maker, options.excludedTerms)};
if zoneSplit
    zoneTerms{2} = alignest.highOrderTerms(options.outerMaker, options.outerExcludedTerms);
end
everything = vertcat(wafers.points);
eachTerms = zoneTerms;   % k の組（Shot ごとなら Shot）ごとに求める項
if sequential
    eachTerms = eachShotTerms(zoneTerms, options.shotEachOrder);   % Shot 共通は使う項すべて、Shot ごとは次数の上限まで
end
shortage = checkShortage(eachTerms, wafers, options.unit, FORMULA_AXES, zoneSplit);
if checkOnly
    result = struct("options", options, "shortage", shortage, "messages", ...
        shortageMessages(shortage, options, zoneSplit));
    return
end
reduction = struct("axis", {}, "zone", {}, "zoneIndex", {}, "reference", {}, "nPoints", {}, "dropped", {});
if options.shortage == "reduceAll"
    [eachTerms, reduction] = reduceTerms(eachTerms, shortage);
end
if ~sequential
    zoneTerms = eachTerms;   % Shot 共通を先に引くときだけ、Shot 共通の項は減らさない
end
reduceGroups = options.shortage == "reduceGroup";
dropped = droppedTerms(reduction, 1);
outerDropped = droppedTerms(reduction, 2);
if ~sequential && (~isempty(dropped) || ~isempty(outerDropped))
    % 使った設定・説明（項の数）は、絞った後の項にする
    options.excludedTerms = unique([options.excludedTerms, dropped]);
    options.outerExcludedTerms = unique([options.outerExcludedTerms, outerDropped]);
    options.description = alignest.highOrderOptions(struct("highOrder", options)).description;
end
if options.unit == "scan" && ~any(ismember(everything.direction, [1, 2]) & isfinite(everything.shotNo))
    error('alignest:highOrderDirection', ['Scan 方向（Direction）が分からないので、Scan 方向ごとには求められません。' ...
        '「1. データの読み込み」で Direction の列を対応づけるか「Scan 方向の付与」の規則を選ぶ（Excel・CSV のときは' ...
        '「Excel・CSV の列」で Direction の列か規則を選ぶ）と使えます。']);
end
vifInfos = cell(1, numel(zoneTerms));
for z = 1:numel(zoneTerms)
    inZone = ~zoneSplit | everything.zone == z;   % 外周の式を分けるときは、その範囲の点で VIF を求める
    [zoneTerms{z}, vifInfos{z}] = alignest.highOrderVif(zoneTerms{z}, [everything.localX(inZone), ...
        everything.localY(inZone)], [isfinite(everything.valueX(inZone)), isfinite(everything.valueY(inZone))] & ...
        isfinite(everything.shotNo(inZone)), options.vifThreshold);
    zoneTerms{z}.zone = repmat(ternaryText(zoneSplit, ZONE_NAMES(z), ""), height(zoneTerms{z}), 1);
end
polynomialOrder = options.waferOrder * (options.waferRtRange ~= "all");   % すべての Shot が RT なら Wafer 成分は使わない
waferPowers = polynomialPowers(polynomialOrder);
waferFirst = options.unit == "shot" && polynomialOrder > 0;   % Shot ごと：Wafer 成分を先に求めて引く
fitWaferPowers = waferPowers;
if options.unit == "shot"
    fitWaferPowers = zeros(0, 2);   % Shot ごとの k と一緒には求めない（k1・k2 が Wafer 成分を含む）
end

waferRadiusMm = alignest.defaultSettings().data.waferRadiusMm;
if isfield(settings, "data") && isfield(settings.data, "waferRadiusMm")
    waferRadiusMm = settings.data.waferRadiusMm;
end

pointParts = cell(numel(wafers), 1);
rtParts = cell(numel(wafers), 1);
coefficientParts = cell(numel(wafers), 2);
commonParts = cell(numel(wafers), 2);
groupReductionParts = cell(numel(wafers), 2);
summaryParts = cell(numel(wafers) + 1, 2);
regionParts = cell(numel(wafers) + 1, 2, 2);
counts = struct("skipped", [0, 0], "groups", [0, 0], "notConverged", 0, "noRobust", 0, "waferDropped", 0, ...
    "undetermined", strings(1, 0), "constant", strings(1, 0), "reducedGroups", [0, 0], "reducedTerms", strings(1, 0), ...
    "rtDropped", 0, "rtNotConverged", 0, "commonMissing", 0);
% 求めた・補正しなかった k の組の数（軸 × 範囲。1列目は内周と外周にまたがる組、2・3列目は内周・外周の組）
[totalFitted, totalSkipped] = deal(zeros(2, 3));
for w = 1:numel(wafers)
    points = wafers(w).points;
    label = string(wafers(w).label);
    nPoints = height(points);
    values = [points.valueX, points.valueY];
    [groupKey, groupName] = groupOfPoints(points, options.unit, zoneSplit);
    rt = fitWaferRt(points, values, isfinite(groupKey), options, waferRadiusMm);
    rtParts{w} = waferRtRows(label, rt, options);
    counts.rtDropped = counts.rtDropped + (rt.nDropped > 0);
    counts.rtNotConverged = counts.rtNotConverged + ~rt.converged;
    fitValues = values - rt.part;   % RT の分を引いた残りを補正の式で求める（RT なしなら values のまま）
    % 表より速く切り出せる数の配列で回帰に渡す。5列目：Wafer 成分を使う点は 1、RT で補正する Shot の点は 0
    coordinates = [points.localX, points.localY, points.Xc, points.Yc, double(~rt.inScope)];
    [correction, linearCorrection, weights, waferOnlyCorrection, commonCorrection, looResidual, leverage] = deal(nan(nPoints, 2));
    [fitted, skipped] = deal(zeros(2, 3));
    for a = 1:2
        fitOptions = axisFits(a).options;
        penalty = struct("lambda", axisFits(a).lambda, "orders", axisFits(a).orders);
        rows = find(isfinite(values(:, a)) & isfinite(points.shotNo) & isfinite(groupKey));
        axisTerms = cellfun(@(terms) terms(terms.axis == FORMULA_AXES(a) & terms.used, :), zoneTerms, ...
            'UniformOutput', false);   % 式の範囲（内周・外周）ごとの使う項
        eachAxisTerms = axisTerms;   % k の組ごとに求める項
        if sequential
            eachAxisTerms = cellfun(@(terms) terms(terms.axis == FORMULA_AXES(a) & terms.used, :), eachTerms, ...
                'UniformOutput', false);
        end
        linearTerms = zoneTerms{1}(zoneTerms{1}.axis == FORMULA_AXES(a) & zoneTerms{1}.order <= 1, :);
        parts = cell(1, 0);
        waferPart = zeros(nPoints, 1);
        waferRemoved = false;
        if flags.stages
            waferOnlyCorrection(:, a) = fitWaferOnly(coordinates, values(:, a), isfinite(points.shotNo) & ~rt.inScope, ...
                [0, 0; waferPowers], fitOptions);
            waferOnlyCorrection(rt.inScope, a) = rt.part(rt.inScope, a);
        end
        commonPart = zeros(nPoints, 1);   % 先に引く Shot 共通の k の分（Shot 共通を先に引くときだけ）
        nCommonTerms = 0;   % 求めて先に引いた Shot 共通の k の数（回帰の自由度に入れる）
        if options.unit ~= "common" && (flags.stages || waferFirst || sequential)
            % Wafer 高次補正＋Shot 共通補正（くくりが Wafer 内で共通なら、高次補正そのものなので下で写す）
            if inputCommon
                [commonFitted, commonWaferPart, commonPart, common] = applyInputCommon(points, coordinates, ...
                    fitValues(:, a), isfinite(groupKey), axisTerms, inputValues, waferPowers, zoneSplit, fitOptions);
                commonParts{w, a} = inputCommonRows(label, FORMULA_AXES(a), axisTerms, inputValues, zoneSplit);
            else
                [commonFitted, commonWaferPart, common] = fitCommon(points, coordinates, fitValues(:, a), axisTerms, ...
                    waferPowers, zoneSplit, penalty, fitOptions, reduceGroups);
                if ~isempty(common) && any(common.fit.ok)
                    commonParts{w, a} = coefficientRows(label, common.unit, FORMULA_AXES(a), common.terms, zeros(0, 2), ...
                        common.fit, zoneSplit, "Shot 共通");
                    if sequential
                        commonPart = commonFitted - commonWaferPart;   % 求めた Shot 共通の k の分（求められない範囲は 0）
                        commonPart(~isfinite(commonPart)) = 0;
                        nCommonTerms = sum(cellfun(@numel, common.fit.coefficients(common.fit.ok)));
                    end
                elseif sequential
                    counts.commonMissing = counts.commonMissing + 1;   % Shot 共通は引かずに Shot ごとの k だけ
                end
            end
            commonCorrection(:, a) = commonFitted + rt.part(:, a);
            if waferFirst
                % Shot ごと：この Wafer 成分を先に引き、残りを Shot ごとに求める
                if isempty(common) || ~any(common.fit.ok)
                    counts.waferDropped = counts.waferDropped + 1;   % 求められなかった Wafer 成分は 0（Shot ごとの k だけ）
                else
                    waferPart = commonWaferPart;
                    waferRemoved = true;
                    parts{end + 1} = waferRows(label, FORMULA_AXES(a), waferPowers, common.fit); %#ok<AGROW>
                    counts.waferDropped = counts.waferDropped + any(~common.fit.waferDetermined);
                    counts.notConverged = counts.notConverged + ~common.fit.converged;
                end
            end
        end
        commonTable = [];   % Shot ごとの k に足す Shot 共通の k（Shot 共通を先に引くとき）
        if sequential && ~isempty(commonParts{w, a})
            commonTable = coefficientTable(commonParts{w, a});
        end
        fitUnits = partitionRows(rows, points, groupKey, groupName, options.unit, zoneSplit);
        reductionParts = cell(1, numel(fitUnits));
        for u = 1:numel(fitUnits)
            members = fitUnits(u).members;
            groupIndex = fitUnits(u).groupIndex;
            groupTerms = eachAxisTerms(fitUnits(u).zones);
            counts.groups(a) = counts.groups(a) + numel(fitUnits(u).labels);
            if reduceGroups
                [groupTerms, groupDropped] = reduceGroupTerms(coordinates(members, 1:2), groupIndex, groupTerms);
                reductionParts{u} = groupReductionRows(label, FORMULA_AXES(a), fitUnits(u), groupDropped, zoneSplit);
                counts.reducedGroups(a) = counts.reducedGroups(a) + height(reductionParts{u});
                counts.reducedTerms = unique([counts.reducedTerms, "k" + string([groupDropped{:}])], 'stable');
            end
            removed = waferPart(members) + commonPart(members);   % 先に引いた Wafer 成分・Shot 共通の k の分
            fit = fitGroups(coordinates(members, :), fitValues(members, a) - removed, groupIndex, groupTerms, ...
                fitWaferPowers, penalty, fitOptions);
            done = fit.ok(groupIndex);
            correction(members(done), a) = fit.fitted(done) + removed(done) + rt.part(members(done), a);
            weights(members(done), a) = fit.weights(done);
            looResidual(members(done), a) = fit.looResidual(done);
            leverage(members(done), a) = fit.leverage(done);
            column = 1 + groupZones(points.zone(members), groupIndex, numel(fit.ok));
            fitted(a, :) = fitted(a, :) + accumarray(column(:), double(fit.ok(:)), [3, 1]).';
            skipped(a, :) = skipped(a, :) + accumarray(column(:), double(~fit.ok(:)), [3, 1]).';
            counts.skipped(a) = counts.skipped(a) + nnz(~fit.ok);
            for g = find(~fit.ok)
                names = termNames(groupTerms{g});
                counts.undetermined = unique([counts.undetermined, names(~fit.determined{g})], 'stable');
            end
            if any(fit.ok)
                unitRows = coefficientRows(label, fitUnits(u), FORMULA_AXES(a), groupTerms, fitWaferPowers, fit, zoneSplit);
                if sequential
                    unitRows = withCommonValues(unitRows, commonTable, ...
                        ternaryText(zoneSplit, ZONE_NAMES(fitUnits(u).zones(1)), ""));
                end
                parts{end + 1} = unitRows; %#ok<AGROW>
                counts.notConverged = counts.notConverged + ~fit.converged;
                counts.noRobust = counts.noRobust + (options.loss(a) ~= "ols" && ~fit.robust);
                counts.waferDropped = counts.waferDropped + any(~fit.waferDetermined);
                for g = find(fit.ok)
                    names = termNames(groupTerms{g});
                    counts.constant = unique([counts.constant, names(fit.constant{g})], 'stable');
                end
            end
        end
        if waferRemoved
            % 先に引いた Wafer 成分の項の数も回帰の自由度に入れる（点で等分する）
            corrected = isfinite(leverage(:, a));
            leverage(corrected, a) = leverage(corrected, a) + size(waferPowers, 1) / nnz(corrected);
        end
        if nCommonTerms > 0
            % 求めて先に引いた Shot 共通の k の数も回帰の自由度に入れる（Wafer 成分と同じく点で等分する）
            corrected = isfinite(leverage(:, a));
            leverage(corrected, a) = leverage(corrected, a) + nCommonTerms / max(nnz(corrected), 1);
        end
        leverage(:, a) = leverage(:, a) + rt.leverage(:, a);   % 先に引いた RT の項も回帰の自由度に入れる
        coefficientParts{w, a} = [parts{:}];
        groupReductionParts{w, a} = vertcat(reductionParts{:});
        if options.unit == "common" && flags.stages
            commonCorrection(:, a) = correction(:, a);
        end
        % 比べる補正：Shot ごとに 1次（k1〜k6）だけ（くくりによらない。Wafer 成分は Shot ごとの k1・k2 に含まれる）
        shotRows = find(isfinite(values(:, a)) & isfinite(points.shotNo));
        [~, ~, shotIndex] = unique(points.shotNo(shotRows));
        for s = 1:max([shotIndex; 0])
            members = shotRows(shotIndex == s);
            linearFit = fitGroups(coordinates(members, :), values(members, a), ones(numel(members), 1), {linearTerms}, ...
                zeros(0, 2), noPenalty, fitOptions);
            if linearFit.ok
                linearCorrection(members, a) = linearFit.fitted;
            end
        end
    end
    totalFitted = totalFitted + fitted;
    totalSkipped = totalSkipped + skipped;
    residual = values - correction;
    linearResidual = values - linearCorrection;
    waferResidual = values - waferOnlyCorrection;
    commonResidual = values - commonCorrection;
    groupText = strings(nPoints, 1);
    known = isfinite(groupKey) & isfinite(points.shotNo);
    groupText(known) = groupName(groupKey(known), points.shotNo(known));
    zoneText = strings(nPoints, 1);
    zoneText(isfinite(points.zone)) = ZONE_NAMES(points.zone(isfinite(points.zone)));
    pointParts{w} = [table(repmat(label, nPoints, 1), 'VariableNames', "wafer"), ...
        points(:, ["source", "name", "shotNo", "x", "y", "localX", "localY", "direction", "rowParity", "valueX", ...
        "valueY"]), table(groupText, points.shotRadius, zoneText, rt.part(:, 1), rt.part(:, 2), rt.inScope, ...
        correction(:, 1), correction(:, 2), residual(:, 1), ...
        residual(:, 2), linearResidual(:, 1), linearResidual(:, 2), waferResidual(:, 1), waferResidual(:, 2), ...
        commonResidual(:, 1), commonResidual(:, 2), looResidual(:, 1), looResidual(:, 2), weights(:, 1), ...
        weights(:, 2), leverage(:, 1), leverage(:, 2), 'VariableNames', ["group", "shotRadius", "zone", "waferRtX", ...
        "waferRtY", "waferRtUsed", "correctionX", "correctionY", "residualX", "residualY", "linearResidualX", "linearResidualY", "waferResidualX", ...
        "waferResidualY", "commonResidualX", "commonResidualY", "looResidualX", "looResidualY", "weightX", "weightY", ...
        "leverageX", "leverageY"])];
    for a = 1:2
        summaryParts{w, a} = summaryRow(label, AXIS_NAMES(a), ALL_REGION, points.shotNo, pointParts{w}, ...
            sum(fitted(a, :)), sum(skipped(a, :)));
        for z = 1:2
            inZone = points.zone == z;
            [kSets, notCorrected] = zoneGroupCounts(fitted(a, :), skipped(a, :), z);
            regionParts{w, a, z} = summaryRow(label, AXIS_NAMES(a), ZONE_NAMES(z), points.shotNo(inZone), ...
                pointParts{w}(inZone, :), kSets, notCorrected);
        end
    end
end
result.options = options;
result.description = options.description;
result.terms = vertcat(zoneTerms{:});
result.vifInfo = vifInfos{1};
result.reduction = reduction;
result.shortage = shortage;
result.coefficients = coefficientTable([rtParts{:}, coefficientParts{:}]);
if options.waferRtRange == "outer"
    result.coefficients.zone(result.coefficients.component == "Wafer 成分") = ZONE_NAMES(1);   % Wafer 成分は内周の Shot だけ
end
result.commonCoefficients = coefficientTable([commonParts{:}]);
result.groupReductions = groupReductionTable(groupReductionParts(:));
result.points = vertcat(pointParts{:});
all_ = result.points;
allKeys = all_.wafer + "|" + string(all_.shotNo);
for a = 1:2
    axisName = AXIS_NAMES(a);
    summaryParts{end, a} = summaryRow(ALL_LABEL, axisName, ALL_REGION, allKeys, all_, ...
        counts.groups(a) - counts.skipped(a), counts.skipped(a));
    for z = 1:2
        inZone = all_.zone == ZONE_NAMES(z);
        [kSets, notCorrected] = zoneGroupCounts(totalFitted(a, :), totalSkipped(a, :), z);
        regionParts{end, a, z} = summaryRow(ALL_LABEL, axisName, ZONE_NAMES(z), allKeys(inZone), all_(inZone, :), ...
            kSets, notCorrected);
    end
end
result.summary = xFirst(vertcat(summaryParts{:}));
% 内周・外周の行：Wafer ごとに内周・外周の順（X の行、Y の行の順）
regions = permute(regionParts, [3, 1, 2]);
result.regionSummary = xFirst(vertcat(regions{:}));
result.messages = [reductionMessages(reduction, sequential); buildMessages(options, wafers, everything, counts, vifInfos, ...
    zoneSplit, ZONE_NAMES)];
end

function rows = xFirst(rows)
% X の行、Y の行の順に並べる（同じ軸の中は元の順）
[~, order] = sortrows([rows.axis == "Y", (1:height(rows)).']);
rows = rows(order, :);
end

function numbers = droppedTerms(reduction, zoneIndex)
% 項数の絞り込みで外した k の番号（式の範囲ごと）
numbers = [reduction([reduction.zoneIndex] == zoneIndex).dropped];
end

function check = checkShortage(terms, wafers, unit, formulaAxes, zoneSplit)
% 点が足りない k の組を調べる（計算の前の確かめ）：式の範囲（外周の式を分けないときは1つ、分けるときは内周・外周。terms は
% 範囲ごとの項の表の cell）・軸ごとに、k の組（Shot ごとなら Shot、ほかは Wafer・Scan 方向・行の偶奇の組。外周の式を分ける
% ときはその範囲の組）の点の配置で、使う項がすべて決まるかを調べる（determinableTerms。正則化は考えない）。
% 基準の組は、k1〜k6 を決められて点の数が最も少ない組。その点の配置で決められない項が dropped（「全体の項を減らす」で外す項）。
% check：範囲・軸ごとの axis・zone・zoneIndex・reference・nPoints・nUsed・dropped・nGroups・nShort・nUnfit
% （alignest.shotHighOrder の result.shortage）
ZONE_NAMES = ["内周", "外周"];
check = struct("axis", {}, "zone", {}, "zoneIndex", {}, "reference", {}, "nPoints", {}, "nUsed", {}, "dropped", {}, ...
    "nGroups", {}, "nShort", {}, "nUnfit", {});
columns = ["valueX", "valueY"];
for z = 1:numel(terms)
    zoneTerms = terms{z};
    for a = 1:numel(formulaAxes)
        axisTerms = zoneTerms(zoneTerms.axis == formulaAxes(a) & zoneTerms.used, :);
        best = struct("n", Inf, "local", zeros(0, 2), "label", "");
        [nGroups, nShort, nUnfit] = deal(0);
        for w = 1:numel(wafers)
            points = wafers(w).points;
            [key, nameOf] = groupOfPoints(points, unit, zoneSplit);
            valid = find(isfinite(points.(columns(a))) & isfinite(points.shotNo) & isfinite(key));
            if zoneSplit
                valid = valid(points.zone(valid) == z);
            end
            [keys, ~, index] = unique(key(valid));
            for g = 1:numel(keys)
                members = valid(index == g);
                local = [points.localX(members), points.localY(members)];
                nGroups = nGroups + 1;
                if rank([ones(numel(members), 1), local]) < 3
                    nUnfit = nUnfit + 1;   % k1〜k6 を決められない組は補正しない（基準にしない）
                    nShort = nShort + 1;
                    continue
                end
                [~, groupDropped] = determinableTerms(axisTerms, local);
                nShort = nShort + ~isempty(groupDropped);
                if numel(members) < best.n
                    name = string(wafers(w).label);
                    if unit ~= "common" || zoneSplit
                        name = name + " の " + nameOf(keys(g), points.shotNo(members(1)));
                    end
                    best = struct("n", numel(members), "local", local, "label", name);
                end
            end
        end
        entry = struct("axis", formulaAxes(a), "zone", ternaryText(zoneSplit, ZONE_NAMES(z), ""), "zoneIndex", z, ...
            "reference", "", "nPoints", NaN, "nUsed", height(axisTerms), "dropped", zeros(1, 0), "nGroups", nGroups, ...
            "nShort", nShort, "nUnfit", nUnfit);
        if isfinite(best.n)
            [~, entry.dropped] = determinableTerms(axisTerms, best.local);
            entry.reference = best.label;
            entry.nPoints = best.n;
        end
        check(end + 1) = entry; %#ok<AGROW>
    end
end
end

function [terms, reduction] = reduceTerms(terms, check)
% 「全体の項を減らす」：範囲・軸ごとに、基準の組（点の数が最も少ない組。checkShortage）の点の配置で決められない項を、
% すべての組で使わない。reduction：範囲・軸ごとの axis・zone・zoneIndex・reference（基準の組）・nPoints・dropped（外した
% k の番号）
reduction = rmfield(check, ["nUsed", "nGroups", "nShort", "nUnfit"]);
for entry = check
    zoneTerms = terms{entry.zoneIndex};
    zoneTerms.used(zoneTerms.axis == entry.axis & ismember(zoneTerms.k, entry.dropped)) = false;
    terms{entry.zoneIndex} = zoneTerms;
end
end

function messages = shortageMessages(check, options, zoneSplit)
% 計算の前の知らせ：点が足りない k の組があれば、範囲・軸ごとに、点の数が最も少ない組で決められない項と足りない組の数、
% 「点が足りない Shot」の扱いで計算のときにどうなるかを書く（足りなければ空）
GROUP_NAMES = struct("common", "Wafer", "scan", "k の組（Scan 方向）", "row", "k の組（行の偶奇）", "shot", "Shot");
groupName = GROUP_NAMES.(options.unit);
if zoneSplit && options.unit == "common"
    groupName = "k の組（内周・外周）";
end
messages = strings(0, 1);
for entry = check
    if isempty(entry.dropped) && entry.nShort == 0
        continue
    end
    axisText = entry.axis;
    if entry.zone ~= ""
        axisText = axisText + "（" + entry.zone + "の式）";
    end
    text = "⚠ " + axisText + "：";
    if ~isempty(entry.dropped)
        text = text + sprintf("点の数が最も少ない %s（%s：%d 点）では、使う %d 項のうち %d 項（%s）が決まりません。", ...
            groupName, entry.reference, entry.nPoints, entry.nUsed, numel(entry.dropped), ...
            strjoin("k" + string(entry.dropped), "・"));
    end
    text = text + sprintf("使う項がすべては決まらない %s：%d / %d", groupName, entry.nShort, entry.nGroups);
    if entry.nUnfit > 0
        text = text + sprintf("（うち k1〜k6 も決まらない %d は補正しません）", entry.nUnfit);
    end
    messages(end + 1, 1) = text + "。"; %#ok<AGROW>
end
if isempty(messages)
    return
end
switch options.shortage
    case "reduceAll"
        consequence = "「補正を計算する」では、点の数が最も少ない " + groupName + " で決められない項を、すべての " + ...
            groupName + " で外して計算します（「点が足りない Shot」で、その " + groupName + " だけ項を減らす・補正しないも選べます）。";
    case "reduceGroup"
        consequence = "「補正を計算する」では、点が足りない " + groupName + " だけ、その点で決められる項で補正します。";
    otherwise
        consequence = "「補正を計算する」では、点が足りない " + groupName + " は補正しません（正則化をかけた次数の項は、" + ...
            "点が少なくても決まります）。";
end
if options.unit == "shot" && options.shotCommon ~= "none"
    consequence = consequence + "Shot 共通を先に引くので、減らすのは Shot ごとに求める項だけです（Shot 共通の項はすべて使います）。";
end
messages(end + 1, 1) = consequence;
end

function messages = reductionMessages(info, sequential)
% 項数を絞ったときの知らせ（絞らなければ空）。sequential：Shot 共通を先に引くとき（Shot ごとに求める項だけを減らす）
messages = strings(0, 1);
for a = 1:numel(info)
    if isempty(info(a).dropped)
        continue
    end
    axisText = info(a).axis;
    if info(a).zone ~= ""
        axisText = axisText + "（" + info(a).zone + "の式）";
    end
    template = ['⚠ %s：選んだ項が、点の数が最も少ない k の組（%s：%d 点）では求められないため、' ...
        'k の小さい順に決められる項だけを使いました（外した項：%s）。'];
    if sequential
        template = ['⚠ %s：Shot ごとに求める項が、点の数が最も少ない Shot（%s：%d 点）では求められないため、Shot ごとには' ...
            ' k の小さい順に決められる項だけを求めました（Shot 共通の値だけにした項：%s）。'];
    end
    messages(end + 1, 1) = sprintf(template, axisText, info(a).reference, info(a).nPoints, ...
        strjoin("k" + string(info(a).dropped), "・")); %#ok<AGROW>
end
end

function points = withGroupColumns(points, outerRadiusMm)
% 点の表に、Scan 方向（direction）・Shot 行の奇偶（rowParity）の列が無ければ足し（Scan 方向は分からない。行は Shot 中心の
% Y 座標が同じ Shot の並びを上から数える。alignest.prepareData の Shot 行と同じ数え方）、Shot 中心の半径（shotRadius）と
% 内周・外周（zone：1 = 内周、2 = 外周。半径が outerRadiusMm 以上を外周）を足す
SHOT_COORDINATE_DIGITS = 3;   % 行を判定する桁（1 µm。alignest.prepareData と同じ）
RADIUS_TOLERANCE_MM = 1e-9;   % 境界ちょうどの Shot を外周に入れる（計算の丸めの差を除く）
names = string(points.Properties.VariableNames);
if ~any(names == "direction")
    points.direction = nan(height(points), 1);
end
if ~any(names == "rowParity")
    rowY = round(points.Yc, SHOT_COORDINATE_DIGITS);
    [~, row] = ismember(rowY, sort(unique(rowY(isfinite(rowY))), 'descend'));
    parity = 1 + mod(row - 1, 2);
    parity(row == 0) = NaN;
    points.rowParity = parity;
end
points.shotRadius = hypot(points.Xc, points.Yc);
zone = 1 + double(points.shotRadius >= outerRadiusMm - RADIUS_TOLERANCE_MM);
zone(~isfinite(points.shotRadius)) = NaN;
points.zone = zone;
end

function [key, nameOf] = groupOfPoints(points, unit, zoneSplit)
% 点ごとの k の組の番号（分からない点は NaN）と、組の名前を返す関数 nameOf(番号, shotNo)。外周の式を分けるときは、
% Shot ごとのほかは内周・外周で別の組にする（番号は 範囲の番号 × ZONE_STRIDE ＋ くくりの番号、名前は「内周・Scan 方向 1」など）
ROW_NAMES = ["奇数行", "偶数行"];
ZONE_NAMES = ["内周", "外周"];
ZONE_STRIDE = 10;   % 範囲ごとに番号をずらす幅（くくりの番号は 1・2）
n = height(points);
switch unit
    case "common"
        key = ones(n, 1);
        baseName = @(keys) repmat("共通", numel(keys), 1);
    case "scan"
        key = points.direction;
        key(~ismember(key, [1, 2])) = NaN;
        baseName = @(keys) "Scan 方向 " + string(keys(:));
    case "row"
        key = points.rowParity;
        key(~ismember(key, [1, 2])) = NaN;
        baseName = @(keys) reshape(ROW_NAMES(keys), [], 1);
    otherwise
        key = points.shotNo;
        if zoneSplit
            key(~isfinite(points.zone)) = NaN;
        end
        nameOf = @(~, shotNos) "Shot " + string(shotNos(:));
        return
end
if ~zoneSplit
    nameOf = @(keys, ~) baseName(keys);
    return
end
key = key + (points.zone - 1) * ZONE_STRIDE;
zoneName = @(keys) reshape(ZONE_NAMES(floor((keys(:) - 1) / ZONE_STRIDE) + 1), [], 1);
if unit == "common"
    nameOf = @(keys, ~) zoneName(keys);
else
    nameOf = @(keys, ~) zoneName(keys) + "・" + baseName(mod(keys(:) - 1, ZONE_STRIDE) + 1);
end
end

function fitUnits = partitionRows(rows, points, groupKey, groupName, unit, zoneSplit)
% 一緒に求める点の集まり（members）と、その中の k の組（groupIndex：1〜組の数、labels：組の名前、zones：組の式の範囲
% （1 = 内周の式、2 = 外周の式。外周の式を分けないときはすべて 1））。Shot ごとは Shot ごとに別に求める。ほかは Wafer の点を
% まとめて求める（Wafer 成分は共通、k は組ごと）
fitUnits = struct("members", {}, "groupIndex", {}, "labels", {}, "shotNo", {}, "zones", {});
if isempty(rows)
    return   % この軸の値が無い Wafer
end
if unit == "shot"
    [shots, ~, index] = unique(points.shotNo(rows));
    for s = 1:numel(shots)
        members = rows(index == s);
        zone = 1;
        if zoneSplit
            zone = points.zone(members(1));
        end
        fitUnits(s) = struct("members", members, "groupIndex", ones(numel(members), 1), "labels", ...
            groupName(1, shots(s)), "shotNo", shots(s), "zones", zone);
    end
    return
end
[keys, first, index] = unique(groupKey(rows));
zones = ones(1, numel(keys));
if zoneSplit
    zones = reshape(points.zone(rows(first)), 1, []);
end
fitUnits(1) = struct("members", rows, "groupIndex", index, "labels", groupName(keys, nan(size(keys))), "shotNo", NaN, ...
    "zones", zones);
end

function zones = groupZones(pointZones, groupIndex, nGroups)
% k の組ごとの範囲（1 = 内周・2 = 外周。組の点が内周と外周にまたがるときは 0）
zones = zeros(1, nGroups);
for g = 1:nGroups
    mine = unique(pointZones(groupIndex == g));
    if isscalar(mine) && isfinite(mine)
        zones(g) = mine;
    end
end
end

function [kSets, skipped] = zoneGroupCounts(fitted, notFitted, zone)
% 内周・外周の行の k の組の数（内周と外周にまたがる組があれば数えられないので NaN）
if fitted(1) + notFitted(1) > 0
    [kSets, skipped] = deal(NaN);
else
    kSets = fitted(zone + 1);
    skipped = notFitted(zone + 1);
end
end

function [terms, dropped] = determinableTerms(terms, local)
% 点の配置（Shot 内の座標 local）で決められる項だけを使う：k1〜k6 を先に、残りは k の番号の小さい順に、前の項で表せない項を
% 選び、表せる項（点が足りない・点の配置で決まらない項）の used を false にする（k1〜k6 は外さない）。terms：1つの軸の項の表、
% dropped：外した k の番号（小さい順）
RELATIVE_TOLERANCE = 1e-9;   % 前の項で表せる割合がこれより大きい項は、決められない項とする（alignest.robustRidgeFit と同じ）
rows = find(terms.used);
[~, order] = sortrows([~terms.protected(rows), terms.k(rows)]);   % k1〜k6 を先に、残りは k の小さい順
rows = rows(order);
basis = zeros(size(local, 1), 0);
dropped = zeros(1, 0);
for row = reshape(rows, 1, [])
    column = local(:, 1) .^ terms.xPower(row) .* local(:, 2) .^ terms.yPower(row);
    scale = norm(column);
    remainder = column;
    for pass = 1:2
        remainder = remainder - basis * (basis.' * remainder);
    end
    if scale > 0 && norm(remainder) > sqrt(RELATIVE_TOLERANCE) * scale
        basis(:, end + 1) = remainder / norm(remainder); %#ok<AGROW>
    elseif ~terms.protected(row)
        terms.used(row) = false;
        dropped(end + 1) = terms.k(row); %#ok<AGROW>
    end
end
dropped = sort(dropped);
end

function [groupTerms, dropped] = reduceGroupTerms(local, groupIndex, groupTerms)
% 「その組だけ項を減らす」：k の組（groupIndex）ごとに、その組の点の配置（Shot 内の座標 local）で決められる項だけを使う
% （determinableTerms。k1〜k6 は外さない）。dropped：組ごとの外した k の番号
dropped = cell(1, numel(groupTerms));
for g = 1:numel(groupTerms)
    [terms, dropped{g}] = determinableTerms(groupTerms{g}, local(groupIndex == g, :));
    groupTerms{g} = terms(terms.used, :);
end
end

function rows = groupReductionRows(label, axisName, fitUnit, dropped, zoneSplit)
% 「その組だけ項を減らす」で項を減らした k の組の行（wafer・axis・group・shotNo・zone・dropped）
ZONE_NAMES = ["内周", "外周"];
reduced = find(~cellfun(@isempty, dropped));
n = numel(reduced);
zone = strings(n, 1);
if zoneSplit
    zone = reshape(ZONE_NAMES(fitUnit.zones(reduced)), [], 1);
end
text = strings(n, 1);
for j = 1:n
    text(j) = strjoin("k" + string(dropped{reduced(j)}), "・");
end
rows = table(repmat(string(label), n, 1), repmat(string(axisName), n, 1), reshape(fitUnit.labels(reduced), [], 1), ...
    repmat(fitUnit.shotNo, n, 1), zone, text, 'VariableNames', ["wafer", "axis", "group", "shotNo", "zone", "dropped"]);
end

function reductions = groupReductionTable(parts)
% 項を減らした k の組の表を縦につなぐ（無ければ列だけの表）
parts = parts(~cellfun(@isempty, parts));
if isempty(parts)
    reductions = table(strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
        'VariableNames', ["wafer", "axis", "group", "shotNo", "zone", "dropped"]);
else
    reductions = vertcat(parts{:});
end
end

function block = waferBlock(coordinates, powers)
% Wafer 成分の項の値（Shot 中心の座標 Xc・Yc の多項式。5列目が 0 の点（RT で補正する Shot）は 0）
block = coordinates(:, 3) .^ (powers(:, 1).') .* coordinates(:, 4) .^ (powers(:, 2).') .* coordinates(:, 5);
end

function rt = fitWaferRt(points, values, hasGroup, options, waferRadiusMm)
% Wafer RT：RT モデルを Shot 中心の座標で、X・Y を一緒に当てはめる（1 Wafer 分。k の組の分からない点は補正の式と同じく使わない
% （hasGroup が false の点））。rt.inScope：RT で補正する Shot の点、
% rt.part：点ごとの RT の補正量（点の数 × 2。ほかの点は 0）、rt.leverage：ハット行列の対角（X・Y の行を点に戻す。ほかの点は 0）、
% rt.names・coefficients・determined：項ごとの名前・係数・決まったか、rt.nDropped：決まらなかった項の数、rt.converged
n = height(points);
rt = struct("inScope", false(n, 1), "part", zeros(n, 2), "leverage", zeros(n, 2), "names", strings(0, 1), ...
    "coefficients", zeros(0, 1), "determined", false(0, 1), "nDropped", 0, "converged", true);
if options.waferRtRange == "none"
    return
end
rt.inScope = isfinite(points.shotNo) & isfinite(points.Xc) & isfinite(points.Yc);
if options.waferRtRange == "outer"
    rt.inScope = rt.inScope & points.zone == 2;
end
rowsX = find(rt.inScope & hasGroup & isfinite(values(:, 1)));
rowsY = find(rt.inScope & hasGroup & isfinite(values(:, 2)));
if isempty(rowsX) && isempty(rowsY)
    return   % 補正する Shot の値が無い Wafer（例：外周の Shot が無い）
end
[basisX, basisY, rt.names] = alignest.basis.rtDesign([points.Xc, points.Yc] / waferRadiusMm, options.waferRtOrder);
lossName = options.loss(1);
if options.loss(2) ~= lossName
    lossName = "ols";   % X・Y を一緒に求めるので、損失関数が違うときは最小二乗
end
fit = alignest.robustRidgeFit([basisX(rowsX, :); basisY(rowsY, :)], [values(rowsX, 1); values(rowsY, 2)], ...
    false(numel(rt.names), 1), 'loss', lossName, 'huberTuning', options.huberTuning(1), 'lambda', 0);
rt.coefficients = fit.coefficients;
rt.determined = fit.determined;
rt.nDropped = nnz(~fit.determined);
rt.converged = fit.converged;
rt.part(rt.inScope, :) = [basisX(rt.inScope, :) * fit.coefficients, basisY(rt.inScope, :) * fit.coefficients];
rt.leverage(rowsX, 1) = fit.leverage(1:numel(rowsX));
rt.leverage(rowsY, 2) = fit.leverage(numel(rowsX) + 1:end);
end

function rows = waferRtRows(label, rt, options)
% Wafer RT の係数の行（coefficientRows と同じ形。RT を使わない・値が無ければ空）
rows = [];
n = numel(rt.names);
if n == 0
    return
end
note = strings(n, 1);
note(~rt.determined) = "点の配置では決まらない（0 にした）";
rows = struct("wafer", repmat(string(label), n, 1), "shotNo", nan(n, 1), "group", repmat("Wafer で共通", n, 1), ...
    "zone", repmat(ternaryText(options.waferRtRange == "outer", "外周", ""), n, 1), "axis", repmat("dx・dy", n, 1), ...
    "component", repmat("Wafer RT", n, 1), "k", nan(n, 1), "term", rt.names, "value", rt.coefficients, ...
    "unit", repmat("nm", n, 1), "note", note, "xPower", nan(n, 1), "yPower", nan(n, 1));
end

function terms = eachShotTerms(terms, maxOrder)
% Shot 共通を先に引くとき、Shot ごとに求める項：使う項のうち次数が maxOrder 以下の項（0 なら使う項すべて。k1〜k6 は必ず
% 使う）。terms：式の範囲ごとの項の表の cell
if maxOrder <= 0
    return
end
for z = 1:numel(terms)
    terms{z}.used = terms{z}.used & (terms{z}.order <= maxOrder | terms{z}.protected);
end
end

function [fitted, waferPart, commonPart, info] = applyInputCommon(points, coordinates, values, hasGroup, axisTerms, ...
        inputValues, waferPowers, zoneSplit, fitOptions)
% 入力した Shot 共通の k を先に引く（1つの軸）。commonPart：点ごとの入力した k の分（外周の式を分けるときは、外周の Shot は
% 外周の式の k）。Wafer 成分があれば、入力した k を引いた残りに定数と Wafer 成分を当てはめて求める（定数は Shot ごとの
% k1・k2 に入るので引かない）。fitted：Wafer 成分 + 入力した k の分（補正の段階「Wafer 高次補正＋Shot 共通補正」。Shot・
% k の組の分からない点は NaN）、waferPart：点ごとの Wafer 成分の分（定数は含めない）、info：Wafer 成分の当てはめ（fit。
% fitGroups の結果）。Wafer 成分が無い・点が無ければ []
n = height(points);
commonPart = zeros(n, 1);
zoneOf = ones(n, 1);
if zoneSplit
    zoneOf = points.zone;
end
for z = 1:numel(axisTerms)
    inZone = zoneOf == z;
    terms = axisTerms{z};
    commonPart(inZone) = (coordinates(inZone, 1) .^ (terms.xPower.') .* coordinates(inZone, 2) .^ (terms.yPower.')) * ...
        valuesOfK(inputValues{z}, terms.k);
end
rows = find(isfinite(values) & isfinite(points.shotNo) & hasGroup);
fitted = nan(n, 1);
waferPart = zeros(n, 1);
info = [];
if ~isempty(waferPowers) && ~isempty(rows)
    constant = axisTerms{1}(axisTerms{1}.order == 0, :);
    fit = fitGroups(coordinates(rows, :), values(rows) - commonPart(rows), ones(numel(rows), 1), {constant}, waferPowers, ...
        struct("lambda", 0, "orders", zeros(1, 0)), fitOptions);
    info = struct("fit", fit);
    if any(fit.ok)
        coefficients = fit.waferCoefficients;
        coefficients(~isfinite(coefficients)) = 0;
        waferPart = waferBlock(coordinates, waferPowers) * coefficients;
        waferPart(~isfinite(waferPart)) = 0;
    end
end
fitted(rows) = commonPart(rows) + waferPart(rows);
end

function rows = inputCommonRows(label, axisName, axisTerms, inputValues, zoneSplit)
% 入力した Shot 共通の k の行（coefficientRows と同じ形。component は "Shot 共通"、メモは「入力した値」）
ZONE_NAMES = ["内周", "外周"];
INPUT_NOTE = "入力した値";
parts = cell(1, numel(axisTerms));
for z = 1:numel(axisTerms)
    terms = axisTerms{z};
    n = height(terms);
    [zone, group] = deal("", "共通");
    if zoneSplit
        [zone, group] = deal(ZONE_NAMES(z));
    end
    parts{z} = struct("wafer", repmat(string(label), n, 1), "shotNo", nan(n, 1), "group", repmat(group, n, 1), ...
        "zone", repmat(zone, n, 1), "axis", repmat(string(axisName), n, 1), "component", repmat("Shot 共通", n, 1), ...
        "k", terms.k, "term", reshape(termNames(terms), [], 1), "value", valuesOfK(inputValues{z}, terms.k), ...
        "unit", unitText(terms.order), "note", repmat(INPUT_NOTE, n, 1), "xPower", terms.xPower, "yPower", terms.yPower);
end
rows = [parts{:}];
end

function values = valuesOfK(vector, kNumbers)
% 入力した k の値の並び（n 番目が kn の値）から、kNumbers の k の値を取り出す（並びより大きい番号の k は 0）
values = zeros(numel(kNumbers), 1);
inside = kNumbers <= numel(vector);
values(inside) = vector(kNumbers(inside));
end

function rows = withCommonValues(rows, common, zone)
% Shot 共通を先に引いたとき：Shot ごとの k（Shot 共通を引いた残りに当てはめた値。1つの Shot の行）に、同じ式の範囲の
% Shot 共通の k を足して、その Shot に当てる k にする（alignest.highOrderLevels の「Shot 毎」は、ここから Shot 共通を
% 引いて戻す）。Shot ごとに求めない Shot 共通の項（次数の上限より上・点が足りず減らした項）は、Shot 共通の値の行を足す
EACH_LEFT_NOTE = "Shot ごとには求めない項（Shot 共通の値）";
if isempty(common) || isempty(rows.k)
    return
end
mine = common(common.zone == zone, :);
[found, position] = ismember(rows.k, mine.k);
rows.value(found) = rows.value(found) + mine.value(position(found));
extra = mine(~ismember(mine.k, rows.k), :);
n = height(extra);
if n == 0
    return
end
added = struct("wafer", extra.wafer, "shotNo", repmat(rows.shotNo(1), n, 1), "group", repmat(rows.group(1), n, 1), ...
    "zone", extra.zone, "axis", extra.axis, "component", repmat(rows.component(1), n, 1), "k", extra.k, ...
    "term", extra.term, "value", extra.value, "unit", extra.unit, "note", repmat(EACH_LEFT_NOTE, n, 1), ...
    "xPower", extra.xPower, "yPower", extra.yPower);
for name = string(fieldnames(rows)).'
    rows.(name) = [rows.(name); added.(name)];
end
end

function fitted = fitWaferOnly(coordinates, values, hasShot, powers, fitOptions)
% Wafer 高次補正だけ：Shot 中心の座標 Xc・Yc の多項式（powers のべき。定数を含む）を、Shot の分かる点で当てはめた補正量
% （正則化なし。同じ損失関数）。決まらない項は 0（alignest.robustRidgeFit）。点が無ければ NaN
fitted = nan(numel(values), 1);
rows = find(isfinite(values) & hasShot);
if isempty(rows)
    return
end
design = waferBlock(coordinates(rows, :), powers);
fit = alignest.robustRidgeFit(design, values(rows), false(size(powers, 1), 1), fitOptions{:}, 'lambda', 0);
fitted(rows) = fit.fitted;
end

function [fitted, waferPart, info] = fitCommon(points, coordinates, values, axisTerms, waferPowers, zoneSplit, penalty, ...
        fitOptions, reduceGroups)
% Wafer 高次補正＋Shot 共通補正：Wafer 成分と、Wafer 内の Shot で共通の k（外周の式を分けるときは内周・外周の2組）を全点で
% 一緒に求める（「Wafer 内で共通」と同じ求め方。reduceGroups なら組の点で決められる項だけ）。fitted：点ごとの補正量（求め
% られなかった点は NaN）、waferPart：点ごとの Wafer 成分の分（定数は含めない。求められなければ 0）。Shot ごとで Wafer 成分が
% あるときは、この Wafer 成分を先に引いてから Shot ごとの k を求める（Wafer 成分は Shot 中心の座標の関数なので、補正量・
% 残差は変わらず、Shot ごとの k1・k2 が Wafer 成分を除いた値になる）。info：fit（fitGroups の結果）・unit（点の集まり）・
% terms（組ごとの項）。点が無ければ []
n = height(points);
fitted = nan(n, 1);
waferPart = zeros(n, 1);
info = [];
[key, name] = groupOfPoints(points, "common", zoneSplit);
rows = find(isfinite(values) & isfinite(points.shotNo) & isfinite(key));
fitUnits = partitionRows(rows, points, key, name, "common", zoneSplit);
if isempty(fitUnits)
    return
end
unit = fitUnits(1);
terms = axisTerms(unit.zones);
if reduceGroups
    terms = reduceGroupTerms(coordinates(unit.members, 1:2), unit.groupIndex, terms);
end
fit = fitGroups(coordinates(unit.members, :), values(unit.members), unit.groupIndex, terms, waferPowers, penalty, ...
    fitOptions);
info = struct("fit", fit, "unit", unit, "terms", {terms});
if ~any(fit.ok)
    return
end
fitted(unit.members) = fit.fitted;
coefficients = fit.waferCoefficients;
coefficients(~isfinite(coefficients)) = 0;
waferPart = waferBlock(coordinates, waferPowers) * coefficients;
waferPart(~isfinite(waferPart)) = 0;
end

function out = fitGroups(coordinates, values, groupIndex, groupTerms, waferPowers, penalty, fitOptions)
% 一緒に求める点の集まりに補正の式を当てはめる：k は組（groupIndex）ごと（組 g の項は groupTerms{g}。外周の式を分けると
% 組ごとに項が違う）、Wafer 成分は共通。項がすべては決まらない組は補正しない（その組を除いて求め直す。組の項はその組の
% 点だけで決まるので、ほかの組は変わらない）。
% coordinates：点ごとの [Shot 内の x, Shot 内の y, Shot 中心の Xc, Yc, Wafer 成分を使うか（1・0）]。penalty：正則化の強さ lambda とかける項の次数 orders。
% out.ok：補正した組、out.fitted・weights・looResidual（1点抜きの予測の誤差）・leverage（ハット行列の対角）：点ごと（補正しない組の点は NaN）、
% out.coefficients・determined・constant：組ごとの cell（組の項の数 × 1）、out.waferCoefficients・waferDetermined・
% waferConstant：Wafer 成分の項
nGroups = max([groupIndex(:); 0]);
nWafer = size(waferPowers, 1);
n = numel(values);
emptyOf = @(fill) cellfun(@(terms) fill(height(terms), 1), groupTerms, 'UniformOutput', false);
out = struct("ok", false(1, nGroups), "fitted", nan(n, 1), "weights", nan(n, 1), "looResidual", nan(n, 1), ...
    "leverage", nan(n, 1), ...
    "coefficients", {emptyOf(@nan)}, "determined", {emptyOf(@false)}, "constant", {emptyOf(@false)}, ...
    "waferCoefficients", nan(nWafer, 1), "waferDetermined", true(nWafer, 1), "waferConstant", false(nWafer, 1), ...
    "converged", true, "robust", false);
active = 1:nGroups;
rows = true(n, 1);
local = groupIndex;
while ~isempty(active)
    if numel(active) < nGroups   % 決まらない組を除いたとき（はじめはすべての組）
        rows = ismember(groupIndex, active);
        [~, local] = ismember(groupIndex(rows), active);
    end
    fit = solveGroups(coordinates(rows, :), values(rows), local, groupTerms(active), waferPowers, penalty, fitOptions);
    ok = true(1, numel(active));
    for j = 1:numel(active)
        out.determined{active(j)} = fit.determined(fit.columns{j});
        ok(j) = all(out.determined{active(j)});
    end
    if all(ok)
        break
    end
    active = active(ok);   % 決まらない組を除いて求め直す（残りが無ければ終わり）
end
if isempty(active)
    return
end
out.ok(active) = true;
out.fitted(rows) = fit.fitted;
out.looResidual(rows) = fit.looResidual;
out.leverage(rows) = fit.leverage;
out.weights(rows) = fit.weights;
for j = 1:numel(active)
    out.coefficients{active(j)} = fit.coefficients(fit.columns{j});
    out.constant{active(j)} = fit.constant(fit.columns{j});
end
out.waferCoefficients = fit.coefficients(fit.waferColumns);
out.waferDetermined = fit.determined(fit.waferColumns);
out.waferConstant = fit.constant(fit.waferColumns);
out.converged = fit.converged;
out.robust = fit.robust;
end

function fit = solveGroups(coordinates, values, groupIndex, groupTerms, waferPowers, penalty, fitOptions)
% 設計行列：組ごとの補正の式の項（その組の点だけ値があり、ほかは 0）と、共通の Wafer 成分の項。
% fit.columns{g}：組 g の項の列、fit.waferColumns：Wafer 成分の列
nGroups = numel(groupTerms);
widths = cellfun(@height, groupTerms);
blocks = zeros(numel(values), sum(widths));
isPenalized = false(sum(widths), 1);
columnGroup = zeros(sum(widths), 1);
columns = cell(1, nGroups);
offset = 0;
for g = 1:nGroups
    terms = groupTerms{g};
    columns{g} = offset + (1:height(terms));
    local = coordinates(:, 1) .^ (terms.xPower.') .* coordinates(:, 2) .^ (terms.yPower.');
    blocks(:, columns{g}) = local .* (groupIndex == g);
    isPenalized(columns{g}) = ismember(terms.order, penalty.orders);   % 選んだ次数の項だけ（Wafer 成分にはかけない）
    columnGroup(columns{g}) = g;
    offset = offset + height(terms);
end
wafer = waferBlock(coordinates, waferPowers);
nWafer = size(waferPowers, 1);
groupOptions = {};
if nGroups > 1
    groupOptions = {'rowGroup', groupIndex, 'columnGroup', [columnGroup; zeros(nWafer, 1)]};
end
fit = alignest.robustRidgeFit([blocks, wafer], values, [isPenalized; false(nWafer, 1)], fitOptions{:}, ...
    'lambda', penalty.lambda, groupOptions{:});
fit.columns = columns;
fit.waferColumns = offset + (1:nWafer);
end

function names = termNames(terms)
names = reshape("k" + string(terms.k) + "（" + terms.term + "）", 1, []);
end

function rows = coefficientRows(label, fitUnit, axisName, groupTerms, waferPowers, fit, zoneSplit, component)
% 係数の行（列ごとの配列の構造体。最後に coefficientTable で表にする）：補正した k の組ごとの補正の式の項（k。component の
% 名前。省略時は "Shot 高次補正"）と、Wafer で共通の Wafer 成分の項
ZONE_NAMES = ["内周", "外周"];
if nargin < 8
    component = "Shot 高次補正";
end
groups = find(fit.ok);
parts = cell(1, numel(groups) + 1);
for j = 1:numel(groups)
    g = groups(j);
    terms = groupTerms{g};
    n = height(terms);
    note = strings(n, 1);
    note(fit.constant{g}) = "点の配置では値が変わらない（定数と同じ）ので 0";
    note(~fit.determined{g}) = "点の配置では決まらない（0 にした）";
    zone = "";
    if zoneSplit
        zone = ZONE_NAMES(fitUnit.zones(g));
    end
    parts{j} = struct("wafer", repmat(string(label), n, 1), "shotNo", repmat(fitUnit.shotNo, n, 1), ...
        "group", repmat(fitUnit.labels(g), n, 1), "zone", repmat(zone, n, 1), "axis", repmat(string(axisName), n, 1), ...
        "component", repmat(component, n, 1), "k", terms.k, "term", reshape(termNames(terms), [], 1), ...
        "value", fit.coefficients{g}, "unit", unitText(terms.order), "note", note, "xPower", terms.xPower, ...
        "yPower", terms.yPower);
end
if ~isempty(waferPowers)
    parts{end} = waferRows(label, axisName, waferPowers, fit);
end
rows = [parts{:}];
end

function rows = waferRows(label, axisName, waferPowers, fit)
% Wafer で共通の Wafer 成分の係数の行（coefficientRows と同じ形）
nWafer = size(waferPowers, 1);
note = strings(nWafer, 1);
note(fit.waferConstant) = "点の配置では値が変わらない（定数と同じ）ので 0";
note(~fit.waferDetermined) = "点の配置では決まらない（0 にした）";
rows = struct("wafer", repmat(string(label), nWafer, 1), "shotNo", nan(nWafer, 1), ...
    "group", repmat("Wafer で共通", nWafer, 1), "zone", strings(nWafer, 1), "axis", repmat(string(axisName), nWafer, 1), ...
    "component", repmat("Wafer 成分", nWafer, 1), "k", nan(nWafer, 1), "term", waferTermNames(waferPowers), ...
    "value", fit.waferCoefficients, "unit", unitText(sum(waferPowers, 2)), "note", note, ...
    "xPower", waferPowers(:, 1), "yPower", waferPowers(:, 2));
end

function coefficients = coefficientTable(parts)
% 係数の行（coefficientRows の構造体の配列）を縦につないで表にする（行が無ければ列だけの表）
% xPower・yPower は項のべき（Shot 高次補正は Shot 内の x・y、Wafer 成分は Shot 中心の Xc・Yc。alignest.highOrderModelAt。
% Wafer RT は NaN）
names = ["wafer", "shotNo", "group", "zone", "axis", "component", "k", "term", "value", "unit", "note", "xPower", "yPower"];
if isempty(parts)
    parts = struct("wafer", strings(0, 1), "shotNo", zeros(0, 1), "group", strings(0, 1), "zone", strings(0, 1), ...
        "axis", strings(0, 1), "component", strings(0, 1), "k", zeros(0, 1), "term", strings(0, 1), "value", ...
        zeros(0, 1), "unit", strings(0, 1), "note", strings(0, 1), "xPower", zeros(0, 1), "yPower", zeros(0, 1));
end
columns = cell(1, numel(names));
for k = 1:numel(names)
    columns{k} = vertcat(parts.(names(k)));
end
coefficients = table(columns{:}, 'VariableNames', names);
end

function names = waferTermNames(powers)
% Wafer 成分の項の名前（Shot 中心の座標を Xc・Yc と書く）
names = strings(size(powers, 1), 1);
for k = 1:size(powers, 1)
    parts = strings(0, 1);
    for v = 1:2
        symbol = ["Xc", "Yc"];
        if powers(k, v) == 1
            parts(end + 1) = symbol(v); %#ok<AGROW>
        elseif powers(k, v) > 1
            parts(end + 1) = symbol(v) + "^" + powers(k, v); %#ok<AGROW>
        end
    end
    names(k) = strjoin(parts, "·");
end
end

function powers = polynomialPowers(order)
% Wafer 成分の項のべき [Xc のべき, Yc のべき]（1〜order 次。次数の順、同じ次数では Yc のべきが小さい順。定数は含めない）
powers = zeros(0, 2);
for degree = 1:order
    for powerY = 0:degree
        powers(end + 1, :) = [degree - powerY, powerY]; %#ok<AGROW>
    end
end
end

function text = unitText(order)
text = "nm/mm^" + string(order);
text(order == 0) = "nm";
text(order == 1) = "nm/mm（ppm）";
end

function text = ternaryText(condition, whenTrue, whenFalse)
if condition
    text = whenTrue;
else
    text = whenFalse;
end
end

function row = summaryRow(label, axisName, region, shotKeys, points, kSets, skipped)
% 1つの Wafer・軸・範囲の評価（points は点の表。axisName の列を使う）。補正前・Shot ごとの1次・高次補正の |平均|+3σ は、
% どちらの補正もできた点で比べる。|残差| の 95% 点・中央値も同じ点。kSets・skipped：求めた・補正しなかった k の組の数。
% 外れ値とみなした点：比べた点のうち、ロバスト回帰で重みを半分未満に下げた点（alignest.highOrderOutliers）
values = points.("value" + axisName);
residual = points.("residual" + axisName);
linearResidual = points.("linearResidual" + axisName);
weights = points.("weight" + axisName);
compared = isfinite(residual) & isfinite(linearResidual);
withValue = isfinite(values);
shots = numel(unique(shotKeys(withValue)));
before = meanPlus3Sigma(values(compared));
linear = meanPlus3Sigma(linearResidual(compared));
highOrder = meanPlus3Sigma(residual(compared));
rms = NaN;
if any(compared)
    rms = sqrt(mean(residual(compared) .^ 2));
end
magnitude = abs(residual(compared));
p95 = alignest.stats.percentile(magnitude, 95);
middle = NaN;
if ~isempty(magnitude)
    middle = median(magnitude);
end
[rSquared, adjustedRSquared] = alignest.highOrderRSquared(values, residual, points.("leverage" + axisName));
row = table(string(label), string(axisName), string(region), nnz(withValue), nnz(compared), shots, kSets, skipped, ...
    before, linear, highOrder, linear - highOrder, p95, middle, rms, nnz(compared & alignest.highOrderOutliers(weights)), ...
    rSquared, adjustedRSquared, 'VariableNames', ["wafer", "axis", "region", "n", "nCorrected", "shots", "kSets", ...
    "skipped", "before", "linear", "highOrder", "improvement", "highOrderP95", "highOrderMedian", "rmsHighOrder", ...
    "outliers", "rSquared", "adjustedRSquared"]);
end

function value = meanPlus3Sigma(values)
% Overlay の代表値 |平均| + 3σ（σ は不偏標準偏差）。点が2点未満なら NaN（alignest.overlayCorrection と同じ）
values = values(isfinite(values));
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end

function messages = buildMessages(options, wafers, everything, counts, vifInfos, zoneSplit, zoneNames)
messages = strings(0, 1);
messages(end + 1, 1) = sprintf('%d Wafer・%d 点（dx の値 %d 点・dy の値 %d 点）で求めました。補正：%s。', numel(wafers), ...
    height(everything), nnz(isfinite(everything.valueX)), nnz(isfinite(everything.valueY)), options.description);
noShot = nnz(~isfinite(everything.shotNo));
if noShot > 0
    messages(end + 1, 1) = sprintf('Shot の分からない点 %d 点は使っていません。', noShot);
end
shotKeys = strings(0, 1);
shotZones = zeros(0, 1);
for w = 1:numel(wafers)
    points = wafers(w).points;
    [shots, first] = unique(points.shotNo(isfinite(points.shotNo)));
    zones = points.zone(isfinite(points.shotNo));
    shotKeys = [shotKeys; string(w) + "|" + string(shots)]; %#ok<AGROW>
    shotZones = [shotZones; zones(first)]; %#ok<AGROW>
end
outerText = sprintf('外周の Shot（Shot 中心の半径 %g mm 以上）：%d Shot・内周 %d Shot（%d Wafer の合計）', ...
    options.outerRadiusMm, nnz(shotZones == 2), nnz(shotZones == 1), numel(wafers));
if zoneSplit
    messages(end + 1, 1) = outerText + "。外周の Shot は外周の式で、k の組を内周と別にして求めました。";
else
    messages(end + 1, 1) = outerText + "。「補正の評価」で内周・外周に分けて出せます。";
end
if options.waferRtRange ~= "none"
    rtNames = struct("all", "すべての Shot", "outer", "外周の Shot");
    messages(end + 1, 1) = sprintf(['%s は、Wafer RT（RT モデル %d 次。Shot 中心の座標で、X・Y を一緒に）を先に求めて引き、' ...
        '残りを補正の式で求めました。'], rtNames.(options.waferRtRange), options.waferRtOrder);
    if options.waferRtRange == "outer" && options.waferOrder > 0
        messages(end) = messages(end) + sprintf("内周の Shot は Wafer 成分（%d 次）で補正しました。", options.waferOrder);
    end
    if options.loss(1) ~= options.loss(2)
        messages(end) = messages(end) + "X・Y で損失関数が違うので、Wafer RT は最小二乗で求めました。";
    end
    if options.unit == "shot"
        messages(end) = messages(end) + "Shot ごとの k1・k2 は Wafer RT を除いた値です（補正量・残差は Wafer RT なしと同じ）。";
    end
end
if counts.rtDropped > 0
    messages(end + 1, 1) = sprintf(['⚠ Shot の数が少なく Wafer RT の項が決まらない Wafer が %d 個あり、その項は 0 に' ...
        'しました（書き出しの「補正値」のメモ）。次数を下げると決まります。'], counts.rtDropped);
end
if counts.rtNotConverged > 0
    messages(end + 1, 1) = sprintf('⚠ Wafer RT のロバスト回帰の繰り返しが収束しなかった Wafer が %d 個あります（最後の値を使いました）。', ...
        counts.rtNotConverged);
end
if options.unit == "shot" && options.waferOrder > 0 && options.waferRtRange ~= "all"
    if options.shotCommon == "input"
        messages(end + 1, 1) = sprintf(['Shot ごと：Wafer 成分（%d 次）を、入力した Shot 共通の k を引いた残りで求めて先に' ...
            '引き、残りを Shot ごとに求めました（Shot ごとの k1・k2 は Wafer 成分を除いた値。補正量・残差は Wafer 成分なしと' ...
            '同じ）。'], options.waferOrder);
    else
        messages(end + 1, 1) = sprintf(['Shot ごと：Wafer 成分（%d 次）を先に、Wafer 内で共通の k と一緒に求めて引き、残りを' ...
            ' Shot ごとに求めました（Shot ごとの k1・k2 は Wafer 成分を除いた値。補正量・残差は Wafer 成分なしと同じ）。'], ...
            options.waferOrder);
    end
end
if options.unit == "shot" && options.shotCommon ~= "none"
    sourceText = ternaryText(options.shotCommon == "fit", "Wafer 内の Shot で共通に求めた k", "入力した k");
    eachText = "使う項";
    if options.shotEachOrder > 0
        eachText = sprintf("%d次までの項", options.shotEachOrder);
    end
    messages(end + 1, 1) = "Shot ごと：Shot 共通補正（" + sourceText + "）を先に引き、残りを Shot ごとに" + eachText + ...
        "で求めました。Shot ごとの k は、Shot 共通の k を足した値です（残りの分は書き出しの「補正値」の「Shot 毎」）。";
    if options.shotEachOrder == 0 && all(options.regularization == "none" | options.lambda == 0)
        messages(end) = messages(end) + "Shot ごとに使う項をすべて求め、正則化もかけないので、補正量・残差は Shot 共通を" + ...
            "引かないときと同じです（点が足りず項を減らした Shot を除く）。違いを見るときは「Shot ごとの次数」を下げるか、" + ...
            "正則化をかけてください。";
    end
    if counts.commonMissing > 0
        messages(end + 1, 1) = sprintf(['⚠ Shot 共通の k を求められなかった Wafer が %d 個（dx・dy を別に数える）あり、' ...
            'そこは Shot 共通を引かずに Shot ごとの k だけで補正しました。'], counts.commonMissing);
    end
end
if options.unit == "scan"
    noDirection = nnz(~ismember(everything.direction, [1, 2]) & isfinite(everything.shotNo));
    if noDirection > 0
        messages(end + 1, 1) = sprintf('⚠ Scan 方向の分からない点 %d 点は使っていません（補正量・残差は空欄）。', noDirection);
    end
end
groupNames = struct("common", "Wafer", "scan", "k の組（Scan 方向）", "row", "k の組（行の偶奇）", "shot", "Shot");
groupName = groupNames.(options.unit);
if zoneSplit && options.unit == "common"
    groupName = "k の組（内周・外周）";
end
fitName = "Wafer";
if options.unit == "shot"
    fitName = "Shot";
end
if any(counts.skipped > 0)
    messages(end + 1, 1) = sprintf(['⚠ 点が足りない（または点の配置で項が決まらない）ため補正しなかった %s：dx %d / %d・' ...
        'dy %d / %d（補正量・残差は空欄）。'], groupName, counts.skipped(1), counts.groups(1), counts.skipped(2), ...
        counts.groups(2));
    messages(end) = messages(end) + "決まらない項：" + strjoin(counts.undetermined, "・") + "。";
    if options.shortage == "skip"
        messages(end) = messages(end) + "「点が足りない Shot」を「全体の項を減らす」か「その Shot（組）だけ項を減らす」に" + ...
            "すると、決められる項で補正します。";
    elseif all(options.regularization == "none" | options.lambda == 0)
        messages(end) = messages(end) + "「VIF で選ぶ」でその項を外すか、その次数の項に正則化（L2・L1）をかけてください" + ...
            "（正則化をかけた次数の項は、点が少なくても決まります）。";
    else
        messages(end) = messages(end) + "1次の項（k1〜k6）を決めるには、1つの k の組に同じ直線の上に無い3点以上が要ります。";
    end
end
if any(counts.reducedGroups > 0)
    numbers = sort(str2double(extractAfter(counts.reducedTerms, 1)));
    messages(end + 1, 1) = sprintf(['点が足りない %s（dx %d・dy %d）は、その点の配置で決められる項だけで補正しました' ...
        '（外した項：%s。どの組で外したかは「書き出し」の「Shot ごとの k」のメモ）。'], groupName, counts.reducedGroups(1), ...
        counts.reducedGroups(2), strjoin("k" + string(numbers), "・"));
end
if ~isempty(counts.constant)
    messages(end + 1, 1) = "⚠ 点の配置では値が変わらない（定数と同じになる）項：" + strjoin(counts.constant, "・") + ...
        "。正則化で 0 にしました（VIF が ∞ の項。「VIF で選ぶ」で外せます）。";
end
if counts.noRobust > 0
    messages(end + 1, 1) = sprintf(['点の数が項の数以下の %s が %d 個あり、そこではロバスト回帰の重みを使わずに' ...
        '求めました（残差がほぼ 0 になり、外れ値を見分けられないため）。'], fitName, counts.noRobust);
end
if counts.notConverged > 0
    messages(end + 1, 1) = sprintf('⚠ ロバスト回帰の繰り返しが収束しなかった組が %d 個あります（最後の値を使いました）。', ...
        counts.notConverged);
end
if counts.waferDropped > 0
    messages(end + 1, 1) = sprintf(['Shot の数が少なく Wafer 成分の項が決まらない Wafer が %d 個あり、その項は 0 に' ...
        'しました（係数の表の「メモ」）。'], counts.waferDropped);
end
for z = 1:numel(vifInfos)
    info = vifInfos{z};
    rangeText = "";
    if zoneSplit
        rangeText = zoneNames(z) + "の式の";
    end
    messages(end + 1, 1) = sprintf(['%sVIF は Shot 内の座標（dx %d 点・dy %d 点、位置 %d・%d か所）で求めました。' ...
        '「VIF で選ぶ」（しきい値 %.4g）で外す項：%s。'], rangeText, info.points(1), info.points(2), ...
        info.positions(1), info.positions(2), options.vifThreshold, suggestedText(info.suggestedExcluded)); %#ok<AGROW>
end
end

function text = suggestedText(numbers)
if isempty(numbers)
    text = "なし";
else
    text = strjoin("k" + string(numbers), "・");
end
end
