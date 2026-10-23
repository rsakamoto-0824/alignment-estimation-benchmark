function [colors, markers] = scanColors()
%SCANCOLORS Scan 方向 1・2 を示す色（行ごと）と印（▲・▼）。計測マップと Wafer マップの Shot の枠で共通に使う。
%   矢印の色（長さ）・X・Y の色（青〜赤）・計測マップの塗り（橙・青・白・灰）と区別できる緑と紫にする。
colors = [0.10, 0.58, 0.28; 0.58, 0.20, 0.70];
markers = ['^', 'v'];
end
