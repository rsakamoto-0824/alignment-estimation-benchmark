function same = sameRunSettings(first, second)
%SAMERUNSETTINGS 2つの評価の設定が、推定の結果について同じか（表示の設定 display・Shot 高次補正の設定 highOrder は
%   比べない）。一時中断した評価を続きから再開できるかを確かめるときに使う（Scan 方向の色・向きや、「7. Shot高次補正」の
%   設定を変えても再開できるように）。
same = isequaln(withoutUnrelated(first), withoutUnrelated(second));
end

function settings = withoutUnrelated(settings)
for name = ["display", "highOrder"]
    if isstruct(settings) && isfield(settings, name)
        settings = rmfield(settings, name);
    end
end
end
