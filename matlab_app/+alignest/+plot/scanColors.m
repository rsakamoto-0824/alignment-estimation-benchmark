function [colors, markers] = scanColors(style)
%SCANCOLORS Scan 方向 1・2 を示す色（行ごと）と印（▲・▼）。計測マップと Wafer マップの Shot の枠で共通に使う。
%   [colors, markers] = alignest.plot.scanColors()        % 既定（Scan 1 = 緑 ▲、Scan 2 = 紫 ▼）
%   [colors, markers] = alignest.plot.scanColors(style)   % 設定の色・向き（alignest.plot.scanStyle）
if nargin < 1
    style = alignest.plot.scanStyle();
end
colors = style.colors;
markers = style.markers;
end
