function methods = buildMethodList(config)
%BUILDMETHODLIST 手法一覧。説明変数の組ごとに GPR → TPS → RBF → Kriging → GAM、最後に XY・RT。
%   id の書き方は Python 版と同じ：GPR_<カーネル>_<説明変数>_<質的変数の扱い>、TPS_<説明変数>、
%   OK_<バリオグラム>_<説明変数>（通常 Kriging）、UK_<バリオグラム>_<説明変数>（Universal Kriging）、
%   GAM_<説明変数>、XY<次数>、RT<次数>。
%   RBF_gaussian_<説明変数> を追加。TPS・RBF・OK・UK の Backfitting は既存 id に _backfit を付ける。
%   GPR のカーネル matern・ardmatern は config.gpr.maternNu の ν ごとに matern_nu<ν>・ardmatern_nu<ν> にする。
%   GAM の形状関数にガウス過程回帰の項があれば、id に _gp-<項>（例：GAM_XYR_gp-xy-r）を付ける。
%   config.gam.shapes は項（xy・r）ごとに選んだ形状関数（spline・gp。1つ以上）で、その組み合わせをすべて並べる。
%   ガウス過程の項がある組は、config.gam.gpKernels のカーネルごとに並べる（matern は config.gam.gpMaternNu の ν ごと）。
%   matern52 は以前と同じ id、ほかのカーネルは id の最後に _<カーネル>（例：GAM_XYR_gp-xy_matern32）を付ける。
%   variant は "gp:<項>+<項>:<カーネル>"（例：gp:xy+r:matern52）。
[modeNames, modeLabels] = alignest.models.gprFactorModes();
config = alignest.completeMethodSettings(config);
methods = struct("id", {}, "family", {}, "featureSet", {}, "variant", {}, "factorMode", {}, "label", {});
for featureSet = string(config.featureSets(:)).'
    featureLabel = featureSetLabel(featureSet);
    if config.gpr.enabled
        for kernel = expandKernels(config.gpr.kernels, config.gpr.maternNu)
            for mode = string(config.gpr.factorModes(:)).'
                methods(end + 1) = item(sprintf("GPR_%s_%s_%s", kernel, featureSet, mode), "GPR", featureSet, kernel, mode, ...
                    sprintf("GPR %s｜%s｜%s", replace(kernel, "_nu", " ν="), featureLabel, ...
                    modeLabels(modeNames == mode))); %#ok<AGROW>
            end
        end
    end
    if config.tps.enabled
        for mode = spatialModes(config.tps.factorModes)
            methods(end + 1) = spatialItem("TPS_" + featureSet, "TPS", featureSet, "tps", mode, "TPS｜" + featureLabel); %#ok<AGROW>
        end
    end
    if config.rbf.enabled
        for mode = spatialModes(config.rbf.factorModes)
            methods(end + 1) = spatialItem("RBF_gaussian_" + featureSet, "RBF", featureSet, "gaussian", mode, ...
                "RBF Gaussian｜" + featureLabel); %#ok<AGROW>
        end
    end
    kinds = [config.kriging.ordinary, config.kriging.universal];
    families = ["OK", "UK"];
    names = ["Kriging", "Universal Kriging"];
    factorModes = {config.kriging.ordinaryFactorModes, config.kriging.universalFactorModes};
    for k = find(kinds)
        for variogram = string(config.kriging.variograms(:)).'
            for mode = spatialModes(factorModes{k})
                methods(end + 1) = spatialItem(sprintf("%s_%s_%s", families(k), variogram, featureSet), families(k), featureSet, ...
                    variogram, mode, sprintf("%s %s｜%s", names(k), variogram, featureLabel)); %#ok<AGROW>
            end
        end
    end
    if config.gam.enabled
        gpKernels = gamKernels(config.gam);
        for shapes = gamShapeCombinations(featureSet, config.gam.shapes)
            [idSuffix, variant, labelSuffix] = gamShapeNames(featureSet, shapes);
            if variant == "pspline"
                kernels = "";   % スプラインだけの組はカーネルを使わない
            else
                kernels = gpKernels;
            end
            for kernel = kernels
                id = "GAM_" + featureSet + idSuffix;
                label = "GAM｜" + featureLabel + "（質的変数あり）" + labelSuffix;
                kernelVariant = variant;
                if kernel ~= ""
                    kernelVariant = variant + ":" + kernel;
                    label = label + "（" + replace(kernel, "_nu", " ν=") + "）";
                    if kernel ~= "matern52"
                        id = id + "_" + kernel;
                    end
                end
                methods(end + 1) = item(id, "GAM", featureSet, kernelVariant, "factor", label); %#ok<AGROW>
            end
        end
    end
end
if config.polynomial.enabled
    order = config.polynomial.order;
    methods(end + 1) = item(sprintf("XY%d", order), "XY", "-", sprintf("order%d", order), "none", sprintf("XY%d次多項式", order));
end
if config.rt.enabled
    for order = config.rt.orders(:).'
        methods(end + 1) = item(sprintf("RT%d", order), "RT", "-", sprintf("order%d", order), "none", ...
            sprintf("RT モデル K=%d", order)); %#ok<AGROW>
    end
end
end

function kernels = expandKernels(names, maternNu)
% matern・ardmatern を ν ごとの名前に展開する（ν は %g の書き方。例：matern_nu1.2）
kernels = strings(1, 0);
for name = string(names(:)).'
    if any(name == ["matern", "ardmatern"])
        if isempty(maternNu)
            error('alignest:maternNu', 'カーネル %s を使うときは、Matérn の ν を1つ以上入れてください。', name);
        end
        for nu = maternNu(:).'
            alignest.models.maternNuCheck(nu);
            kernels(end + 1) = name + "_nu" + sprintf("%g", nu); %#ok<AGROW>
        end
    else
        kernels(end + 1) = name; %#ok<AGROW>
    end
end
kernels = unique(kernels, 'stable');
end

function kernels = gamKernels(gam)
% GAM のガウス過程の形状関数のカーネル（matern は ν ごとの名前に展開する）
names = unique(string(gam.gpKernels(:)).', 'stable');
choices = alignest.models.gamKernelChoices();
if isempty(names)
    error('alignest:gamKernel', 'GAM のガウス過程回帰のカーネルを1つ以上選んでください。');
end
unknown = names(~ismember(names, choices));
if ~isempty(unknown)
    error('alignest:gamKernel', 'GAM のガウス過程回帰のカーネルは %s のいずれかです: %s', strjoin(choices, "・"), ...
        strjoin(unknown, "・"));
end
kernels = expandKernels(names, gam.gpMaternNu);
end

function combinations = gamShapeCombinations(featureSet, shapes)
% 項ごとに選んだ形状関数の組み合わせ（構造体配列。各要素は項ごとに1つの形状関数）。スプラインだけの組を先に並べる
terms = alignest.models.gamTerms(featureSet);
choices = cell(1, numel(terms));
for k = 1:numel(terms)
    chosen = "spline";
    if isfield(shapes, terms(k))
        chosen = unique(string(shapes.(terms(k))), 'stable');
    end
    if isempty(chosen)
        error('alignest:gamShape', 'GAM の形状関数を、項（%s）ごとにスプラインかガウス過程回帰の少なくとも1つ選んでください。', ...
            terms(k));
    end
    choices{k} = [chosen(chosen == "spline"), chosen(chosen ~= "spline")];
end
counts = cellfun(@numel, choices);
combinations = struct();
combinations(prod(counts)).(terms(1)) = "";
for index = 1:prod(counts)
    picks = cell(1, numel(terms));
    [picks{:}] = ind2sub(flip(counts), index);
    picks = flip(cell2mat(picks));
    for k = 1:numel(terms)
        combinations(index).(terms(k)) = choices{k}(picks(k));
    end
end
end

function [idSuffix, variant, labelSuffix] = gamShapeNames(featureSet, shapes)
% 形状関数をガウス過程回帰にした項（この説明変数の組にある項だけ）を id・variant・表示名に入れる
[terms, termLabels] = alignest.models.gamTerms(featureSet);
gp = false(size(terms));
for k = 1:numel(terms)
    value = "spline";
    if isfield(shapes, terms(k))
        value = string(shapes.(terms(k)));
    end
    if ~any(value == ["spline", "gp"])
        error('alignest:gamShape', 'GAM の形状関数は spline（スプライン）か gp（ガウス過程回帰）です: %s = %s', terms(k), value);
    end
    gp(k) = value == "gp";
end
if ~any(gp)
    idSuffix = "";
    variant = "pspline";
    labelSuffix = "";
    return
end
idSuffix = "_gp-" + strjoin(terms(gp), "-");
variant = "gp:" + strjoin(terms(gp), "+");
labelSuffix = "｜ガウス過程：" + strjoin(termLabels(gp), "・");
end

function modes = spatialModes(value)
modes = unique(string(value(:)).', 'stable');
if isempty(modes) || any(~ismember(modes, ["none", "backfit"]))
    error('alignest:spatialFactorMode', '質的変数の扱いは none・backfit のいずれか、または両方を選んでください。');
end
end

function method = spatialItem(id, family, featureSet, variant, mode, label)
if mode == "backfit"
    id = string(id) + "_backfit";
    label = string(label) + "｜Backfitting";
end
method = item(id, family, featureSet, variant, mode, label);
end

function method = item(id, family, featureSet, variant, factorMode, label)
method = struct("id", string(id), "family", string(family), "featureSet", string(featureSet), ...
    "variant", string(variant), "factorMode", string(factorMode), "label", string(label));
end

function label = featureSetLabel(featureSet)
switch featureSet
    case "XY"
        label = "X,Y";
    case "XYR"
        label = "X,Y,半径";
    otherwise
        error('alignest:featureSet', '説明変数の組は XY・XYR のいずれかです: %s', featureSet);
end
end
