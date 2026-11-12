function summary = waferOverlayMap(ax, layers, options)
%WAFEROVERLAYMAP 複数の Wafer の値（ベクトル）を、Wafer ごとに色を変えて1つの図に重ねて描く（「7. Shot高次補正」のマップ）。
%   summary = alignest.plot.waferOverlayMap(ax, layers, scaleMmPerNm=..., stack=false, waferRadiusMm=150, shotSizeMm=[26 33], ...
%       titleText="", valueLabel="")
%   layers：Wafer ごとの構造体の配列（label：Wafer の名前、positions：点の位置 [mm]（点の数 × 2）、values：点の値 [nm]（点の数 × 2））。
%   stack = false：Wafer 上の位置（positions は Wafer 上の座標）に点ごとの矢印。Wafer の外周（waferRadiusMm）の円を描く。
%   stack = true ：Shot を重ねた図（positions は Shot 内の座標）。Wafer ごとに、同じ Shot 内の位置（0.001 mm で丸める）の値を
%   平均した矢印を描き、Shot の枠（shotSizeMm：幅・高さ）を描く。
%   矢印は値 × scaleMmPerNm [mm/nm] の長さ（すべての Wafer で同じ倍率）。色は Wafer ごと（MATLAB の線の既定の色の順）。
%   summary：Wafer ごとの表（label・n（描いた点の数）・meanPlus3SigmaX・meanPlus3SigmaY [nm]。値は点ごとの値で求める）
arguments
    ax
    layers struct
    options.scaleMmPerNm (1, 1) double {mustBePositive} = 1
    options.stack (1, 1) logical = false
    options.waferRadiusMm (1, 1) double {mustBePositive} = 150
    options.shotSizeMm (1, 2) double = [NaN, NaN]
    options.titleText (1, 1) string = ""
    options.valueLabel (1, 1) string = ""
end
POSITION_DIGITS = 3;          % Shot を重ねる図で、同じ位置とみなす桁（0.001 mm）
WAFER_EDGE_COLOR = [0.55, 0.55, 0.55];
cla(ax, 'reset');
hold(ax, 'on');
colors = lines(max(numel(layers), 1));
n = numel(layers);
[counts, sigmaX, sigmaY] = deal(zeros(n, 1));
for k = 1:n
    positions = layers(k).positions;
    values = layers(k).values;
    usable = all(isfinite(values), 2) & all(isfinite(positions), 2);
    counts(k) = nnz(usable);
    sigmaX(k) = meanPlus3Sigma(values(usable, 1));
    sigmaY(k) = meanPlus3Sigma(values(usable, 2));
    positions = positions(usable, :);
    values = values(usable, :);
    if options.stack && ~isempty(positions)
        % Shot を重ねる：同じ Shot 内の位置の値を平均する
        [positions, ~, index] = unique(round(positions, POSITION_DIGITS), 'rows');
        values = [accumarray(index, values(:, 1), [], @mean), accumarray(index, values(:, 2), [], @mean)];
    end
    if isempty(positions)
        plot(ax, NaN, NaN, '-', 'Color', colors(k, :), 'DisplayName', layers(k).label);   % 凡例だけ
        continue
    end
    quiver(ax, positions(:, 1), positions(:, 2), values(:, 1) * options.scaleMmPerNm, ...
        values(:, 2) * options.scaleMmPerNm, 0, 'Color', colors(k, :), 'LineWidth', 1.1, 'MaxHeadSize', 0.4, ...
        'DisplayName', layers(k).label);
end
if options.stack
    if all(isfinite(options.shotSizeMm))
        half = options.shotSizeMm / 2;
        plot(ax, [-half(1), half(1), half(1), -half(1), -half(1)], [-half(2), -half(2), half(2), half(2), -half(2)], ...
            '-', 'Color', WAFER_EDGE_COLOR, 'HandleVisibility', 'off');
    end
    xlabel(ax, sprintf('Shot 内の X [mm]（矢印 1 nm = %.3g mm）', options.scaleMmPerNm));
    ylabel(ax, 'Shot 内の Y [mm]');
else
    angle = linspace(0, 2 * pi, 361);
    plot(ax, options.waferRadiusMm * cos(angle), options.waferRadiusMm * sin(angle), ':', 'Color', WAFER_EDGE_COLOR, ...
        'HandleVisibility', 'off');
    xlabel(ax, sprintf('X [mm]（矢印 1 nm = %.3g mm）', options.scaleMmPerNm));
    ylabel(ax, 'Y [mm]');
end
hold(ax, 'off');
axis(ax, 'equal');
grid(ax, 'on');
box(ax, 'on');
titleText = strjoin([options.titleText, options.valueLabel], "｜");
if options.titleText == "" || options.valueLabel == ""
    titleText = options.titleText + options.valueLabel;
end
title(ax, titleText, 'Interpreter', 'none');
legend(ax, 'Location', 'northeastoutside', 'Interpreter', 'none');
summary = table(reshape(string({layers.label}), [], 1), counts, sigmaX, sigmaY, 'VariableNames', ...
    ["label", "n", "meanPlus3SigmaX", "meanPlus3SigmaY"]);
end

function value = meanPlus3Sigma(values)
% |平均| + 3σ（点が2点未満なら NaN）
value = NaN;
if numel(values) >= 2
    value = abs(mean(values)) + 3 * std(values);
end
end
