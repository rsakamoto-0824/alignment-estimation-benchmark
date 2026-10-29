function setModeChoices(dropdown, spec)
% 図の表示（ベクトル・X・Y）の選択肢。1変数は色（値の名前）だけ
if spec.scalar
    setChoices(dropdown, spec.name + "（色）", {'X'});
elseif ~isequal(dropdown.ItemsData, {'vector', 'X', 'Y'})
    setChoices(dropdown, ["ベクトル（矢印）", "X（色）", "Y（色）"], {'vector', 'X', 'Y'});
end
end
