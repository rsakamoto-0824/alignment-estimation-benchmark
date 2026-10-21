function config = completeMethodSettings(config)
%COMPLETEMETHODSETTINGS 以前の設定構造体にも追加項目の初期値を補う。
defaults = alignest.recommendedMethods();
for group = ["gpr", "rbf", "tps", "kriging", "gam", "options"]
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
