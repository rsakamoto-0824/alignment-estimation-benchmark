function sets = termSetTable(lines)
%TERMSETTABLE 保存した項の組み合わせ（"名前|式|k の番号 …"。settings.highOrder.termSets）を表にする（読めない行は使わない）。
%   name・maker・terms（使う k の番号の cell）・makerLabel・count（使う項の数）
lines = string(lines(:));
lines = lines(strlength(strtrim(lines)) > 0);
names = strings(0, 1);
makers = strings(0, 1);
terms = cell(0, 1);
for k = 1:numel(lines)
    parts = split(lines(k), "|");
    if numel(parts) ~= 3 || ~any(parts(2) == ["asml", "canon", "nikon", "custom"])
        continue
    end
    numbers = str2double(split(strtrim(parts(3))));
    if any(~isfinite(numbers))
        continue
    end
    names(end + 1, 1) = strtrim(parts(1)); %#ok<AGROW>
    makers(end + 1, 1) = parts(2); %#ok<AGROW>
    terms{end + 1, 1} = reshape(numbers, 1, []); %#ok<AGROW>
end
makerNames = ["asml", "canon", "nikon", "custom"];
makerLabels = ["ASML", "Canon", "Nikon", "カスタム"];
[~, position] = ismember(makers, makerNames);
labels = strings(size(makers));
labels(position > 0) = makerLabels(position(position > 0));
sets = struct("name", names, "maker", makers, "terms", {terms}, "makerLabel", labels, ...
    "count", cellfun(@numel, terms));
end
