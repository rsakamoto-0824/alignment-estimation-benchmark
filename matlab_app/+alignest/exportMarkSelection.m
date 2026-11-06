function exportMarkSelection(filePath, study, count)
%EXPORTMARKSELECTION 「8. Mark配置の最適化」で選んだ1つの配置（Mark の数 count）を Excel ファイル（.xlsx）に書き出す。
%   alignest.exportMarkSelection(filePath, study, count)
%   study：alignest.markLayoutStudy の結果。シート：「配置」（計測する Mark の番号・Shot 内の座標・必ず計測か）、「説明」
%   （Mark の数・I 効率・D 効率・補正の式と回帰）。
arguments
    filePath (1, 1) string
    study struct
    count (1, 1) double
end
[~, ~, extension] = fileparts(filePath);
if ~strcmpi(extension, ".xlsx")
    error('alignest:exportType', '書き出し先は .xlsx にしてください: %s', filePath);
end
k = find(study.counts == count, 1);
if isempty(k)
    error('alignest:markLayout', 'Mark の数 %d の配置はありません。', count);
end
if isfile(filePath)
    try
        delete(filePath);
    catch err
        error('alignest:exportLocked', '「%s」を置き換えられません（Excel で開いていないか確かめてください）。理由: %s', ...
            filePath, err.message);
    end
end
candidates = study.candidates(study.layouts.selected(:, k), :);
writetable(table(candidates.no, candidates.xMm, candidates.yMm, candidates.required, 'VariableNames', ...
    ["Markの番号", "X[mm]", "Y[mm]", "必ず計測"]), filePath, 'Sheet', '配置');
items = ["Mark の数"; "I 効率 [%]"; "D 効率 [%]"; "補正の式と回帰"];
values = [string(count); string(round(study.layouts.efficiency(k), 2)); string(round(study.layouts.dEfficiency(k), 2)); ...
    study.options.description];
writetable(table(items, values, 'VariableNames', ["項目", "内容"]), filePath, 'Sheet', '説明');
end
