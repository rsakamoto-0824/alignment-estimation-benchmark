function text = normalizeNumberText(text)
%NORMALIZENUMBERTEXT 数字を入れる欄の全角の文字（数字・空白・カンマ・小数点・マイナス）を半角にする。
%   text = alignest.normalizeNumberText(text)   % 例："０．７５　２" → "0.75 2"
%   日本語入力のまま数字や空白を打っても読めるようにする（設定の欄・手動の指定）。
text = string(text);
fullWidth = ["０", "１", "２", "３", "４", "５", "６", "７", "８", "９", "　", "，", "．", "－", "−", "＋"];
halfWidth = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", " ", ",", ".", "-", "-", "+"];
text = replace(text, fullWidth, halfWidth);
end
