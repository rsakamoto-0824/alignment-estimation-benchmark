function text = axisLabel(spec, axisNames)
% 表・図に出す軸の名前（1変数は値の名前）
text = string(axisNames);
if spec.scalar
    text(text == "X") = spec.name;
end
end
