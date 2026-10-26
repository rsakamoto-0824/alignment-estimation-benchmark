function same = sameRunSettings(first, second)
%SAMERUNSETTINGS 2つの評価の設定が、推定の結果について同じか（表示の設定 display は比べない）。
%   一時中断した評価を続きから再開できるかを確かめるときに使う（Scan 方向の色・向きを変えても再開できるように）。
same = isequaln(withoutDisplay(first), withoutDisplay(second));
end

function settings = withoutDisplay(settings)
if isstruct(settings) && isfield(settings, "display")
    settings = rmfield(settings, "display");
end
end
