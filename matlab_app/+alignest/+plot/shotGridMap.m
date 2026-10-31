function summary = shotGridMap(ax, centers, sizeMm, displacement, options)
%SHOTGRIDMAP Shot の形（補正量で変形させたグリッド）を描く（「7. Shot高次補正」のマップの「グリッド（Shot の形）」）。
%   summary = alignest.plot.shotGridMap(ax, centers, sizeMm, displacement, options)
%   centers：Shot 中心 [mm]（Shot の数 × 2）、sizeMm：Shot の大きさ [幅, 高さ] [mm]、
%   displacement：関数 @(local) [dx, dy]。Shot 内の位置 local [mm]（位置の数 × 2）での変位 [nm]（Shot の数 × 位置の数 の
%   dx・dy。alignest.highOrderModelAt）。
%   options.stack = false：Wafer 上の各 Shot の位置に、変形していない Shot の枠（灰色）と変形させたグリッドを描く。
%   options.stack = true：すべての Shot のグリッドを1つの Shot に重ね（薄い線）、平均のグリッドを濃い線で描く。
%   options.scaleMmPerNm：変位の倍率 [mm/nm]（0 なら、変位の大きさの 95% 点がグリッドの間隔の SHIFT_RATIO 倍になる）。
%   options.gridLines：グリッドの線の数（縦・横それぞれ）、options.titleText：題名、options.waferRadiusMm：Wafer の半径。
%   summary：描いた Shot の数 n、倍率 scaleMmPerNm、変位の大きさの最大 maxNm。
arguments
    ax
    centers double
    sizeMm (1, 2) double
    displacement function_handle
    options.stack (1, 1) logical = false
    options.scaleMmPerNm (1, 1) double {mustBeNonnegative} = 0
    options.gridLines (1, 1) double {mustBeInteger, mustBePositive} = 5
    options.titleText (1, 1) string = ""
    options.waferRadiusMm (1, 1) double = 150
end
SAMPLES = 15;                  % グリッドの線1本を描く点の数
SHIFT_RATIO = 0.4;             % 自動の倍率：変位の大きさの95%点がグリッドの間隔のこの割合
FRAME_COLOR = [0.65, 0.65, 0.65];
GRID_COLOR = [0.80, 0.25, 0.20];
EACH_COLOR = [0.42, 0.62, 0.85];
MEAN_COLOR = [0.05, 0.20, 0.45];
WAFER_COLOR = [0.3, 0.3, 0.3];
% グリッドの線（横の線と縦の線）。線ごとに SAMPLES 点、線の間は NaN で区切る
half = sizeMm / 2;
levelsX = linspace(-half(1), half(1), options.gridLines);
levelsY = linspace(-half(2), half(2), options.gridLines);
along = linspace(0, 1, SAMPLES).';
local = zeros(0, 2);
for k = 1:options.gridLines
    local = [local; -half(1) + 2 * half(1) * along, repmat(levelsY(k), SAMPLES, 1); NaN, NaN]; %#ok<AGROW>
    local = [local; repmat(levelsX(k), SAMPLES, 1), -half(2) + 2 * half(2) * along; NaN, NaN]; %#ok<AGROW>
end
inside = all(isfinite(local), 2);
[dx, dy] = deal(nan(size(centers, 1), size(local, 1)));
[dx(:, inside), dy(:, inside)] = displacement(local(inside, :));
drawn = all(isfinite(dx(:, inside)) & isfinite(dy(:, inside)), 2);
magnitude = hypot(dx(drawn, inside), dy(drawn, inside));
maxNm = max([magnitude(:); 0]);
scale = options.scaleMmPerNm;
if scale == 0
    typical = alignest.stats.percentile(magnitude(:), 95);
    spacing = min(sizeMm) / max(options.gridLines - 1, 1);
    scale = SHIFT_RATIO * spacing / max(typical, eps);
end
cla(ax, 'reset');
legend(ax, 'off');
hold(ax, 'on');
items = gobjects(1, 0);
if options.stack
    % 1つの Shot に重ねる：Shot ごとの薄い線と、平均の濃い線
    [px, py] = deal(zeros(0, 1));
    for s = reshape(find(drawn), 1, [])
        px = [px; local(:, 1) + scale * dx(s, :).'; NaN]; %#ok<AGROW>
        py = [py; local(:, 2) + scale * dy(s, :).'; NaN]; %#ok<AGROW>
    end
    plot(ax, local(:, 1), local(:, 2), '-', 'Color', FRAME_COLOR, 'LineWidth', 0.5, 'HandleVisibility', 'off');
    if ~isempty(px)
        items(end + 1) = plot(ax, px, py, '-', 'Color', [EACH_COLOR, 0.35], 'LineWidth', 0.5, ...
            'DisplayName', sprintf('Shot ごと（%d Shot）', nnz(drawn)));
        meanX = mean(dx(drawn, :), 1, 'omitnan');
        meanY = mean(dy(drawn, :), 1, 'omitnan');
        items(end + 1) = plot(ax, local(:, 1) + scale * meanX.', local(:, 2) + scale * meanY.', '-', 'Color', MEAN_COLOR, ...
            'LineWidth', 1.6, 'DisplayName', 'Shot の平均');
    end
    limits = 1.25 * max(half);
    axis(ax, 'equal');
    xlim(ax, [-limits, limits]);
    ylim(ax, [-limits, limits]);
    xlabel(ax, sprintf('Shot 内の X [mm]（変位 1 nm = %.3g mm）', scale));
    ylabel(ax, 'Shot 内の Y [mm]');
else
    % Wafer 上：Shot の枠（灰色）と、変形させたグリッド
    frame = [-half(1), -half(2); half(1), -half(2); half(1), half(2); -half(1), half(2); -half(1), -half(2); NaN, NaN];
    [fx, fy, gx, gy] = deal(zeros(0, 1));
    for s = 1:size(centers, 1)
        fx = [fx; centers(s, 1) + frame(:, 1)]; %#ok<AGROW>
        fy = [fy; centers(s, 2) + frame(:, 2)]; %#ok<AGROW>
        if drawn(s)
            gx = [gx; centers(s, 1) + local(:, 1) + scale * dx(s, :).'; NaN]; %#ok<AGROW>
            gy = [gy; centers(s, 2) + local(:, 2) + scale * dy(s, :).'; NaN]; %#ok<AGROW>
        end
    end
    plot(ax, fx, fy, '-', 'Color', FRAME_COLOR, 'LineWidth', 0.5, 'HandleVisibility', 'off');
    if ~isempty(gx)
        items(end + 1) = plot(ax, gx, gy, '-', 'Color', GRID_COLOR, 'LineWidth', 0.8, ...
            'DisplayName', sprintf('変形させたグリッド（%d Shot）', nnz(drawn)));
    end
    angle = linspace(0, 2 * pi, 361);
    plot(ax, options.waferRadiusMm * cos(angle), options.waferRadiusMm * sin(angle), '-', 'Color', WAFER_COLOR, ...
        'HandleVisibility', 'off');
    limits = 1.05 * options.waferRadiusMm;
    axis(ax, 'equal');
    xlim(ax, [-limits, limits]);
    ylim(ax, [-limits, limits]);
    xlabel(ax, sprintf('X [mm]（変位 1 nm = %.3g mm）', scale));
    ylabel(ax, 'Y [mm]');
end
hold(ax, 'off');
box(ax, 'on');
grid(ax, 'on');
if options.titleText ~= ""
    title(ax, options.titleText, 'Interpreter', 'none');
end
if ~isempty(items)
    legend(ax, items, 'Location', 'southoutside', 'Box', 'off', 'FontSize', 9);
end
summary = struct("n", nnz(drawn), "scaleMmPerNm", scale, "maxNm", maxNm);
end
