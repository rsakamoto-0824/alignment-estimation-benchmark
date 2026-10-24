function distributionHistograms(ax, samples, names, edges, titleText, unit)
%DISTRIBUTIONHISTOGRAMS いくつかの値の集まりのヒストグラムを、共通の区間 edges の割合（合計 1）で重ねて描く。
%   unit（省略可）は横軸の単位（既定 "nm"）。
%   一番目は薄い塗り、ほかは太い線（階段）で描くので、重なっても形を比べられる。凡例に名前と点数を出す。
if nargin < 6
    unit = "nm";
end
COLORS = [0.55, 0.55, 0.55; 0.0, 0.36, 0.67; 0.85, 0.40, 0.05; 0.60, 0.10, 0.55];
cla(ax, 'reset');
hold(ax, 'on');
for k = 1:numel(samples)
    values = samples{k}(isfinite(samples{k}));
    label = sprintf("%s（%d 点）", names(k), numel(values));
    color = COLORS(1 + mod(k - 1, size(COLORS, 1)), :);
    if k == 1
        histogram(ax, values, edges, 'Normalization', 'probability', 'FaceColor', color, 'FaceAlpha', 0.35, ...
            'EdgeColor', 'none', 'DisplayName', label);
    else
        histogram(ax, values, edges, 'Normalization', 'probability', 'DisplayStyle', 'stairs', ...
            'EdgeColor', color, 'LineWidth', 2, 'DisplayName', label);
    end
end
hold(ax, 'off');
xlabel(ax, "値 [" + unit + "]");
ylabel(ax, '割合（区間ごと、合計 1）');
title(ax, titleText, 'Interpreter', 'none');
grid(ax, 'on');
box(ax, 'on');
legend(ax, 'Location', 'northeast', 'Box', 'off', 'FontSize', 10);
end
