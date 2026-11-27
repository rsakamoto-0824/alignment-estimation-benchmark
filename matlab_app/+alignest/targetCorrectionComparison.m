function comparison = targetCorrectionComparison(unit, plan, method, settings, targetsPlan, targetsAll)
%TARGETCORRECTIONCOMPARISON 未知の座標の推定値を足して高次の式で補正すると、重ね合わせがよくなるかを、計測値のある Mark で比べる
%   （「5. 未知の座標の推定」の「補正の比較」）。
%   comparison = alignest.targetCorrectionComparison(unit, plan, method, settings, targetsPlan, targetsAll)
%   plan：評価の学習パターン（一部計測。results.plans の1つ）。全 Mark で推定したときは [] を渡す（一部計測の行は出さない）。
%   targetsPlan・targetsAll：学習パターン・全 Mark で推定した未知の座標の推定値（alignest.predictTargets の result.table）。
%   比べる 4 つの補正（どれも、補正量をその Wafer の計測値のある Mark に当てた「計測値 − 補正量」の |平均|+3σ で比べる）：
%   1. 全計測｜基準の補正：全 Mark の計測値で「2. 面内推定の設定」の Overlay 補正（基準の条件）を求める
%   2. 一部計測＋面内推定｜基準の補正：学習した Mark は計測値、学習しなかった Mark は推定値で、基準の条件の補正を求める
%   3. 全計測＋未知の座標｜このタブの補正：全 Mark の計測値と未知の座標の推定値で、「5.」の補正のモデル（高次の式）を求める
%   4. 一部計測＋面内推定＋未知の座標｜このタブの補正：2. の値と未知の座標の推定値で、「5.」の補正のモデルを求める
%   補正の名前には番号（①〜④）を付ける（全 Mark で推定したときは ① と ③ だけ）。
%   comparison.table：行 = 補正 × 軸。scenario・measurement・model・axis・n（比べた Mark の数）・before（計測値の |平均|+3σ）・
%   residual（補正後の |平均|+3σ）・targets（使った未知の座標の点の数）。
%   comparison.maps：補正ごとの構造体（scenario・residual（Mark の数 × 2）・description）。comparison.baseline・model：
%   基準の補正・このタブの補正の説明。
arguments
    unit struct
    plan
    method struct
    settings struct
    targetsPlan table
    targetsAll table
end
AXIS_NAMES = ["X", "Y"];
baseline = alignest.overlayChoice(settings);
if ~baseline.enabled
    error('alignest:overlayModel', ['基準の補正がありません。「2. 面内推定の設定」の Overlay 補正で、Wafer 成分・Shot 共通成分・' ...
        'Shot ごとの成分のどれかを選んでください。']);
end
model = alignest.targetCorrectionChoice(settings);
allShots = 1:numel(unit.shots.shotNo);
noTargets = targetsAll([], :);
scenarios = struct("name", {"① 全計測｜基準の補正", "③ 全計測＋未知の座標｜このタブの補正"}, ...
    "measurement", {"全計測", "全計測＋未知の座標"}, "model", {"基準（2. の条件）", "このタブの補正"}, ...
    "training", {allShots, allShots}, "targets", {noTargets, targetsAll}, "choice", {baseline, model});
if ~isempty(plan)
    scenarios = [scenarios(1), struct("name", "② 一部計測＋面内推定｜基準の補正", "measurement", "一部計測＋面内推定", ...
        "model", "基準（2. の条件）", "training", plan, "targets", noTargets, "choice", baseline), scenarios(2), ...
        struct("name", "④ 一部計測＋面内推定＋未知の座標｜このタブの補正", "measurement", "一部計測＋面内推定＋未知の座標", ...
        "model", "このタブの補正", "training", plan, "targets", targetsPlan, "choice", model)];
end
marks = unit.marks;
measured = [marks.measX(:), marks.measY(:)];
measured(~[marks.validX(:), marks.validY(:)]) = NaN;   % 有効な計測値だけで比べる
rows = cell(0, 1);
maps = struct("scenario", {}, "residual", {}, "description", {});
for k = 1:numel(scenarios)
    scenario = scenarios(k);
    correction = alignest.targetOverlayCorrection(unit, scenario.training, method, settings, scenario.targets, ...
        scenario.choice);
    residual = measured - correction.markCorrection;
    targetCount = height(scenario.targets);
    if targetCount > 0 && any(string(scenario.targets.Properties.VariableNames) == "outsideWafer")
        targetCount = nnz(~scenario.targets.outsideWafer);
    end
    for a = 1:2
        compared = isfinite(residual(:, a));
        rows{end + 1, 1} = table(string(scenario.name), string(scenario.measurement), string(scenario.model), ...
            AXIS_NAMES(a), nnz(compared), meanPlus3Sigma(measured(compared, a)), meanPlus3Sigma(residual(compared, a)), ...
            targetCount, 'VariableNames', ["scenario", "measurement", "model", "axis", "n", "before", "residual", ...
            "targets"]); %#ok<AGROW>
    end
    maps(end + 1) = struct("scenario", string(scenario.name), "residual", residual, ...
        "description", string(correction.description)); %#ok<AGROW>
end
comparison.table = vertcat(rows{:});
comparison.maps = maps;
comparison.baseline = baseline.description;
comparison.model = model.description;
end

function value = meanPlus3Sigma(values)
% |平均| + 3σ（σ は不偏標準偏差）。点が2点未満なら NaN
values = values(isfinite(values));
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end
