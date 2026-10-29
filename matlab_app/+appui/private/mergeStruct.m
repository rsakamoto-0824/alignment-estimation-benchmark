function merged = mergeStruct(base, extra)
merged = base;
for name = string(fieldnames(extra)).'
    merged.(name) = extra.(name);
end
end
