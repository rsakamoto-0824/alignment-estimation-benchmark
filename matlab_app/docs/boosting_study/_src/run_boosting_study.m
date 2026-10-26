function rows = run_boosting_study(dataFolder, outputFile, options)
%RUN_BOOSTING_STUDY GPR・GAM にブースティング（残差の当てはめを足していく方法）を加えたときの効果を、模擬データで調べる。
%   rows = run_boosting_study(dataFolder, outputFile)
%   dataFolder：make_boosting_data.py が書き出した boosting_standard.csv・boosting_high.csv のあるフォルダ。
%   outputFile：結果（Wafer × パターン × 手法 × 変種 × 回数 の表）を書き出す CSV。
%   matlab_app をパスに入れて実行する。手法の当てはめはアプリ（alignest.estimateWafer）と同じモデル関数・同じ設定
%   （説明変数 X,Y,半径、質的変数は Scan 方向と Mark 番号）で、X・Y を別々に当てはめる。最初の当てはめが
%   estimateWafer と同じ推定値になることを、Wafer・学習パターンごとに確かめる（結果の checkDiff）。
%
%   手法：GPR（matern52、質的変数なし）、GPR（matern52、加法カーネル）、GAM（スプライン、質的変数あり）
%   変種（F_0 = 手法の当てはめ、y = 学習点の計測値、m = 1, 2, … が回数）
%     base           ：F_0 だけ（ブースティングなし）
%     L2refit        ：r = y − F_{m−1}（学習点）に同じ手法を当てはめ直し（ハイパーパラメータ・λ も推定し直す）、
%                      F_m = F_{m−1} + ν·h_m
%     L2fixed        ：同じ。ただし h_m は F_0 のハイパーパラメータ・λ のまま（古典的な L2 ブースティング。
%                      線形の平滑化 S なら y − F_m = (I − νS)^m (I − S) y で、平滑化が弱まる方向に進む）
%     stack:<手法>   ：F_0 の残差に別の手法を1回当てはめて足す（ν = 1）。GPR には GAM、GAM には GPR（質的変数なし）
%   評価：学習しなかった Shot の Mark で、真値（ノイズを足す前）と計測値に対する RMSE（X・Y 合計）。
arguments
    dataFolder (1, 1) string
    outputFile (1, 1) string
    options.shotCounts double = [10, 20, 30, 40]
    options.samplings string = ["ioptimal", "random"]
    options.noises string = ["standard", "high"]
    options.refitRounds (1, 1) double = 3
    options.fixedRounds (1, 1) double = 5
    options.shrinkages double = [0.5, 1]
    options.nWafers (1, 1) double = Inf
end
BASES = ["GPR_none", "GPR_additive", "GAM"];
STACK_PARTNER = struct("GPR_none", "GAM", "GPR_additive", "GAM", "GAM", "GPR_none");
APP_IDS = struct("GPR_none", "GPR_matern52_XYR_none", "GPR_additive", "GPR_matern52_XYR_additive", "GAM", "GAM_XYR");
settings = alignest.defaultSettings();
config = alignest.recommendedMethods('none');
config.gpr.enabled = true;
config.gpr.kernels = "matern52";
config.gpr.factorModes = ["none", "additive"];
config.gam.enabled = true;
settings.methods = config;
appMethods = alignest.buildMethodList(config);
appIds = string({appMethods.id});
rows = cell(0, 1);
timer = tic;
for noise = options.noises
    raw = alignest.readMeasurementFile(fullfile(dataFolder, "boosting_" + noise + ".csv"));
    data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
    units = data.units(1:min(numel(data.units), options.nWafers));
    plans = containers.Map();
    for u = 1:numel(units)
        unit = units(u);
        truth = truthOf(unit);
        for sampling = options.samplings
            for nShots = options.shotCounts
                key = sampling + "|" + nShots;   % 模擬データの Wafer はすべて同じ配置なので、学習パターンも同じ
                if ~isKey(plans, key)
                    plans(key) = makePlan(unit, settings, sampling, nShots);
                end
                plan = plans(key);
                problem = makeProblem(unit, plan, settings);
                context = struct("noise", noise, "sampling", sampling, "nShots", nShots, "wafer", string(unit.label));
                for base = BASES
                    [first, seconds] = fitLearner(problem, base, problem.measured, []);
                    reference = alignest.estimateWafer(unit, plan, appMethods(appIds == APP_IDS.(base)), settings);
                    checkDiff = max(abs([first.test.X - reference.estimate.X; first.test.Y - reference.estimate.Y]));
                    rows{end + 1, 1} = record(context, base, "base", NaN, 0, first, problem, truth, seconds, checkDiff); %#ok<AGROW>
                    % L2refit：同じ手法を残差に当てはめ直す（ν = 1）
                    current = first;
                    for m = 1:options.refitRounds
                        [step, seconds] = fitLearner(problem, base, residualsOf(problem, current), []);
                        current = addStep(current, step, 1);
                        rows{end + 1, 1} = record(context, base, "L2refit", 1, m, current, problem, truth, seconds, NaN); %#ok<AGROW>
                    end
                    % L2fixed：最初の当てはめのハイパーパラメータ・λ のまま
                    for nu = options.shrinkages
                        current = first;
                        for m = 1:options.fixedRounds
                            [step, seconds] = fitLearner(problem, base, residualsOf(problem, current), first.params);
                            current = addStep(current, step, nu);
                            rows{end + 1, 1} = record(context, base, "L2fixed", nu, m, current, problem, truth, seconds, NaN); %#ok<AGROW>
                        end
                    end
                    partner = STACK_PARTNER.(base);
                    [step, seconds] = fitLearner(problem, partner, residualsOf(problem, first), []);
                    rows{end + 1, 1} = record(context, base, "stack:" + partner, 1, 1, addStep(first, step, 1), ...
                        problem, truth, seconds, NaN); %#ok<AGROW>
                end
            end
        end
        fprintf('%s %s：%d / %d 枚（%.0f 秒）\n', noise, unit.label, u, numel(units), toc(timer));
    end
end
rows = vertcat(rows{:});
writetable(rows, outputFile);
end

function plan = makePlan(unit, settings, sampling, nShots)
sampling_ = settings.sampling;
sampling_.method = sampling;
sampling_.nShots = nShots;
[sampling_.nShotsStart, sampling_.nShotsEnd, sampling_.nShotsStep] = deal(nShots, nShots, 1);
sampling_.randomRepeats = 1;
specs = alignest.buildPlanSpecs(sampling_);
plan = alignest.planTrainingShots(unit, specs(1), sampling_, settings.data.waferRadiusMm);
end

function problem = makeProblem(unit, plan, settings)
% 1つの Wafer・学習パターンの当てはめに要るもの（軸ごとの学習点・評価点、説明変数、質的変数の水準）
RADIUS_MM = settings.data.waferRadiusMm;
marks = unit.marks;
inTrain = alignest.trainingMarks(unit, plan);
features = alignest.basis.distanceFeatures(marks.x, marks.y, "XYR", RADIUS_MM);
points = struct("x", marks.x / RADIUS_MM, "y", marks.y / RADIUS_MM, "r", marks.r / RADIUS_MM);
direction = nan(numel(marks.x), 1);
if unit.hasDirection
    direction = marks.direction;
end
problem = struct("features", features, "points", points, "groups", alignest.basis.featureGroups("XYR"), ...
    "options", settings.methods.options);
for axisName = ["X", "Y"]
    valid = marks.("valid" + axisName);
    problem.train.(axisName) = find(inTrain & valid);
    problem.test.(axisName) = find(~inTrain & valid);
    problem.measured.(axisName) = marks.("meas" + axisName);
end
problem.direction = direction;
problem.markNo = marks.markNo;
end

function [fit, seconds] = fitLearner(problem, learner, values, params)
% 手法を当てはめ、評価点と学習点の推定値を返す（params が空ならハイパーパラメータ・λ を推定、空でなければその値のまま）
timer = tic;
fit = struct("test", struct(), "train", struct(), "params", struct());
for axisName = ["X", "Y"]
    train = problem.train.(axisName);
    test = problem.test.(axisName);
    evaluate = [test; train];                  % 評価点と学習点（学習点の推定値 = 当てはめ値）
    y = values.(axisName)(train);
    fixed = [];
    if ~isempty(params)
        fixed = params.(axisName);
    end
    factors = struct("scanTrain", problem.direction(train), "scanTest", problem.direction(evaluate), ...
        "markTrain", problem.markNo(train), "markTest", problem.markNo(evaluate));
    switch learner
        case {"GPR_none", "GPR_additive"}
            mode = extractAfter(learner, "GPR_");
            result = alignest.models.gprFitPredict(problem.features(train, :), problem.features(evaluate, :), ...
                problem.groups, y, "matern52", mode, factors, maxIterations=problem.options.gprMaxIterations, ...
                fixedLogParams=fixed);
            fit.params.(axisName) = result.logParams;
        case "GAM"
            [codesTrain, codesTest] = factorCodes(factors);
            model = alignest.models.gamSetup(subsetPoints(problem.points, train), ...
                subsetPoints(problem.points, evaluate), "XYR", codesTrain, codesTest, ...
                struct("axis", problem.options.gamBasisAxis, "radius", problem.options.gamBasisRadius));
            result = alignest.models.gamFitPredict(model, y, fixedLog10Lambda=fixed);
            fit.params.(axisName) = result.log10Lambda;
    end
    fit.test.(axisName) = result.prediction(1:numel(test));
    fit.train.(axisName) = result.prediction(numel(test) + 1:end);
end
seconds = toc(timer);
end

function [train, test] = factorCodes(factors)
% GAM の質的変数（Scan 方向・Mark 番号）の効果コード。学習点で一次従属な列を除く（estimateWafer と同じ）
blocksTrain = {ones(numel(factors.scanTrain), 1)};
blocksTest = {ones(numel(factors.scanTest), 1)};
for name = ["scan", "mark"]
    levelsTrain = factors.(name + "Train");
    if any(isnan(levelsTrain))
        continue
    end
    [codesTrain, codesTest] = alignest.basis.effectCoding(levelsTrain, factors.(name + "Test"));
    blocksTrain{end + 1} = codesTrain; %#ok<AGROW>
    blocksTest{end + 1} = codesTest; %#ok<AGROW>
end
[train, test] = alignest.basis.independentColumns([blocksTrain{:}], [blocksTest{:}]);
train = train(:, 2:end);
test = test(:, 2:end);
end

function subset = subsetPoints(points, index)
subset = structfun(@(values) values(index), points, 'UniformOutput', false);
end

function values = residualsOf(problem, current)
% 学習点の残差（計測値 − ここまでの当てはめ値）
values = problem.measured;
for axisName = ["X", "Y"]
    train = problem.train.(axisName);
    values.(axisName)(train) = problem.measured.(axisName)(train) - current.train.(axisName);
end
end

function current = addStep(current, step, nu)
for axisName = ["X", "Y"]
    current.test.(axisName) = current.test.(axisName) + nu * step.test.(axisName);
    current.train.(axisName) = current.train.(axisName) + nu * step.train.(axisName);
end
end

function truth = truthOf(unit)
% 真値（模擬データの「その他の列」truthX・truthY）
names = string(unit.attributeNames);
truth.X = str2double(unit.marks.attributes(:, names == "truthX"));
truth.Y = str2double(unit.marks.attributes(:, names == "truthY"));
end

function row = record(context, base, variant, nu, round_, current, problem, truth, seconds, checkDiff)
[errorTruth, errorMeasured, residualTrain] = deal(zeros(0, 1));
for axisName = ["X", "Y"]
    test = problem.test.(axisName);
    train = problem.train.(axisName);
    errorTruth = [errorTruth; truth.(axisName)(test) - current.test.(axisName)]; %#ok<AGROW>
    errorMeasured = [errorMeasured; problem.measured.(axisName)(test) - current.test.(axisName)]; %#ok<AGROW>
    residualTrain = [residualTrain; problem.measured.(axisName)(train) - current.train.(axisName)]; %#ok<AGROW>
end
row = table(context.noise, context.sampling, context.nShots, context.wafer, base, variant, nu, round_, ...
    sqrt(mean(errorTruth .^ 2)), sqrt(mean(errorMeasured .^ 2)), sqrt(mean(residualTrain .^ 2)), seconds, checkDiff, ...
    'VariableNames', ["noise", "sampling", "nShots", "wafer", "method", "variant", "nu", "round", "rmseTruth", ...
    "rmseMeasured", "rmseTrain", "seconds", "checkDiff"]);
end
