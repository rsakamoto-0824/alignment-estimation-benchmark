function timingBars(axSeconds, axShare, breakdown)
%TIMINGBARS 処理時間の内訳（alignest.timingBreakdown）を、手法ごとの積み上げ横棒で描く。
%   左（axSeconds）は秒数、右（axShare）は合計を 100% にした割合。割合が SHARE_LABEL_MIN [%] 以上の段階には数字を書く。
%   色だけで区別しないよう、凡例に段階の名前を書き、割合の数字も添える。
STAGE_COLORS = [0.90, 0.55, 0.20; 0.80, 0.25, 0.25; 0.65, 0.65, 0.65; 0.12, 0.42, 0.72; 0.20, 0.65, 0.60; ...
    0.55, 0.40, 0.75; 0.80, 0.70, 0.20];
SHARE_LABEL_MIN = 6;
values = breakdown.table{:, cellstr(breakdown.stages)};
nMethods = size(values, 1);
share = 100 * values ./ max(sum(values, 2), eps);
% 手法が1つでも積み上げにするため、空の行を足して描き、縦軸は1本目だけを見せる
positions = 1:max(nMethods, 2);
padded = @(matrix) [matrix; nan(max(2 - nMethods, 0), size(matrix, 2))];
labels = breakdown.table.methodLabel;
axesList = [axSeconds, axShare];
data = {values, share};
for a = 1:2
    ax = axesList(a);
    cla(ax, 'reset');
    legend(ax, 'off');
    bars = barh(ax, positions, padded(data{a}), 'stacked', 'EdgeColor', 'none');
    for k = 1:numel(bars)
        bars(k).FaceColor = STAGE_COLORS(k, :);
        bars(k).DisplayName = breakdown.labels(k);
    end
    ax.YTick = 1:nMethods;
    ax.YTickLabel = cellstr(labels);
    ax.TickLabelInterpreter = 'none';
    ax.YDir = 'reverse';
    ylim(ax, [0.5, nMethods + 0.5]);
    grid(ax, 'on');
    box(ax, 'on');
end
xlabel(axSeconds, '1 条件あたりの時間 [秒]');
title(axSeconds, sprintf('処理時間（%d 回の中央値）', breakdown.nRepeats));
xlabel(axShare, '割合 [%]');
xlim(axShare, [0, 100]);
title(axShare, '段階ごとの割合');
axShare.YTickLabel = {};
hold(axShare, 'on');
for m = 1:nMethods
    left = 0;
    for k = 1:size(share, 2)
        if share(m, k) >= SHARE_LABEL_MIN
            % 明るい色の上は黒、暗い色の上は白の文字にする（読みやすさ）
            light = STAGE_COLORS(k, :) * [0.299; 0.587; 0.114] > 0.55;
            text(axShare, left + share(m, k) / 2, m, sprintf('%.0f%%', share(m, k)), 'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', 'FontSize', 10, 'Color', [1, 1, 1] * ~light, 'FontWeight', 'bold');
        end
        left = left + share(m, k);
    end
end
hold(axShare, 'off');
legend(axShare, 'Location', 'eastoutside', 'Box', 'off', 'FontSize', 10);
end
