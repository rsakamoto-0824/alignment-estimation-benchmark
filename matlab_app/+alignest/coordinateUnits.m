function [units, scale] = coordinateUnits(input)
%COORDINATEUNITS 入力座標の単位と mm への倍率。指定のない列は mm。
arguments
    input (1, 1) struct = struct()
end
names = ["Xmm", "Ymm", "markXmm", "markYmm", "Radius"];
supported = ["m", "mm", "um", "nm"];
toMm = [1e3, 1, 1e-3, 1e-6];
for name = names
    unit = "mm";
    if isfield(input, name)
        unit = string(input.(name));
    end
    unit = replace(strtrim(unit), ["µm", "μm"], "um");
    if ~isscalar(unit) || ismissing(unit) || ~any(unit == supported)
        error('alignest:coordinateUnit', '%s の入力単位は m・mm・um（µm）・nm から選んでください。', name);
    end
    units.(name) = unit;
    scale.(name) = toMm(supported == unit);
end
end
