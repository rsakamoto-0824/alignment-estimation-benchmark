function saveSettings(settings, filePath)
%SAVESETTINGS 設定を JSON ファイル（UTF-8）に保存する。
text = jsonencode(settings, 'PrettyPrint', true);
fileId = fopen(filePath, 'w', 'n', 'UTF-8');
if fileId < 0
    error('alignest:saveSettings', '設定ファイルを書き込めません: %s（保存先のフォルダと書き込み権限を確かめてください）', filePath);
end
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, '%s', text);
end
