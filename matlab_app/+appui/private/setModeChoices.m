function setModeChoices(dropdown, spec, withVariance)
% 図の表示（ベクトル・X・Y）の選択肢。1変数は色（値の名前）だけ。withVariance（省略可）が true なら、GPR の推定の分散を
% 色で描く選択肢（varianceX・varianceY。1変数は varianceX）も足す（「6. 未知の座標の推定」）
if nargin < 3
    withVariance = false;
end
if spec.scalar
    items = spec.name + "（色）";
    data = {'X'};
    if withVariance
        items = [items, "分散（色・GPR）"];
        data = [data, {'varianceX'}];
    end
else
    items = ["ベクトル（矢印）", "X（色）", "Y（色）"];
    data = {'vector', 'X', 'Y'};
    if withVariance
        items = [items, "X の分散（色・GPR）", "Y の分散（色・GPR）"];
        data = [data, {'varianceX', 'varianceY'}];
    end
end
if spec.scalar || ~isequal(dropdown.ItemsData, data)   % 1変数は値の名前が変わることがあるので、いつも作り直す
    setChoices(dropdown, items, data);
end
end
