function style = scanStyle(display)
%SCANSTYLE Scan 方向 1・2 の色・印（▲ 上向き・▼ 下向き）・凡例の名前（設定の settings.display から）。
%   style = alignest.plot.scanStyle(settings.display)
%   style = alignest.plot.scanStyle()   % 既定（Scan 1 = 緑 ▲ 上、Scan 2 = 紫 ▼ 下）
%   display.scan1Up：true なら Scan 方向 1 が上向き（▲）・2 が下向き（▼）、false なら逆。
%   display.scan1Color・scan2Color：Scan 方向 1・2 の色（RGB、0〜1）。
%   style.colors（2 × 3）・markers（'^'・'v' の並び）・symbols（"▲"・"▼"）・words（"上"・"下"）・
%   names（凡例の名前。例："Scan 1（▲ 上）"）。計測マップ・Wafer マップの枠と Shot の配置・Shot スタックマップで使う。
%   既定の色は、矢印の色（長さ）・X・Y の色（青〜赤）・計測マップの塗り（橙・青・白・灰）と区別できる緑と紫。
DEFAULT_COLORS = [0.10, 0.58, 0.28; 0.58, 0.20, 0.70];
if nargin < 1 || ~isstruct(display)
    display = struct();
end
colors = DEFAULT_COLORS;
names = ["scan1Color", "scan2Color"];
for k = 1:2
    if isfield(display, names(k))
        value = double(display.(names(k)));
        if numel(value) ~= 3 || any(~isfinite(value) | value < 0 | value > 1)
            error('alignest:scanColor', 'Scan 方向 %d の色は 0〜1 の RGB の3つの値にしてください。', k);
        end
        colors(k, :) = reshape(value, 1, 3);
    end
end
up = ~isfield(display, "scan1Up") || logical(display.scan1Up);
order = [1, 2];
if ~up
    order = [2, 1];   % Scan 方向 1 が下向き
end
markers = ['^', 'v'];
symbols = ["▲", "▼"];
words = ["上", "下"];
style.colors = colors;
style.markers = markers(order);
style.symbols = symbols(order);
style.words = words(order);
style.names = "Scan " + (1:2) + "（" + style.symbols + " " + style.words + "）";
style.scan1Up = up;
end
