% 解説資料（加法カーネルと交互作用）の計算例：模擬データ（sample_alignment.csv）で GPR の質的変数の扱いを比べ、加法カーネルの中身を数値で出す
close all force;
% 使い方：MATLAB で matlab_app を開き、run('docs/kernel_guide/_src/kernel_numbers.m')。kernel_numbers.json を書く
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(fileparts(here)));   % _src → kernel_guide → docs → matlab_app
outFile = fullfile(here, 'kernel_numbers.json');
cd(root); rehash;
raw = alignest.readMeasurementFile(fullfile(root, 'sample_data', 'sample_alignment.csv'));
data = alignest.prepareData(raw, alignest.guessColumnMapping(raw.Properties.VariableNames));
settings = alignest.defaultSettings();
settings.methods = alignest.recommendedMethods("none");
settings.methods.gpr.enabled = true;
settings.methods.gpr.kernels = "matern52";
settings.methods.gpr.factorModes = alignest.models.gprFactorModes();
settings.methods.gpr.factorModes = settings.methods.gpr.factorModes(settings.methods.gpr.factorModes ~= "backfit");
settings.sampling.nShots = [15, 30]; settings.sampling.nShotsStart = 15; settings.sampling.nShotsEnd = 30; settings.sampling.nShotsStep = 15;
settings.overlay.waferOrder = 0; settings.overlay.shotCommon = "none";
tic; results = alignest.runEvaluation(data, settings); seconds = toc;
summary = alignest.summarizeResults(results, "RMSE_XY", "mean");
out.compare = struct("methods", {cellstr(string({results.methods.factorMode}))}, "labels", {cellstr(summary.methodLabels)}, ...
    "groups", {cellstr(summary.groups)}, "rmse", summary.values, "seconds", seconds);
% Wafer 1・I 最適 15 Shot・X 成分で、加法カーネル＋交互作用の中身
unit = data.units(1); marks = unit.marks;
planIndex = find([results.plans.unitIndex] == 1 & string({results.plans.group}) == "15 Shot", 1);
plan = results.plans(planIndex);
inTrain = ismember(marks.shotIndex, plan.shotIndex);
features = alignest.basis.distanceFeatures(marks.x, marks.y, 'XYR', 150);
groups = alignest.basis.featureGroups("XYR");
out.unit = unit.label; out.plan = plan.label; out.nShots = plan.nShots;
for axisName = ["X", "Y"]
    valid = marks.("valid" + axisName);
    train = find(inTrain & valid); test = find(~inTrain & valid);
    y = marks.("meas" + axisName)(train);
    factors = struct("scanTrain", marks.direction(train), "scanTest", marks.direction(test), ...
        "markTrain", marks.markNo(train), "markTest", marks.markNo(test));
    for mode = ["additive", "additive_int", "none", "basis"]
        [gp, basisTrain, basisTest] = alignest.models.gprModeSetup(features(train, :), features(test, :), groups, "matern52", mode, factors, 300);
        fit = alignest.models.gprFit(gp, y, basisTrain);
        p = exp(fit.logParams(:)).';
        item = struct("mode", mode, "lengthScale", p(1), "sigmaF", p(2), "sigmaN", p(end), ...
            "tauNames", {cellstr(string({gp.categorical.name}))}, "tau", p(3:end - 1), "beta", fit.beta(:).', ...
            "nll", fit.nll, "nTrain", numel(train), "stdY", std(y, 1));
        prediction = alignest.models.gprPredict(gp, fit, basisTest);
        item.rmse = sqrt(mean((prediction - marks.("meas" + axisName)(test)) .^ 2));
        if mode == "additive_int"
            % 予測の内訳：β0 + 空間 + 質的変数の各項（評価点ごと）。1 点目を例に出す
            crossFull = alignest.models.gprKernel(gp, fit.logParams, "cross");
            categoricalParts = zeros(numel(test), gp.nCategorical);
            for k = 1:gp.nCategorical
                categoricalParts(:, k) = p(2 + k) ^ 2 * gp.categorical(k).crossSame * fit.alphaVector;
            end
            spatialPart = crossFull * fit.alphaVector - sum(categoricalParts, 2);
            pick = find(marks.markNo(test) == 3 & marks.direction(test) == 1, 1);
            item.example = struct("x", marks.x(test(pick)), "y", marks.y(test(pick)), "scan", marks.direction(test(pick)), ...
                "mark", marks.markNo(test(pick)), "beta0", fit.beta(1), "spatial", spatialPart(pick), ...
                "parts", categoricalParts(pick, :), "prediction", prediction(pick), "measured", marks.("meas" + axisName)(test(pick)));
            % 水準ごとの推定したずれ（変量効果の予測 = τ² × その水準の学習点の α の和）
            levels = struct();
            for k = 1:gp.nCategorical
                name = gp.categorical(k).name;
                if name == "scan", codes = marks.direction(train); elseif name == "mark", codes = marks.markNo(train); else, codes = 10 * marks.direction(train) + marks.markNo(train); end
                values = unique(codes).';
                effects = arrayfun(@(v) p(2 + k) ^ 2 * sum(fit.alphaVector(codes == v)), values);
                levels.(name) = struct("levels", values, "effects", effects);
            end
            item.levelEffects = levels;
            % 4 つの組の共分散の内訳（基準の点 A と、同じ Shot の別 Mark・隣の Shot の同じ Mark など）
            a = test(pick);
            shotA = marks.shotIndex(a);
            labels = ["同じ Shot・別の Mark（Scan 同じ）", "別の Shot・同じ Mark・Scan 違う", ...
                "別の Shot・同じ Mark・Scan 同じ", "別の Shot・別の Mark・Scan 違う"];
            others = setdiff(1:numel(marks.x), a).';
            sameScan = marks.direction(others) == marks.direction(a); sameMark = marks.markNo(others) == marks.markNo(a);
            sameShot = marks.shotIndex(others) == shotA;
            rules = {sameShot & ~sameMark, ~sameShot & sameMark & ~sameScan, ~sameShot & sameMark & sameScan, ...
                ~sameShot & ~sameMark & ~sameScan};
            pairs = struct("label", {}, "distanceMm", {}, "spatial", {}, "scan", {}, "mark", {}, "scanMark", {}, "total", {});
            for c = 1:4
                cand = others(rules{c});
                dc = hypot(marks.x(cand) - marks.x(a), marks.y(cand) - marks.y(a));
                [~, j] = min(dc);
                b = cand(j);
                r = norm(features(a, :) - features(b, :)) / p(1);
                rho = (1 + sqrt(5) * r + 5 / 3 * r ^ 2) * exp(-sqrt(5) * r);
                ss = marks.direction(b) == marks.direction(a); sm = marks.markNo(b) == marks.markNo(a);
                pairs(c) = struct("label", labels(c), "distanceMm", hypot(marks.x(b) - marks.x(a), marks.y(b) - marks.y(a)), ...
                    "spatial", p(2) ^ 2 * rho, "scan", ss * p(3) ^ 2, "mark", sm * p(4) ^ 2, "scanMark", ss * sm * p(5) ^ 2, "total", 0);
                pairs(c).total = pairs(c).spatial + pairs(c).scan + pairs(c).mark + pairs(c).scanMark;
            end
            item.pairs = pairs;
            item.self = p(2) ^ 2 + p(3) ^ 2 + p(4) ^ 2 + p(5) ^ 2;
        end
        out.(axisName + "_" + mode) = item;
    end
end
% アプリの推定（estimateWafer）と同じ超パラメータか（Excel の「超パラメータ」の名前も）
method = alignest.buildMethodList(settings.methods);
method = method(string({method.factorMode}) == "additive_int");
check = alignest.estimateWafer(unit, plan.shotIndex, method, settings);
out.appExtra = check.extra;
fid = fopen(outFile, 'w'); fwrite(fid, jsonencode(out, 'PrettyPrint', true), 'char'); fclose(fid);
disp(out.compare.rmse); disp(out.X_additive_int.tau); disp(check.extra);
