function setGroupItems(dropdown, options)
% Wafer ごと・平均の選択肢を入れる（UserData に選択肢の中身を持つ）
dropdown.Items = cellstr([options.label]);
dropdown.ItemsData = 1:numel(options);
dropdown.UserData = options;
dropdown.Value = 1;
end
