function range = valueRange(values)
% 1変数の値を色で描く範囲 [最小, 最大]（値が無ければ NaN：0 を中心にした色の範囲になる）
values = values(isfinite(values));
range = [NaN, NaN];
if ~isempty(values)
    range = [min(values), max(values)];
end
end
