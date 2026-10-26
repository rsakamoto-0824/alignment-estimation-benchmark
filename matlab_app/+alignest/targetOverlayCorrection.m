function correction = targetOverlayCorrection(unit, training, method, settings, targetTable)
%TARGETOVERLAYCORRECTION 未知の座標を推定した後に、重ね合わせ（Overlay）補正値を求める。
%   correction = alignest.targetOverlayCorrection(unit, training, method, settings, targetTable)
%   補正に使う点（X・Y 別）：
%   - 元の実測値：学習に使った Mark の計測値（training は alignest.predictTargets と同じ）
%   - 推定値     ：学習しなかった Shot（Mark）の有効な Mark の推定値（学習パターンのとき。alignest.estimateWafer）
%   - 未知の座標の推定値：targetTable（alignest.predictTargets の result.table）。Wafer の外の点は除く
%   補正モデルは「2. 評価の設定」の Overlay 補正（alignest.overlayChoice：Wafer 成分 + Shot 共通成分 + Shot ごとの
%   成分。設計行列は alignest.overlayDesign）。X・Y 別に最小二乗で当てはめ、係数（補正値）・点ごとの補正量・
%   補正後の残差（値 − 補正量）を返す。
%   未知の座標の点の Shot：点を含む Shot（targetTable.shotIndex）。Shot 内の座標は点 − その Shot の中心。どの Shot にも
%   入らない点は、点そのものを Shot 中心とする1点だけの Shot として扱う（Shot ごとの成分はその点に合う）。
%   係数：成分どうしで重なる項（例：Wafer 成分の定数と Shot 共通成分の k1）や、点が少なくて決まらない項は、
%   前の項（Wafer → Shot 共通 → Shot ごと、各成分の中は式の順）に含めて 0 とする（note に書く）。補正量は
%   重なりがあっても変わらない。係数は mm の座標に直した値（単位 nm/mm^べき。1次は nm/mm = ppm）。
%   correction.coefficients：表（axis・component・componentLabel・shotNo・term・value・unit・note）
%   correction.points：表（source・name・shotNo・x・y・valueX・valueY・correctionX・correctionY・residualX・residualY）
%   correction.summary：表（axis・source・n・valueMean3Sigma・residualMean3Sigma）。|平均| + 3σ [nm]
%   correction.description：補正モデルの説明、correction.messages：注意
arguments
    unit struct
    training
    method struct
    settings struct
    targetTable table
end
RELATIVE_TOLERANCE = 1e-9;   % 前の項で表せる割合がこれより大きい列（ほぼ一次従属な項）は 0 にする
SOURCE_LABELS = ["実測値（学習点）", "推定値（学習しなかった Mark）", "推定値（未知の座標）"];
COMPONENT_NAMES = ["wafer", "shotCommon", "perShot"];
COMPONENT_LABELS = ["Wafer 成分", "Shot 共通成分", "Shot ごとの成分"];
AXIS_NAMES = ["X", "Y"];
choice = alignest.overlayChoice(settings);
if ~choice.enabled
    error('alignest:overlayModel', ['補正モデルがありません。「2. 評価の設定」の Overlay 補正で、Wafer 成分・Shot 共通成分・' ...
        'Shot ごとの成分のどれかを選んでください（%s）。'], choice.description);
end
marks = unit.marks;
shots = unit.shots;
nMarks = numel(marks.x);

% 元の実測値（学習点）と、学習しなかった Mark の推定値
out = alignest.estimateWafer(unit, training, method, settings);
values = nan(nMarks, 2);
source = zeros(nMarks, 1);
for k = 1:2
    train = out.trainIndex.(AXIS_NAMES(k));
    test = out.testIndex.(AXIS_NAMES(k));
    values(train, k) = marks.("meas" + AXIS_NAMES(k))(train);
    values(test, k) = out.estimate.(AXIS_NAMES(k));
    source(test) = 2;
    source(train) = 1;
end

% 未知の座標の推定値（Wafer の外の点は推定していないので除く）
targets = targetTable;
if any(string(targets.Properties.VariableNames) == "outsideWafer")
    targets = targets(~targets.outsideWafer, :);
end
nTargets = height(targets);
located = targets.shotIndex > 0;
centerX = targets.x;
centerY = targets.y;
centerX(located) = shots.Xmm(targets.shotIndex(located));
centerY(located) = shots.Ymm(targets.shotIndex(located));
targetShot = targets.shotIndex;
targetShot(~located) = numel(shots.Xmm) + (1:nnz(~located));   % どの Shot にも入らない点は1点だけの Shot

points = struct("Xmm", [marks.Xmm(:); centerX], "Ymm", [marks.Ymm(:); centerY], ...
    "markXmm", [marks.markXmm(:); targets.x - centerX], "markYmm", [marks.markYmm(:); targets.y - centerY], ...
    "shotIndex", [marks.shotIndex(:); targetShot]);
values = [values; targets.estimateX, targets.estimateY];
source = [source; 3 * ones(nTargets, 1)];
used = source > 0;
shotNo = [shots.shotNo(max(marks.shotIndex(:), 1)); nan(nTargets, 1)];
shotNo([marks.shotIndex(:) < 1; false(nTargets, 1)]) = NaN;
shotNo(nMarks + find(located)) = shots.shotNo(targets.shotIndex(located));
names = [repmat("", nMarks, 1); targets.name];
xy = [marks.x(:), marks.y(:); targets.x, targets.y];

corrections = nan(size(values));
coefficientParts = cell(2, 1);
dropped = zeros(1, 2);
for k = 1:2
    index = find(used & isfinite(values(:, k)));
    [design, terms] = alignest.overlayDesign(points, choice, settings.data.waferRadiusMm, k, index);
    keep = orderedIndependent(design, RELATIVE_TOLERANCE);
    coefficients = zeros(size(design, 2), 1);
    coefficients(keep) = design(:, keep) \ values(index, k);
    corrections(index, k) = design * coefficients;
    dropped(k) = nnz(~keep);
    % 係数を mm の座標に直す（座標を割った値のべきで割る）
    power = terms.xPower + terms.yPower;
    physical = coefficients ./ terms.scaleMm .^ power;
    [~, componentPosition] = ismember(terms.component, COMPONENT_NAMES);
    termShotNo = nan(height(terms), 1);
    perShot = terms.component == "perShot";
    termShotNo(perShot) = shotNumberOf(terms.shot(perShot), shots);
    note = strings(height(terms), 1);
    note(~keep) = "前の項と重なる（または点が少なく決まらない）ため 0（補正量は前の項に含まれる）";
    coefficientParts{k} = table(repmat(AXIS_NAMES(k), height(terms), 1), terms.component, ...
        COMPONENT_LABELS(componentPosition).', termShotNo, terms.name, physical, unitText(power), note, ...
        'VariableNames', ["axis", "component", "componentLabel", "shotNo", "term", "value", "unit", "note"]);
end
correction.coefficients = vertcat(coefficientParts{:});
residuals = values - corrections;
rows = find(used);
sourceLabel = SOURCE_LABELS(source(rows)).';
correction.points = table(sourceLabel, names(rows), shotNo(rows), xy(rows, 1), xy(rows, 2), values(rows, 1), ...
    values(rows, 2), corrections(rows, 1), corrections(rows, 2), residuals(rows, 1), residuals(rows, 2), ...
    'VariableNames', ["source", "name", "shotNo", "x", "y", "valueX", "valueY", "correctionX", "correctionY", ...
    "residualX", "residualY"]);
correction.summary = summarize(values, residuals, source, SOURCE_LABELS, AXIS_NAMES);
correction.description = choice.description;
messages = strings(0, 1);
counts = arrayfun(@(s) nnz(source == s), 1:3);
messages(end + 1, 1) = sprintf(['補正に使った点：元の実測値 %d 点・学習しなかった Mark の推定値 %d 点・未知の座標の推定値 %d 点' ...
    '（補正モデル：%s）。'], counts(1), counts(2), counts(3), choice.description);
if any(~located)
    messages(end + 1, 1) = sprintf(['どの Shot にも入らない未知の座標の点が %d 点あります（Shot 内の座標は 0、Shot ごとの成分は' ...
        'その点だけで決まります）。'], nnz(~located));
end
if any(dropped > 0)
    messages(end + 1, 1) = sprintf(['ほかの項と重なる・点が少なく決まらない係数が X %d 個・Y %d 個あり、0 にしました' ...
        '（補正量はほかの項に含まれます。係数の表の「メモ」）。'], dropped(1), dropped(2));
end
correction.messages = messages;
end

function keep = orderedIndependent(design, tolerance)
% 前の列で表せない列だけを残す（列の順に、それまでに残した列の正規直交基底へ射影した残りの大きさで判定）。
% 同じ射影を2回する（Gram–Schmidt の再直交化）ので、列が多くても数値的に安定
nColumns = size(design, 2);
keep = false(1, nColumns);
basis = zeros(size(design, 1), 0);
for column = 1:nColumns
    vector = design(:, column);
    scale = norm(vector);
    if scale == 0
        continue
    end
    for pass = 1:2
        vector = vector - basis * (basis.' * vector);
    end
    remainder = norm(vector);
    if remainder > sqrt(tolerance) * scale
        keep(column) = true;
        basis(:, end + 1) = vector / remainder; %#ok<AGROW>
    end
end
end

function numbers = shotNumberOf(shotIndex, shots)
% Shot ごとの成分の Shot 番号（どの Shot にも入らない点の Shot は NaN）
numbers = nan(size(shotIndex));
inside = shotIndex >= 1 & shotIndex <= numel(shots.shotNo);
numbers(inside) = shots.shotNo(shotIndex(inside));
end

function text = unitText(power)
text = repmat("nm/mm^" , numel(power), 1) + string(power);
text(power == 0) = "nm";
text(power == 1) = "nm/mm（ppm）";
end

function summary = summarize(values, residuals, source, labels, axisNames)
% 種類ごと・全体の点数と、補正前の値・補正後の残差の |平均| + 3σ
rows = cell(0, 1);
for k = 1:2
    for s = 0:numel(labels)
        if s == 0
            select = source > 0;
            name = "全体";
        else
            select = source == s;
            name = labels(s);
        end
        select = select & isfinite(values(:, k));
        rows{end + 1, 1} = table(axisNames(k), name, nnz(select), meanPlus3Sigma(values(select, k)), ...
            meanPlus3Sigma(residuals(select, k)), 'VariableNames', ["axis", "source", "n", "valueMean3Sigma", ...
            "residualMean3Sigma"]); %#ok<AGROW>
    end
end
summary = vertcat(rows{:});
end

function value = meanPlus3Sigma(values)
% Overlay の代表値 |平均| + 3σ（σ は不偏標準偏差）。点が2点未満なら NaN（alignest.overlayCorrection と同じ）
values = values(isfinite(values));
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end
