function settings = loadSettings(filePath)
%LOADSETTINGS JSON ファイルの設定を読み、初期設定に重ねる（ファイルに無い項目は初期値のまま）。
%   型は初期設定に合わせる（文字列の並び・数値の行ベクトルなど）。知らない項目は無視する。
%   学習 Shot 数の開始・終了・刻みが無い以前の設定ファイルは、Shot 数の並びから決める（alignest.syncShotCounts）。
if ~isfile(filePath)
    error('alignest:loadSettings', '設定ファイルが見つかりません: %s', filePath);
end
try
    fileId = fopen(filePath, 'r', 'n', 'UTF-8');
    text = fread(fileId, '*char').';
    fclose(fileId);
    decoded = jsondecode(text);
catch err
    error('alignest:loadSettings', '設定ファイルを JSON として読めません: %s（%s）', filePath, err.message);
end
settings = merge(alignest.defaultSettings(), decoded);
settings.sampling = alignest.syncShotCounts(settings.sampling);
settings.methods = alignest.completeMethodSettings(settings.methods);
end

function merged = merge(defaults, decoded)
merged = defaults;
if ~isstruct(decoded)
    return
end
for name = string(fieldnames(defaults)).'
    if ~isfield(decoded, name)
        continue
    end
    value = decoded.(name);
    template = defaults.(name);
    if isstruct(template)
        merged.(name) = merge(template, value);
    elseif isstring(template)
        merged.(name) = orient(string(value), template);
    elseif islogical(template)
        merged.(name) = logical(value);
    elseif isnumeric(template)
        merged.(name) = orient(double(value), template);
    end
end
end

function value = orient(value, template)
% 初期設定と同じ向き（行または列）にそろえる
if size(template, 1) == 1
    value = reshape(value, 1, []);
else
    value = reshape(value, [], 1);
end
end
