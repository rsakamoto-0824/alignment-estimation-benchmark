function config = completeMethodSettings(config)
%COMPLETEMETHODSETTINGS 以前の設定構造体にも追加項目の初期値を補う。
%   使わなくなった説明変数の組 XYRT（方位角 T）は除く（残りが無ければ XYR にする）。
defaults = alignest.recommendedMethods();
featureSets = string(config.featureSets);
featureSets = featureSets(featureSets ~= "XYRT");
if isempty(featureSets)
    featureSets = "XYR";
end
config.featureSets = reshape(featureSets, 1, []);
for group = ["gpr", "rbf", "rbfe", "tps", "kriging", "gam", "zernike", "options"]
    if ~isfield(config, group)
        config.(group) = defaults.(group);
        continue
    end
    for name = string(fieldnames(defaults.(group))).'
        if ~isfield(config.(group), name)
            config.(group).(name) = defaults.(group).(name);
        end
    end
end
end
