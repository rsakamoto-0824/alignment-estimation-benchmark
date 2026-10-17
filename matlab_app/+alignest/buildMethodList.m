function methods = buildMethodList(config)
%BUILDMETHODLIST 比べる手法の一覧（構造体配列）。並びは Python 版と同じ（説明変数の組ごとに GPR → TPS → Kriging → GAM、最後に XY・RT）。
%   id の書き方は Python 版と同じ：GPR_<カーネル>_<説明変数>_<質的変数の扱い>、TPS_<説明変数>、
%   OK_<バリオグラム>_<説明変数>（通常 Kriging）、UK_<バリオグラム>_<説明変数>（Universal Kriging）、
%   GAM_<説明変数>、XY<次数>、RT<次数>。
[modeNames, modeLabels] = alignest.models.gprFactorModes();
methods = struct("id", {}, "family", {}, "featureSet", {}, "variant", {}, "factorMode", {}, "label", {});
for featureSet = string(config.featureSets(:)).'
    featureLabel = featureSetLabel(featureSet);
    if config.gpr.enabled
        for kernel = string(config.gpr.kernels(:)).'
            for mode = string(config.gpr.factorModes(:)).'
                methods(end + 1) = item(sprintf("GPR_%s_%s_%s", kernel, featureSet, mode), "GPR", featureSet, kernel, mode, ...
                    sprintf("GPR %s｜%s｜%s", kernel, featureLabel, modeLabels(modeNames == mode))); %#ok<AGROW>
            end
        end
    end
    if config.tps.enabled
        methods(end + 1) = item("TPS_" + featureSet, "TPS", featureSet, "tps", "none", "TPS｜" + featureLabel); %#ok<AGROW>
    end
    kinds = [config.kriging.ordinary, config.kriging.universal];
    families = ["OK", "UK"];
    names = ["Kriging", "Universal Kriging"];
    for k = find(kinds)
        for variogram = string(config.kriging.variograms(:)).'
            methods(end + 1) = item(sprintf("%s_%s_%s", families(k), variogram, featureSet), families(k), featureSet, ...
                variogram, "none", sprintf("%s %s｜%s", names(k), variogram, featureLabel)); %#ok<AGROW>
        end
    end
    if config.gam.enabled
        methods(end + 1) = item("GAM_" + featureSet, "GAM", featureSet, "pspline", "factor", ...
            "GAM｜" + featureLabel + "（質的変数あり）"); %#ok<AGROW>
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
    case "XYRT"
        label = "X,Y,半径,T";
    otherwise
        error('alignest:featureSet', '説明変数の組は XY・XYR・XYRT のいずれかです: %s', featureSet);
end
end
