function [settings, source] = siteDefaults(folders)
%SITEDEFAULTS アプリの初期設定：alignest.defaultSettings に、管理者が置いた「既定の設定ファイル」を重ねたもの。
%   [settings, source] = alignest.siteDefaults()          % 今のフォルダ（pwd）を探す
%   [settings, source] = alignest.siteDefaults(folders)   % 探すフォルダを指定する（先にあるものを使う）
%   既定の設定ファイルは DEFAULTS_FILE_NAME（JSON。「設定を保存…」と同じ形）。変えたい項目だけを書けばよく、
%   書いていない項目は alignest.defaultSettings の値になる（alignest.loadSettings）。exe を作り直さずに、
%   利用者全員の初期設定（画面を開いたときと「初期設定に戻す」の値）を変えるために使う。
%   exe はショートカットの「作業フォルダー」（ふつうは exe のフォルダ）が今のフォルダになる。
%   source は読んだファイル（無ければ ""）。読めないファイルはエラーにする（間違った初期設定で評価しないため）。
DEFAULTS_FILE_NAME = "alignment_estimation_defaults.json";
if nargin < 1
    folders = string(pwd);
end
settings = alignest.defaultSettings();
source = "";
for folder = reshape(string(folders), 1, [])
    candidate = fullfile(folder, DEFAULTS_FILE_NAME);
    if isfile(candidate)
        try
            settings = alignest.loadSettings(candidate);
        catch err
            error('alignest:siteDefaults', ['既定の設定ファイルを読めません: %s（%s）。ファイルを直すか、' ...
                '別の名前にしてから開き直してください。'], candidate, err.message);
        end
        source = string(candidate);
        return
    end
end
end
