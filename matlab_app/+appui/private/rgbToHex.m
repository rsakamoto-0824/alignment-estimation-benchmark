function text = rgbToHex(rgb)
% RGB（0〜1）を「#RRGGBB」の文字にする
text = char("#" + strjoin(string(dec2hex(round(min(max(rgb, 0), 1) * 255), 2)).', ""));
end
