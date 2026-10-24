function exportTargetEstimates(filePath, estimates, notes, spec)
%EXPORTTARGETESTIMATES 未知の座標での推定値を Excel ファイル（.xlsx）に書き出す。
%   alignest.exportTargetEstimates(filePath, estimates, notes, spec)
%   estimates：alignest.predictTargets の result.table に、Wafer の列（wafer）を足して縦に並べた表。
%   notes：「説明」シートに足す行（[項目, 内容] の2列の文字列）。
%   「推定値」シート：Wafer・名前・Xmm・Ymm・markXmm・markYmm・markNo・shotNo・Direction（読み込む表と同じ見出し
%   なので、このシートを alignest.readTargetPoints でそのまま読める）・Wafer 上の x・y・推定値 X・Y [nm]・外挿・
%   学習範囲の外 [mm]・最も近い学習点 [mm]・メモ。「説明」シート：作成日時・外挿の決め方・notes。
%   spec（alignest.valueSpec、省略可）が1変数なら、推定値は1列（「推定値 <値の名前>[<単位>]」）。
arguments
    filePath (1, 1) string
    estimates table
    notes (:, 2) string = strings(0, 2)
    spec struct = alignest.valueSpec(struct())
end
[~, ~, extension] = fileparts(filePath);
if ~strcmpi(extension, ".xlsx")
    error('alignest:exportType', '書き出し先は .xlsx にしてください: %s', filePath);
end
if height(estimates) == 0
    error('alignest:noTargets', '書き出す推定値がありません。先に「推定する」を押してください。');
end
if isfile(filePath)
    try
        delete(filePath);
    catch err
        error('alignest:exportLocked', '「%s」を置き換えられません（Excel で開いていないか確かめてください）。理由: %s', ...
            filePath, err.message);
    end
end
items = ["作成日時"; "点の数"; "推定値"; "外挿"; notes(:, 1)];
values = [string(datetime('now', 'Format', 'yyyy/MM/dd HH:mm:ss')); string(height(estimates)); ...
    "学習データ（計測値）から推定した値 [nm]。Wafer 上の座標は x = Xmm + markXmm、y = Ymm + markYmm [mm]。"; ...
    "学習点を囲む凸包の外にある点を「外挿」とする（凸包の外への距離が「学習範囲の外」）。学習点から離れるほど" + ...
    "推定値は信頼できない。学習に無い Mark 番号の点は、Mark 番号の効果を全 Mark の平均として推定する。"; notes(:, 2)];
writetable(table(items, values, 'VariableNames', ["項目", "内容"]), filePath, 'Sheet', '説明');
mark = strings(height(estimates), 1);
mark(estimates.extrapolated) = "外挿";
sheet = table(estimates.wafer, estimates.name, estimates.Xmm, estimates.Ymm, estimates.markXmm, estimates.markYmm, ...
    estimates.markNo, estimates.shotNo, estimates.direction, estimates.x, estimates.y, estimates.estimateX, ...
    estimates.estimateY, mark, estimates.outsideMm, estimates.nearestMm, estimates.note, 'VariableNames', ...
    ["Wafer", "名前", "Xmm", "Ymm", "markXmm", "markYmm", "markNo", "shotNo", "Direction", "x[mm]", "y[mm]", ...
    "推定値X[nm]", "推定値Y[nm]", "外挿", "学習範囲の外[mm]", "最も近い学習点[mm]", "メモ"]);
if spec.scalar
    sheet = removevars(sheet, "推定値Y[nm]");
    sheet.Properties.VariableNames{'推定値X[nm]'} = char("推定値 " + spec.name + "[" + spec.unit + "]");
end
writetable(sheet, filePath, 'Sheet', '推定値');
end
