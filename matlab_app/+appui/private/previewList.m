function text = previewList(values, maxCount)
% 並びを「10, 15, 20」のように出す。多いときは途中を「…」で省く
values = string(values);
if numel(values) > maxCount
    values = [values(1:maxCount - 1), "…", values(end)];
end
text = strjoin(values, ", ");
end
