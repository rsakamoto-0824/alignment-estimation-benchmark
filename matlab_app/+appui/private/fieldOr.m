function value = fieldOr(data, name, fallback)
% 以前の設定・データに無い項目は fallback
value = fallback;
if isfield(data, name)
    value = data.(name);
end
end
