function waferMap(ax, points, values, options)
%WAFERMAP Wafer 上の値をベクトル（矢印）または色で描く。
%   points : 点の座標 [x, y]（mm、点数 × 2）
%   values : 値 [X, Y]（nm、点数 × 2。片方の軸が無効な点は NaN）
%   options.mode         : "vector"（矢印）・"X"・"Y"（色）
%   options.scaleMmPerNm : 矢印の長さ [mm/nm]。矢印の色は長さ |v| [nm]（alignest.plot.magnitudeArrows）。
%                          共分散楕円も描くときは、矢印を options.arrowColor の単色にする（色の目盛りは楕円の |r|）
%   options.magnitudeLimit : 矢印の色の範囲の上限 [nm]（0 なら描く矢印の最大。並べる図をそろえるときに渡す）
%   options.colorLimit   : 色の範囲 ±[nm]
%   options.markerShape  : 色で描くときの点の形（"o" = ●、"s" = ■）
%   options.trainPoints  : 学習に使った Mark の座標（四角で描く）
%   options.outlierPoints: 学習データから除いた異常値の Mark の座標（× で描く）
%   options.titleText    : 図の題名
%   options.showLegend   : 凡例を出すか（既定 true）
%   options.markerSize   : 色で描くときの点の大きさ（scatter の面積 [ポイント²]、既定 30）
%   options.shotCenters  : Shot 中心の座標 [x, y]（mm、Shot 数 × 2）。空なら Shot の枠を描かない
%   options.shotSizeMm   : Shot の大きさ [幅, 高さ]（mm）
%   options.shotDirections: Shot ごとの Scan 方向（1・2、無ければ NaN。shotCenters と同じ数）。渡すと Shot の枠を
%                          Scan 方向の色（と ▲・▼ の印）で描く（alignest.plot.scanFrames）。空なら灰色の枠
%   options.ringRadiiMm  : 同心円の制約の区切りの半径 [mm]（alignest.zoneEdgesMm）。破線の円で描く（空なら描かない）
%   options.covariance   : 点ごとの Wafer 間の共分散 [X の分散, Y の分散, X・Y の共分散]（nm²、点数 × 3）
%   options.showArrows   : 矢印（ベクトル）を描くか（既定 true）。false なら楕円だけ（楕円の中心は矢印の先のまま）
%   options.ellipseSigma : 共分散楕円の大きさ（σ の何倍か。0 なら描かない）。矢印の先を中心に、矢印と同じ倍率で描く。
%                          楕円の色は X・Y の相関係数の絶対値（alignest.plot.covarianceEllipses。MATLAB の既定の色）
%   色だけで意味を伝えないよう、学習 Mark は形（四角）と凡例の文字でも示す。
arguments
    ax
    points double
    values double
    options.mode (1, 1) string = "vector"
    options.scaleMmPerNm (1, 1) double = 1
    options.colorLimit (1, 1) double = 5
    options.trainPoints double = zeros(0, 2)
    options.outlierPoints double = zeros(0, 2)
    options.titleText (1, 1) string = ""
    options.waferRadiusMm (1, 1) double = 150
    options.magnitudeLimit (1, 1) double {mustBeNonnegative} = 0
    options.arrowColor (1, 3) double = [0.0, 0.33, 0.62]   % 楕円も描くときの矢印の色
    options.markerShape (1, 1) string {mustBeMember(options.markerShape, ["o", "s"])} = "o"
    options.showLegend (1, 1) logical = true
    options.markerSize (1, 1) double {mustBePositive} = 30
    options.shotCenters double = zeros(0, 2)
    options.shotSizeMm (1, 2) double = [NaN, NaN]
    options.shotDirections double = zeros(0, 1)
    options.ringRadiiMm double = zeros(1, 0)
    options.covariance double = zeros(0, 3)
    options.ellipseSigma (1, 1) double {mustBeNonnegative} = 0
    options.showArrows (1, 1) logical = true
end
WAFER_EDGE_COLOR = [0.45, 0.45, 0.45];
TRAIN_FACE_COLOR = [0.80, 0.80, 0.80];
TRAIN_EDGE_COLOR = [0.25, 0.25, 0.25];
OUTLIER_COLOR = [0.80, 0.0, 0.0];
MARGIN_MM = 8;
MAX_LEGEND_COLUMNS = 2;   % 凡例を横に並べる数（多いと図の幅を超えるので折り返す）
LEGEND_FONT_SIZE = 9;
SCAN_FRAME_INSET = 0.08;  % Scan 方向の色の枠を Shot の内側に少し縮める（隣の Shot の枠と重ならないように）
cla(ax, 'reset');
colorbar(ax, 'off');
hold(ax, 'on');
angle = linspace(0, 2 * pi, 361);
plot(ax, options.waferRadiusMm * cos(angle), options.waferRadiusMm * sin(angle), '--', ...
    'Color', WAFER_EDGE_COLOR, 'HandleVisibility', 'off');
legendItems = gobjects(0);
if ~isempty(options.shotDirections) && numel(options.shotDirections) == size(options.shotCenters, 1)
    legendItems = alignest.plot.scanFrames(ax, options.shotCenters, options.shotSizeMm, options.shotDirections, ...
        SCAN_FRAME_INSET);
else
    alignest.plot.shotFrames(ax, options.shotCenters, options.shotSizeMm);
end
rings = alignest.plot.zoneRings(ax, options.ringRadiiMm);
if ~isempty(rings)
    legendItems(end + 1) = rings;
end
if ~isempty(options.trainPoints)
    legendItems(end + 1) = plot(ax, options.trainPoints(:, 1), options.trainPoints(:, 2), 's', 'MarkerSize', 6, ...
        'MarkerFaceColor', TRAIN_FACE_COLOR, 'MarkerEdgeColor', TRAIN_EDGE_COLOR, 'LineStyle', 'none', ...
        'DisplayName', '学習に使った Mark');
end
if ~isempty(options.outlierPoints)
    legendItems(end + 1) = plot(ax, options.outlierPoints(:, 1), options.outlierPoints(:, 2), 'x', 'MarkerSize', 9, ...
        'LineWidth', 1.8, 'Color', OUTLIER_COLOR, 'LineStyle', 'none', 'DisplayName', '学習から除いた異常値');
end
if options.mode == "vector"
    usable = all(isfinite(values), 2);
    withEllipses = options.ellipseSigma > 0 && size(options.covariance, 1) == size(points, 1);
    arrows = gobjects(0);
    if options.showArrows && withEllipses
        % 楕円と重ねるときは矢印を単色にする（色の目盛りは楕円の |r| に使う）
        arrows = quiver(ax, points(usable, 1), points(usable, 2), values(usable, 1) * options.scaleMmPerNm, ...
            values(usable, 2) * options.scaleMmPerNm, 0, 'Color', options.arrowColor, 'LineWidth', 1, 'MaxHeadSize', 0.4);
    elseif options.showArrows
        arrows = alignest.plot.magnitudeArrows(ax, points(usable, :), values(usable, :), options.scaleMmPerNm, ...
            magnitudeLimit=options.magnitudeLimit);
    end
    if ~isempty(arrows)
        arrows.DisplayName = '値（矢印）';
        legendItems(end + 1) = arrows;
    end
    if withEllipses
        tips = points(usable, :) + values(usable, :) * options.scaleMmPerNm;
        handle = alignest.plot.covarianceEllipses(ax, tips, options.covariance(usable, :), ...
            options.ellipseSigma * options.scaleMmPerNm);
        if ~isempty(handle)
            handle.DisplayName = sprintf('Wafer 間のばらつき（%gσ 楕円）', options.ellipseSigma);
            legendItems(end + 1) = handle;
        end
    end
    drawScaleBar(ax, options.scaleMmPerNm, options.waferRadiusMm);
else
    column = 1 + (options.mode == "Y");
    usable = isfinite(values(:, column));
    scatter(ax, points(usable, 1), points(usable, 2), options.markerSize, values(usable, column), 'filled', ...
        'Marker', options.markerShape, 'HandleVisibility', 'off');
    colormap(ax, alignest.plot.divergingColormap());
    caxis(ax, [-1, 1] * max(options.colorLimit, eps));
    bar = colorbar(ax);
    bar.Title.String = options.mode + " [nm]";
end
hold(ax, 'off');
axis(ax, 'equal');
limit = options.waferRadiusMm + MARGIN_MM;
xlim(ax, [-limit, limit]);
ylim(ax, [-limit, limit]);
xlabel(ax, 'x [mm]');
ylabel(ax, 'y [mm]');
title(ax, options.titleText, 'Interpreter', 'none');
box(ax, 'on');
if options.showLegend && ~isempty(legendItems)
    legend(ax, legendItems, 'Location', 'southoutside', 'NumColumns', min(numel(legendItems), MAX_LEGEND_COLUMNS), ...
        'Box', 'off', 'FontSize', LEGEND_FONT_SIZE);
end
end

function drawScaleBar(ax, scaleMmPerNm, waferRadiusMm)
% 左下に矢印の長さの目安（きりのよい nm）を描く
TARGET_LENGTH_MM = 25;
raw = TARGET_LENGTH_MM / scaleMmPerNm;
exponent = floor(log10(raw));
candidates = [1, 2, 5, 10] * 10^exponent;
lengthNm = candidates(find(candidates <= raw, 1, 'last'));
if isempty(lengthNm)
    lengthNm = candidates(1);
end
x0 = -waferRadiusMm;
y0 = -waferRadiusMm + 2;
% 軸と同じ色（ダークモードでは明るい色。Tag = foreground は画面の色を変えたときに一緒に変える）
quiver(ax, x0, y0, lengthNm * scaleMmPerNm, 0, 0, 'Color', ax.XColor, 'Tag', 'foreground', 'LineWidth', 1.5, ...
    'MaxHeadSize', 0.6, 'HandleVisibility', 'off');
text(ax, x0, y0 + 8, sprintf('%g nm', lengthNm), 'FontSize', 12, 'VerticalAlignment', 'bottom');
end
