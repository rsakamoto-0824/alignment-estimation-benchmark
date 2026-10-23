function settings = loadSettings(filePath, source)
%LOADSETTINGS JSON ファイルの設定を読み、初期設定に重ねる（ファイルに無い項目は初期値のまま）。
%   settings = alignest.loadSettings(text, "text") は JSON の文字列から読む（評価結果の Excel の「設定」シートなど）。
%   型は初期設定に合わせる（文字列の並び・数値の行ベクトルなど）。知らない項目は無視する。
%   学習 Shot 数の開始・終了・刻みが無い以前の設定ファイルは、Shot 数の並びから決める（alignest.syncShotCounts）。
%   同心円の区切り・外周の半径を Wafer 半径に対する比で書いた以前の設定は、mm の値に直す（alignest.upgradeRadiusSettings）。
%   変えたい項目だけを書いたファイル（既定の設定ファイルなど）で、学習 Shot 数の開始・終了・刻みだけがあり並び nShots が
%   無いときは、開始・終了・刻みから並びを作る（書いた値が使われるように）。
if nargin >= 2 && source == "text"
    try
        decoded = jsondecode(char(filePath));
    catch err
        error('alignest:loadSettings', '設定を JSON として読めません（%s）', err.message);
    end
    settings = merge(alignest.defaultSettings(), alignest.upgradeRadiusSettings(decoded));
    if isstruct(decoded) && isfield(decoded, "sampling") && isstruct(decoded.sampling) && ...
            ~isfield(decoded.sampling, "nShots") && any(isfield(decoded.sampling, ["nShotsStart", "nShotsEnd", "nShotsStep"]))
        sampling = settings.sampling;
        sampling.nShots = alignest.shotCountList(sampling.nShotsStart, sampling.nShotsEnd, sampling.nShotsStep);
        settings.sampling = sampling;
    end
    settings.sampling = alignest.syncShotCounts(settings.sampling);
    settings.methods = alignest.completeMethodSettings(settings.methods);
    return
end
if ~isfile(filePath)
    error('alignest:loadSettings', '設定ファイルが見つかりません: %s', filePath);
end
try
    fileId = fopen(filePath, 'r', 'n', 'UTF-8');
    text = fread(fileId, '*char').';
    fclose(fileId);
catch err
    error('alignest:loadSettings', '設定ファイルを読めません: %s（%s）', filePath, err.message);
end
settings = alignest.loadSettings(string(text), "text");
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
