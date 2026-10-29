function text = pValueText(p)
% p 値：小さい値は指数で出す
if isnan(p)
    text = '—';
elseif p < 1e-4
    text = sprintf('%.1e', p);
else
    text = sprintf('%.4f', p);
end
end
