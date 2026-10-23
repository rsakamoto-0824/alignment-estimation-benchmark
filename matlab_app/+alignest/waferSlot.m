function [slot, parity] = waferSlot(names)
%WAFERSLOT Wafer ID のハイフンの後の整数（Slot 番号）と、その偶奇。
%   [slot, parity] = alignest.waferSlot(waferIds)
%   例："LOT123-05" → Slot 5・"奇数"、"A1B2-12" → 12・"偶数"。最後のハイフンの後の先頭の数字を読む
%   （画面の表示名「LOT123-05 (EXP01)」のように後ろに付けた「 (…)」は除いてから読む）。
%   ハイフンが無い・数字で始まらないときは slot = NaN、parity = ""。
%   Slot 番号はロットの中のスロットの位置（01〜25）で、偶数・奇数で傾向が違うかを見るために使う。
names = string(names);
slot = nan(size(names));
for k = 1:numel(names)
    name = regexprep(names(k), "\s*\(.*\)\s*$", "");
    if ~contains(name, "-")
        continue
    end
    parts = split(name, "-");
    digits = regexp(strtrim(parts(end)), "^\d+", 'match', 'once');
    if ~isempty(digits) && strlength(digits) > 0
        slot(k) = str2double(digits);
    end
end
parity = repmat("", size(names));
parity(isfinite(slot) & mod(slot, 2) == 1) = "奇数";
parity(isfinite(slot) & mod(slot, 2) == 0) = "偶数";
end
