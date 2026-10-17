function colors = divergingColormap(nColors)
%DIVERGINGCOLORMAP 負が青・0が白・正が赤の色の並び（値の符号を色で見分ける。値そのものは色の棒で読む）。
if nargin < 1
    nColors = 255;
end
NEGATIVE = [0.17, 0.40, 0.73];
ZERO = [1, 1, 1];
POSITIVE = [0.80, 0.22, 0.17];
half = (nColors + 1) / 2;
t = ((1:nColors).' - half) / (half - 1);
colors = zeros(nColors, 3);
negative = t < 0;
colors(negative, :) = ZERO + (-t(negative)) .* (NEGATIVE - ZERO);
colors(~negative, :) = ZERO + t(~negative) .* (POSITIVE - ZERO);
end
