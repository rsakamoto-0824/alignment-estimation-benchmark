function lines = mergeTermSets(preferred, others)
%MERGETERMSETS 保存した項の組み合わせ（1行 = "名前|式|k の番号 …"。settings.highOrder.termSets）を合わせる。
%   同じ名前の組み合わせは preferred の行を使い、others からは preferred に無い名前の行だけを足す。
preferred = reshape(string(preferred), [], 1);
others = reshape(string(others), [], 1);
lines = [preferred; others(~ismember(termSetNames(others), termSetNames(preferred)))];
end

function names = termSetNames(lines)
names = strtrim(extractBefore(lines + "|", "|"));   % 「|」の無い行は行全体を名前とみなす
end
