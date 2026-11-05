function setListChoices(listbox, items, itemsData)
% 複数選べる一覧の選択肢を変える（前に選んでいた値のうち残っているものは選んだまま。無ければ最初の1つを選ぶ）
previous = listbox.Value;
listbox.Items = cellstr(items);
listbox.ItemsData = itemsData;
kept = previous(cellfun(@(value) any(cellfun(@(item) isequal(item, value), itemsData)), previous));
if isempty(kept)
    kept = itemsData(1);
end
listbox.Value = kept;
end
