function text = numberText(value, format)
if nargin < 2
    format = '%.6g';
end
if isnan(value)
    text = '—';
else
    text = sprintf(format, value);
end
end
