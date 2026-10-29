function setChoices(dropdown, items, itemsData)
% ドロップダウンの選択肢を変える（前に選んでいた値が残っていれば、そのまま選ぶ）
previous = dropdown.Value;
dropdown.Items = cellstr(items);
dropdown.ItemsData = itemsData;
if any(cellfun(@(value) isequal(value, previous), itemsData))
    dropdown.Value = previous;
end
end
