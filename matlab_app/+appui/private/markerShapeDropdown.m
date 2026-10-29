function control = markerShapeDropdown(parent, callback)
% X・Y の色の図（ヒートマップ）の点の形
control = uidropdown(parent, 'Items', {'●', '■'}, 'ItemsData', {'o', 's'}, 'ValueChangedFcn', callback, ...
    'Tooltip', 'X・Y 成分の色の図（ヒートマップ）で、点を丸（●）で描くか四角（■）で描くか');
end
